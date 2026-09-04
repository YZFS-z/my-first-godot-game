extends SceneTree
## 校验：移动端飞行升降按钮（拉升/下降）
## 1. settings_manager 默认配置注册 pitch_up/pitch_down（含 x_pct/y_pct/width/height/enabled，位置可自定义）
## 2. mobile_controls 创建两按钮且默认隐藏；set_air_buttons_visible 按载具类型显隐
## 3. 按钮位置/尺寸与设置配置一致
## 4. 按钮回调维护 active 标志
## 5. 固定翼：拉升→input_throttle=1，下降→-1；摇杆叠加油门/偏航；拖动引导机头
## 6. 直升机：升降按钮增减 collective（悬停中先退出悬停再调整）；摇杆/拖动同固定翼

const MAX_FRAMES := 240

var _failed := 0
var _frame := 0
var _phase := 0
var _mobile: Node = null
var _airplane: Node = null
var _heli: Node = null
var _sm: Node = null
var _done := false
var _yaw0 := 0.0
var _pitch0 := 0.0

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
	ml.name = "MobileControlsTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	return ml

func _spawn_vehicle(scene_path: String, json_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = false
	v.team = 1
	root.add_child(v)
	v.setup_from_data(_load_json(json_path))
	return v

func _find_btn(text: String) -> Button:
	for child in _mobile.get_children():
		if child is Button and child.text == text:
			return child
	return null

func _initialize() -> void:
	# --script 模式下没有 current_scene，挂一个假场景节点
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobileAirTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面（物理结算需要）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	# SettingsManager：-s 主脚本编译期无法解析 autoload 名，改用节点动态访问
	_sm = root.get_node_or_null("SettingsManager")
	if _sm == null:
		_sm = Node.new()
		_sm.name = "SettingsManager"
		_sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(_sm)
	_mobile = _spawn_mobile()
	print("INFO: 移动端控件已生成，先校验默认状态（载具未出生）...")
	_phase = 0

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES * 4:
		print("FAIL: 测试全局超时")
		_finish()
		return false
	match _phase:
		0:
			# 等 mobile 进树完成 _ready，此时尚无载具 → 升降按钮应隐藏
			if _mobile.is_inside_tree() and _frame > 8:
				_check_default_hidden()
				# 载具此时出生：_ready 会调 set_air_buttons_visible(true) 显示按钮
				_airplane = _spawn_vehicle("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json")
				_heli = _spawn_vehicle("res://scenes/helicopter.tscn", "res://data/vehicles/heli_ah64.json")
				print("INFO: 固定翼/直升机已生成（玩家控制），进入输入校验...")
				_phase = 1
				_frame = 0
		1:
			# 等所有节点进树并完成 _ready
			if _airplane.is_inside_tree() and _heli.is_inside_tree() and _frame > 8:
				_airplane.global_position = Vector3(0, 60, 0)
				_heli.global_position = Vector3(0, 40, 0)
				_phase = 2
				_frame = 0
		2:
			if _frame >= 8:
				_check_ui_config()
				# 固定翼：拉升按住
				_mobile.pitch_up_active = true
				_phase = 3
				_frame = 0
		3:
			if _frame >= 3:
				_check(_airplane.input_throttle == 1.0, "固定翼：拉升按住→油门1.0 (%.2f)" % _airplane.input_throttle)
				_mobile.pitch_up_active = false
				_mobile.pitch_down_active = true
				_phase = 4
				_frame = 0
		4:
			if _frame >= 3:
				_check(_airplane.input_throttle == -1.0, "固定翼：下降按住→油门-1.0 (%.2f)" % _airplane.input_throttle)
				_mobile.pitch_down_active = false
				_mobile.joystick_y = 0.5
				_phase = 5
				_frame = 0
		5:
			if _frame >= 3:
				_check(abs(_airplane.input_throttle - 0.5) < 0.01, "固定翼：摇杆前推→油门0.5 (%.2f)" % _airplane.input_throttle)
				_mobile.joystick_y = 0.0
				_mobile.joystick_x = 0.4
				_phase = 6
				_frame = 0
		6:
			if _frame >= 3:
				_check(abs(_airplane.input_yaw - 0.4) < 0.01, "固定翼：摇杆横推→偏航0.4 (%.2f)" % _airplane.input_yaw)
				_mobile.joystick_x = 0.0
				# 隔离消费者：让直升机退出玩家控制，避免它抢先消费 look_delta
				_heli.is_player_controlled = false
				_yaw0 = _airplane.target_yaw
				_pitch0 = _airplane.target_pitch
				_phase = 7
				_frame = 0
		7:
			# 模拟手指按住持续拖动：真实拖拽中 look_delta 每帧被 drag 事件刷新
			_mobile.look_delta = Vector2(10, 6)
			if _frame >= 3:
				_check(_airplane.target_yaw < _yaw0 - 0.02 and _airplane.target_pitch < _pitch0 - 0.02, "固定翼：屏幕拖动→机头右转+下压 (yaw %.3f→%.3f pitch %.3f→%.3f)" % [_yaw0, _airplane.target_yaw, _pitch0, _airplane.target_pitch])
				# ── 直升机升降按钮 ──
				_mobile.look_delta = Vector2.ZERO
				_heli.is_player_controlled = true
				_yaw0 = _heli.collective
				_mobile.pitch_up_active = true
				_phase = 8
				_frame = 0
		8:
			if _frame >= 8:
				_check(_heli.collective > _yaw0 + 0.01, "直升机：拉升按住→总距增加 (%.3f→%.3f)" % [_yaw0, _heli.collective])
				_mobile.pitch_up_active = false
				_yaw0 = _heli.collective
				_mobile.pitch_down_active = true
				_phase = 9
				_frame = 0
		9:
			if _frame >= 8:
				_check(_heli.collective < _yaw0 - 0.01, "直升机：下降按住→总距减小 (%.3f→%.3f)" % [_yaw0, _heli.collective])
				_mobile.pitch_down_active = false
				_mobile.joystick_y = 0.5
				_phase = 10
				_frame = 0
		10:
			if _frame >= 3:
				_check(abs(_heli.input_pitch - 0.5) < 0.01, "直升机：摇杆前推→俯仰输入0.5 (%.2f)" % _heli.input_pitch)
				_mobile.joystick_y = 0.0
				_mobile.joystick_x = -0.4
				_phase = 11
				_frame = 0
		11:
			if _frame >= 3:
				_check(abs(_heli.input_yaw - -0.4) < 0.01, "直升机：摇杆横推→偏航输入-0.4 (%.2f)" % _heli.input_yaw)
				_mobile.joystick_x = 0.0
				# 隔离消费者：让固定翼退出玩家控制，避免它抢先消费 look_delta
				_airplane.is_player_controlled = false
				_yaw0 = _heli.target_yaw
				_pitch0 = _heli.target_pitch
				_phase = 12
				_frame = 0
		12:
			# 模拟手指按住持续拖动：真实拖拽中 look_delta 每帧被 drag 事件刷新
			_mobile.look_delta = Vector2(10, 6)
			if _frame >= 3:
				_check(_heli.target_yaw < _yaw0 - 0.02 and _heli.target_pitch < _pitch0 - 0.02, "直升机：屏幕拖动→机头引导 (yaw %.3f→%.3f pitch %.3f→%.3f)" % [_yaw0, _heli.target_yaw, _pitch0, _heli.target_pitch])
				# ── 悬停中按升降 → 先退出悬停再调整总距 ──
				_heli.global_position.y = 40.0
				_heli.velocity = Vector3.ZERO
				_heli._toggle_hover()
				_check(_heli.hover_active, "直升机：空中激活悬停（前置条件）")
				_yaw0 = _heli.collective
				_mobile.pitch_up_active = true
				_phase = 13
				_frame = 0
		13:
			if _frame >= 6:
				_check(not _heli.hover_active, "直升机：悬停中按拉升→退出悬停")
				_check(_heli.collective > _yaw0 + 0.01, "直升机：退出悬停后拉升→总距增加 (%.3f→%.3f)" % [_yaw0, _heli.collective])
				_mobile.pitch_up_active = false
				_finish()
	return false

func _check_default_hidden() -> void:
	var up_btn: Button = _find_btn("拉升")
	var down_btn: Button = _find_btn("下降")
	_check(up_btn != null and down_btn != null, "移动端：拉升/下降按钮已创建")
	if up_btn == null or down_btn == null:
		_done = true
		quit(1)
		return
	_check(not up_btn.visible and not down_btn.visible, "移动端：默认隐藏（未上飞机时）")

func _check_ui_config() -> void:
	# 1. 设置配置注册（位置可自定义的字段齐备）
	var btns: Dictionary = _sm.get_touch_buttons()
	for key in ["pitch_up", "pitch_down"]:
		_check(btns.has(key), "设置：%s 已注册默认配置" % key)
		var cfg: Dictionary = btns[key]
		_check(cfg.has("enabled") and cfg.has("x_pct") and cfg.has("y_pct") and cfg.has("width") and cfg.has("height") and cfg.has("label"), "设置：%s 含位置/尺寸/启停字段" % key)
	_check(btns.pitch_up.y_pct < btns.pitch_down.y_pct, "设置：拉升在下降上方")
	# 2. 按钮已创建并被载具显示（_ready 已调 set_air_buttons_visible(true)）
	var up_btn: Button = _find_btn("拉升")
	var down_btn: Button = _find_btn("下降")
	_check(up_btn != null and down_btn != null, "移动端：拉升/下降按钮存在")
	_check(up_btn.visible and down_btn.visible, "移动端：飞机出生后按钮显示")
	# 3. 位置/尺寸与配置一致
	var vps: Vector2 = _mobile.get_viewport().get_visible_rect().size
	var up_cfg: Dictionary = btns.pitch_up
	var down_cfg: Dictionary = btns.pitch_down
	_check(abs(up_btn.position.x - up_cfg.x_pct * vps.x) < 1.0 and abs(up_btn.position.y - up_cfg.y_pct * vps.y) < 1.0, "移动端：拉升位置与配置一致 (%.0f,%.0f)" % [up_btn.position.x, up_btn.position.y])
	_check(abs(down_btn.position.x - down_cfg.x_pct * vps.x) < 1.0 and abs(down_btn.position.y - down_cfg.y_pct * vps.y) < 1.0, "移动端：下降位置与配置一致 (%.0f,%.0f)" % [down_btn.position.x, down_btn.position.y])
	_check(up_btn.size.is_equal_approx(Vector2(up_cfg.width, up_cfg.height)), "移动端：拉升尺寸与配置一致")
	# 4. 显隐控制
	_mobile.set_air_buttons_visible(false)
	_check(not up_btn.visible and not down_btn.visible, "移动端：set_air_buttons_visible(false)→隐藏")
	_mobile.set_air_buttons_visible(true)
	_check(up_btn.visible and down_btn.visible, "移动端：set_air_buttons_visible(true)→显示")
	# 5. 回调维护 active
	_mobile._on_pitch_up_down()
	_check(_mobile.pitch_up_active, "移动端：拉升按下→active=true")
	_mobile._on_pitch_up_up()
	_check(not _mobile.pitch_up_active, "移动端：拉升松开→active=false")
	_mobile._on_pitch_down_down()
	_check(_mobile.pitch_down_active, "移动端：下降按下→active=true")
	_mobile._on_pitch_down_up()
	_check(not _mobile.pitch_down_active, "移动端：下降松开→active=false")

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)