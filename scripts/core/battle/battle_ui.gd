extends Node
## 战斗UI管理器 - 负责暂停菜单、胜负面板、输入处理、返回键防误触
## 作为 Main 节点的子节点，通过 get_parent() 访问共享状态

const BACK_PRESS_WINDOW_MS: int = 2000

var _pause_menu: Control = null
var _is_paused: bool = false
var _last_back_press_ms: int = -100000
var _back_hint_label: Label = null

func _get_main() -> Node:
	return get_parent()

func _get_hud_layer() -> CanvasLayer:
	return _get_main().hud_layer

func process_back_hint() -> void:
	"""每帧调用，检查返回键防误触提示是否超时"""
	if _back_hint_label != null and Time.get_ticks_msec() - _last_back_press_ms > BACK_PRESS_WINDOW_MS:
		_hide_back_press_hint()

func handle_input(event: InputEvent) -> void:
	"""由 main._input 转发，处理 ESC 键和返回键"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			var main = _get_main()
			if main._get_mobile_controls() != null and _pause_menu == null:
				var now_ms := Time.get_ticks_msec()
				if now_ms - _last_back_press_ms > BACK_PRESS_WINDOW_MS:
					_last_back_press_ms = now_ms
					_show_back_press_hint()
					return
				_last_back_press_ms = -100000
				_hide_back_press_hint()
			if main.game_ended:
				_on_pause_main_menu()
				return
			toggle_pause_menu()

func _show_back_press_hint() -> void:
	if _back_hint_label == null:
		var hud_layer = _get_hud_layer()
		if not hud_layer:
			return
		_back_hint_label = Label.new()
		_back_hint_label.name = "BackPressHint"
		_back_hint_label.text = "再按一次返回键退出"
		_back_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_back_hint_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_back_hint_label.offset_top = 330
		_back_hint_label.add_theme_font_size_override("font_size", 20)
		_back_hint_label.modulate = Color(1, 1, 1, 0.9)
		_back_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back_hint_label.z_index = 1500
		_back_hint_label.process_mode = Node.PROCESS_MODE_ALWAYS
		hud_layer.add_child(_back_hint_label)

func _hide_back_press_hint() -> void:
	if _back_hint_label:
		_back_hint_label.queue_free()
		_back_hint_label = null

func toggle_pause_menu() -> void:
	if _pause_menu:
		close_pause_menu()
	else:
		open_pause_menu()

func open_pause_menu() -> void:
	var main = _get_main()
	_is_paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.z_index = 1000
	_get_hud_layer().add_child(_pause_menu)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.add_child(bg)

	var title = Label.new()
	title.text = "游戏暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 180
	title.add_theme_font_size_override("font_size", 42)
	title.modulate = Color(1, 0.9, 0.5)
	_pause_menu.add_child(title)

	var btn_box = VBoxContainer.new()
	btn_box.set_anchors_preset(Control.PRESET_CENTER)
	btn_box.offset_left = -120
	btn_box.offset_right = 120
	btn_box.offset_top = -60
	btn_box.offset_bottom = 120
	btn_box.add_theme_constant_override("separation", 16)
	_pause_menu.add_child(btn_box)

	var resume_btn = Button.new()
	resume_btn.text = "返回游戏"
	resume_btn.custom_minimum_size = Vector2(0, 48)
	resume_btn.add_theme_font_size_override("font_size", 20)
	resume_btn.pressed.connect(close_pause_menu)
	btn_box.add_child(resume_btn)

	var settings_btn = Button.new()
	settings_btn.text = "设置"
	settings_btn.custom_minimum_size = Vector2(0, 48)
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.pressed.connect(_on_pause_settings)
	btn_box.add_child(settings_btn)

	var menu_btn = Button.new()
	menu_btn.text = "返回主菜单"
	menu_btn.custom_minimum_size = Vector2(0, 48)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.modulate = Color(1, 0.6, 0.6)
	menu_btn.pressed.connect(_on_pause_main_menu)
	btn_box.add_child(menu_btn)

func close_pause_menu() -> void:
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null
	_is_paused = false
	get_tree().paused = false
	_last_back_press_ms = -100000
	_hide_back_press_hint()
	var main = _get_main()
	if not main._get_mobile_controls():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_pause_settings() -> void:
	var settings_scene = load("res://scenes/settings.tscn")
	if settings_scene:
		var dlg = settings_scene.instantiate()
		dlg.process_mode = Node.PROCESS_MODE_ALWAYS
		dlg.z_index = 1001
		_get_hud_layer().add_child(dlg)

func _on_pause_main_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func on_mobile_pause() -> void:
	"""移动端暂停按钮回调"""
	var main = _get_main()
	if main.game_ended:
		_on_pause_main_menu()
		return
	toggle_pause_menu()

# === 胜负判定 ===

func on_kill_check_victory(_killer: String, _victim: String, _victim_team: int, _killer_team: int) -> void:
	var main = _get_main()
	if main.game_ended:
		return
	check_victory()

func check_victory() -> void:
	var main = _get_main()
	if main.game_ended or not main.player_tank:
		return
	var player_team = main.player_tank.team
	var enemy_alive = 0
	var friendly_alive = 0
	for child in main.get_children():
		if child and "is_destroyed" in child and "team" in child:
			if child.is_destroyed:
				continue
			if child.team == player_team:
				friendly_alive += 1
			else:
				enemy_alive += 1
	if enemy_alive <= 0:
		main.game_ended = true
		show_victory()
	elif friendly_alive <= 0:
		main.game_ended = true
		show_defeat()

func _create_result_panel(title: String, color: Color) -> Control:
	var panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(0, -200)
	panel.custom_minimum_size = Vector2(400, 160)
	panel.size = Vector2(400, 160)
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)
	var label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 48)
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_bottom = -30
	panel.add_child(label)
	var hint = Label.new()
	hint.text = "按 ESC 返回主菜单"
	hint.add_theme_font_size_override("font_size", 18)
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.offset_top = 100
	panel.add_child(hint)
	_get_hud_layer().add_child(panel)
	var tween = create_tween()
	tween.tween_property(panel, "position:y", 80.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return panel

func show_victory() -> void:
	var main = _get_main()
	GameManager.chat_message.emit("系统", "胜利！敌方全部被摧毁。", 0)
	print("[BattleUI] 胜利！")
	main.victory_panel = _create_result_panel("胜 利", Color(0.3, 1.0, 0.4))

func show_defeat() -> void:
	var main = _get_main()
	GameManager.chat_message.emit("系统", "失败！我方全部被摧毁。", 0)
	print("[BattleUI] 失败")
	main.victory_panel = _create_result_panel("失 败", Color(1.0, 0.3, 0.3))
