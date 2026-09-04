extends SceneTree
## 隔离测试：ConcavePolygonShape3D 三角网格碰撞体 — 验证位置对齐 + CharacterBody 碰撞

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
	print("=== ConcavePolygonShape3D Collision Test ===")

	# 1. 创建一个有高低起伏的三角网格地形（与 terrain_builder 相同的坐标体系）
	var n := 4
	var cell := 10.0
	var half := (n - 1) * cell * 0.5  # = 15
	var grid_size := n - 1  # = 3

	# 生成高度数据：中心高、四周低
	var heights := []
	heights.resize(n * n)
	for z in range(n):
		for x in range(n):
			var dx := float(x) - float(n - 1) * 0.5
			var dz := float(z) - float(n - 1) * 0.5
			var h := maxf(0.0, 5.0 - sqrt(dx * dx + dz * dz) * 2.0)
			heights[z * n + x] = h

	# 创建 ConcavePolygonShape3D
	var ground_body := StaticBody3D.new()
	ground_body.name = "TestGround"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var trimesh := ConcavePolygonShape3D.new()
	var vertices := PackedVector3Array()
	for zg in range(grid_size):
		for xg in range(grid_size):
			var i00 = zg * n + xg
			var i10 = zg * n + xg + 1
			var i01 = (zg + 1) * n + xg
			var i11 = (zg + 1) * n + xg + 1
			var h00 = float(heights[i00])
			var h10 = float(heights[i10])
			var h01 = float(heights[i01])
			var h11 = float(heights[i11])
			var v00 = Vector3(xg * cell - half, h00, zg * cell - half)
			var v10 = Vector3((xg + 1) * cell - half, h10, zg * cell - half)
			var v01 = Vector3(xg * cell - half, h01, (zg + 1) * cell - half)
			var v11 = Vector3((xg + 1) * cell - half, h11, (zg + 1) * cell - half)
			vertices.append(v00)
			vertices.append(v01)
			vertices.append(v10)
			vertices.append(v10)
			vertices.append(v01)
			vertices.append(v11)
	trimesh.set_faces(vertices)
	trimesh.backface_collision = true
	col.shape = trimesh
	ground_body.add_child(col)
	root.add_child(ground_body)

	# 2. 等待物理帧让碰撞体就绪
	await physics_frame
	await physics_frame

	# 3. 多点射线采样验证位置对齐
	var helper := Node3D.new()
	root.add_child(helper)
	var space := helper.get_world_3d().direct_space_state

	print("Heightmap data:")
	for z in range(n):
		var row := ""
		for x in range(n):
			row += "%.2f " % float(heights[z * n + x])
		print("  z=%d: %s" % [z, row])

	# 中心 (0,0) 应命中 ~3.59（网格中心高度）
	# 角点 (-15,-15) 应命中 ~0.76（角点高度）
	# 角点 (15,15) 应命中 ~0.76
	var sample_points := [Vector3(0,0,0), Vector3(-15,0,-15), Vector3(15,0,15), Vector3(15,0,-15), Vector3(-15,0,15)]
	for sp in sample_points:
		var rf := Vector3(sp.x, 50, sp.z)
		var rt := Vector3(sp.x, -50, sp.z)
		var rq := PhysicsRayQueryParameters3D.create(rf, rt)
		rq.collision_mask = 1
		var rr := space.intersect_ray(rq)
		if rr.is_empty():
			print("  Ray (%.0f,%.0f): NO HIT" % [sp.x, sp.z])
		else:
			print("  Ray (%.0f,%.0f): hit_y=%.3f" % [sp.x, sp.z, rr.position.y])

	# 中心 (0,0) 应命中 ~3.59
	var ray_result := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 50, 0), Vector3(0, -50, 0), 1))
	var center_y := -999.0
	if not ray_result.is_empty():
		center_y = ray_result.position.y
	print("Center raycast: y=%.3f (expected ~3.59)" % center_y)
	_check(center_y > 3.0 and center_y < 4.0, "Center (0,0) hits at ~3.59 (got %.3f)" % center_y)

	# 4. 创建 CharacterBody3D 测试碰撞
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 3
	body.floor_snap_length = 2.0
	body.safe_margin = 0.04
	var body_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 1.2, 6.0)
	body_col.shape = box
	body_col.position = Vector3(0, 0.6, 0)
	body.add_child(body_col)
	body.position = Vector3(0, 10.0, 0)
	root.add_child(body)

	# 5. 施加重力并运行物理帧
	var GRAVITY := 20.0
	print("Starting body at y=10.0, applying gravity...")
	for frame in range(120):
		body.velocity.y -= GRAVITY * (1.0 / 60.0)
		body.move_and_slide()
		await physics_frame
		if frame < 5 or frame % 20 == 0 or frame == 119:
			print("  frame%d: y=%.4f on_floor=%s vel.y=%.3f" % [frame, body.global_position.y, body.is_on_floor(), body.velocity.y])

	var final_y := body.global_position.y
	print("Final: y=%.4f (expected ~3.59 if collision works)" % final_y)
	_check(final_y > 3.0 and final_y < 4.2, "CharacterBody3D collides with trimesh (final_y=%.3f, expected ~3.59)" % final_y)

	body.queue_free()
	ground_body.queue_free()
	helper.queue_free()
	await physics_frame

	print("\n=== Summary: passed=%d failed=%d ===" % [_passed, _failed])
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
