extends SceneTree
## 校验：坦克第三人称视角异步机制
## 直接操作 view_offset_yaw/camera_pitch 验证炮塔/火炮限速跟随
## 1. view_offset_yaw 变化后 camera_yaw 即时更新
## 2. turret_yaw 限速跟随 view_offset_yaw
## 3. gun_pitch 限速跟随 camera_pitch
## 4. 炮镜模式仍保持同步
## 5. 退出炮镜后视角同步到炮塔方向

const MAX_FRAMES := 400

var _failed := 0
var _frame := 0
var _phase := 0
var _done := false
var _tank: Node = null
var _y0 := 0.0
var _t0 := 0.0
var _p0 := 0.0
var _g0 := 0.0

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

func _initialize() -> void:
	print("=== Tank Async View Check ===")
	var fake_scene := Node.new()
	fake_scene.name = "AsyncViewTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	# SettingsManager
	if root.get_node_or_null("SettingsManager") == null:
		var sm := Node.new()
		sm.name = "SettingsManager"
		sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(sm)
	print("INFO: 场景就绪")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES:
		_failed += 1
		print("FAIL: 测试全局超时")
		_finish()
		return false
	# 使用固定 delta 避免帧率波动影响限速计算
	var fixed_delta := 1.0 / 60.0
	match _phase:
		0:
			if _frame > 8:
				_tank = load("res://scenes/vehicle.tscn").instantiate()
				_tank.is_player_controlled = true
				_tank.is_server_controlled = false
				_tank.team = 1
				root.add_child(_tank)
				var data: Dictionary = _load_json("res://data/vehicles/tank_abrams.json")
				_tank.setup_from_data(data)
				_phase = 1
				_frame = 0
		1:
			if _frame > 10:
				# 源码检查
				var f := FileAccess.open("res://scripts/vehicles/tank.gd", FileAccess.READ)
				var src := f.get_as_text()
				f.close()
				_check(src.find("view_offset_yaw") != -1, "tank.gd 包含 view_offset_yaw 变量")
				_check(src.find("wrapf(view_offset_yaw - turret_yaw") != -1,
					"tank.gd 炮塔追踪视角方向（wrapf 差值）")
				_check(src.find("camera_yaw = view_offset_yaw + rad_to_deg(rotation.y)") != -1,
					"tank.gd 摄像机跟随车体+视角偏移（非炮塔方向）")
				_check(src.find("camera_pitch = clamp(camera_pitch - event.relative.y") != -1,
					"tank.gd 鼠标直接控制 camera_pitch（即时）")
				# 基线
				_check(abs(_tank.camera_yaw) < 0.01 and abs(_tank.view_offset_yaw) < 0.01,
					"基线：camera_yaw=%.2f view_offset_yaw=%.2f" % [_tank.camera_yaw, _tank.view_offset_yaw])
				# 记录初始值
				_y0 = _tank.camera_yaw
				_t0 = _tank.turret_yaw
				_p0 = _tank.camera_pitch
				_g0 = _tank.gun_pitch
				# 直接设置 view_offset_yaw 模拟鼠标大幅右移
				_tank.view_offset_yaw = -150.0  # 鼠标右移 → view_offset_yaw 减小
				_tank.camera_pitch = 15.0  # 鼠标上移 → camera_pitch 增大
				# 调用 _process 使视角更新生效
				_tank._process(fixed_delta)
				_phase = 2
				_frame = 0
		2:
			# 验证第一帧结果
			if _frame == 1:
				var cam_delta = abs(_tank.camera_yaw - _y0)
				var tur_delta = abs(_tank.turret_yaw - _t0)
				_check(cam_delta > 100.0,
					"视角即时响应 (camera_yaw: %.1f→%.1f, delta=%.1f)" % [_y0, _tank.camera_yaw, cam_delta])
				_check(tur_delta < cam_delta,
					"炮塔限速跟随 (turret_yaw delta=%.1f < camera_yaw delta=%.1f)" % [tur_delta, cam_delta])
				_check(tur_delta > 0.01,
					"炮塔确实在跟随 (turret_yaw delta=%.1f > 0)" % tur_delta)
				# 俯仰
				var pit_delta = abs(_tank.camera_pitch - _p0)
				var gun_delta = abs(_tank.gun_pitch - _g0)
				_check(pit_delta > 10.0,
					"俯仰即时响应 (camera_pitch: %.1f→%.1f, delta=%.1f)" % [_p0, _tank.camera_pitch, pit_delta])
				_check(gun_delta < pit_delta,
					"火炮限速跟随 (gun_pitch delta=%.1f < camera_pitch delta=%.1f)" % [gun_delta, pit_delta])
				# camera_yaw = view_offset_yaw + hull_yaw
				_check(abs(_tank.camera_yaw - (_tank.view_offset_yaw + rad_to_deg(_tank.rotation.y))) < 0.5,
					"camera_yaw = view_offset_yaw + hull_yaw (cam=%.1f offset=%.1f hull=%.1f)" % [
						_tank.camera_yaw, _tank.view_offset_yaw, rad_to_deg(_tank.rotation.y)])
				_phase = 3
				_frame = 0
		3:
			# 等待多帧，炮塔逐渐追上视角
			_tank._process(fixed_delta)
			if _frame >= 30:
				var tur_delta = abs(_tank.turret_yaw - _t0)
				_check(tur_delta > 40.0,
					"炮塔持续追赶 (30帧后 turret_yaw delta=%.1f)" % tur_delta)
				# 炮塔尚未完全追上（仍有差距）
				var remaining = abs(wrapf(_tank.view_offset_yaw - _tank.turret_yaw, -180.0, 180.0))
				_check(remaining > 1.0,
					"炮塔尚未追上视角 (剩余差距=%.1f°)" % remaining)
				_phase = 4
				_frame = 0
		4:
			# 炮镜模式同步验证
			if _frame == 1:
				_tank._toggle_scope()
				_tank._process(fixed_delta)
				_check(_tank.is_scope_mode, "进入炮镜模式")
				_check(abs(_tank.camera_pitch - _tank.gun_pitch) < 0.01,
					"炮镜：camera_pitch=gun_pitch (cam=%.2f gun=%.2f)" % [_tank.camera_pitch, _tank.gun_pitch])
				_check(abs(_tank.camera_yaw - (_tank.turret_yaw + rad_to_deg(_tank.rotation.y))) < 0.01,
					"炮镜：camera_yaw=turret_yaw+hull (cam=%.2f tur+hull=%.2f)" % [
						_tank.camera_yaw, _tank.turret_yaw + rad_to_deg(_tank.rotation.y)])
				_phase = 5
				_frame = 0
		5:
			# 退出炮镜后视角同步
			if _frame == 1:
				_tank._toggle_scope()
				_tank._process(fixed_delta)
				_check(not _tank.is_scope_mode, "退出炮镜模式")
				_check(abs(_tank.view_offset_yaw - _tank.turret_yaw) < 0.01,
					"退出炮镜：view_offset_yaw=turret_yaw (offset=%.2f tur=%.2f)" % [
						_tank.view_offset_yaw, _tank.turret_yaw])
				_check(abs(_tank.camera_pitch - _tank.gun_pitch) < 0.01,
					"退出炮镜：camera_pitch=gun_pitch (cam=%.2f gun=%.2f)" % [_tank.camera_pitch, _tank.gun_pitch])
				_finish()
				return false
	return false

func _finish() -> void:
	_done = true
	print("\n=== 汇总: failed=%d ===" % _failed)
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
