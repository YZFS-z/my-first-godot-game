extends SceneTree
## 测试坦克在平坦地面上能否正常移动
## 验证 floor_snap_length + safe_margin + 平坦地形 BoxShape3D 优化

var _tank: CharacterBody3D = null
var _ground: StaticBody3D = null
var _frame := 0
var _phase := 0  # 0=落地等待, 1=移动测试, 2=完成
var _start_pos := Vector3.ZERO
var _failed := 0
var _done := false

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	print("=== Flat Ground Movement Check ===")

	# --- 源码检查 ---
	var f := FileAccess.open("res://scenes/vehicle.tscn", FileAccess.READ)
	assert(f != null, "Cannot open vehicle.tscn")
	var tscn := f.get_as_text()
	f.close()
	_check(tscn.find("floor_snap_length") != -1, "vehicle.tscn 包含 floor_snap_length")
	_check(tscn.find("safe_margin") != -1, "vehicle.tscn 包含 safe_margin")

	f = FileAccess.open("res://scripts/vehicles/tank.gd", FileAccess.READ)
	assert(f != null, "Cannot open tank.gd")
	var tank_src := f.get_as_text()
	f.close()
	_check(tank_src.find("mouse_sensitivity: float = 0.3") != -1, "tank.gd mouse_sensitivity=0.3")

	f = FileAccess.open("res://scripts/core/battle/terrain_builder.gd", FileAccess.READ)
	assert(f != null, "Cannot open terrain_builder.gd")
	var terrain_src := f.get_as_text()
	f.close()
	_check(terrain_src.find("all_flat") != -1, "terrain_builder.gd 平坦地形检测 all_flat")
	_check(terrain_src.find("BoxShape3D") != -1, "terrain_builder.gd 平坦地形用 BoxShape3D")

	if _failed > 0:
		print("\n源码检查失败，跳过运行时测试")
		print("RESULT: failed=%d" % _failed)
		quit(1)
		return

	# --- 运行时测试：BoxShape3D 地面 ---
	_setup_scene()
	print("\n--- 运行时测试: BoxShape3D 地面 ---")

func _setup_scene() -> void:
	# 地面（BoxShape3D，顶面 y=0）
	_ground = StaticBody3D.new()
	_ground.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	_ground.add_child(col)
	root.add_child(_ground)

	# 坦克
	var tank_scene: PackedScene = load("res://scenes/vehicle.tscn")
	var data_text := FileAccess.get_file_as_string("res://data/vehicles/tank_abrams.json")
	assert(data_text != "", "Cannot read tank data")
	var data: Dictionary = JSON.parse_string(data_text)
	assert(data.has("physics"), "Tank data missing physics")

	_tank = tank_scene.instantiate()
	_tank.is_player_controlled = true
	_tank.position = Vector3(0, 2.0, 0)
	root.add_child(_tank)
	_tank.setup_from_data(data)

	_frame = 0
	_phase = 0

func _physics_process(delta: float) -> bool:
	if _done:
		return false
	if _tank == null or not is_instance_valid(_tank):
		print("ERROR: tank is null or freed")
		quit(1)
		return true
	_frame += 1
	# 安全超时
	if _frame > 600:
		print("ERROR: test timeout")
		quit(1)
		return true

	if _phase == 0:
		# 等待坦克落地（约1秒）
		if _frame == 60:
			var on_floor: bool = _tank.is_on_floor()
			print("  落地: is_on_floor=%s y=%.3f" % [on_floor, _tank.position.y])
			# 注入前进输入
			_tank.input_throttle = 1.0
			_tank.input_steering = 0.0
			_start_pos = _tank.position
			_phase = 1
			_frame = 0
			print("  注入 input_throttle=1.0, 开始移动测试")
		return false

	if _phase == 1:
		# 持续注入输入
		_tank.input_throttle = 1.0
		# 运行120帧（2秒）后检查
		if _frame >= 120:
			var moved: float = _tank.position.distance_to(_start_pos)
			var moved_z: float = abs(_tank.position.z - _start_pos.z)
			print("  移动距离: %.3f m (start=%.2f,%.2f end=%.2f,%.2f)" % [
				moved, _start_pos.x, _start_pos.z, _tank.position.x, _tank.position.z
			])
			_check(moved > 1.0, "BoxShape3D 地面坦克可移动 (距离=%.2fm)" % moved)

			# 验证 CharacterBody3D 属性
			_check(abs(_tank.floor_snap_length - 2.0) < 0.001, "floor_snap_length=2.0 (实际=%.2f)" % _tank.floor_snap_length)
			_check(abs(_tank.safe_margin - 0.04) < 0.001, "safe_margin=0.04 (实际=%.3f)" % _tank.safe_margin)

			# 验证 mouse_sensitivity
			var ms: float = _tank.mouse_sensitivity
			_check(ms > 0.2, "mouse_sensitivity > 0.2 (实际=%.2f)" % ms)

			# 清理
			_tank.queue_free()
			_ground.queue_free()
			_done = true

			print("\n=== 汇总: failed=%d ===" % _failed)
			if _failed == 0:
				print("RESULT: failed=0")
				quit(0)
			else:
				print("RESULT: failed=%d" % _failed)
				quit(1)
		return false
	return false
