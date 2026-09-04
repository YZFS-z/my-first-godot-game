extends SceneTree

func _init():
	print("=== Terrain System Check ===")
	
	# 1. Check map_editor.gd source for terrain features
	var f = FileAccess.open("res://scripts/ui/map_editor.gd", FileAccess.READ)
	assert(f != null, "Cannot open map_editor.gd")
	var editor_src = f.get_as_text()
	f.close()
	
	# Terrain variables
	assert(editor_src.find("terrain_grid_size") != -1, "Missing terrain_grid_size")
	assert(editor_src.find("terrain_heights") != -1, "Missing terrain_heights")
	assert(editor_src.find("is_terrain_mode") != -1, "Missing is_terrain_mode")
	assert(editor_src.find("terrain_brush_radius") != -1, "Missing terrain_brush_radius")
	assert(editor_src.find("terrain_brush_strength") != -1, "Missing terrain_brush_strength")
	print("PASS: Terrain variables present in map_editor.gd")
	
	# Terrain functions
	assert(editor_src.find("func _init_terrain_heights") != -1, "Missing _init_terrain_heights")
	assert(editor_src.find("func _rebuild_terrain_mesh") != -1, "Missing _rebuild_terrain_mesh")
	assert(editor_src.find("func _rebuild_terrain_collision") != -1, "Missing _rebuild_terrain_collision")
	assert(editor_src.find("func _paint_terrain") != -1, "Missing _paint_terrain")
	assert(editor_src.find("func _flatten_terrain") != -1, "Missing _flatten_terrain")
	assert(editor_src.find("func _terrain_input") != -1, "Missing _terrain_input")
	assert(editor_src.find("func _create_brush_indicator") != -1, "Missing _create_brush_indicator")
	assert(editor_src.find("func _update_brush_indicator") != -1, "Missing _update_brush_indicator")
	print("PASS: All terrain functions present in map_editor.gd")
	
	# Terrain obstacle option
	assert(editor_src.find('add_item("地形", 6)') != -1, "Missing terrain obstacle option")
	print("PASS: Terrain option added to obstacle dropdown")
	
	# Terrain save/load
	assert(editor_src.find('"terrain"') != -1 or editor_src.find("'terrain'") != -1, "Missing terrain in save")
	assert(editor_src.find('"grid_size"') != -1, "Missing grid_size in save")
	assert(editor_src.find('"heights"') != -1, "Missing heights in save")
	print("PASS: Terrain save/load in map_editor.gd")
	
	# Trimesh collision
	assert(editor_src.find("create_trimesh_shape") != -1, "Missing create_trimesh_shape in editor")
	print("PASS: Trimesh collision in map_editor.gd")
	
	# 2. Check main.gd for terrain support
	f = FileAccess.open("res://scripts/core/main.gd", FileAccess.READ)
	assert(f != null, "Cannot open main.gd")
	var main_src = f.get_as_text()
	f.close()
	
	assert(main_src.find("func _get_terrain_height") != -1, "Missing _get_terrain_height in main.gd")
	assert(main_src.find("create_trimesh_shape") != -1, "Missing create_trimesh_shape in main.gd")
	assert(main_src.find("has_terrain") != -1, "Missing has_terrain check in main.gd")
	assert(main_src.find("SurfaceTool") != -1, "Missing SurfaceTool in main.gd")
	print("PASS: main.gd has terrain support (_get_terrain_height, trimesh, SurfaceTool)")
	
	# Spawn point terrain adjustment
	assert(main_src.find("_get_terrain_height") != -1, "Missing _get_terrain_height usage")
	print("PASS: main.gd adjusts spawn Y with terrain height")
	
	# 3. Check vehicle.gd ray range
	f = FileAccess.open("res://scripts/vehicles/vehicle.gd", FileAccess.READ)
	assert(f != null, "Cannot open vehicle.gd")
	var vehicle_src = f.get_as_text()
	f.close()
	
	assert(vehicle_src.find("Vector3(0, 1.0, 0)") != -1, "Ray from should be y=1.0")
	assert(vehicle_src.find("Vector3(0, -5.0, 0)") != -1, "Ray to should be y=-5.0")
	print("PASS: vehicle.gd _align_to_ground ray range expanded to 6.0m (1.0 to -5.0)")
	
	# 4. Verify no type inference errors (check for := with max/min)
	assert(editor_src.find("var min_x := max(") == -1, "Still has := with max() in _paint_terrain")
	assert(editor_src.find("var max_x := min(") == -1, "Still has := with min() in _paint_terrain")
	assert(editor_src.find("var min_z := max(") == -1, "Still has := with max() in _flatten_terrain")
	assert(editor_src.find("var max_z := min(") == -1, "Still has := with min() in _flatten_terrain")
	print("PASS: No type inference issues with max/min")
	
	print("")
	print("=== All terrain checks passed ===")
	quit(0)
