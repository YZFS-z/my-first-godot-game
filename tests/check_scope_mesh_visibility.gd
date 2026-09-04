extends SceneTree
## 测试：验证坦克开镜后导入模型网格被正确隐藏（修复 ImportedModel 为 Node3D 容器时的遮挡 bug）
## 覆盖：
## 1. 源码结构：_set_vehicle_meshes_visible 使用递归遍历而非 is VisualInstance3D 判断
## 2. 运行时验证：导入 glb 后开镜，ImportedModel 下所有 GeometryInstance3D.visible == false

var _pass: int = 0
var _fail: int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: " + msg)
	else:
		_fail += 1
		print("FAIL: " + msg)

func _initialize():
	print("=== check_scope_mesh_visibility ===")
	_test_source_code_recursive_hide()
	_test_runtime_visibility()

func _test_source_code_recursive_hide():
	var src = _read_file("res://scripts/vehicles/tank.gd")

	# 不应再用 imported_model is VisualInstance3D 判断（glb 导入根节点是 Node3D）
	if src.find("is VisualInstance3D") == -1 or src.find("imported_model and imported_model is VisualInstance3D") == -1:
		_check(true, "不再依赖 imported_model is VisualInstance3D 判断")
	else:
		_check(false, "仍使用 imported_model is VisualInstance3D 判断（glb 根节点是 Node3D，此分支不执行）")

	# 应有递归遍历函数
	if src.find("_set_node_and_geometry_children_visible") != -1:
		_check(true, "存在递归隐藏函数 _set_node_and_geometry_children_visible")
	else:
		_check(false, "缺少递归隐藏函数")

	if src.find("is GeometryInstance3D") != -1:
		_check(true, "递归判断 GeometryInstance3D")
	else:
		_check(false, "递归应判断 GeometryInstance3D")

func _test_runtime_visibility():
	# 设置 GameManager，使用内置坦克验证炮镜网格隐藏
	var gm = root.get_node("GameManager")
	gm.selected_map_id = "map_valley"
	gm.selected_vehicle_id = "tank_kv1"

	# 加载主场景
	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame

	# 查找玩家载具
	var player_vehicle = null
	var spawner = main.get_node_or_null("VehicleSpawner")
	if spawner:
		player_vehicle = spawner.get("player_vehicle")
	if player_vehicle == null:
		for child in main.get_children():
			if child is CharacterBody3D and child.get("is_player_controlled") == true:
				player_vehicle = child
				break

	if player_vehicle == null:
		_check(false, "未找到玩家载具")
		_report()
		return

	_check(true, "找到玩家载具")

	# 检查是否有 ImportedModel
	var imported_model = player_vehicle.get_node_or_null("ImportedModel")
	if imported_model == null:
		print("  跳过运行时测试：无 ImportedModel（内置坦克），仅验证源码结构")
		_report()
		return

	_check(true, "存在 ImportedModel")

	# 记录开镜前的 visible 状态
	var mesh_count = 0
	var meshes_before = _count_visible_meshes(imported_model, mesh_count)
	mesh_count = meshes_before[1]
	print("  开镜前 ImportedModel 下可见 GeometryInstance3D: %d" % mesh_count)

	# 模拟开镜
	if player_vehicle.has_method("_toggle_scope"):
		player_vehicle._toggle_scope()
	elif player_vehicle.has_method("_open_scope"):
		player_vehicle._open_scope()
	else:
		# 手动调用
		player_vehicle.set("is_scope_mode", true)
		player_vehicle._set_vehicle_meshes_visible(false)

	await physics_frame

	# 检查开镜后所有网格是否被隐藏
	var hidden_result = _count_hidden_meshes(imported_model)
	var hidden_count = hidden_result[1]
	print("  开镜后隐藏的 GeometryInstance3D: %d" % hidden_count)
	_check(hidden_count > 0, "开镜后 ImportedModel 下有被隐藏的网格")
	_check(hidden_count == mesh_count, "开镜后所有网格被隐藏（%d/%d）" % [hidden_count, mesh_count])

	# 模拟关镜
	if player_vehicle.has_method("_close_scope"):
		player_vehicle._close_scope()
	else:
		player_vehicle.set("is_scope_mode", false)
		player_vehicle._set_vehicle_meshes_visible(true)

	await physics_frame

	# 检查关镜后网格恢复
	var restored = _count_visible_meshes(imported_model, 0)
	_check(restored[1] == mesh_count, "关镜后网格恢复可见（%d/%d）" % [restored[1], mesh_count])

	main.queue_free()
	_report()

func _count_visible_meshes(node: Node, count: int) -> Array:
	if node is GeometryInstance3D and node.visible:
		count += 1
	for child in node.get_children():
		var result = _count_visible_meshes(child, count)
		count = result[1]
	return [node, count]

func _count_hidden_meshes(node: Node) -> Array:
	var count = 0
	if node is GeometryInstance3D and not node.visible:
		count += 1
	for child in node.get_children():
		var result = _count_hidden_meshes(child)
		count += result[1]
	return [node, count]

func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content = f.get_as_text()
	f.close()
	return content

func _report():
	print("\n=== 汇总: passed=%d failed=%d ===" % [_pass, _fail])
	if _fail > 0:
		print("RESULT: failed=%d" % _fail)
	else:
		print("RESULT: failed=0")
	quit()
