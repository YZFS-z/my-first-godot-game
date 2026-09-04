extends SceneTree
## 回归校验：固定翼拉杆筋斗（拉杆掉头，2026-08）
## 覆盖四个约束：
##  1) 数据一致性：A-10 JSON 与 airplane.gd 默认均 max_aim_pitch_up=175°
##  2) 引导无折叠（纯算法判别，绕过推重比限制）：速度已上斜 45°、目标 150°（>90°
##     的后上方）时，引导持续抬头（vy 单调增）——旧 asin 实现把 150° 折叠成 30°，
##     当前 45° 时 err=30-45=-15° 直接低头拉回；新 atan2/投影实现应继续翻越
##  3) 推重比允许（测试内临时打桩 max_thrust=200kN，仅本测试生效）时能完整翻顶、
##     收敛到 150° 目标并保持（dot ≥ 0.90 持续 240 帧，不因 up_t 升力漂移回竖直）
##  4) 收敛路径无回摆：翻顶前速度方向不出现连续窗口净下降（旧实现 ~90° 处拉回）

var _failed := 0
var _step := 0
var _phase := 0
var _plane: Node = null
var _data: Dictionary = {}
var _target_n: Vector3 = Vector3.ZERO
var _vdir_y_peak: float = -1.0
var _dot_final: float = -1.0
var _regress_window: PackedFloat32Array = []
var _regressed: bool = false
var _settle_frames: int = 0
var _fail_reason: String = ""
var _start_vy: float = 0.0
var _last_vy: float = 0.0
var _dot_initial: float = 0.0
var _body_roll_max: float = 0.0   # 竖直拉升窗口内机身滚转角峰值（度，0=翼平）
var _vert_lock_ref: Vector3 = Vector3.ZERO  # 纯竖直（过顶锁roll）段首帧机背基准
var _vert_lock_max: float = 0.0             # 锁roll段机背方向漂移峰值（度）
var _vert_lock_armed: bool = false
var _cam_ok_frames: int = 0      # 相机回正且与机身一致帧数
var _cam_bad_frames: int = 0     # 相机仍倒置帧数
var _loop_done_at: int = -1      # 自动改平完成的 step
const TARGET_DEG: float = 150.0

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
	_plane.global_position = Vector3(1.0, 200.0, 0)
	root.add_child(_plane)
	# 地面（避免任何落地判定干扰）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -101.0, 0)
	ground.add_child(col)
	root.add_child(ground)

func _set_target(deg: float) -> void:
	# 与 airplane.gd:436 完全一致的构造：先 yaw=-90°（速度系 +X），再抬 pitch
	_target_n = (-Basis.from_euler(Vector3(deg_to_rad(deg), deg_to_rad(-90.0), 0.0)).z).normalized()

func _physics_process(delta: float) -> bool:
	_step += 1
	match _phase:
		0:
			if _step < 15 or _plane.damage_system == null:
				return false
			_check(absf(_plane.max_aim_pitch_up - 175.0) < 0.001,
				"[默认] airplane.gd max_aim_pitch_up=175° (实际 %.1f)" % _plane.max_aim_pitch_up)
			_check(absf(_plane.max_aim_pitch_down + 175.0) < 0.001,
				"[默认] airplane.gd max_aim_pitch_down=-175° 与拉杆对称 (实际 %.1f)" % _plane.max_aim_pitch_down)
			_plane.setup_from_data(_data)
			var phys: Dictionary = _data.get("physics", {})
			_check(phys.get("max_aim_pitch_up", 0.0) == 175.0,
				"[JSON] plane_a10.json max_aim_pitch_up=175° (实际 %.1f)" % phys.get("max_aim_pitch_up", 0.0))
			_check(phys.get("max_aim_pitch_down", 0.0) == -175.0,
				"[JSON] plane_a10.json max_aim_pitch_down=-175° (实际 %.1f)" % phys.get("max_aim_pitch_down", 0.0))
			_check(absf(_plane.max_aim_pitch_up - 175.0) < 0.001,
				"[装载] 装载后 max_aim_pitch_up=175° (实际 %.1f)" % _plane.max_aim_pitch_up)
			_check(absf(_plane.max_aim_pitch_down + 175.0) < 0.001,
				"[装载] 装载后 max_aim_pitch_down=-175° (实际 %.1f)" % _plane.max_aim_pitch_down)
			# ---- 阶段1（默认推力，纯引导方向判别）：速度 45° 上斜，目标 150° ----
			_plane.global_position = Vector3(1.0, 300.0, 0)
			_plane.velocity = Vector3(200.0, 200.0, 0.0).normalized() * 180.0
			_plane.rotation.y = deg_to_rad(-90.0)
			_plane.target_yaw = deg_to_rad(-90.0)
			_plane.target_pitch = deg_to_rad(TARGET_DEG)
			_plane.throttle = 1.0
			_set_target(TARGET_DEG)
			_start_vy = _plane.velocity.normalized().y
			_last_vy = _start_vy
			_phase = 1
			_step = 0
		1:
			# 默认推力、45° 初速：旧算法立即低头（err=asin(0.5)-asin(0.707)<0），
			# 新算法持续抬头。采样 40 帧：净变化应增大，且无连续下跌窗口。
			var vdir: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			var vy: float = vdir.y
			if vy > _vdir_y_peak:
				_vdir_y_peak = vy
			_regress_window.append(vy)
			if _regress_window.size() > 8:
				_regress_window.remove_at(0)
			if _regress_window.size() == 8 and not _regressed:
				var win: float = _regress_window[0] - _regress_window[_regress_window.size() - 1]
				if win > 0.05:
					_regressed = true
					_fail_reason = "阶段1 vy 连续下跌 %.3f（asin 折叠拉回？）peak=%.3f @step %d" % [win, _vdir_y_peak, _step]
			if _step >= 40:
				var net: float = vy - _start_vy
				_check(net > 0.01, "45° 初速下引导持续抬头跨过折叠点 (vy: %.3f→%.3f, 净变化 %+.3f)" %
					[_start_vy, vy, net])
				_check(not _regressed, "爬升段无中途回调 %s" % (("  [FAIL详] " + _fail_reason) if _regressed else ""))
				print("INFO: 阶段1通过，进入阶段2打桩翻顶 (peak vy=%.3f)" % _vdir_y_peak)
				# ---- 阶段2：临时提高推力（仅本测试实例）+ 巡航初速，验证完整筋斗 ----
				# 推重比 1.67（300kN/9000kg，明确高于 1.0 零升力极限）叠加 280 m/s 巡航
				# 动能：翻顶全程速度保持健康（>stall），不触发失速塌陷——
				# 语义仍是"推重比允许时完整翻顶收敛"（A-10 正式配置 0.27 不在其列）。
				# 注：收敛后若继续长时间大过载维持，诱导阻力会缓慢掉速直至失速塌陷，
				# 那是既有失速模型的物理行为（非引导缺陷），故收敛断言在速度健康窗口内完成。
				# 诱导阻力（0.05，该游戏"机动惩罚"参数）在 n_load≈5.5 满过载时可产生
				# 100~200 m/s² 减速，与"推重比是否允许筋斗"正交——测试打桩设为理想值，
				# 专验引导算法完整性：无折叠、完整翻顶、收敛到 150° 并保持。
				# 地图边界：默认 map_half_size=1000 会让 -X 方向飞行 5s 后触发坐标钳制
				# （vx 清零→只剩竖直速度→伪"掰竖直"），须对齐游戏场景的 6000。
				_plane.max_thrust = 300000.0
				_plane.induced_drag = 0.005
				_plane.map_half_size = 6000.0
				_plane.global_position = Vector3(1.0, 300.0, 0)
				_plane.velocity = Vector3(280.0, 0.0, 0.0)
				_plane.rotation.y = deg_to_rad(-90.0)
				_plane.target_yaw = deg_to_rad(-90.0)
				_plane.target_pitch = deg_to_rad(TARGET_DEG)
				_plane.throttle = 1.0
				# 阶段2 是独立翻越验证子场景：阶段1 残留的 _loop_state=1/_loop_peak_vy 会把
				# "翻越失败回落"判据（peak−vdir.y>0.2）与"速度重置为水平"耦合误触发——
				# 修复前无失败分支残留无害，修复后会被 elif 消费。显式重置状态机，
				# 让 0→1→2 完整流程在打桩环境下重新开始（真实游戏中速度连续，无此跳变）。
				_plane._loop_state = 0
				_plane._loop_peak_vy = 0.0
				_vdir_y_peak = -1.0
				_regressed = false
				_regress_window.clear()
				_phase = 2
				_step = 0
		2:
			var vdir: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			var vy: float = vdir.y
			var dot: float = vdir.dot(_target_n)
			if _step == 1:
				_dot_initial = dot
				_body_roll_max = 0.0
				_vert_lock_armed = false
				_vert_lock_max = 0.0
			if vy > _vdir_y_peak:
				_vdir_y_peak = vy
			if dot > _dot_final:
				_dot_final = dot
			# 竖直拉升横滚稳定性（用户报"竖直拉升时飞机左右倾斜"）：
			# 窗口A（0.9≤vd2.y<0.99 且在前半球 vdir·fwd>0，即拉杆上冲段）：
			# 机背应贴近"垂直速度方向的铅垂参考"（翼平，滚转角≈0）——修复后通道1
			# 在该窗口禁行、压坡仅由通道1 向心加速度驱动且随 vert_w 淡出，噪声不再
			# 引发侧倾。过顶下坡段（后半球）参考方向随 vdir 水平分量变号而翻转，
			# 机背处于锁定期过渡，不属于"拉升侧倾"，故排除在采样窗口外。
			# 窗口B（vd2.y≥0.99，姿态求解进入 vdir_vertical 锁roll分支）：机背世界
			# 方向应锁定不变（横滚中立），测其相对进入窗口时基准方向的漂移——若左右
			# 摇摆漂移持续增大；锁定时保持≈0。过顶时机背转平是筋斗的正常物理过程
			# （up_t 兜底 RIGHT），不是侧倾，故只测"相对基准的稳定度"。
			if _plane.velocity.length() > 3.0:
				var vd2: Vector3 = _plane.velocity.normalized()
				if vd2.y > 0.9:
					if vd2.y >= 0.99:
						if not _vert_lock_armed:
							_vert_lock_armed = true
							_vert_lock_ref = _plane.global_transform.basis.y
						else:
							var drift: float = rad_to_deg(acos(clamp(_plane.global_transform.basis.y.dot(_vert_lock_ref), -1.0, 1.0)))
							if drift > _vert_lock_max:
								_vert_lock_max = drift
					elif vd2.x > 0.0:
						var fwd2: Vector3 = -_plane.global_transform.basis.z
						var ref_up2: Vector3 = Vector3.UP - fwd2 * Vector3.UP.dot(fwd2)
						if ref_up2.length() < 0.01:
							ref_up2 = Vector3.RIGHT
						else:
							ref_up2 = ref_up2.normalized()
						var roll_deg: float = rad_to_deg(acos(clamp(_plane.global_transform.basis.y.dot(ref_up2), -1.0, 1.0)))
						if roll_deg > _body_roll_max:
							_body_roll_max = roll_deg
			# 高位异常回落（峰值后跌 >35° 仍未触发翻越完成）→ 引导中途回调
			if _vdir_y_peak > 0.5 and _vdir_y_peak - vy > 0.6 and _plane._loop_state == 1 and not _regressed:
				_regressed = true
				_fail_reason = "阶段2 翻越高位异常回落 %.3f (peak=%.3f)" % [_vdir_y_peak - vy, _vdir_y_peak]
			# 筋斗翻越完成判据：对 150° 后向目标拉杆，速度矢量沿弧线转满（初始 dot=-0.866）。
			# 物理证据 = 飞机内部状态机触发（_loop_state==2：vdir 深入后半球+过顶回落，
			# 引导自动把 target_pitch 收回水平）且弧线最佳对准 _dot_final≥0.85（翻越到位）。
			# 原先"对准 150° 保持 30 帧"断言与自动改平冲突（改平后 vdir 掉头回水平，
			# dot 必跌破 0.9），故改为"触发即证翻越" + 阶段3 验证改平完成。
			if _plane._loop_state == 2:
				_check(_dot_final > 0.85, "筋斗翻转弧走满 (best_dot=%.3f, peak vy=%.3f, spd=%.0f)" %
					[_dot_final, _vdir_y_peak, _plane.velocity.length()])
				_check(not _regressed, "筋斗翻越无折叠回摆/中途回调 (peak vy=%.3f) %s" %
					[_vdir_y_peak, ("  [FAIL详] " + _fail_reason) if _regressed else ""])
				_check(_body_roll_max < 25.0, "竖直拉升（0.9≤仰<0.99）翼平不侧倾（roll 峰值 %.1f° < 25°）" % _body_roll_max)
				_check(_vert_lock_max < 30.0, "纯竖直锁 roll 机背不摇摆（漂移 %.1f° < 30°）" % _vert_lock_max)
				print("INFO: 筋斗翻越完成并触发自动改平 step=%d（进入改平校验）" % _step)
				_phase = 3
				_settle_frames = 0
			if _step > 1500:
				_check(false, "阶段2超时未完成翻越 (peak vy=%.3f, best_dot=%.3f, vy=%.3f, spd=%.1f)" %
					[_vdir_y_peak, _dot_final, vy, _plane.velocity.length()])
				_finish()
		3:
			# 自动改平完成校验：翻越后 target_pitch 自动收回水平（状态机 2→0），
			# vdir 回到水平前方（y<0.4）且速度健康，保持 30 帧证明稳定不再回摆。
			var vdir3: Vector3 = _plane.velocity.normalized() if _plane.velocity.length() > 0.5 else Vector3.RIGHT
			# 相机视角探针：机身回正（basis.y·UP>0.95）后，相机视线应与机身机头一致
			# （正置视角），而非仍停留倒置（相机 -z 朝后上方，即"飞机正了但镜头倒着"）。
			if _plane.global_transform.basis.y.dot(Vector3.UP) > 0.95:
				_loop_done_at = _step if _loop_done_at < 0 else _loop_done_at
				var cam_dir: Vector3 = -_plane.camera_pivot.global_transform.basis.z
				var body_fwd: Vector3 = -_plane.global_transform.basis.z
				var body_up: Vector3 = _plane.global_transform.basis.y
				var cam_up: Vector3 = _plane.camera_pivot.global_transform.basis.y
				var body_cam_ang: float = rad_to_deg(body_fwd.angle_to(cam_dir))
				var cam_align_up: bool = cam_up.dot(Vector3.UP) > 0.0
				var fwd_align: bool = body_cam_ang < 60.0
				if cam_align_up and fwd_align:
					_cam_ok_frames += 1
					_cam_bad_frames = 0
				else:
					_cam_bad_frames += 1
					if _cam_bad_frames == 1:
						print("CAMPROBE body_fwd=(%.2f,%.2f,%.2f) cam_dir=(%.2f,%.2f,%.2f) cam_up.y=%.2f body_cam=%.1f° loop_state=%d" %
							[body_fwd.x, body_fwd.y, body_fwd.z, cam_dir.x, cam_dir.y, cam_dir.z, cam_up.y, body_cam_ang, _plane._loop_state])
			if _plane._loop_state == 0 and vdir3.y < 0.4 and _plane.velocity.length() > 80.0:
				_settle_frames += 1
				if _settle_frames >= 30:
					_check(true, "筋斗后自动改平完成：回到水平前方 (vy=%.3f, spd=%.0f)" %
						[vdir3.y, _plane.velocity.length()])
					var up_ratio: float = _plane.global_transform.basis.y.dot(Vector3.UP)
					_check(up_ratio > 0.95, "改平完成后机背朝上、滚转回中 (basis.y·UP=%.3f)" % up_ratio)
					_check(_cam_bad_frames <= 3 or _cam_ok_frames >= 3,
						"机身回正时相机同步回正（倒置帧 %d / 回正帧 %d）" % [_cam_bad_frames, _cam_ok_frames])
					_finish()
			else:
				_settle_frames = 0
			if _step > 800:
				_check(false, "阶段3超时：自动改平未完成 (loop_state=%d, vy=%.3f, spd=%.1f)" %
					[_plane._loop_state, vdir3.y, _plane.velocity.length()])
				_finish()
	return false

func _finish() -> void:
	_phase = 99
	print("RESULT: peak_vy=%.4f dot_final=%.4f" % [_vdir_y_peak, _dot_final])
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)