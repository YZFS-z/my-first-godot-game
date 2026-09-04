extends SceneTree
## 校验：暂停状态下打开设置界面，设置应显示在暂停菜单之上
## 校验点：
##  1. 设置对话框父节点 = hud_layer（与暂停菜单同画布，z_index 才能生效）
##  2. 设置 z_index > 暂停菜单 z_index
##  3. 非暂停打开设置（root 直挂）行为不被破坏：暂停状态下修复仅影响 _on_pause_settings

var _failed := 0
var _frame := 0
var _main: Node = null
var _hud_layer: CanvasLayer = null
var _done := false

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _physics_process(delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _main == null:
		_main = current_scene
		return false
	# 场景就绪：等待 5 帧让 main._ready 完成初始化
	if _frame < 8:
		return false
	if not _hud_layer:
		_hud_layer = _main.get_node_or_null("HUD") as CanvasLayer
		_check(_hud_layer != null, "找到 HUD CanvasLayer")
		if _hud_layer == null:
			_finish()
			return false
		# 模拟玩家按 Esc 打开暂停菜单
		_main._open_pause_menu()
		_check(_main._is_paused, "暂停菜单已打开")
		var pause_menu = _main._pause_menu
		_check(pause_menu != null, "暂停菜单节点存在")
		_check(pause_menu.get_parent() == _hud_layer, "暂停菜单挂在 HUD 层")
		# 模拟点击"设置"
		_main._on_pause_settings()
		# 找到刚打开的设置对话框（HUD 层最后加入的子节点）
		var dlg: Control = null
		for child in _hud_layer.get_children():
			if child is Control and child.name == "SettingsDialog":
				dlg = child
		_check(dlg != null, "设置对话框存在")
		if dlg:
			_check(dlg.get_parent() == _hud_layer, "设置对话框挂到 HUD 层（与暂停菜单同画布）")
			_check(dlg is Control and dlg.z_index > pause_menu.z_index,
				"设置 z_index(%d) > 暂停菜单 z_index(%d)，设置显示在上层" % [dlg.z_index, pause_menu.z_index])
			# 兄弟顺序（后 add 的在 Godot Control 中默认后绘制；z_index 相同时后者在上，z_index 不同时先比 z_index）
			# 验证设置对话框兄弟索引在暂停菜单之后（同层绘制顺序更靠后）
			var idx_pause = pause_menu.get_index()
			var idx_dlg = dlg.get_index()
			_check(idx_dlg > idx_pause, "设置对话框绘制顺序在暂停菜单之后 (%d > %d)" % [idx_dlg, idx_pause])
			# 关闭设置，不应影响暂停状态
			dlg.queue_free()
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