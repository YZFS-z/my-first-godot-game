extends Node3D
## 地图编辑器 - 障碍物/草丛/灌木/出生点管理
## 职责：创建、放置、删除障碍物/草丛/灌木/出生点，模型AABB计算
## 作为 MapEditor 节点的子节点，通过 get_parent() 访问共享状态

func _get_editor() -> Node:
	return get_parent()

func place_obstacle(pos: Vector3) -> void:
	var editor = _get_editor()
	if editor.current_obstacle_type == "grass":
		place_grass(pos)
		return
	if editor.current_obstacle_type == "bush":
		place_bush(pos)
		return
	if editor.current_obstacle_type == "model" and editor.current_model_path == "":
		editor.status_label.text = "请先导入或选择模型！"
		editor.status_label.modulate = Color(1, 0.3, 0.3)
		return
	var s = Vector3(editor.current_scale, editor.current_scale, editor.current_scale)
	var obs = create_obstacle_node(editor.current_obstacle_type, pos, s, editor.current_model_path)
	editor.obstacles.append(obs)
	editor.selected_obstacle = obs
	editor._update_status()
	editor._update_selected_label()

func place_grass(pos: Vector3) -> void:
	var editor = _get_editor()
	var patch = create_grass_node(pos, editor.current_grass_radius, editor.current_grass_density)
	editor.grass_patches.append(patch)
	editor.selected_grass = patch
	editor.selected_obstacle = {}
	editor.status_label.text = "已放置草丛: 半径%.0fm, 密度%.1f" % [editor.current_grass_radius, editor.current_grass_density]
	editor.status_label.modulate = Color(0.5, 0.8, 0.4)
	editor._update_selected_label()

func create_grass_node(pos: Vector3, radius: float, density: float) -> Dictionary:
	var editor = _get_editor()
	var root = Node3D.new()
	root.name = "GrassPatch"
	root.position = pos
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.3
	mesh_inst.mesh = cylinder
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	var body = StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 2.0
	col.shape = shape
	col.position.y = 1.0
	body.add_child(col)
	root.add_child(body)
	editor.add_child(root)
	return {"node": root, "type": "grass", "position": [pos.x, pos.y, pos.z], "radius": radius, "density": density, "mesh": mesh_inst}

func place_bush(pos: Vector3) -> void:
	var editor = _get_editor()
	var patch = create_bush_node(pos, editor.current_bush_radius, editor.current_bush_density)
	editor.bush_patches.append(patch)
	editor.selected_bush = patch
	editor.selected_obstacle = {}
	editor.selected_grass = {}
	editor.status_label.text = "已放置灌木丛: 半径%.0fm, 密度%.1f" % [editor.current_bush_radius, editor.current_bush_density]
	editor.status_label.modulate = Color(0.3, 0.6, 0.2)
	editor._update_selected_label()

func create_bush_node(pos: Vector3, radius: float, density: float) -> Dictionary:
	var editor = _get_editor()
	var root = Node3D.new()
	root.name = "BushPatch"
	root.position = pos
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 3.0
	mesh_inst.mesh = cylinder
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.38, 0.12, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	var body = StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.5
	col.shape = shape
	col.position.y = 1.75
	body.add_child(col)
	root.add_child(body)
	editor.add_child(root)
	return {"node": root, "type": "bush", "position": [pos.x, pos.y, pos.z], "radius": radius, "density": density, "mesh": mesh_inst}

func get_model_aabb_size(model_path: String) -> Vector3:
	var editor = _get_editor()
	var model_scene = load(model_path)
	if not model_scene:
		return Vector3(3, 3, 3)
	var instance = model_scene.instantiate()
	editor.add_child(instance)
	var aabb = AABB()
	var has_mesh = false
	for child in instance.find_children("*", "MeshInstance3D"):
		if child.mesh:
			var mesh_aabb = child.mesh.get_aabb()
			var global_aabb = child.global_transform * mesh_aabb
			if not has_mesh:
				aabb = global_aabb
				has_mesh = true
			else:
				aabb = aabb.merge(global_aabb)
	instance.queue_free()
	if has_mesh and aabb.size > Vector3.ZERO:
		return aabb.size
	return Vector3(3, 3, 3)

func create_obstacle_node(type: String, pos: Vector3, scale: Vector3, model_path: String = "") -> Dictionary:
	var editor = _get_editor()
	var body = StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = pos

	var col = CollisionShape3D.new()

	if type == "model" and model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			model_instance.scale = scale
			body.add_child(model_instance)
			var aabb_size = get_model_aabb_size(model_path)
			var box_shape = BoxShape3D.new()
			box_shape.size = aabb_size * scale
			col.shape = box_shape
		else:
			editor.status_label.text = "模型未导入(需重启Godot): %s，使用占位盒" % model_path.get_file()
			editor.status_label.modulate = Color(1, 0.8, 0.3)
			var fallback_mesh = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = scale * 3.0
			fallback_mesh.mesh = box
			var fmat = StandardMaterial3D.new()
			fmat.albedo_color = Color(1.0, 0.5, 0.2, 0.8)
			fallback_mesh.material_override = fmat
			body.add_child(fallback_mesh)
			var box_shape = BoxShape3D.new()
			box_shape.size = scale * 3.0
			col.shape = box_shape
	else:
		var mesh_inst = MeshInstance3D.new()
		if type == "building":
			var box = BoxMesh.new()
			box.size = scale * 4.0
			mesh_inst.mesh = box
			var box_shape = BoxShape3D.new()
			box_shape.size = scale * 4.0
			col.shape = box_shape
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.5, 0.45, 1.0)
			mat.roughness = 0.8
			mesh_inst.material_override = mat
		elif type == "ramp":
			var ramp_size = Vector3(scale.x * 6.0, scale.y * 0.5, scale.z * 8.0)
			var box = BoxMesh.new()
			box.size = ramp_size
			mesh_inst.mesh = box
			var box_shape = BoxShape3D.new()
			box_shape.size = ramp_size
			col.shape = box_shape
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.45, 0.35, 1.0)
			mat.roughness = 0.9
			mesh_inst.material_override = mat
			body.rotation.x = deg_to_rad(25)
			body.position.y += ramp_size.z * 0.5 * sin(deg_to_rad(25))
		else:
			var sphere = SphereMesh.new()
			sphere.radius = scale.x * 1.5
			sphere.height = scale.y * 3.0
			mesh_inst.mesh = sphere
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = scale.x * 1.5
			col.shape = sphere_shape
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.45, 0.42, 0.38, 1.0)
			mat.roughness = 0.95
			mesh_inst.material_override = mat
		body.add_child(mesh_inst)

	body.add_child(col)
	editor.add_child(body)

	return {"node": body, "type": type, "position": pos, "scale": scale, "rotation": [0.0, 0.0, 0.0], "model_path": model_path}

func remove_obstacle(obs: Dictionary) -> void:
	var editor = _get_editor()
	if obs.has("node") and obs.node and is_instance_valid(obs.node):
		obs.node.queue_free()
	editor.obstacles.erase(obs)
	if editor.selected_obstacle == obs:
		editor.selected_obstacle = {}
		editor._update_selected_label()
	editor._update_status()

func remove_grass(patch: Dictionary) -> void:
	var editor = _get_editor()
	if patch.has("node") and patch.node and is_instance_valid(patch.node):
		patch.node.queue_free()
	editor.grass_patches.erase(patch)
	if editor.selected_grass == patch:
		editor.selected_grass = {}
		editor._update_selected_label()
	editor._update_status()

func remove_bush(patch: Dictionary) -> void:
	var editor = _get_editor()
	if patch.has("node") and patch.node and is_instance_valid(patch.node):
		patch.node.queue_free()
	editor.bush_patches.erase(patch)
	if editor.selected_bush == patch:
		editor.selected_bush = {}
		editor._update_selected_label()
	editor._update_status()

func place_spawn_point(pos: Vector3) -> void:
	var editor = _get_editor()
	editor.spawn_points = editor.spawn_points.filter(func(sp): return sp.team != editor.spawn_team)
	for child in editor.get_children():
		if child.name.begins_with("SpawnMarker_"):
			child.queue_free()

	var marker = MeshInstance3D.new()
	marker.name = "SpawnMarker_%d" % editor.spawn_team
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 3.0
	cylinder.bottom_radius = 3.0
	cylinder.height = 0.3
	marker.mesh = cylinder
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.6) if editor.spawn_team == 1 else Color(0.8, 0.2, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = mat
	marker.position = Vector3(pos.x, 0.15, pos.z)
	editor.add_child(marker)

	var dx: float = -pos.x
	var dz: float = -pos.z
	var rot_y: float = rad_to_deg(atan2(-dx, -dz))
	editor.spawn_points.append({"team": editor.spawn_team, "position": [pos.x, 2.0, pos.z], "rotation": rot_y})
	editor.spawn_team = 2 if editor.spawn_team == 1 else 1
	editor._update_status()
