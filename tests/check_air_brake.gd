extends SceneTree
## 回归校验：固定翼滑跑刹车（2026-08 新增）
## 覆盖约束：
##  1) 数据一致性：A-10 装载后 brake_decel=7.0（JSON 覆盖与脚本默认一致）
##  2) 滑跑不按 Ctrl：仅滚动摩擦减速（30 帧 ≈ 降 0.3 m/s，throttle=0）
##  3) 滑跑按住 Ctrl（input_throttle=-1）：摩擦 + brake_decel 叠加（30 帧 ≈ 降 3.8 m/s）
##  4) 持续按住 Ctrl 可刹停并进入静止锁定（速度收敛到 ~0）
##  5) 空中按 Ctrl 只减油门（不触发地面刹车物理）

var _failed := 0
var _step := 0
var _phase := 0
var _plane: Node = null
var _data: Dictionary = {}
var _ground_frames: int = 0
var _armed: bool = false

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
	_data = _load_json("res://data/vehicles/plane_a10.json")
	_plane = load("res://scenes/airplane.tscn").instantiate()
	_plane.is_player_controlled = true
	_plane.is_server_controlled = false
	_plane.team = 1
	root.add_child(_plane)
	_plane.global_position = Vector3(1.0, 2.0, 0)
	# 地面（滑跑/落地判定需要）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _h_speed() -> float:
	return Vector3(_plane.velocity.x, 0.0, _plane.velocity.z).length()

func _physics_process(delta: float) -> bool:
	_step += 1
	match _phase:
		0:
			# 等待实例化完成 + 落地，然后装载数据
			if _step < 15 or _plane.damage_system == null:
				return false
			_plane.setup_from_data(_data)
			var phys: Dictionary = _data.get("physics", {})
			_check(phys.get("brake_decel", 0.0) == 7.0, "A-10 JSON brake_decel=7.0 (实际 %.1f)" % phys.get("brake_decel", 0.0))
			_check(absf(_plane.brake_decel - 7.0) < 0.001, "装载后 brake_decel=7.0 (实际 %.2f)" % _plane.brake_decel)
			_check(absf(_plane.ground_turn_rate - 20.0) < 0.001, "滑跑转向上限 20°/s (实际 %.1f)" % _plane.ground_turn_rate)
			_plane.throttle = 0.0
			_plane.velocity = Vector3(20.0, 0.0, 0.0)
			_plane.rotation.y = deg_to_rad(-90.0)   # 机头指向 +X（与速度同向，减少对齐扰动）
			_plane.target_yaw = deg_to_rad(-90.0)
			_plane.input_throttle = 0.0
			_phase = 1
			_step = 0
		1:
			# 等落地稳定后重置速度，测 30 帧"无刹车"对照（throttle=0，纯滚动摩擦）
			if not _plane.is_on_floor():
				_armed = false
				return false
			if not _armed:
				_armed = true
				_ground_frames = 0
				return false
			_ground_frames += 1
			if _ground_frames <= 5:
				return false
			if _ground_frames == 6:
				_plane.velocity = Vector3(20.0, 0.0, 0.0)
				print("DBG P1 GF=6: vel=%s on_floor=%s" % [str(_plane.velocity), _plane.is_on_floor()])
				return false
			if _ground_frames == 7:
				print("DBG P1 GF=7: vel=%s on_floor=%s h_spd=%.3f" % [str(_plane.velocity), _plane.is_on_floor(), _h_speed()])
			if _ground_frames <= 6 + 30:
				return false
			var v_no_brake: float = _h_speed()
			print("DBG P1 RESULT: h_spd=%.3f gf=%d" % [v_no_brake, _ground_frames])
			_check(absf(v_no_brake - 19.7) < 0.4, "滑跑不按Ctrl仅摩擦减速 30帧≈19.7 m/s (实测 %.2f)" % v_no_brake)
			# 进入刹车阶段：同样 20 m/s 起步，模拟玩家按住 Ctrl（throttle_down）
			_plane.velocity = Vector3(20.0, 0.0, 0.0)
			Input.action_press("throttle_down")
			_ground_frames = 0
			_armed = true
			_phase = 2
		2:
			_ground_frames += 1
			if _ground_frames <= 30:
				return false
			var v_brake: float = _h_speed()
			# 摩擦 0.6 + 刹车 7.0 → 30 帧(0.5s) 降 3.8
			_check(absf(v_brake - 16.2) < 0.8, "滑跑按Ctrl摩擦+刹车 30帧≈16.2 m/s (实测 %.2f)" % v_brake)
			_phase = 3
		3:
			# 持续按住 Ctrl：从 ~16 m/s 刹车约 2.1s 归零，随后静止锁定收敛
			if _step < 300:
				return false
			_check(_h_speed() < 0.5, "持续刹车可刹停并锁定 (v=%.3f m/s)" % _h_speed())
			Input.action_release("throttle_down")
			_phase = 4
		4:
			# 空中对照：Ctrl 键只减油门，不触发地面刹车物理
			_plane.global_position = Vector3(0, 150.0, 0)
			_plane.velocity = Vector3(60.0, 0.0, 0.0)
			_plane.rotation.y = deg_to_rad(-90.0)
			_plane.target_yaw = deg_to_rad(-90.0)
			_plane.throttle = 0.5
			Input.action_press("throttle_down")
			_phase = 5
			_step = 0
		5:
			if _step < 60:
				return false
			_check(_plane.throttle < 0.5, "空中按Ctrl只减油门 (throttle=%.2f)" % _plane.throttle)
			Input.action_release("throttle_down")
			print("RESULT: failed=%d" % _failed)
			quit()
			return true
	return false