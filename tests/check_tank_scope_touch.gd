extends SceneTree
## 校验：坦克开镜（炮镜）时移动端拖拽视角方向与未开镜一致
## 背景：mobile.look_delta 为屏幕手势单帧位移（屏幕 y 向下为正：手下滑=+y）。
## 坦克与飞机一致：mouse_gun_delta -= look_delta.y*0.3（手下滑→gun_pitch减小→下俯）；
## 开镜与未开镜同向（手下滑→gun_pitch 减小→下俯）；水平方向三处一致（-=）。
## 1. 开镜信号连接与切换正常
## 2. 未开镜基线：手下滑→camera_pitch 减小；手右滑→camera_yaw 减小
## 3. 开镜：手下滑→gun_pitch 减小（与未开镜同向）；相机俯仰与炮管同步
## 4. 开镜：手上滑→gun_pitch 增大（反向仍一致）
## 5. 开镜：手右滑→turret_yaw 减小（水平方向与未开镜同向）

const MAX_FRAMES := 300

var _failed := 0
var _frame := 0
var _phase := 0
var _done := false
var _mobile: Node = null
var _tank: Node = null
var _p0 := 0.0
var _y0 := 0.0
var _g0 := 0.0
var _t0 := 0.0

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

func _spawn_mobile() -> Node:
	var ml := CanvasLayer.new()
	ml.name = "MobileControlsScopeTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	return ml

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeTankScopeTouchTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面（物理结算需要，坦克防下沉）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	# SettingsManager：-s 主脚本编译期无法解析 autoload 名，改用节点动态访问
	if root.get_node_or_null("SettingsManager") == null:
		var sm := Node.new()
		sm.name = "SettingsManager"
		sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(sm)
	_mobile = _spawn_mobile()
	print("INFO: 场景就绪，开始坦克开镜拖拽方向校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES:
		_failed += 1
		print("FAIL: 测试全局超时")
		_finish()
		return false
	match _phase:
		0:
			# 等 mobile 入树；初始未开镜
			if _mobile.is_inside_tree() and _frame > 8:
				_check(_tank == null or not _tank.is_scope_mode, "初始状态：未开镜")
				# 生成玩家坦克并加载数据（_ready 连接 mobile 信号）
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
			# 等 _ready(含延迟重连) 与 setup 完成
			if _frame > 10:
				_check(_tank.camera_pitch == 0.0 and _tank.camera_yaw == 0.0, "基线：俯仰/偏航为0 (%.2f/%.2f)" % [_tank.camera_pitch, _tank.camera_yaw])
				# 未开镜：手下滑（+y）
				_p0 = _tank.camera_pitch
				_y0 = _tank.camera_yaw
				_phase = 2
				_frame = 0
		2:
			# 每帧注入持续拖拽（手下滑）；先模拟触摸按住，避免 mobile._process idle 清零
			_mobile._look_touch_id = 99
			_mobile.look_delta = Vector2(0.0, 20.0)
			if _frame >= 8:
				_check(_tank.camera_pitch < _p0 - 0.5, "未开镜：手下滑→视角下俯 (%.2f→%.2f)" % [_p0, _tank.camera_pitch])
				_mobile.look_delta = Vector2.ZERO
				_p0 = _tank.camera_pitch
				_y0 = _tank.camera_yaw
				_phase = 3
				_frame = 0
		3:
			# 未开镜：手右滑（+x）
			_mobile.look_delta = Vector2(20.0, 0.0)
			if _frame >= 8:
				_mobile._look_touch_id = -1
				_check(_tank.camera_yaw < _y0 - 1.0, "未开镜：手右滑→视角左转 (%.2f→%.2f)" % [_y0, _tank.camera_yaw])
				_mobile.look_delta = Vector2.ZERO
				# 通过移动端信号开镜（真实链路）
				if _mobile.scope_toggled.is_connected(Callable(_tank, "_toggle_scope")):
					_mobile.scope_toggled.emit()
				else:
					_check(false, "开镜信号未连接到坦克")
				_phase = 4
				_frame = 0
		4:
			if _frame >= 4:
				_check(_tank.is_scope_mode, "开镜：scope_toggled 信号→进入炮镜模式")
				_g0 = _tank.gun_pitch
				_check(abs(_tank.camera_pitch - _tank.gun_pitch) < 0.01, "开镜：相机俯仰与炮管同步 (cam=%.2f gun=%.2f)" % [_tank.camera_pitch, _tank.gun_pitch])
				_check(abs(_tank.camera_yaw - (_tank.turret_yaw + rad_to_deg(_tank.rotation.y))) < 0.01, "开镜：相机偏航=炮塔+车体")
				_phase = 5
				_frame = 0
		5:
			# 开镜：手下滑（+y）——核心修复断言
			_mobile._look_touch_id = 99
			_mobile.look_delta = Vector2(0.0, 20.0)
			if _frame >= 8:
				_check(_tank.gun_pitch < _g0 - 0.5, "开镜：手下滑→炮口下俯（与未开镜同向）(%.2f→%.2f)" % [_g0, _tank.gun_pitch])
				_mobile.look_delta = Vector2.ZERO
				_g0 = _tank.gun_pitch
				_phase = 6
				_frame = 0
		6:
			# 开镜：手上滑（-y）
			_mobile.look_delta = Vector2(0.0, -20.0)
			if _frame >= 8:
				_check(_tank.gun_pitch > _g0 + 0.15, "开镜：手上滑→炮口上仰（反向一致）(%.2f→%.2f)" % [_g0, _tank.gun_pitch])
				_mobile._look_touch_id = -1
				_mobile.look_delta = Vector2.ZERO
				_t0 = _tank.turret_yaw
				_phase = 7
				_frame = 0
		7:
			# 开镜：手右滑（+x）
			_mobile._look_touch_id = 99
			_mobile.look_delta = Vector2(20.0, 0.0)
			if _frame >= 8:
				_check(_tank.turret_yaw < _t0 - 0.2, "开镜：手右滑→炮塔左转（与未开镜水平同向）(%.2f→%.2f)" % [_t0, _tank.turret_yaw])
				_mobile.look_delta = Vector2.ZERO
				_mobile._look_touch_id = -1
				_finish()
				return false
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("总结: 全部通过")
		print("RESULT: failed=0")
		quit(0)
	else:
		print("总结: 失败 %d 项" % _failed)
		print("RESULT: failed=%d" % _failed)
		quit(1)