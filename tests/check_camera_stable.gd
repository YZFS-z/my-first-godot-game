extends SceneTree
## 校验：飞行器摄像机锚点稳定性与防穿地修正（2026-08 修复）
## 覆盖 5 条约束：
##  1) 相机锚点（AircraftCameraPivot）高空平视时精确 = 机体 + (0,3,0)
##  2) 机体滚转（压坡）时锚点不随机身画圈位移（top_level + 每帧手动跟随）
##  3) 低空对地大俯角时防穿地修正生效：摄像机不穿入地底（global y >= 1.0）
##  4) 防穿地修正不残留：恢复高空平视后锚点回到机体 + (0,3,0)，不再偏高
##     （回归bug：helicopter _update_camera 用 camera_pivot.position.y += diff 局部累加，
##      触发一次后相机锚点被永久垫高 →「控制飞行器时摄像机位置变高」）
##  5) 固定翼/直升机两侧行为一致（airplane 为回归护栏，应全过）
## 实现要点：非玩家载具不自动建相机/不更新——手动调 _setup_aircraft_camera() 与
## _update_camera(delta)（delta 固定 1/60），直接设 pivot basis 以确定性触发防穿地分支

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _heli: Node = null
var _plane: Node = null
const DT: float = 1.0 / 60.0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _cam_drift(v: Node) -> float:
	"""锚点相对机体基准 (0,3,0) 的世界偏差长度"""
	var want: Vector3 = v.global_position + Vector3(0, 3.0, 0)
	return (v.camera_pivot.global_position - want).length()

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeCameraStableTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	var heli: Node = load("res://scenes/helicopter.tscn").instantiate()
	heli.is_player_controlled = false
	heli.is_server_controlled = false
	heli.is_remote_ai = false
	heli.team = 1
	root.add_child(heli)
	heli.global_position = Vector3(0.0, 40.0, 0.0)
	_heli = heli
	var plane: Node = load("res://scenes/airplane.tscn").instantiate()
	plane.is_player_controlled = false
	plane.is_server_controlled = false
	plane.is_remote_ai = false
	plane.team = 1
	root.add_child(plane)
	plane.global_position = Vector3(0.0, 40.0, 80.0)
	_plane = plane
	print("INFO: 场景就绪，开始摄像机锚点稳定性校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if not _heli.camera_pivot:
		_heli._setup_aircraft_camera()
	if not _plane.camera_pivot:
		_plane._setup_aircraft_camera()
		_plane.camera_3d.current = false   # 避免与主相机冲突
	match _phase:
		0:
			# —— 直升机：高空平视基准 ——
			_heli.target_pitch = 0.0
			_heli.target_yaw = 0.0
			_heli.rotation = Vector3.ZERO
			if _step >= 2:
				_check(_heli.camera_pivot != null and _heli.camera_3d != null, "直升机相机已创建")
				_phase = 1
				_step = 0
		1:
			for i in 10:
				_heli._update_camera(DT)
			_check(_cam_drift(_heli) < 0.001, "直升机高空平视：锚点 = 机体+(0,3,0) (漂移 %.4f)" % _cam_drift(_heli))
			_heli.rotation.z = 0.4   # 压坡 23°
			_phase = 2
			_step = 0
		2:
			for i in 30:
				_heli._update_camera(DT)
			_check(_cam_drift(_heli) < 0.001,
				"直升机压坡(roll=0.4)锚点不随机身画圈 (漂移 %.4f)" % _cam_drift(_heli))
			# 触发防穿地：相机姿态由 target_quat 引导（俯冲时相机反而更高），
			# 直接模拟"相机处于贴地状态"（等价 低空俯冲瞄准地面的真实场景），
			# 验证保护生效且修正无残留
			_heli.camera_pivot.global_position.y = _heli.global_position.y + 3.0
			_heli.camera_pivot.global_transform.basis = Basis.IDENTITY
			_heli.camera_3d.global_position.y = 0.3
			_phase = 3
			_step = 0
		3:
			_heli._update_camera(DT)
			if _step >= 2:
				var cam_y: float = _heli.camera_3d.global_position.y
				_check(cam_y >= 0.999, "直升机相机贴地：防穿地抬升保护（相机 y=%.3f ≥ 1.0）" % cam_y)
				_heli.camera_3d.position = Vector3(0.0, 5.5, 20.0)   # 还原相机局部位置（不再人为触发）
				# 恢复高空平视：锚点必须回到基准，不再偏高（回归残留 bug）
				_heli.global_position.y = 40.0
				_heli.target_pitch = 0.0
				_heli.target_yaw = 0.0
				_heli.rotation = Vector3.ZERO
				_heli.camera_pivot.global_transform.basis = Basis.IDENTITY
				_phase = 4
				_step = 0
		4:
			for i in 3:
				_heli._update_camera(DT)
			_check(absf(_heli.camera_pivot.global_position.y - 43.0) < 0.01,
				"直升机恢复高空平视：锚点无残留抬高 (y=%.3f 期望 43.0)" % _heli.camera_pivot.global_position.y)
			# —— 固定翼（回归护栏）——
			_plane.rotation = Vector3.ZERO
			_plane.target_pitch = 0.0
			_plane.target_yaw = 0.0
			_phase = 5
			_step = 0
		5:
			for i in 10:
				_plane._update_camera(DT)
			_check(_cam_drift(_plane) < 0.001, "固定翼高空平视：锚点 = 机体+(0,3,0) (漂移 %.4f)" % _cam_drift(_plane))
			_plane.rotation.z = 0.4
			_phase = 6
			_step = 0
		6:
			for i in 30:
				_plane._update_camera(DT)
			_check(_cam_drift(_plane) < 0.001, "固定翼压坡(roll=0.4)锚点不随机身画圈 (漂移 %.4f)" % _cam_drift(_plane))
			_plane.camera_pivot.global_position.y = _plane.global_position.y + 3.0
			_plane.camera_pivot.global_transform.basis = Basis.IDENTITY
			_plane.camera_3d.global_position.y = 0.3
			_phase = 7
			_step = 0
		7:
			_plane._update_camera(DT)
			if _step >= 2:
				var cam_y: float = _plane.camera_3d.global_position.y
				_check(cam_y >= 0.999, "固定翼相机贴地：防穿地抬升保护（相机 y=%.3f ≥ 1.0）" % cam_y)
				_plane.camera_3d.position = Vector3(0.0, 2.0, 6.0)   # 还原相机局部位置
				_plane.global_position.y = 40.0
				_plane.target_pitch = 0.0
				_plane.target_yaw = 0.0
				_plane.rotation = Vector3.ZERO
				_plane.camera_pivot.global_transform.basis = Basis.IDENTITY
				_phase = 8
				_step = 0
		8:
			for i in 3:
				_plane._update_camera(DT)
			_check(absf(_plane.camera_pivot.global_position.y - 43.0) < 0.01,
				"固定翼恢复高空平视：锚点无残留抬高 (y=%.3f 期望 43.0)" % _plane.camera_pivot.global_position.y)
			_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("\nALL PASS: 摄像机锚点稳定性校验全部通过")
	else:
		print("\n%d FAILED" % _failed)
	quit(_failed)