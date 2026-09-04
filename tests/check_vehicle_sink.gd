extends SceneTree
## 物理帧测试：山谷地图载具落地，检查缝隙和下沉

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
	print("=== Vehicle Sink/Gap Physics Test (Valley Map) ===")

	# 设置 GameManager 使用山谷图
	var gm = root.get_node("GameManager")
	gm.selected_map_id = "map_valley"
	gm.selected_vehicle_id = "tank_abrams"

	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)

	# 等待 main._ready() 完成（含 await process_frame + physics_frame）
	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame

	var tb = main.get_node_or_null("TerrainBuilder")
	assert(tb != null, "TerrainBuilder not found")

	# 在多个位置测试
	var test_positions := [
		Vector3(0, 0, 50),
		Vector3(0, 0, -50),
		Vector3(100, 0, 100),
		Vector3(-100, 0, -100),
		Vector3(200, 0, 0),
	]

	for i in range(test_positions.size()):
		var pos = test_positions[i]
		var terrain_h = tb.get_terrain_height(pos.x, pos.z)
		var ground_h = tb.get_ground_height(pos.x, pos.z)

		# 生成载具（挂到 main 下，共享 World3D）
		var vehicle_scene = load("res://scenes/vehicle.tscn")
		var vehicle = vehicle_scene.instantiate()
		vehicle.position = Vector3(pos.x, ground_h + 2.0, pos.z)
		vehicle.set("is_player_controlled", true)
		main.add_child(vehicle)

		# 等待载具 setup + 落地
		await physics_frame
		await physics_frame

		# 运行 90 物理帧（1.5秒），让载具充分落地
		for frame in range(90):
			await physics_frame

		var final_pos = vehicle.global_position
		var final_y = final_pos.y
		var on_floor = vehicle.is_on_floor()
		# 用车辆最终位置的地面高度做对比（车辆可能在斜坡上滑动）
		var ground_h_final = tb.get_ground_height(final_pos.x, final_pos.z)
		var gap = final_y - ground_h_final

		var slide = Vector2(final_pos.x - pos.x, final_pos.z - pos.z).length()
		print("  点%d (%.0f,%.0f): terrain_h=%.2f ground_h=%.2f final_y=%.4f on_floor=%s gap=%.4f slide=%.2f" % [
			i, pos.x, pos.z, terrain_h, ground_h, final_y, on_floor, gap, slide
		])

		# 载具不应下沉（final_y 不应低于最终位置地面高度超过 0.1m）
		_check(final_y >= ground_h_final - 0.1,
			"点%d: 载具未下沉 (final_y=%.4f >= ground_h_final-0.1=%.4f)" % [i, final_y, ground_h_final - 0.1])

		# 载具不应悬空（final_y 不应高于最终位置地面高度超过 0.1m）
		_check(final_y <= ground_h_final + 0.1,
			"点%d: 载具未悬空 (final_y=%.4f <= ground_h_final+0.1=%.4f)" % [i, final_y, ground_h_final + 0.1])

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
