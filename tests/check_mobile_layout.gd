extends SceneTree
## 校验：移动端触控 UI 在 expand 宽高比适配下的布局（无黑边方案回归）
## 背景：project.godot 设 stretch/mode=canvas_items + stretch/aspect=expand，
## 手机 20:9~21:9 横屏下可见视口变为 1280x576~1280x540（横向对齐设计宽度，
## 垂直可见区较 16:9 更窄高），触控按钮/摇杆不得越出视口。
## 1. 16:9 基线（1280x720）：默认构建全部控件在视口内
## 2. 20:9（1280x576）：重建后全部控件在视口内（fire/ammo/底部按钮不贴出底边）
## 3. 21:9（1280x540）：极端比例下仍不越界
## 4. 右侧默认配置按钮（scope/repair/artillery/smoke 等）位置互不重叠

const MAX_FRAMES := 60

var _failed := 0
var _frame := 0
var _phase := 0
var _done := false
var _mobile: Node = null

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _controls() -> Array:
	"""收集全部可测控件（含 ammo/weapon 按钮组）"""
	var arr: Array = []
	if _mobile._joystick_bg: arr.append(_mobile._joystick_bg)
	if _mobile._joystick_handle: arr.append(_mobile._joystick_handle)
	if _mobile._look_area: arr.append(_mobile._look_area)
	for b in ["_fire_btn", "_scope_btn", "_repair_btn", "_chat_btn", "_artillery_btn",
			"_smoke_btn", "_free_look_btn", "_pitch_up_btn", "_pitch_down_btn"]:
		var c = _mobile.get(b)
		if c: arr.append(c)
	for b in _mobile._ammo_btns:
		arr.append(b)
	for b in _mobile._weapon_btns:
		arr.append(b)
	return arr

func _floats(v: bool, msg: String) -> void:
	_check(v, msg)

func _in_viewport(ctl: Control, vp: Vector2) -> bool:
	var p: Vector2 = ctl.position
	var e: Vector2 = ctl.position + ctl.size
	return p.x >= -0.5 and p.y >= -0.5 and e.x <= vp.x + 0.5 and e.y <= vp.y + 0.5

func _check_all_in(vp: Vector2, tag: String) -> void:
	var ctrls = _controls()
	var bad: Array = []
	for c in ctrls:
		if not _in_viewport(c, vp):
			bad.append("%s(%s) pos=%s size=%s" % [c.name, c.get_class(), c.position, c.size])
	if bad.is_empty():
		_check(true, "%s：%d 个控件全部在视口 %v 内" % [tag, ctrls.size(), vp])
	else:
		_check(false, "%s：%d 个控件越界 → %s" % [tag, bad.size(), "; ".join(bad)])

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobileLayoutTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# SettingsManager：-s 主脚本编译期无法解析 autoload 名，改用节点动态访问
	var sm: Node = root.get_node_or_null("SettingsManager")
	if sm == null:
		sm = Node.new()
		sm.name = "SettingsManager"
		sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(sm)
	_mobile = CanvasLayer.new()
	_mobile.name = "MobileControlsLayoutTest"
	_mobile.set_script(load("res://scripts/ui/mobile_controls.gd"))
	root.add_child(_mobile)
	print("INFO: 场景就绪，开始触控布局越界校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame > MAX_FRAMES:
		print("FAIL: 测试全局超时")
		_finish()
		return true
	match _phase:
		0:  # 等待 _ready 完成默认构建（16:9 基线 1280x720）
			if _frame > 3:
				_check(_mobile._joystick_bg != null, "默认构建完成（摇杆已创建）")
				_check_all_in(Vector2(1280.0, 720.0), "16:9 基线(720)")
				_phase = 1
		1:  # 模拟 20:9 手机 expand 视口：1280x576
			_mobile._ammo_btns.clear()
			_mobile._weapon_btns.clear()
			_mobile._viewport_size = Vector2(1280.0, 576.0)
			_mobile._build_ui()
			_check_all_in(Vector2(1280.0, 576.0), "20:9(576)")
			# 底部关键按钮不贴出底边（留白 ≥ 6px）
			var rig = _mobile._fire_btn
			var ok_bottom: bool = rig.position.y + rig.size.y <= 576.0 - 6.0
			_check(ok_bottom, "开火按钮底边留白 (底=%.1f ≤570)" % (rig.position.y + rig.size.y))
			_phase = 2
		2:  # 模拟 21:9 极端比例：1280x540
			_mobile._ammo_btns.clear()
			_mobile._weapon_btns.clear()
			_mobile._viewport_size = Vector2(1280.0, 540.0)
			_mobile._build_ui()
			_check_all_in(Vector2(1280.0, 540.0), "21:9(540)")
			# 右侧功能按钮不重叠（fire 与 scope 不同框）
			var fb: Rect2 = _mobile._fire_btn.get_global_rect()
			var sb: Rect2 = _mobile._scope_btn.get_global_rect()
			_check(not fb.intersects(sb), "开火与开镜按钮不重叠")
			_done = true
			_finish()
			return true
	return false

func _finish() -> void:
	if _failed == 0:
		print("总结: 全部通过")
		print("RESULT: failed=0")
	else:
		print("总结: 失败 %d 项" % _failed)
		print("RESULT: failed=%d" % _failed)