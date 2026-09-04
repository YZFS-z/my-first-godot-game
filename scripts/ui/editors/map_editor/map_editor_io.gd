extends Node3D
## 地图编辑器 - 地图IO与模型导入
## 职责：地图保存/加载/新建/清除、模型导入与扫描、文件对话框
## 作为 MapEditor 节点的子节点，通过 get_parent() 访问共享状态

func _get_editor() -> Node:
	return get_parent()

func setup_file_dialog() -> void:
	var editor = _get_editor()
	editor.model_file_dialog = FileDialog.new()
	editor.model_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	editor.model_file_dialog.title = "选择3D模型文件"
	editor.model_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	editor.model_file_dialog.filters = PackedStringArray([
		"*.glb ; GLTF Binary",
		"*.gltf ; GLTF Text",
		"*.obj ; Wavefront OBJ",
		"*.fbx ; Autodesk FBX",
		"*.dae ; Collada",
		"*.tscn ; Godot Scene",
	])
	editor.model_file_dialog.file_selected.connect(on_model_file_selected)
	editor.add_child(editor.model_file_dialog)

func on_import_model() -> void:
	var editor = _get_editor()
	editor.model_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	editor.model_file_dialog.popup_centered_ratio(0.6)

func on_model_file_selected(path: String) -> void:
	var editor = _get_editor()
	var target_dir = "user://assets/map_models"
	DirAccess.make_dir_recursive_absolute(target_dir)
	var file_name = path.get_file()
	var target_path = "%s/%s" % [target_dir, file_name]
	var base_name = file_name.get_basename()
	var ext = file_name.get_extension()
	var counter = 1
	while ResourceLoader.exists(target_path):
		target_path = "%s/%s_%d.%s" % [target_dir, base_name, counter, ext]
		counter += 1
	var source_file = FileAccess.open(path, FileAccess.READ)
	if not source_file:
		editor.status_label.text = "无法读取文件: %s" % path
		editor.status_label.modulate = Color(1, 0.3, 0.3)
		return
	var data = source_file.get_buffer(source_file.get_length())
	source_file.close()
	var dest_file = FileAccess.open(target_path, FileAccess.WRITE)
	if not dest_file:
		editor.status_label.text = "无法写入: %s" % target_path
		editor.status_label.modulate = Color(1, 0.3, 0.3)
		return
	dest_file.store_buffer(data)
	dest_file.close()
	editor.current_model_path = target_path
	editor.current_obstacle_type = "model"
	editor.obstacle_option.select(2)
	var test = load(target_path)
	if test:
		editor.status_label.text = "已导入模型: %s，点击地面放置" % file_name
		editor.status_label.modulate = Color(0.3, 1, 0.3)
		scan_imported_models()
		for i in range(editor.model_option.item_count):
			if editor.model_option.get_item_metadata(i) == target_path:
				editor.model_option.select(i)
				break
		editor._create_placement_preview()
	else:
		editor.status_label.text = "模型已复制，但需重启游戏让Godot导入后才能使用: %s" % file_name
		editor.status_label.modulate = Color(1, 0.8, 0.3)
	editor._update_status()

func scan_imported_models() -> void:
	var editor = _get_editor()
	editor.model_option.clear()
	editor.model_option.add_item("（选择模型）")
	editor.model_option.set_item_metadata(0, "")
	scan_models_in_dir("res://assets/map_models/")
	scan_models_in_dir("user://assets/map_models/")

func scan_models_in_dir(dir_path: String) -> void:
	var editor = _get_editor()
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if not file.begins_with(".") and (file.ends_with(".tscn") or file.ends_with(".glb") or file.ends_with(".gltf")):
			var path = dir_path + file
			var test_load = load(path)
			if test_load:
				editor.model_option.add_item(file)
				editor.model_option.set_item_metadata(editor.model_option.item_count - 1, path)
			else:
				print("[MapEditor] 模型未导入，跳过: %s" % path)
		file = dir.get_next()
	dir.list_dir_end()

func on_model_selected(index: int) -> void:
	var editor = _get_editor()
	var path = editor.model_option.get_item_metadata(index)
	if path == "" or path == null:
		return
	editor.current_model_path = path
	editor.current_obstacle_type = "model"
	editor.obstacle_option.select(2)
	editor.status_label.text = "已选择模型: %s" % path.get_file()
	editor.status_label.modulate = Color(0.3, 1, 0.3)
	if not editor.is_placing:
		editor.place_mode_toggle.button_pressed = true
	else:
		editor._create_placement_preview()

func on_save() -> void:
	var editor = _get_editor()
	var map_id = editor.map_name_input.text.strip_edges()
	if map_id == "":
		editor.status_label.text = "请输入地图名称/ID！"
		editor.status_label.modulate = Color(1, 0.3, 0.3)
		return
	if not map_id.begins_with("map_"):
		map_id = "map_" + map_id

	var map_data = {
		"id": map_id,
		"name": editor.map_name_input.text,
		"source": "custom",
		"description": "由地图编辑器创建",
		"scene_path": "res://scenes/main.tscn",
		"ground_color": [0.6, 0.55, 0.4],
		"sky_color": [0.5, 0.65, 0.85],
		"size": int(editor.map_size),
		"air_boundary_size": int(editor.air_boundary_input.text) if editor.air_boundary_input.text.is_valid_float() else 0,
		"spawn_points": editor.spawn_points,
		"obstacles": [],
		"grass_patches": []
	}

	for obs in editor.obstacles:
		var obs_data: Dictionary = {
			"type": obs.type,
			"position": [obs.position.x, obs.position.y, obs.position.z],
			"scale": [obs.scale.x, obs.scale.y, obs.scale.z],
			"rotation": [rad_to_deg(obs.node.rotation.x), rad_to_deg(obs.node.rotation.y), rad_to_deg(obs.node.rotation.z)],
		}
		if obs.type == "model":
			obs_data["model_path"] = obs.model_path
		map_data["obstacles"].append(obs_data)

	for patch in editor.grass_patches:
		map_data["grass_patches"].append({
			"position": patch.position,
			"radius": patch.radius,
			"density": patch.density
		})
	map_data["bush_patches"] = []
	for patch in editor.bush_patches:
		map_data["bush_patches"].append({
			"position": patch.position,
			"radius": patch.radius,
			"density": patch.density
		})

	var save_dir = "user://data/maps/"
	var dir = DirAccess.open(save_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(save_dir)

	var terrain_data = {
		"grid_size": editor.terrain_grid_size,
		"heights": editor.terrain_heights
	}
	if editor.color_image != null:
		var color_png_name = "%s_color.png" % map_id
		var color_png_path = save_dir + color_png_name
		var save_err = editor.color_image.save_png(color_png_path)
		if save_err == OK:
			terrain_data["color_texture"] = color_png_name
			terrain_data["color_resolution"] = editor.color_resolution
			editor.color_texture_filename = color_png_name
	map_data["terrain"] = terrain_data

	var file_path = save_dir + "%s.json" % map_id
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(map_data, "  "))
		file.close()
		DataLoader.load_maps()
		editor.status_label.text = "已保存: %s" % file_path
		editor.status_label.modulate = Color(0.3, 1, 0.3)
		editor.map_saved.emit(map_id)
	else:
		editor.status_label.text = "保存失败！无法写入 %s" % file_path
		editor.status_label.modulate = Color(1, 0.3, 0.3)

func on_load() -> void:
	var editor = _get_editor()
	var map_id = editor.map_name_input.text.strip_edges()
	if not map_id.begins_with("map_"):
		map_id = "map_" + map_id
	var data = DataLoader.get_map(map_id)
	if data.is_empty():
		editor.status_label.text = "地图不存在: %s" % map_id
		editor.status_label.modulate = Color(1, 0.3, 0.3)
		return
	load_map_data(data)
	editor.status_label.text = "已加载: %s" % data.get("name", map_id)
	editor.status_label.modulate = Color(0.3, 1, 0.3)

func load_map_data(data: Dictionary) -> void:
	var editor = _get_editor()
	var objects = editor.get_node_or_null("MapObjects")
	var terrain = editor.get_node_or_null("MapTerrain")
	var color_paint = editor.get_node_or_null("MapColorPaint")
	on_clear()
	editor.map_name_input.text = data.get("name", "")
	editor.map_size_input.text = str(data.get("size", 200))
	editor.map_size = data.get("size", 200)
	editor.air_boundary_input.text = str(data.get("air_boundary_size", 12000))
	var gc = data.get("ground_color", [0.6, 0.55, 0.4])
	editor.default_ground_color = Color(gc[0], gc[1], gc[2], 1.0)
	editor.color_brush_radius = max(15.0, editor.map_size * 0.05)
	var terrain_data: Dictionary = data.get("terrain", {})
	if not terrain_data.is_empty():
		editor.terrain_grid_size = int(terrain_data.get("grid_size", 64))
		var saved_heights = terrain_data.get("heights", [])
		var n: int = int(editor.terrain_grid_size) + 1
		editor.terrain_heights.resize(n * n)
		for i in range(min(saved_heights.size(), n * n)):
			editor.terrain_heights[i] = float(saved_heights[i])
	else:
		editor.terrain_grid_size = 64
		if terrain:
			terrain.init_terrain_heights()
	var saved_color_texture: String = terrain_data.get("color_texture", "")
	var saved_color_res: int = int(terrain_data.get("color_resolution", editor.color_resolution))
	if saved_color_res != editor.color_resolution:
		editor.color_resolution = saved_color_res
		editor.color_image = null
	editor._setup_ground(false)
	if saved_color_texture != "":
		editor.color_texture_filename = saved_color_texture
		var load_paths = [
			"user://data/maps/" + saved_color_texture,
			"res://data/maps/" + saved_color_texture
		]
		var loaded: bool = false
		for lp in load_paths:
			if FileAccess.file_exists(lp):
				var img = Image.load_from_file(lp)
				if img:
					editor.color_image = img
					editor.color_resolution = img.get_width()
					editor.color_texture = ImageTexture.create_from_image(editor.color_image)
					if editor.terrain_ground_material:
						editor.terrain_ground_material.albedo_texture = editor.color_texture
					loaded = true
					break
		if not loaded:
			print("[MapEditor] 颜色纹理未找到: %s" % saved_color_texture)

	for obs_data in data.get("obstacles", []):
		var pos = obs_data.get("position", [0, 1, 0])
		var scale = obs_data.get("scale", [1, 1, 1])
		var obs_type = obs_data.get("type", "rock")
		var model_path = obs_data.get("model_path", "")
		var obs = objects.create_obstacle_node(obs_type, Vector3(pos[0], pos[1], pos[2]), Vector3(scale[0], scale[1], scale[2]), model_path)
		var rot = obs_data.get("rotation", 0.0)
		if typeof(rot) == TYPE_ARRAY:
			obs.node.rotation = Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2]))
		else:
			obs.node.rotation.y = deg_to_rad(rot)
		obs.rotation = rot
		editor.obstacles.append(obs)

	editor.spawn_points = data.get("spawn_points", []).duplicate()
	for sp in editor.spawn_points:
		var pos = sp.get("position", [0, 2, 0])
		var team = sp.get("team", 1)
		var marker = MeshInstance3D.new()
		marker.name = "SpawnMarker_%d" % team
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 3.0
		cylinder.bottom_radius = 3.0
		cylinder.height = 0.3
		marker.mesh = cylinder
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.6) if team == 1 else Color(0.8, 0.2, 0.2, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.material_override = mat
		marker.position = Vector3(pos[0], 0.15, pos[2])
		editor.add_child(marker)

	for patch_data in data.get("grass_patches", []):
		var pos = patch_data.get("position", [0, 0, 0])
		var radius = patch_data.get("radius", 20.0)
		var density = patch_data.get("density", 0.7)
		var patch = objects.create_grass_node(Vector3(pos[0], pos[1], pos[2]), radius, density)
		editor.grass_patches.append(patch)
	for patch_data in data.get("bush_patches", []):
		var pos = patch_data.get("position", [0, 0, 0])
		var radius = patch_data.get("radius", 15.0)
		var density = patch_data.get("density", 0.8)
		var patch = objects.create_bush_node(Vector3(pos[0], pos[1], pos[2]), radius, density)
		editor.bush_patches.append(patch)

	editor._update_status()
	# 加载地图后自动将相机移到地图中心并恢复俯视视角
	editor._reset_camera_view()

func on_new() -> void:
	var editor = _get_editor()
	on_clear()
	editor.map_name_input.text = ""
	editor.map_size_input.text = "200"
	editor.map_size = 200.0
	editor.air_boundary_input.text = "12000"
	editor._setup_ground()
	# 新建地图后自动将相机移到地图中心并恢复俯视视角
	editor._reset_camera_view()
	editor.status_label.text = "新地图"
	editor.status_label.modulate = Color(1, 1, 1)

func on_clear() -> void:
	var editor = _get_editor()
	for obs in editor.obstacles:
		if obs.has("node") and obs.node and is_instance_valid(obs.node):
			obs.node.queue_free()
	editor.obstacles.clear()
	for patch in editor.grass_patches:
		if patch.has("node") and patch.node and is_instance_valid(patch.node):
			patch.node.queue_free()
	editor.grass_patches.clear()
	editor.selected_grass = {}
	for patch in editor.bush_patches:
		if patch.has("node") and patch.node and is_instance_valid(patch.node):
			patch.node.queue_free()
	editor.bush_patches.clear()
	editor.selected_bush = {}
	for child in editor.get_children():
		if child.name.begins_with("SpawnMarker_"):
			child.queue_free()
	editor.spawn_points.clear()
	editor.selected_obstacle = {}
	var terrain = editor.get_node_or_null("MapTerrain")
	if terrain:
		terrain.clear_brush_indicator()
	var color_paint = editor.get_node_or_null("MapColorPaint")
	if color_paint:
		color_paint.clear_color_brush_indicator()
	editor.is_terrain_mode = false
	editor.is_color_paint_mode = false
	editor.color_texture_filename = ""
	editor.color_image = null
	editor.color_resolution = 256
	editor.terrain_grid_size = 64
	editor.default_ground_color = Color(0.6, 0.55, 0.4, 1.0)
	editor.color_brush_radius = 15.0
	if terrain:
		terrain.init_terrain_heights()
	editor._update_status()
	editor._update_selected_label()

func on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
