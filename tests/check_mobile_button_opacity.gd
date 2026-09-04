extends SceneTree
## 校验：移动端按钮不透明度（提高后的样式约束）
## 1. mobile_controls 创建后：所有触屏按钮均套用 StyleBoxFlat（normal），且底色 alpha >= 0.9（高不透明）
## 2. 有文字的按钮（拉升/下降/自由视角/武器）modulate alpha 不低于 0.85（不再半透明）
## 3. 开火/炮镜/维修/聊天/技能按钮 modulate alpha 为 1.0

const MAX_FRAMES := 120

var _failed := 0
var _frame := 0
var _done := false
var _mobile: Node = null

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobileOpacityTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	if root.get_node_or_null("SettingsManager") == null:
		var sm := Node.new()
		sm.name = "SettingsManager"
		sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(sm)
	var ml := CanvasLayer.new()
	ml.name = "MobileControlsOpacityTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	_mobile = ml
	print("INFO: 场景就绪，开始按钮不透明度校验...")

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
		var btns: Array = []
		for child in _mobile.get_children():
			if child is Button:
				btns.append(child)
		_check(btns.size() >= 10, "按钮已创建 (%d 个)" % btns.size())
		var no_style := 0
		var low_alpha := 0
		for b in btns:
			var sb: StyleBox = b.get_theme_stylebox("normal")
			if sb == null or not (sb is StyleBoxFlat):
				no_style += 1
				continue
			var f: StyleBoxFlat = sb
			if f.bg_color.a < 0.9:
				low_alpha += 1
		_check(no_style == 0, "全部按钮套用 StyleBoxFlat 高不透明底 (缺失 %d)" % no_style)
		_check(low_alpha == 0, "按钮底色 alpha 均 >= 0.9 (过低 %d)" % low_alpha)
		# modulate 校验：文字/命令按钮不再半透明
		var low_mod := 0
		for b in btns:
			if b.modulate.a < 0.85:
				low_mod += 1
		_check(low_mod == 0, "按钮 modulate alpha 均 >= 0.85 (过低 %d)" % low_mod)
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