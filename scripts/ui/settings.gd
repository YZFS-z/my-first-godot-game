extends Control
## 设置界面脚本

@onready var resolution_option: OptionButton = $Panel/Tabs/Window/ResRow/ResolutionOption
@onready var fullscreen_check: CheckBox = $Panel/Tabs/Window/FullscreenRow/FullscreenCheck
@onready var vsync_check: CheckBox = $Panel/Tabs/Window/VsyncRow/VsyncCheck

@onready var language_option: OptionButton = $Panel/Tabs/Language/LangRow/LanguageOption

@onready var master_slider: HSlider = $Panel/Tabs/Audio/MasterRow/MasterSlider
@onready var master_label: Label = $Panel/Tabs/Audio/MasterRow/MasterLabel
@onready var sfx_slider: HSlider = $Panel/Tabs/Audio/SfxRow/SfxSlider
@onready var sfx_label: Label = $Panel/Tabs/Audio/SfxRow/SfxLabel
@onready var music_slider: HSlider = $Panel/Tabs/Audio/MusicRow/MusicSlider
@onready var music_label: Label = $Panel/Tabs/Audio/MusicRow/MusicLabel

@onready var quality_option: OptionButton = $Panel/Tabs/Graphics/QualityRow/QualityOption
@onready var msaa_option: OptionButton = $Panel/Tabs/Graphics/MsaaRow/MsaaOption
@onready var shadow_check: CheckBox = $Panel/Tabs/Graphics/ShadowRow/ShadowCheck

@onready var mobile_check: CheckBox = $Panel/Tabs/Gameplay/MobileRow/MobileCheck
@onready var crosshair_size_slider: HSlider = $Panel/Tabs/Gameplay/CrosshairSizeRow/CrosshairSizeSlider
@onready var crosshair_size_label: Label = $Panel/Tabs/Gameplay/CrosshairSizeRow/CrosshairSizeLabel
@onready var crosshair_color_picker: ColorPickerButton = $Panel/Tabs/Gameplay/CrosshairColorRow/CrosshairColorPicker
@onready var scope_style_option: OptionButton = $Panel/Tabs/Gameplay/ScopeStyleRow/ScopeStyleOption
@onready var range_font_option: OptionButton = $Panel/Tabs/Gameplay/RangeFontRow/RangeFontOption
@onready var range_color_picker: ColorPickerButton = $Panel/Tabs/Gameplay/RangeColorRow/RangeColorPicker
@onready var auto_aim_check: CheckBox = $Panel/Tabs/Gameplay/AutoAimRow/AutoAimCheck
@onready var ccip_color_picker: ColorPickerButton = $Panel/Tabs/Gameplay/CcipColorRow/CcipColorPicker
@onready var ccip_size_spin: SpinBox = $Panel/Tabs/Gameplay/CcipSizeRow/CcipSizeSpin
@onready var invert_y_check: CheckBox = $Panel/Tabs/Gameplay/InvertYRow/InvertYCheck
@onready var custom_content_check: CheckBox = $Panel/Tabs/Gameplay/CustomContentRow/CustomContentCheck
@onready var background_option: OptionButton = $Panel/Tabs/Gameplay/BackgroundRow/BackgroundOption

@onready var nickname_input: LineEdit = $Panel/Tabs/输入/NicknameRow/NicknameInput
@onready var key_bindings_list: VBoxContainer = $Panel/Tabs/输入/KeyScroll/KeyBindingsList
@onready var reset_keys_button: Button = $Panel/Tabs/输入/ResetKeysRow/ResetKeysButton
@onready var touch_list: VBoxContainer = $Panel/Tabs/触摸/TouchScroll/TouchList
@onready var touch_reset_button: Button = $Panel/Tabs/触摸/TouchResetRow/TouchResetButton
@onready var touch_edit_button: Button = $Panel/Tabs/触摸/TouchResetRow/TouchEditButton
var _layout_editor: Control = null
var _dragging_btn: Button = null
var _drag_offset: Vector2 = Vector2.ZERO

# 网络设置
@onready var server_host_input: LineEdit = $Panel/Tabs/网络/ServerHostRow/ServerHostInput
@onready var server_port_input: LineEdit = $Panel/Tabs/网络/ServerPortRow/ServerPortInput
@onready var lan_port_input: LineEdit = $Panel/Tabs/网络/LanPortRow/LanPortInput

@onready var reset_button: Button = $Panel/BottomRow/ResetButton
@onready var close_button: Button = $Panel/BottomRow/CloseButton
@onready var tabs: TabContainer = $Panel/Tabs

var _suppress_signals: bool = true  # 初始化时抑制信号，避免重复保存


func _ready() -> void:
	# 设置中文Tab标题
	tabs.set_tab_title(0, "窗口")
	tabs.set_tab_title(1, "语言")
	tabs.set_tab_title(2, "声音")
	tabs.set_tab_title(3, "画质")
	tabs.set_tab_title(4, "游戏性")
	tabs.set_tab_title(5, "网络")
	tabs.set_tab_title(6, "输入")
	tabs.set_tab_title(7, "触摸")
	_populate_options()
	_load_current_settings()
	_connect_signals()
	_populate_key_bindings()
	_populate_touch_buttons()
	_suppress_signals = false


func _populate_options() -> void:
	# 分辨率
	resolution_option.clear()
	for res in SettingsManager.RESOLUTIONS:
		resolution_option.add_item("%d x %d" % [res.x, res.y])

	# 语言
	language_option.clear()
	for lang_code in SettingsManager.LANGUAGES.keys():
		language_option.add_item(SettingsManager.LANGUAGES[lang_code])
		language_option.set_item_metadata(language_option.item_count - 1, lang_code)

	# 画质
	quality_option.clear()
	quality_option.add_item("低")
	quality_option.set_item_metadata(quality_option.item_count - 1, "low")
	quality_option.add_item("中")
	quality_option.set_item_metadata(quality_option.item_count - 1, "medium")
	quality_option.add_item("高")
	quality_option.set_item_metadata(quality_option.item_count - 1, "high")
	quality_option.add_item("极致")
	quality_option.set_item_metadata(quality_option.item_count - 1, "ultra")

	# MSAA
	msaa_option.clear()
	msaa_option.add_item("关闭")
	msaa_option.set_item_metadata(msaa_option.item_count - 1, 0)
	msaa_option.add_item("2x")
	msaa_option.set_item_metadata(msaa_option.item_count - 1, 2)
	msaa_option.add_item("4x")
	msaa_option.set_item_metadata(msaa_option.item_count - 1, 4)
	msaa_option.add_item("8x")
	msaa_option.set_item_metadata(msaa_option.item_count - 1, 8)

	# 瞄准镜样式
	scope_style_option.clear()
	for style_id in SettingsManager.SCOPE_STYLES.keys():
		scope_style_option.add_item(SettingsManager.SCOPE_STYLES[style_id])
		scope_style_option.set_item_metadata(scope_style_option.item_count - 1, style_id)
	range_font_option.clear()
	for label in SettingsManager.RANGE_FONT_LABELS:
		range_font_option.add_item(label)

	# 菜单背景
	background_option.clear()
	for bg_id in SettingsManager.MENU_BACKGROUNDS.keys():
		background_option.add_item(SettingsManager.MENU_BACKGROUNDS[bg_id])
		background_option.set_item_metadata(background_option.item_count - 1, bg_id)


func _load_current_settings() -> void:
	_suppress_signals = true

	# 窗口
	resolution_option.select(SettingsManager.get_resolution_index())
	fullscreen_check.button_pressed = SettingsManager.get_setting("window", "fullscreen", false)
	vsync_check.button_pressed = SettingsManager.get_setting("window", "vsync", true)

	# 语言
	var current_lang = SettingsManager.get_setting("language", "current", "zh_CN")
	for i in range(language_option.item_count):
		if language_option.get_item_metadata(i) == current_lang:
			language_option.select(i)
			break

	# 声音
	var master_vol = SettingsManager.get_setting("audio", "master_volume", 80.0)
	if master_slider:
		master_slider.value = master_vol
	if master_label:
		master_label.text = "主音量：%d%%" % int(master_vol)

	var sfx_vol = SettingsManager.get_setting("audio", "sfx_volume", 100.0)
	if sfx_slider:
		sfx_slider.value = sfx_vol
	if sfx_label:
		sfx_label.text = "音效音量：%d%%" % int(sfx_vol)

	var music_vol = SettingsManager.get_setting("audio", "music_volume", 70.0)
	if music_slider:
		music_slider.value = music_vol
	if music_label:
		music_label.text = "音乐音量：%d%%" % int(music_vol)

	# 画质
	var quality = SettingsManager.get_setting("graphics", "quality", "medium")
	for i in range(quality_option.item_count):
		if quality_option.get_item_metadata(i) == quality:
			quality_option.select(i)
			break

	var msaa = SettingsManager.get_setting("graphics", "msaa", 2)
	for i in range(msaa_option.item_count):
		if msaa_option.get_item_metadata(i) == msaa:
			msaa_option.select(i)
			break

	shadow_check.button_pressed = SettingsManager.get_setting("graphics", "shadows", true)

	# 游戏性
	mobile_check.button_pressed = SettingsManager.is_mobile_mode()
	var ch_size = SettingsManager.get_crosshair_size()
	crosshair_size_slider.value = ch_size
	crosshair_size_label.text = "准心大小：%d%%" % int(ch_size * 100)
	crosshair_color_picker.color = SettingsManager.get_crosshair_color()
	var scope_style = SettingsManager.get_scope_style()
	for i in range(scope_style_option.item_count):
		if scope_style_option.get_item_metadata(i) == scope_style:
			scope_style_option.select(i)
			break
	var rf_idx := SettingsManager.get_scope_range_font_size()
	if rf_idx < 0 or rf_idx >= range_font_option.item_count:
		rf_idx = 1  # 旧版字号数值越界，重置为"中"
		SettingsManager.set_scope_range_font_size(rf_idx)
	range_font_option.select(rf_idx)
	range_color_picker.color = SettingsManager.get_scope_range_color()
	auto_aim_check.button_pressed = SettingsManager.is_auto_aim_elevation()
	ccip_color_picker.color = SettingsManager.get_ccip_color()
	ccip_size_spin.value = SettingsManager.get_ccip_size()
	invert_y_check.button_pressed = SettingsManager.is_invert_y()
	custom_content_check.button_pressed = SettingsManager.is_allow_custom_content()
	var bg_id = SettingsManager.get_menu_background()
	for i in range(background_option.item_count):
		if background_option.get_item_metadata(i) == bg_id:
			background_option.select(i)
			break

	# 控制
	nickname_input.text = SettingsManager.get_nickname()

	# 网络
	server_host_input.text = SettingsManager.get_setting("network", "public_server_host", "game.thefeishu.top")
	server_port_input.text = str(SettingsManager.get_setting("network", "public_server_port", 8765))
	lan_port_input.text = str(SettingsManager.get_setting("network", "lan_port", 7777))

	_suppress_signals = false


func _connect_signals() -> void:
	resolution_option.item_selected.connect(_on_resolution_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	language_option.item_selected.connect(_on_language_changed)
	master_slider.value_changed.connect(_on_master_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	quality_option.item_selected.connect(_on_quality_changed)
	msaa_option.item_selected.connect(_on_msaa_changed)
	shadow_check.toggled.connect(_on_shadow_toggled)
	mobile_check.toggled.connect(_on_mobile_toggled)
	crosshair_size_slider.value_changed.connect(_on_crosshair_size_changed)
	crosshair_color_picker.color_changed.connect(_on_crosshair_color_changed)
	scope_style_option.item_selected.connect(_on_scope_style_changed)
	range_font_option.item_selected.connect(_on_range_font_changed)
	range_color_picker.color_changed.connect(_on_range_color_changed)
	auto_aim_check.toggled.connect(_on_auto_aim_toggled)
	ccip_color_picker.color_changed.connect(_on_ccip_color_changed)
	ccip_size_spin.value_changed.connect(_on_ccip_size_changed)
	invert_y_check.toggled.connect(_on_invert_y_toggled)
	custom_content_check.toggled.connect(_on_custom_content_toggled)
	background_option.item_selected.connect(_on_background_changed)
	nickname_input.text_submitted.connect(_on_nickname_submitted)
	nickname_input.focus_exited.connect(_on_nickname_focus_exited)
	server_host_input.focus_exited.connect(_on_server_host_focus_exited)
	server_port_input.focus_exited.connect(_on_server_port_focus_exited)
	lan_port_input.focus_exited.connect(_on_lan_port_focus_exited)
	reset_keys_button.pressed.connect(_on_reset_keys_pressed)
	touch_reset_button.pressed.connect(_on_touch_reset_pressed)
	touch_edit_button.pressed.connect(_on_touch_edit_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)


# ── 窗口设置 ────────────────────────────────────────────

func _on_resolution_changed(index: int) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_resolution(index)


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_fullscreen(enabled)


func _on_vsync_toggled(enabled: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_setting("window", "vsync", enabled)
	SettingsManager.apply_window_settings()


# ── 语言设置 ────────────────────────────────────────────

func _on_language_changed(index: int) -> void:
	if _suppress_signals:
		return
	var lang_code = language_option.get_item_metadata(index)
	SettingsManager.set_language(lang_code)


# ── 声音设置 ────────────────────────────────────────────

func _on_master_volume_changed(value: float) -> void:
	if master_label:
		master_label.text = "主音量：%d%%" % int(value)
	if _suppress_signals:
		return
	SettingsManager.set_master_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	if sfx_label:
		sfx_label.text = "音效音量：%d%%" % int(value)
	if _suppress_signals:
		return
	SettingsManager.set_sfx_volume(value)


func _on_music_volume_changed(value: float) -> void:
	if music_label:
		music_label.text = "音乐音量：%d%%" % int(value)
	if _suppress_signals:
		return
	SettingsManager.set_music_volume(value)


# ── 画质设置 ────────────────────────────────────────────

func _on_quality_changed(index: int) -> void:
	if _suppress_signals:
		return
	var quality = quality_option.get_item_metadata(index)
	SettingsManager.set_quality(quality)
	# 同步MSAA和阴影选项
	_load_current_settings()


func _on_msaa_changed(index: int) -> void:
	if _suppress_signals:
		return
	var msaa = msaa_option.get_item_metadata(index)
	SettingsManager.set_setting("graphics", "msaa", msaa)
	SettingsManager.apply_graphics_settings()


func _on_shadow_toggled(enabled: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_setting("graphics", "shadows", enabled)
	SettingsManager.apply_graphics_settings()


# ── 游戏性设置 ──────────────────────────────────────────

func _on_mobile_toggled(enabled: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_mobile_mode(enabled)


func _on_crosshair_size_changed(value: float) -> void:
	crosshair_size_label.text = "准心大小：%d%%" % int(value * 100)
	if _suppress_signals:
		return
	SettingsManager.set_crosshair_size(value)


func _on_crosshair_color_changed(color: Color) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_crosshair_color(color)


func _on_scope_style_changed(index: int) -> void:
	if _suppress_signals:
		return
	var style = scope_style_option.get_item_metadata(index)
	SettingsManager.set_scope_style(style)

func _on_range_font_changed(index: int) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_scope_range_font_size(index)

func _on_range_color_changed(color: Color) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_scope_range_color(color)

func _on_auto_aim_toggled(checked: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_auto_aim_elevation(checked)

func _on_ccip_color_changed(color: Color) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_ccip_color(color)

func _on_ccip_size_changed(size: float) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_ccip_size(size)

func _on_invert_y_toggled(checked: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_invert_y(checked)

func _on_custom_content_toggled(checked: bool) -> void:
	if _suppress_signals:
		return
	SettingsManager.set_allow_custom_content(checked)
	print("[Settings] 允许自定义内容: ", checked)

func _on_background_changed(index: int) -> void:
	if _suppress_signals:
		return
	var bg_id = background_option.get_item_metadata(index)
	SettingsManager.set_menu_background(bg_id)


# ── 控制设置 ────────────────────────────────────────────

var _rebinding_action: String = ""  # 当前正在重绑定的动作

func _populate_key_bindings() -> void:
	"""生成按键绑定列表"""
	# 清空旧的
	for child in key_bindings_list.get_children():
		child.queue_free()

	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var label = Label.new()
		label.text = SettingsManager.ACTION_DISPLAY_NAMES.get(action, action)
		label.custom_minimum_size = Vector2(140, 0)
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(180, 32)
		btn.add_theme_font_size_override("font_size", 14)
		btn.text = _keycode_to_string(SettingsManager.get_action_keycode(action))
		btn.pressed.connect(func(): _start_rebind(action, btn))
		row.add_child(btn)

		key_bindings_list.add_child(row)

func _keycode_to_string(physical_keycode: int) -> String:
	if physical_keycode == 0:
		return "未绑定"
	var ev = InputEventKey.new()
	ev.physical_keycode = physical_keycode
	return ev.as_text()

func _start_rebind(action: String, btn: Button) -> void:
	_rebinding_action = action
	btn.text = "按任意键...（Esc取消）"
	btn.modulate = Color(1.0, 0.8, 0.3, 1.0)

func _input(event: InputEvent) -> void:
	# 按键重绑定监听
	if _rebinding_action != "":
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				# 取消重绑定
				_rebinding_action = ""
				_populate_key_bindings()
				get_viewport().set_input_as_handled()
				return
			# 绑定新按键
			SettingsManager.rebind_action(_rebinding_action, event.physical_keycode)
			_rebinding_action = ""
			_populate_key_bindings()
			get_viewport().set_input_as_handled()
		return
	# Esc关闭设置
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()

func _on_nickname_submitted(_text: String) -> void:
	SettingsManager.set_nickname(nickname_input.text)

func _on_nickname_focus_exited() -> void:
	SettingsManager.set_nickname(nickname_input.text)

# ── 网络设置 ────────────────────────────────────────────

func _on_server_host_focus_exited() -> void:
	var host: String = server_host_input.text.strip_edges()
	if not host.is_empty():
		SettingsManager.set_setting("network", "public_server_host", host)
		SettingsManager.save_settings()

func _on_server_port_focus_exited() -> void:
	var port_str: String = server_port_input.text.strip_edges()
	if port_str.is_valid_int():
		SettingsManager.set_setting("network", "public_server_port", int(port_str))
		SettingsManager.save_settings()
	else:
		server_port_input.text = str(SettingsManager.get_setting("network", "public_server_port", 8765))

func _on_lan_port_focus_exited() -> void:
	var port_str: String = lan_port_input.text.strip_edges()
	if port_str.is_valid_int():
		SettingsManager.set_setting("network", "lan_port", int(port_str))
		SettingsManager.save_settings()
	else:
		lan_port_input.text = str(SettingsManager.get_setting("network", "lan_port", 7777))

func _on_reset_keys_pressed() -> void:
	SettingsManager.reset_input_map()
	_populate_key_bindings()

func _populate_touch_buttons() -> void:
	"""生成触摸按钮配置列表"""
	for child in touch_list.get_children():
		child.queue_free()
	var buttons = SettingsManager.get_touch_buttons()
	for btn_id in buttons.keys():
		var cfg = buttons[btn_id]
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		# 标题行：启用复选框 + 按钮名称
		var title_row = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		var enable_check = CheckBox.new()
		enable_check.text = "%s (%s)" % [cfg.get("label", btn_id), cfg.get("action", "")]
		enable_check.button_pressed = cfg.get("enabled", true)
		enable_check.custom_minimum_size = Vector2(180, 0)
		var _bid = btn_id
		enable_check.toggled.connect(func(checked):
			var c = SettingsManager.get_touch_buttons()[_bid]
			c["enabled"] = checked
			SettingsManager.set_touch_button(_bid, c)
		)
		title_row.add_child(enable_check)
		row.add_child(title_row)

		# 位置行：X百分比 + Y百分比
		var pos_row = HBoxContainer.new()
		pos_row.add_theme_constant_override("separation", 8)
		var x_label = Label.new()
		x_label.text = "X:"
		x_label.custom_minimum_size = Vector2(20, 0)
		pos_row.add_child(x_label)
		var x_spin = SpinBox.new()
		x_spin.min_value = 0.0
		x_spin.max_value = 1.0
		x_spin.step = 0.01
		x_spin.value = cfg.get("x_pct", 0.5)
		x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _bid2 = btn_id
		x_spin.value_changed.connect(func(val):
			var c = SettingsManager.get_touch_buttons()[_bid2]
			c["x_pct"] = val
			SettingsManager.set_touch_button(_bid2, c)
		)
		pos_row.add_child(x_spin)
		var y_label = Label.new()
		y_label.text = "Y:"
		y_label.custom_minimum_size = Vector2(20, 0)
		pos_row.add_child(y_label)
		var y_spin = SpinBox.new()
		y_spin.min_value = 0.0
		y_spin.max_value = 1.0
		y_spin.step = 0.01
		y_spin.value = cfg.get("y_pct", 0.5)
		y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _bid3 = btn_id
		y_spin.value_changed.connect(func(val):
			var c = SettingsManager.get_touch_buttons()[_bid3]
			c["y_pct"] = val
			SettingsManager.set_touch_button(_bid3, c)
		)
		pos_row.add_child(y_spin)
		row.add_child(pos_row)

		# 大小行：宽度 + 高度
		var size_row = HBoxContainer.new()
		size_row.add_theme_constant_override("separation", 8)
		var w_label = Label.new()
		w_label.text = "宽:"
		w_label.custom_minimum_size = Vector2(20, 0)
		size_row.add_child(w_label)
		var w_spin = SpinBox.new()
		w_spin.min_value = 20
		w_spin.max_value = 200
		w_spin.step = 1
		w_spin.value = cfg.get("width", 50)
		w_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _bid4 = btn_id
		w_spin.value_changed.connect(func(val):
			var c = SettingsManager.get_touch_buttons()[_bid4]
			c["width"] = int(val)
			SettingsManager.set_touch_button(_bid4, c)
		)
		size_row.add_child(w_spin)
		var h_label = Label.new()
		h_label.text = "高:"
		h_label.custom_minimum_size = Vector2(20, 0)
		size_row.add_child(h_label)
		var h_spin = SpinBox.new()
		h_spin.min_value = 20
		h_spin.max_value = 200
		h_spin.step = 1
		h_spin.value = cfg.get("height", 50)
		h_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var _bid5 = btn_id
		h_spin.value_changed.connect(func(val):
			var c = SettingsManager.get_touch_buttons()[_bid5]
			c["height"] = int(val)
			SettingsManager.set_touch_button(_bid5, c)
		)
		size_row.add_child(h_spin)
		row.add_child(size_row)

		# 分隔线
		var sep = HSeparator.new()
		sep.custom_minimum_size = Vector2(0, 8)
		row.add_child(sep)

		touch_list.add_child(row)

func _on_touch_reset_pressed() -> void:
	SettingsManager.reset_touch_buttons()
	_populate_touch_buttons()

func _on_touch_edit_pressed() -> void:
	"""打开拖动式布局编辑器"""
	if _layout_editor:
		_layout_editor.queue_free()
		_layout_editor = null
		return
	_layout_editor = Control.new()
	_layout_editor.name = "TouchLayoutEditor"
	_layout_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().root.add_child(_layout_editor)

	# 半透明背景
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_editor.add_child(bg)

	# 顶部提示
	var hint = Label.new()
	hint.text = "拖动按钮调整位置，完成后点击保存"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 10
	hint.add_theme_font_size_override("font_size", 18)
	hint.modulate = Color(1, 1, 0.8)
	_layout_editor.add_child(hint)

	# 保存/取消按钮
	var btn_row = HBoxContainer.new()
	btn_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	btn_row.offset_top = 40
	btn_row.offset_left = 20
	btn_row.offset_right = -20
	btn_row.add_theme_constant_override("separation", 15)
	_layout_editor.add_child(btn_row)

	var save_btn = Button.new()
	save_btn.text = "保存布局"
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.modulate = Color(0.3, 1, 0.3)
	save_btn.pressed.connect(_on_layout_save)
	btn_row.add_child(save_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_on_layout_cancel)
	btn_row.add_child(cancel_btn)

	# 创建可拖动的按钮（使用实际视口大小模拟）
	var vp_size = get_viewport().get_visible_rect().size
	var buttons = SettingsManager.get_touch_buttons()
	for btn_id in buttons.keys():
		var cfg = buttons[btn_id]
		if not cfg.get("enabled", true):
			continue
		var is_joystick = btn_id == "joystick"
		var btn = Button.new()
		btn.text = cfg.get("label", btn_id)
		btn.size = Vector2(cfg.get("width", 50), cfg.get("height", 50))
		if is_joystick:
			# 摇杆配置存的是中心点，编辑器用左上角
			btn.position = Vector2(
				cfg.get("x_pct", 0.5) * vp_size.x - btn.size.x * 0.5,
				cfg.get("y_pct", 0.5) * vp_size.y - btn.size.y * 0.5
			)
		else:
			btn.position = Vector2(cfg.get("x_pct", 0.5) * vp_size.x, cfg.get("y_pct", 0.5) * vp_size.y)
		if is_joystick:
			btn.modulate = Color(0.3, 0.7, 1.0, 0.7)
		else:
			btn.modulate = Color(0.4, 0.8, 1.0, 0.9)
		btn.add_theme_font_size_override("font_size", 14)
		# 存储按钮ID用于保存
		btn.set_meta("btn_id", btn_id)
		# 拖动事件
		btn.gui_input.connect(_on_layout_btn_gui_input.bind(btn))
		_layout_editor.add_child(btn)

func _on_layout_btn_gui_input(event: InputEvent, btn: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_btn = btn
			_drag_offset = btn.position - event.global_position
			btn.modulate = Color(1, 1, 0.3, 1.0)
		else:
			if _dragging_btn == btn:
				_dragging_btn = null
				btn.modulate = Color(0.4, 0.8, 1.0, 0.9)
	elif event is InputEventMouseMotion and _dragging_btn == btn:
		var vp_size = get_viewport().get_visible_rect().size
		var new_pos = event.global_position + _drag_offset
		# 限制在视口内
		new_pos.x = clamp(new_pos.x, 0, vp_size.x - btn.size.x)
		new_pos.y = clamp(new_pos.y, 60, vp_size.y - btn.size.y)
		btn.position = new_pos

func _on_layout_save() -> void:
	"""保存布局到SettingsManager"""
	var vp_size = get_viewport().get_visible_rect().size
	for btn in _layout_editor.get_children():
		if btn is Button and btn.has_meta("btn_id"):
			var btn_id = btn.get_meta("btn_id")
			var cfg = SettingsManager.get_touch_buttons()[btn_id]
			if btn_id == "joystick":
				# 摇杆保存中心点位置
				cfg["x_pct"] = (btn.position.x + btn.size.x * 0.5) / vp_size.x
				cfg["y_pct"] = (btn.position.y + btn.size.y * 0.5) / vp_size.y
			else:
				cfg["x_pct"] = btn.position.x / vp_size.x
				cfg["y_pct"] = btn.position.y / vp_size.y
			cfg["width"] = int(btn.size.x)
			cfg["height"] = int(btn.size.y)
			SettingsManager.set_touch_button(btn_id, cfg)
	_on_layout_cancel()
	_populate_touch_buttons()

func _on_layout_cancel() -> void:
	if _layout_editor:
		_layout_editor.queue_free()
		_layout_editor = null
	_dragging_btn = null


# ── 按钮 ────────────────────────────────────────────────

func _on_reset_pressed() -> void:
	SettingsManager.reset_to_default()
	_load_current_settings()


func _on_close_pressed() -> void:
	queue_free()
