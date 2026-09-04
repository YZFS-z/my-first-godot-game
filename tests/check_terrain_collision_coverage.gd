extends SceneTree
## 验证 HeightMapShape3D 缩放后碰撞体覆盖完整地图
## 在地图边缘位置射线向下检测，确认能命中地形

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	print("=== Terrain Collision Coverage Check ===")

	# 加载山谷地图配置
	var map_text := FileAccess.get_file_as_string("res://data/maps/map_valley.json")
	assert(map_text != "", "Cannot read map_valley.json")
	var map_config: Dictionary = JSON.parse_string(map_text)
	assert(map_config.has("terrain"), "map_valley.json missing terrain")

	var terrain = map_config["terrain"]
	var grid_size = int(terrain.get("grid_size", 64))
	var map_size = float(map_config.get("size", 2000))
	var half = map_size * 0.5
	var cell = map_size / float(grid_size)

	print("map_size=%.0f, grid_size=%d, cell=%.3f" % [map_size, grid_size, cell])

	# 源码检查：HeightMapShape3D 应有 col.scale 缩放
	var f := FileAccess.open("res://scripts/core/battle/terrain_builder.gd", FileAccess.READ)
	assert(f != null, "Cannot open terrain_builder.gd")
	var src := f.get_as_text()
	f.close()
	_check(src.find("col.scale = Vector3(cell, 1.0, cell)") != -1,
		"terrain_builder.gd HeightMapShape3D 有 col.scale 缩放")

	# autoload 在 --script 模式下自动加载，直接构建 Main 场景
	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	main.map_config = map_config
	root.add_child(main)

	# 等待物理帧让碰撞体就绪
	await physics_frame
	await physics_frame

	var tb = main.get_node_or_null("TerrainBuilder")
	assert(tb != null, "TerrainBuilder not found")

	# 在地图边缘（远离中心）的多个位置射线检测
	# 如果 HeightMapShape3D 未缩放，这些位置会 miss
	var test_points := [
		Vector3(half * 0.9, 0, half * 0.9),
		Vector3(-half * 0.9, 0, half * 0.9),
		Vector3(half * 0.9, 0, -half * 0.9),
		Vector3(-half * 0.9, 0, -half * 0.9),
		Vector3(half * 0.5, 0, half * 0.5),
		Vector3(-half * 0.5, 0, -half * 0.5),
		Vector3(0, 0, 0),
	]

	var hit_count := 0
	for i in range(test_points.size()):
		var p = test_points[i]
		var terrain_h = tb.get_terrain_height(p.x, p.z)
		var ground_h = tb.get_ground_height(p.x, p.z)
		var diff = abs(ground_h - terrain_h)
		var hit = diff < 2.0
		print("  点%d (%.0f,%.0f): terrain_h=%.2f ground_h=%.2f diff=%.2f %s" % [
			i, p.x, p.z, terrain_h, ground_h, diff, "HIT" if hit else "MISS"
		])
		if hit:
			hit_count += 1

	_check(hit_count >= 6, "地图边缘射线命中率 >= 6/7 (实际=%d/7)" % hit_count)

	# 清理
	main.queue_free()
	await physics_frame

	print("\n=== 汇总: failed=%d ===" % _failed)
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
