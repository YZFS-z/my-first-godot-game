extends SceneTree
## 测试：KV-1 内置坦克（source=builtin + glb 模型）的数据加载、炮管俯仰、炮镜网格隐藏
## 覆盖：
## 1. KV-1 作为内置载具加载（source=builtin），glb 模型作为 ImportedModel 加载
## 2. 内置占位网格被隐藏，glb 炮管自动 reparent 到 gun_node
## 3. 真实数据校验（武器 gun_76mm_zis5, 苏联, ww2, 装甲数值）
## 4. 导入炮管随 gun_node 俯仰移动
## 5. 开镜后所有 GeometryInstance3D 被隐藏，关镜后恢复

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
	print("=== check_kv1_builtin ===")
	_test_runtime()

func _test_runtime():
	var gm = root.get_node("GameManager")
	gm.selected_map_id = "map_valley"
	gm.selected_vehicle_id = "tank_kv1"

	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame

	var spawner = main.get_node_or_null("VehicleSpawner")
	var player_vehicle = spawner.get("player_vehicle") if spawner else null
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

	# 1. 验证 ImportedModel 存在（glb 模型加载）
	var imported = player_vehicle.get_node_or_null("ImportedModel")
	_check(imported != null, "glb 模型已加载（ImportedModel 存在）")

	# 2. 验证内置占位网格被隐藏
	var hull = player_vehicle.get_node_or_null("Hull")
	if hull:
		_check(not hull.visible, "内置 Hull 网格已隐藏（glb 模型替代）")
	else:
		_check(false, "内置 Hull 节点不存在")

	var turret_mesh = player_vehicle.get_node_or_null("Turret/TurretMesh")
	if turret_mesh:
		_check(not turret_mesh.visible, "内置 TurretMesh 已隐藏")
	else:
		_check(false, "Turret/TurretMesh 节点不存在")

	# 3. 验证 Turret/Gun 节点结构
	var turret = player_vehicle.get_node_or_null("Turret")
	_check(turret != null, "Turret 节点存在")

	var gun_node = player_vehicle.get("gun_node")
	_check(gun_node != null, "gun_node 存在")

	# 4. 查找导入的炮管网格（非内置 GunMesh）
	var barrel_mesh: MeshInstance3D = null
	for child in gun_node.get_children():
		if child is MeshInstance3D and child.name != "GunMesh":
			barrel_mesh = child
			print("  导入炮管网格: %s" % child.name)
			break
	_check(barrel_mesh != null, "glb 炮管已 reparent 到 gun_node")

	# 内置 GunMesh 也应存在但被隐藏
	var gun_mesh = gun_node.get_node_or_null("GunMesh")
	if gun_mesh:
		_check(not gun_mesh.visible, "内置 GunMesh 已隐藏")

	# 5. 验证 KV-1 真实数据
	var vd = player_vehicle.get("vehicle_data")
	if not vd.is_empty():
		_check(vd.get("nation") == "USSR", "国籍为 USSR")
		_check(vd.get("era") == "ww2", "时代为 ww2")
		_check(vd.get("source") == "builtin", "source 为 builtin")

		var physics = vd.get("physics", {})
		_check(int(physics.get("mass", 0)) == 43000, "质量 43000kg")
		_check(abs(float(physics.get("max_speed", 0)) - 35.0) < 0.01, "最大速度 35km/h")

		var armor = vd.get("armor", {})
		_check(int(armor.get("hull_front", 0)) == 75, "车体正面装甲 75mm")
		_check(int(armor.get("turret_front", 0)) == 110, "炮塔正面装甲 110mm")

		var weapons = vd.get("weapons", [])
		if weapons.size() >= 2:
			_check(weapons[0].get("weapon_id") == "gun_76mm_zis5", "主炮为 gun_76mm_zis5")
			_check(int(weapons[0].get("ammo_capacity", 0)) == 114, "主炮弹药量 114")
			_check(weapons[1].get("weapon_id") == "mg_dt_762", "副武器为 mg_dt_762 机枪")
			_check(int(weapons[1].get("ammo_capacity", 0)) == 1000, "机枪弹药量 1000")
			_check(int(weapons[1].get("fire_rate", 0)) == 600, "机枪射速 600rpm")
			_check(abs(float(weapons[1].get("reload_time", 0)) - 0.1) < 0.001, "机枪射击间隔 0.1s (600rpm)")
		else:
			_check(false, "武器列表应 >= 2（主炮+机枪）")

		_check(int(vd.get("crew_count", 0)) == 5, "乘员 5 人")
	else:
		_check(false, "vehicle_data 为空")

	# 6. 测试导入炮管俯仰
	if barrel_mesh:
		var pos_before = barrel_mesh.global_position
		player_vehicle.set("gun_pitch", 15.0)
		player_vehicle.set("input_gun", 1.0)
		await physics_frame
		await physics_frame
		await physics_frame
		var pos_after = barrel_mesh.global_position
		var moved = pos_before.distance_to(pos_after) > 0.01
		_check(moved, "炮管俯仰时导入网格跟随移动 (移动距离=%.3f)" % pos_before.distance_to(pos_after))

	# 7. 开镜后检查所有 GeometryInstance3D 被隐藏
	if player_vehicle.has_method("_open_scope"):
		player_vehicle._open_scope()
		await physics_frame
		await physics_frame
		var visible_count = _count_visible_meshes(player_vehicle)
		print("  开镜后仍可见的 GeometryInstance3D: %d" % visible_count)
		_check(visible_count == 0, "开镜后所有网格被隐藏")

		# 关镜后恢复
		if player_vehicle.has_method("_close_scope"):
			player_vehicle._close_scope()
			await physics_frame
			await physics_frame
			var restored_count = _count_visible_meshes(player_vehicle)
			print("  关镜后恢复可见的 GeometryInstance3D: %d" % restored_count)
			_check(restored_count > 0, "关镜后网格恢复可见")

	# 8. 验证武器数据
	var dl = root.get_node_or_null("DataLoader")
	if dl:
		var weapon_data = dl.get_weapon("gun_76mm_zis5")
		if not weapon_data.is_empty():
			_check(int(weapon_data.get("caliber", 0)) == 76, "武器口径 76mm")
			var ammo_types = weapon_data.get("ammo_types", [])
			_check(ammo_types.size() >= 3, "弹药种类 >= 3 (APHEBC/APCR/HE)")
			if ammo_types.size() >= 3:
				_check(ammo_types[0].get("id") == "aphe_br350a", "弹药1: BR-350A APHEBC")
				_check(ammo_types[1].get("id") == "apcr_br350p", "弹药2: BR-350P APCR")
				_check(ammo_types[2].get("id") == "he_of350", "弹药3: OF-350 HE")
		else:
			_check(false, "gun_76mm_zis5 武器数据未加载")

		# 验证 DT 机枪武器数据
		var mg_data = dl.get_weapon("mg_dt_762")
		if not mg_data.is_empty():
			_check(int(mg_data.get("caliber", 0)) == 8, "机枪口径 7.62mm (caliber=8)")
			_check(mg_data.get("type") == "machine_gun", "武器类型为 machine_gun")
			var mg_ammo = mg_data.get("ammo_types", [])
			_check(mg_ammo.size() >= 3, "机枪弹药种类 >= 3 (穿甲/穿甲燃烧/曳光)")
			if mg_ammo.size() >= 3:
				_check(mg_ammo[0].get("id") == "dt_ap_762", "机枪弹药1: 7.62mm 穿甲弹")
				_check(mg_ammo[1].get("id") == "dt_ap_i_762", "机枪弹药2: 7.62mm 穿甲燃烧弹")
				_check(mg_ammo[2].get("id") == "dt_tracer_762", "机枪弹药3: 7.62mm 曳光弹")
		else:
			_check(false, "mg_dt_762 武器数据未加载")
	else:
		_check(false, "DataLoader 未注册")

	main.queue_free()
	_check(true, "KV-1 内置坦克测试完成")

	_report()

func _count_visible_meshes(node: Node) -> int:
	var count = 0
	if node is GeometryInstance3D and node.visible:
		count += 1
	for child in node.get_children():
		count += _count_visible_meshes(child)
	return count

func _report():
	print("\n=== 汇总: passed=%d failed=%d ===" % [_pass, _fail])
	if _fail > 0:
		print("RESULT: failed=%d" % _fail)
	else:
		print("RESULT: failed=0")
	quit()
