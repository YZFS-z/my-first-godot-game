extends SceneTree
## 回归校验：起落架系统（固定翼/直升机）+ 固定翼滑跑转向（随速度受限 + 贴地滞回）
## 相位顺序避免状态污染：先在干净地面环境验证滑跑转向，再验证起落架收放/保护。
## 覆盖：
##  1) 初始状态：两机出生即放下（gear_deployed=true, gear_anim≈1）
##  2) 贴地强制放下：低空/着地时 toggle 无效（不会意外收起）
##  3) 固定翼高速滑跑转向：滑跑（throttle 大、速度>3）时机头按 ground_turn_rate 收敛到
##     target_yaw（准星偏航），且不被姿态求解（速度方向重建机头）吃掉；
##     滑跑期间贴地滞回 _ground_state 保持 true（不抖动切回飞行态）
##  4) 固定翼低速滑跑转向受限：低速（airspeed≈5）时转向能力按 (v/ref)^2 衰减，
##     2 秒内不应大角度转向（真实固定翼低速前轮/舵面效能弱，不能原地掉头）
##  5) 空中收起：抬到高空 → 贴地滞回切出（_ground_state=false）→ toggle 收起：
##     gear_deployed=false、动画平滑推进、容器上移缩进机腹
##  6) 空中再放下：动画回落到基准高度
##  7) 回归：固定翼落地静止时（油门≈0 速度≈0）机头保持当前朝向不转头

var _failed := 0
var _step := 0
var _total := 0
var _phase := 0
var _airplane: Node = null
var _helicopter: Node = null
var _ap_data: Dictionary = {}
var _hp_data: Dictionary = {}
var _reset_yaw: float = 0.0
var _air_toggled: bool = false
var _stable_floor: int = 0

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

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeLandingGearTest"
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
	# 两机分开出生，避免碰撞盒重叠互相推挤
	_ap_data = _load_json("res://data/vehicles/plane_a10.json")
	_hp_data = _load_json("res://data/vehicles/heli_ah64.json")
	_airplane = load("res://scenes/airplane.tscn").instantiate()
	_airplane.is_player_controlled = true
	_airplane.is_server_controlled = true
	_airplane.global_position = Vector3(1.0, 2.0, 0)
	root.add_child(_airplane)
	_helicopter = load("res://scenes/helicopter.tscn").instantiate()
	_helicopter.is_player_controlled = true
	_helicopter.is_server_controlled = true
	_helicopter.global_position = Vector3(1500.0, 2.0, 0)
	root.add_child(_helicopter)

func _physics_process(delta: float) -> bool:
	_step += 1
	_total += 1
	if _total > 5000:
		print("FAIL: 测试全局超时 (_phase=%d)" % _phase)
		_finish()
		return false
	match _phase:
		0:
			# 等 _ready 完成（damage_system 就绪）再装载数据（同 main.gd 出生流程）
			if _step < 15:
				return false
			if _airplane.damage_system == null or _helicopter.damage_system == null:
				return false
			_airplane.setup_from_data(_ap_data)
			_helicopter.setup_from_data(_hp_data)
			_airplane.velocity = Vector3.ZERO
			_helicopter.velocity = Vector3.ZERO
			_phase = 1
			_step = 0
		1:
			# 初始状态：等待落地后应保持放下
			if _step >= 45:
				_check(_airplane.gear_deployed, "[固定翼] 初始起落架放下")
				_check(abs(_airplane.gear_anim - 1.0) < 0.02, "[固定翼] 初始动画=放下 (%.2f)" % _airplane.gear_anim)
				_check(_helicopter.gear_deployed, "[直升机] 初始起落架放下")
				# 贴地强制放下：仍在低空/地面附近，toggle 应被拒
				_airplane._toggle_landing_gear()
				_helicopter._toggle_landing_gear()
				_phase = 2
				_step = 0
		2:
			# 贴地 toggle 无效（落地/低空保护）
			if _step >= 10:
				_check(_airplane.gear_deployed, "[固定翼] 贴地 toggle 后仍放下（强制落地保护）")
				_check(_helicopter.gear_deployed, "[直升机] 贴地 toggle 后仍放下（强制落地保护）")
				# ---- 固定翼滑跑转向测试（在干净地面状态下进行）----
				_airplane.throttle = 0.8       # 推油门滑跑（不喂 input_throttle，headless 会被 Input.get_axis 覆盖）
				_airplane.target_yaw = deg_to_rad(120.0)
				_phase = 3
				_step = 0
		3:
			# 滑跑起步：等速度起来后清掉初始姿态误差，将目标设为一个明确的偏航角
			# （本轮转向手感钝化后，地面转向速率已降为 40°/s 且按 (v/ref)^2 衰减；
			# 延长加速窗口让速度真正进入"转向能力全开"的滑跑段，再验证收敛不被姿态求解吃掉）
			if _step >= 140:
				_airplane.rotation.y = 0.0
				_airplane.target_yaw = deg_to_rad(90.0)
				_phase = 4
				_step = 0
		4:
			# 高速滑跑转向收敛检查（速度已上来的滑跑段，转向能力全开）
			if _step >= 320:
				var err_deg: float = rad_to_deg(absf(wrapf(_airplane.rotation.y - _airplane.target_yaw, -PI, PI)))
				_check(err_deg < 8.0, "[固定翼] 滑跑前轮转向收敛到准星偏航 (yaw=%.1f°, 目标=90.0°, err=%.1f°)" % [rad_to_deg(_airplane.rotation.y), err_deg])
				_check(_airplane.is_on_floor(), "[固定翼] 滑跑期间确实贴地 (y=%.2f)" % _airplane.global_position.y)
				_check(_airplane.airspeed > 3.0, "[固定翼] 滑跑期间速度已起来 (v=%.1f)" % _airplane.airspeed)
				_check(_airplane._ground_state, "[固定翼] 滑跑期间贴地滞回保持 (ground_state=true)")
				# ---- 低速转向受限测试准备：低速滑跑（速度≈5 m/s，转向能力大幅衰减）----
				_airplane.throttle = 0.18      # 维持滑跑（>0.1，避免触发静止锁定），但推力弱
				_airplane.airspeed = 5.0
				_airplane.velocity = Vector3(5.0, 0.0, 0.0)
				_airplane.rotation.y = 0.0
				_airplane.target_yaw = deg_to_rad(90.0)   # 与机头差 90°，模拟想要大角度转向
				_phase = 5
				_step = 0
		5:
			# 低速滑跑转向受限：2 秒（约 120 帧）内只允许缓慢转向，不允许大角度掉头
			if _step >= 120:
				var yaw_deg: float = rad_to_deg(wrapf(_airplane.rotation.y, -PI, PI))
				_check(yaw_deg < 45.0, "[固定翼] 低速滑跑转向受限，2s 未大角度掉头 (转了 %.1f°)" % yaw_deg)
				_check(yaw_deg > 1.0, "[固定翼] 低速滑跑仍具备轻微转向能力 (转了 %.1f°)" % yaw_deg)
				_check(_airplane.airspeed < 12.0, "[固定翼] 低速测试期间速度未失控 (v=%.1f)" % _airplane.airspeed)
				# ---- 空中收起测试准备：把两机抬到高处并清零速度 ----
				_airplane.throttle = 0.0
				_airplane.velocity = Vector3.ZERO
				_airplane.global_position = Vector3(1.0, 60.0, 0)
				_helicopter.velocity = Vector3.ZERO
				_helicopter.collective = 0.0
				_helicopter.global_position = Vector3(1500.0, 60.0, 0)
				_phase = 6
				_step = 0
		6:
			# 悬空保持：无玩家操控时载具会自由落体坠地（触发"贴地强制放下"），测试期间维持高空
			if _helicopter.global_position.y < 20.0:
				_helicopter.global_position.y = 60.0
				_helicopter.velocity = Vector3.ZERO
			if _airplane.global_position.y < 20.0:
				_airplane.global_position.y = 60.0
				_airplane.velocity = Vector3.ZERO
			# 空中收起：等待贴地滞回切出（_ground_state=false）后再 toggle，确保收起不被"贴地保护"拒绝
			# （一次性触发：首次满足条件即调用，避免条件错过帧后永不执行）
			if not _air_toggled and _step >= 20 and not _airplane._ground_state:
				_air_toggled = true
				_airplane._toggle_landing_gear()
				_helicopter._toggle_landing_gear()
			if _step >= 170:
				_check(not _airplane._ground_state, "[固定翼] 高空稳定后贴地滞回已切出 (ground_state=false)")
				_check(not _airplane.gear_deployed, "[固定翼] 空中 toggle 后收起")
				_check(_airplane.gear_anim < 0.25, "[固定翼] 收起动画推进到收起 (%.2f)" % _airplane.gear_anim)
				if _airplane.gear_container:
					var lift_y: float = _airplane.gear_container.position.y
					_check(lift_y > _airplane._gear_base_y + 0.3, "[固定翼] 收起后容器上移缩进 (y=%.2f, base=%.2f)" % [lift_y, _airplane._gear_base_y])
				_check(not _helicopter.gear_deployed, "[直升机] 空中 toggle 后收起")
				_check(_helicopter.gear_anim < 0.25, "[直升机] 收起动画推进到收起 (%.2f)" % _helicopter.gear_anim)
				# 再次放下（空中也允许）
				_airplane._toggle_landing_gear()
				_helicopter._toggle_landing_gear()
				_phase = 7
				_step = 0
		7:
			if _step >= 110:
				_check(_airplane.gear_deployed and _airplane.gear_anim > 0.95, "[固定翼] 再次放下动画回落 (%.2f)" % _airplane.gear_anim)
				_check(_helicopter.gear_deployed and _helicopter.gear_anim > 0.95, "[直升机] 再次放下动画回落 (%.2f)" % _helicopter.gear_anim)
				# ---- 回归准备：落地静止 ----
				_airplane.throttle = 0.0
				_airplane.velocity = Vector3.ZERO
				_airplane.global_position = Vector3(500.0, 2.0, -300.0)  # 新地点，远离旧轨迹
				_phase = 8
				_step = 0
		8:
			# 等待真正稳定贴地：落地会经历"嵌入→弹出→弹跳衰减"（碰撞体底部在
			# origin 下方约 5m，y=2.0 起点会先被推出再反复接触），若在 vy 仍大、
			# onFloor 抖动时直接设姿态，spd 恰过 3.0 会触发空中姿态求解一步 slerp
			# 把机头掰向下降速度方向（yaw 30°→-90°伪失败）。等 is_on_floor 与贴地
			# 滞回连续 30 帧（0.5s）成立、静止锁定接管后，再重置姿态才测得到
			# "静止保持朝向"本意。
			if _step >= 30 and _airplane.is_on_floor() and _airplane._ground_state:
				_stable_floor += 1
				if _stable_floor >= 30:
					# 全量重置姿态（避免单分量 euler 耦合），设一个明确的静止朝向
					_airplane.global_transform.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(30.0), 0.0))
					_airplane.rotation.y = deg_to_rad(30.0)
					_airplane.velocity = Vector3(0.5, 0.0, 0.0)
					_airplane.target_yaw = deg_to_rad(-120.0)
					_reset_yaw = _airplane.rotation.y
					_phase = 9
					_step = 0
		9:
			if _step >= 50:
				var yaw_deg: float = rad_to_deg(wrapf(_airplane.rotation.y, -PI, PI))
				_check(absf(yaw_deg - 30.0) < 5.0, "[固定翼] 静止时机头保持当前朝向 (yaw=%.1f°, 初始=%.1f°)" % [yaw_deg, rad_to_deg(_reset_yaw)])
				_check(_airplane.airspeed < 2.0, "[固定翼] 静止期间速度被锁定 (v=%.2f)" % _airplane.airspeed)
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