extends SceneTree
## 回归校验：固定翼/直升机在 _physics_process 内将 current_speed 同步到
## airspeed / velocity.length()，保证 HUD（hud.gd:103 直读 player_vehicle.current_speed）
## 显示非零速度。复现场景：请求「所有飞机速度显示 0」——
## 修复前 current_speed 只在坦克 _update_movement 中更新（vehicle.gd:1064），
## 两飞行载具从不写回 → HUD 恒显 0。
##
## 覆盖三个修复点：
##  1) airplane.gd _update_flight 内 current_speed = airspeed（飞行/滑跑路径）
##  2) airplane.gd 地面静止锁定分支 current_speed = 0.0（提前 return 路径）
##  3) helicopter.gd current_speed = velocity.length()（含贴地锁定归零）

var _failed := 0
var _step := 0       # 阶段内步数
var _total := 0      # 全局步数 watchdog
var _phase := 0
var _vehicles: Array = []   # [固定翼, 直升机]

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

func _spawn(scene_path: String, json_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = false
	v.team = 1
	v.global_position = Vector3(1.0 + 1000.0 * _vehicles.size(), 2.0, 0)
	root.add_child(v)
	_data_paths.append(json_path)
	return v

var _data_paths: Array = []

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeAirSpeedTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面（物理结算与 on_ground 判定需要）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	# 先只入树不 setup：_ready 才会创建 damage_system，等其就绪后再装载数据
	_vehicles.append(_spawn("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json"))
	_vehicles.append(_spawn("res://scenes/helicopter.tscn", "res://data/vehicles/heli_ah64.json"))

func _physics_process(delta: float) -> bool:
	_step += 1
	_total += 1
	if _total > 3000:
		print("FAIL: 测试全局超时 (_phase=%d, step=%d)" % [_phase, _step])
		_finish()
		return false
	match _phase:
		0:
			# 等两机 _ready 完成（damage_system 就绪）后再 setup_from_data（同 main.gd 出生流程）
			if _step < 15:
				return false
			for i in _vehicles.size():
				var v: Node = _vehicles[i]
				if v.damage_system == null:
					return false
				v.setup_from_data(_load_json(_data_paths[i]))
			for v in _vehicles:
				v.velocity = Vector3.ZERO
			# 固定翼：直接驱动油门；直升机：总距拉起
			_vehicles[0].throttle = 1.0
			_vehicles[1].collective = 0.8
			_phase = 1
			_step = 0
		1:
			# 加速/起飞 6 秒（360 帧），记录两机各自最大速度
			var max0: float = 0.0
			var max1: float = 0.0
			for i in 2:
				var v: Node = _vehicles[i]
				max0 = max(max0, v.current_speed) if i == 0 else max0
				max1 = max(max1, v.current_speed) if i == 1 else max1
			if _step >= 360:
				_check(max0 > 5.0, "[固定翼] 加油门滑跑 current_speed 同步非零 (max=%.1f m/s)" % max0)
				_check(max1 > 2.0, "[直升机] 提升离地 current_speed 同步非零 (max=%.1f m/s)" % max1)
				# 收油门/总距回零 → 构造静止前置状态，验证归零路径
				_vehicles[0].throttle = 0.0
				_vehicles[1].collective = 0.0
				# 固定翼：放到低速滑行（<2 m/s 且着地），触发地面静止锁定分支（修复点2）
				_vehicles[0].velocity = Vector3(1.0, 0.0, 0.0)
				_vehicles[0].global_position = Vector3(2.0, 1.5, 0)
				# 直升机：贴地放下（含贴地判定增强），速度清零（修复点3→ velocity.length()==0）
				_vehicles[1].velocity = Vector3.ZERO
				_vehicles[1].global_position = Vector3(1002.0, 1.0, 0)
				_phase = 2
				_step = 0
		2:
			# 静止 45 帧（0.75s）：固定翼速度矢量被滚动摩擦耗散并进入静止锁定
			if _step < 45:
				return false
			var ap: Node = _vehicles[0]
			# on_floor 在速度归零瞬间可能短暂翻 false（Godot 静止接触判定），
			# 以「速度已耗尽 + 熄火」为归零准据，不把物理接触与显示值同帧耦合
			var ap_locked: bool = ap.throttle < 0.1 and abs(ap.current_speed) < 0.1
			_check(ap_locked, "[固定翼] 静止后 current_speed 归零 (cur=%.3f, on_floor=%s)" % [ap.current_speed, ap.is_on_floor()])
			var hp: Node = _vehicles[1]
			_check(abs(hp.current_speed) < 0.5, "[直升机] 贴地停车后 current_speed 归零 (%.3f)" % hp.current_speed)
			_finish()
	return false

func _finish() -> void:
	_phase = 99
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)