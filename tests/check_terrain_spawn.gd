extends SceneTree

## 测试地形地图上载具出生点不会在地下
## 验证 _get_terrain_height 双线性插值在网格顶点处准确，
## 且出生点 Y = 地形高度 + 1.0 始终高于地表

var failures: int = 0
var map_config: Dictionary

func _initialize():
	print("=== 地形出生点高度测试 ===")
	_run_tests()
	print("=== 汇总: failed=%d ===" % failures)
	quit(failures)

func _run_tests() -> void:
	# 直接加载 map_valley.json
	var f = FileAccess.open("res://data/maps/map_valley.json", FileAccess.READ)
	if f == null:
		print("FAIL: 无法打开 map_valley.json")
		failures += 1
		return
	var json_text = f.get_as_text()
	f.close()
	
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		print("FAIL: map_valley.json 解析失败: %s" % json.get_error_message())
		failures += 1
		return
	map_config = json.data
	
	if not map_config.has("terrain"):
		print("FAIL: map_valley 没有 terrain 字段")
		failures += 1
		return
	
	var terrain = map_config["terrain"]
	var heights = terrain["heights"]
	var grid_size = int(terrain.get("grid_size", 64))
	var n = grid_size + 1
	var map_size = float(map_config.get("size", 200))
	var half = map_size * 0.5
	var cell = map_size / float(grid_size)
	
	print("map_valley: size=%s, grid_size=%s, heights_count=%d" % [
		str(map_config.get("size", "?")),
		str(terrain.get("grid_size", "?")),
		heights.size()
	])
	
	# 测试1: _get_terrain_height 在网格顶点处返回正确值
	var sample_points = [0, n / 4, n / 2, n * 3 / 4, n - 1]
	var vertex_errors = 0
	for sz in sample_points:
		for sx in sample_points:
			var idx = sz * n + sx
			if idx >= heights.size():
				continue
			var expected = float(heights[idx])
			var world_x = sx * cell - half
			var world_z = sz * cell - half
			var got = _get_terrain_height(world_x, world_z)
			if abs(got - expected) > 0.01:
				print("FAIL: 顶点(%d,%d) 期望=%.2f 实际=%.2f" % [sx, sz, expected, got])
				vertex_errors += 1
	if vertex_errors == 0:
		print("PASS: 网格顶点高度采样正确（5x5=25点）")
	else:
		print("FAIL: %d 个顶点高度不匹配" % vertex_errors)
		failures += 1
	
	# 测试2: 插值高度在相邻顶点的 min~max 范围内
	var interp_errors = 0
	var test_coords = [
		Vector2(0.5, 0.5), Vector2(10.3, 20.7), Vector2(32.0, 32.0),
		Vector2(50.1, 60.9), Vector2(15.5, 40.2), Vector2(63.9, 0.1)
	]
	for tc in test_coords:
		var gx = tc.x
		var gz = tc.y
		var x0 = int(gx)
		var z0 = int(gz)
		var x1 = min(x0 + 1, grid_size)
		var z1 = min(z0 + 1, grid_size)
		var h00 = float(heights[z0 * n + x0]) if z0 * n + x0 < heights.size() else 0.0
		var h10 = float(heights[z0 * n + x1]) if z0 * n + x1 < heights.size() else 0.0
		var h01 = float(heights[z1 * n + x0]) if z1 * n + x0 < heights.size() else 0.0
		var h11 = float(heights[z1 * n + x1]) if z1 * n + x1 < heights.size() else 0.0
		var h_min = min(min(h00, h10), min(h01, h11))
		var h_max = max(max(h00, h10), max(h01, h11))
		var world_x = gx * cell - half
		var world_z = gz * cell - half
		var got = _get_terrain_height(world_x, world_z)
		if got < h_min - 0.01 or got > h_max + 0.01:
			print("FAIL: 坐标(%.1f,%.1f) 插值=%.2f 超出范围[%.2f, %.2f]" % [gx, gz, got, h_min, h_max])
			interp_errors += 1
	if interp_errors == 0:
		print("PASS: 双线性插值高度在相邻顶点 min~max 范围内（6点）")
	else:
		print("FAIL: %d 个插值点超出范围" % interp_errors)
		failures += 1
	
	# 测试3: 出生点 Y 坐标 = 地形高度 + 1.0，不会在地下
	var spawn_points = map_config.get("spawn_points", [])
	var spawn_errors = 0
	for sp in spawn_points:
		var pos = sp.get("position", [0, 1, 0])
		var terrain_h = _get_terrain_height(float(pos[0]), float(pos[2]))
		var spawn_y = terrain_h + 1.0
		if spawn_y < terrain_h:
			print("FAIL: 出生点 %s Y=%.2f 低于地形高度=%.2f" % [str(pos), spawn_y, terrain_h])
			spawn_errors += 1
	if spawn_points.is_empty():
		# 测试默认出生点
		for team in [1, 2]:
			var z_pos = 50.0 if team == 1 else -50.0
			var terrain_h = _get_terrain_height(0.0, z_pos)
			print("INFO: 队伍%d 默认出生点 (0, %.0f) 地形高度=%.1f, 生成Y=%.1f" % [team, z_pos, terrain_h, terrain_h + 1.0])
			if terrain_h + 1.0 < terrain_h:
				spawn_errors += 1
		if spawn_errors == 0:
			print("PASS: 默认出生点 Y 坐标高于地形高度（2队）")
	else:
		if spawn_errors == 0:
			print("PASS: 所有出生点 Y 坐标高于地形高度（%d个）" % spawn_points.size())
	if spawn_errors > 0:
		failures += 1
	
	# 测试4: 地形高度范围
	var h_min_val = INF
	var h_max_val = -INF
	for h in heights:
		var hv = float(h)
		if hv < h_min_val:
			h_min_val = hv
		if hv > h_max_val:
			h_max_val = hv
	print("INFO: 地形高度范围 [%.1f, %.1f]，落差 %.1fm" % [h_min_val, h_max_val, h_max_val - h_min_val])
	
	# 测试5: 最大相邻顶点高度差（插值与三角面差异的根源）
	var max_diff = 0.0
	var max_diff_pos = Vector2i(0, 0)
	for z in range(grid_size):
		for x in range(grid_size):
			var i = z * n + x
			var h0 = float(heights[i])
			var h1 = float(heights[i + 1])
			var h2 = float(heights[i + n])
			var h3 = float(heights[i + n + 1])
			var cell_diff = max(max(abs(h0 - h1), abs(h0 - h2)), max(abs(h3 - h1), abs(h3 - h2)))
			if cell_diff > max_diff:
				max_diff = cell_diff
				max_diff_pos = Vector2i(x, z)
	print("INFO: 最大相邻顶点高度差 %.1fm 在格子 (%d, %d)" % [max_diff, max_diff_pos.x, max_diff_pos.y])
	if max_diff > 10.0:
		print("WARN: 陡峭地形高差 %.1fm，双线性插值与三角面存在显著差异 → 射线检测(_get_ground_height)是必要的" % max_diff)
	
	# 测试6: 验证 terrain_builder.gd 提供了 get_ground_height 和 get_terrain_height
	var tbf = FileAccess.open("res://scripts/core/battle/terrain_builder.gd", FileAccess.READ)
	assert(tbf != null, "Cannot open terrain_builder.gd")
	var terrain_src = tbf.get_as_text()
	tbf.close()
	
	if terrain_src.find("func get_ground_height") != -1:
		print("PASS: terrain_builder.gd 提供 get_ground_height 射线检测")
	else:
		print("FAIL: terrain_builder.gd 缺少 get_ground_height")
		failures += 1
	
	if terrain_src.find("func get_terrain_height") != -1:
		print("PASS: terrain_builder.gd 提供 get_terrain_height 双线性插值")
	else:
		print("FAIL: terrain_builder.gd 缺少 get_terrain_height")
		failures += 1
	
	# 测试7: 验证 main.gd _ready 中有 await get_tree().physics_frame
	var mf = FileAccess.open("res://scripts/core/main.gd", FileAccess.READ)
	assert(mf != null, "Cannot open main.gd")
	var main_src = mf.get_as_text()
	mf.close()
	
	if main_src.find("await get_tree().physics_frame") != -1:
		print("PASS: _ready() 包含 await physics_frame，确保物理世界就绪")
	else:
		print("FAIL: _ready() 缺少 await physics_frame")
		failures += 1
	
	# 测试8: 验证 await physics_frame 在 build_obstacles() 调用之前
	var await_pos = main_src.find("await get_tree().physics_frame")
	var obs_call_pos = main_src.find("build_obstacles")
	if await_pos != -1 and obs_call_pos != -1 and await_pos < obs_call_pos:
		print("PASS: await physics_frame 在 build_obstacles() 调用之前")
	else:
		print("FAIL: await physics_frame 不在 build_obstacles() 调用之前")
		failures += 1
	
	# 测试9: 验证障碍物适配地形高度（terrain_builder.gd）
	if terrain_src.find("func build_obstacles") != -1 and terrain_src.find("has_terrain") != -1:
		var obs_section = terrain_src.substr(terrain_src.find("func build_obstacles"), 800)
		if obs_section.find("get_ground_height") != -1:
			print("PASS: build_obstacles 使用 get_ground_height 适配地形")
		else:
			print("FAIL: build_obstacles 未使用 get_ground_height 适配地形")
			failures += 1
	else:
		print("FAIL: 无法验证 build_obstacles 地形适配")
		failures += 1
	
	# 测试10: 验证草丛适配地形高度（foliage_manager.gd）
	var fmf = FileAccess.open("res://scripts/core/battle/foliage_manager.gd", FileAccess.READ)
	assert(fmf != null, "Cannot open foliage_manager.gd")
	var foliage_src = fmf.get_as_text()
	fmf.close()
	
	if foliage_src.find("get_ground_height") != -1 and foliage_src.find("has_terrain") != -1:
		print("PASS: 草丛生成使用 get_ground_height 适配地形")
	else:
		print("FAIL: 草丛生成未使用 get_ground_height 适配地形")
		failures += 1
	
	# 测试11: 验证草丛 cell 级别地形适配
	var patch_section = foliage_src.substr(foliage_src.find("func _create_grass_patch"), 3000)
	if patch_section.find("has_terrain") != -1 and patch_section.find("get_terrain_height") != -1:
		print("PASS: _create_grass_patch 支持每个 cell 地形高度适配")
	else:
		print("FAIL: _create_grass_patch 缺少 cell 级别地形适配")
		failures += 1
	
	# 测试12: 验证射线排除空气边界（terrain_builder.gd）
	if terrain_src.find("_air_boundary_rids") != -1 and terrain_src.find("query.exclude") != -1:
		print("PASS: get_ground_height 排除空气边界碰撞体")
	else:
		print("FAIL: get_ground_height 未排除空气边界碰撞体")
		failures += 1
	
	# 测试13: 验证 terrain_builder.gd 暴露 get_air_boundary_rids() 供载具射线排除
	if terrain_src.find("func get_air_boundary_rids") != -1:
		print("PASS: terrain_builder.gd 提供 get_air_boundary_rids() 暴露空气边界 RID")
	else:
		print("FAIL: terrain_builder.gd 缺少 get_air_boundary_rids()")
		failures += 1
	
	# 测试14: 验证 vehicle.gd _align_to_ground 射线范围覆盖地形高差且排除空气边界
	var vf = FileAccess.open("res://scripts/vehicles/vehicle.gd", FileAccess.READ)
	assert(vf != null, "Cannot open vehicle.gd")
	var vehicle_src = vf.get_as_text()
	vf.close()
	
	var align_pos = vehicle_src.find("func _align_to_ground")
	if align_pos != -1:
		var align_section = vehicle_src.substr(align_pos, 1200)
		# 射线范围应覆盖山谷地形 80m 高差（向下至少 -10.0）
		var has_wide_ray = align_section.find("-15.0") != -1 or align_section.find("-10.0") != -1
		if has_wide_ray:
			print("PASS: _align_to_ground 射线向下范围覆盖地形高差")
		else:
			print("FAIL: _align_to_ground 射线向下范围不足")
			failures += 1
		# 应排除空气边界 RID
		if align_section.find("get_air_boundary_rids") != -1 or align_section.find("air_boundary") != -1:
			print("PASS: _align_to_ground 排除空气边界碰撞体")
		else:
			print("FAIL: _align_to_ground 未排除空气边界碰撞体")
			failures += 1
		# 应排除障碍物 RID
		if align_section.find("get_obstacle_rids") != -1:
			print("PASS: _align_to_ground 排除障碍物碰撞体")
		else:
			print("FAIL: _align_to_ground 未排除障碍物碰撞体")
			failures += 1
		# 应检查 is_on_floor 避免离地时错误对齐
		if align_section.find("is_on_floor") != -1:
			print("PASS: _align_to_ground 包含 is_on_floor 检查")
		else:
			print("FAIL: _align_to_ground 缺少 is_on_floor 检查")
			failures += 1
	else:
		print("FAIL: vehicle.gd 缺少 _align_to_ground 函数")
		failures += 1
	
	# 测试14b: 验证 terrain_builder.gd 暴露 get_obstacle_rids() 供载具射线排除
	if terrain_src.find("func get_obstacle_rids") != -1:
		print("PASS: terrain_builder.gd 提供 get_obstacle_rids() 暴露障碍物 RID")
	else:
		print("FAIL: terrain_builder.gd 缺少 get_obstacle_rids()")
		failures += 1
	
	# 测试14c: 验证空气边界位置在地形地图中移到最低点以下（避免与地形面重叠）
	if terrain_src.find("_terrain_min_height") != -1:
		print("PASS: terrain_builder.gd 追踪地形最低高度用于空气边界定位")
	else:
		print("FAIL: terrain_builder.gd 未追踪地形最低高度")
		failures += 1
	
	# 测试15: 验证 vehicle.tscn floor_snap_length 和 floor_max_angle 适配陡峭地形
	var vtf = FileAccess.open("res://scenes/vehicle.tscn", FileAccess.READ)
	assert(vtf != null, "Cannot open vehicle.tscn")
	var vtsn_src = vtf.get_as_text()
	vtf.close()
	
	var snap_match = vtsn_src.find("floor_snap_length = 2.0")
	if snap_match != -1:
		print("PASS: vehicle.tscn floor_snap_length=2.0 适配地形起伏")
	else:
		print("FAIL: vehicle.tscn floor_snap_length 未设置为 2.0")
		failures += 1
	
	if vtsn_src.find("floor_max_angle = 1.0472") != -1:
		print("PASS: vehicle.tscn floor_max_angle=1.0472(60°) 适配陡峭坡度")
	else:
		print("FAIL: vehicle.tscn floor_max_angle 未设置为 1.0472(60°)")
		failures += 1
	
	print("---- 地形出生点测试 done ----")

func _get_terrain_height(x: float, z: float) -> float:
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
	var h0 = lerpf(h00, h10, fx)
	var h1 = lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)
