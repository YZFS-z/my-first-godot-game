extends CanvasLayer
## 移动端触摸控制系统
## 左侧虚拟摇杆移动，右侧拖动瞄准，右下按钮开火/炮镜/维修/切弹

signal fire_pressed()
signal scope_toggled()
signal repair_pressed()
signal ammo_selected(index: int)
signal weapon_selected(index: int)  # 武器槽切换
signal chat_pressed()  # 打开聊天
signal skill_artillery_pressed()  # 火炮打击
signal skill_smoke_pressed()  # 烟幕遮蔽
signal free_look_pressed()   # 自由视角按下（按住进入）
signal free_look_released()  # 自由视角松开（退出）
signal pitch_up_pressed()    # 拉升按下（按住持续）
signal pitch_up_released()   # 拉升松开
signal pitch_down_pressed()  # 下降按下（按住持续）
signal pitch_down_released() # 下降松开
signal pause_pressed()       # 退出/暂停（等效 ESC）
signal range_finder_pressed()  # 测距

# 摇杆输出（-1 ~ 1）
var joystick_y: float = 0.0  # 前后（W/S）
var joystick_x: float = 0.0  # 左右转向（A/D）

# 飞行器升降按钮状态（按住期间为 true，供载具每帧读取）
var pitch_up_active: bool = false
var pitch_down_active: bool = false
# 开火按钮按住状态（按住期间为 true，供载具每帧轮询连续开火）
var fire_held: bool = false

# 图标纹理缓存
static var _icon_cache: Dictionary = {}
static func _get_icon(name: String, size: int = 48) -> Texture2D:
	var cache_key = "%s_%d" % [name, size]
	if not _icon_cache.has(cache_key):
		var path = "res://assets/icons/%s.png" % name
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			var img: Image = tex.get_image()
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
			_icon_cache[cache_key] = ImageTexture.create_from_image(img)
		else:
			_icon_cache[cache_key] = null
	return _icon_cache[cache_key]
# 视角拖动输出
var look_delta: Vector2 = Vector2.ZERO

# 摇杆
var _joystick_bg: ColorRect
var _joystick_handle: ColorRect
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_touch_id: int = -1
var _joystick_active: bool = false
const JOYSTICK_RADIUS: float = 80.0
const JOYSTICK_DEADZONE: float = 15.0

# 视角拖动
var _look_touch_id: int = -1
var _look_last_pos: Vector2 = Vector2.ZERO
var _look_area: ColorRect

# 按钮
var _fire_btn: Button
var _scope_btn: Button
var _repair_btn: Button
var _chat_btn: Button
var _artillery_btn: Button
var _smoke_btn: Button
var _free_look_btn: Button
var _pitch_up_btn: Button   # 飞行器升降：拉升（按住持续）
var _pitch_down_btn: Button # 飞行器升降：下降（按住持续）
var _pause_btn: Button      # 退出/暂停（等效 ESC，位置可自定义）
var _range_btn: Button      # 测距
var _air_buttons_requested: bool = false  # 当前载具是否需要飞行升降按钮（坦克隐藏）
var _ammo_btns: Array = []
var _weapon_btns: Array = []  # 武器槽按钮

var _viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 50  # 在HUD之上
	add_to_group("mobile_controls")
	_viewport_size = get_viewport().get_visible_rect().size
	print("[MobileControls] _ready called, viewport: ", _viewport_size)
	_build_ui()
	print("[MobileControls] UI built, joystick_center: ", _joystick_center, " 设备: ", OS.get_name())


func _build_ui() -> void:
	var w = _viewport_size.x
	var h = _viewport_size.y

	# ── 左侧虚拟摇杆（位置大小从配置读取）──
	var joy_cfg = SettingsManager.get_touch_buttons().get("joystick", {})
	var joy_diameter = joy_cfg.get("width", 160) if not joy_cfg.is_empty() else 160
	var joy_radius = joy_diameter * 0.5
	var joy_center_x = (joy_cfg.get("x_pct", 0.12) if not joy_cfg.is_empty() else 0.12) * w
	var joy_center_y = (joy_cfg.get("y_pct", 0.75) if not joy_cfg.is_empty() else 0.75) * h
	var joy_bg_pos = Vector2(joy_center_x - joy_radius, joy_center_y - joy_radius)

	_joystick_bg = ColorRect.new()
	_joystick_bg.size = Vector2(joy_diameter, joy_diameter)
	_joystick_bg.position = joy_bg_pos
	_joystick_bg.color = Color(0.2, 0.2, 0.2, 0.5)
	_joystick_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joystick_bg)

	_joystick_handle = ColorRect.new()
	_joystick_handle.size = Vector2(50, 50)
	_joystick_handle.position = joy_bg_pos + Vector2(joy_radius - 25, joy_radius - 25)
	_joystick_handle.color = Color(0.3, 0.7, 1.0, 0.9)
	_joystick_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joystick_handle)

	_joystick_center = Vector2(joy_center_x, joy_center_y)

	# 摇杆标签
	var joy_hint = Label.new()
	joy_hint.text = "移动"
	joy_hint.position = Vector2(joy_center_x - 20, joy_center_y - joy_radius - 20)
	joy_hint.modulate = Color(1, 1, 1, 0.7)
	add_child(joy_hint)

	# ── 右侧视角拖动区域（全屏极低透明度覆盖，用坐标判断触摸区域） ──
	_look_area = ColorRect.new()
	_look_area.position = Vector2.ZERO
	_look_area.size = Vector2(w, h)
	_look_area.color = Color(0.05, 0.05, 0.1, 0.04)  # 几乎完全透明
	_look_area.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不拦截，由_input统一处理
	add_child(_look_area)

	# 视角提示文字
	var look_hint = Label.new()
	look_hint.text = "← 右侧拖动瞄准 →"
	look_hint.position = Vector2(w * 0.65, 30)
	look_hint.modulate = Color(0.5, 0.8, 1.0, 0.4)
	look_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(look_hint)

	# ── 右下按钮区 ──
	var btn_size = Vector2(70, 70)
	var btn_y = h - 160

	# 开火按钮（最大）
	_fire_btn = Button.new()
	_fire_btn.text = ""
	_fire_btn.icon = _get_icon("fire")
	_fire_btn.size = Vector2(90, 90)
	_fire_btn.position = Vector2(w - 120, btn_y - 20)
	_apply_touch_config(_fire_btn, "fire")
	_fire_btn.modulate = Color(1.0, 0.4, 0.4, 1.0)
	_apply_opaque_style(_fire_btn, Color(1.0, 0.4, 0.4))
	_fire_btn.button_down.connect(_on_fire_down)
	_fire_btn.button_up.connect(_on_fire_up)
	add_child(_fire_btn)

	# 炮镜按钮
	_scope_btn = Button.new()
	_scope_btn.text = ""
	_scope_btn.icon = _get_icon("scope")
	_scope_btn.size = btn_size
	_scope_btn.position = Vector2(w - 220, btn_y)
	_apply_touch_config(_scope_btn, "scope")
	_scope_btn.modulate = Color(0.4, 0.8, 1.0, 1.0)
	_apply_opaque_style(_scope_btn, Color(0.4, 0.8, 1.0))
	_scope_btn.pressed.connect(_on_scope)
	add_child(_scope_btn)

	# 维修按钮
	_repair_btn = Button.new()
	_repair_btn.text = ""
	_repair_btn.icon = _get_icon("repair")
	_repair_btn.size = btn_size
	_repair_btn.position = Vector2(w - 310, btn_y)
	_apply_touch_config(_repair_btn, "repair")
	_repair_btn.modulate = Color(0.4, 1.0, 0.5, 1.0)
	_apply_opaque_style(_repair_btn, Color(0.4, 1.0, 0.5))
	_repair_btn.pressed.connect(_on_repair)
	add_child(_repair_btn)

	# 测距按钮
	_range_btn = Button.new()
	_range_btn.text = "测距"
	_range_btn.size = Vector2(55, 55)
	_range_btn.add_theme_font_size_override("font_size", 14)
	_apply_touch_config(_range_btn, "range_finder")
	_range_btn.modulate = Color(1.0, 0.9, 0.3, 1.0)
	_apply_opaque_style(_range_btn, Color(1.0, 0.9, 0.3))
	_range_btn.pressed.connect(_on_range)
	add_child(_range_btn)

	# 聊天按钮
	_chat_btn = Button.new()
	_chat_btn.text = ""
	_chat_btn.icon = _get_icon("chat")
	_apply_touch_config(_chat_btn, "chat")
	_chat_btn.modulate = Color(0.6, 0.8, 1.0, 1.0)
	_apply_opaque_style(_chat_btn, Color(0.6, 0.8, 1.0))
	_chat_btn.pressed.connect(_on_chat)
	add_child(_chat_btn)

	# 火炮打击按钮
	_artillery_btn = Button.new()
	_artillery_btn.text = ""
	_artillery_btn.icon = _get_icon("artillery")
	_apply_touch_config(_artillery_btn, "artillery")
	_artillery_btn.modulate = Color(1.0, 0.6, 0.3, 1.0)
	_apply_opaque_style(_artillery_btn, Color(1.0, 0.6, 0.3))
	_artillery_btn.pressed.connect(_on_artillery)
	add_child(_artillery_btn)

	# 烟幕遮蔽按钮
	_smoke_btn = Button.new()
	_smoke_btn.text = ""
	_smoke_btn.icon = _get_icon("smoke")
	_apply_touch_config(_smoke_btn, "smoke")
	_smoke_btn.modulate = Color(0.6, 0.6, 0.6, 1.0)
	_apply_opaque_style(_smoke_btn, Color(0.6, 0.6, 0.6))
	_smoke_btn.pressed.connect(_on_smoke)
	add_child(_smoke_btn)

	# 自由视角按钮（按住进入自由视角，松开退出；右侧中上区域，避免与瞄准冲突）
	_free_look_btn = Button.new()
	_free_look_btn.text = "自由视角"
	_free_look_btn.size = Vector2(110, 46)
	_free_look_btn.position = Vector2(w * 0.78, h * 0.32)
	_free_look_btn.add_theme_font_size_override("font_size", 15)
	_apply_touch_config(_free_look_btn, "free_look")
	_free_look_btn.modulate = Color(0.95, 0.85, 0.4, 1.0)
	_apply_opaque_style(_free_look_btn, Color(0.95, 0.85, 0.4))
	_free_look_btn.button_down.connect(_on_free_look_down)
	_free_look_btn.button_up.connect(_on_free_look_up)
	add_child(_free_look_btn)

	# ── 飞行器升降按钮（拉升/下降，按住持续；位置可在设置中自定义）──
	# 固定在屏幕左侧中上部（x_pct<0.35 避开右侧视角拖动区），垂直排列对应 W/S 手感
	_pitch_up_btn = Button.new()
	_pitch_up_btn.text = "拉升"
	_pitch_up_btn.size = Vector2(60, 56)
	_apply_touch_config(_pitch_up_btn, "pitch_up")
	_pitch_up_btn.add_theme_font_size_override("font_size", 16)
	_pitch_up_btn.modulate = Color(0.5, 1.0, 0.6, 1.0)
	_apply_opaque_style(_pitch_up_btn, Color(0.5, 1.0, 0.6))
	_pitch_up_btn.button_down.connect(_on_pitch_up_down)
	_pitch_up_btn.button_up.connect(_on_pitch_up_up)
	_pitch_up_btn.visible = false  # 默认隐藏，由载具按类型显示
	add_child(_pitch_up_btn)

	_pitch_down_btn = Button.new()
	_pitch_down_btn.text = "下降"
	_pitch_down_btn.size = Vector2(60, 56)
	_apply_touch_config(_pitch_down_btn, "pitch_down")
	_pitch_down_btn.add_theme_font_size_override("font_size", 16)
	_pitch_down_btn.modulate = Color(1.0, 0.65, 0.35, 1.0)
	_apply_opaque_style(_pitch_down_btn, Color(1.0, 0.65, 0.35))
	_pitch_down_btn.button_down.connect(_on_pitch_down_down)
	_pitch_down_btn.button_up.connect(_on_pitch_down_up)
	_pitch_down_btn.visible = false
	add_child(_pitch_down_btn)

	# ── 退出/暂停按钮（等效桌面端 ESC；位置/大小/开关可在设置中自定义）──
	_pause_btn = Button.new()
	_pause_btn.text = "退出"
	_pause_btn.size = Vector2(60, 44)
	_apply_touch_config(_pause_btn, "pause")
	_pause_btn.add_theme_font_size_override("font_size", 16)
	_pause_btn.modulate = Color(1.0, 0.55, 0.45, 1.0)
	_apply_opaque_style(_pause_btn, Color(1.0, 0.55, 0.45))
	_pause_btn.pressed.connect(_on_pause)
	add_child(_pause_btn)

	# ── 武器切换 + 弹药切换（同一行，武器在左，弹药在右）──
	# 武器按钮（有副武器时显示，无副武器时全部隐藏）
	for i in range(2):
		var btn = Button.new()
		btn.text = "W%d" % (i + 1)
		btn.size = Vector2(48, 36)
		btn.position = Vector2(w * 0.5 - 160 + i * 52, h - 50)
		_apply_touch_config(btn, "weapon_%d" % (i + 1))
		btn.add_theme_font_size_override("font_size", 12)
		_apply_opaque_style(btn, Color(0.4, 0.8, 1.0))
		btn.visible = false  # 默认隐藏，set_weapon_count控制
		var idx = i
		btn.pressed.connect(func(): _on_weapon(idx))
		_weapon_btns.append(btn)
		add_child(btn)

	# 弹药切换按钮
	for i in range(3):
		var btn = Button.new()
		btn.text = str(i + 1)
		btn.size = Vector2(42, 42)
		btn.position = Vector2(w * 0.5 - 10 + i * 48, h - 53)
		_apply_touch_config(btn, "ammo_%d" % (i + 1))
		btn.add_theme_font_size_override("font_size", 16)
		btn.modulate = Color(1, 1, 1, 1.0)
		_apply_opaque_style(btn, Color(1.0, 1.0, 1.0))
		var idx = i
		btn.pressed.connect(func(): _on_ammo(idx))
		_ammo_btns.append(btn)
		add_child(btn)

	# 弹药标签
	var ammo_hint = Label.new()
	ammo_hint.text = "武器/弹药"
	ammo_hint.position = Vector2(w * 0.5 - 45, h - 80)
	ammo_hint.modulate = Color(1, 1, 1, 0.5)
	add_child(ammo_hint)


func _input(event: InputEvent) -> void:
	# 处理触摸事件
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var pos = event.position

	if event.pressed:
		# 判断是否在摇杆区域（左下）
		if pos.distance_to(_joystick_center) < JOYSTICK_RADIUS * 1.8:
			_joystick_touch_id = event.index
			_joystick_active = true
			_update_joystick(pos)
			get_viewport().set_input_as_handled()
			return

		# 判断是否在视角区域（屏幕右侧65%，且不在底部按钮区）
		var in_look_x = pos.x > _viewport_size.x * 0.35
		var in_look_y = pos.y < _viewport_size.y * 0.75  # 底部25%是按钮区
		if in_look_x and in_look_y:
			_look_touch_id = event.index
			_look_last_pos = pos
			get_viewport().set_input_as_handled()
			return
	else:
		# 松开
		if event.index == _joystick_touch_id:
			_joystick_touch_id = -1
			_joystick_active = false
			joystick_x = 0.0
			joystick_y = 0.0
			_reset_joystick_handle()
		if event.index == _look_touch_id:
			_look_touch_id = -1
			look_delta = Vector2.ZERO


func _handle_drag(event: InputEventScreenDrag) -> void:
	var pos = event.position

	if event.index == _joystick_touch_id and _joystick_active:
		_update_joystick(pos)
		get_viewport().set_input_as_handled()
		return

	if event.index == _look_touch_id:
		look_delta = pos - _look_last_pos
		_look_last_pos = pos
		get_viewport().set_input_as_handled()


func _update_joystick(pos: Vector2) -> void:
	var offset = pos - _joystick_center
	var dist = offset.length()

	if dist > JOYSTICK_RADIUS:
		offset = offset.normalized() * JOYSTICK_RADIUS

	# 死区
	if dist < JOYSTICK_DEADZONE:
		joystick_x = 0.0
		joystick_y = 0.0
	else:
		# 归一化到 -1~1
		var normalized = offset / JOYSTICK_RADIUS
		joystick_x = normalized.x  # 左右转向
		joystick_y = -normalized.y  # 前后（上推=前进=正）

	# 更新把手位置
	_joystick_handle.position = _joystick_center + offset - Vector2(25, 25)


func _reset_joystick_handle() -> void:
	_joystick_handle.position = _joystick_center - Vector2(25, 25)


# ── 按钮回调 ──

func _on_fire_down() -> void:
	fire_held = true
	fire_pressed.emit()  # 兼容旧连接：按下瞬间立即开火一次；连发由载具轮询 fire_held 驱动


func _on_fire_up() -> void:
	fire_held = false


func _on_scope() -> void:
	scope_toggled.emit()


func _on_repair() -> void:
	repair_pressed.emit()

func _on_range() -> void:
	range_finder_pressed.emit()

func _on_chat() -> void:
	chat_pressed.emit()

func _on_artillery() -> void:
	skill_artillery_pressed.emit()

func _on_smoke() -> void:
	skill_smoke_pressed.emit()

func _on_free_look_down() -> void:
	free_look_pressed.emit()

func _on_free_look_up() -> void:
	free_look_released.emit()

func _on_pitch_up_down() -> void:
	pitch_up_active = true
	pitch_up_pressed.emit()

func _on_pitch_up_up() -> void:
	pitch_up_active = false
	pitch_up_released.emit()

func _on_pitch_down_down() -> void:
	pitch_down_active = true
	pitch_down_pressed.emit()

func _on_pitch_down_up() -> void:
	pitch_down_active = false
	pitch_down_released.emit()

func _on_pause() -> void:
	pause_pressed.emit()

func set_air_buttons_visible(show: bool) -> void:
	"""按载具类型显示/隐藏飞行升降按钮（玩家开飞机时显示，坦克隐藏）"""
	_air_buttons_requested = show
	if _pitch_up_btn:
		_pitch_up_btn.visible = show and SettingsManager.get_touch_buttons().get("pitch_up", {}).get("enabled", true)
	if _pitch_down_btn:
		_pitch_down_btn.visible = show and SettingsManager.get_touch_buttons().get("pitch_down", {}).get("enabled", true)


func _on_ammo(index: int) -> void:
	ammo_selected.emit(index)

func _on_weapon(index: int) -> void:
	weapon_selected.emit(index)
	set_current_weapon(index)

func set_weapon_count(count: int) -> void:
	"""设置武器槽数量，控制按钮显示（没有副武器则不显示武器切换按钮）"""
	var show_weapons = count >= 2
	var buttons_cfg = SettingsManager.get_touch_buttons()
	for i in range(_weapon_btns.size()):
		if i < _weapon_btns.size() and is_instance_valid(_weapon_btns[i]):
			var cfg = buttons_cfg.get("weapon_%d" % (i + 1), {})
			var cfg_enabled = cfg.get("enabled", true)
			_weapon_btns[i].visible = show_weapons and cfg_enabled and (i < count)
	set_current_weapon(0)

func set_current_weapon(index: int) -> void:
	"""高亮当前武器按钮"""
	for i in range(_weapon_btns.size()):
		if i < _weapon_btns.size() and is_instance_valid(_weapon_btns[i]):
			_weapon_btns[i].modulate = Color(0.4, 0.8, 1.0, 1.0) if i == index else Color(1, 1, 1, 0.85)

func _apply_touch_config(btn: Button, btn_id: String) -> void:
	"""从SettingsManager读取触摸按钮配置并应用到按钮"""
	var cfg = SettingsManager.get_touch_buttons().get(btn_id, {})
	if cfg.is_empty():
		return
	if cfg.has("enabled"):
		btn.visible = cfg.enabled
	if cfg.has("x_pct") and cfg.has("y_pct"):
		btn.position = Vector2(cfg.x_pct * _viewport_size.x, cfg.y_pct * _viewport_size.y)
	if cfg.has("width") and cfg.has("height"):
		btn.size = Vector2(cfg.width, cfg.height)


func _opaque_box(alpha: float, accent: Color) -> StyleBoxFlat:
	"""不透明深色圆角底 + 主题色描边（默认主题按钮底半透明，在战场上辨识度低）"""
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, alpha)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _apply_opaque_style(btn: Button, accent: Color) -> void:
	"""给移动端按钮套用高不透明度样式（normal/hover/pressed 三态 + 取消焦点框）"""
	btn.add_theme_stylebox_override("normal", _opaque_box(0.92, Color(accent.r, accent.g, accent.b, 0.8)))
	btn.add_theme_stylebox_override("hover", _opaque_box(0.97, Color(accent.r, accent.g, accent.b, 1.0)))
	btn.add_theme_stylebox_override("pressed", _opaque_box(0.75, Color(accent.r, accent.g, accent.b, 1.0)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# ── 每帧重置视角增量（用完即弃） ──
func _process(_delta: float) -> void:
	# look_delta 由消费方读取后不需要重置，因为每次drag都会更新
	# 但如果没有拖动，应该为0
	if _look_touch_id == -1:
		look_delta = Vector2.ZERO


func is_mobile() -> bool:
	"""判断是否为移动端"""
	var name = OS.get_name()
	return name == "Android" or name == "iOS" or name == "iOS Simulator"
