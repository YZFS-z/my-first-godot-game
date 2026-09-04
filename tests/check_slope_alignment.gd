extends SceneTree
## 斜坡贴地测试：在山谷地图找有坡度的位置，检查载具 pitch/roll 是否正确贴合

var _failed := 0
var _passed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	print("=== Slope Alignment Test (Multi-Ray) ===")

	var gm = root.get_node("GameManager")
	gm.selected_map_id = "map_valley"
	gm.selected_vehicle_id = "tank_abrams"

	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame

	var tb = main.get_node_or_null("TerrainBuilder")
	assert(tb != null, "TerrainBuilder not found")

	# 扫描地形找有坡度的位置
	var slope_positions: Array[Vector3] = []
	var scan_step := 20.0
	var max_scan := 300.0
	for x in range(-max_scan, max_scan + 1, int(scan_step)):
		for z in range(-max_scan, max_scan + 1, int(scan_step)):
			var h0 = tb.get_terrain_height(x, z)
			# 检查 x 方向坡度
			var hx = tb.get_terrain_height(x + 5.0, z)
			var dx = abs(hx - h0) / 5.0
			# 检查 z 方向坡度
			var hz = tb.get_terrain_height(x, z + 5.0)
			var dz = abs(hz - h0) / 5.0
			var slope = max(dx, dz)
			if slope > 0.15 and slope < 0.6:  # 8~31 度坡
				slope_positions.append(Vector3(x, 0, z))
				if slope_positions.size() >= 5:
					break
		if slope_positions.size() >= 5:
			break

	if slope_positions.is_empty():
		print("No suitable slope positions found, using predefined")
		slope_positions = [
			Vector3(50, 0, 50),
			Vector3(-50, 0, 50),
			Vector3(100, 0, -50),
			Vector3(-100, 0, 100),
			Vector3(150, 0, 50),
		]

	var vehicle_scene = load("res://scenes/vehicle.tscn")

	for i in range(slope_positions.size()):
		var pos = slope_positions[i]
		var ground_h = tb.get_ground_height(pos.x, pos.z)

		# 计算附近坡度
		var h_c = tb.get_terrain_height(pos.x, pos.z)
		var h_x = tb.get_terrain_height(pos.x + 5.0, pos.z)
		var h_z = tb.get_terrain_height(pos.x, pos.z + 5.0)
		var slope_x = (h_x - h_c) / 5.0
		var slope_z = (h_z - h_c) / 5.0
		var slope_deg = rad_to_deg(atan(max(abs(slope_x), abs(slope_z))))

		var vehicle = vehicle_scene.instantiate()
		vehicle.position = Vector3(pos.x, ground_h + 1.5, pos.z)
		vehicle.set("is_player_controlled", true)
		main.add_child(vehicle)

		# 等待载具落地
		for frame in range(120):
			await physics_frame

		var final_pos = vehicle.global_position
		var final_rot = vehicle.rotation
		var final_ground_h = tb.get_ground_height(final_pos.x, final_pos.z)
		var gap = final_pos.y - final_ground_h

		# 检查射线是否命中（射线是载具直接子节点，名为 GroundRay_N）
		var ray_hits := 0
		var ray_points: Array[Vector3] = []
		for ci in range(5):
			var ray = vehicle.get_node_or_null("GroundRay_%d" % ci)
			if ray and ray is RayCast3D:
				if ray.is_colliding():
					ray_hits += 1
					ray_points.append(ray.get_collision_point())

		print("  点%d (%.0f,%.0f) slope=%.1f°: final_y=%.3f ground_h=%.3f gap=%.4f pitch=%.2f° roll=%.2f° rays=%d/5" % [
			i, pos.x, pos.z, slope_deg, final_pos.y, final_ground_h, gap,
			rad_to_deg(final_rot.x), rad_to_deg(final_rot.z), ray_hits
		])

		# 检查1: 至少3条射线命中
		_check(ray_hits >= 3,
			"点%d: 射线命中 >=3 (%d/5)" % [i, ray_hits])

		# 检查2: gap < 0.3m
		_check(abs(gap) < 0.3,
			"点%d: 贴地 gap<0.3 (gap=%.4f)" % [i, gap])

		# 检查3: pitch 有响应（坡度>5°时 pitch 应非零）
		if slope_deg > 5.0:
			_check(abs(rad_to_deg(final_rot.x)) > 0.5,
				"点%d: pitch响应 (pitch=%.2f° slope=%.1f°)" % [i, rad_to_deg(final_rot.x), slope_deg])

		vehicle.queue_free()
		await physics_frame

	main.queue_free()
	await physics_frame

	print("\n=== 汇总: passed=%d failed=%d ===" % [_passed, _failed])
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
