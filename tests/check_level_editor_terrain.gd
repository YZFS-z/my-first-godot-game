extends SceneTree
## 测试关卡编辑器地形加载与载具放置高度
## 验证：切换地图时重建地形，放置坦克使用射线检测高度而非硬编码1.0

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _init():
	print("=== Level Editor Terrain Check ===")

	# --- 源码检查 ---
	var f := FileAccess.open("res://scripts/ui/level_editor.gd", FileAccess.READ)
	assert(f != null, "Cannot open level_editor.gd")
	var src := f.get_as_text()
	f.close()

	_check(src.find("_rebuild_ground_for_map") != -1, "包含 _rebuild_ground_for_map 函数")
	_check(src.find("ground_mesh_node") != -1, "引用 ground_mesh_node 节点")
	_check(src.find("pos.y += 1.0") != -1, "放置坦克使用 pos.y += 1.0 (射线高度+偏移)")
	_check(src.find("pos.y = 1.0") == -1, "不再硬编码 pos.y = 1.0")

	# 检查 _on_map_changed 调用 _rebuild_ground_for_map
	var map_changed_pos := src.find("func _on_map_changed")
	if map_changed_pos != -1:
		var snippet := src.substr(map_changed_pos, 200)
		_check(snippet.find("_rebuild_ground_for_map") != -1, "_on_map_changed 调用 _rebuild_ground_for_map")

	# 检查 _ready 初始加载地形
	var ready_pos := src.find("func _ready")
	if ready_pos != -1:
		var ready_snippet := src.substr(ready_pos, 200)
		_check(ready_snippet.find("_rebuild_ground_for_map") != -1, "_ready 初始加载地形")

	# 检查 _load_level_data 重建地形
	var load_pos := src.find("func _load_level_data")
	if load_pos != -1:
		var load_snippet := src.substr(load_pos, 600)
		_check(load_snippet.find("_rebuild_ground_for_map") != -1, "_load_level_data 重建地形")

	# 检查 _place_tank_at 重采样高度
	var place_at_pos := src.find("func _place_tank_at")
	if place_at_pos != -1:
		var place_at_snippet := src.substr(place_at_pos, 400)
		_check(place_at_snippet.find("_get_terrain_height") != -1 or place_at_snippet.find("heights") != -1,
			"_place_tank_at 重采样地形高度")

	# --- 数据验证：山谷地图地形高度 ---
	print("\n--- 数据验证: 山谷地图 ---")
	var valley_text := FileAccess.get_file_as_string("res://data/maps/map_valley.json")
	assert(valley_text != "", "Cannot read map_valley.json")
	var valley: Dictionary = JSON.parse_string(valley_text)
	assert(valley.has("terrain"), "Valley map missing terrain")

	var terrain: Dictionary = valley["terrain"]
	var grid_size: int = int(terrain.get("grid_size", 64))
	var heights: Array = terrain.get("heights", [])
	var map_size: float = float(valley.get("size", 1000))
	var n: int = grid_size + 1
	var half: float = map_size * 0.5
	var cell: float = map_size / float(grid_size)

	# 采样几个关键点的高度
	var center_h := _sample_terrain(heights, n, grid_size, cell, half, 0.0, 0.0)
	var edge_h := _sample_terrain(heights, n, grid_size, cell, half, half, 0.0)
	print("  山谷中心高度: %.1fm" % center_h)
	print("  山谷边缘高度: %.1fm" % edge_h)

	# 出生点高度
	var spawn1_h := _sample_terrain(heights, n, grid_size, cell, half, 0.0, 50.0)
	var spawn2_h := _sample_terrain(heights, n, grid_size, cell, half, 0.0, -50.0)
	print("  出生点1高度: %.1fm" % spawn1_h)
	print("  出生点2高度: %.1fm" % spawn2_h)

	# 如果载具被放在边缘（高度80m），Y应该是81.0而非1.0
	_check(center_h < 5.0, "山谷中心接近0m (实际=%.1f)" % center_h)
	_check(edge_h > 50.0, "山谷边缘高度>50m (实际=%.1f)" % edge_h)

	# --- 汇总 ---
	print("\n=== 汇总: failed=%d ===" % _failed)
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)

func _sample_terrain(heights: Array, n: int, grid_size: int, cell: float, half: float, x: float, z: float) -> float:
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
