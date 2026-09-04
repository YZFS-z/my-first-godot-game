extends SceneTree
## 回归护栏：手机端固定翼相机收缩到可完整看到机体（2026-08 修复）
## 背景：原固定翼相机局部 (0,2,6) 叠加 pivot 抬升 3m 后，相机相对机体 (0,5,6)，
##       观察角 atan(5/6)≈39.8° 超出 fov70(半角35°) -> 机体整体被推出画面底部
##       （手机端"控制飞机看不到机体"）；直升机 (0,5.5,20)+3 观察角≈23° 正常。
## 修复：存在 mobile 控件（与开火门控同一判断口径）时固定翼相机改用 (0,4.5,16)/fov75，
##       观察角 atan(7.5/16)≈25.1°，机体完整落入视锥内且居中偏下；桌面端保持 (0,2,6)/fov70 不变。
## 覆盖 4 条约束：
##  1) 有 mobile 控件：固定翼玩家相机 = 局部(0,4.5,16)、fov 75
##  2) 无 mobile 控件：固定翼玩家相机 = 局部(0,2,6)、fov 70（桌面端不受影响）
##  3) 手机参数下机体中心位于相机视锥内（修复前 39.8°>35° 视锥外）
##  4) 桌面参数下机体中心仍在视锥外（证明两分支差异确实由视角几何决定，
##     且修复只针对移动端，不改变桌面端既有视角）

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _mobile: Node = null
var _plane_mobile: Node = null
var _plane_desktop: Node = null

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobilePlaneCamTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	print("INFO: 场景就绪，开始移动端固定翼相机视角校验...")

func _spawn_plane() -> Node:
	var p: Node = load("res://scenes/airplane.tscn").instantiate()
	p.is_player_controlled = true
	p.is_server_controlled = false
	p.is_remote_ai = false
	p.team = 1
	root.add_child(p)
	p.global_position = Vector3(0.0, 40.0, 0.0)
	return p

func _in_frustum(p: Node) -> bool:
	"""当前相机朝向平视（pitch/yaw=0）时，机体中心是否落在相机视锥内"""
	if p.camera_pivot:
		p.camera_pivot.global_transform.basis = Basis.from_euler(Vector3.ZERO)
	return p.camera_3d.is_position_in_frustum(p.global_position)

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	match _phase:
		0:
			# 注入 mobile 控件（模拟手机模式；必须先于飞机 spawn，_ready 建相机时即生效）
			if _mobile == null:
				_mobile = CanvasLayer.new()
				_mobile.name = "MobilePlaneCamTest"
				_mobile.set_script(load("res://scripts/ui/mobile_controls.gd"))
				_mobile.add_to_group("mobile_controls")
				root.add_child(_mobile)
			_check(_mobile.is_inside_tree(), "mobile 控件注入成功（手机模式）")
			_phase = 1
			_step = 0
		1:
			# 手机模式：spawn 玩家固定翼（_ready 内 _setup_aircraft_camera 走手机分支）
			if _plane_mobile == null:
				_plane_mobile = _spawn_plane()
			if _plane_mobile.camera_3d and _step >= 5:
				_check(_plane_mobile.camera_3d.position == Vector3(0.0, 4.5, 16.0),
					"手机模式固定翼相机局部位置 = (0,4.5,16) (实际 %s)" % str(_plane_mobile.camera_3d.position))
				_check(absf(_plane_mobile.camera_3d.fov - 75.0) < 0.01,
					"手机模式固定翼相机 fov = 75 (实际 %.2f)" % _plane_mobile.camera_3d.fov)
				# 平视时机体中心应落在视锥内（修复前 39.8°>35° 为 false —— 这就是"看不到机体"的根因）
				_plane_mobile.camera_3d.current = false
				_check(_in_frustum(_plane_mobile),
					"手机参数(观察角≈25.1°)下机体中心在视锥内: %s" % str(_in_frustum(_plane_mobile)))
				# 移除 mobile，切换到桌面模式
				if _mobile != null:
					_mobile.free()
					_mobile = null
				_phase = 2
				_step = 0
		2:
			# 桌面模式：spawn 另一架玩家固定翼（无 mobile 控件 -> 桌面分支）
			if _plane_desktop == null:
				_plane_desktop = _spawn_plane()
			if _plane_desktop.camera_3d and _step >= 5:
				_check(_plane_desktop.camera_3d.position == Vector3(0.0, 2.0, 6.0),
					"桌面模式固定翼相机局部位置 = (0,2,6) (实际 %s)" % str(_plane_desktop.camera_3d.position))
				_check(absf(_plane_desktop.camera_3d.fov - 70.0) < 0.01,
					"桌面模式固定翼相机 fov = 70 (实际 %.2f)" % _plane_desktop.camera_3d.fov)
				# 桌面参数保持原视角（机体中心仍在视锥外 —— 这是既有视角，不在本次修复范围）
				_plane_desktop.camera_3d.current = false
				_check(not _in_frustum(_plane_desktop),
					"桌面参数(观察角≈39.8°)下机体中心在视锥外（既有视角未改）: %s" % str(_in_frustum(_plane_desktop)))
				_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("\nALL PASS: 移动端固定翼相机视角校验全部通过")
	else:
		print("\n%d FAILED" % _failed)
	quit(_failed)