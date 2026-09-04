extends Node
## 飞行器AI控制器（固定翼 / 直升机通用）
## 行为：TAKEOFF(起飞爬升) -> SEEK(巡航搜索) -> ATTACK(接近目标并对准开火)
## 控制方式：直接写载具的 target_yaw / target_pitch(世界系瞄准，与鼠标引导同符号)，
##          直升机用 collective 管理高度、input_pitch 前进；固定翼用 input_throttle 管理油门。
##          开火统一走 vehicle.fire()（制导弹药由载具 _update_lock_on 自动搜索锁定）。

signal target_acquired(target: Node)
signal target_lost()

enum AIState {
	TAKEOFF,
	SEEK,
	ATTACK
}

@export var team: int = 2  # 1=友方, 2=敌方
@export var detection_range: float = 500.0
@export var attack_range: float = 500.0
@export var min_attack_range: float = 45.0
@export var cruise_altitude: float = 40.0
@export var fire_cooldown: float = 3.0
@export var accuracy: float = 0.7    # 0~1，越小越难命中（保留接口，供难度调节）
@export var aggression: float = 0.5  # 0~1
@export var reaction_min: float = 0.4
@export var reaction_max: float = 1.2

var vehicle: Node = null
var is_heli: bool = false
var current_state: AIState = AIState.TAKEOFF
var target: Node = null
var search_timer: float = 0.0
var fire_timer: float = 0.0
var reaction_timer: float = 0.0
var reset_point: Vector3 = Vector3.ZERO  # 固定翼拉起复位的盘旋点
var reset_timer: float = 0.0             # 复位阶段剩余时间

func _ready() -> void:
	vehicle = get_parent()
	if vehicle == null or not vehicle.has_method("fire"):
		push_error("[AircraftAI] Parent is not a Vehicle")
		return
	var vtype: String = vehicle.vehicle_data.get("type", "") if vehicle.vehicle_data else ""
	is_heli = vtype == "helicopter" or ("collective" in vehicle)
	vehicle.add_to_group("ai_vehicle")
	# 火力节奏跟随载具当前武器槽装填时间（导弹 30s 太长，AI 用 3s 节流即可，装填由 is_reloading 门控）
	if "reload_time" in vehicle and vehicle.reload_time > 0.0:
		fire_cooldown = min(3.0, vehicle.reload_time)
	reaction_timer = randf_range(reaction_min, reaction_max)
	print("[AircraftAI] Initialized for %s team %d (heli=%s)" % [vehicle.vehicle_id, team, is_heli])

func _physics_process(delta: float) -> void:
	if vehicle == null or vehicle.is_destroyed:
		return
	fire_timer -= delta
	reaction_timer -= delta
	search_timer -= delta
	# 目标搜索节流（0.3s 一次，300 米内才做射线检测）
	if search_timer <= 0.0:
		search_timer = 0.3
		_search_target()
	# 目标失效（被击毁等）直接放弃
	if target != null and (not is_instance_valid(target) or ("is_destroyed" in target and target.is_destroyed)):
		_lose_target()
	match current_state:
		AIState.TAKEOFF:
			_update_takeoff(delta)
		AIState.SEEK:
			_update_seek(delta)
		AIState.ATTACK:
			_update_attack(delta)

# ── 状态机 ──

func _update_takeoff(_delta: float) -> void:
	if is_heli:
		# 垂直起飞：总距爬升到巡航高度，保持水平姿态
		vehicle.collective = _height_collective()
		if vehicle.global_position.y >= cruise_altitude - 3.0:
			_set_state(AIState.SEEK, "升空完成")
	else:
		# 固定翼：全油门沿跑道直线起飞，拉起爬升到预定高度后转入攻击。
		# 注意：起飞段保持跑道航向（不预置"指向目标"，否则贴地直冲飞越目标头顶），
		# 但离地后需要明确爬升角，否则平飞爬升率过低、会低空横穿整个战场。
		vehicle.input_throttle = 1.0
		var fwd2: Vector3 = -vehicle.global_transform.basis.z
		fwd2.y = 0.0
		if fwd2.length() > 0.1:
			fwd2 = fwd2.normalized()
			vehicle.target_yaw = atan2(-fwd2.x, -fwd2.z)
			vehicle.target_pitch = 0.15  # ~8.6° 拉起爬升
		var on_floor: bool = _vehicle_on_floor()
		if not on_floor and vehicle.global_position.y > 12.0 and vehicle.velocity.y > 0.0:
			_set_state(AIState.SEEK, "离地爬升完成")

func _update_seek(_delta: float) -> void:
	# 搜索到目标立即转入攻击
	if target != null:
		_set_state(AIState.ATTACK, "发现目标 %s" % target.name)
		return
	if is_heli:
		# 悬停巡航：保持高度，不移动
		vehicle.collective = _height_collective()
		vehicle.input_pitch = 0.0
	else:
		# 平飞巡航：沿当前朝向直线飞，保持巡航高度（浅俯仰修正）
		vehicle.input_throttle = vehicle.throttle if "throttle" in vehicle else 0.0
		if "throttle" in vehicle and vehicle.throttle < 0.6:
			vehicle.input_throttle = 1.0
		var fwd_h: Vector3 = -vehicle.global_transform.basis.z
		fwd_h.y = 0.0
		if fwd_h.length() < 0.1:
			fwd_h = Vector3.FORWARD
		else:
			fwd_h = fwd_h.normalized()
		var cruise_point: Vector3 = vehicle.global_position + fwd_h * 300.0
		cruise_point.y = cruise_altitude
		_aim_at_point(cruise_point)

func _update_attack(_delta: float) -> void:
	if target == null:
		_set_state(AIState.SEEK, "目标丢失")
		return
	var tpos: Vector3 = target.global_position
	var to_target: Vector3 = tpos - vehicle.global_position
	var dist: float = to_target.length()
	var dir: Vector3 = to_target.normalized()
	# 优先切到副武器（导弹/制导弹），制导命中率更高；打空后 fire() 会自动换回机炮
	if vehicle.has_method("get_weapon_count") and vehicle.get_weapon_count() >= 2 \
			and vehicle.current_weapon_index != 1 and not vehicle.is_reloading:
		vehicle.switch_weapon(1)
	if is_heli:
		# 悬停攻击：保持高度（略低于目标头顶安全线），机头对准目标供导弹锁定
		vehicle.collective = _height_collective()
		vehicle.input_pitch = 0.3 if dist > attack_range * 0.7 else 0.0
		_aim_at(dir)
		_try_fire()
	else:
		# 固定翼：俯冲攻击 -> 过近/过低拉起复位，周而复始
		if reset_timer > 0.0:
			reset_timer -= _delta
			vehicle.input_throttle = 0.85
			_aim_at_point(reset_point)
			return
		vehicle.input_throttle = 1.0
		_aim_at(dir)
		_try_fire()
		var too_low: bool = vehicle.global_position.y < tpos.y + 10.0 or vehicle.global_position.y < 16.0
		if dist < min_attack_range or too_low:
			# 拉起：飞到目标正上方偏外侧的高空点
			var away: Vector3 = (vehicle.global_position - tpos)
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3.BACK
			away = away.normalized()
			reset_point = tpos + away * 60.0
			reset_point.y = max(tpos.y, cruise_altitude) + 60.0
			reset_timer = 3.5
			print("[AircraftAI] %s 拉起复位 -> %s" % [vehicle.vehicle_id, str(reset_point)])

func _try_fire() -> void:
	if target == null or fire_timer > 0.0 or reaction_timer > 0.0:
		return
	var to_target: Vector3 = target.global_position - vehicle.global_position
	var dist: float = to_target.length()
	if dist > attack_range or dist < min_attack_range:
		return
	# 机头(炮口)与目标夹角足够小才开火：制导弹药出膛后自寻的（锁定 FOV 8~10 度），
	# 粗对准即可发射（AGM-65/AGM-114 具备发射后锁定能力）；机炮直射仍由载具端判定。
	if _aim_error_deg() > 15.0:
		return
	if vehicle.can_fire == false or vehicle.is_reloading:
		return
	vehicle.fire()
	fire_timer = max(fire_cooldown, 0.4)
	reaction_timer = randf_range(reaction_min, reaction_max) * 0.5

# ── 工具 ──

func _set_state(state: AIState, why: String) -> void:
	current_state = state
	# 只在状态变化时打印，避免刷屏
	print("[AircraftAI] %s -> %s (%s)" % [vehicle.vehicle_id, str(state), why])

func _search_target() -> void:
	"""搜索敌方载具（3D距离 + 视线检测）。目标一旦确立就持续追猎，只有超距/失效才重新搜索"""
	# 当前目标仍有效（距离在探测范围的1.3倍内）→ 保持，不因短暂丢失而放弃
	if target != null and is_instance_valid(target) and not ("is_destroyed" in target and target.is_destroyed):
		var d: float = vehicle.global_position.distance_to(target.global_position)
		if d <= detection_range * 1.3:
			return
	var vehicles = get_tree().get_nodes_in_group("vehicle")
	var closest: Node = null
	var closest_d: float = detection_range
	for v in vehicles:
		if v == vehicle or v.is_destroyed:
			continue
		var v_team = v.get("team") if "team" in v else 1
		if v_team == team:
			continue
		var d: float = vehicle.global_position.distance_to(v.global_position)
		if d < closest_d and _has_line_of_sight(v.global_position):
			closest_d = d
			closest = v
	if closest != null and closest != target:
		target = closest
		target_acquired.emit(target)
		reaction_timer = randf_range(reaction_min, reaction_max)
	elif closest == null and target != null:
		_lose_target()

func _lose_target() -> void:
	if target != null:
		target_lost.emit(target)
	target = null
	if current_state != AIState.SEEK:
		_set_state(AIState.SEEK, "目标丢失")

func _has_line_of_sight(target_pos: Vector3) -> bool:
	"""从机体偏上向目标做射线，只检测地形/建筑物遮挡；所有载具彼此不构成遮挡（防空到坦克都算'看到'）"""
	var from: Vector3 = vehicle.global_position + vehicle.global_transform.basis.y * 3.0
	var to: Vector3 = target_pos + Vector3.UP * 2.0
	var space = vehicle.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var excludes: Array = []
	for v in get_tree().get_nodes_in_group("vehicle"):
		excludes.append(v.get_rid())
	query.exclude = excludes
	return space.intersect_ray(query).is_empty()

func _aim_at(world_dir: Vector3) -> void:
	"""把世界系方向写进 target_pitch/target_yaw（与玩家鼠标引导同符号）"""
	var d: Vector3 = world_dir.normalized()
	vehicle.target_yaw = atan2(-d.x, -d.z)
	vehicle.target_pitch = asin(clamp(d.y, -1.0, 1.0))

func _aim_at_point(world_point: Vector3) -> void:
	var d: Vector3 = world_point - vehicle.global_position
	_aim_at(d)

func _aim_error_deg() -> float:
	"""机头(炮口)朝向与目标方向的夹角（度）"""
	var fwd: Vector3 = -vehicle.global_transform.basis.z
	var to_target: Vector3 = (target.global_position - vehicle.global_position).normalized()
	return rad_to_deg(fwd.angle_to(to_target))

func _height_collective() -> float:
	"""直升机高度反馈：低于目标高度加总距，上升趋势减总距，防震荡"""
	var err: float = cruise_altitude - vehicle.global_position.y
	return clamp(0.25 + err * 0.04 - vehicle.velocity.y * 0.015, 0.0, 1.0)

func _vehicle_on_floor() -> bool:
	if vehicle.has_method("is_on_floor"):
		return vehicle.is_on_floor()
	return vehicle.global_position.y < 1.2