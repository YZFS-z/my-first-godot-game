extends SceneTree
## 回归校验：固定翼长周期（phugoid）阻尼
## 校验点：
##  1. 巡航速度+水平飞行：末段垂直速度收敛到近零（无持续上下抖动）
##  2. 爬升扰动（vy=+5）后 5 秒内衰减到 <1.0 m/s
##  3. 下降扰动（vy=-5）后 5 秒内衰减到 <1.0 m/s
##  4. 爬升指令（target_pitch=30°）：vy 收敛到 sin(30°)*spd 附近，无振荡
##  5. 俯冲指令（target_pitch=-20°）：vy 收敛到 sin(-20°)*spd 附近，无振荡
##  6. W/S 模拟：target_pitch 变化后飞机俯仰角跟随变化

const MAX_STEPS := 400

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _veh: Node = null
var _vys: Array = []
var _pitches: Array = []

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
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "PhugoidCheck"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_ground()
	_veh = load("res://scenes/airplane.tscn").instantiate()
	_veh.is_player_controlled = false
	_veh.is_server_controlled = true
	_veh.is_remote_ai = false
	_veh.team = 1
	_veh.global_position = Vector3(0, 200.0, 0)
	root.add_child(_veh)
	_phase = 0
	_step = 0

func _begin_phase(vy: float, t_pitch: float = 0.0) -> void:
	_vys.clear()
	_pitches.clear()
	# 给飞机一个水平巡航速度（沿 -Z 方向）
	var cruise_spd: float = 80.0
	_veh.global_position = Vector3(0, 200.0, 0)
	_veh.velocity = Vector3(0, vy, -cruise_spd)
	_veh.rotation = Vector3.ZERO
	_veh.angular_velocity = Vector3.ZERO
	# 设定油门维持巡航推力
	_veh.throttle = 0.5
	# target_pitch 设定
	_veh.target_pitch = t_pitch
	_veh.target_yaw = 0.0

func _analyze(tag: String, expect_vy: float) -> void:
	var frames: int = _vys.size()
	if frames < 60:
		_check(false, "[%s] 帧数不足 (%d)" % [tag, frames])
		return
	var last1 := _vys.slice(frames - 60, frames)
	var sum_vy := 0.0
	for v in last1:
		sum_vy += v
	var mean_vy := sum_vy / last1.size()
	var amp := 0.0
	for i in range(1, last1.size()):
		amp = maxf(amp, absf(last1[i] - last1[i - 1]))
	var max_abs_vy := 0.0
	for v in last1:
		max_abs_vy = maxf(max_abs_vy, absf(v))
	print("  [%s] 末段平均vy=%.3f 最大|vy|=%.3f 帧间振幅=%.4f" % [tag, mean_vy, max_abs_vy, amp])
	_check(absf(mean_vy) < expect_vy, "[%s] 末段平均垂直速度收敛 <%.1f m/s (实际 %.3f)" % [tag, expect_vy, mean_vy])
	_check(amp < 0.5, "[%s] 末段无振荡 (帧间振幅 %.4f < 0.5)" % [tag, amp])
	_check(max_abs_vy < expect_vy * 2.0, "[%s] 末段最大垂直速度 <%.1f m/s (实际 %.3f)" % [tag, expect_vy * 2.0, max_abs_vy])

func _analyze_climb(tag: String, target_pitch_rad: float, cruise_spd: float) -> void:
	var frames: int = _vys.size()
	if frames < 60:
		_check(false, "[%s] 帧数不足 (%d)" % [tag, frames])
		return
	var last1 := _vys.slice(frames - 60, frames)
	var sum_vy := 0.0
	for v in last1:
		sum_vy += v
	var mean_vy := sum_vy / last1.size()
	var amp := 0.0
	for i in range(1, last1.size()):
		amp = maxf(amp, absf(last1[i] - last1[i - 1]))
	# 目标垂直速度 = sin(target_pitch) * spd（注意：实际 vy 不精确匹配，
	# 因航迹角 ≠ 俯仰角（有攻角），且爬升/俯冲时速度变化。
	# 判据：vy 方向正确（与 target_pitch 同号）且量级合理（>目标的 30%），
	# 且无振荡（帧间振幅 < 1.0）。
	var target_vy := sin(target_pitch_rad) * cruise_spd
	var same_sign := (mean_vy > 0) == (target_vy > 0)
	var magnitude_ok := absf(mean_vy) > absf(target_vy) * 0.3
	print("  [%s] 末段平均vy=%.3f 目标vy=%.3f 同号=%s 量级OK=%s 帧间振幅=%.4f" % [tag, mean_vy, target_vy, same_sign, magnitude_ok, amp])
	_check(same_sign, "[%s] 垂直速度方向正确 (vy=%.1f, target=%.1f)" % [tag, mean_vy, target_vy])
	_check(magnitude_ok, "[%s] 垂直速度量级合理 (|vy|=%.1f > |target|*0.3=%.1f)" % [tag, absf(mean_vy), absf(target_vy) * 0.3])
	_check(amp < 1.0, "[%s] 爬升/俯冲过程无振荡 (帧间振幅 %.4f < 1.0)" % [tag, amp])

func _analyze_pitch_response(tag: String) -> void:
	# 检查俯仰角是否跟随 target_pitch 变化
	var frames: int = _pitches.size()
	if frames < 60:
		_check(false, "[%s] 帧数不足 (%d)" % [tag, frames])
		return
	var last1 := _pitches.slice(frames - 60, frames)
	var sum_p := 0.0
	for p in last1:
		sum_p += p
	var mean_p := sum_p / last1.size()
	var amp := 0.0
	for i in range(1, last1.size()):
		amp = maxf(amp, absf(last1[i] - last1[i - 1]))
	print("  [%s] 末段平均pitch=%.3f rad (%.1f°) 帧间振幅=%.4f" % [tag, mean_p, rad_to_deg(mean_p), amp])
	# 俯仰角应该明显偏离0（跟随 target_pitch）
	_check(absf(mean_p) > deg_to_rad(5.0), "[%s] 俯仰角跟随 target_pitch 变化 (|pitch|=%.1f° > 5°)" % [tag, rad_to_deg(absf(mean_p))])
	_check(amp < deg_to_rad(2.0), "[%s] 俯仰角无振荡 (帧间振幅 %.2f° < 2°)" % [tag, rad_to_deg(amp)])

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if _step > MAX_STEPS * 10:
		print("FAIL: 测试全局超时 @phase=%d" % _phase)
		_finish()
		return false
	match _phase:
		0:
			if _step < 8:
				return false
			_veh.setup_from_data(_load_json("res://data/vehicles/plane_a10.json"))
			if _veh.phugoid_damping_gain <= 0.0:
				_check(false, "phugoid_damping_gain 未生效 (%.2f)" % _veh.phugoid_damping_gain)
			print("phugoid 阻尼参数: gain=%.2f" % _veh.phugoid_damping_gain)
			_begin_phase(0.0)
			_phase = 1
			_step = 0
		1:
			# 水平巡航无扰动：5 秒（300 帧）应收敛到近零 vy
			if _step < 300:
				_veh.throttle = 0.5
				_vys.append(_veh.velocity.y)
				return false
			_analyze("水平巡航无扰动", 1.0)
			# 爬升扰动：vy=+5
			_begin_phase(5.0)
			_phase = 2
			_step = 0
		2:
			# 爬升扰动：5 秒内 vy 衰减到 <1.0
			if _step < 300:
				_veh.throttle = 0.5
				_vys.append(_veh.velocity.y)
				return false
			_analyze("爬升扰动收敛", 1.0)
			# 下降扰动：vy=-5
			_begin_phase(-5.0)
			_phase = 3
			_step = 0
		3:
			# 下降扰动：5 秒内 vy 衰减到 <1.0
			if _step < 300:
				_veh.throttle = 0.5
				_vys.append(_veh.velocity.y)
				return false
			_analyze("下降扰动收敛", 1.0)
			# 爬升指令：target_pitch=30°，禁用自动回正（模拟玩家持续按 W）
			_begin_phase(0.0, deg_to_rad(30.0))
			_veh.auto_center_enabled = false
			_phase = 4
			_step = 0
		4:
			# 爬升指令：6 秒（360 帧）应收敛到目标 vy 并无振荡
			if _step < 360:
				_veh.throttle = 0.5
				_vys.append(_veh.velocity.y)
				_pitches.append(_veh.rotation.x)
				return false
			_analyze_climb("爬升指令收敛", deg_to_rad(30.0), 80.0)
			_analyze_pitch_response("爬升指令俯仰响应")
			# 俯冲指令：target_pitch=-20°
			_begin_phase(0.0, deg_to_rad(-20.0))
			_veh.auto_center_enabled = false
			_phase = 5
			_step = 0
		5:
			# 俯冲指令：6 秒应收敛到目标 vy 并无振荡
			if _step < 360:
				_veh.throttle = 0.5
				_vys.append(_veh.velocity.y)
				_pitches.append(_veh.rotation.x)
				return false
			_analyze_climb("俯冲指令收敛", deg_to_rad(-20.0), 80.0)
			_analyze_pitch_response("俯冲指令俯仰响应")
			_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
