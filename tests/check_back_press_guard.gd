extends SceneTree
## 校验：手机端系统返回键防误触（连续两次返回才触发暂停/主菜单逻辑）
## 1. 手机端（存在 mobile 控件）：单次返回不触发暂停菜单，仅显示提示
## 2. 窗口内第二次返回触发暂停菜单，提示清除
## 3. 暂停菜单已打开时：单次返回直接关闭菜单（逆向操作不拦截）
## 4. 超出窗口的按键不与先前的按键构成双击（重新记为第一次）
## 5. 桌面端（无 mobile 控件）：单次 ESC 仍直接触发暂停菜单

var _failed := 0
var _frame := 0
var _done := false
var _main: Node = null
var _mobile: Node = null
var _step := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

func _press_esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	_main._input(ev)

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _main == null:
		_main = current_scene
		return false
	if _frame < 8:
		return false  # 等 main._ready 完成初始化
	match _step:
		0:  # 注入 mobile 节点，模拟手机模式
			if _mobile == null:
				_mobile = CanvasLayer.new()
				_mobile.name = "MobileControlsGuardTest"
				_mobile.set_script(load("res://scripts/ui/mobile_controls.gd"))
				_mobile.add_to_group("mobile_controls")
				root.add_child(_mobile)
			var ml: Node = _main._get_mobile_controls()
			_check(ml != null, "注入 mobile 控件成功（手机模式）")
			_check(_main._back_hint_label == null, "初始无返回提示")
			_step = 1
		1:  # 单次返回：不触发暂停，仅出现提示
			_press_esc()
			_check(_main._pause_menu == null, "单次返回不触发暂停菜单（防误触生效）")
			_check(_main._back_hint_label != null, "首次返回显示「再按一次返回」提示")
			_step = 2
		2:  # 窗口内第二次返回：触发暂停菜单，提示清除
			_press_esc()
			_check(_main._pause_menu != null, "窗口内第二次返回触发暂停菜单")
			_check(_main._back_hint_label == null, "触发后提示已清除")
			_main._close_pause_menu()
			_step = 3
		3:  # 暂停菜单已打开时：单次返回直接关闭（不拦截逆向操作）
			_main._open_pause_menu()
			_check(_main._pause_menu != null, "暂停菜单已重新打开")
			_press_esc()
			_check(_main._pause_menu == null, "暂停菜单打开时单次返回直接关闭")
			_step = 4
		4:  # 超时重置：超出窗口的按键不构成双击
			_press_esc()
			_check(_main._pause_menu == null, "超时前第一次按：仍不触发（提示）")
			_main._last_back_press_ms = Time.get_ticks_msec() - 5000  # 模拟超过 2s 窗口
			_press_esc()
			_check(_main._pause_menu == null, "超出窗口后按键不构成双击（未触发）")
			_check(_main._back_hint_label != null, "超时后重新显示提示（重新记为第一次）")
			_press_esc()  # 立即再按（窗口内）→ 应双击触发
			_check(_main._pause_menu != null, "窗口内连按仍可触发暂停菜单")
			_main._close_pause_menu()
			_step = 5
		5:  # 切换到桌面模式：移除 mobile 节点
			if _mobile != null:
				_mobile.free()
				_mobile = null
			_step = 6
		6:  # 桌面端：单次 ESC 直接触发
			_check(_main._get_mobile_controls() == null, "mobile 控件已移除（桌面模式）")
			_press_esc()
			_check(_main._pause_menu != null, "桌面端单次 ESC 直接打开暂停菜单（不受防误触影响）")
			_main._close_pause_menu()
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