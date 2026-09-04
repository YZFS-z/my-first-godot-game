extends SceneTree

func _init():
	print("=== Terrain Function Check ===")
	
	# Test bilinear interpolation logic (same as main.gd _get_terrain_height)
	var grid_size = 4
	var n = grid_size + 1  # 5
	var heights = PackedFloat32Array()
	heights.resize(n * n)
	# Create a simple ramp: height = x * 2
	for z in range(n):
		for x in range(n):
			heights[z * n + x] = float(x) * 2.0
	
	# Sample at center (x=2, z=2) should be 4.0
	var h = _bilinear_sample(heights, grid_size, n, 2.0, 2.0)
	assert(absf(h - 4.0) < 0.01, "Center sample should be 4.0, got %f" % h)
	print("PASS: Bilinear sample at (2,2) = %.2f (expected 4.0)" % h)
	
	# Sample at (1.5, 2) should be 3.0 (between 2.0 and 4.0)
	h = _bilinear_sample(heights, grid_size, n, 1.5, 2.0)
	assert(absf(h - 3.0) < 0.01, "Midpoint sample should be 3.0, got %f" % h)
	print("PASS: Bilinear sample at (1.5,2) = %.2f (expected 3.0)" % h)
	
	# Sample at (0, 0) should be 0.0
	h = _bilinear_sample(heights, grid_size, n, 0.0, 0.0)
	assert(absf(h) < 0.01, "Corner sample should be 0.0, got %f" % h)
	print("PASS: Bilinear sample at (0,0) = %.2f (expected 0.0)" % h)
	
	# Test SurfaceTool mesh building logic
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var map_size = 200.0
	var cell = map_size / grid_size
	var half = map_size * 0.5
	for z in range(n):
		for x in range(n):
			var idx = z * n + x
			var hh = heights[idx]
			st.add_vertex(Vector3(x * cell - half, hh, z * cell - half))
	for z in range(grid_size):
		for x in range(grid_size):
			var i = z * n + x
			st.add_index(i)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + n + 1)
	st.generate_normals()
	var mesh = st.commit()
	assert(mesh != null, "Mesh should not be null")
	assert(mesh.get_surface_count() == 1, "Mesh should have 1 surface")
	print("PASS: SurfaceTool mesh built with %d surfaces" % mesh.get_surface_count())
	
	# Test trimesh shape creation
	var shape = mesh.create_trimesh_shape()
	assert(shape != null, "Trimesh shape should not be null")
	print("PASS: Trimesh collision shape created from mesh")
	
	# Test brush falloff calculation (cosine falloff)
	var brush_radius = 10.0
	var dist = 5.0
	var falloff = cos(dist / brush_radius * PI * 0.5)
	assert(falloff > 0.0 and falloff < 1.0, "Falloff at half radius should be between 0 and 1")
	print("PASS: Brush falloff at dist=5/radius=10 = %.4f (cosine)" % falloff)
	
	# Falloff at center should be 1.0
	falloff = cos(0.0 / brush_radius * PI * 0.5)
	assert(absf(falloff - 1.0) < 0.01, "Falloff at center should be 1.0")
	print("PASS: Brush falloff at center = %.4f (expected 1.0)" % falloff)
	
	# Falloff at edge should be 0.0
	falloff = cos(brush_radius / brush_radius * PI * 0.5)
	assert(absf(falloff) < 0.01, "Falloff at edge should be 0.0")
	print("PASS: Brush falloff at edge = %.4f (expected 0.0)" % falloff)
	
	print("")
	print("=== All terrain function checks passed ===")
	quit(0)

func _bilinear_sample(heights: PackedFloat32Array, grid_size: int, n: int, gx: float, gz: float) -> float:
	"""Same logic as main.gd _get_terrain_height bilinear interpolation"""
	gx = clampf(gx, 0.0, float(grid_size))
	gz = clampf(gz, 0.0, float(grid_size))
	var x0 = int(gx)
	var z0 = int(gz)
	var x1 = min(x0 + 1, grid_size)
	var z1 = min(z0 + 1, grid_size)
	var fx = gx - x0
	var fz = gz - z0
	var h00 = float(heights[z0 * n + x0])
	var h10 = float(heights[z0 * n + x1])
	var h01 = float(heights[z1 * n + x0])
	var h11 = float(heights[z1 * n + x1])
	var h0 = lerpf(h00, h10, fx)
	var h1 = lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)
