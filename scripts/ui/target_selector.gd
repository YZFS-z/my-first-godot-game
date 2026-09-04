
## 技能目标选择器 - 俯视图选择打击位置（支持缩放、平移、比例尺）
## 挂在预定义CanvasLayer场景上，layer=1000

extends CanvasLayer

var _vehicle: Node = null
var _skill_id: String = ""
var _map_size: float = 400.0
var _selected_pos: Vector2 = Vector2.ZERO
var _marker: ColorRect = null
var _map_rect: Rect2 = Rect2()
var _mouse_timer: Timer = null

# 缩放和平移
var _zoom: float = 1.0  # 1.0=全图, 越大越放大
var _view_center: Vector2 = Vector2.ZERO  # 视图中心的世界坐标(wx, wz)
var _is_panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO
const MIN_ZOOM = 1.0
const MAX_ZOOM = 8.0

# UI元素引用（需要动态更新）
var _scale_label: Label = null
var _zoom_label: Label = null
var _grid_container: Node = null  # 网格线容器，缩放时重建
var _self_marker: ColorRect = null

func _ready() -> void:
	add_to_group("target_selector")
	print("[TargetSelector] _ready, layer=%d" % layer)
	_mouse_timer = Timer.new()
	_mouse_timer.wait_time = 0.05
	_mouse_timer.autostart = true
	_mouse_timer.timeout.connect(_on_mouse_timer)
	add_child(_mouse_timer)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_mouse_timer() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func setup(vehicle: Node, skill_id: String) -> void:
	_vehicle = vehicle
	_skill_id = skill_id
	if Engine.has_singleton("DataLoader"):
		var map_cfg = DataLoader.get_map(GameManager.selected_map_id)
		if map_cfg and map_cfg.has("size"):
			_map_size = float(map_cfg["size"])
	# 初始视图中心 = 玩家位置
	if _vehicle and is_instance_valid(_vehicle):
		_view_center = Vector2(_vehicle.global_position.x, _vehicle.global_position.z)
	else:
		_view_center = Vector2.ZERO
	_build_ui()
	print("[TargetSelector] setup完成, 地图%.0fm, 视图中心%s" % [_map_size, str(_view_center)])

func _build_ui() -> void:
	var vp_size = get_viewport().get_visible_rect().size

	# 全屏半透明背景
	var bg = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = vp_size
	bg.color = Color(0.05, 0.08, 0.1, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 点击捕获层（放在最底层，按钮在上面可正常点击）
	var click_catcher = Control.new()
	click_catcher.position = Vector2.ZERO
	click_catcher.size = vp_size
	click_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	click_catcher.gui_input.connect(_on_gui_input)
	add_child(click_catcher)

	# 标题
	var title = Label.new()
	title.text = "选择 %s 目标位置（俯视图）" % _get_skill_name()
	title.position = Vector2(0, 20)
	title.size = Vector2(vp_size.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1, 0.9, 0.5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# 提示
	var hint = Label.new()
	hint.text = "左键选择目标 | 滚轮缩放(全屏有效) | 右键/中键拖动平移 | 重复技能键取消"
	hint.position = Vector2(0, 58)
	hint.size = Vector2(vp_size.x, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.add_theme_font_size_override("font_size", 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	# 地图区域
	var map_px = min(vp_size.x * 0.6, vp_size.y * 0.58)
	var map_x = (vp_size.x - map_px) * 0.5
	var map_y = (vp_size.y - map_px) * 0.5 + 25
	_map_rect = Rect2(map_x, map_y, map_px, map_px)

	var map_bg = ColorRect.new()
	map_bg.position = _map_rect.position
	map_bg.size = _map_rect.size
	map_bg.color = Color(0.15, 0.22, 0.15, 0.95)
	map_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_bg)

	# 网格线容器
	_grid_container = Node.new()
	_grid_container.name = "GridContainer"
	add_child(_grid_container)
	_rebuild_grid()

	# 自己的位置标记
	if _vehicle and is_instance_valid(_vehicle):
		var vpos = _vehicle.global_position
		var self_screen = _world_to_map(vpos.x, vpos.z)
		_self_marker = ColorRect.new()
		_self_marker.size = Vector2(14, 14)
		_self_marker.position = self_screen - Vector2(7, 7)
		_self_marker.color = Color(0.3, 1, 0.4, 1)
		_self_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_self_marker)

	# 目标标记
	_marker = ColorRect.new()
	_marker.size = Vector2(22, 22)
	_marker.color = Color(1, 0.3, 0.3, 0.9)
	_marker.visible = false
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)

	# 比例尺（左下角）
	_scale_label = Label.new()
	_scale_label.position = Vector2(_map_rect.position.x + 10, _map_rect.position.y + _map_rect.size.y - 30)
	_scale_label.size = Vector2(200, 24)
	_scale_label.modulate = Color(1, 1, 1, 0.9)
	_scale_label.add_theme_font_size_override("font_size", 13)
	_scale_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scale_label)
	_update_scale_label()

	# 缩放级别（右上角）
	_zoom_label = Label.new()
	_zoom_label.position = Vector2(_map_rect.position.x + _map_rect.size.x - 120, _map_rect.position.y + 8)
	_zoom_label.size = Vector2(110, 22)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zoom_label.modulate = Color(1, 1, 0.7, 0.9)
	_zoom_label.add_theme_font_size_override("font_size", 13)
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zoom_label)
	_update_zoom_label()

	# 缩放按钮（右下角）- 加背景面板更明显
	var zoom_panel = Panel.new()
	zoom_panel.position = Vector2(_map_rect.position.x + _map_rect.size.x - 115, _map_rect.position.y + _map_rect.size.y - 44)
	zoom_panel.size = Vector2(108, 40)
	zoom_panel.modulate = Color(0.1, 0.15, 0.1, 0.9)
	add_child(zoom_panel)

	var zoom_btn_row = HBoxContainer.new()
	zoom_btn_row.position = Vector2(4, 4)
	zoom_btn_row.size = Vector2(100, 32)
	zoom_btn_row.add_theme_constant_override("separation", 4)
	zoom_panel.add_child(zoom_btn_row)

	var zoom_out_btn = Button.new()
	zoom_out_btn.text = "−"
	zoom_out_btn.custom_minimum_size = Vector2(32, 32)
	zoom_out_btn.add_theme_font_size_override("font_size", 20)
	zoom_out_btn.pressed.connect(func(): _zoom_at(_zoom * 0.7, _map_rect.position + _map_rect.size * 0.5))
	zoom_btn_row.add_child(zoom_out_btn)

	var zoom_reset_btn = Button.new()
	zoom_reset_btn.text = "□"
	zoom_reset_btn.custom_minimum_size = Vector2(32, 32)
	zoom_reset_btn.add_theme_font_size_override("font_size", 16)
	zoom_reset_btn.pressed.connect(_reset_view)
	zoom_btn_row.add_child(zoom_reset_btn)

	var zoom_in_btn = Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(32, 32)
	zoom_in_btn.add_theme_font_size_override("font_size", 20)
	zoom_in_btn.pressed.connect(func(): _zoom_at(_zoom * 1.4, _map_rect.position + _map_rect.size * 0.5))
	zoom_btn_row.add_child(zoom_in_btn)

	# 按钮行
	var btn_row = HBoxContainer.new()
	btn_row.position = Vector2(vp_size.x * 0.3, vp_size.y - 80)
	btn_row.size = Vector2(vp_size.x * 0.4, 46)
	btn_row.add_theme_constant_override("separation", 20)
	add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.add_theme_font_size_override("font_size", 17)
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认呼叫"
	confirm_btn.custom_minimum_size = Vector2(0, 44)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.add_theme_font_size_override("font_size", 17)
	confirm_btn.modulate = Color(1, 0.7, 0.3)
	confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(confirm_btn)

	print("[TargetSelector] UI完成, 子节点=%d" % get_child_count())

func _get_skill_name() -> String:
	if _skill_id == "artillery":
		return "火炮打击"
	elif _skill_id == "smoke":
		return "烟幕遮蔽"
	return _skill_id

func _get_visible_world_size() -> float:
	"""当前缩放级别下，地图显示区域对应的世界尺寸（米）"""
	return _map_size / _zoom

func _world_to_map(wx: float, wz: float) -> Vector2:
	"""世界坐标 -> 屏幕坐标（考虑缩放和平移）"""
	var visible_size = _get_visible_world_size()
	var offset_x = (wx - _view_center.x) / visible_size
	var offset_y = (wz - _view_center.y) / visible_size
	return Vector2(
		_map_rect.position.x + _map_rect.size.x * 0.5 + offset_x * _map_rect.size.x,
		_map_rect.position.y + _map_rect.size.y * 0.5 + offset_y * _map_rect.size.y
	)

func _map_to_world(sx: float, sy: float) -> Vector2:
	"""屏幕坐标 -> 世界坐标（考虑缩放和平移）"""
	var visible_size = _get_visible_world_size()
	var offset_x = (sx - (_map_rect.position.x + _map_rect.size.x * 0.5)) / _map_rect.size.x
	var offset_y = (sy - (_map_rect.position.y + _map_rect.size.y * 0.5)) / _map_rect.size.y
	return Vector2(
		_view_center.x + offset_x * visible_size,
		_view_center.y + offset_y * visible_size
	)

func _clamp_view_center() -> void:
	"""限制视图中心不超出地图范围"""
	var visible_size = _get_visible_world_size()
	var half = visible_size * 0.5
	var map_half = _map_size * 0.5
	if half >= map_half:
		_view_center = Vector2.ZERO
		return
	_view_center.x = clamp(_view_center.x, -map_half + half, map_half - half)
	_view_center.y = clamp(_view_center.y, -map_half + half, map_half - half)

func _zoom_at(new_zoom: float, screen_point: Vector2) -> void:
	"""以指定屏幕点为中心缩放"""
	var old_zoom = _zoom
	var old_world = _map_to_world(screen_point.x, screen_point.y)
	_zoom = clamp(new_zoom, MIN_ZOOM, MAX_ZOOM)
	_clamp_view_center()
	# 缩放后保持鼠标指向的世界坐标不变
	var new_world_at_point = _map_to_world(screen_point.x, screen_point.y)
	_view_center += (old_world - new_world_at_point)
	_clamp_view_center()
	_refresh_view()

func _reset_view() -> void:
	"""重置视图：全图显示，中心为玩家位置"""
	_zoom = 1.0
	if _vehicle and is_instance_valid(_vehicle):
		_view_center = Vector2(_vehicle.global_position.x, _vehicle.global_position.z)
	else:
		_view_center = Vector2.ZERO
	_clamp_view_center()
	_refresh_view()

func _refresh_view() -> void:
	"""缩放/平移后刷新所有动态元素"""
	_rebuild_grid()
	_update_scale_label()
	_update_zoom_label()
	# 更新自己位置标记
	if _self_marker and _vehicle and is_instance_valid(_vehicle):
		var vpos = _vehicle.global_position
		_self_marker.position = _world_to_map(vpos.x, vpos.z) - Vector2(7, 7)
	# 更新目标标记
	if _marker and _marker.visible:
		_marker.position = _world_to_map(_selected_pos.x, _selected_pos.y) - Vector2(11, 11)

func _rebuild_grid() -> void:
	"""根据缩放级别重建网格线"""
	if not _grid_container:
		return
	# 清除旧网格
	for child in _grid_container.get_children():
		child.queue_free()
	# 计算合适的网格间距（世界坐标米）
	var visible_size = _get_visible_world_size()
	var grid_spacing = 100.0
	for gs in [50, 100, 200, 500, 1000]:
		if visible_size / gs < 12:
			grid_spacing = gs
			break
	# 计算可见范围内的网格线
	var half_visible = visible_size * 0.5
	var map_half = _map_size * 0.5
	var start_x = floor((_view_center.x - half_visible) / grid_spacing) * grid_spacing
	var end_x = ceil((_view_center.x + half_visible) / grid_spacing) * grid_spacing
	var start_z = floor((_view_center.y - half_visible) / grid_spacing) * grid_spacing
	var end_z = ceil((_view_center.y + half_visible) / grid_spacing) * grid_spacing
	# 绘制竖线
	var wx = start_x
	while wx <= end_x:
		if wx >= -map_half and wx <= map_half:
			var screen_x = _world_to_map(wx, 0).x
			if screen_x >= _map_rect.position.x and screen_x <= _map_rect.position.x + _map_rect.size.x:
				var line = ColorRect.new()
				line.position = Vector2(screen_x, _map_rect.position.y)
				line.size = Vector2(1, _map_rect.size.y)
				line.color = Color(0.3, 0.45, 0.3, 0.4)
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_grid_container.add_child(line)
		wx += grid_spacing
	# 绘制横线
	var wz = start_z
	while wz <= end_z:
		if wz >= -map_half and wz <= map_half:
			var screen_y = _world_to_map(0, wz).y
			if screen_y >= _map_rect.position.y and screen_y <= _map_rect.position.y + _map_rect.size.y:
				var line = ColorRect.new()
				line.position = Vector2(_map_rect.position.x, screen_y)
				line.size = Vector2(_map_rect.size.x, 1)
				line.color = Color(0.3, 0.45, 0.3, 0.4)
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_grid_container.add_child(line)
		wz += grid_spacing
	# 地图边界线
	var boundary_color = Color(0.6, 0.3, 0.3, 0.6)
	var bl = _world_to_map(-map_half, -map_half)
	var br = _world_to_map(map_half, -map_half)
	var tl = _world_to_map(-map_half, map_half)
	if bl.x >= _map_rect.position.x and bl.x <= _map_rect.position.x + _map_rect.size.x:
		var l = ColorRect.new()
		l.position = Vector2(bl.x, _map_rect.position.y)
		l.size = Vector2(2, _map_rect.size.y)
		l.color = boundary_color
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(l)
	if br.x >= _map_rect.position.x and br.x <= _map_rect.position.x + _map_rect.size.x:
		var l = ColorRect.new()
		l.position = Vector2(br.x, _map_rect.position.y)
		l.size = Vector2(2, _map_rect.size.y)
		l.color = boundary_color
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(l)
	if tl.y >= _map_rect.position.y and tl.y <= _map_rect.position.y + _map_rect.size.y:
		var l = ColorRect.new()
		l.position = Vector2(_map_rect.position.x, tl.y)
		l.size = Vector2(_map_rect.size.x, 2)
		l.color = boundary_color
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(l)
	if bl.y >= _map_rect.position.y and bl.y <= _map_rect.position.y + _map_rect.size.y:
		var l = ColorRect.new()
		l.position = Vector2(_map_rect.position.x, bl.y)
		l.size = Vector2(_map_rect.size.x, 2)
		l.color = boundary_color
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(l)

func _update_scale_label() -> void:
	"""更新比例尺显示"""
	if not _scale_label:
		return
	var visible_size = _get_visible_world_size()
	# 选择一个合适的比例尺长度（像素）和对应距离
	var target_px = 120.0
	var world_per_px = visible_size / _map_rect.size.x
	var scale_world = target_px * world_per_px
	# 取整到合适的数值
	var nice_values = [10, 20, 50, 100, 200, 500, 1000, 2000]
	var nice_world = 100
	for nv in nice_values:
		if abs(scale_world - nv) < abs(scale_world - nice_world):
			nice_world = nv
	var scale_px = nice_world / world_per_px
	_scale_label.text = "比例尺: %dm (%.0fpx) | 每像素%.1fm" % [nice_world, scale_px, world_per_px]

func _update_zoom_label() -> void:
	if not _zoom_label:
		return
	_zoom_label.text = "缩放: %.1fx | 视野: %.0fm" % [_zoom, _get_visible_world_size()]

func _input(event: InputEvent) -> void:
	"""用_input处理滚轮和平移（在所有Control之前接收，最可靠）"""
	# 鼠标滚轮缩放（全屏有效，不限制在地图区域）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(_zoom * 1.3, event.position)
		get_viewport().set_input_as_handled()
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(_zoom * 0.75, event.position)
		get_viewport().set_input_as_handled()
		return
	# 右键/中键按下开始平移
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and event.pressed:
		_is_panning = true
		_pan_last_mouse = event.position
		get_viewport().set_input_as_handled()
		return
	# 右键/中键释放结束平移
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and not event.pressed:
		if _is_panning:
			_is_panning = false
			get_viewport().set_input_as_handled()
			return
	# 平移中
	if event is InputEventMouseMotion and _is_panning:
		var delta = event.position - _pan_last_mouse
		_pan_last_mouse = event.position
		var visible_size = _get_visible_world_size()
		var world_delta_x = -delta.x / _map_rect.size.x * visible_size
		var world_delta_y = -delta.y / _map_rect.size.y * visible_size
		_view_center += Vector2(world_delta_x, world_delta_y)
		_clamp_view_center()
		_refresh_view()
		get_viewport().set_input_as_handled()
		return

func _on_gui_input(event: InputEvent) -> void:
	"""gui_input只处理左键选择目标（按钮点击不会到达这里）"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _is_panning:
		if _map_rect.has_point(event.position):
			_selected_pos = _map_to_world(event.position.x, event.position.y)
			var map_half = _map_size * 0.5
			_selected_pos.x = clamp(_selected_pos.x, -map_half, map_half)
			_selected_pos.y = clamp(_selected_pos.y, -map_half, map_half)
			_marker.position = _world_to_map(_selected_pos.x, _selected_pos.y) - Vector2(11, 11)
			_marker.visible = true
		return

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skill_artillery") and _skill_id == "artillery":
		_on_cancel()
	elif event.is_action_pressed("skill_smoke") and _skill_id == "smoke":
		_on_cancel()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_G and _skill_id == "artillery":
		_on_cancel()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_H and _skill_id == "smoke":
		_on_cancel()

func _on_confirm() -> void:
	if not _marker.visible:
		return
	var target = Vector3(_selected_pos.x, 0.5, _selected_pos.y)
	if _vehicle and _vehicle.has_method("confirm_skill"):
		_vehicle.confirm_skill(target)
	_cleanup()

func _on_cancel() -> void:
	if _vehicle and _vehicle.has_method("cancel_skill"):
		_vehicle.cancel_skill()
	_cleanup()

func _cleanup() -> void:
	if _mouse_timer:
		_mouse_timer.stop()
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()
