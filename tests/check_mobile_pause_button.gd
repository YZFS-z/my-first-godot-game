extends SceneTree
## 校验：移动端退出/暂停按钮（等效桌面端 ESC；位置可自定义）
## 1. SettingsManager 默认配置包含 "pause"（label=退出, enabled=true, 位置/大小可调字段齐全）
## 2. mobile_controls 创建"退出"按钮，位置/大小读取自配置
## 3. 修改配置后 _apply_touch_config 能更新按钮位置/大小（设置面板自定义生效）
## 4. 点击按钮发出 pause_pressed 信号（main.gd 已连接为与 ESC 相同分支）

const MAX_FRAMES := 120

var _failed := 0
var _frame := 0
var _done := false
var _mobile: Node = null
var _sm: Node = null
var _pause_signal_count := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobilePauseTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# SettingsManager：-s 主脚本编译期无法解析 autoload 名，改用节点动态访问
	_sm = root.get_node_or_null("SettingsManager")
	if _sm == null:
		_sm = Node.new()
		_sm.name = "SettingsManager"
		_sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(_sm)
	var ml := CanvasLayer.new()
	ml.name = "MobileControlsPauseTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	_mobile = ml
	_mobile.pause_pressed.connect(func(): _pause_signal_count += 1)
	print("INFO: 场景就绪，开始退出按钮校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES:
		print("FAIL: 测试全局超时")
		_finish()
		return false
	if _frame < 10:
		return false  # 等 _ready 完成 _build_ui
	if _frame == 10:
		# 1. 默认配置
		var cfg: Dictionary = _sm.get_touch_buttons()
		_check(cfg.has("pause"), "触摸按钮默认配置包含 pause")
		var pc: Dictionary = cfg.get("pause", {})
		_check(pc.get("label", "") == "退出", "pause 按钮标签为「退出」")
		_check(pc.get("enabled", false) == true, "pause 按钮默认启用")
		_check(pc.has("x_pct") and pc.has("y_pct") and pc.has("width") and pc.has("height"),
			"pause 配置含位置/大小字段（可自定义）")
		# 2. 界面按钮
		var pause_btn: Button = null
		for child in _mobile.get_children():
			if child is Button and child.text == "退出":
				pause_btn = child
		_check(pause_btn != null, "移动端界面创建「退出」按钮")
		if pause_btn:
			var vp: Vector2 = _mobile._viewport_size
			var expect_pos := Vector2(float(pc.get("x_pct", 0.0)) * vp.x, float(pc.get("y_pct", 0.0)) * vp.y)
			_check(pause_btn.position.distance_to(expect_pos) < 0.5,
				"按钮位置取自配置 (pos=%s, 预期≈%s)" % [str(pause_btn.position), str(expect_pos)])
			_check(pause_btn.size == Vector2(float(pc.get("width", 50)), float(pc.get("height", 50))),
				"按钮大小取自配置 (%s)" % str(pause_btn.size))
			# 3. 自定义位置/大小（模拟设置面板保存后重新应用）
			var new_cfg := {
				"enabled": true, "action": "pause", "label": "退出",
				"x_pct": 0.90, "y_pct": 0.08, "width": 80, "height": 52,
			}
			_sm.set_touch_button("pause", new_cfg)
			_mobile._apply_touch_config(pause_btn, "pause")
			_check(pause_btn.position.distance_to(Vector2(0.90 * vp.x, 0.08 * vp.y)) < 0.5,
				"自定义 X/Y 百分比生效 (pos=%s)" % str(pause_btn.position))
			_check(pause_btn.size == Vector2(80, 52), "自定义宽高生效 (%s)" % str(pause_btn.size))
			# 4. 点击按钮 → pause_pressed 信号
			pause_btn.pressed.emit()
			_check(_pause_signal_count == 1, "点击「退出」发出 pause_pressed 信号")
		_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("总结: 全部通过")
		quit(0)
	else:
		print("总结: 失败 %d 项" % _failed)
		quit(1)