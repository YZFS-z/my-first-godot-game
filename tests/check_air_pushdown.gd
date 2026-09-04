extends SceneTree
## 回归校验：固定翼推杆外筋斗（推杆翻过头底"往来的方向飞"，2026-08-23）
## 覆盖五个约束：
##  1) 数据一致性：A-10 JSON 与 airplane.gd 默认均 max_aim_pitch_down=-175°（与拉杆 +175° 对称）
##  2) 引导无折叠（默认推力纯算法判别）：45° 下滑、目标 -150°（<-90° 的后下方）时引导持续低头
##     （旧 asin 实现把 -150° 折叠成 -30°，当前 -45° 时 err=+15° 直接抬头拉回；投影实现应继续翻越）
##  3) 推重比允许时的极限深度（打桩 300kN、平飞 280m/s 推 -175°）：外筋斗完整 state0→1→2→0、
##     自动改平收尾、全程不撞地。注：-175° 目标接近水平正后方，最短弧不必经过正下方，
##     故不作"nadir<-0.9"断言（那是"垂直俯冲后继续推"的专属判据，见阶段3）
##  4) 【用户核心场景，默认推力】垂直俯冲蓄速 → 继续推杆 -150°：vdir 从垂直向下继续下压翻越
##     后半球（nadir<-0.9、vdir·fwd<0 往来的方向），外筋斗完成自动改平，全程不撞地、速度健康。
##     推杆外筋斗有重力帮忙，默认推重比 0.27 即可达成——这正是与拉杆（需打桩）的本质区别
##  5) 自动改平时相机同步回正：机身回正且相机 slerp 收敛后，ok 帧占绝对多数（防"飞机正了镜头倒着"）

var _failed := 0
var _step := 0
var _phase := 0
var _plane: Node = null
var _data: Dictionary = {}
var _target_n: Vector3 = Vector3.ZERO
var _start_vy: float = 0.0
var _regress_window: PackedFloat32Array = []
var _regressed: bool = false
var _fail_reason: String = ""
var _nadir_vy: float = 0.0
var _min_spd: float = 1e9
var _min_alt: float = 1e9
var _state1_at: int = -1
var _state2_at: int = -1
var _state0_at: int = -1
var _cam_ok_frames: int = 0
var _cam_bad_frames: int = 0
var _dive_ready: bool = false
const TARGET_DEG: float = -150.0
const DEEP_DEG: float = -175.0

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
	_plane.global_position = Vector3(1.0, 500.0, 0)
	root.add_child(_plane)
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -101.0, 0)
	ground.add_child(col)
	root.add_child(ground)

func _set_target(deg: float) -> void:
	# 与 airplane.gd 引导同构；check_air_loop.gd:70 已验证该构造（150° 收敛）
	_target_n = (-Basis.from_euler(Vector3(deg_to_rad(deg), deg_to_rad(-90.0), 0.0)).z).normalized()

func _reset_scene_state() -> void:
	# 显式重置推杆状态机（与拉杆测试重置 _loop_state 同口径，见 check_air_loop.gd:145-150）
	_plane._push_state = 0
	_plane._push_nadir_vy = 0.0
	_nadir_vy = 0.0
	_min_spd = 1e9
	_min_alt = 1e9
	_state1_at = -1
	_state2_at = -1
	_state0_at = -1
	_cam_ok_frames = 0
	_cam_bad_frames = 0
	_regressed = false
	_dive_ready = false
	_step = 0

func _setup_flight(target_deg: float, speed: float, thrust: float, i_drag: float, alt: float) -> void:
	_plane.global_position = Vector3(1.0, alt, 0)
	_plane.velocity = Vector3(speed, 0.0, 0.0)
	_plane.rotation.y = deg_to_rad(-90.0)
	_plane.target_yaw = deg_to_rad(-90.0)
	_plane.target_pitch = deg_to_rad(target_deg)
	_plane.auto_center_enabled = false  # 测试直接设 target_pitch，禁用自动回正
	_plane.throttle = 1.0
	_plane.max_thrust = thrust
	_plane.induced_drag = i_drag
	_plane.map_half_size = 6000.0
	_set_target(target_deg)
	_reset_scene_state()

func _sampler() -> Dictionary:
	# 相机采样：state0（自动改平完成）后 100~160 帧窗口，此时 slerp 已基本收敛，
	# ok 帧应占绝对多数；拉杆测试同款几何探针（body_fwd vs cam_dir、cam_up 朝上）
	var cam_dir: Vector3 = -_plane.camera_pivot.global_transform.basis.z
	var body_fwd: Vector3 = -_plane.global_transform.basis.z
	var cam_up: Vector3 = _plane.camera_pivot.global_transform.basis.y
	var bca: float = rad_to_deg(body_fwd.angle_to(cam_dir))
	return {"ok": cam_up.dot(Vector3.UP) > 0.0 and bca < 60.0, "bca": bca}

func _physics_process(delta: float) -> bool:
	_step += 1
	match _phase:
		0:
			if _step < 15 or _plane.damage_system == null:
				return false
			_check(absf(_plane.max_aim_pitch_down + 175.0) < 0.001,
				"[默认] airplane.gd max_aim_pitch_down=-175° (实际 %.1f)" % _plane.max_aim_pitch_down)
			_plane.setup_from_data(_data)
			var phys: Dictionary = _data.get("physics", {})
			_check(phys.get("max_aim_pitch_down", 0.0) == -175.0,
				"[JSON] plane_a10.json max_aim_pitch_down=-175° (实际 %.1f)" % phys.get("max_aim_pitch_down", 0.0))
			_check(absf(_plane.max_aim_pitch_down + 175.0) < 0.001,
				"[装载] 装载后 max_aim_pitch_down=-175° (实际 %.1f)" % _plane.max_aim_pitch_down)
			# ---- 阶段1（默认推力，纯引导方向判别）：45° 下滑、目标 -150° ----
			_plane.global_position = Vector3(1.0, 3000.0, 0)
			_plane.velocity = Vector3(200.0, -200.0, 0.0).normalized() * 180.0
			_plane.rotation.y = deg_to_rad(-90.0)
			_plane.target_yaw = deg_to_rad(-90.0)
			_plane.target_pitch = deg_to_rad(TARGET_DEG)
			_plane.throttle = 1.0
			_plane.map_half_size = 6000.0
			_plane.max_thrust = 48000.0
			_plane.induced_drag = 0.05
			_set_target(TARGET_DEG)
			_start_vy = _plane.velocity.normalized().y
			_phase = 1
			_step = 0
		1:
			var vdir: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			var vy: float = vdir.y
			_nadir_vy = min(_nadir_vy, vy)
			_regress_window.append(vy)
			if _regress_window.size() > 8:
				_regress_window.remove_at(0)
			if _regress_window.size() == 8 and not _regressed:
				var win: float = _regress_window[_regress_window.size() - 1] - _regress_window[0]
				if win > 0.05:
					_regressed = true
					_fail_reason = "阶段1 vy 连续回升 %.3f（asin 折叠拉回？）nadir=%.3f @step%d" % [win, _nadir_vy, _step]
			if _step >= 40:
				var net: float = vy - _start_vy
				_check(net < -0.01, "45° 下滑初速下引导持续低头跨过折叠点 (vy: %.3f→%.3f, 净变化 %+.3f)" %
					[_start_vy, vy, net])
				_check(not _regressed, "下压段无中途回调 %s" % (("  [FAIL详] " + _fail_reason) if _regressed else ""))
				print("INFO: 阶段1通过，进入阶段2打桩极限深度外筋斗 (nadir vy=%.3f)" % _nadir_vy)
				_setup_flight(DEEP_DEG, 280.0, 300000.0, 0.005, 3000.0)
				_phase = 2
		2:
			var vdir: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			var spd: float = _plane.velocity.length()
			_nadir_vy = min(_nadir_vy, vdir.y)
			_min_spd = min(_min_spd, spd)
			_min_alt = min(_min_alt, _plane.global_position.y)
			if _plane._push_state == 1 and _state1_at < 0:
				_state1_at = _step
				print("INFO: 推杆状态机触发 state1 @%d (vdir·target=%.3f)" % [_step, vdir.dot(_target_n)])
			if _plane._push_state == 2 and _state2_at < 0:
				_state2_at = _step
				print("INFO: 外筋斗完成触发自动改平 state2 @%d (best dot=%.3f, vy=%.3f, spd=%.0f)" %
					[_step, vdir.dot(_target_n), vdir.y, spd])
			if _plane._push_state == 0 and _state2_at > 0 and _state0_at < 0:
				_state0_at = _step
				print("INFO: 状态机复位 state0 @%d vy=%.3f spd=%.0f" % [_step, vdir.y, spd])
			# 相机采样窗口：state0 后 100~160 帧
			if _state0_at > 0 and _step >= _state0_at + 100 and _step <= _state0_at + 160:
				var s: Dictionary = _sampler()
				if s["ok"]:
					_cam_ok_frames += 1
				else:
					_cam_bad_frames += 1
			if _state0_at > 0 and _step >= _state0_at + 300:
				var up_ratio: float = _plane.global_transform.basis.y.dot(Vector3.UP)
				_check(up_ratio > 0.95, "[-175°] 改平完成后机背朝上、滚转回中 (basis.y·UP=%.3f)" % up_ratio)
				_check(_min_alt > 300.0, "[-175°] 全程不撞地 (min_alt=%.0f)" % _min_alt)
				_check(_nadir_vy < -0.3, "[-175°] 翻转弧有效下压（nadir vy=%.3f，-175° 近水平后向弧不需过顶）" % _nadir_vy)
				_check(_cam_ok_frames >= 40 and _cam_bad_frames <= 20,
					"[-175°] 相机同步回正（ok %d / bad %d，绿色收敛窗口 60 帧）" % [_cam_ok_frames, _cam_bad_frames])
				print("INFO: 阶段2通过，进入阶段3默认推力俯冲掉头（用户核心场景）")
				# ---- 阶段3：垂直俯冲蓄速 → 继续推杆 -150°（默认推力 48kN）----
				_setup_flight(-90.0, 280.0, 48000.0, 0.05, 9000.0)
				_phase = 3
			if _step > 2000:
				_check(false, "阶段2超时未完成外筋斗 (push_state=%d, state2=%d, state0=%d)" %
					[_plane._push_state, _state2_at, _state0_at])
				_finish()
		3:
			var vdir: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			var spd: float = _plane.velocity.length()
			_nadir_vy = min(_nadir_vy, vdir.y)
			_min_spd = min(_min_spd, spd)
			_min_alt = min(_min_alt, _plane.global_position.y)
			if not _dive_ready:
				# 子阶段A：垂直俯冲稳定
				if vdir.y < -0.94:
					_dive_ready = true
					_plane.target_pitch = deg_to_rad(TARGET_DEG)  # 已建立俯冲，继续推杆 -150°
					print("INFO: 垂直俯冲建立 vdir.y=%.3f spd=%.0f @%d，继续推杆至 %d°" %
						[vdir.y, spd, _step, int(TARGET_DEG)])
				elif _step > 2000:
					_check(false, "阶段3 俯冲未建立 (vdir.y=%.3f)" % vdir.y)
					_finish()
				return false
			# 子阶段B：翻转跟踪（镜像阶段2逻辑）
			if _plane._push_state == 2 and _state2_at < 0:
				_state2_at = _step
				var fwd_h: Vector3 = Vector3(-sin(_plane.target_yaw), 0.0, -cos(_plane.target_yaw)).normalized()
				var dot_fwd: float = vdir.dot(fwd_h)
				print("INFO: 默认推力外筋斗完成 state2 @%d (vdir·水平前向=%.3f, nadir=%.3f, spd=%.0f, min_alt=%.0f)" %
					[_step, dot_fwd, _nadir_vy, spd, _min_alt])
				_check(dot_fwd < 0.0, "俯冲后继续推杆翻过底、往来的方向飞 (vdir·水平前向=%.3f < 0)" % dot_fwd)
				_check(_nadir_vy < -0.9, "翻转弧从垂直俯冲继续下压 (nadir vy=%.3f < -0.9)" % _nadir_vy)
				_check(_min_spd > _plane.stall_speed * 0.8, "翻转过程速度健康 (min_spd=%.0f > 失速 %.0f×0.8)" %
					[_min_spd, _plane.stall_speed])
			if _plane._push_state == 0 and _state2_at > 0 and _state0_at < 0:
				_state0_at = _step
				print("INFO: 默认推力自动改平复位 state0 @%d vy=%.3f spd=%.0f" % [_step, vdir.y, spd])
			if _state0_at > 0 and _step >= _state0_at + 100 and _step <= _state0_at + 160:
				var s: Dictionary = _sampler()
				if s["ok"]:
					_cam_ok_frames += 1
				else:
					_cam_bad_frames += 1
			if _state0_at > 0 and _step >= _state0_at + 160:
				_check(_plane.global_transform.basis.y.dot(Vector3.UP) > 0.95,
					"[默认推力] 改平完成、机背朝上 (basis.y·UP=%.3f)" %
					_plane.global_transform.basis.y.dot(Vector3.UP))
				_check(_min_alt > 300.0, "[默认推力] 全程不撞地 (min_alt=%.0f)" % _min_alt)
				_check(_cam_ok_frames >= 40 and _cam_bad_frames <= 20,
					"[默认推力] 相机同步回正（ok %d / bad %d）" % [_cam_ok_frames, _cam_bad_frames])
				_finish()
			elif _state2_at < 0 and _step > 2500:
				_check(false, "阶段3超时：默认推力未触发外筋斗 (push_state=%d, nadir=%.3f, spd=%.1f, min_alt=%.0f)" %
					[_plane._push_state, _nadir_vy, spd, _min_alt])
				_finish()
	return false

func _finish() -> void:
	_phase = 99
	print("RESULT: nadir_vy=%.4f min_spd=%.0f min_alt=%.0f" % [_nadir_vy, _min_spd, _min_alt])
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)