extends Control
## 炮镜瞄准镜覆盖层
## 根据载具配置渲染不同样式的分划板、放大倍数、镜片效果
## 支持多种炮镜样式：现代、二战德国、二战苏联、简易

signal zoom_changed(level: int, fov: float)
signal range_complete
signal scope_opened()
signal scope_closed()

@export var scope_config: Dictionary = {}

var is_open: bool = false
var current_zoom_index: int = 0
var zoom_levels: Array = [3.0, 6.0, 10.0]
var reticle_color: Color = Color(0, 1, 0, 0.9)
var reticle_style: String = "modern"
var lens_color: Color = Color(0.85, 0.92, 1.0, 0.08)
var has_range_finder: bool = false
var has_stadiametric: bool = true
var base_fov: float = 40.0
var current_fov: float = 40.0

# 弹道参数（用于计算炮弹下坠对应的瞄准密位）
var muzzle_velocity: float = 800.0
var gravity: float = 9.8
var drag_coefficient: float = 0.1
var mass: float = 10.0

# 测距状态
var is_ranging: bool = false
var range_progress: float = 0.0
var range_duration: float = 1.0
var last_range: float = -1.0  # -1=无有效测距
var range_finder_time: float = 1.0  # 从载具配置读取
var range_finder_font_size: int = 13  # 测距文字大小（用户设置可覆盖）
var range_color: Color = Color(0, 1, 0, 0.95)  # 测距结果文字颜色（用户设置可覆盖）

# 绘制参数
var center: Vector2 = Vector2.ZERO
var scope_radius: float = 300.0
var mask_rect: ColorRect = null

func _ready() -> void:
	visible = false
	set_mouse_filter(Control.MOUSE_FILTER_IGNORE)
	center = size * 0.5
	scope_radius = min(size.x, size.y) * 0.45
	_create_circular_mask()

func _create_circular_mask() -> void:
	"""创建着色器驱动的圆形遮罩（圆外黑色，圆内透明）"""
	mask_rect = ColorRect.new()
	mask_rect.name = "CircularMask"
	mask_rect.color = Color(0, 0, 0, 1)
	mask_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = load("res://scripts/ui/scope_mask.gdshader")
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("radius_ratio", 0.45)
		mask_rect.material = mat
	add_child(mask_rect)

func apply_config(config: Dictionary) -> void:
	"""应用载具的炮镜配置"""
	scope_config = config
	reticle_style = config.get("style", "modern")
	# 用户设置覆盖载具默认样式（default表示使用载具自带）
	var user_style = SettingsManager.get_scope_style()
	if user_style != "default":
		reticle_style = user_style
	zoom_levels = config.get("zoom_levels", [3.0, 6.0, 10.0])
	base_fov = config.get("field_of_view", 40.0)
	has_range_finder = config.get("has_range_finder", false)
	has_stadiametric = config.get("has_stadiametric", true)
	range_finder_time = config.get("range_finder_time", 1.0)
	range_finder_font_size = config.get("range_finder_font_size", 14)
	# 用户设置三档覆盖（小/中/大 → 11/14/18）
	var user_font_idx := SettingsManager.get_scope_range_font_size()
	if user_font_idx >= 0 and user_font_idx < SettingsManager.RANGE_FONT_SIZES.size():
		range_finder_font_size = SettingsManager.RANGE_FONT_SIZES[user_font_idx]
	# 用户设置测距文字颜色
	range_color = SettingsManager.get_scope_range_color()

	var rc = config.get("reticle_color", "#00ff00")
	if typeof(rc) == TYPE_STRING:
		reticle_color = Color.html(rc)
	elif typeof(rc) == TYPE_ARRAY and rc.size() >= 3:
		reticle_color = Color(rc[0], rc[1], rc[2], rc[3] if rc.size() > 3 else 0.9)

	var lc = config.get("lens_color", [0.85, 0.92, 1.0, 0.08])
	if typeof(lc) == TYPE_ARRAY and lc.size() >= 3:
		lens_color = Color(lc[0], lc[1], lc[2], lc[3] if lc.size() > 3 else 0.08)

	current_zoom_index = 0
	current_fov = base_fov / zoom_levels[0] if zoom_levels.size() > 0 else base_fov
	queue_redraw()

func open() -> void:
	is_open = true
	visible = true
	scope_opened.emit()
	_update_fov()

func close() -> void:
	is_open = false
	visible = false
	scope_closed.emit()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func cycle_zoom() -> void:
	"""放大一档（单向：到最大后停住，不循环回最小）"""
	if zoom_levels.is_empty():
		return
	current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
	_update_fov()
	queue_redraw()

func set_zoom_index(index: int) -> void:
	if index >= 0 and index < zoom_levels.size():
		current_zoom_index = index
		_update_fov()
		queue_redraw()

func _update_fov() -> void:
	if zoom_levels.size() > 0:
		current_fov = base_fov / zoom_levels[current_zoom_index]
	zoom_changed.emit(current_zoom_index, current_fov)

func get_current_fov() -> float:
	return current_fov

func get_current_zoom() -> float:
	if zoom_levels.size() > 0:
		return zoom_levels[current_zoom_index]
	return 1.0

func _get_mil_size() -> float:
	"""获取当前缩放下1密位对应的像素大小（放大倍数越大，密位分划越宽）"""
	var base_mil = scope_radius * 0.03
	if zoom_levels.size() > 0:
		var zoom_factor = get_current_zoom() / zoom_levels[0]
		return base_mil * zoom_factor
	return base_mil

func set_ballistics(v0: float, g: float = 9.8, cd: float = 0.1, m: float = 10.0) -> void:
	"""设置当前弹药的弹道参数（切换弹药时调用），重绘分划
	v0=初速, g=重力, cd=阻力系数, m=弹丸质量（与projectile.gd物理一致）"""
	muzzle_velocity = max(v0, 50.0)
	gravity = g
	drag_coefficient = cd
	mass = max(m, 0.1)
	queue_redraw()

func get_aim_angle_deg(distance: float) -> float:
	"""计算给定距离(m)需要抬高的炮管角度（度）
	用于火控：测距后自动抬炮使炮弹下坠后命中目标"""
	var drop_mil := _get_drop_mil(distance)
	return drop_mil * 0.0572958  # 密位→弧度(×0.001)→度(×57.2958)

func _get_drop_mil(distance: float) -> float:
	"""计算给定距离(m)的炮弹下坠对应的瞄准密位数
	数值积分模拟炮弹飞行（与projectile.gd相同：重力9.81 + 平方阻力 cd*v²/m）
	炮弹沿-Z飞行，到达 -distance 时停止，读取下坠量"""
	if muzzle_velocity <= 0:
		return 0.0
	var vel := Vector3(0, 0, -muzzle_velocity)
	var pos := Vector3.ZERO
	var dt := 0.005
	var t := 0.0
	var cd := drag_coefficient
	var m := mass
	const DRAG_AREA_FACTOR := 0.0003  # 与projectile.gd一致
	while pos.z > -distance and t < 15.0:
		var spd := vel.length()
		if spd > 0.0:
			var drag := cd * spd * spd / m * DRAG_AREA_FACTOR
			vel -= vel.normalized() * drag * dt
		vel.y -= gravity * dt
		pos += vel * dt
		t += dt
	var drop := -pos.y  # 下坠量（正值）
	var angle := atan(drop / distance) if distance > 0 else 0.0
	return angle * 1000.0

func _process(delta: float) -> void:
	if is_ranging:
		range_progress += delta / range_duration
		if range_progress >= 1.0:
			range_progress = 1.0
			is_ranging = false
			range_complete.emit()
		queue_redraw()

func _draw() -> void:
	if not is_open:
		return

	center = size * 0.5
	scope_radius = min(size.x, size.y) * 0.45

	# 圆形遮罩由mask_rect着色器处理，这里只绘制边框
	_draw_scope_border()

	# 绘制镜片效果
	_draw_lens()

	# 绘制分划板
	match reticle_style:
		"modern": _draw_modern_reticle()
		"ww2_german": _draw_ww2_german_reticle()
		"ww2_soviet": _draw_ww2_soviet_reticle()
		"simple": _draw_simple_reticle()
		_: _draw_modern_reticle()

	# 绘制放大倍数显示
	_draw_zoom_indicator()

	# 绘制测距仪（如果有）
	if has_range_finder:
		_draw_range_finder()

func _draw_scope_border() -> void:
	# 炮镜边框（圆形）
	draw_arc(center, scope_radius, 0, TAU, 64, Color(0.1, 0.1, 0.1, 1), 4.0)
	draw_arc(center, scope_radius - 3, 0, TAU, 64, Color(0.3, 0.3, 0.3, 0.8), 1.0)

func _draw_lens() -> void:
	# 镜片颜色叠加
	draw_circle(center, scope_radius - 2, lens_color)
	# 镜片渐晕效果
	for i in range(5):
		var r = scope_radius - 2 - i * (scope_radius * 0.18)
		var alpha = 0.02 * (i + 1)
		draw_arc(center, r, 0, TAU, 64, Color(0, 0, 0, alpha), 8.0)

func _draw_modern_reticle() -> void:
	"""现代坦克炮镜：中心光点 + 密位分划（带数值）+ 弹道距离分划（线+数值）"""
	var col = reticle_color
	var mil = _get_mil_size()
	var font = ThemeDB.fallback_font

	# 中心光点
	draw_circle(center, 2.0, col)

	# 水平主线
	draw_line(center + Vector2(-scope_radius * 0.8, 0), center + Vector2(scope_radius * 0.8, 0), col, 1.5)
	# 垂直主线（上半部分短，下半部分长）
	draw_line(center + Vector2(0, -scope_radius * 0.3), center + Vector2(0, scope_radius * 0.7), col, 1.5)

	# 水平密位分划（垂直线）+ 偶数密位标数值
	for i in range(-8, 9):
		if i == 0:
			continue
		var x = center.x + i * mil * 2
		var h = mil * (0.8 if abs(i) % 2 == 0 else 1.5)
		draw_line(Vector2(x, center.y - h), Vector2(x, center.y + h), col, 1.0)
		# 偶数密位标数值（±2 ±4 ±6 ±8）
		if abs(i) % 2 == 0:
			var num_col = Color(col.r, col.g, col.b, 0.7)
			draw_string(font, Vector2(x - 6, center.y + h + 12), str(i * 2), HORIZONTAL_ALIGNMENT_CENTER, -1, 10, num_col)

	# 垂直密位分划（水平线，等间距基础刻度）
	for i in range(1, 10):
		var y = center.y + i * mil * 2
		if y > center.y + scope_radius * 0.82:
			break
		var w = mil * (1.0 if i % 2 == 0 else 0.6)
		draw_line(Vector2(center.x - w, y), Vector2(center.x + w, y), Color(col.r, col.g, col.b, 0.5), 1.0)

	# 弹道距离分划（主要分划线 + 数值，基于实际炮弹下坠，不等间距）
	for dist_hectometer in [5, 10, 15, 20, 25, 30]:
		var drop_mil := _get_drop_mil(dist_hectometer * 100.0)
		var y = center.y + drop_mil * mil
		if y < center.y + scope_radius * 0.82:
			# 主要分划线（比密位线长、粗）
			var line_w: float = mil * 2.5
			draw_line(Vector2(center.x - line_w, y), Vector2(center.x + line_w, y), col, 1.5)
			# 数值在右侧
			draw_string(font, Vector2(center.x + line_w + 6, y + 4), str(dist_hectometer), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
			# 短辅助线在左侧
			draw_line(Vector2(center.x - line_w - mil, y), Vector2(center.x - line_w, y), col, 1.0)

func _draw_ww2_german_reticle() -> void:
	"""二战德国炮镜（Tzf系列）：尖顶三角形 + 水平密位"""
	var col = reticle_color
	var mil = _get_mil_size() * 0.83

	# 中心尖顶三角形（瞄准点）
	var tri_size = mil * 3
	var points = PackedVector2Array([
		center + Vector2(0, -tri_size),
		center + Vector2(-tri_size * 0.6, tri_size * 0.5),
		center + Vector2(tri_size * 0.6, tri_size * 0.5)
	])
	draw_colored_polygon(points, col)

	# 水平长线
	draw_line(center + Vector2(-scope_radius * 0.75, tri_size * 0.5), center + Vector2(scope_radius * 0.75, tri_size * 0.5), col, 1.5)

	# 水平密位分划
	for i in range(-10, 11):
		if i == 0:
			continue
		var x = center.x + i * mil * 2
		var h = mil * (0.6 if abs(i) % 5 == 0 else 0.3)
		var y = tri_size * 0.5
		draw_line(Vector2(x, center.y + y - h), Vector2(x, center.y + y + h), col, 1.0)

	# 下方距离刻度（倒三角）
	for i in range(1, 6):
		var y = center.y + tri_size * 0.5 + i * mil * 4
		var tri = PackedVector2Array([
			Vector2(center.x, y),
			Vector2(center.x - mil, y + mil * 1.5),
			Vector2(center.x + mil, y + mil * 1.5)
		])
		draw_colored_polygon(tri, col)

func _draw_ww2_soviet_reticle() -> void:
	"""二战苏联炮镜（PSO系列）：V形分划 + 距离刻度"""
	var col = reticle_color
	var mil = _get_mil_size() * 0.93

	# 中心V形（ Chevron ）
	var chevron_h = mil * 4
	var chevron_w = mil * 2.5
	draw_line(center, center + Vector2(-chevron_w, chevron_h), col, 2.0)
	draw_line(center, center + Vector2(chevron_w, chevron_h), col, 2.0)

	# 水平密位线
	draw_line(center + Vector2(-scope_radius * 0.7, chevron_h), center + Vector2(scope_radius * 0.7, chevron_h), col, 1.0)

	# 水平密位分划
	for i in range(-10, 11):
		if i == 0:
			continue
		var x = center.x + i * mil * 2
		var h = mil * (0.7 if abs(i) % 5 == 0 else 0.35)
		draw_line(Vector2(x, center.y + chevron_h - h), Vector2(x, center.y + chevron_h + h), col, 1.0)

	# 左侧距离数字（1000m, 2000m... 基于实际弹道下坠）
	var font = ThemeDB.fallback_font
	for i in range(1, 5):
		var drop_mil := _get_drop_mil(i * 1000.0)
		var y = center.y + chevron_h + drop_mil * mil
		if y < center.y + scope_radius * 0.85:
			draw_line(Vector2(center.x - mil * 2, y), Vector2(center.x, y), col, 1.0)
			draw_string(font, Vector2(center.x - mil * 8, y + 4), str(i), HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, col)

	# 右侧风偏刻度
	for i in range(1, 5):
		var x = center.x + i * mil * 4
		draw_line(Vector2(x, center.y + chevron_h), Vector2(x, center.y + chevron_h + mil), col, 1.0)

func _draw_simple_reticle() -> void:
	"""简易十字分划"""
	var col = reticle_color
	# 十字线
	draw_line(center + Vector2(-scope_radius * 0.6, 0), center + Vector2(-10, 0), col, 2.0)
	draw_line(center + Vector2(10, 0), center + Vector2(scope_radius * 0.6, 0), col, 2.0)
	draw_line(center + Vector2(0, -scope_radius * 0.6), center + Vector2(0, -10), col, 2.0)
	draw_line(center + Vector2(0, 10), center + Vector2(0, scope_radius * 0.6), col, 2.0)
	# 中心点
	draw_circle(center, 3.0, col)
	draw_circle(center, 1.5, Color(0, 0, 0, 1))

func _draw_zoom_indicator() -> void:
	var font = ThemeDB.fallback_font
	var zoom = get_current_zoom()
	var text = "x%.1f" % zoom
	var pos = Vector2(center.x - scope_radius + 15, center.y + scope_radius - 20)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, reticle_color)

func _draw_range_finder() -> void:
	"""电子测距仪显示（圆内右上角，右对齐避免超出遮罩）：测距中/测距结果/无数据"""
	var font = ThemeDB.fallback_font
	var pos = center + Vector2(scope_radius * 0.5, -scope_radius * 0.55)
	var fs := range_finder_font_size
	if is_ranging:
		var text = "测距中 %d%%" % int(range_progress * 100)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color(1, 1, 0, 0.95))
		# 进度条（右对齐）
		var bar_w := 100.0
		var bar_h := 5.0
		var bar_pos = pos + Vector2(-bar_w, fs + 4)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.9))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * range_progress, bar_h)), Color(1, 1, 0, 0.95))
	elif last_range >= 0:
		var text = "RANGE: %d m" % int(last_range)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, range_color)
	else:
		draw_string(font, pos, "RANGE: ---- m", HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color(0.5, 0.5, 0.5, 0.7))

func start_ranging(duration: float = -1.0) -> void:
	"""开始测距（duration<=0 时用配置的 range_finder_time）"""
	if duration > 0:
		range_duration = duration
	else:
		range_duration = range_finder_time
	is_ranging = true
	range_progress = 0.0
	last_range = -1.0
	queue_redraw()

func set_range_result(distance: float) -> void:
	"""设置测距结果（由外部射线检测后调用）"""
	last_range = distance
	queue_redraw()

func update_range(distance: float) -> void:
	"""更新测距显示（兼容旧接口）"""
	last_range = distance
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	# 滚轮切换放大倍数
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 缩小一档（单向：到最小后停住，不循环回最大）
			if zoom_levels.size() > 0:
				current_zoom_index = max(current_zoom_index - 1, 0)
				_update_fov()
				queue_redraw()
