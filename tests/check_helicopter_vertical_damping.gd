extends SceneTree
## 回归校验：非悬停模式垂直阻尼（旋翼入流反馈）
## 校验点：
##  1. 固定总距≈悬停平衡值时，非悬停模式垂直速度收敛到近零（阻尼生效，无发散/振荡）
##  2. 施加垂直扰动（vy=+3）后，垂直速度在 5 秒内衰减到 <0.5 m/s（阻尼有效吸收扰动）
##  3. 施加下降扰动（vy=-3）后，垂直速度在 5 秒内衰减到 <0.5 m/s

const MAX_STEPS := 400

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _veh: Node = null
var _vys: Array = []
var _target_collective := 0.0

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
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "VertDampCheck"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_ground()
	_veh = load("res://scenes/helicopter.tscn").instantiate()
	_veh.is_player_controlled = false
	_veh.is_server_controlled = true
	_veh.is_remote_ai = false
	_veh.team = 1
	_veh.global_position = Vector3(0, 40.0, 0)
	root.add_child(_veh)
	_phase = 0
	_step = 0

func _begin_phase(collective: float, vy: float) -> void:
	_vys.clear()
	_veh.global_position = Vector3(0, 40.0, 0)
	_veh.velocity = Vector3(0, vy, 0)
	_veh.rotation = Vector3.ZERO
	_veh.angular_velocity = Vector3.ZERO
	_veh.hover_active = false
	_veh.collective = collective
	_target_collective = collective

func _analyze(tag: String, expect_vy: float) -> void:
	var frames: int = _vys.size()
	if frames < 60:
		_check(false, "[%s] 帧数不足 (%d)" % [tag, frames])
		return
	var last1 := _vys.slice(frames - 60, frames)
	# 末段平均垂直速度
	var sum_vy := 0.0
	for v in last1:
		sum_vy += v
	var mean_vy := sum_vy / last1.size()
	# 末段最大帧间速度变化（振幅）
	var amp := 0.0
	for i in range(1, last1.size()):
		amp = maxf(amp, absf(last1[i] - last1[i - 1]))
	# 末段最大绝对速度
	var max_abs_vy := 0.0
	for v in last1:
		max_abs_vy = maxf(max_abs_vy, absf(v))
	print("  [%s] 末段平均vy=%.3f 最大|vy|=%.3f 帧间振幅=%.4f" % [tag, mean_vy, max_abs_vy, amp])
	_check(absf(mean_vy) < expect_vy, "[%s] 末段平均垂直速度收敛 <%.1f m/s (实际 %.3f)" % [tag, expect_vy, mean_vy])
	_check(amp < 0.1, "[%s] 末段无振荡 (帧间振幅 %.4f < 0.1)" % [tag, amp])
	_check(max_abs_vy < expect_vy * 2.0, "[%s] 末段最大垂直速度 <%.1f m/s (实际 %.3f)" % [tag, expect_vy * 2.0, max_abs_vy])

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if _step > MAX_STEPS * 5:
		print("FAIL: 测试全局超时 @phase=%d" % _phase)
		_finish()
		return false
	match _phase:
		0:
			if _step < 8:
				return false
			_veh.setup_from_data(_load_json("res://data/vehicles/heli_ah64.json"))
			if _veh.vertical_damping_gain <= 0.0:
				_check(false, "vertical_damping_gain 未生效 (%.2f)" % _veh.vertical_damping_gain)
			print("垂直阻尼参数: gain=%.2f" % _veh.vertical_damping_gain)
			# 计算悬停平衡总距（近似）
			var rho: float = float(_veh.AIR_DENSITY) * exp(-40.0 / 8500.0)
			var tip: float = float(_veh.rotor_omega_nominal) * float(_veh.rotor_radius)
			var denom: float = float(_veh.ct_max) * rho * float(_veh.rotor_area) * tip * tip
			_target_collective = (float(_veh.mass_kg) * 20.0) / maxf(denom, 0.001)
			print("悬停平衡总距≈%.3f" % _target_collective)
			_begin_phase(_target_collective, 0.0)
			_phase = 1
			_step = 0
		1:
			# 平衡总距 + 无扰动：5 秒（300 帧）应收敛到近零 vy
			if _step < 300:
				# 保持 collective 固定（防止 setup_from_data 后默认值变化）
				_veh.collective = _target_collective
				_vys.append(_veh.velocity.y)
				return false
			_analyze("平衡总距无扰动", 0.5)
			# 爬升扰动：vy=+3
			_begin_phase(_target_collective, 3.0)
			_phase = 2
			_step = 0
		2:
			# 爬升扰动 + 平衡总距：5 秒内 vy 衰减到 <0.5
			if _step < 300:
				_veh.collective = _target_collective
				_vys.append(_veh.velocity.y)
				return false
			_analyze("爬升扰动收敛", 0.5)
			# 下降扰动：vy=-3
			_begin_phase(_target_collective, -3.0)
			_phase = 3
			_step = 0
		3:
			# 下降扰动 + 平衡总距：5 秒内 vy 衰减到 <0.5
			if _step < 300:
				_veh.collective = _target_collective
				_vys.append(_veh.velocity.y)
				return false
			_analyze("下降扰动收敛", 0.5)
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
