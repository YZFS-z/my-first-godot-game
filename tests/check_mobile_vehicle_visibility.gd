extends SceneTree
## 回归护栏：手机模式机体可见性增强（2026-08-23）
## 背景：用户反馈手机端"只能看到玩家的昵称看不到飞机机体"。排查确认机体正常挂载、
##       正常渲染（两种渲染驱动验证），根因是深色机身与背景/暗屏对比度过低，
##       而昵称（Label3D 绿字+黑描边）始终清晰。修复：手机模式（存在 mobile 控件，
##       与开火门控同口径）挂载模型后，对全部可见网格 material_override 为
##       mobile_rim.gdshader 轮廓材质（边缘 EMISSION 轮廓光，不依赖光源）；桌面端不改。
## 覆盖：
##  1) 手机模式：固定翼全部可见网格套用轮廓材质（ShaderMaterial=mobile_rim）
##  2) 手机模式：直升机同样生效（同一基类加载路径）
##  3) base_color 取自原材质 albedo 且提亮（轮廓光叠加后机体整体更可辨）
##  4) 桌面模式：机体 material_override 保持 null（零影响）
## 渲染级验证由手动脚本 tests/_render_verify.gd 承担（需真实窗口，不进全量回归）。

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _mobile: Node = null
var _plane: Node = null
var _heli: Node = null
var _desktop_plane: Node = null

const RIM_SHADER_PATH := "res://scripts/vehicles/mobile_rim.gdshader"

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobileVisibilityTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	print("INFO: 场景就绪，开始手机模式机体可见性校验...")

func _spawn_vehicle(scene_path: String, model_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = false
	v.is_remote_ai = false
	v.team = 1
	root.add_child(v)
	v.global_position = Vector3(0.0, 40.0, 0.0)
	v.setup_from_data({
		"name": "visibility_test",
		"model": {"scene_path": model_path, "scale": 1.0},
		"physics": {}
	})
	return v

func _visible_meshes(v: Node) -> Array:
	var out: Array = []
	for m in v.find_children("*", "MeshInstance3D", true, false):
		if m.visible and m.mesh != null:
			out.append(m)
	return out

func _boosted_count(v: Node) -> int:
	var count := 0
	for m in _visible_meshes(v):
		var ov = m.material_override
		if ov is ShaderMaterial and ov.shader != null and ov.shader.resource_path == RIM_SHADER_PATH:
			count += 1
	return count

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	match _phase:
		0:
			# 注入 mobile 控件（必须先于载具 spawn，_ready 即套用手机模式材质）
			if _mobile == null:
				_mobile = CanvasLayer.new()
				_mobile.name = "MobileVisibilityTest"
				_mobile.set_script(load("res://scripts/ui/mobile_controls.gd"))
				_mobile.add_to_group("mobile_controls")
				root.add_child(_mobile)
			_check(_mobile.is_inside_tree(), "mobile 控件注入成功（手机模式）")
			_phase = 1
			_step = 0
		1:
			# 手机模式固定翼：所有可见网格套用轮廓材质
			if _plane == null:
				_plane = _spawn_vehicle("res://scenes/airplane.tscn", "res://scenes/airplane_model.tscn")
			if _step >= 5:
				var meshes := _visible_meshes(_plane)
				_check(meshes.size() > 0, "固定翼模型网格已挂载 (count=%d)" % meshes.size())
				var boosted := _boosted_count(_plane)
				_check(boosted == meshes.size(),
					"手机模式固定翼全部可见网格套用轮廓材质 (%d/%d)" % [boosted, meshes.size()])
				if meshes.size() > 0:
					var mat := meshes[0].material_override as ShaderMaterial
					var bc: Color = mat.get_shader_parameter("base_color")
					_check(bc.r > 0.1 and bc.r < 1.0 and bc.g > 0.1 and bc.b > 0.1,
						"base_color 已从原材质映射为有效基色: %s" % str(bc))
				_phase = 2
				_step = 0
		2:
			# 手机模式直升机：同一基类路径同样生效
			if _heli == null:
				_heli = _spawn_vehicle("res://scenes/helicopter.tscn", "res://scenes/helicopter_model.tscn")
			if _step >= 5:
				var meshes := _visible_meshes(_heli)
				_check(meshes.size() > 0, "直升机模型网格已挂载 (count=%d)" % meshes.size())
				var boosted := _boosted_count(_heli)
				_check(boosted == meshes.size(),
					"手机模式直升机全部可见网格套用轮廓材质 (%d/%d)" % [boosted, meshes.size()])
				# 切桌面模式
				if _mobile != null:
					_mobile.free()
					_mobile = null
				_phase = 3
				_step = 0
		3:
			# 桌面模式：不套用轮廓材质（零影响；模型场景自带 material_override 属正常，只排除 ShaderMaterial）
			if _desktop_plane == null:
				_desktop_plane = _spawn_vehicle("res://scenes/airplane.tscn", "res://scenes/airplane_model.tscn")
			if _step >= 5:
				var mistakenly_boosted := 0
				for m in _visible_meshes(_desktop_plane):
					if m.material_override is ShaderMaterial:
						mistakenly_boosted += 1
						print("INFO: 桌面模式意外套用轮廓: mesh=%s" % m.name)
				_check(mistakenly_boosted == 0, "桌面模式未套用轮廓材质（ShaderMaterial=0, 实际 %d）" % mistakenly_boosted)
				_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("\nALL PASS: 手机模式机体可见性校验全部通过")
	else:
		print("\n%d FAILED" % _failed)
	quit(_failed)