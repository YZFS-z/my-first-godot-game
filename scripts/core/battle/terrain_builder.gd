extends Node3D
## 地形构建器 - 负责地面/地形网格、飞机边界、障碍物的构建，以及地形高度查询
## 作为 Main 节点的子节点，通过 get_parent() 访问共享状态（map_config 等）

const DEFAULT_AIR_BOUNDARY: float = 12000.0
const AIR_WALL_HEIGHT: float = 3000.0
const AIR_WALL_THICKNESS: float = 20.0

var _air_boundary_rids: Array[RID] = []  # 空气边界碰撞体 RID，地形射线检测时排除
var _obstacle_rids: Array[RID] = []  # 障碍物碰撞体 RID，载具对齐射线排除
var _terrain_min_height: float = 0.0  # 地形最低点高度

func _get_main() -> Node:
	return get_parent()

func _get_map_config() -> Dictionary:
	return _get_main().map_config

func build_ground() -> void:
	"""构建地面/地形网格（含高度图、颜色纹理）和碰撞体"""
	var map_config = _get_map_config()
	var map_size = map_config.get("size", 200)
	var ground_color = map_config.get("ground_color", [0.5, 0.55, 0.4])

	var terrain_data = map_config.get("terrain", {})
	var has_terrain = not terrain_data.is_empty()

	var ground_mesh = MeshInstance3D.new()
	ground_mesh.name = "Ground"
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(ground_color[0], ground_color[1], ground_color[2], 1.0)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if has_terrain:
		var grid_size = int(terrain_data.get("grid_size", 64))
		var heights = terrain_data.get("heights", [])
		var n = grid_size + 1
		var half = float(map_size) * 0.5
		var cell = float(map_size) / float(grid_size)
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
				# 逆时针绕序（从上方看），法线朝上
				st.add_index(i)
				st.add_index(i + n)
				st.add_index(i + 1)
				st.add_index(i + 1)
				st.add_index(i + n)
				st.add_index(i + n + 1)
		st.generate_normals()
		ground_mesh.mesh = st.commit()

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
						var color_tex = ImageTexture.create_from_image(color_img)
						mat.albedo_texture = color_tex
						mat.albedo_color = Color.WHITE
					break
		ground_mesh.material_override = mat
		_get_main().add_child(ground_mesh)

		var all_flat := true
		_terrain_min_height = 0.0
		for h in heights:
			var fh = float(h)
			if abs(fh) > 0.01:
				all_flat = false
			if fh < _terrain_min_height:
				_terrain_min_height = fh
		var ground_body = StaticBody3D.new()
		ground_body.name = "GroundCollision"
		ground_body.collision_layer = 1
		ground_body.collision_mask = 0
		var col = CollisionShape3D.new()
		if all_flat:
			var shape = BoxShape3D.new()
			shape.size = Vector3(map_size, 1.0, map_size)
			col.shape = shape
			col.position = Vector3(0, -0.5, 0)
		else:
			# 使用 ConcavePolygonShape3D（三角网格碰撞体），顶点与可视网格完全一致
			# 根因：Godot 4 的 HeightMapShape3D 忽略 CollisionShape3D.position 偏移，
			# 碰撞体始终在 (0,0)~(map_size,map_size)，而可视网格在 (-half,-half)~(half,half)，
			# 偏移 half 导致射线命中错误高度 → 载具缝隙/下沉
			# ConcavePolygonShape3D 尊重 transform，顶点坐标直接使用世界坐标，天然对齐
			var trimesh = ConcavePolygonShape3D.new()
			var vertices := PackedVector3Array()
			# 每个网格单元生成 2 个三角形（6 个顶点），与可视网格绕序一致
			for zg in range(grid_size):
				for xg in range(grid_size):
					var i00 = zg * n + xg
					var i10 = zg * n + xg + 1
					var i01 = (zg + 1) * n + xg
					var i11 = (zg + 1) * n + xg + 1
					var h00 = float(heights[i00]) if i00 < heights.size() else 0.0
					var h10 = float(heights[i10]) if i10 < heights.size() else 0.0
					var h01 = float(heights[i01]) if i01 < heights.size() else 0.0
					var h11 = float(heights[i11]) if i11 < heights.size() else 0.0
					# 世界坐标（与可视网格顶点一致）
					var v00 = Vector3(xg * cell - half, h00, zg * cell - half)
					var v10 = Vector3((xg + 1) * cell - half, h10, zg * cell - half)
					var v01 = Vector3(xg * cell - half, h01, (zg + 1) * cell - half)
					var v11 = Vector3((xg + 1) * cell - half, h11, (zg + 1) * cell - half)
					# 三角形 1: v00, v01, v10（逆时针，法线朝上）
					vertices.append(v00)
					vertices.append(v01)
					vertices.append(v10)
					# 三角形 2: v10, v01, v11
					vertices.append(v10)
					vertices.append(v01)
					vertices.append(v11)
			trimesh.set_faces(vertices)
			trimesh.backface_collision = true
			col.shape = trimesh
		ground_body.add_child(col)
		_get_main().add_child(ground_body)
	else:
		var plane = PlaneMesh.new()
		plane.size = Vector2(map_size, map_size)
		plane.subdivide_width = 40
		plane.subdivide_depth = 40
		ground_mesh.mesh = plane
		ground_mesh.material_override = mat
		_get_main().add_child(ground_mesh)

		var ground_body = StaticBody3D.new()
		ground_body.name = "GroundCollision"
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(map_size, 1.0, map_size)
		col.shape = shape
		ground_body.add_child(col)
		_get_main().add_child(ground_body)

func build_air_boundary() -> void:
	"""构建飞机大边界：底部大地 + 四面墙 + 顶盖，封闭盒子"""
	var map_config = _get_map_config()
	var air_size: float = float(map_config.get("air_boundary_size", DEFAULT_AIR_BOUNDARY))
	var half: float = air_size * 0.5
	var wall_h: float = float(map_config.get("air_wall_height", AIR_WALL_HEIGHT))
	var wall_t: float = float(map_config.get("air_wall_thickness", AIR_WALL_THICKNESS))
	var ground_color = map_config.get("ground_color", [0.5, 0.55, 0.4])
	var sky = map_config.get("sky_color", [0.5, 0.65, 0.85])
	var root_node := Node3D.new()
	root_node.name = "AirBounds"
	_get_main().add_child(root_node)

	# 底部大地
	var air_ground := MeshInstance3D.new()
	air_ground.name = "AirGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(air_size, air_size)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	air_ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(ground_color[0], ground_color[1], ground_color[2], 1.0)
	mat.roughness = 0.95
	air_ground.material_override = mat
	air_ground.position = Vector3(0, -0.25, 0)
	root_node.add_child(air_ground)

	var air_ground_body := StaticBody3D.new()
	air_ground_body.name = "AirGroundCollision"
	var ag_col := CollisionShape3D.new()
	var ag_shape := BoxShape3D.new()
	ag_shape.size = Vector3(air_size, 0.6, air_size)
	ag_col.shape = ag_shape
	# 地形地图：将空气边界地面碰撞体移到最低地形点以下 5m，
	# 避免与地形面重叠导致地面载具 move_and_slide 误碰撞（起伏/弹跳）
	# 平坦地图：保持 y=-0.3（与地面 BoxShape3D 重叠但顶面一致，不影响）
	var ag_y = -0.3
	if _terrain_min_height < -0.01:
		ag_y = _terrain_min_height - 5.0
	ag_col.position = Vector3(0, ag_y, 0)
	air_ground_body.add_child(ag_col)
	root_node.add_child(air_ground_body)
	_air_boundary_rids.append(air_ground_body.get_rid())

	# 四面墙 + 顶盖
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(sky[0] * 0.8, sky[1] * 0.8, sky[2] * 0.85, 0.35)
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.roughness = 0.8
	var walls: Array[Vector3] = [
		Vector3(0, wall_h * 0.5, half + wall_t * 0.25),
		Vector3(0, wall_h * 0.5, -half - wall_t * 0.25),
		Vector3(half + wall_t * 0.25, wall_h * 0.5, 0),
		Vector3(-half - wall_t * 0.25, wall_h * 0.5, 0),
	]
	for w_idx in range(4):
		var is_x_wall: bool = w_idx >= 2
		var body := StaticBody3D.new()
		body.name = "AirWall%d" % (w_idx + 1)
		var c := CollisionShape3D.new()
		var s := BoxShape3D.new()
		if is_x_wall:
			s.size = Vector3(wall_t, wall_h, air_size + wall_t)
		else:
			s.size = Vector3(air_size + wall_t, wall_h, wall_t)
		c.shape = s
		body.add_child(c)
		body.position = walls[w_idx]
		root_node.add_child(body)
		_air_boundary_rids.append(body.get_rid())
		var vis := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = s.size
		vis.mesh = box
		vis.material_override = wall_mat
		vis.position = walls[w_idx]
		root_node.add_child(vis)

	# 顶盖
	var ceil_body := StaticBody3D.new()
	ceil_body.name = "AirCeiling"
	var cc := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(air_size + wall_t, wall_t, air_size + wall_t)
	cc.shape = cs
	ceil_body.add_child(cc)
	ceil_body.position = Vector3(0, wall_h + wall_t * 0.5, 0)
	root_node.add_child(ceil_body)
	_air_boundary_rids.append(ceil_body.get_rid())
	var ceil_vis := MeshInstance3D.new()
	var ceil_box := BoxMesh.new()
	ceil_box.size = cs.size
	ceil_vis.mesh = ceil_box
	ceil_vis.material_override = wall_mat
	ceil_vis.position = ceil_body.position
	root_node.add_child(ceil_vis)

func build_obstacles() -> void:
	"""根据地图配置构建障碍物"""
	var map_config = _get_map_config()
	var has_terrain = map_config.has("terrain")
	var obstacles = map_config.get("obstacles", [])
	for obs in obstacles:
		var type = obs.get("type", "rock")
		var pos = obs.get("position", [0, 0, 0])
		var scale = obs.get("scale", [2, 2, 2])
		var rotation = obs.get("rotation", 0)
		var model_path = obs.get("model_path", "")
		var color = obs.get("color", null)
		var world_pos = Vector3(pos[0], pos[1], pos[2])
		if has_terrain:
			world_pos.y = get_ground_height(world_pos.x, world_pos.z)
		_create_obstacle(type, world_pos, Vector3(scale[0], scale[1], scale[2]), rotation, model_path, color)

func _create_obstacle(type: String, position: Vector3, scale: Vector3, rotation = null, model_path: String = "", color = null) -> void:
	var body = StaticBody3D.new()
	body.name = "Obstacle_%s" % type
	body.position = position
	if rotation == null:
		body.rotation.y = 0.0
	elif typeof(rotation) == TYPE_ARRAY:
		body.rotation = Vector3(deg_to_rad(rotation[0]), deg_to_rad(rotation[1]), deg_to_rad(rotation[2]))
	else:
		body.rotation.y = deg_to_rad(rotation)
	body.collision_layer = 1
	body.collision_mask = 2

	var custom_color = null
	if color != null and typeof(color) == TYPE_ARRAY and color.size() >= 3:
		custom_color = Color(color[0], color[1], color[2], 1.0)

	if type == "model" and model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			model_instance.scale = scale
			body.add_child(model_instance)
			var aabb_size = _get_model_aabb_size(model_path)
			var col = CollisionShape3D.new()
			var box_shape = BoxShape3D.new()
			box_shape.size = aabb_size * scale
			col.shape = box_shape
			body.add_child(col)
		else:
			push_warning("[TerrainBuilder] 无法加载模型: %s" % model_path)
	else:
		var mesh_inst = MeshInstance3D.new()
		var col = CollisionShape3D.new()

		if type == "building":
			var box = BoxMesh.new()
			box.size = scale
			mesh_inst.mesh = box
			var box_shape = BoxShape3D.new()
			box_shape.size = scale
			col.shape = box_shape
			var mat = StandardMaterial3D.new()
			mat.albedo_color = custom_color if custom_color else Color(0.5, 0.48, 0.45, 1.0)
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
			mat.albedo_color = custom_color if custom_color else Color(0.5, 0.45, 0.35, 1.0)
			mat.roughness = 0.9
			mesh_inst.material_override = mat
			body.rotation.x = deg_to_rad(25)
			body.position.y += ramp_size.z * 0.5 * sin(deg_to_rad(25))
		else:  # rock
			var sphere = SphereMesh.new()
			sphere.radius = scale.x * 0.5
			sphere.height = scale.y
			mesh_inst.mesh = sphere
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = scale.x * 0.5
			col.shape = sphere_shape
			var mat = StandardMaterial3D.new()
			mat.albedo_color = custom_color if custom_color else Color(0.45, 0.42, 0.38, 1.0)
			mat.roughness = 0.95
			mesh_inst.material_override = mat

		body.add_child(mesh_inst)
		body.add_child(col)

	_get_main().add_child(body)
	_obstacle_rids.append(body.get_rid())

func _get_model_aabb_size(model_path: String) -> Vector3:
	var model_scene = load(model_path)
	if not model_scene:
		return Vector3(3, 3, 3)
	var instance = model_scene.instantiate()
	_get_main().add_child(instance)
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

func get_terrain_height(x: float, z: float) -> float:
	"""从地形高度图采样指定XZ坐标的高度（双线性插值）"""
	var map_config = _get_map_config()
	if not map_config.has("terrain"):
		return 0.0
	var terrain = map_config["terrain"]
	var grid_size = int(terrain.get("grid_size", 64))
	var heights = terrain.get("heights", [])
	if heights.is_empty():
		return 0.0
	var map_size = float(map_config.get("size", 200))
	var n = grid_size + 1
	var half = map_size * 0.5
	var cell = map_size / float(grid_size)
	var gx = (x + half) / cell
	var gz = (z + half) / cell
	gx = clampf(gx, 0.0, float(grid_size))
	gz = clampf(gz, 0.0, float(grid_size))
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
	# 三角形重心插值——与 ConcavePolygonShape3D 碰撞网格的三角剖分完全一致
	# Triangle 1: v00, v01, v10 (对角线 v01-v10，覆盖 fx+fz<=1)
	# Triangle 2: v10, v01, v11 (覆盖 fx+fz>1)
	if fx + fz <= 1.0:
		return h00 * (1.0 - fx - fz) + h01 * fz + h10 * fx
	else:
		return h10 * (1.0 - fz) + h01 * (1.0 - fx) + h11 * (fx + fz - 1.0)

func get_air_boundary_rids() -> Array[RID]:
	"""返回空气边界碰撞体 RID 列表，供载具射线检测排除使用"""
	return _air_boundary_rids

func get_obstacle_rids() -> Array[RID]:
	"""返回障碍物碰撞体 RID 列表，供载具对齐射线排除使用"""
	return _obstacle_rids

func get_ground_height(x: float, z: float) -> float:
	"""通过向下射线检测获取真实地面高度，排除空气边界碰撞体"""
	var map_config = _get_map_config()
	if not map_config.has("terrain"):
		return 0.0
	var base_h = get_terrain_height(x, z)
	var space = get_world_3d().direct_space_state
	var from = Vector3(x, base_h + 80.0, z)
	var to = Vector3(x, base_h - 80.0, z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var exclude_rids: Array[RID] = []
	exclude_rids.append_array(_air_boundary_rids)
	exclude_rids.append_array(_obstacle_rids)
	if not exclude_rids.is_empty():
		query.exclude = exclude_rids
	var result = space.intersect_ray(query)
	if result and not result.is_empty():
		return result.position.y
	return base_h
