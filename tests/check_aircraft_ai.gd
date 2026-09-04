extends SceneTree
## 校验：飞行器AI（aircraft_ai.gd）能驱动直升机/固定翼起飞、发现敌方并瞄准开火
## 阶段0：直升机 + 敌方坦克 80m 外 -> 爬升 > 30m、进入 ATTACK、机头对准、锁定并开火
## 阶段1：固定翼 A-10 + 敌方坦克 180m 外 -> 离地爬升、油门推进、进入 ATTACK、机头对准

const AI_SCRIPT := "res://scripts/ai/aircraft_ai.gd"
const MAX_FRAMES := 1500
const MAX_FRAMES_P1 := 1800

var _failed := 0
var _frame := 0
var _phase := 0
var _vehicle: Node = null
var _target: Node = null
var _ai: Node = null
var _done := false
var _ammo_before := 0
var _min_err := 999.0  # 阶段1攻击周期中记录到的最小机头对准误差
var _max_y := 0.0      # 阶段1全程记录到的最高点（俯冲-拉起机动中结束帧可能恰在低点）

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _spawn(vid: String, pos: Vector3, team: int, with_ai: bool, rot_y: float = 0.0) -> Node:
	var data: Dictionary = _load_json("res://data/vehicles/%s.json" % vid)
	var vtype: String = data.get("type", "tank")
	var path: String = "res://scenes/helicopter.tscn"
	if vtype == "airplane":
		path = "res://scenes/airplane.tscn"
	elif vtype == "tank":
		path = "res://scenes/vehicle.tscn"
	var v: Node = load(path).instantiate()
	v.is_player_controlled = false
	v.is_server_controlled = true
	v.team = team
	v.global_position = pos
	v.rotation.y = rot_y  # 出生朝向（与 main.gd spawn 一致：spawn 区带方向）
	root.add_child(v)          # 先入树：_ready 才会初始化 damage_system 等
	v.setup_from_data(data)    # 再装载数据（与 main.gd 出生流程一致）
	if with_ai:
		var ai: Node = load(AI_SCRIPT).new()
		ai.team = team
		v.add_child(ai)
		_ai = ai
	return v

func _aim_error(target: Node) -> float:
	var fwd: Vector3 = -_vehicle.global_transform.basis.z
	return rad_to_deg(fwd.angle_to((target.global_position - _vehicle.global_position).normalized()))

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _init_phase0() -> void:
	print("INFO: 阶段0 - 直升机AI验证")
	_make_ground()
	_vehicle = _spawn("heli_ah64", Vector3(0, 0.2, 0), 1, true)
	_target = _spawn("tank_abrams", Vector3(80, 0.5, 0), 2, false)
	_ammo_before = _total_ammo()
	print("INFO: 直升机 %s 挂载AI，敌方坦克位于 80m 外，等待 %d 帧..." % [_vehicle.vehicle_id, MAX_FRAMES])

func _init_phase1() -> void:
	print("INFO: 阶段1 - 固定翼AI验证")
	_frame = 0
	_min_err = 999.0
	# 面向敌方坦克（+X 方向）：A-10 机头朝 -Z，绕 Y 转 -90° 即面向 +X
	_vehicle = _spawn("plane_a10", Vector3(0, 0.2, 0), 1, true, -PI / 2.0)
	# 模拟跑道滑跑初速（55 m/s 起飞速度前的滑跑段，避免测试场地内加速时间过长）
	_vehicle.velocity = Vector3(40.0, 0.0, 0.0)
	# 坦克放远：先滑跑离地、爬升，再进入 500m 攻击距离（放在滑跑线上会被物理挡停）
	_target = _spawn("tank_abrams", Vector3(500, 0.5, 0), 2, false)
	_ammo_before = _total_ammo()
	print("INFO: 固定翼 %s 挂载AI，敌方坦克位于 180m 外，等待 %d 帧..." % [_vehicle.vehicle_id, MAX_FRAMES])

func _total_ammo() -> int:
	# 跨所有武器槽统计（AI 会从机炮切到导弹，只统计当前槽会误报）
	var total := 0
	if _vehicle and "_weapon_states" in _vehicle:
		for st in _vehicle._weapon_states:
			if "ammo_counts" in st:
				for k in st.ammo_counts:
					total += int(st.ammo_counts[k])
	elif _vehicle and "ammo_counts" in _vehicle:
		for k in _vehicle.ammo_counts:
			total += int(_vehicle.ammo_counts[k])
	return total

func _initialize() -> void:
	# --script 模式下没有 current_scene，挂一个假场景节点，保证 fire() 生成弹丸正常
	var fake_scene := Node.new()
	fake_scene.name = "FakeAircraftAITest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_init_phase0()

func _physics_process(delta: float) -> bool:
	if _done:
		# 阶段切换：等上一阶段节点被 queue_free 清理干净后，在下一帧干净地重建
		if _phase == 1 and _vehicle == null and _ai == null:
			_done = false
			_init_phase1()
		return false
	_frame += 1
	if _vehicle == null or _vehicle.is_destroyed:
		return false
	# 调试输出
	if _frame <= 5 or _frame % 120 == 0 or (_phase == 1 and _frame in [700, 710, 720, 730, 740, 750]):
		var state_name: String = str(_ai.current_state) if _ai else "no_ai"
		var locked: String = "no"
		if "locked_target" in _vehicle and _vehicle.locked_target != null:
			locked = "yes(%.0f%%)" % (float(_vehicle.lock_progress) * 100.0)
		var ai_extra: String = ""
		if _phase == 1 and _ai:
			var d: float = _vehicle.global_position.distance_to(_target.global_position)
			ai_extra = " ft=%.2f rt=%.2f cf=%s rl=%s d=%.0f" % [
				_ai.fire_timer, _ai.reaction_timer, _vehicle.can_fire,
				_vehicle.is_reloading, d]
		print("DBG phase%d frame=%d v=%s y=%.1f throttle=%.2f state=%s target=%s aim_err=%.1f deg lock=%s on_floor=%s%s" % [
			_phase, _frame, _vehicle.vehicle_id, _vehicle.global_position.y,
			_vehicle.throttle if "throttle" in _vehicle else -1.0,
			state_name,
			"yes" if _ai and _ai.target != null else "no",
			_aim_error(_target), locked,
			_vehicle.is_on_floor(), ai_extra])
	if _phase == 0:
		if _frame >= MAX_FRAMES:
			_done = true
			var y: float = _vehicle.global_position.y
			_check(y > 30.0, "直升机AI完成爬升 (y=%.1f)" % y)
			_check(_ai.target == _target, "直升机AI发现敌方目标")
			_check(_ai.current_state == _ai.AIState.ATTACK, "直升机AI进入攻击状态")
			var err: float = _aim_error(_target)
			_check(err < 10.0, "直升机机头对准目标 (误差=%.1f°)" % err)
			var fired: bool = not _vehicle.can_fire or _vehicle.reload_timer > 0.0
			_check(fired, "直升机AI实际开火（进入装填）") 
			_vehicle.queue_free()
			_target.queue_free()
			_vehicle = null
			_target = null
			_ai = null
			_phase = 1
			return false
	elif _phase == 1:
		# 只在攻击状态下记录瞄准误差（证明攻击机动中对准过，滑跑/巡航期不算）
		if _ai and _ai.current_state == _ai.AIState.ATTACK and _ai.target != null:
			_min_err = min(_min_err, _aim_error(_target))
		_max_y = max(_max_y, _vehicle.global_position.y)
		if _frame >= MAX_FRAMES_P1:
			_done = true
			var y: float = _vehicle.global_position.y
			_check(_max_y > 15.0, "固定翼AI完成离地爬升 (最高到达 y=%.1f)" % _max_y)
			_check(_vehicle.throttle > 0.7, "固定翼油门推进 (throttle=%.2f)" % _vehicle.throttle)
			_check(_ai.target == _target, "固定翼AI发现敌方目标")
			var err: float = _min_err
			_check(err < 20.0, "固定翼攻击中机头对准目标 (最小误差=%.1f°)" % err)
			var fired2: bool = not _vehicle.can_fire or _vehicle.reload_timer > 0.0
			_check(fired2, "固定翼AI实际开火（进入装填）")
			_check(_ai.current_state == _ai.AIState.ATTACK or y > 60.0, "固定翼AI转入攻击/爬升机动")
			_vehicle.queue_free()
			_target.queue_free()
			if _failed == 0:
				print("RESULT: failed=0")
				quit(0)
			else:
				print("RESULT: failed=%d" % _failed)
				quit(1)
	return false