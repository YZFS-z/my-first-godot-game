extends Node3D
## 地图编辑器 - 地形高度图系统
## 职责：地形网格重建、碰撞重建、地形绘制（抬升/降低/平整）、笔刷指示器、地形输入处理
## 作为 MapEditor 节点的子节点，通过 get_parent() 访问共享状态

func _get_editor() -> Node:
	return get_parent()

func init_terrain_heights() -> void:
	var editor: Node = _get_editor()
	var n: int = int(editor.terrain_grid_size) + 1
	editor.terrain_heights.resize(n * n)
	editor.terrain_heights.fill(0.0)

func rebuild_terrain_mesh() -> void:
	var editor: Node = _get_editor()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = float(editor.map_size) * 0.5
	var cell: float = float(editor.map_size) / float(editor.terrain_grid_size)
	var n: int = int(editor.terrain_grid_size) + 1
	var vertex_count: int = 0
	for z in range(n):
		for x in range(n):
			var idx: int = z * n + x
			var h: float = float(editor.terrain_heights[idx]) if idx < editor.terrain_heights.size() else 0.0
			var uv_x: float = float(x) / float(editor.terrain_grid_size)
			var uv_y: float = float(z) / float(editor.terrain_grid_size)
			st.set_uv(Vector2(uv_x, uv_y))
			st.add_vertex(Vector3(x * cell - half, h, z * cell - half))
			vertex_count += 1
	var index_count: int = 0
	for z in range(int(editor.terrain_grid_size)):
		for x in range(int(editor.terrain_grid_size)):
			var i: int = z * n + x
			# 逆时针绕序（从上方看），法线朝上
			st.add_index(i)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + n + 1)
			index_count += 6
	st.generate_normals()
	editor.ground.mesh = st.commit()

func rebuild_terrain_collision() -> void:
	var editor: Node = _get_editor()
	# 立即移除旧碰撞体
	for child in editor.ground_collision.get_children():
		editor.ground_collision.remove_child(child)
		child.queue_free()
	if not editor.ground.mesh:
		return
	# 使用 trimesh 碰撞体，与网格完全匹配（支持任意地形高度）
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = editor.ground.mesh.create_trimesh_shape()
	col.shape = shape
	editor.ground_collision.add_child(col)
	editor.terrain_collision_shape = col

func paint_terrain(world_pos: Vector3, sign: int) -> void:
	var editor: Node = _get_editor()
	var half: float = float(editor.map_size) * 0.5
	var cell: float = float(editor.map_size) / float(editor.terrain_grid_size)
	var n: int = int(editor.terrain_grid_size) + 1
	var cx: float = (world_pos.x + half) / cell
	var cz: float = (world_pos.z + half) / cell
	var brush_cells: float = float(editor.terrain_brush_radius) / cell
	var min_x: int = max(0, int(cx - brush_cells))
	var max_x: int = min(int(editor.terrain_grid_size), int(cx + brush_cells) + 1)
	var min_z: int = max(0, int(cz - brush_cells))
	var max_z: int = min(int(editor.terrain_grid_size), int(cz + brush_cells) + 1)
	for z in range(min_z, max_z):
		for x in range(min_x, max_x):
			var dx: float = float(x) - cx
			var dz: float = float(z) - cz
			var dist: float = sqrt(dx * dx + dz * dz)
			if dist <= brush_cells:
				var falloff: float = cos(dist / brush_cells * PI * 0.5)
				var idx: int = z * n + x
				editor.terrain_heights[idx] += sign * float(editor.terrain_brush_strength) * falloff
				editor.terrain_heights[idx] = clamp(float(editor.terrain_heights[idx]), -50.0, 100.0)
	rebuild_terrain_mesh()
	editor.terrain_collision_dirty = true

func flush_terrain_collision() -> void:
	var editor: Node = _get_editor()
	if editor.terrain_collision_dirty:
		rebuild_terrain_collision()
		editor.terrain_collision_dirty = false

func flatten_terrain(world_pos: Vector3, target_height: float) -> void:
	var editor: Node = _get_editor()
	var half: float = float(editor.map_size) * 0.5
	var cell: float = float(editor.map_size) / float(editor.terrain_grid_size)
	var n: int = int(editor.terrain_grid_size) + 1
	var cx: float = (world_pos.x + half) / cell
	var cz: float = (world_pos.z + half) / cell
	var brush_cells: float = float(editor.terrain_brush_radius) / cell
	var min_x: int = max(0, int(cx - brush_cells))
	var max_x: int = min(int(editor.terrain_grid_size), int(cx + brush_cells) + 1)
	var min_z: int = max(0, int(cz - brush_cells))
	var max_z: int = min(int(editor.terrain_grid_size), int(cz + brush_cells) + 1)
	for z in range(min_z, max_z):
		for x in range(min_x, max_x):
			var dx: float = float(x) - cx
			var dz: float = float(z) - cz
			var dist: float = sqrt(dx * dx + dz * dz)
			if dist <= brush_cells:
				var falloff: float = cos(dist / brush_cells * PI * 0.5)
				var idx: int = z * n + x
				editor.terrain_heights[idx] = lerp(float(editor.terrain_heights[idx]), target_height, falloff)
	rebuild_terrain_mesh()
	editor.terrain_collision_dirty = true

func create_brush_indicator() -> void:
	var editor: Node = _get_editor()
	clear_brush_indicator()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "BrushIndicator"
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = float(editor.terrain_brush_radius)
	cylinder.bottom_radius = float(editor.terrain_brush_radius)
	cylinder.height = 0.3
	mesh_inst.mesh = cylinder
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.visible = false
	editor.add_child(mesh_inst)
	editor.brush_indicator = mesh_inst

func clear_brush_indicator() -> void:
	var editor: Node = _get_editor()
	if editor.brush_indicator and is_instance_valid(editor.brush_indicator):
		editor.brush_indicator.queue_free()
	editor.brush_indicator = null

func update_brush_indicator(mouse_pos: Vector2) -> void:
	var editor: Node = _get_editor()
	if not editor.brush_indicator:
		return
	var hit: Vector3 = editor._raycast_ground(mouse_pos)
	if hit != Vector3.INF:
		editor.brush_indicator.position = hit
		editor.brush_indicator.visible = true
	else:
		editor.brush_indicator.visible = false

func update_brush_indicator_size() -> void:
	var editor: Node = _get_editor()
	if editor.brush_indicator and editor.brush_indicator.mesh is CylinderMesh:
		editor.brush_indicator.mesh.top_radius = float(editor.terrain_brush_radius)
		editor.brush_indicator.mesh.bottom_radius = float(editor.terrain_brush_radius)

func handle_input(event: InputEvent) -> void:
	var editor: Node = _get_editor()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.shift_pressed:
			editor.terrain_brush_radius = clamp(float(editor.terrain_brush_radius) + 5, 5, 200)
			update_brush_indicator_size()
			editor.status_label.text = "地形笔刷半径: %.0fm (Shift+滚轮调整)" % float(editor.terrain_brush_radius)
		elif event.ctrl_pressed:
			editor.terrain_brush_strength = clamp(float(editor.terrain_brush_strength) + 0.5, 0.5, 10.0)
			editor.status_label.text = "地形笔刷强度: %.1f (Ctrl+滚轮调整)" % float(editor.terrain_brush_strength)
		else:
			var step: float = max(10.0, float(editor.camera_height) * 0.15)
			editor.camera_height = max(float(editor.camera_min_height), float(editor.camera_height) - step)
			editor.camera_rig.position.y = editor.camera_height
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.shift_pressed:
			editor.terrain_brush_radius = clamp(float(editor.terrain_brush_radius) - 5, 5, 200)
			update_brush_indicator_size()
			editor.status_label.text = "地形笔刷半径: %.0fm (Shift+滚轮调整)" % float(editor.terrain_brush_radius)
		elif event.ctrl_pressed:
			editor.terrain_brush_strength = clamp(float(editor.terrain_brush_strength) - 0.5, 0.5, 10.0)
			editor.status_label.text = "地形笔刷强度: %.1f (Ctrl+滚轮调整)" % float(editor.terrain_brush_strength)
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
			editor.terrain_is_painting = true
			editor.terrain_paint_sign = 1
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_terrain(hit, 1)
		else:
			editor.terrain_is_painting = false
			flush_terrain_collision()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			editor.terrain_is_painting = true
			editor.terrain_paint_sign = -1
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_terrain(hit, -1)
		else:
			editor.terrain_is_painting = false
			flush_terrain_collision()
	if event is InputEventMouseMotion:
		update_brush_indicator(event.position)
		if editor.terrain_is_painting and not editor.is_panning:
			var hit: Vector3 = editor._raycast_ground(event.position)
			if hit != Vector3.INF:
				paint_terrain(hit, int(editor.terrain_paint_sign))
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		var mp: Vector2 = get_viewport().get_mouse_position()
		var hit: Vector3 = editor._raycast_ground(mp)
		if hit != Vector3.INF:
			flatten_terrain(hit, 0.0)
			flush_terrain_collision()
			editor.status_label.text = "已平整地形到 0m"
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		editor.is_terrain_mode = false
		editor.obstacle_option.select(0)
		editor.current_obstacle_type = "rock"
		clear_brush_indicator()
		if editor.is_placing:
			editor._create_placement_preview()
		editor._update_status()
