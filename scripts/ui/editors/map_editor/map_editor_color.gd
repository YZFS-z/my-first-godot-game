extends Node3D
## 地图编辑器 - 地面颜色绘制系统
## 职责：颜色图像管理、颜色绘制、笔刷指示器、颜色绘制输入处理
## 作为 MapEditor 节点的子节点，通过 get_parent() 访问共享状态

func _get_editor() -> Node:
	return get_parent()

func init_color_image() -> void:
	var editor: Node = _get_editor()
	if editor.color_image == null:
		editor.color_image = Image.create(int(editor.color_resolution), int(editor.color_resolution), false, Image.FORMAT_RGBA8)
	else:
		editor.color_image.resize(int(editor.color_resolution), int(editor.color_resolution))
	editor.color_image.fill(editor.default_ground_color)
	editor.color_texture = ImageTexture.create_from_image(editor.color_image)

func on_color_picked(color: Color) -> void:
	var editor: Node = _get_editor()
	if editor.is_color_paint_mode:
		editor.status_label.text = "绘制颜色: R=%.2f G=%.2f B=%.2f (左键绘制/右键擦除)" % [color.r, color.g, color.b]

func create_color_brush_indicator() -> void:
	var editor: Node = _get_editor()
	clear_color_brush_indicator()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "ColorBrushIndicator"
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = float(editor.color_brush_radius)
	cylinder.bottom_radius = float(editor.color_brush_radius)
	cylinder.height = 0.4
	mesh_inst.mesh = cylinder
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var picker_color: Color = editor.color_picker_button.color
	mat.albedo_color = Color(picker_color.r, picker_color.g, picker_color.b, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.visible = false
	editor.add_child(mesh_inst)
	editor.color_brush_indicator = mesh_inst

func clear_color_brush_indicator() -> void:
	var editor: Node = _get_editor()
	if editor.color_brush_indicator and is_instance_valid(editor.color_brush_indicator):
		editor.color_brush_indicator.queue_free()
	editor.color_brush_indicator = null

func update_color_brush_indicator(mouse_pos: Vector2) -> void:
	var editor: Node = _get_editor()
	if not editor.color_brush_indicator:
		return
	var hit: Vector3 = editor._raycast_ground(mouse_pos)
	if hit != Vector3.INF:
		editor.color_brush_indicator.position = hit
		editor.color_brush_indicator.visible = true
		var mat: Material = editor.color_brush_indicator.material_override
		if mat:
			var c: Color = editor.color_picker_button.color
			mat.albedo_color = Color(c.r, c.g, c.b, 0.3)
	else:
		editor.color_brush_indicator.visible = false

func update_color_brush_indicator_size() -> void:
	var editor: Node = _get_editor()
	if editor.color_brush_indicator and editor.color_brush_indicator.mesh is CylinderMesh:
		editor.color_brush_indicator.mesh.top_radius = float(editor.color_brush_radius)
		editor.color_brush_indicator.mesh.bottom_radius = float(editor.color_brush_radius)

func paint_ground_color(world_pos: Vector3, erase: bool) -> void:
	var editor: Node = _get_editor()
	var half: float = float(editor.map_size) * 0.5
	var px: int = int((world_pos.x + half) / float(editor.map_size) * float(editor.color_resolution))
	var py: int = int((world_pos.z + half) / float(editor.map_size) * float(editor.color_resolution))
	var brush_px: int = max(1, int(float(editor.color_brush_radius) / float(editor.map_size) * float(editor.color_resolution)))
	var picker_color: Color = editor.color_picker_button.color
	var paint_color: Color = editor.default_ground_color if erase else Color(picker_color.r, picker_color.g, picker_color.b, 1.0)
	var min_x: int = max(0, px - brush_px)
	var max_x: int = min(int(editor.color_resolution) - 1, px + brush_px)
	var min_y: int = max(0, py - brush_px)
	var max_y: int = min(int(editor.color_resolution) - 1, py + brush_px)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = float(x) - float(px)
			var dy: float = float(y) - float(py)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= brush_px:
				var falloff: float = cos(dist / float(brush_px) * PI * 0.5)
				var existing: Color = editor.color_image.get_pixel(x, y)
				var blended: Color = existing.lerp(paint_color, falloff)
				editor.color_image.set_pixel(x, y, blended)
	editor.color_texture.update(editor.color_image)
	if editor.terrain_ground_material:
		editor.terrain_ground_material.albedo_texture = editor.color_texture

func handle_input(event: InputEvent) -> void:
	var editor: Node = _get_editor()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.shift_pressed:
			editor.color_brush_radius = clamp(float(editor.color_brush_radius) + 5, 3, 150)
			update_color_brush_indicator_size()
			editor.status_label.text = "颜色笔刷半径: %.0fm (Shift+滚轮调整)" % float(editor.color_brush_radius)
		else:
			var step: float = max(10.0, float(editor.camera_height) * 0.15)
			editor.camera_height = max(float(editor.camera_min_height), float(editor.camera_height) - step)
			editor.camera_rig.position.y = editor.camera_height
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.shift_pressed:
			editor.color_brush_radius = clamp(float(editor.color_brush_radius) - 5, 3, 150)
			update_color_brush_indicator_size()
			editor.status_label.text = "颜色笔刷半径: %.0fm (Shift+滚轮调整)" % float(editor.color_brush_radius)
		else:
			var step: float = max(10.0, float(editor.camera_height) * 0.15)
			editor.camera_height = min(float(editor.camera_max_height), float(editor.camera_height) + step)
			editor.camera_rig.position.y = editor.camera_height
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		editor.is_panning = event.pressed
		editor.pan_last_pos = event.position
	if event is InputEventMouseMotion and editor.is_panning:
		var d: Vector2 = event.position - editor.pan_last_pos
		editor.pan_last_pos = event.position
		editor.camera_rig.position.x -= d.x * (float(editor.camera_height) / 200.0)
		editor.camera_rig.position.z -= d.y * (float(editor.camera_height) / 200.0)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			editor.color_is_painting = true
			editor.color_paint_erase = false
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_ground_color(hit, false)
		else:
			editor.color_is_painting = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			editor.color_is_painting = true
			editor.color_paint_erase = true
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_ground_color(hit, true)
		else:
			editor.color_is_painting = false
	if event is InputEventMouseMotion:
		update_color_brush_indicator(event.position)
		if editor.color_is_painting and not editor.is_panning:
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_ground_color(hit, bool(editor.color_paint_erase))
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		editor.is_color_paint_mode = false
		editor.obstacle_option.select(0)
		editor.current_obstacle_type = "rock"
		clear_color_brush_indicator()
		if editor.is_placing:
			editor._create_placement_preview()
		editor._update_status()
