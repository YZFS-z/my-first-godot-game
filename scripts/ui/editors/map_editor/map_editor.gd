extends Node3D
## 可视化地图编辑器 - 核心协调器
## 职责：UI初始化、主输入转发、放置预览、摄像机控制、射线检测、状态显示、组件协调
## 子组件：MapTerrain（地形绘制）、MapColorPaint（颜色绘制）、MapObjects（障碍物管理）、MapIO（保存加载）

signal map_saved(map_id: String)

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var ground: MeshInstance3D = $Ground
@onready var ground_collision: StaticBody3D = $GroundCollision
@onready var ui_layer: CanvasLayer = $UILayer
@onready var obstacle_option: OptionButton = $UILayer/Panel/ToolbarScroll/Toolbar/ObstacleOption
@onready var import_model_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/ImportModelButton
@onready var model_option: OptionButton = $UILayer/Panel/ToolbarScroll/Toolbar/ModelOption
@onready var scale_slider: HSlider = $UILayer/Panel/ToolbarScroll/Toolbar/ScaleSlider
@onready var scale_value: Label = $UILayer/Panel/ToolbarScroll/Toolbar/ScaleValue
@onready var place_mode_toggle: Button = $UILayer/Panel/ToolbarScroll/Toolbar/PlaceModeToggle
@onready var color_picker_button: ColorPickerButton = $UILayer/Panel/ToolbarScroll/Toolbar/ColorPickerButton
@onready var map_name_input: LineEdit = $UILayer/Panel/ToolbarScroll/Toolbar/MapNameInput
@onready var map_size_input: LineEdit = $UILayer/Panel/ToolbarScroll/Toolbar/MapSizeInput
@onready var air_boundary_input: LineEdit = $UILayer/Panel/ToolbarScroll/Toolbar/AirBoundaryInput
@onready var save_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/SaveButton
@onready var load_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/LoadButton
@onready var new_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/NewButton
@onready var clear_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/ClearButton
@onready var spawn_toggle: Button = $UILayer/Panel/ToolbarScroll/Toolbar/SpawnToggle
@onready var back_button: Button = $UILayer/Panel/ToolbarScroll/Toolbar/BackButton
@onready var status_label: Label = $UILayer/Panel/StatusLabel
@onready var selected_label: Label = $UILayer/SelectedLabel

# === 共享状态（各组件通过 get_parent() 访问）===
var obstacles: Array = []
var grass_patches: Array = []
var bush_patches: Array = []
var spawn_points: Array = []
var selected_obstacle: Dictionary = {}
var selected_grass: Dictionary = {}
var selected_bush: Dictionary = {}
var is_dragging: bool = false
var drag_offset: Vector3 = Vector3.ZERO
var current_obstacle_type: String = "rock"
var current_model_path: String = ""
var current_scale: float = 1.0
var current_grass_radius: float = 25.0
var current_grass_density: float = 0.7
var current_bush_radius: float = 18.0
var current_bush_density: float = 0.8
var model_file_dialog: FileDialog = null
var is_placing: bool = true
var placement_preview: Node3D = null
var preview_valid: bool = false
var is_placing_spawn: bool = false
var spawn_team: int = 1
var map_size: float = 200.0

# 地形高度图系统
var terrain_grid_size: int = 64
var terrain_heights: PackedFloat32Array = PackedFloat32Array()
var terrain_collision_shape: CollisionShape3D = null
var terrain_collision_dirty: bool = false
var is_terrain_mode: bool = false
var terrain_brush_radius: float = 20.0
var terrain_brush_strength: float = 1.5
var terrain_is_painting: bool = false
var terrain_paint_sign: int = 0
var brush_indicator: MeshInstance3D = null
var terrain_ground_material: StandardMaterial3D = null

# 地面颜色绘制系统
var color_resolution: int = 256
var color_image: Image = null
var color_texture: ImageTexture = null
var is_color_paint_mode: bool = false
var color_brush_radius: float = 15.0
var color_is_painting: bool = false
var color_paint_erase: bool = false
var color_brush_indicator: MeshInstance3D = null
var default_ground_color: Color = Color(0.6, 0.55, 0.4, 1.0)
var color_texture_filename: String = ""

# 摄像机控制
var camera_height: float = 80.0
var camera_min_height: float = 15.0
var camera_max_height: float = 200.0
var is_panning: bool = false
var pan_last_pos: Vector2 = Vector2.ZERO

# === 组件引用 ===
var _terrain: Node = null
var _color_paint: Node = null
var _objects: Node = null
var _io: Node = null

func _ready() -> void:
	# 缓存组件引用
	_terrain = get_node_or_null("MapTerrain")
	_color_paint = get_node_or_null("MapColorPaint")
	_objects = get_node_or_null("MapObjects")
	_io = get_node_or_null("MapIO")

	obstacle_option.clear()
	obstacle_option.add_item("岩石", 0)
	obstacle_option.add_item("建筑", 1)
	obstacle_option.add_item("模型", 2)
	obstacle_option.add_item("斜坡", 3)
	obstacle_option.add_item("草丛", 4)
	obstacle_option.add_item("灌木丛", 5)
	obstacle_option.add_item("地形", 6)
	obstacle_option.add_item("地面颜色", 7)
	obstacle_option.item_selected.connect(_on_obstacle_type_changed)
	import_model_button.pressed.connect(_on_import_model)
	model_option.item_selected.connect(_on_model_selected)
	scale_slider.value_changed.connect(_on_scale_changed)
	place_mode_toggle.toggled.connect(_on_place_mode_toggled)
	color_picker_button.color_changed.connect(_on_color_picked)
	if _io:
		_io.setup_file_dialog()
		_io.scan_imported_models()
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	new_button.pressed.connect(_on_new)
	clear_button.pressed.connect(_on_clear)
	spawn_toggle.pressed.connect(_on_spawn_toggle)
	back_button.pressed.connect(_on_back)
	map_size_input.text = "200"
	air_boundary_input.text = "12000"
	_setup_ground()
	_update_status()
	_create_placement_preview()
	_reset_camera_view()

# === 相机控制 ===

func _reset_camera_view() -> void:
	# 重置相机为纯俯视视角，定位到地图中心
	camera_max_height = max(200.0, map_size * 1.5)
	camera_height = camera_max_height * 0.6
	camera_rig.position = Vector3(0, camera_height, 0)
	camera_rig.rotation = Vector3.ZERO
	camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)

# === 地面设置 ===

func _setup_ground(init_heights: bool = true) -> void:
	map_size = float(map_size_input.text) if map_size_input.text.is_valid_float() else 200.0
	camera_max_height = max(200.0, map_size * 1.5)
	if init_heights and _terrain:
		_terrain.init_terrain_heights()
	if _terrain:
		_terrain.rebuild_terrain_mesh()
	terrain_ground_material = StandardMaterial3D.new()
	terrain_ground_material.roughness = 0.9
	terrain_ground_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	terrain_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _color_paint:
		_color_paint.init_color_image()
	terrain_ground_material.albedo_texture = color_texture
	terrain_ground_material.albedo_color = Color.WHITE
	ground.material_override = terrain_ground_material
	if _terrain:
		_terrain.rebuild_terrain_collision()
	if camera_height < camera_max_height * 0.3 or camera_height > camera_max_height:
		camera_height = camera_max_height * 0.5
	camera_rig.position = Vector3(0, camera_height, 0)

func _create_grid_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3, 0.3)
	mat.wireframe = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

# === 放置预览 ===

func _on_scale_changed(value: float) -> void:
	current_scale = value
	scale_value.text = "%.1f" % value
	if selected_obstacle and not selected_obstacle.is_empty() and is_instance_valid(selected_obstacle.node):
		var s = Vector3(current_scale, current_scale, current_scale)
		selected_obstacle.scale = s
		selected_obstacle.node.scale = s
		for child in selected_obstacle.node.get_children():
			if child is CollisionShape3D:
				if selected_obstacle.type == "model" and _objects:
					child.shape.size = _objects.get_model_aabb_size(selected_obstacle.model_path) * current_scale
				elif selected_obstacle.type == "building":
					child.shape.size = s * 4.0
				elif selected_obstacle.type == "ramp":
					child.shape.size = Vector3(s.x * 6.0, s.y * 0.5, s.z * 8.0)
				else:
					child.shape.radius = current_scale * 1.5
	elif selected_obstacle and not selected_obstacle.is_empty():
		selected_obstacle = {}
		_update_selected_label()
	if is_placing and placement_preview and is_instance_valid(placement_preview):
		placement_preview.scale = Vector3(current_scale, current_scale, current_scale)

func _on_place_mode_toggled(pressed: bool) -> void:
	is_placing = pressed
	place_mode_toggle.text = "放置模式" if pressed else "选择模式"
	place_mode_toggle.modulate = Color(0.4, 1.0, 0.5, 1.0) if pressed else Color(1.0, 0.8, 0.3, 1.0)
	if is_placing:
		_create_placement_preview()
		selected_obstacle = {}
		_update_selected_label()
	else:
		_clear_placement_preview()
	_update_status()

func _create_placement_preview() -> void:
	_clear_placement_preview()
	if current_obstacle_type == "grass":
		var root = Node3D.new()
		var mesh_inst = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = current_grass_radius
		cylinder.bottom_radius = current_grass_radius
		cylinder.height = 0.3
		mesh_inst.mesh = cylinder
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.7, 0.2, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat
		root.add_child(mesh_inst)
		placement_preview = root
		add_child(placement_preview)
		preview_valid = false
		return
	if current_obstacle_type == "bush":
		var root = Node3D.new()
		var mesh_inst = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = current_bush_radius
		cylinder.bottom_radius = current_bush_radius
		cylinder.height = 3.0
		mesh_inst.mesh = cylinder
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.4, 0.12, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat
		root.add_child(mesh_inst)
		placement_preview = root
		add_child(placement_preview)
		preview_valid = false
		return
	if current_obstacle_type == "model" and current_model_path == "":
		return
	var s = Vector3(current_scale, current_scale, current_scale)
	placement_preview = _create_preview_node(current_obstacle_type, s, current_model_path)
	if placement_preview:
		placement_preview.name = "PlacementPreview"
		for mesh_inst in placement_preview.find_children("*", "MeshInstance3D"):
			if mesh_inst.mesh:
				var transparent_mat = StandardMaterial3D.new()
				transparent_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.4)
				transparent_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				transparent_mat.roughness = 0.6
				mesh_inst.material_override = transparent_mat
		for child in placement_preview.find_children("*", "CollisionShape3D"):
			child.queue_free()
		for child in placement_preview.find_children("*", "StaticBody3D"):
			child.queue_free()
		add_child(placement_preview)
		preview_valid = false

func _create_preview_node(type: String, scale: Vector3, model_path: String) -> Node3D:
	var root = Node3D.new()
	if type == "model" and model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var inst = model_scene.instantiate()
			inst.scale = scale
			root.add_child(inst)
		else:
			var mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = scale * 3.0
			mesh.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.5, 0.2, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = mat
			root.add_child(mesh)
	elif type == "building":
		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = scale * 4.0
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.5, 0.45, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		root.add_child(mesh)
	elif type == "ramp":
		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(scale.x * 6.0, scale.y * 0.5, scale.z * 8.0)
		mesh.mesh = box
		mesh.rotation.x = deg_to_rad(25)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.45, 0.35, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		root.add_child(mesh)
	else:
		var mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = scale.x * 1.5
		sphere.height = scale.y * 3.0
		mesh.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.42, 0.38, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		root.add_child(mesh)
	return root

func _clear_placement_preview() -> void:
	if placement_preview and is_instance_valid(placement_preview):
		placement_preview.queue_free()
	placement_preview = null
	preview_valid = false

func _update_placement_preview(mouse_pos: Vector2) -> void:
	if not placement_preview:
		return
	var hit = _raycast_ground(mouse_pos)
	if hit != Vector3.INF:
		placement_preview.position = hit
		placement_preview.visible = true
		preview_valid = true
	else:
		placement_preview.visible = false
		preview_valid = false

# === 射线检测 ===

func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * max(2000.0, camera_max_height * 2.0)
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result and result.has("position"):
		return result.position
	return Vector3.INF

func _raycast_obstacle(screen_pos: Vector2) -> Dictionary:
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4
	var result = space.intersect_ray(query)
	if result and result.has("collider"):
		var collider = result.collider
		for obs in obstacles:
			if is_instance_valid(obs.node) and (obs.node == collider or obs.node.is_ancestor_of(collider)):
				return obs
	return {}

func _find_obstacle_at(pos: Vector3) -> Dictionary:
	for obs in obstacles:
		var op = obs.position
		var obs_pos: Vector3 = Vector3(op[0], op[1], op[2]) if typeof(op) == TYPE_ARRAY else op
		var dist = obs_pos.distance_to(pos)
		var obs_scale = obs.scale
		var scale_vec: Vector3 = Vector3(obs_scale[0], obs_scale[1], obs_scale[2]) if typeof(obs_scale) == TYPE_ARRAY else obs_scale
		var radius = max(scale_vec.x, scale_vec.z) * 2.5
		if dist < radius:
			return obs
	for patch in grass_patches:
		var pp = patch.position
		var patch_pos = Vector3(pp[0], pp[1], pp[2]) if typeof(pp) == TYPE_ARRAY else pp
		var dist2 = patch_pos.distance_to(pos)
		if dist2 < patch.radius:
			return patch
	for patch in bush_patches:
		var pp2 = patch.position
		var patch_pos2 = Vector3(pp2[0], pp2[1], pp2[2]) if typeof(pp2) == TYPE_ARRAY else pp2
		var dist3 = patch_pos2.distance_to(pos)
		if dist3 < patch.radius:
			return patch
	return {}

# === 主输入处理 ===

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and _is_mouse_over_toolbar(event.position):
		return

	if is_terrain_mode and _terrain:
		_terrain.handle_input(event)
		return

	if is_color_paint_mode and _color_paint:
		_color_paint.handle_input(event)
		return

	# 摄像机缩放 / 草丛半径调整
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if current_obstacle_type == "grass" and event.shift_pressed:
			current_grass_radius = clamp(current_grass_radius + 5, 5, 100)
			_create_placement_preview()
			status_label.text = "草丛半径: %.0fm (Shift+滚轮调整)" % current_grass_radius
		elif current_obstacle_type == "bush" and event.shift_pressed:
			current_bush_radius = clamp(current_bush_radius + 5, 5, 100)
			_create_placement_preview()
			status_label.text = "灌木丛半径: %.0fm (Shift+滚轮调整)" % current_bush_radius
		else:
			var step: float = max(10.0, camera_height * 0.15)
			camera_height = max(camera_min_height, camera_height - step)
			camera_rig.position.y = camera_height
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if current_obstacle_type == "grass" and event.shift_pressed:
			current_grass_radius = clamp(current_grass_radius - 5, 5, 100)
			_create_placement_preview()
			status_label.text = "草丛半径: %.0fm (Shift+滚轮调整)" % current_grass_radius
		elif current_obstacle_type == "bush" and event.shift_pressed:
			current_bush_radius = clamp(current_bush_radius - 5, 5, 100)
			_create_placement_preview()
			status_label.text = "灌木丛半径: %.0fm (Shift+滚轮调整)" % current_bush_radius
		else:
			var step: float = max(10.0, camera_height * 0.15)
			camera_height = min(camera_max_height, camera_height + step)
			camera_rig.position.y = camera_height

	# 中键平移
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		is_panning = event.pressed
		pan_last_pos = event.position
	if event is InputEventMouseMotion and is_panning:
		var delta = event.position - pan_last_pos
		pan_last_pos = event.position
		camera_rig.position.x -= delta.x * (camera_height / 200.0)
		camera_rig.position.z -= delta.y * (camera_height / 200.0)

	# 鼠标移动：更新放置预览
	if event is InputEventMouseMotion:
		if is_placing and not is_panning:
			_update_placement_preview(event.position)

	# 左键：放置/选择/拖拽
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_placing_spawn or is_placing:
				var hit = _raycast_ground(event.position)
				if hit != Vector3.INF:
					if is_placing_spawn and _objects:
						_objects.place_spawn_point(hit)
					elif is_placing and _objects:
						_update_placement_preview(event.position)
						if placement_preview and is_instance_valid(placement_preview):
							placement_preview.position = hit
						_objects.place_obstacle(hit)
						_update_placement_preview(event.position)
			else:
				var clicked = _raycast_obstacle(event.position)
				if clicked.is_empty():
					var gh = _raycast_ground(event.position)
					if gh != Vector3.INF:
						clicked = _find_obstacle_at(gh)
				if not clicked.is_empty():
					if clicked.get("type", "") == "grass":
						selected_grass = clicked
						selected_obstacle = {}
						selected_bush = {}
					elif clicked.get("type", "") == "bush":
						selected_bush = clicked
						selected_obstacle = {}
						selected_grass = {}
					else:
						selected_obstacle = clicked
						selected_grass = {}
						selected_bush = {}
					is_dragging = true
					var gh = _raycast_ground(event.position)
					if gh != Vector3.INF:
						var cp = clicked.position
						var clicked_pos = Vector3(cp[0], cp[1], cp[2]) if typeof(cp) == TYPE_ARRAY else cp
						drag_offset = clicked_pos - gh
					_update_selected_label()
				else:
					selected_obstacle = {}
					selected_grass = {}
					selected_bush = {}
					_update_selected_label()
		else:
			is_dragging = false

	# 右键：删除/切换模式
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_placing:
			place_mode_toggle.button_pressed = false
		else:
			var clicked = _raycast_obstacle(event.position)
			if clicked.is_empty():
				var gh = _raycast_ground(event.position)
				if gh != Vector3.INF:
					clicked = _find_obstacle_at(gh)
			if not clicked.is_empty() and _objects:
				if clicked.get("type", "") == "grass":
					_objects.remove_grass(clicked)
				elif clicked.get("type", "") == "bush":
					_objects.remove_bush(clicked)
				else:
					_objects.remove_obstacle(clicked)

	# 拖拽移动
	if event is InputEventMouseMotion and is_dragging:
		var hit = _raycast_ground(event.position)
		if hit != Vector3.INF:
			var new_pos = hit + drag_offset
			# 安全检查：防止拖拽到异常位置
			if new_pos.x == new_pos.x and new_pos.y == new_pos.y and new_pos.z == new_pos.z and abs(new_pos.x) < 10000 and abs(new_pos.z) < 10000:
				if selected_obstacle and not selected_obstacle.is_empty() and is_instance_valid(selected_obstacle.node):
					var obs_pos = selected_obstacle.position
					var obs_y: float = obs_pos.y if typeof(obs_pos) != TYPE_ARRAY else obs_pos[1]
					new_pos.y = obs_y
					selected_obstacle.position = new_pos
					selected_obstacle.node.position = new_pos
				elif selected_grass and not selected_grass.is_empty() and is_instance_valid(selected_grass.node):
					selected_grass.position = [new_pos.x, new_pos.y, new_pos.z]
					selected_grass.node.position = new_pos
				elif selected_bush and not selected_bush.is_empty() and is_instance_valid(selected_bush.node):
					selected_bush.position = [new_pos.x, new_pos.y, new_pos.z]
					selected_bush.node.position = new_pos

	# Delete键删除
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		if selected_obstacle and not selected_obstacle.is_empty() and _objects:
			_objects.remove_obstacle(selected_obstacle)
			selected_obstacle = {}
			_update_selected_label()
		elif selected_grass and not selected_grass.is_empty() and _objects:
			_objects.remove_grass(selected_grass)
			selected_grass = {}
			_update_selected_label()
		elif selected_bush and not selected_bush.is_empty() and _objects:
			_objects.remove_bush(selected_bush)
			selected_bush = {}
			_update_selected_label()

	# R/T旋转，W/S高低
	if event is InputEventKey and event.pressed and selected_obstacle and not selected_obstacle.is_empty() and is_instance_valid(selected_obstacle.node):
		if event.keycode == KEY_R:
			selected_obstacle.node.rotate_y(deg_to_rad(15))
			selected_obstacle.rotation = [rad_to_deg(selected_obstacle.node.rotation.x), rad_to_deg(selected_obstacle.node.rotation.y), rad_to_deg(selected_obstacle.node.rotation.z)]
			_update_selected_label()
		elif event.keycode == KEY_T:
			selected_obstacle.node.rotate_x(deg_to_rad(15))
			selected_obstacle.rotation = [rad_to_deg(selected_obstacle.node.rotation.x), rad_to_deg(selected_obstacle.node.rotation.y), rad_to_deg(selected_obstacle.node.rotation.z)]
			_update_selected_label()
		elif event.keycode == KEY_W:
			var new_pos = selected_obstacle.node.position
			new_pos.y += 0.5
			selected_obstacle.node.position = new_pos
			selected_obstacle.position = new_pos
			_update_selected_label()
		elif event.keycode == KEY_S:
			var new_pos = selected_obstacle.node.position
			new_pos.y -= 0.5
			selected_obstacle.node.position = new_pos
			selected_obstacle.position = new_pos
			_update_selected_label()

	# 空格切换模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		place_mode_toggle.button_pressed = not place_mode_toggle.button_pressed
		get_viewport().set_input_as_handled()

	# ESC返回
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_placing_spawn:
			is_placing_spawn = false
			spawn_toggle.button_pressed = false
			_update_status()
		elif is_placing:
			place_mode_toggle.button_pressed = false
		else:
			_on_back()

func _is_mouse_over_toolbar(pos: Vector2) -> bool:
	return pos.y < 98.0

# === UI回调转发 ===

func _on_import_model() -> void:
	if _io:
		_io.on_import_model()

func _on_model_selected(index: int) -> void:
	if _io:
		_io.on_model_selected(index)

func _on_color_picked(color: Color) -> void:
	if _color_paint:
		_color_paint.on_color_picked(color)

func _on_save() -> void:
	if _io:
		_io.on_save()

func _on_load() -> void:
	if _io:
		_io.on_load()

func _on_new() -> void:
	if _io:
		_io.on_new()

func _on_clear() -> void:
	if _io:
		_io.on_clear()

func _on_back() -> void:
	if _io:
		_io.on_back()

func _on_spawn_toggle() -> void:
	is_placing_spawn = spawn_toggle.button_pressed
	spawn_team = 1
	if is_placing_spawn:
		_clear_placement_preview()
	elif is_placing:
		_create_placement_preview()
	_update_status()

func _on_obstacle_type_changed(index: int) -> void:
	match index:
		0: current_obstacle_type = "rock"
		1: current_obstacle_type = "building"
		2:
			current_obstacle_type = "model"
			if current_model_path == "":
				status_label.text = "请先点击\"导入模型\"或从下拉列表选择模型"
				status_label.modulate = Color(1, 0.8, 0.3)
		3: current_obstacle_type = "ramp"
		4:
			current_obstacle_type = "grass"
			status_label.text = "草丛模式: 半径%.0fm, 密度%.1f (Shift+滚轮调整半径)" % [current_grass_radius, current_grass_density]
			status_label.modulate = Color(0.5, 0.8, 0.4)
		5:
			current_obstacle_type = "bush"
			status_label.text = "灌木丛模式: 半径%.0fm, 密度%.1f (Shift+滚轮调整半径)" % [current_bush_radius, current_bush_density]
			status_label.modulate = Color(0.3, 0.6, 0.2)
		6:
			current_obstacle_type = "terrain"
			is_terrain_mode = true
			is_color_paint_mode = false
			if _color_paint:
				_color_paint.clear_color_brush_indicator()
			_clear_placement_preview()
			if _terrain:
				_terrain.create_brush_indicator()
			status_label.text = "地形模式: 左键抬升, 右键降低, F平整, Shift+滚轮半径(%.0fm), Ctrl+滚轮强度(%.1f)" % [terrain_brush_radius, terrain_brush_strength]
			status_label.modulate = Color(0.9, 0.7, 0.3)
			_update_status()
			return
		7:
			current_obstacle_type = "color_paint"
			is_color_paint_mode = true
			is_terrain_mode = false
			if _terrain:
				_terrain.clear_brush_indicator()
			_clear_placement_preview()
			if _color_paint:
				_color_paint.create_color_brush_indicator()
			var c: Color = color_picker_button.color
			status_label.text = "地面颜色模式: 左键绘制, 右键擦除, Shift+滚轮半径(%.0fm) 颜色: R%.2f G%.2f B%.2f" % [color_brush_radius, c.r, c.g, c.b]
			status_label.modulate = Color(0.7, 0.9, 0.5)
			_update_status()
			return
	is_terrain_mode = false
	is_color_paint_mode = false
	if _terrain:
		_terrain.clear_brush_indicator()
	if _color_paint:
		_color_paint.clear_color_brush_indicator()
	if not is_placing:
		place_mode_toggle.button_pressed = true
	elif is_placing:
		_create_placement_preview()
	_update_status()

# === 状态显示 ===

func _update_status() -> void:
	var mode_text = ""
	if is_terrain_mode:
		mode_text = "地形模式 - 左键抬升, 右键降低, F平整, Shift+滚轮半径(%.0fm), Ctrl+滚轮强度(%.1f)" % [terrain_brush_radius, terrain_brush_strength]
	elif is_placing_spawn:
		mode_text = "放置出生点(队伍%d)" % spawn_team
	elif is_placing:
		mode_text = "放置模式(%s) - 左键放置, 右键切换选择" % current_obstacle_type
	else:
		mode_text = "选择模式 - 左键选中/拖拽, 右键删除, R水平旋转, T竖直旋转, W/S高低, Delete删除"
	status_label.text = "%s | 障碍物: %d | 草丛: %d | 灌木: %d | 出生点: %d | 滚轮缩放 | 中键平移" % [mode_text, obstacles.size(), grass_patches.size(), bush_patches.size(), spawn_points.size()]

func _update_selected_label() -> void:
	if not selected_bush.is_empty():
		var pos = selected_bush.position
		selected_label.text = "选中: 灌木丛 @ (%.1f, %.1f, %.1f) 半径: %.0fm 密度: %.1f" % [
			pos[0], pos[1], pos[2],
			selected_bush.radius, selected_bush.density
		]
		return
	if not selected_grass.is_empty():
		var pos = selected_grass.position
		selected_label.text = "选中: 草丛 @ (%.1f, %.1f, %.1f) 半径: %.0fm 密度: %.1f" % [
			pos[0], pos[1], pos[2],
			selected_grass.radius, selected_grass.density
		]
		return
	if selected_obstacle.is_empty():
		selected_label.text = "未选中"
	else:
		var type_text = selected_obstacle.type
		if selected_obstacle.type == "model" and selected_obstacle.model_path != "":
			type_text = "模型: %s" % selected_obstacle.model_path.get_file()
		var s = selected_obstacle.scale.x if selected_obstacle.has("scale") else 1.0
		var rot = selected_obstacle.rotation
		var rot_text: String
		if typeof(rot) == TYPE_ARRAY:
			rot_text = "旋转: (%.0f, %.0f, %.0f)°" % [rot[0], rot[1], rot[2]]
		else:
			rot_text = "旋转: %.0f°" % rot
		selected_label.text = "选中: %s @ (%.1f, %.1f, %.1f) 缩放: %.1f %s" % [type_text, selected_obstacle.position.x, selected_obstacle.position.y, selected_obstacle.position.z, s, rot_text]
		if scale_slider and abs(scale_slider.value - s) > 0.01:
			scale_slider.value = s
