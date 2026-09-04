extends SceneTree
## 回归校验：公网联机下 固定翼/直升机 与坦克等价地向服务器上报输入与状态
## 复现场景：请求16 —— 手机端开飞机，电脑端看不到飞机（服务器广播列表把不
## 上报状态/心跳的玩家过滤掉：game_server.py `if p["state"]:` + timeout_players）。
## 修复前 airplane.gd/helicopter.gd 的 _physics_process 完全没有
## game_send_input(30Hz)/game_send_state(15Hz) 调用，校验点：
##  1. is_public_local + NetworkManager.game_connected_flag 时上报计时器被驱动
##     （计时器出现清零下降 = if 分支执行过；门控关闭时计时器恒不变）
##  2. 地面静止时固定翼保持机头朝向（不随准星转头；未加油门原地转向不科学），
##     直升机保留原地旋回（尾桨可原地转向）；两机均保持水平不抬头
## 另覆盖：game_send_* 在 game_udp=null（未真实连 UDP）时安全返回不崩溃。

const MAX_STEPS := 400

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _vehicles: Array = []      # [固定翼, 直升机]
var _scripts: Array = []       # 对应脚本路径列表，供等待进树后 setup
var _nm: Node = null
var _old_flag: bool = false
var _drops_in := 0
var _drops_st := 0
var _drops_in2 := 0
var _drops_st2 := 0
var _prev_in: Array = [0.0, 0.0]
var _prev_st: Array = [0.0, 0.0]
var _max_tilt := 0.0
var _settle := 0
var _labels: Array = ["固定翼", "直升机"]

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

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

## 只 add_child 不 setup：_initialize 阶段 root 未 complete ready，damage_system 为空，
## 立即 setup_from_data 会 add_child(null) 崩溃（check_public_local 只查属性才没暴露）。
## setup 延后到进树之后的 phase 0。
## 两机出生坐标分开：airplane.tscn/helicopter.tscn 根节点默认都在原点，同层碰撞体
## 重叠会互相推挤（曾把固定翼顶入地下自由落体到 y=-14.8，导致 phase4 瞬移后
## move_and_slide 基于旧穿透状态恢复异常、继续穿地 → 地面转向校验失败）。
func _spawn(scene_path: String, data_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = true
	v.team = 1
	v.global_position = Vector3(300.0 * _vehicles.size() + 1.0, 0.2, 0)
	root.add_child(v)
	return v

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeAirNetReport"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_ground()
	# --script 主脚本无法解析 autoload 标识符，用节点动态访问
	_nm = root.get_node_or_null("NetworkManager")
	if _nm == null:
		print("FAIL: NetworkManager autoload 未挂载到 root")
		_failed += 1
		_finish()
		return
	_vehicles.append(_spawn("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json"))
	_vehicles.append(_spawn("res://scenes/helicopter.tscn", "res://data/vehicles/heli_ah64.json"))
	_old_flag = _nm.game_connected_flag
	_nm.game_connected_flag = false
	_phase = 0

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if _step > MAX_STEPS * 8:
		print("FAIL: 测试全局超时 @phase=%d" % _phase)
		_finish()
		return false
	match _phase:
		0:
			# 等两机进树并 _ready（damage_system 就绪）后再 setup
			if _step < 8:
				return false
			for i in 2:
				var v: Node = _vehicles[i]
				if v.is_inside_tree() and v.damage_system != null:
					v.setup_from_data(_load_json("res://data/vehicles/%s.json" % ("plane_a10" if i == 0 else "heli_ah64")))
				else:
					_check(false, "[%s] 进树/模块系统未就绪" % _labels[i])
			_phase = 1
			_step = 0
		1:
			# 门控关闭（is_public_local=false, game_connected_flag=false）：
			# 多帧观察上报计时器恒为 0
			if _step < 30:
				return false
			_check(_vehicles[0].get("_net_input_timer") == 0.0 and _vehicles[1].get("_net_input_timer") == 0.0,
				"[门控关闭] 两机上报计时器均不推进 (%.4f/%.4f)" % [_vehicles[0].get("_net_input_timer"), _vehicles[1].get("_net_input_timer")])
			_phase = 2
			_step = 0
		2:
			# 门控开启：注入接近阈值，观察清零（if 分支真实执行）
			_vehicles[0].is_public_local = true
			_vehicles[1].is_public_local = true
			_nm.game_connected_flag = true
			for i in 2:
				_vehicles[i].set("_net_input_timer", 1.0 / 30.0 * 0.9)
				_vehicles[i].set("_net_state_timer", 1.0 / 15.0 * 0.9)
				_prev_in[i] = 1.0 / 30.0 * 0.9
				_prev_st[i] = 1.0 / 15.0 * 0.9
			_drops_in = 0
			_drops_st = 0
			_drops_in2 = 0
			_drops_st2 = 0
			_phase = 3
			_step = 0
		3:
			if _step >= 36:
				# 帧级统计在 match 下方统一累加，exit 到这里时计算完成
				_check(_drops_in > 0, "[固定翼] 输入上报 30Hz 分支被驱动 (清零 %d 次)" % _drops_in)
				_check(_drops_st > 0, "[固定翼] 状态上报 15Hz 分支被驱动 (清零 %d 次)" % _drops_st)
				_check(_drops_in2 > 0, "[直升机] 输入上报 30Hz 分支被驱动 (清零 %d 次)" % _drops_in2)
				_check(_drops_st2 > 0, "[直升机] 状态上报 15Hz 分支被驱动 (清零 %d 次)" % _drops_st2)
				# 清门控，进入地面转向校验
				_nm.game_connected_flag = false
				for i in 2:
					_vehicles[i].is_public_local = false
					# 两车分开放置（同 collision_layer=2 的碰撞体会互相顶开，
					# 同坐标叠加会污染固定翼落地/转向验证）
					_vehicles[i].global_position = Vector3(i * 100.0, 0.2, 0)
					_vehicles[i].velocity = Vector3.ZERO
					if "throttle" in _vehicles[i]:
						_vehicles[i].throttle = 0.0
					if "collective" in _vehicles[i]:
						_vehicles[i].collective = 0.0
					_vehicles[i].rotation.y = 0.0
					_vehicles[i].target_yaw = 1.0  # 约 57.3°，45°/s 约需 1.27s
				_max_tilt = 0.0
				_settle = 0
				_phase = 4
				_step = 0
		4:
			# 等落地稳住（飞机/直升机各自落地后静止判定）
			if _step < 60:
				return false
			_phase = 5
			_step = 0
		5:
			# 观察静止转向行为：固定翼应保持机头朝向（飞机原地转头不科学），
			# 直升机保留原地旋回（尾桨转向）；两机都保持水平不抬头
			_settle += 1
			for i in 2:
				var v: Node = _vehicles[i]
				_max_tilt = max(_max_tilt, abs(v.rotation.x), abs(v.rotation.z))
			if _settle >= 240:
				var fw: Node = _vehicles[0]
				_check(abs(wrapf(fw.rotation.y, -PI, PI)) < 0.02,
					"[固定翼] 静止时机头保持朝向不随准星 (y=%.3f)" % fw.rotation.y)
				var hp: Node = _vehicles[1]
				_check(abs(wrapf(hp.rotation.y - hp.target_yaw, -PI, PI)) < 0.02,
					"[直升机] 静止时保留原地旋回收敛到 target_yaw (y=%.3f)" % hp.rotation.y)
				_check(_max_tilt < deg_to_rad(2.0), "转向全程保持水平 (max tilt=%.2f°)" % rad_to_deg(_max_tilt))
				_finish()
	# 帧级观察：phase==3 时统计两个计时器的清零次数
	if _phase == 3:
		for i in 2:
			var v: Node = _vehicles[i]
			var cur_in: float = v.get("_net_input_timer")
			var cur_st: float = v.get("_net_state_timer")
			if cur_in < _prev_in[i] - 0.0001:
				if i == 0:
					_drops_in += 1
				else:
					_drops_in2 += 1
			if cur_st < _prev_st[i] - 0.0001:
				if i == 0:
					_drops_st += 1
				else:
					_drops_st2 += 1
			_prev_in[i] = cur_in
			_prev_st[i] = cur_st
	return false

func _finish() -> void:
	_done = true
	if _nm:
		_nm.game_connected_flag = _old_flag
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)