extends SceneTree
## 回归校验：飞机/直升机大边界 + 相机俯仰接近 ±90° 视角不突然左右切换

## 模拟 main.gd 的载具父节点（vehicle._ready 从父节点读 map_config）
class FakeParent:
	extends Node3D
	var map_config: Dictionary = {}

var _failed := 0
var _step := 0
var _phase := 0
var _airplane: Node = null
var _helicopter: Node = null
var _tank: Node = null
var _ap_data: Dictionary = {}
var _hp_data: Dictionary = {}
var _tk_data: Dictionary = {}

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
	# 地面：飞机出生即落地，避免自由落体姿态病态
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30000.0, 1.0, 30000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

	# 带 map_config 的假父节点（模拟 main.gd：坦克战场 size=2000，飞机大边界 air=12000）
	var ap_parent := FakeParent.new()
	ap_parent.name = "AirParent"
	ap_parent.map_config = {"size": 2000.0, "air_boundary_size": 12000.0}
	root.add_child(ap_parent)
	var tk_parent := FakeParent.new()
	tk_parent.name = "TankParent"
	tk_parent.map_config = {"size": 2000.0, "air_boundary_size": 12000.0}
	root.add_child(tk_parent)

	_ap_data = _load_json("res://data/vehicles/plane_a10.json")
	_hp_data = _load_json("res://data/vehicles/heli_ah64.json")
	_tk_data = _load_json("res://data/vehicles/tank_abrams.json")

	_airplane = load("res://scenes/airplane.tscn").instantiate()
	_airplane.is_player_controlled = true
	_airplane.is_server_controlled = true
	ap_parent.add_child(_airplane)
	_airplane.global_position = Vector3(100.0, 2.0, 100.0)
	_helicopter = load("res://scenes/helicopter.tscn").instantiate()
	_helicopter.is_player_controlled = true
	_helicopter.is_server_controlled = true
	ap_parent.add_child(_helicopter)
	_helicopter.global_position = Vector3(2000.0, 2.0, 2000.0)
	_tank = load("res://scenes/vehicle.tscn").instantiate()
	_tank.is_player_controlled = true
	_tank.is_server_controlled = true
	tk_parent.add_child(_tank)
	_tank.global_position = Vector3(500.0, 2.0, 500.0)

func _physics_process(delta: float) -> bool:
	_step += 1
	if _step > 2000:
		print("FAIL: 测试全局超时 (_phase=%d)" % _phase)
		_finish()
		return false
	match _phase:
		0:
			# 等 _ready 完成（damage_system 就绪）再装载数据
			if _step < 15:
				return false
			if _airplane.damage_system == null or _helicopter.damage_system == null or _tank.damage_system == null:
				return false
			_airplane.setup_from_data(_ap_data)
			_helicopter.setup_from_data(_hp_data)
			_tank.setup_from_data(_tk_data)
			_airplane.velocity = Vector3.ZERO
			_helicopter.velocity = Vector3.ZERO
			_tank.velocity = Vector3.ZERO
			_phase = 1
			_step = 0
		1:
			# 边界读取：飞机/直升机用 air_boundary_size（12000/2=6000），坦克用 size（2000/2=1000）
			if _step >= 5:
				_check(_airplane.use_air_boundary, "[边界] 固定翼 use_air_boundary=true")
				_check(_helicopter.use_air_boundary, "[边界] 直升机 use_air_boundary=true")
				_check(not _tank.use_air_boundary, "[边界] 坦克 use_air_boundary=false（不受飞机大边界影响）")
				_check(absf(_airplane.map_half_size - 6000.0) < 0.5, "[边界] 固定翼 map_half_size=%.0f (期望6000)" % _airplane.map_half_size)
				_check(absf(_helicopter.map_half_size - 6000.0) < 0.5, "[边界] 直升机 map_half_size=%.0f (期望6000)" % _helicopter.map_half_size)
				_check(absf(_tank.map_half_size - 1000.0) < 0.5, "[边界] 坦克 map_half_size=%.0f (期望1000)" % _tank.map_half_size)
				# ---- 相机回归准备：固定翼 ----
				_airplane.auto_center_enabled = false  # 测试直接设 target_pitch，禁用自动回正
				_airplane.target_yaw = 0.0
				_airplane.target_pitch = 0.0
				_airplane.free_look_yaw = 0.0
				_airplane.free_look_pitch = 0.0
				_phase = 2
				_step = 0
		2:
			# 固定翼：俯仰逐步推到 85° → 89° → 89.9°（≈±90° 反解退化区），
			# 相机 slerp 每帧收敛后，视线应与各自 pitch 的目标视线连续对齐（无 180° 左右切换）
			if _step == 1:
				_airplane.target_pitch = deg_to_rad(85.0)
			elif _step == 40:
				_airplane.target_pitch = deg_to_rad(89.0)
			elif _step == 80:
				_airplane.target_pitch = deg_to_rad(89.9)
			elif _step >= 150:
				_run_camera_verification(_airplane, "固定翼", 89.9)
				# ---- 直升机准备 ----
				_helicopter.target_yaw = 0.0
				_helicopter.target_pitch = 0.0
				_helicopter.free_look_yaw = 0.0
				_helicopter.free_look_pitch = 0.0
				_phase = 3
				_step = 0
		3:
			if _step == 1:
				_helicopter.target_pitch = deg_to_rad(85.0)
			elif _step == 40:
				_helicopter.target_pitch = deg_to_rad(89.0)
			elif _step == 80:
				_helicopter.target_pitch = deg_to_rad(89.9)
			elif _step >= 150:
				_run_camera_verification(_helicopter, "直升机", 89.9)
				_finish()
	return false

## 相机回归核心：当前 camera_pivot 视线应近似等于"直接由目标角度构造的四元数"视线，
## 且从 85° 到 89.9° 的视线变化连续（小角度），没有 180° 翻转。
## 同时验证 yaw 未突变：目标 yaw=0，若出现"左右切换"，视线会在 (x,z) 水平面翻转。
func _run_camera_verification(v: Node, label: String, pitch_deg: float) -> void:
	_check(v.camera_pivot != null, "[%s] camera_pivot 存在" % label)
	if v.camera_pivot == null:
		return
	var cur_dir: Vector3 = -v.camera_pivot.global_transform.basis.z
	# 期望视线 = 直接由目标角度构造的四元数朝向（新逻辑，无 atan2/asin 反解）
	var expect_dir: Vector3 = -Basis.from_euler(Vector3(deg_to_rad(pitch_deg), v.target_yaw, 0.0)).z
	var ang: float = rad_to_deg(cur_dir.angle_to(expect_dir))
	_check(ang < 3.0, "[%s] 俯仰%.1f° 相机视线收敛到目标 (偏差%.2f°)" % [label, pitch_deg, ang])
	# 视线应指向上方（pitch=89.9° 时视线几乎垂直向上）：y 分量应显著大于水平分量
	_check(cur_dir.y > 0.9, "[%s] 大俯仰时视线垂直向上 (dir.y=%.3f)" % [label, cur_dir.y])
	# yaw 未跳变：目标 yaw=0，相机水平投影方向不应翻转到 ±180°
	var yaw_from_cam: float = rad_to_deg(atan2(cur_dir.x, -cur_dir.z))
	_check(absf(wrapf(yaw_from_cam, -180.0, 180.0)) < 10.0, "[%s] 相机 yaw 未突变 (yaw=%.1f°)" % [label, yaw_from_cam])
	# 路径连续性：85° 与 89.9° 的目标视线夹角应小（旧反解会在此区间 yaw 翻转 → 180° 跳变）
	var dir85: Vector3 = -Basis.from_euler(Vector3(deg_to_rad(85.0), v.target_yaw, 0.0)).z
	var dir90: Vector3 = -Basis.from_euler(Vector3(deg_to_rad(89.9), v.target_yaw, 0.0)).z
	var jump: float = rad_to_deg(dir85.angle_to(dir90))
	_check(jump < 15.0, "[%s] 85°→89.9° 视线连续无跳变 (夹角%.2f°)" % [label, jump])

func _finish() -> void:
	_phase = 99
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)