extends SceneTree
## 验证载具视觉模型与碰撞体之间无垂直空隙
## 1. HeightMapShape3D 碰撞体居中（position = (-half, 0, -half)）
## 2. get_ground_height (raycast) 与 get_terrain_height (heightmap) 一致
## 3. 内置坦克 track 视觉底部 = 碰撞底部 (Y=0.0)

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
	print("=== Vehicle Ground Gap Check ===")

	# --- 1. 源码检查：HeightMapShape3D 碰撞体居中 ---
	var f := FileAccess.open("res://scripts/core/battle/terrain_builder.gd", FileAccess.READ)
	assert(f != null, "Cannot open terrain_builder.gd")
	var src := f.get_as_text()
	f.close()
	_check(src.find("col.position = Vector3(-half, 0, -half)") != -1,
		"HeightMapShape3D col.position 居中至 (-half, 0, -half)")

	# --- 2. 源码检查：vehicle.tscn track 底部 = 碰撞底部 ---
	var vf := FileAccess.open("res://scenes/vehicle.tscn", FileAccess.READ)
	assert(vf != null, "Cannot open vehicle.tscn")
	var vsrc := vf.get_as_text()
	vf.close()

	# CollisionShape3D at Y=0.6, size Y=1.2 -> bottom = 0.0
	# TrackLeft/Right at Y=0.3, size Y=0.6 -> bottom = 0.0
	_check(vsrc.find("0, 0.6, 0") != -1, "CollisionShape3D Y=0.6 (bottom=0.0)")
	_check(vsrc.find("-1.8, 0.3, 0") != -1, "TrackLeft Y=0.3 (bottom=0.0)")
	_check(vsrc.find("1.8, 0.3, 0") != -1, "TrackRight Y=0.3 (bottom=0.0)")

	# --- 3. 山谷地图：raycast vs heightmap 一致性 ---
	var map_text := FileAccess.get_file_as_string("res://data/maps/map_valley.json")
	assert(map_text != "", "Cannot read map_valley.json")
	var map_config: Dictionary = JSON.parse_string(map_text)
	assert(map_config.has("terrain"), "map_valley.json missing terrain")

	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	main.map_config = map_config
	root.add_child(main)

	await physics_frame
	await physics_frame

	var tb = main.get_node_or_null("TerrainBuilder")
	assert(tb != null, "TerrainBuilder not found")

	var terrain = map_config["terrain"]
	var map_size = float(map_config.get("size", 2000))
	var half = map_size * 0.5

	# 在地图各处采样，验证 raycast 高度与 heightmap 高度一致
	# 修复前：碰撞体偏移 +half，raycast 命中错误位置的高度
	var test_points := [
		Vector3(0, 0, 0),
		Vector3(half * 0.5, 0, half * 0.5),
		Vector3(-half * 0.5, 0, -half * 0.5),
		Vector3(half * 0.3, 0, -half * 0.3),
		Vector3(-half * 0.3, 0, half * 0.3),
		Vector3(half * 0.8, 0, 0),
		Vector3(0, 0, half * 0.8),
		Vector3(-half * 0.8, 0, -half * 0.8),
	]

	var max_diff := 0.0
	for i in range(test_points.size()):
		var p = test_points[i]
		var terrain_h = tb.get_terrain_height(p.x, p.z)
		var ground_h = tb.get_ground_height(p.x, p.z)
		var diff = abs(ground_h - terrain_h)
		if diff > max_diff:
			max_diff = diff
		print("  点%d (%.0f,%.0f): terrain_h=%.2f ground_h=%.2f diff=%.3f" % [
			i, p.x, p.z, terrain_h, ground_h, diff
		])

	_check(max_diff < 1.0,
		"raycast 与 heightmap 最大偏差 < 1.0m (实际=%.3f)" % max_diff)

	# --- 4. 生成载具检查视觉-碰撞对齐 ---
	# 加载 vehicle.tscn，检查节点 Y 坐标
	var vehicle_scene = load("res://scenes/vehicle.tscn")
	var vehicle = vehicle_scene.instantiate()
	root.add_child(vehicle)
	await physics_frame

	var col_shape = vehicle.get_node_or_null("CollisionShape3D")
	assert(col_shape != null, "CollisionShape3D not found")
	var col_y = col_shape.position.y
	var col_height = col_shape.shape.size.y
	var col_bottom = col_y - col_height * 0.5

	var track_l = vehicle.get_node_or_null("TrackLeft")
	assert(track_l != null, "TrackLeft not found")
	var track_y = track_l.position.y
	var track_height = track_l.mesh.size.y
	var track_bottom = track_y - track_height * 0.5

	print("  CollisionShape3D: Y=%.2f height=%.2f bottom=%.2f" % [col_y, col_height, col_bottom])
	print("  TrackLeft: Y=%.2f height=%.2f bottom=%.2f" % [track_y, track_height, track_bottom])

	_check(abs(col_bottom - track_bottom) < 0.01,
		"Track 视觉底部 (%.2f) = 碰撞底部 (%.2f)" % [track_bottom, col_bottom])

	var hull = vehicle.get_node_or_null("Hull")
	assert(hull != null, "Hull not found")
	var hull_y = hull.position.y
	var hull_height = hull.mesh.size.y
	var hull_bottom = hull_y - hull_height * 0.5
	print("  Hull: Y=%.2f height=%.2f bottom=%.2f" % [hull_y, hull_height, hull_bottom])
	_check(hull_bottom >= track_bottom,
		"Hull 底部 (%.2f) >= Track 底部 (%.2f)" % [hull_bottom, track_bottom])

	vehicle.queue_free()
	main.queue_free()
	await physics_frame

	print("\n=== 汇总: passed=%d failed=%d ===" % [_passed, _failed])
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
