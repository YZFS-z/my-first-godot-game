extends Node3D
## 关卡编辑器 - 在地图上放置双方坦克，定义型号和位置

signal level_saved(level_id: String)

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var ground_mesh_node: MeshInstance3D = $Ground
@onready var ground_collision: StaticBody3D = $GroundCollision
@onready var tank_markers: Node3D = $TankMarkers
@onready var map_option: OptionButton = $UILayer/Panel/Toolbar/MapOption
@onready var team_option: OptionButton = $UILayer/Panel/Toolbar/TeamOption
@onready var vehicle_option: OptionButton = $UILayer/Panel/Toolbar/VehicleOption
@onready var level_name_input: LineEdit = $UILayer/Panel/Toolbar/LevelNameInput
@onready var save_button: Button = $UILayer/Panel/Toolbar/SaveButton
@onready var load_button: Button = $UILayer/Panel/Toolbar/LoadButton
@onready var clear_button: Button = $UILayer/Panel/Toolbar/ClearButton
@onready var back_button: Button = $UILayer/Panel/Toolbar/BackButton
@onready var status_label: Label = $UILayer/StatusLabel
@onready var count_label: Label = $UILayer/CountLabel
@onready var load_file_dialog: FileDialog = $UILayer/LoadFileDialog

var placed_tanks: Array = []  # {node, team, vehicle_id, position, rotation}
var current_team: int = 1
var current_vehicle_id: String = ""
var current_map_id: String = ""
var current_map_size: float = 400.0
var map_ids: Array = []
var vehicle_ids: Array = []
var _loading_level: bool = false  # 加载关卡时抑制信号副作用

# 摄像机
var cam_height: float = 80.0
var cam_max_height: float = 200.0
var cam_x: float = 0.0
var cam_z: float = 0.0
var is_panning: bool = false
var pan_last: Vector2 = Vector2.ZERO

func _ready() -> void:
	_populate_maps()
	_populate_vehicles()
	_populate_teams()
	_connect_signals()
	# 初始加载第一个地图的地形
	if current_map_id != "":
		_rebuild_ground_for_map(current_map_id)
	_reset_camera_view()
	_update_count()
	print("[LevelEditor] Ready")

func _reset_camera_view() -> void:
	"""重置相机为纯俯视视角，定位到地图中心，高度确保能看到整个地图"""
	cam_x = 0.0
	cam_z = 0.0
	cam_max_height = max(500.0, current_map_size * 1.5)
	cam_height = current_map_size * 1.2
	camera_rig.position = Vector3(cam_x, cam_height, cam_z)
	camera_rig.rotation = Vector3.ZERO
	camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)

func _populate_maps() -> void:
	map_option.clear()
	map_ids.clear()
	var maps = DataLoader.get_all_maps()
	for id in maps.keys():
		map_ids.append(id)
		map_option.add_item(maps[id].get("name", id))
		map_option.set_item_metadata(map_option.item_count - 1, id)
	if map_ids.size() > 0:
		map_option.select(0)
		current_map_id = map_ids[0]

func _populate_vehicles() -> void:
	vehicle_option.clear()
	vehicle_ids.clear()
	var vehicles = DataLoader.get_all_vehicles()
	# 按类型分组
	var type_names: Dictionary = {
		"tank": "坦克",
		"helicopter": "直升机",
		"airplane": "飞机"
	}
	var type_order: Array = ["tank", "helicopter", "airplane"]
	var first_id: String = ""
	for vtype in type_order:
		var type_vehicles: Array = []
		for id in vehicles.keys():
			if vehicles[id].get("type", "tank") == vtype:
				type_vehicles.append(id)
		if type_vehicles.size() > 0:
			# 添加分组标题（不可选）
			vehicle_option.add_item("—— %s ——" % type_names.get(vtype, vtype))
			vehicle_option.set_item_disabled(vehicle_option.item_count - 1, true)
			for id in type_vehicles:
				vehicle_ids.append(id)
				vehicle_option.add_item("  " + vehicles[id].get("name", id))
				vehicle_option.set_item_metadata(vehicle_option.item_count - 1, id)
				if first_id == "":
					first_id = id
	if first_id != "":
		# 选中第一个可用载具（跳过禁用的分组标题）
		for i in range(vehicle_option.item_count):
			if not vehicle_option.is_item_disabled(i):
				vehicle_option.select(i)
				current_vehicle_id = vehicle_option.get_item_metadata(i)
				break

func _populate_teams() -> void:
	team_option.clear()
	team_option.add_item("友方(绿)", 1)
	team_option.add_item("敌方(红)", 2)
	team_option.select(0)

func _connect_signals() -> void:
	map_option.item_selected.connect(_on_map_changed)
	team_option.item_selected.connect(_on_team_changed)
	vehicle_option.item_selected.connect(_on_vehicle_changed)
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	clear_button.pressed.connect(_on_clear)
	back_button.pressed.connect(_on_back)
	load_file_dialog.file_selected.connect(_on_load_file_selected)

func _on_map_changed(index: int) -> void:
	current_map_id = map_option.get_item_metadata(index)
	# 加载关卡时由 _load_level_data 统一重建，避免重复
	if not _loading_level:
		_rebuild_ground_for_map(current_map_id)
		_reset_camera_view()

func _rebuild_ground_for_map(map_id: String) -> void:
	"""根据选中地图重建地面网格和碰撞体（含地形高度图）"""
	var map_data = DataLoader.get_map(map_id)
	if map_data.is_empty():
		return
	var map_size = float(map_data.get("size", 400))
	current_map_size = map_size
	var ground_color = map_data.get("ground_color", [0.5, 0.55, 0.4])
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(ground_color[0], ground_color[1], ground_color[2], 1.0)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# 清除旧的碰撞形状
	for child in ground_collision.get_children():
		child.queue_free()

	var terrain_data = map_data.get("terrain", {})
	if terrain_data.is_empty():
		# 无地形：平坦 PlaneMesh + BoxShape3D
		var plane = PlaneMesh.new()
		plane.size = Vector2(map_size, map_size)
		plane.subdivide_width = 40
		plane.subdivide_depth = 40
		ground_mesh_node.mesh = plane
		ground_mesh_node.material_override = mat
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(map_size, 1.0, map_size)
		col.shape = shape
		col.position = Vector3(0, -0.5, 0)
		ground_collision.add_child(col)
	else:
		# 有地形：从高度图构建网格 + trimesh 碰撞
		var grid_size = int(terrain_data.get("grid_size", 64))
		var heights = terrain_data.get("heights", [])
		var n = grid_size + 1
		var half = map_size * 0.5
		var cell = map_size / float(grid_size)
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for z in range(n):
			for x in range(n):
				var idx = z * n + x
				var h = float(heights[idx]) if idx < heights.size() else 0.0
				var uv_x = float(x) / float(grid_size)
				var uv_y = float(z) / float(grid_size)
				st.set_uv(Vector2(uv_x, uv_y))
				st.add_vertex(Vector3(x * cell - half, h, z * cell - half))
		for z in range(grid_size):
			for x in range(grid_size):
				var i = z * n + x
				st.add_index(i)
				st.add_index(i + n)
				st.add_index(i + 1)
				st.add_index(i + 1)
				st.add_index(i + n)
				st.add_index(i + n + 1)
		st.generate_normals()
		ground_mesh_node.mesh = st.commit()
		# 加载颜色纹理（如果地图有保存）
		var color_tex_name = terrain_data.get("color_texture", "")
		if color_tex_name != "":
			var color_paths = [
				"user://data/maps/" + color_tex_name,
				"res://data/maps/" + color_tex_name
			]
			for cp in color_paths:
				if FileAccess.file_exists(cp):
					var color_img = Image.load_from_file(cp)
					if color_img:
						mat.albedo_texture = ImageTexture.create_from_image(color_img)
						# 有纹理时 albedo_color 必须为白色（否则与纹理相乘导致颜色被压暗）
						mat.albedo_color = Color.WHITE
					break
		ground_mesh_node.material_override = mat
		var col = CollisionShape3D.new()
		col.shape = ground_mesh_node.mesh.create_trimesh_shape()
		ground_collision.add_child(col)

	# 调整摄像机高度以适应地形规模（纯俯视需要足够高度看到整个地图）
	cam_max_height = max(500.0, map_size * 1.5)
	cam_height = map_size * 1.2
	_update_camera()
	print("[LevelEditor] Ground rebuilt for map: %s (size=%.0f, terrain=%s)" % [
		map_id, map_size, "yes" if not terrain_data.is_empty() else "no"])

func _on_team_changed(index: int) -> void:
	current_team = team_option.get_item_id(index)

func _on_vehicle_changed(index: int) -> void:
	current_vehicle_id = vehicle_option.get_item_metadata(index)

func _unhandled_input(event: InputEvent) -> void:
	# 使用 _unhandled_input 避免UI控件（顶部菜单栏等）上的点击被地图捕获
	# 滚轮缩放
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		var step = max(10.0, cam_height * 0.15)
		cam_height = clamp(cam_height - step, 20.0, cam_max_height)
		_update_camera()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step = max(10.0, cam_height * 0.15)
		cam_height = clamp(cam_height + step, 20.0, cam_max_height)
		_update_camera()

	# 中键拖动
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		is_panning = event.pressed
		pan_last = event.position
	elif event is InputEventMouseMotion and is_panning:
		var delta = event.position - pan_last
		cam_x -= delta.x * 0.3
		cam_z -= delta.y * 0.3
		pan_last = event.position
		_update_camera()

	# 左键放置
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not is_panning:
		_place_tank(event.position)
	# 右键删除
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_delete_tank(event.position)

func _update_camera() -> void:
	camera_rig.position = Vector3(cam_x, cam_height, cam_z)

func _raycast_ground(screen_pos: Vector2) -> Vector3:
	"""从屏幕坐标射线检测地面，返回世界坐标（射线失败时用地形高度图兜底）"""
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	var to = from + dir * 2000.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to, 1)
	var result = space.intersect_ray(query)
	if result:
		return result.position
	# 射线检测失败（trimesh 碰撞体在某些位置可能失效），用地形高度图兜底
	# 计算射线与 y=0 平面的交点，获取 (x,z) 坐标
	if abs(dir.y) > 0.001:
		var t = -from.y / dir.y
		if t > 0:
			var x = from.x + dir.x * t
			var z = from.z + dir.z * t
			var h = _get_terrain_height(x, z)
			return Vector3(x, h, z)
	return Vector3.ZERO

func _get_vehicle_type(vehicle_id: String) -> String:
	"""获取载具类型（tank/helicopter/airplane）"""
	var vdata = DataLoader.get_vehicle(vehicle_id)
	if vdata.is_empty():
		return "tank"
	return vdata.get("type", "tank")

func _get_terrain_height(x: float, z: float) -> float:
	"""从地形高度图采样指定(x,z)位置的地面高度，无地形返回0"""
	var map_data = DataLoader.get_map(current_map_id)
	if map_data.is_empty():
		return 0.0
	var terrain_data = map_data.get("terrain", {})
	if terrain_data.is_empty():
		return 0.0
	var grid_size = int(terrain_data.get("grid_size", 64))
	var heights = terrain_data.get("heights", [])
	if heights.is_empty():
		return 0.0
	var map_size = float(map_data.get("size", 400))
	var n = grid_size + 1
	var half = map_size * 0.5
	var cell = map_size / float(grid_size)
	var gx = clampf((x + half) / cell, 0.0, float(grid_size))
	var gz = clampf((z + half) / cell, 0.0, float(grid_size))
	var x0 = int(gx)
	var z0 = int(gz)
	var x1 = min(x0 + 1, grid_size)
	var z1 = min(z0 + 1, grid_size)
	var fx = gx - x0
	var fz = gz - z0
	var h00 = float(heights[z0 * n + x0]) if z0 * n + x0 < heights.size() else 0.0
	var h10 = float(heights[z0 * n + x1]) if z0 * n + x1 < heights.size() else 0.0
	var h01 = float(heights[z1 * n + x0]) if z1 * n + x0 < heights.size() else 0.0
	var h11 = float(heights[z1 * n + x1]) if z1 * n + x1 < heights.size() else 0.0
	var h0 = lerpf(h00, h10, fx)
	var h1 = lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)

func _place_tank(screen_pos: Vector2) -> void:
	var pos = _raycast_ground(screen_pos)
	if pos == Vector3.ZERO:
		return
	# 使用地形高度图采样准确的地面高度，避免射线检测到山坡侧面导致载具卡在山里
	var terrain_h = _get_terrain_height(pos.x, pos.z)
	var marker_scale: float = max(1.0, current_map_size / 200.0)
	var vtype = _get_vehicle_type(current_vehicle_id)
	# 载具底部在地面上方，中心高度 = 地面高度 + 载具高度的一半 + 安全偏移
	# 注意：高度计算使用固定值，不随 marker_scale 变化（marker_scale 只用于视觉显示）
	var vehicle_height = 2.0 if vtype == "tank" else 3.0
	pos.y = terrain_h + vehicle_height * 0.5 + 1.0

	# 创建标记（StaticBody3D + Mesh + Collision + Label）
	var marker = StaticBody3D.new()
	marker.collision_layer = 2
	marker.collision_mask = 0
	marker.position = pos

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3 * marker_scale, 1.5 * marker_scale, 5 * marker_scale)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	# 按载具类型区分颜色：坦克=绿/红，直升机=青/橙，飞机=蓝/黄
	if vtype == "helicopter":
		mat.albedo_color = Color(0.2, 0.7, 0.9, 1.0) if current_team == 1 else Color(0.9, 0.6, 0.2, 1.0)
	elif vtype == "airplane":
		mat.albedo_color = Color(0.4, 0.3, 0.9, 1.0) if current_team == 1 else Color(0.9, 0.8, 0.2, 1.0)
	else:
		mat.albedo_color = Color(0.2, 0.8, 0.2, 1.0) if current_team == 1 else Color(0.9, 0.2, 0.2, 1.0)
	mesh.material_override = mat
	marker.add_child(mesh)

	var col = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(3.5 * marker_scale, 2 * marker_scale, 5.5 * marker_scale)
	col.shape = col_shape
	marker.add_child(col)

	var label = Label3D.new()
	var vdata = DataLoader.get_vehicle(current_vehicle_id)
	label.text = vdata.get("name", current_vehicle_id)
	label.font_size = int(24 * marker_scale)
	label.position = Vector3(0, 2 * marker_scale, 0)
	marker.add_child(label)

	tank_markers.add_child(marker)

	placed_tanks.append({
		"node": marker,
		"team": current_team,
		"vehicle_id": current_vehicle_id,
		"position": [pos.x, pos.y, pos.z],
		"rotation": 0.0,
	})
	_update_count()
	status_label.text = "已放置: %s (阵营%d)" % [current_vehicle_id, current_team]

func _delete_tank(screen_pos: Vector2) -> void:
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	var to = from + dir * 2000.0
	var space = get_world_3d().direct_space_state
	# 检测标记层(2)
	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	var result = space.intersect_ray(query)
	if result and result.collider.get_parent() == tank_markers:
		var target = result.collider
		for i in range(placed_tanks.size()):
			if placed_tanks[i].node == target:
				placed_tanks.remove_at(i)
				break
		target.queue_free()
		_update_count()
		status_label.text = "已删除一辆坦克"

func _update_count() -> void:
	var friendly = 0
	var enemy = 0
	for t in placed_tanks:
		if t.team == 1:
			friendly += 1
		else:
			enemy += 1
	count_label.text = "友方: %d辆 | 敌方: %d辆 | 总计: %d辆" % [friendly, enemy, placed_tanks.size()]

func _on_save() -> void:
	var name = level_name_input.text.strip_edges()
	if name == "":
		name = "level_%d" % Time.get_unix_time_from_system()
		level_name_input.text = name
	var level_id = name.to_lower().replace(" ", "_")
	var data = {
		"id": level_id,
		"name": name,
		"map_id": current_map_id,
		"tanks": [],
	}
	for t in placed_tanks:
		data.tanks.append({
			"team": t.team,
			"vehicle_id": t.vehicle_id,
			"position": t.position,
			"rotation": t.rotation,
		})
	# 保存到 user:// 目录（导出后可写）
	var save_dir = "user://data/levels/"
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path = save_dir + "%s.json" % level_id
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		status_label.text = "已保存: %s (%d辆坦克)" % [path, placed_tanks.size()]
		level_saved.emit(level_id)
	else:
		status_label.text = "保存失败! 无法写入 %s" % path

func _on_load() -> void:
	# 扫描内置和自定义关卡目录，检查是否有可加载的关卡
	var has_files := false
	for dir_path in ["res://data/levels/", "user://data/levels/"]:
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file = dir.get_next()
			while file != "":
				if file.ends_with(".json"):
					has_files = true
					break
				file = dir.get_next()
			dir.list_dir_end()
		if has_files:
			break
	if not has_files:
		status_label.text = "没有已保存的关卡"
		return
	# 设置文件对话框初始目录为 user://data/levels/（转换为真实路径）
	var user_levels_dir = ProjectSettings.globalize_path("user://data/levels/")
	if DirAccess.dir_exists_absolute(user_levels_dir):
		load_file_dialog.current_dir = user_levels_dir
	else:
		# 回退到项目目录下的 data/levels/
		load_file_dialog.current_dir = ProjectSettings.globalize_path("res://data/levels/")
	# 弹出文件选择对话框，让用户选择关卡
	load_file_dialog.popup_centered()

func _on_load_file_selected(path: String) -> void:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		status_label.text = "无法打开文件: %s" % path
		return
	var text = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		status_label.text = "文件格式错误，不是有效的 JSON: %s" % path.get_file()
		return
	if not data.has("tanks"):
		status_label.text = "缺少 tanks 字段，不是有效的关卡文件: %s" % path.get_file()
		return
	_load_level_data(data)
	status_label.text = "已加载: %s (%d辆坦克)" % [path.get_file(), data.get("tanks", []).size()]

func _load_level_data(data: Dictionary) -> void:
	_loading_level = true
	_on_clear()
	_loading_level = false
	level_name_input.text = data.get("name", "")
	current_map_id = data.get("map_id", "")
	# 选中对应地图（信号被 _loading_level 抑制，下面统一重建）
	for i in range(map_option.item_count):
		if map_option.get_item_metadata(i) == current_map_id:
			map_option.select(i)
			break
	# 统一重建地形（避免信号+手动双重重建）
	_rebuild_ground_for_map(current_map_id)
	for t in data.get("tanks", []):
		var pos_arr = t.get("position", [0, 1, 0])
		var pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var team = int(t.get("team", 2))
		var vid = t.get("vehicle_id", "tank_t34_85")
		# 临时切换当前设置以放置
		var old_team = current_team
		var old_vid = current_vehicle_id
		current_team = team
		current_vehicle_id = vid
		_place_tank_at(pos)
		current_team = old_team
		current_vehicle_id = old_vid
	# 加载关卡后重置相机到地图中心，纯俯视
	_reset_camera_view()

func _place_tank_at(pos: Vector3) -> void:
	"""直接在指定位置放置坦克（用于加载）"""
	# 使用地形高度图采样准确的地面高度
	var terrain_h = _get_terrain_height(pos.x, pos.z)
	var marker_scale: float = max(1.0, current_map_size / 200.0)
	var vtype = _get_vehicle_type(current_vehicle_id)
	# 高度计算使用固定值，不随 marker_scale 变化
	var vehicle_height = 2.0 if vtype == "tank" else 3.0
	pos.y = terrain_h + vehicle_height * 0.5 + 1.0
	var marker = StaticBody3D.new()
	marker.collision_layer = 2
	marker.collision_mask = 0
	marker.position = pos

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(3 * marker_scale, 1.5 * marker_scale, 5 * marker_scale)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	# 按载具类型区分颜色：坦克=绿/红，直升机=青/橙，飞机=蓝/黄
	if vtype == "helicopter":
		mat.albedo_color = Color(0.2, 0.7, 0.9, 1.0) if current_team == 1 else Color(0.9, 0.6, 0.2, 1.0)
	elif vtype == "airplane":
		mat.albedo_color = Color(0.4, 0.3, 0.9, 1.0) if current_team == 1 else Color(0.9, 0.8, 0.2, 1.0)
	else:
		mat.albedo_color = Color(0.2, 0.8, 0.2, 1.0) if current_team == 1 else Color(0.9, 0.2, 0.2, 1.0)
	mesh.material_override = mat
	marker.add_child(mesh)

	var col = CollisionShape3D.new()
	var col_shape = BoxShape3D.new()
	col_shape.size = Vector3(3.5 * marker_scale, 2 * marker_scale, 5.5 * marker_scale)
	col.shape = col_shape
	marker.add_child(col)

	var label = Label3D.new()
	var vdata = DataLoader.get_vehicle(current_vehicle_id)
	label.text = vdata.get("name", current_vehicle_id)
	label.font_size = int(24 * marker_scale)
	label.position = Vector3(0, 2 * marker_scale, 0)
	marker.add_child(label)

	tank_markers.add_child(marker)

	placed_tanks.append({
		"node": marker,
		"team": current_team,
		"vehicle_id": current_vehicle_id,
		"position": [pos.x, pos.y, pos.z],
		"rotation": 0.0,
	})
	_update_count()

func _on_clear() -> void:
	for t in placed_tanks:
		if is_instance_valid(t.node):
			t.node.queue_free()
	placed_tanks.clear()
	_update_count()
	if not _loading_level:
		status_label.text = "已清空"

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
