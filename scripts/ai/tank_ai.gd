extends Node
## 坦克AI控制器
## 状态机：巡逻 → 发现目标 → 追击 → 攻击 → （血量低）撤退
## 通过设置载具的 input_* 变量来控制移动和瞄准

signal state_changed(new_state: int)
signal target_acquired(target: Node)
signal target_lost()

enum AIState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	RETREAT
}

@export var team: int = 2  # 1=友方, 2=敌方
@export var detection_range: float = 120.0
@export var attack_range: float = 80.0
@export var preferred_range: float = 50.0
@export var retreat_health_percent: float = 0.2
@export var fire_cooldown: float = 3.0
@export var accuracy: float = 0.7  # 0.0-1.0, 影响瞄准偏差
@export var aggression: float = 0.5  # 0.0-1.0, 影响追击倾向
var reaction_min: float = 0.5
var reaction_max: float = 1.5

var tank = null  # Vehicle类型，避免class_name解析问题
var current_state: AIState = AIState.PATROL
var target: Node = null
var patrol_target: Vector3 = Vector3.ZERO
var patrol_timer: float = 0.0
var fire_timer: float = 0.0
var is_aimed: bool = false
var aim_offset: Vector2 = Vector2.ZERO  # 瞄准偏差（模拟AI精度）
var stuck_timer: float = 0.0
var last_position: Vector3 = Vector3.ZERO
var reaction_timer: float = 0.0  # 反应时间

func _ready() -> void:
	tank = get_parent()
	if not tank or not tank.has_method("take_damage"):
		push_error("[TankAI] Parent is not a Vehicle")
		return
	tank.add_to_group("ai_vehicle")
	last_position = tank.global_position
	_apply_difficulty()
	# 装填间隔由载具武器数据决定
	if "reload_time" in tank:
		fire_cooldown = tank.reload_time
	_enter_patrol()
	print("[TankAI] Initialized for %s, team %d, difficulty %d" % [tank.vehicle_id, team, GameManager.difficulty])

func _apply_difficulty() -> void:
	"""根据游戏难度调整AI参数（装填间隔由载具武器数据决定，不受难度影响）"""
	match GameManager.difficulty:
		0:  # 简单
			accuracy = 0.4
			aggression = 0.3
			detection_range = 80.0
			attack_range = 55.0
			reaction_min = 1.5
			reaction_max = 3.0
		1:  # 普通（默认）
			accuracy = 0.7
			aggression = 0.5
			detection_range = 120.0
			attack_range = 80.0
			reaction_min = 0.5
			reaction_max = 1.5
		2:  # 困难
			accuracy = 0.85
			aggression = 0.7
			detection_range = 150.0
			attack_range = 100.0
			reaction_min = 0.2
			reaction_max = 0.8
		3:  # 专家
			accuracy = 0.95
			aggression = 0.9
			detection_range = 180.0
			attack_range = 120.0
			reaction_min = 0.1
			reaction_max = 0.4

func _physics_process(delta: float) -> void:
	if not tank or tank.is_destroyed:
		return

	fire_timer -= delta
	reaction_timer -= delta

	# 状态更新
	match current_state:
		AIState.IDLE:
			_update_idle(delta)
		AIState.PATROL:
			_update_patrol(delta)
		AIState.CHASE:
			_update_chase(delta)
		AIState.ATTACK:
			_update_attack(delta)
		AIState.RETREAT:
			_update_retreat(delta)

	# 检测是否卡住
	_check_stuck(delta)

	# 血量检测
	var health = tank.get_health_percent()
	if health < retreat_health_percent and current_state != AIState.RETREAT:
		_enter_retreat()

func _update_idle(_delta: float) -> void:
	# 待机，缓慢搜索
	tank.input_throttle = 0.0
	tank.input_steering = 0.0
	tank.input_turret = 0.0
	_search_target()
	if target:
		_enter_chase()

func _update_patrol(delta: float) -> void:
	patrol_timer -= delta
	if patrol_timer <= 0 or tank.global_position.distance_to(patrol_target) < 5.0:
		_pick_new_patrol_point()

	_move_toward(patrol_target, 0.5)
	_slow_rotate_turret()

	# 巡逻中搜索目标
	if reaction_timer <= 0:
		_search_target()
		reaction_timer = randf_range(reaction_min, reaction_max)

	if target:
		_enter_chase()

func _update_chase(_delta: float) -> void:
	if not target or target.is_destroyed:
		target = null
		_enter_patrol()
		return

	var dist = tank.global_position.distance_to(target.global_position)

	# 距离合适，进入攻击
	if dist <= attack_range:
		_enter_attack()
		return

	# 距离太远，继续追击
	_move_toward(target.global_position, 1.0)
	_aim_at_target()

func _update_attack(_delta: float) -> void:
	if not target or target.is_destroyed:
		target = null
		_enter_patrol()
		return

	var dist = tank.global_position.distance_to(target.global_position)

	# 目标超出攻击范围，追击
	if dist > attack_range * 1.2:
		_enter_chase()
		return

	# 太近，后退保持距离
	if dist < preferred_range * 0.5:
		tank.input_throttle = -0.5
	else:
		tank.input_throttle = 0.0

	# 微调车身朝向
	_aim_body_at_target()

	# 瞄准目标
	_aim_at_target()

	# 瞄准完成后开火
	if is_aimed and fire_timer <= 0:
		_fire()
		fire_timer = fire_cooldown + randf_range(-0.5, 0.5)

func _update_retreat(_delta: float) -> void:
	if not target:
		# 没有目标，找个安全点
		if patrol_timer <= 0:
			_pick_new_patrol_point()
			patrol_timer = randf_range(3.0, 6.0)
		_move_toward(patrol_target, 0.8)
	else:
		# 远离目标
		var away_dir = (tank.global_position - target.global_position).normalized()
		var retreat_pos = tank.global_position + away_dir * 50.0
		_move_toward(retreat_pos, 1.0)
		_aim_at_target()  # 边撤边打

	# 血量恢复一些后回到巡逻
	if tank.get_health_percent() > retreat_health_percent * 1.5:
		_enter_patrol()

func _search_target() -> void:
	"""搜索敌方目标（车长损毁降低探测范围）"""
	var vehicles = get_tree().get_nodes_in_group("vehicle")
	# 车长效能影响探测范围
	var commander_eff = tank.get_commander_effectiveness() if tank and tank.has_method("get_commander_effectiveness") else 1.0
	var effective_range = detection_range * commander_eff
	var closest_dist = effective_range
	var closest = null

	for v in vehicles:
		if v == tank or v.is_destroyed:
			continue
		# 检查是否是敌方（team不同）
		var v_team = v.get("team") if "team" in v else 1
		if v_team == team:
			continue
		var dist = tank.global_position.distance_to(v.global_position)
		if dist < closest_dist:
			# 简单视线检测
			if _has_line_of_sight(v.global_position):
				closest_dist = dist
				closest = v

	if closest and closest != target:
		target = closest
		# 随机瞄准偏差（炮手损毁进一步降低精度）
		var gunner_eff = tank.get_gunner_effectiveness() if tank and tank.has_method("get_gunner_effectiveness") else 1.0
		var accuracy_factor = accuracy * gunner_eff
		aim_offset = Vector2(randf_range(-1.0, 1.0) * (1.0 - accuracy_factor) * 5.0,
			randf_range(-1.0, 1.0) * (1.0 - accuracy_factor) * 3.0)
		target_acquired.emit(target)
	elif not closest and target:
		target = null
		target_lost.emit()

func _has_line_of_sight(target_pos: Vector3) -> bool:
	"""简单的视线检测（射线）"""
	var from = tank.global_position + Vector3(0, 1.5, 0)
	var to = target_pos + Vector3(0, 1.5, 0)
	var space = tank.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # 只检测世界/障碍物
	query.exclude = [tank.get_rid()]
	var result = space.intersect_ray(query)
	return result.is_empty()

func _move_toward(target_pos: Vector3, speed_factor: float) -> void:
	"""移动朝向目标点"""
	var to_target = target_pos - tank.global_position
	to_target.y = 0
	var dist = to_target.length()

	if dist < 2.0:
		tank.input_throttle = 0.0
		tank.input_steering = 0.0
		return

	# 计算目标方向与车头的夹角
	var target_dir = to_target.normalized()
	var forward = -tank.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	var dot = forward.dot(target_dir)
	var cross = forward.cross(target_dir)
	var angle = atan2(cross.y, dot)  # 左右偏差

	# 转向
	tank.input_steering = clamp(angle * 2.0, -1.0, 1.0)

	# 油门（转向大时减速）
	var throttle = speed_factor * (1.0 - abs(angle) * 0.5)
	tank.input_throttle = clamp(throttle, -1.0, 1.0)

	# 障碍物规避
	_avoid_obstacles()

func _avoid_obstacles() -> void:
	"""简单的障碍物规避：前方射线检测"""
	var forward = -tank.global_transform.basis.z
	var from = tank.global_position + Vector3(0, 1.0, 0)
	var to = from + forward * 8.0
	var space = tank.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [tank.get_rid()]
	var result = space.intersect_ray(query)

	if result:
		# 前方有障碍，减速并转向
		tank.input_throttle *= 0.3
		# 随机左右转
		if randf() < 0.5:
			tank.input_steering = 1.0
		else:
			tank.input_steering = -1.0

func _aim_at_target() -> void:
	"""炮塔和火炮瞄准目标"""
	if not target:
		is_aimed = false
		return

	# 计算目标相对炮塔的方向
	var turret_pos = Vector3.ZERO
	if tank.turret_node:
		turret_pos = tank.turret_node.global_position
	else:
		turret_pos = tank.global_position + Vector3(0, 1.5, 0)

	var to_target = target.global_position + Vector3(0, 1.0, 0) - turret_pos
	# 加入瞄准偏差
	to_target.x += aim_offset.x
	to_target.y += aim_offset.y

	# 水平角度（炮塔旋转）：世界角度转相对车体角度
	var target_yaw_world = atan2(-to_target.x, -to_target.z)
	var body_yaw_deg = rad_to_deg(tank.rotation.y)
	var target_yaw_rel = rad_to_deg(target_yaw_world) - body_yaw_deg
	# 归一化到 -180~180
	target_yaw_rel = fmod(target_yaw_rel + 180.0, 360.0) - 180.0
	var yaw_diff = target_yaw_rel - tank.turret_yaw
	yaw_diff = fmod(yaw_diff + 180.0, 360.0) - 180.0

	var turret_eff = tank._get_module_effectiveness("turret_ring")

	if abs(yaw_diff) > 0.5:
		tank.input_turret = clamp(yaw_diff * 0.15, -1.0, 1.0)
	else:
		tank.input_turret = 0.0

	# 垂直角度（火炮俯仰）
	var horizontal_dist = sqrt(to_target.x * to_target.x + to_target.z * to_target.z)
	var target_pitch = rad_to_deg(atan2(to_target.y, horizontal_dist))
	var pitch_diff = target_pitch - tank.gun_pitch

	if abs(pitch_diff) > 0.3:
		tank.input_gun = clamp(pitch_diff * 0.2, -1.0, 1.0)
	else:
		tank.input_gun = 0.0

	# 判断是否瞄准完成
	is_aimed = abs(yaw_diff) < 1.5 and abs(pitch_diff) < 1.0

func _aim_body_at_target() -> void:
	"""车身微调朝向目标（攻击时）"""
	if not target:
		return
	var to_target = target.global_position - tank.global_position
	to_target.y = 0
	var forward = -tank.global_transform.basis.z
	forward.y = 0
	var dot = forward.dot(to_target.normalized())
	if dot < 0.9:  # 车身偏差超过25度
		var cross = forward.cross(to_target.normalized())
		tank.input_steering = clamp(cross.y * 2.0, -0.5, 0.5)
	else:
		tank.input_steering = 0.0

func _slow_rotate_turret() -> void:
	"""巡逻时缓慢旋转炮塔搜索"""
	tank.input_turret = 0.3
	tank.input_gun = 0.0

func _fire() -> void:
	"""开火"""
	tank.fire()
	# 开火后重新随机偏差（模拟后坐力，炮手损毁精度更差）
	var gunner_eff = tank.get_gunner_effectiveness() if tank and tank.has_method("get_gunner_effectiveness") else 1.0
	var accuracy_factor = accuracy * gunner_eff
	aim_offset = Vector2(randf_range(-1.0, 1.0) * (1.0 - accuracy_factor) * 5.0,
		randf_range(-1.0, 1.0) * (1.0 - accuracy_factor) * 3.0)

func _pick_new_patrol_point() -> void:
	"""随机选择巡逻点"""
	var angle = randf() * TAU
	var radius = randf_range(15.0, 40.0)
	patrol_target = tank.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	patrol_timer = randf_range(5.0, 10.0)

func _check_stuck(delta: float) -> void:
	"""检测是否卡住"""
	var moved = tank.global_position.distance_to(last_position)
	if moved < 0.1 and abs(tank.input_throttle) > 0.3:
		stuck_timer += delta
		if stuck_timer > 2.0:
			# 卡住了，倒车+转向
			tank.input_throttle = -0.8
			tank.input_steering = 1.0 if randf() < 0.5 else -1.0
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0
	last_position = tank.global_position

func _enter_idle() -> void:
	current_state = AIState.IDLE
	state_changed.emit(current_state)

func _enter_patrol() -> void:
	current_state = AIState.PATROL
	patrol_timer = 0.0
	_pick_new_patrol_point()
	state_changed.emit(current_state)

func _enter_chase() -> void:
	current_state = AIState.CHASE
	state_changed.emit(current_state)

func _enter_attack() -> void:
	current_state = AIState.ATTACK
	state_changed.emit(current_state)

func _enter_retreat() -> void:
	current_state = AIState.RETREAT
	patrol_timer = 0.0
	state_changed.emit(current_state)

func get_state_name() -> String:
	match current_state:
		AIState.IDLE: return "IDLE"
		AIState.PATROL: return "PATROL"
		AIState.CHASE: return "CHASE"
		AIState.ATTACK: return "ATTACK"
		AIState.RETREAT: return "RETREAT"
	return "UNKNOWN"
