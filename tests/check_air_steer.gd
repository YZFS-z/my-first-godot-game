extends SceneTree
## 回归校验：固定翼转向手感（2026-08 手感钝化调整）
## 覆盖五个约束：
##  1) 数据一致性：A-10 装载后 guidance_gain=1.3、aim_sensitivity=0.55（JSON 覆盖与脚本默认一致，
##     压低鼠标灵敏度 + 温和引导，防止"鼠标稍动即大幅偏转"）
##  2) 滑跑转向速率上限：单帧 yaw_step ≤ ground_turn_rate(20°/s)×(v/ref)^2，
##     且受 ground_steer_gain 软收敛 + ground_steer_max_deg(30°) 指令限幅——防止"太灵敏、转向角度过大"回潮
##  3) 空中小幅转向最小响应：yaw_err≈2°（死区外）时水平引导速率 ≥ steer_min_rate(0.05 rad/s)
##  4) 死区静默：误差进入死区（<0.5°）后引导停止（无持续转向）
##  5) 压坡平滑：空中转向时机翼倾斜角（bank_cur）单帧变化有界，不突变（消除感官瞬移）

var _failed := 0
var _step := 0
var _phase := 0
var _plane: Node = null
var _data: Dictionary = {}
var _last_yaw: float = 0.0
var _max_yaw_step: float = 0.0
var _prev_vdir: Vector3 = Vector3.RIGHT
var _max_min_rate: float = 0.0
var _deadzone_rate_max: float = 0.0
var _last_bank: float = 0.0
var _max_bank_step_deg: float = 0.0
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
	_plane.global_position = Vector3(1.0, 2.0, 0)
	root.add_child(_plane)
	# 地面（滑跑/落地判定需要）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _vdir_h() -> Vector3:
	return Vector3(_plane.velocity.x, 0.0, _plane.velocity.z).normalized()

func _physics_process(delta: float) -> bool:
	_step += 1
	match _phase:
		0:
			if _step < 15 or _plane.damage_system == null:
				return false
			_plane.setup_from_data(_data)
			var phys: Dictionary = _data.get("physics", {})
			_check(phys.get("guidance_gain", 0.0) == 1.3, "A-10 JSON guidance_gain=1.3 (实际 %.1f)" % phys.get("guidance_gain", 0.0))
			_check(absf(_plane.guidance_gain - 1.3) < 0.001, "装载后 guidance_gain=1.3 (实际 %.2f)" % _plane.guidance_gain)
			_check(absf(_plane.aim_sensitivity - 0.55) < 0.001, "装载后 aim_sensitivity=0.55 (实际 %.2f)" % _plane.aim_sensitivity)
			_check(absf(_plane.ground_turn_rate - 20.0) < 0.001, "滑跑转向上限 20°/s (实际 %.1f)" % _plane.ground_turn_rate)
			_check(absf(_plane.ground_steer_gain - 0.4) < 0.001, "滑跑软收敛增益 0.4 (实际 %.2f)" % _plane.ground_steer_gain)
			_check(absf(_plane.ground_steer_max_deg - 30.0) < 0.001, "滑跑指令限幅 30° (实际 %.1f)" % _plane.ground_steer_max_deg)
			_check(absf(_plane.bank_smooth_rate - 4.0) < 0.001, "压坡平滑速率 4.0 (实际 %.2f)" % _plane.bank_smooth_rate)
			_check(phys.get("ground_steer_max_deg", 0.0) == 30.0, "A-10 JSON ground_steer_max_deg=30 (实际 %.1f)" % phys.get("ground_steer_max_deg", 0.0))
			_check(phys.get("bank_smooth_rate", 0.0) == 4.0, "A-10 JSON bank_smooth_rate=4.0 (实际 %.1f)" % phys.get("bank_smooth_rate", 0.0))
			_check(absf(_plane.steer_min_rate - 0.05) < 0.001, "空中最小引导速率 0.05 rad/s (实际 %.3f)" % _plane.steer_min_rate)
			# ---- 滑跑阶段：低速滑跑，目标偏 60°，稳定落地后逐帧采样 yaw_step ----
			_plane.throttle = 0.6
			_plane.velocity = Vector3(8.0, 0.0, 0.0)
			_plane.rotation.y = 0.0
			_plane.target_yaw = deg_to_rad(60.0)
			_phase = 1
			_step = 0
		1:
			# 以"落地事件"为基准：落地前机头被空中姿态重建（≈速度方向，可能远离 0°），
			# 固定帧重置会与落地时机错位 → 第一采样帧 dy 假阳性。改为落地稳定后再重置。
			if not _plane.is_on_floor():
				_armed = false
				return false
			if not _armed:
				_armed = true
				_ground_frames = 0
				return false
			_ground_frames += 1
			if _ground_frames < 5:
				return false
			if _ground_frames == 5:
				_plane.rotation.y = 0.0
				_last_yaw = _plane.rotation.y
				_max_yaw_step = 0.0
				return false
			var dy: float = absf(wrapf(_plane.rotation.y - _last_yaw, -PI, PI))
			if dy > _max_yaw_step:
				_max_yaw_step = dy
			_last_yaw = _plane.rotation.y
			if _ground_frames >= 5 + 120:
				var eff: float = clamp(_plane.airspeed / _plane.ground_turn_speed_ref, 0.0, 1.0)
				var upper: float = deg_to_rad(_plane.ground_turn_rate) * eff * eff * 1.05 + 0.0002
				_check(_max_yaw_step <= upper, "滑跑单帧转向 ≤ 20°/s×(v/ref)^2 上限 (max=%.4f°, upper=%.4f°, v=%.1f m/s)" % [rad_to_deg(_max_yaw_step), rad_to_deg(upper), _plane.airspeed])
				_check(rad_to_deg(_plane.rotation.y) > 1.0, "滑跑已在转向 (yaw=%.1f°)" % rad_to_deg(_plane.rotation.y))
				# ---- 空中阶段：抬空，稳定 30 帧后再测 2° 误差响应 ----
				# 注意：Godot 前向为 -Z，yaw=0 指向前向；vdir=RIGHT(80,0,0) 对应 yaw=-90°
				_plane.global_position = Vector3(1.0, 150.0, 0)
				_plane.velocity = Vector3(80.0, 0.0, 0.0)
				_plane.rotation.y = deg_to_rad(-90.0)
				_plane.target_yaw = deg_to_rad(-90.0)
				_plane.target_pitch = 0.0
				_plane.throttle = 0.5
				_phase = 2
				_step = 0
				_prev_vdir = _vdir_h()
		2:
			# 稳定期：等贴地滞回解除（_ground_state=false）且 vdir 稳定
			if _step < 30 or _plane._ground_state:
				_prev_vdir = _vdir_h()
				return false
			# 注入 2° 误差，测 20 帧水平引导速率；同时采样机翼压坡（bank_cur）单帧变化验证平滑
			if _step == 30:
				_plane.target_yaw = deg_to_rad(-90.0 + 2.0)
				_prev_vdir = _vdir_h()
				_max_min_rate = 0.0
				_last_bank = rad_to_deg(_plane.bank_cur)
				_max_bank_step_deg = 0.0
				return false
			if _step < 30 + 20:
				var vh: Vector3 = _vdir_h()
				if vh.length() > 0.5 and _prev_vdir.length() > 0.5:
					var rate: float = vh.angle_to(_prev_vdir) / delta
					_max_min_rate = max(_max_min_rate, rate)
				_prev_vdir = vh
				var bank_now: float = rad_to_deg(_plane.bank_cur)
				_max_bank_step_deg = max(_max_bank_step_deg, absf(bank_now - _last_bank))
				_last_bank = bank_now
				return false
			_check(_max_min_rate >= _plane.steer_min_rate * 0.85, "空中 2° 误差最小响应 ≥0.05 rad/s (实测 %.3f rad/s)" % _max_min_rate)
			_check(_max_bank_step_deg <= 4.5, "空中压坡单帧变化有界 ≤4.5° (实测 %.2f°/帧)" % _max_bank_step_deg)
			_check(rad_to_deg(absf(_plane.bank_cur)) > 3.0, "压坡已平滑建立 (bank=%+.1f°)" % rad_to_deg(_plane.bank_cur))
			# ---- 死区阶段：目标对准当前航向（RIGHT，yaw=-90°），等收敛后测引导是否静默 ----
			_plane.target_yaw = deg_to_rad(-90.0)
			_prev_vdir = _vdir_h()
			_deadzone_rate_max = 0.0
			_phase = 3
			_step = 0
		3:
			# 前 40 帧等收敛（对准 + 姿态稳定），后 30 帧采样转向速率
			if _step < 40:
				_prev_vdir = _vdir_h()
				return false
			var vh: Vector3 = _vdir_h()
			if vh.length() > 0.5 and _prev_vdir.length() > 0.5:
				var rate: float = vh.angle_to(_prev_vdir) / delta
				_deadzone_rate_max = max(_deadzone_rate_max, rate)
			_prev_vdir = vh
			if _step >= 40 + 30:
				_check(_deadzone_rate_max < 0.04, "误差进入死区后引导静默 (max=%.4f rad/s)" % _deadzone_rate_max)
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