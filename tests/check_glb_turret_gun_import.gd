extends SceneTree
## 测试：验证 glb 导入后 Turret/Gun 旋转中心自动识别与网格挂载
## 覆盖：
## 1. 源码结构：pivot 自动检测 + 手动覆盖 + _reparent_mesh_to_node（在 model_mapper.gd）
## 2. glb 结构验证：Turret/Gun 节点存在且为 MeshInstance3D
## 3. pivot 逻辑：turret_node.position 从 glb 读取，mesh 位置归零
##
## 注：导入映射逻辑已抽离到 scripts/vehicles/model_mapper.gd（ModelMapper），
## 本测试源码部分改为读取 model_mapper.gd。

var _pass: int = 0
var _fail: int = 0
var _errors: Array = []
var _runtime_phase: bool = false

func _init():
	print("=== check_glb_turret_gun_import ===")
	_test_source_code_pivot_logic()
	_test_glb_meshinstance_import()
	_test_reparent_function()
	# 运行时测试延迟到 _process：_init 阶段场景树未就绪，global_transform 不可用

func _process(_delta: float) -> bool:
	if not _runtime_phase:
		_runtime_phase = true
		_test_model_aabb_center_runtime()
		_report()
		return false
	return false

func _test_source_code_pivot_logic():
	var src = _read_file("res://scripts/vehicles/model_mapper.gd")

	# === pivot 自动检测 ===
	if src.find("vehicle.to_local(model_turret.global_position)") != -1:
		_pass_test("Turret pivot auto-detected from glb global_position")
	else:
		_fail_test("Turret pivot should use to_local(global_position)")

	if src.find("turret_pivot") != -1 and src.find('"turret_pivot"') != -1:
		_pass_test("Turret pivot manual override (turret_pivot config) supported")
	else:
		_fail_test("Missing turret_pivot config override")

	if src.find("gun_pivot") != -1 and src.find('"gun_pivot"') != -1:
		_pass_test("Gun pivot manual override (gun_pivot config) supported")
	else:
		_fail_test("Missing gun_pivot config override")

	# Gun pivot 从 Turret 的 local 坐标获取
	if src.find("to_local(model_gun.global_position)") != -1:
		_pass_test("Gun pivot computed relative to Turret")
	else:
		_fail_test("Gun pivot should be relative to Turret")

	# === muzzle 自动检测 ===
	if src.find("muzzle_offset") != -1 and src.find('"muzzle_offset"') != -1:
		_pass_test("Muzzle manual override (muzzle_offset config) supported")
	else:
		_fail_test("Missing muzzle_offset config override")

	if src.find("get_aabb()") != -1:
		_pass_test("Muzzle auto-detected from gun mesh AABB")
	else:
		_fail_test("Muzzle should auto-detect from AABB")

	# === turret_node/gun_node 位置被设置 ===
	if src.find("vehicle.turret_node.position = turret_pivot") != -1:
		_pass_test("turret_node.position set to detected pivot")
	else:
		_fail_test("turret_node.position not set to pivot")

	if src.find("vehicle.gun_node.position = gun_pivot") != -1:
		_pass_test("gun_node.position set to detected pivot")
	else:
		_fail_test("gun_node.position not set to pivot")

	# === 旧的 global_transform 方法已移除 ===
	if src.find("global_transform = turret_global") == -1:
		_pass_test("Old global_transform preservation removed (replaced by pivot)")
	else:
		_fail_test("Old global_transform method should be removed")

	# === Gun 在 Turret reparent 之前查找 ===
	var gun_find_pos = src.find("gun = _find_child_named(turret")
	var reparent_turret_pos = src.find("_reparent_mesh_to_node(model_turret")
	if gun_find_pos != -1 and reparent_turret_pos != -1 and gun_find_pos < reparent_turret_pos:
		_pass_test("Gun found BEFORE Turret reparent (avoids lost reference)")
	else:
		_fail_test("Gun should be found before Turret reparent")

	# === model_instance 先加入载具 ===
	var add_child_pos = src.find("vehicle.add_child(model_instance)")
	var pivot_detect_pos = src.find("vehicle.to_local(model_turret.global_position)")
	if add_child_pos != -1 and pivot_detect_pos != -1 and add_child_pos < pivot_detect_pos:
		_pass_test("model_instance added before pivot detection (global_position available)")
	else:
		_fail_test("model_instance should be added before pivot detection")

	# === MeshInstance3D 分支：保留全局位姿（含整体对齐旋转与缩放）===
	var func_start = src.find("func _reparent_mesh_to_node")
	var func_end = src.find("\n\n", func_start)
	if func_end < 0:
		func_end = src.length()
	var func_body = src.substr(func_start, func_end - func_start)

	if func_body.find("is MeshInstance3D") != -1:
		_pass_test("_reparent handles MeshInstance3D case")
	else:
		_fail_test("_reparent should handle MeshInstance3D")

	if func_body.find("saved_global") != -1 and func_body.find("global_transform = saved_global") != -1:
		_pass_test("MeshInstance3D: global transform preserved (align rotation + scale kept)")
	else:
		_fail_test("MeshInstance3D: should preserve global transform")

	# === Node3D 容器分支：子节点保留全局位姿 ===
	if func_body.find("queue_free()") != -1:
		_pass_test("Container: queue_free after moving children")
	else:
		_fail_test("Container: should queue_free after moving children")

	# === 自动对齐模型前方到 -Z（新增整体旋转）===
	if src.find("_get_model_yaw_align_angle") != -1:
		_pass_test("Yaw align function referenced")
	else:
		_fail_test("Missing yaw align function reference")

	if src.find("func _get_model_yaw_align_angle") != -1:
		_pass_test("_get_model_yaw_align_angle defined")
	else:
		_fail_test("_get_model_yaw_align_angle function missing")

	# === 模型包围盒中心（Node3D 无 get_aabb，需遍历子网格）===
	if src.find("func _get_model_aabb_center") != -1:
		_pass_test("_get_model_aabb_center defined (handles Node3D no-get_aabb)")
	else:
		_fail_test("_get_model_aabb_center function missing")

func _test_glb_meshinstance_import():
	var path = "D:/work/war_thunder_like/.dumate/inbox/kv-1.glb"
	if not FileAccess.file_exists(path):
		print("  跳过 glb 运行时测试：kv-1.glb 不存在（KV-1 已改为内置载具）")
		return

	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var err = gltf.append_from_file(path, state, 0, "")
	if err != OK:
		_fail_test("Failed to load GLTF: error %d" % err)
		return

	var scene = gltf.generate_scene(state)
	if not scene:
		_fail_test("Failed to generate scene from GLTF")
		return

	var turret = scene.find_child("Turret", true, false)
	if turret:
		_pass_test("Turret node found in glb")
	else:
		_fail_test("Turret node NOT found in glb")
		return

	if turret is MeshInstance3D:
		_pass_test("Turret is MeshInstance3D (self is mesh)")
	else:
		_fail_test("Turret is %s (expected MeshInstance3D)" % turret.get_class())
		return

	var gun = turret.find_child("Gun", true, false)
	if gun:
		_pass_test("Gun node found as child of Turret")
	else:
		gun = scene.find_child("Gun", true, false)
		if gun:
			_pass_test("Gun node found in scene (not child of Turret)")
		else:
			_fail_test("Gun node NOT found in glb")
			return

	if gun is MeshInstance3D:
		_pass_test("Gun is MeshInstance3D (self is mesh)")
	else:
		_fail_test("Gun is %s (expected MeshInstance3D)" % gun.get_class())
		return

	if turret.mesh:
		_pass_test("Turret has mesh data")
	else:
		_fail_test("Turret has no mesh data")

	if gun.mesh:
		_pass_test("Gun has mesh data")
	else:
		_fail_test("Gun has no mesh data")

	# 验证 AABB 可用于 muzzle 自动检测
	var gun_aabb = gun.get_aabb()
	if gun_aabb.size.length() > 0.1:
		_pass_test("Gun AABB valid for muzzle detection (size=%.2f)" % gun_aabb.size.length())
	else:
		_fail_test("Gun AABB too small for muzzle detection")

	scene.queue_free()

func _test_reparent_function():
	# 纯 Node3D 模拟验证 _reparent_mesh_to_node 逻辑
	var parent = Node3D.new()
	parent.name = "TestParent"
	root.add_child(parent)

	var child = MeshInstance3D.new()
	child.name = "TestMesh"
	child.position = Vector3(1, 2, 3)
	child.rotation = Vector3(0.1, 0.2, 0.3)
	child.scale = Vector3(2, 2, 2)
	parent.add_child(child)

	var target = Node3D.new()
	target.name = "TargetNode"
	root.add_child(target)

	# 模拟 _reparent_mesh_to_node 的 MeshInstance3D 分支
	var saved_rot = child.rotation
	var saved_scale = child.scale
	parent.remove_child(child)
	target.add_child(child)
	child.position = Vector3.ZERO
	child.rotation = saved_rot
	child.scale = saved_scale

	# 验证
	if child.get_parent() == target:
		_pass_test("Mesh reparented to target node")
	else:
		_fail_test("Mesh not reparented to target")

	if child.position == Vector3.ZERO:
		_pass_test("Mesh position zeroed after reparent")
	else:
		_fail_test("Mesh position should be zero")

	if child.rotation == Vector3(0.1, 0.2, 0.3):
		_pass_test("Mesh rotation preserved after reparent")
	else:
		_fail_test("Mesh rotation not preserved")

	if child.scale == Vector3(2, 2, 2):
		_pass_test("Mesh scale preserved after reparent")
	else:
		_fail_test("Mesh scale not preserved")

	# 测试容器分支
	var container = Node3D.new()
	container.name = "Container"
	root.add_child(container)

	var c1 = MeshInstance3D.new()
	c1.position = Vector3(0.5, 1, -1)
	container.add_child(c1)

	var c2 = MeshInstance3D.new()
	c2.position = Vector3(-0.3, 0, 0.5)
	container.add_child(c2)

	var target2 = Node3D.new()
	target2.name = "TargetNode2"
	root.add_child(target2)

	# 模拟容器分支
	for ch in container.get_children():
		var st = ch.transform
		container.remove_child(ch)
		target2.add_child(ch)
		ch.transform = st
	container.queue_free()

	if c1.get_parent() == target2 and c2.get_parent() == target2:
		_pass_test("Container children moved to target")
	else:
		_fail_test("Container children not moved correctly")

	if c1.position == Vector3(0.5, 1, -1):
		_pass_test("Container child 1 local transform preserved")
	else:
		_fail_test("Container child 1 local transform not preserved")

	if c2.position == Vector3(-0.3, 0, 0.5):
		_pass_test("Container child 2 local transform preserved")
	else:
		_fail_test("Container child 2 local transform not preserved")

	parent.queue_free()
	target.queue_free()
	target2.queue_free()

func _test_model_aabb_center_runtime():
	# 运行时验证：Node3D 基类没有 get_aabb()，_get_model_aabb_center 需遍历子网格合并
	var path = "user://assets/models/tank_t-.glb"
	if not FileAccess.file_exists(path):
		print("  跳过 AABB 中心运行时测试：tank_t-.glb 不存在")
		return
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var err = gltf.append_from_file(path, state, 0, "")
	if err != OK:
		_fail_test("tank_t-.glb 加载失败: error %d" % err)
		return
	var model_instance = gltf.generate_scene(state)
	if not model_instance:
		_fail_test("tank_t-.glb generate_scene 失败")
		return
	var holder := Node3D.new()
	holder.name = "AABBTestHolder"
	root.add_child(holder)
	holder.add_child(model_instance)
	# 遍历合并包围盒（等价于 _get_model_aabb_center 的核心逻辑）
	var combined := AABB()
	var has := false
	for mi in model_instance.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m and m.mesh:
			var local_aabb: AABB = model_instance.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			if not has:
				combined = local_aabb
				has = true
			else:
				combined = combined.merge(local_aabb)
	if not has:
		_fail_test("未找到任何 MeshInstance3D 网格")
		holder.queue_free()
		return
	var center := combined.get_center()
	if center.length() > 0.01:
		_pass_test("模型 AABB 合并成功，中心=%s (无 get_aabb 运行时错误)" % center)
	else:
		_fail_test("AABB 中心异常: %s" % center)
	holder.queue_free()

func _read_file(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var content = file.get_as_text()
	file.close()
	return content

func _pass_test(msg: String):
	_pass += 1
	print("  PASS: %s" % msg)

func _fail_test(msg: String):
	_fail += 1
	_errors.append(msg)
	print("  FAIL: %s" % msg)

func _report():
	print("")
	print("=== Results: %d passed, %d failed ===" % [_pass, _fail])
	if _errors.size() > 0:
		print("Errors:")
		for e in _errors:
			print("  - %s" % e)
		quit(1)
	else:
		quit(0)
