extends Node3D
## 植被管理器 - 负责草丛/灌木丛的生成、视距剔除、爆炸销毁
## 作为 Main 节点的子节点，通过 get_parent() 访问共享状态

const GRASS_LAYER = 16
const FOLIAGE_GRID_SIZE = 10.0

var _grass_patches: Array = []
var _grass_cull_timer: float = 0.0

func _get_main() -> Node:
	return get_parent()

func _get_map_config() -> Dictionary:
	return _get_main().map_config

func build_grass() -> void:
	"""根据地图配置生成草丛和灌木丛"""
	var map_config = _get_map_config()
	var has_terrain = map_config.has("terrain")
	var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")

	var patches = map_config.get("grass_patches", [])
	if not patches.is_empty():
		print("[FoliageManager] 生成 %d 个草丛" % patches.size())
	for patch in patches:
		var pos = patch.get("position", [0, 0, 0])
		var radius = patch.get("radius", 20.0)
		var density = patch.get("density", 0.7)
		var color = patch.get("color", null)
		var world_pos = Vector3(pos[0], pos[1], pos[2])
		if has_terrain and terrain_builder:
			world_pos.y = terrain_builder.get_ground_height(world_pos.x, world_pos.z)
		_create_grass_patch(world_pos, radius, density, "grass", color, has_terrain)

	var bush_patches = map_config.get("bush_patches", [])
	if not bush_patches.is_empty():
		print("[FoliageManager] 生成 %d 个灌木丛" % bush_patches.size())
	for patch in bush_patches:
		var pos = patch.get("position", [0, 0, 0])
		var radius = patch.get("radius", 15.0)
		var density = patch.get("density", 0.8)
		var color = patch.get("color", null)
		var world_pos = Vector3(pos[0], pos[1], pos[2])
		if has_terrain and terrain_builder:
			world_pos.y = terrain_builder.get_ground_height(world_pos.x, world_pos.z)
		_create_grass_patch(world_pos, radius, density, "bush", color, has_terrain)

func _create_grass_patch(position: Vector3, radius: float, density: float, variant: String = "grass", color = null, has_terrain: bool = false) -> void:
	var patch_root = Node3D.new()
	patch_root.name = "GrassPatch" if variant == "grass" else "BushPatch"
	patch_root.position = position
	patch_root.set_meta("grass_radius", radius)
	patch_root.set_meta("variant", variant)

	var is_bush = variant == "bush"
	var mesh_width = 0.5 if is_bush else 0.3
	var mesh_height = 2.0 if is_bush else 1.2
	var min_height = 1.8 if is_bush else 0.8
	var max_height = 4.0 if is_bush else 1.6

	var foliage_color = Color(0.18, 0.38, 0.12, 0.92) if is_bush else Color(0.3, 0.55, 0.2, 0.85)
	if color != null and typeof(color) == TYPE_ARRAY and color.size() >= 3:
		foliage_color = Color(color[0], color[1], color[2], 0.85 if not is_bush else 0.92)

	var col_height = 3.5 if is_bush else 1.5
	var density_mult = 0.7 if is_bush else 0.5

	var grid_r = ceil(radius / FOLIAGE_GRID_SIZE)
	var cell_area = FOLIAGE_GRID_SIZE * FOLIAGE_GRID_SIZE
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(position)
	var cell_count = 0

	var patch_center_h = position.y if has_terrain else 0.0
	var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")

	for gx in range(-grid_r, grid_r + 1):
		for gz in range(-grid_r, grid_r + 1):
			var cell_center_x = gx * FOLIAGE_GRID_SIZE + FOLIAGE_GRID_SIZE * 0.5
			var cell_center_z = gz * FOLIAGE_GRID_SIZE + FOLIAGE_GRID_SIZE * 0.5
			var cell_dist = sqrt(cell_center_x * cell_center_x + cell_center_z * cell_center_z)
			if cell_dist > radius + FOLIAGE_GRID_SIZE * 0.707:
				continue
			var coverage = 1.0
			if cell_dist > radius:
				coverage = clamp(1.0 - (cell_dist - radius) / FOLIAGE_GRID_SIZE, 0.2, 1.0)
			var count = int(cell_area * density * density_mult * coverage)
			count = clamp(count, 1, 80)

			var cell = Node3D.new()
			cell.name = "Cell_%d_%d" % [gx, gz]
			var cell_y = 0.0
			if has_terrain and terrain_builder:
				var world_x = position.x + cell_center_x
				var world_z = position.z + cell_center_z
				# 直接从高度图采样，避免射线检测不稳定导致植物浮在空中
				cell_y = terrain_builder.get_terrain_height(world_x, world_z) - patch_center_h
			cell.position = Vector3(cell_center_x, cell_y, cell_center_z)
			cell.set_meta("grid_x", gx)
			cell.set_meta("grid_z", gz)

			var multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.instance_count = count
			var foliage_mesh = PlaneMesh.new()
			foliage_mesh.size = Vector2(mesh_width, mesh_height)
			foliage_mesh.orientation = PlaneMesh.FACE_Z
			multimesh.mesh = foliage_mesh
			var mmi = MultiMeshInstance3D.new()
			mmi.multimesh = multimesh
			var mat = StandardMaterial3D.new()
			mat.albedo_color = foliage_color
			mat.roughness = 0.9
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mmi.material_override = mat
			cell.add_child(mmi)

			for i in range(count):
				var lx = rng.randf() * FOLIAGE_GRID_SIZE - FOLIAGE_GRID_SIZE * 0.5
				var lz = rng.randf() * FOLIAGE_GRID_SIZE - FOLIAGE_GRID_SIZE * 0.5
				var height = min_height + rng.randf() * (max_height - min_height)
				var rot_y = rng.randf() * TAU
				var scale_v = Vector3(0.7 + rng.randf() * 0.6, height, 1.0)
				var t = Transform3D()
				t.origin = Vector3(lx, height * 0.5, lz)
				t.basis = Basis(Vector3.UP, rot_y).scaled(scale_v)
				multimesh.set_instance_transform(i, t)

			var vision_body = StaticBody3D.new()
			vision_body.name = "GrassVisionBlock"
			vision_body.collision_layer = GRASS_LAYER
			vision_body.collision_mask = 0
			var col = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(FOLIAGE_GRID_SIZE, col_height, FOLIAGE_GRID_SIZE)
			col.shape = box
			col.position.y = col_height * 0.5
			vision_body.add_child(col)
			cell.add_child(vision_body)
			patch_root.add_child(cell)
			cell_count += 1

	if cell_count == 0:
		patch_root.queue_free()
		return
	_get_main().add_child(patch_root)
	_grass_patches.append(patch_root)

func update_grass_culling() -> void:
	"""根据画质档位和摄像机距离更新草丛可见性"""
	if _grass_patches.is_empty():
		return
	var player_tank = _get_main().player_tank
	if not player_tank:
		return
	var cam = player_tank.get_node_or_null("SpringArm3D/Camera3D")
	if not cam:
		cam = get_viewport().get_camera_3d()
	if not cam:
		return
	var cam_pos = cam.global_position
	var quality = SettingsManager.get_setting("graphics", "quality", "medium")
	var render_dist = 300.0
	match quality:
		"low": render_dist = 100.0
		"medium": render_dist = 300.0
		"high": render_dist = 600.0
		"ultra": render_dist = 1000.0
	for patch in _grass_patches:
		var dist = patch.global_position.distance_to(cam_pos)
		patch.visible = dist <= render_dist

func process_culling(delta: float) -> void:
	"""每帧调用，内部计时每0.5秒更新一次"""
	_grass_cull_timer += delta
	if _grass_cull_timer >= 0.5:
		_grass_cull_timer = 0.0
		update_grass_culling()

func _cell_intersects_circle(cell_center: Vector3, explosion_center: Vector3, explosion_radius: float) -> bool:
	var dist = cell_center.distance_to(explosion_center)
	return dist < explosion_radius + FOLIAGE_GRID_SIZE * 0.707

func destroy_foliage_in_radius(center: Vector3, explosion_radius: float, explosion_power: float = 100.0) -> void:
	"""按方格消除爆炸范围内的草丛/灌木丛"""
	var main = _get_main()
	if main.is_public_mode and not main._is_remote_foliage_destroy and NetworkManager.game_connected_flag:
		NetworkManager.game_send_foliage_destroy(center, explosion_radius)
	if _grass_patches.is_empty():
		return
	var cells_destroyed = 0
	var patches_destroyed = 0
	for pi in range(_grass_patches.size() - 1, -1, -1):
		var patch = _grass_patches[pi]
		if not is_instance_valid(patch):
			_grass_patches.remove_at(pi)
			continue
		var patch_pos = patch.global_position
		var patch_radius = patch.get_meta("grass_radius", 20.0)
		if patch_pos.distance_to(center) > patch_radius + explosion_radius + FOLIAGE_GRID_SIZE:
			continue
		var cells_to_remove = []
		for cell in patch.get_children():
			if not cell.name.begins_with("Cell_"):
				continue
			var cell_world_pos = patch_pos + cell.position
			if _cell_intersects_circle(cell_world_pos, center, explosion_radius):
				cells_to_remove.append(cell)
		for cell in cells_to_remove:
			cell.queue_free()
			cells_destroyed += 1
		var has_cells = false
		for child in patch.get_children():
			if child.name.begins_with("Cell_"):
				has_cells = true
				break
		if not has_cells:
			patch.queue_free()
			_grass_patches.remove_at(pi)
			patches_destroyed += 1
	if cells_destroyed > 0:
		print("[FoliageManager] 爆炸消除植被: %d个方格, %d个草丛完全清除 @ %s, 爆炸半径%.1f" % [cells_destroyed, patches_destroyed, str(center), explosion_radius])
