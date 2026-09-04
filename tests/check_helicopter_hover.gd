extends SceneTree
## 回归校验：物理高度悬停（总距级联控制，而非直接设垂直速度）
## 校验点：
##  1. 悬停锁定后高度稳定在目标（末 1 秒 |偏差|<0.5m，帧间振幅小=无振荡）
##  2. 从低位（y=5）恢复爬升到目标高度（5 秒内 |偏差|<0.5m）
##  3. 中途被外力推高（y=13）后回落恢复（5 秒内 |偏差|<0.5m）

const MAX_STEPS := 400

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _veh: Node = null
var _ys: Array = []
var _start_y := 10.0
var _target_y := 10.0
var _disturb := false
var _disturbed := false
var _max_dev := 0.0

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
	fake_scene.name = "FakeHoverCheck"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_ground()
	_veh = load("res://scenes/helicopter.tscn").instantiate()
	_veh.is_player_controlled = false
	_veh.is_server_controlled = true
	_veh.is_remote_ai = false
	_veh.team = 1
	_veh.global_position = Vector3(0, _start_y, 0)
	root.add_child(_veh)
	_phase = 0

func _begin_hover(sy: float, ty: float, disturb: bool) -> void:
	_start_y = sy
	_target_y = ty
	_disturb = disturb
	_disturbed = false
	_ys.clear()
	_max_dev = 0.0
	_veh.global_position = Vector3(0, sy, 0)
	_veh.velocity = Vector3.ZERO
	_veh.rotation = Vector3.ZERO
	_veh.hover_active = true
	_veh.hover_target_y = ty

func _analyze(tag: String) -> void:
	var frames: int = _ys.size()
	if frames < 60:
		_check(false, "[%s] 帧数不足 (%d)" % [tag, frames])
		return
	var last1 := _ys.slice(frames - 60, frames)
	var amp := 0.0
	for i in range(1, last1.size()):
		amp = maxf(amp, absf(last1[i] - last1[i - 1]))
	var final_dev: float = absf(_veh.global_position.y - _target_y)
	var dev_ok: bool = final_dev < 0.5
	var stable_ok: bool = amp < 0.05
	print("  [%s] 最终y=%.2f 偏差=%.2f 末段帧间振幅=%.4f 最大偏差=%.2f" % [_ys[frames - 1], _veh.global_position.y, final_dev, amp, _max_dev])
	_check(dev_ok, "[%s] 悬停收敛到目标高度 ±0.5m (偏差 %.2f)" % [tag, final_dev])
	_check(stable_ok, "[%s] 末段无振荡 (帧间振幅 %.4f)" % [tag, amp])

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if _step > MAX_STEPS * 6:
		print("FAIL: 测试全局超时 @phase=%d" % _phase)
		_finish()
		return false
	match _phase:
		0:
			# 等进树并 setup
			if _step < 8:
				return false
			_veh.setup_from_data(_load_json("res://data/vehicles/heli_ah64.json"))
			if _veh.hover_height_gain <= 0.0:
				_check(false, "JSON 悬停参数未生效 (hover_height_gain=%.2f)" % _veh.hover_height_gain)
			print("悬停参数: gain=%.2f speed_limit=%.2f speed_gain=%.3f rate=%.2f" % [_veh.hover_height_gain, _veh.hover_speed_limit, _veh.hover_speed_gain, _veh.hover_collective_rate])
			_begin_hover(10.0, 10.0, false)
			_phase = 1
			_step = 0
		1:
			# 基础悬停：5 秒（300 帧）
			if _step < 300:
				_ys.append(_veh.global_position.y)
				_max_dev = maxf(_max_dev, absf(_veh.global_position.y - _target_y))
				return false
			_analyze("基础悬停")
			_begin_hover(5.0, 10.0, false)
			_phase = 2
			_step = 0
		2:
			# 低位爬升恢复：5 秒
			if _step < 300:
				_ys.append(_veh.global_position.y)
				_max_dev = maxf(_max_dev, absf(_veh.global_position.y - _target_y))
				return false
			_analyze("低位爬升")
			_begin_hover(10.0, 10.0, true)
			_phase = 3
			_step = 0
		3:
			# 扰动：第 3 秒(180帧)把机体推到 y=13, vy=2
			if _step == 180 and not _disturbed:
				_veh.global_position = Vector3(0, 13, 0)
				_veh.velocity = Vector3(0, 2, 0)
				_disturbed = true
			if _step < 300:
				_ys.append(_veh.global_position.y)
				_max_dev = maxf(_max_dev, absf(_veh.global_position.y - _target_y))
				return false
			_analyze("外力扰动")
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
