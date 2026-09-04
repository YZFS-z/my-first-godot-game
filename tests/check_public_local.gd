extends SceneTree
## 校验：公网联机模式 is_public_local 属性在全部三类载具上可用
## 复现场景：main.gd:731 _setup_public_game() 直接赋值 player_tank.is_public_local = true
## 若载具脚本未声明该属性，Godot 会报 "Invalid assignment of property or key" 并中断
## 覆盖：坦克（vehicle.tscn）、直升机（helicopter.tscn）、固定翼（airplane.tscn）

var _failed := 0
var _frame := 0
var _done := false
var _vehicles: Array = []

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _spawn(scene_path: String, data_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = false
	v.is_server_controlled = false
	v.team = 1
	root.add_child(v)
	v.setup_from_data(_load_json(data_path))
	return v

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakePublicLocalTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 按 main.gd 公网模式的载具实例化路径逐一生成
	_vehicles = [
		_spawn("res://scenes/vehicle.tscn", "res://data/vehicles/tank_abrams.json"),
		_spawn("res://scenes/helicopter.tscn", "res://data/vehicles/heli_ah64.json"),
		_spawn("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json"),
	]
	print("INFO: 已生成 %d 辆载具，开始校验 is_public_local..." % _vehicles.size())

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame < 3:
		return false  # 等进树完成
	for v in _vehicles:
		var vid: String = v.vehicle_id
		_check("is_public_local" in v, "[%s] 属性存在声明" % vid)
		_check(v.is_public_local == false, "[%s] 默认值为 false" % vid)
		# 模拟 main.gd:731 的直接赋值（修复前此处报 Invalid assignment 崩溃）
		v.is_public_local = true
		_check(v.is_public_local == true, "[%s] main.gd:731 赋值成功且读回 true" % vid)
		# 与 JSON 判定路径一致：propagate 后可通过 in / get 读取
		_check(v.get("is_public_local") == true, "[%s] get() 读取一致" % vid)
	_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)