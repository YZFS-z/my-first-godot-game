extends SceneTree
## 手机模式固定翼机体渲染验证：真实挂载 A10 模型并从玩家相机渲染一帧
## 背景：用户反馈手机端"只能看到昵称看不到飞机机体"。几何视角(25.1°<半角37.5°)
##       已由 check_mobile_airplane_camera 覆盖，本脚本做渲染级验证：
##       - 模型能否真实挂载（find_children MeshInstance3D）
##       - 玩家相机（手机分支 (0,4.5,16)/fov75）视角下机体是否真实渲染出像素
## 用法（注意：必须非 headless，否则无渲染帧）：
##   godot --script res://tests/_render_verify.gd
##   godot --script res://tests/_render_verify.gd --rendering-driver opengl3

var _plane: Node = null
var _mobile: Node = null
var _step := 0
var _done := false
var _failed := 0

# 本测试不经过 main.gd，无 WorldEnvironment -> 背景即 default_clear_color
const BG := Color(0.3, 0.35, 0.4)
const OUT_PNG := "D:/work/war_thunder_like/tests/_render_verify_mobile.png"

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var fake := Node.new()
	fake.name = "RenderVerifyScene"
	root.add_child(fake)
	current_scene = fake
	# 补一个方向光，让机体受光后与背景区分更清晰（main.gd 的 _setup_environment 不在本路径）
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -20, 0)
	light.light_energy = 1.2
	root.add_child(light)
	print("INFO: 渲染验证场景就绪 (driver=%s)" % RenderingServer.get_video_adapter_name())

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	# 1) 注入 mobile 控件（手机模式判定口径与游戏一致，必须先于飞机 spawn）
	if _mobile == null:
		_mobile = CanvasLayer.new()
		_mobile.name = "MobileControlsVerify"
		_mobile.set_script(load("res://scripts/ui/mobile_controls.gd"))
		_mobile.add_to_group("mobile_controls")
		root.add_child(_mobile)
		return false
	# 2) 生成玩家固定翼并挂载真实模型
	if _plane == null:
		_plane = load("res://scenes/airplane.tscn").instantiate()
		_plane.is_player_controlled = true
		_plane.is_server_controlled = false
		_plane.is_remote_ai = false
		_plane.team = 1
		_plane.nickname = "VerificationPlane"
		root.add_child(_plane)
		_plane.global_position = Vector3(0.0, 40.0, 0.0)
		# 直接构造模型数据（--script 下不依赖 DataLoader autoload）
		_plane.setup_from_data({
			"name": "render_verify",
			"model": {"scene_path": "res://scenes/airplane_model.tscn", "scale": 1.0},
			"physics": {"crash_impact_scale": 1.0}
		})
		return false
	# 3) 等待相机就绪 + 模型挂载 + 渲染若干帧
	if _plane.camera_3d == null or not _plane.camera_3d.is_inside_tree():
		if _step > 240:
			_check(false, "超时：玩家相机未就绪")
			_finish()
		return false
	if _step < 45:
		return false
	# 4) 模型挂载检查（运行时 add_child 的可见 MeshInstance3D，不数内置占位体）
	var visible_meshes := 0
	for m in _plane.find_children("*", "MeshInstance3D", true, false):
		if m.visible:
			visible_meshes += 1
	_check(visible_meshes > 0, "模型 MeshInstance3D 已挂载且可见 (count=%d)" % visible_meshes)
	# 5) 玩家相机视角渲染帧，统计画面主体区非背景像元
	var img: Image = _plane.camera_3d.get_viewport().get_texture().get_image()
	_check(img != null and img.get_width() > 0,
		"viewport 渲染帧可用 (%s)" % (str(img.get_size()) if img else "null"))
	if img == null or img.get_width() == 0:
		_finish()
		return false
	var body_px := 0
	var total := 0
	for y in range(int(img.get_height() * 0.2), int(img.get_height() * 0.97)):
		for x in range(int(img.get_width() * 0.05), int(img.get_width() * 0.95)):
			var c: Color = img.get_pixel(x, y)
			total += 1
			if absf(c.r - BG.r) + absf(c.g - BG.g) + absf(c.b - BG.b) > 0.30:
				body_px += 1
	_check(body_px > 3000, "玩家相机画面存在显著机体像元 (非背景像素=%d / 采样=%d)" % [body_px, total])
	img.save_png(OUT_PNG)
	print("INFO: 截图已保存: %s" % OUT_PNG)
	_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("\nALL PASS: 手机模式固定翼机体渲染验证通过")
	else:
		print("\n%d FAILED" % _failed)
	quit(_failed)