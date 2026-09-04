extends SceneTree

func _init():
	print("=== Valley Map Check ===")
	
	# Load the map JSON
	var f = FileAccess.open("res://data/maps/map_valley.json", FileAccess.READ)
	assert(f != null, "Cannot open map_valley.json")
	var json_text = f.get_as_text()
	f.close()
	
	var json = JSON.new()
	var err = json.parse(json_text)
	assert(err == OK, "JSON parse error: " + json.get_error_message())
	var map = json.data
	
	# 1. Basic fields
	assert(map["id"] == "map_valley", "id should be map_valley")
	assert(map["name"] == "山谷要塞", "name should be 山谷要塞")
	assert(map["source"] == "builtin", "source should be builtin")
	assert(map["size"] == 1000, "size should be 1000")
	print("PASS: Basic map fields correct")
	
	# 2. Terrain data
	var terrain = map["terrain"]
	assert(int(terrain["grid_size"]) == 64, "grid_size should be 64")
	var heights = terrain["heights"]
	assert(heights.size() == 4225, "heights should have 4225 entries (65*65), got %d" % heights.size())
	print("PASS: Terrain data structure correct (grid_size=64, %d heights)" % heights.size())
	
	# 3. Valley shape: center should be low, edges high
	var n = 65
	var center_h = float(heights[32 * n + 32])
	var edge_h = float(heights[0])
	var edge_h2 = float(heights[64 * n + 64])
	assert(center_h < 5.0, "Center height should be low (<5), got %.2f" % center_h)
	assert(edge_h > 40.0, "Edge height should be high (>40), got %.2f" % edge_h)
	assert(edge_h2 > 40.0, "Opposite edge height should be high (>40), got %.2f" % edge_h2)
	print("PASS: Valley shape correct (center=%.1fm, edge=%.1fm, opposite=%.1fm)" % [center_h, edge_h, edge_h2])
	
	# 4. Spawn points
	var spawns = map["spawn_points"]
	assert(spawns.size() == 2, "Should have 2 spawn points")
	var team1_spawn = spawns[0]
	var team2_spawn = spawns[1]
	assert(int(team1_spawn["team"]) == 1, "Team 1 spawn")
	assert(int(team2_spawn["team"]) == 2, "Team 2 spawn")
	var t1_pos = team1_spawn["position"]
	var t2_pos = team2_spawn["position"]
	assert(abs(float(t1_pos[0])) < 50, "Team 1 spawn X should be near center")
	assert(float(t1_pos[2]) > 0, "Team 1 spawn Z should be positive")
	assert(float(t2_pos[2]) < 0, "Team 2 spawn Z should be negative")
	print("PASS: Spawn points correct (team1 Z=%.0f, team2 Z=%.0f)" % [t1_pos[2], t2_pos[2]])
	
	# 5. Spawn area should be relatively flat
	# Sample terrain height near spawn points
	var grid_size = 64
	var map_size = 1000.0
	var cell = map_size / grid_size
	var half = map_size * 0.5
	
	# Team 1 spawn at (0, 1, 400) -> grid coords
	var spawn1_gx = (0 + half) / cell
	var spawn1_gz = (400 + half) / cell
	var spawn1_x0 = int(spawn1_gx)
	var spawn1_z0 = int(spawn1_gz)
	var spawn1_idx = spawn1_z0 * n + spawn1_x0
	var spawn1_h = float(heights[spawn1_idx]) if spawn1_idx < heights.size() else 0.0
	assert(abs(spawn1_h) < 5.0, "Spawn 1 area should be near flat (h=%.2f)" % spawn1_h)
	
	# Team 2 spawn at (0, 1, -400)
	var spawn2_gz = (-400 + half) / cell
	var spawn2_z0 = int(spawn2_gz)
	var spawn2_idx = spawn2_z0 * n + spawn1_x0
	var spawn2_h = float(heights[spawn2_idx]) if spawn2_idx < heights.size() else 0.0
	assert(abs(spawn2_h) < 5.0, "Spawn 2 area should be near flat (h=%.2f)" % spawn2_h)
	print("PASS: Spawn areas flat (team1 h=%.2f, team2 h=%.2f)" % [spawn1_h, spawn2_h])
	
	# 6. Height range reasonable
	var min_h = 999.0
	var max_h = -999.0
	for h in heights:
		var fh = float(h)
		if fh < min_h: min_h = fh
		if fh > max_h: max_h = fh
	assert(max_h > 50.0, "Max height should be >50, got %.2f" % max_h)
	assert(min_h < 5.0, "Min height should be <5, got %.2f" % min_h)
	print("PASS: Height range reasonable (%.1f to %.1f, span=%.1fm)" % [min_h, max_h, max_h - min_h])
	
	# 7. Obstacles and vegetation exist
	assert(map.has("obstacles") and map["obstacles"].size() > 0, "Should have obstacles")
	assert(map.has("grass_patches") and map["grass_patches"].size() > 0, "Should have grass")
	assert(map.has("bush_patches") and map["bush_patches"].size() > 0, "Should have bushes")
	print("PASS: Obstacles(%d), grass(%d), bushes(%d) present" % [map["obstacles"].size(), map["grass_patches"].size(), map["bush_patches"].size()])
	
	print("")
	print("=== All valley map checks passed ===")
	quit(0)
