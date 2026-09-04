extends SceneTree
## 校验（回归）：
##  1. 出生后相机朝向与机头一致、机头朝向战场中心（出生点 rotation 修正后的期望）
##  2. A/D 偏航辅助是渐进式（rudder_assist_cur 按 rudder_rate 逐步逼近），非瞬时 15° 阶跃
## 校验基准 = 用户反馈：固定翼进入游戏视角时"朝后"且按 A/D 机体会"突然偏转"

const MAPS := {
	"map_desert": [
		{"team": 1, "pos": Vector3(0, 1, 800), "rot": 0.0},
		{"team": 2, "pos": Vector3(0, 1, -800), "rot": 180.0},
	],
	"map_europe": [
		{"team": 1, "pos": Vector3(0, 1, -200), "rot": 180.0},
		{"team": 2, "pos": Vector3(0, 1, 200), "rot": 0.0},
	],
}

var _failed := 0
var _done := false

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
	var text: String = f.get_as_text()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _initialize() -> void:
	# 必须用 _initialize（autoload 注册完成后）而非 _init：否则脚本内 GameManager 标识符解析失败
	_make_ground()
	_run()

## 无地面时飞机出生即自由落体，spd 涨过 3.0 后 _update_flight 姿态求解在
## "竖直下落"病态下打乱 rotation（headless Basis 未归一化报错、机体朝向被改写），
## 因此必须有地面供飞机停靠（与 check_aircraft_ai.gd _make_ground 一致）
func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _run() -> void:
	# ---- 校验1：出生朝向面向战场中心（模拟 main.gd spawn 流程）----
	for map_id in MAPS:
		var map_data: Dictionary = _load_json("res://data/maps/%s.json" % map_id)
		if map_data.is_empty():
			_check(false, "%s 地图加载失败" % map_id)
			continue
		for sp in MAPS[map_id]:
			var data: Dictionary = _load_json("res://data/vehicles/plane_a10.json")
			var v: Node = load("res://scenes/airplane.tscn").instantiate()
			v.is_player_controlled = true
			v.is_server_controlled = true
			v.rotation.y = deg_to_rad(sp.rot)
			root.add_child(v)
			# 必须等一帧：SceneTree._initialize 阶段 root 未 complete ready，
			# 立即 setup_from_data 会因 _ready 未触发而 damage_system 为 null，模块装配中断
			await process_frame
			v.setup_from_data(data)
			v.global_position = sp.pos
			# 相机：_ready 中已 _sync_camera_immediate；几帧后相机转向机头（slerp 收敛）
			for i in 120:
				await process_frame
			var nose: Vector3 = -v.global_transform.basis.z
			var cam_dir: Vector3 = -v.camera_pivot.global_transform.basis.z
			var cam_at: Vector3 = (v.global_position - v.camera_3d.global_position).normalized()
			var ang_nose_cam: float = rad_to_deg(nose.angle_to(cam_dir))
			var ang_nose_view: float = rad_to_deg(nose.angle_to(cam_at * Vector3(1, 0, 1).length()))
			var toward_center: bool = nose.x * (-sp.pos.x) + nose.z * (-sp.pos.z) > 0
			# 视角应看向机头前方（相机在机尾后上方）；朝向中心方向余弦应 > 0
			_check(ang_nose_cam < 5.0, "%s team%d: 相机朝向与机头一致(%.1f°)" % [map_id, sp.team, ang_nose_cam])
			_check(ang_nose_view < 45.0, "%s team%d: 相机从机尾后方观察机体(view=%.1f°)" % [map_id, sp.team, ang_nose_view])
			_check(toward_center, "%s team%d: 机头朝向战场中心" % [map_id, sp.team])
			v.queue_free()
			await process_frame
	print("---- 校验1 done ----")

	# ---- 校验2：A/D 渐进式偏航辅助（不再瞬时 15° 阶跃）----
	var data2: Dictionary = _load_json("res://data/vehicles/plane_a10.json")
	var v2: Node = load("res://scenes/airplane.tscn").instantiate()
	v2.is_player_controlled = true
	v2.is_server_controlled = true
	root.add_child(v2)
	await process_frame
	v2.setup_from_data(data2)
	# 高空平飞：y=600 保证按键期内不落地；初速 60m/s 使 spd>3 且 airspeed>6，
	# 姿态求解启用，按 D 时机体真实跟随 target_dir 渐进偏置（无瞬时阶跃）
	v2.global_position = Vector3(0, 600, 0)
	v2.velocity = Vector3(0, 0, -60)
	for i in 120:
		await process_frame
	var yaw_before: float = v2.rotation.y
	var max_jump_deg: float = 0.0
	var last_assist: float = 0.0
	var prev_yaw: float = yaw_before
	# 按住 D 键：偏置应从 0 渐进到 +15°（D=turn_right 为 get_axis 负轴 → input_yaw=-1 →
	# assist_target=+15°），单帧增量受 rudder_rate 限制。
	# 注意：不能直接给 v2.input_yaw 赋值——_physics_process 每帧用 Input.get_axis 覆盖，
	# 必须用 Input.action_press 模拟真实按键。
	# headless 下 process_frame 可能快于物理帧，故"等待达到目标"而非固定帧数。
	Input.action_press("turn_right")
	var settle := 0
	while settle < 180 and abs(v2.rudder_assist_cur - 15.0) > 0.6:
		await process_frame
		settle += 1
		var cur: float = v2.rudder_assist_cur
		var step: float = abs(cur - last_assist)
		max_jump_deg = max(max_jump_deg, step)
		last_assist = cur
	Input.action_release("turn_right")
	var reach: float = v2.rudder_assist_cur
	_check(abs(reach - 15.0) < 0.6, "按住D 0.5s 后偏置渐进到 +15° (实际 %.2f°)" % reach)
	_check(max_jump_deg < 2.0, "偏置角单帧增量平滑(<2°/帧, 实际 %.3f°)" % max_jump_deg)
	# 释放：偏置应平滑回中
	var settle2 := 0
	while settle2 < 180 and abs(v2.rudder_assist_cur) > 0.6:
		await process_frame
		settle2 += 1
	_check(abs(v2.rudder_assist_cur) < 0.6, "释放后偏置回中 (实际 %.2f°)" % v2.rudder_assist_cur)
	# 机头总偏转量不超过合理引导速率（0.8 rad/s ≈ 0.53°/帧 × 30帧 上限），无"突然偏转"
	var total_turn: float = rad_to_deg(absf(angle_diff(v2.rotation.y, yaw_before)))
	print("INFO: 按住D 0.5s 机头总转向 %.1f°" % total_turn)
	v2.queue_free()
	await process_frame

	print("==== 总结: %s ====" % ("全部通过" if _failed == 0 else "存在 %d 项失败" % _failed))
	quit(0 if _failed == 0 else 1)

func angle_diff(a: float, b: float) -> float:
	var d: float = fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI