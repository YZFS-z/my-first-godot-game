extends RefCounted
## 统一 3D 模型导入映射器（ModelMapper）
## ============================================================
## 把 glb/tscn 外部模型的部件（炮塔/炮管/炮口）映射到游戏载具骨架，
## 集中管理所有导入映射逻辑，配置驱动 + 自动识别兜底。
##
## 阶段划分（load_and_map 依次执行）：
##   1. 加载场景（glb/gltf 用 GLTFDocument 运行时加载；tscn/scn 用 load()）
##   2. 基础变换（scale 缩放 + offset 整体平移）
##   3. 隐藏内置模型（骨架占位网格）
##   4. 材质修复（glb 默认双面渲染 → 强制背面剔除）
##   5. 部件识别（Turret/Turret1 炮塔、Gun/gun 炮管）
##   6. 前方对齐（按 Gun 相对 Turret 方向绕 Y 旋转到游戏 -Z，yaw_offset 可覆盖）
##   7. 炮塔/炮管映射（pivot 定位、muzzle 识别、reparent 挂载、自动炮管识别）
##   8. 碰撞盒覆盖（collision_size / collision_offset）
##
## 配置约定（载具 JSON 的 model 字段，全部可选、向后兼容）：
##   scale / offset / yaw_offset / turret_pivot / gun_pivot / muzzle_offset
##   scope_camera_z / barrel_length / collision_size / collision_offset
##
## 用法：
##   var mapper = preload("res://scripts/vehicles/model_mapper.gd").new()
##   mapper.load_and_map(vehicle, model_config)

# ============ 主入口 ============

func load_and_map(vehicle, model_config: Dictionary) -> bool:
	"""执行完整导入映射。返回是否成功。"""
	var model_instance: Node = _load_scene(model_config)
	if model_instance == null:
		return false
	_apply_basic_transform(model_instance, model_config)
	model_instance.name = "ImportedModel"
	# 先隐藏所有内置模型（此时自定义模型还未添加，Turret/Gun 子节点也还未移动，
	# 所以找到的都是内置模型；额外隐藏已知内置节点确保 find_children 不漏）
	_hide_builtin_meshes(vehicle)
	vehicle.add_child(model_instance)
	# 修复 glb 材质：强制背面剔除（很多软件导出 doubleSided=true，可透视车体内部）
	_fix_materials(model_instance)
	# 部件识别（炮塔/炮管）
	var parts: Dictionary = _identify_parts(model_instance, model_config)
	# 自动对齐模型前方到游戏 -Z 轴
	_align_model_yaw(model_instance, parts, model_config)
	# 炮塔/炮管/炮口映射
	_map_turret_gun(vehicle, parts, model_config)
	# 碰撞盒覆盖
	_map_collision(vehicle, model_config)
	return true

# ============ 阶段 1：加载场景 ============

func _load_scene(model_config: Dictionary) -> Node:
	var scene_path: String = model_config.get("scene_path", "")
	if scene_path == "":
		return null
	var ext: String = scene_path.get_extension().to_lower()
	if ext in ["glb", "gltf"]:
		# 优先用 load()：Godot 已导入的 glb 是 PackedScene，导出 EXE 的 pck 里可用；
		# 旧实现用 append_from_file 读原始 glb 文件字节，导出后 pck 没有原始文件会加载失败回退内置模型。
		var res = load(scene_path)
		if res is PackedScene:
			return (res as PackedScene).instantiate()
		# 回退：运行时复制的未导入 glb/gltf（如 user:// 下）用 GLTFDocument 解析
		if FileAccess.file_exists(scene_path):
			var gltf = GLTFDocument.new()
			var state = GLTFState.new()
			var err = gltf.append_from_file(scene_path, state, 0, "")
			if err == OK:
				var inst: Node = gltf.generate_scene(state)
				if inst:
					return inst
		push_warning("[ModelMapper] Failed to load GLTF: %s" % scene_path)
		return null
	# tscn/scn 等已导入的资源用 load()
	var model_scene = load(scene_path)
	if not model_scene:
		push_warning("[ModelMapper] Failed to load model: %s" % scene_path)
		return null
	return model_scene.instantiate()

# ============ 阶段 2：基础变换 ============

func _apply_basic_transform(model_instance: Node, model_config: Dictionary) -> void:
	"""scale 等比缩放 + offset 整体平移（载具局部坐标）。
	offset 用于 glb 轮底不在载具原点时上移贴合地面；offset 是叠加（+=）非覆盖，
	避免破坏后续 yaw 对齐补偿。"""
	var scale: float = model_config.get("scale", 1.0)
	model_instance.scale = Vector3(scale, scale, scale)
	if model_config.has("offset") and model_instance is Node3D:
		var off: Array = model_config["offset"]
		(model_instance as Node3D).position += Vector3(float(off[0]), float(off[1]), float(off[2]))

# ============ 阶段 3：隐藏内置模型 ============

func _hide_builtin_meshes(vehicle) -> void:
	"""隐藏 vehicle.tscn 骨架的内置占位网格（Hull/Track/TurretMesh/GunMesh 等）。"""
	for child in vehicle.find_children("*", "MeshInstance3D", true, false):
		child.visible = false
	var known_meshes: Array = ["Hull", "Trackleft", "Trackright", "Turret/TurretMesh", "Turret/Gun/GunMesh"]
	for mesh_path in known_meshes:
		var mesh_node = vehicle.get_node_or_null(mesh_path)
		if mesh_node:
			mesh_node.visible = false

# ============ 阶段 4：材质修复 ============

func _fix_materials(model_instance: Node) -> void:
	"""强制背面剔除：很多 3D 软件导出 glb 时默认 doubleSided=true，
	Godot 映射为 CULL_DISABLED，导致从特定角度能透视车体/炮塔内部。"""
	for mi in model_instance.find_children("*", "MeshInstance3D", true, false):
		for i in range(mi.get_surface_override_material_count()):
			var mat = mi.get_active_material(i)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK

# ============ 阶段 5：部件识别 ============

func _identify_parts(model_instance: Node, _model_config: Dictionary) -> Dictionary:
	"""识别模型中的关键部件，返回 {turret, gun}。
	turret：优先 Turret，兼容 Turret1（AH-64 机头主炮塔，Turret2 是副武器挂架不识别）；
	gun：优先在 turret 子树查找 Gun/gun，再全局查找（大小写兼容不同建模软件命名；
	兼容 "gun1" —— 固定翼机头机炮（A-10 等，gun2 是导弹挂架不识别为炮管）。"""
	var parts: Dictionary = {}
	var turret: Node = model_instance.find_child("Turret", true, false)
	if not turret:
		turret = model_instance.find_child("Turret1", true, false)
	parts["turret"] = turret
	var gun: Node = null
	if turret is Node3D:
		gun = _find_child_named(turret, ["Gun", "gun"])
	if not gun:
		gun = _find_child_named(model_instance, ["Gun", "gun", "gun1"])
	parts["gun"] = gun
	return parts

func _find_child_named(parent: Node, names: Array) -> Node:
	"""在 parent 子树中递归查找名字匹配 names 任一（大小写敏感，逐字匹配）的节点。"""
	for child in parent.get_children():
		if str(child.name) in names:
			return child
		var found := _find_child_named(child, names)
		if found:
			return found
	return null

# ============ 阶段 6：前方对齐 ============

func _align_model_yaw(model_instance: Node, parts: Dictionary, model_config: Dictionary) -> void:
	"""自动对齐模型前方到游戏 -Z 轴。
	很多建模软件以 X/Y 为车头方向导出，通过 Gun 相对 Turret 的偏移方向检测炮管指向，
	绕 Y 整体旋转模型对齐，否则炮管横置/缩进炮塔。yaw_offset 配置可覆盖自动判断。"""
	var model_yaw_offset := 0.0
	if model_config.has("yaw_offset"):
		model_yaw_offset = float(model_config["yaw_offset"])
	else:
		model_yaw_offset = _get_model_yaw_align_angle(model_instance, parts.get("turret"), parts.get("gun"))
	if abs(model_yaw_offset) <= 0.02:
		return
	var mi3d := model_instance as Node3D
	if mi3d == null:
		return
	# 绕模型 AABB 中心旋转，避免整车平移
	var center: Vector3 = _get_model_aabb_center(model_instance)
	var center_global: Vector3 = mi3d.to_global(center)
	mi3d.rotate_y(model_yaw_offset)
	var new_center: Vector3 = mi3d.to_global(_get_model_aabb_center(model_instance))
	mi3d.global_position += center_global - new_center
	print("[ModelMapper] 模型整体旋转 %.1f° 对齐前方到 -Z" % rad_to_deg(model_yaw_offset))

func _get_model_aabb_center(model_instance: Node) -> Vector3:
	"""计算 model_instance 下所有 MeshInstance3D 在模型局部坐标的合并 AABB 中心。
	Node3D 基类没有 get_aabb()（那是 VisualInstance3D 的方法），需遍历子网格合并。"""
	var mi3d := model_instance as Node3D
	if mi3d == null:
		return Vector3.ZERO
	var combined := AABB()
	var has := false
	for mi in model_instance.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m and m.mesh:
			# Transform3D * AABB：变换到 model_instance 局部坐标系（轴对齐重算）
			var local_aabb: AABB = mi3d.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			if not has:
				combined = local_aabb
				has = true
			else:
				combined = combined.merge(local_aabb)
	if not has:
		return Vector3.ZERO
	return combined.get_center()

func _get_model_yaw_align_angle(model_instance: Node3D, model_turret: Node, model_gun: Node) -> float:
	"""计算模型需要绕 Y 旋转的角度，使炮管对齐游戏前方 -Z。
	利用 Gun 相对 Turret 的偏移方向作为炮管指向（耳轴→炮口）。
	返回弧度；无法判断时返回 0。"""
	if not (model_turret is Node3D and model_gun is Node3D):
		return 0.0
	var t3 := model_turret as Node3D
	var g3 := model_gun as Node3D
	var offset := g3.global_position - t3.global_position
	var dir := Vector3(offset.x, 0.0, offset.z)
	if dir.length() < 0.05:
		return 0.0  # 炮管几乎竖直，无法判断水平朝向
	return dir.normalized().signed_angle_to(Vector3(0, 0, -1), Vector3.UP)

# ============ 阶段 7：炮塔/炮管/炮口映射 ============

func _map_turret_gun(vehicle, parts: Dictionary, model_config: Dictionary) -> void:
	"""炮塔/炮管映射核心：
	  1. 设置炮塔旋转中心（turret_node.position = turret_pivot）
	  2. 设置炮管俯仰中心（gun_node.position = gun_pivot，相对炮塔）
	  3. 自动识别炮口位置（muzzle_node，从炮管 AABB 或配置）
	  4. Reparent 炮塔网格 → turret_node（Turret1+gun_pivot 特例挂 gun_node，跟随 yaw+pitch）
	  5. Reparent 炮管网格 → gun_node
	  5.5. 无 Gun 节点时自动识别细长炮管网格 → gun_node
	"""
	var model_turret: Node = parts.get("turret")
	var model_gun: Node = parts.get("gun")

	# 1. 设置炮塔旋转中心
	if model_turret and vehicle.turret_node:
		var turret_pivot: Vector3
		if model_config.has("turret_pivot"):
			var tp: Array = model_config["turret_pivot"]
			turret_pivot = Vector3(float(tp[0]), float(tp[1]), float(tp[2]))
		elif model_turret is MeshInstance3D and (model_turret as MeshInstance3D).mesh:
			# 以模型为准：AH-64 等部件节点在原点、mesh 顶点在别处，
			# 用 mesh AABB 中心作为炮塔旋转中心（比节点 global_position 准确）
			var mesh_center: Vector3 = (model_turret as Node3D).to_global((model_turret as MeshInstance3D).get_aabb().get_center())
			turret_pivot = vehicle.to_local(mesh_center)
			print("[ModelMapper] Turret pivot 自动（mesh 中心）: (%.2f, %.2f, %.2f)" % [turret_pivot.x, turret_pivot.y, turret_pivot.z])
		else:
			turret_pivot = vehicle.to_local(model_turret.global_position)
		vehicle.turret_node.position = turret_pivot
		vehicle.turret_node.rotation = Vector3.ZERO
		print("[ModelMapper] Turret pivot: (%.2f, %.2f, %.2f)" % [turret_pivot.x, turret_pivot.y, turret_pivot.z])

	# 2. 设置炮管俯仰中心（相对于炮塔）。
	# 无 Gun 节点时（如 AH-64 机头炮塔为整体网格）仍可按 gun_pivot 配置定位炮管/炮口
	if vehicle.gun_node and (model_gun or model_config.has("gun_pivot")):
		var gun_pivot := Vector3.ZERO
		if model_gun and model_turret is Node3D:
			gun_pivot = (model_turret as Node3D).to_local(model_gun.global_position)
		if model_config.has("gun_pivot"):
			var gp: Array = model_config["gun_pivot"]
			gun_pivot = Vector3(float(gp[0]), float(gp[1]), float(gp[2]))
		vehicle.gun_node.position = gun_pivot
		vehicle.gun_node.rotation = Vector3.ZERO
		print("[ModelMapper] Gun pivot: (%.2f, %.2f, %.2f)" % [gun_pivot.x, gun_pivot.y, gun_pivot.z])

		# 3. 自动识别炮口位置（从炮管网格 AABB 或配置）
		var scope_cam_z := -0.5  # 默认炮镜位置（炮尾后方 0.5m）
		if model_config.has("muzzle_offset"):
			var mo: Array = model_config["muzzle_offset"]
			vehicle.muzzle_node.position = Vector3(float(mo[0]), float(mo[1]), float(mo[2]))
		elif model_gun is MeshInstance3D and model_gun.mesh:
			# 用 AABB 8 角点变换到 gun_node 本地坐标，正确计算 Z 范围
			var aabb_gun = model_gun.get_aabb()
			var min_z_g := 0.0
			var max_z_g := 0.0
			var first_g := true
			for sx in [0.0, 1.0]:
				for sy in [0.0, 1.0]:
					for sz in [0.0, 1.0]:
						var corner = aabb_gun.position + Vector3(aabb_gun.size.x * sx, aabb_gun.size.y * sy, aabb_gun.size.z * sz)
						var local_pos = vehicle.gun_node.to_local(model_gun.to_global(corner))
						if first_g:
							min_z_g = local_pos.z
							max_z_g = local_pos.z
							first_g = false
						else:
							min_z_g = min(min_z_g, local_pos.z)
							max_z_g = max(max_z_g, local_pos.z)
			vehicle.muzzle_node.position = Vector3(0, 0, min_z_g)
			scope_cam_z = max_z_g + 0.3
			print("[ModelMapper] Muzzle auto-detected: Z=%.2f" % min_z_g)
		if model_config.has("scope_camera_z"):
			scope_cam_z = float(model_config["scope_camera_z"])
		# 存储到载具，供 tank.gd _setup_scope() 读取
		vehicle.set_meta("scope_camera_z", scope_cam_z)
		print("[ModelMapper] Scope camera Z offset: %.2f" % scope_cam_z)

	# 4. Reparent 炮塔网格 → turret_node（位置归零，保留旋转/缩放）。
	# 特例：机头主炮塔 Turret1 是"炮塔+炮管"整体网格，配置了 gun_pivot 时应挂到
	# gun_node，使炮塔跟随瞄准的 yaw+pitch（机头炮塔整体俯仰），而非只跟随 yaw。
	if model_turret and vehicle.turret_node:
		if model_turret.name == "Turret1" and model_config.has("gun_pivot") and vehicle.gun_node:
			_reparent_mesh_to_node(model_turret, vehicle.gun_node)
			print("[ModelMapper] Turret1 挂到 gun_node（跟随 yaw+pitch）")
			# Turret1 是"炮塔+炮管"整体网格，节点 origin 原本在模型 offset 处（远离 gun_node），
			# 保留全局位姿后 gun 俯仰会使 origin 绕 gun_node 大半径公转（炮塔浮空/朝向错乱）。
			# 直接整体平移 Turret1，使 mesh 全局中心对齐 gun_node 耳轴——俯仰绕耳轴正确旋转。
			# 用 to_global(get_aabb().get_center()) 取 mesh 真实世界中心（比 global_transform * aabb 更准，
			# 后者在含 scale/rotation 时对 AABB 取包围盒中心而非 mesh 实际中心）。
			if model_turret is MeshInstance3D and model_turret.mesh:
				var aabb := (model_turret as MeshInstance3D).get_aabb()
				var cur_center: Vector3 = (model_turret as Node3D).to_global(aabb.get_center())
				var delta: Vector3 = vehicle.gun_node.global_position - cur_center
				(model_turret as Node3D).global_position += delta
				print("[ModelMapper] Turret1 mesh 中心对齐 gun_node 耳轴 delta=(%.2f, %.2f, %.2f)" % [delta.x, delta.y, delta.z])
		else:
			_reparent_mesh_to_node(model_turret, vehicle.turret_node)
	# 5. Reparent 炮管网格 → gun_node
	if model_gun and vehicle.gun_node:
		_reparent_mesh_to_node(model_gun, vehicle.gun_node)
	# 5.5. 如果 glb 中没有 Gun 节点，自动识别炮管网格（细长形状）并 reparent 到 gun_node。
	# 配置了 gun_pivot 的模型（如 AH-64 机头炮塔为整体网格）用配置定位炮管/炮口，不做自动识别
	if not model_gun and not model_config.has("gun_pivot") and vehicle.gun_node and vehicle.turret_node:
		var barrel: MeshInstance3D = _find_gun_barrel_under_turret(vehicle.turret_node)
		if barrel:
			# 用 global_transform 保持世界位置不变——炮管可能是有旋转/缩放的 Turret 子节点，
			# 只保留 local transform 会丢失父节点变换，导致位置和方向错误
			var saved_global := barrel.global_transform
			var saved_scale := barrel.scale
			var old_parent := barrel.get_parent()
			if old_parent:
				old_parent.remove_child(barrel)
			vehicle.gun_node.add_child(barrel)
			barrel.owner = vehicle.gun_node
			barrel.global_transform = saved_global
			# 修正炮管方向：glb 中炮管可能继承父节点（Turret）的复杂旋转和非均匀缩放，
			# reparent 后 local rotation 可能很大（~90°）。重置 rotation 为 (PI/2,0,0)，
			# 使圆柱体 mesh 的 Y 轴映射到 -Z（前方），保留 scale，position 由 global_transform 保持。
			barrel.rotation = Vector3(PI / 2, 0.0, 0.0)
			barrel.scale = saved_scale
			print("[ModelMapper] Auto-detected gun barrel: %s (reparented, rotation corrected)" % barrel.name)
			# 修正炮管 pivot：真实炮管应以 gun_node（耳轴）为俯仰中心、从耳轴向车头前方伸出。
			# 若炮管 mesh 以自身中心为 pivot，长炮管会有一半伸到车尾（KV-1 曾如此）。
			# 按配置 barrel_length 压缩长度 + 平移使炮尾对齐耳轴，再补算炮口/炮镜。
			if barrel.mesh:
				_fix_auto_barrel_pivot(barrel, vehicle.gun_node, model_config)
				var zr := _calc_auto_barrel_z_range(barrel, vehicle.gun_node)
				var min_z: float = zr[0]
				var max_z: float = zr[1]
				# 炮口在最负 Z 端，炮镜在炮尾端（最正 Z）略向后退
				vehicle.muzzle_node.position = Vector3(0, 0, min_z)
				var scope_cam_z := max_z + 0.3
				if model_config.has("scope_camera_z"):
					scope_cam_z = float(model_config["scope_camera_z"])
				vehicle.set_meta("scope_camera_z", scope_cam_z)
				print("[ModelMapper] Muzzle auto-detected from barrel: Z=%.2f, scope Z=%.2f" % [min_z, scope_cam_z])

func _reparent_mesh_to_node(source_node: Node, target_parent: Node3D) -> void:
	"""将 glb 中的 Turret/Gun 节点移动到载具骨架的对应节点。
	MeshInstance3D：保留全局位姿（含整体对齐旋转与缩放），pivot 节点已在正确位置。
	Node3D 容器：子节点保留各自的全局位姿。"""
	if source_node is MeshInstance3D:
		var saved_global := (source_node as MeshInstance3D).global_transform
		var old_parent := source_node.get_parent()
		if old_parent:
			old_parent.remove_child(source_node)
		target_parent.add_child(source_node)
		source_node.owner = target_parent
		# 保留全局位姿：整体对齐旋转不丢失，炮管仍指向 -Z
		(source_node as MeshInstance3D).global_transform = saved_global
	else:
		for child in source_node.get_children():
			if child is Node3D:
				var saved_global := (child as Node3D).global_transform
				source_node.remove_child(child)
				target_parent.add_child(child)
				child.owner = target_parent
				(child as Node3D).global_transform = saved_global
			else:
				var saved_transform = child.transform
				source_node.remove_child(child)
				target_parent.add_child(child)
				child.owner = target_parent
				child.transform = saved_transform
		source_node.queue_free()

# ============ 自动炮管识别（无 Gun 节点的模型） ============

func _find_gun_barrel_under_turret(turret_node: Node3D) -> MeshInstance3D:
	"""递归搜索 turret_node 子树中形状细长的 MeshInstance3D（炮管）。
	跳过内置网格（TurretMesh/GunMesh）和 gun_node 子树。
	判断标准：AABB 最长边 > 3× 最短边，且最长边 > 0.5m"""
	var skip_names: Array = ["TurretMesh", "GunMesh"]
	var gun_node := turret_node.get_node_or_null("Gun")
	var best: MeshInstance3D = null
	var best_ratio: float = 0.0
	for child in turret_node.get_children():
		# 跳过 gun_node 子树（避免把已 reparent 的炮管重复移动）
		if child == gun_node:
			continue
		if child is MeshInstance3D and not child.name in skip_names:
			var result := _check_mesh_elongated(child)
			if result[0] and result[1] > best_ratio:
				best = child
				best_ratio = result[1]
		# 递归搜索子节点
		if not child is MeshInstance3D or not (child.name in skip_names):
			var sub := _find_gun_barrel_recursive(child, gun_node, skip_names)
			if sub:
				var result := _check_mesh_elongated(sub)
				if result[0] and result[1] > best_ratio:
					best = sub
					best_ratio = result[1]
	return best

func _find_gun_barrel_recursive(node: Node, gun_node: Node, skip_names: Array) -> MeshInstance3D:
	if node == gun_node:
		return null
	if node is MeshInstance3D and not node.name in skip_names:
		var result := _check_mesh_elongated(node)
		if result[0]:
			return node
	for child in node.get_children():
		var found := _find_gun_barrel_recursive(child, gun_node, skip_names)
		if found:
			return found
	return null

func _check_mesh_elongated(mi: MeshInstance3D) -> Array:
	"""检查网格是否细长（炮管形状）。返回 [bool, float] = [是否细长, 长短比]"""
	if mi.mesh == null:
		return [false, 0.0]
	var aabb := mi.get_aabb()
	var s := aabb.size
	var max_dim: float = maxf(s.x, maxf(s.y, s.z))
	var min_dim: float = minf(s.x, minf(s.y, s.z))
	if min_dim < 0.001:
		return [false, 0.0]
	var ratio: float = max_dim / min_dim
	return [ratio > 3.0 and max_dim > 0.5, ratio]

func _calc_auto_barrel_z_range(barrel: MeshInstance3D, gun_node: Node3D) -> Array:
	"""用 mesh 真实顶点计算炮管在 gun_node 局部坐标的 Z 范围 [min_z, max_z]。
	比 AABB 8 角点法更准确——AABB 可能被非炮管几何（如单位立方体部件）撑大。"""
	if barrel.mesh == null:
		return [0.0, 0.0]
	var min_z := 0.0
	var max_z := 0.0
	var first := true
	for s in barrel.mesh.get_surface_count():
		var arr := barrel.mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in verts:
			var lp: Vector3 = gun_node.to_local(barrel.to_global(v))
			if first:
				min_z = lp.z
				max_z = lp.z
				first = false
			else:
				min_z = min(min_z, lp.z)
				max_z = max(max_z, lp.z)
	if first:
		return [0.0, 0.0]
	return [min_z, max_z]

func _fix_auto_barrel_pivot(barrel: MeshInstance3D, gun_node: Node3D, model_config: Dictionary) -> void:
	"""自动识别炮管的 pivot 修正：
	1) 若配置 barrel_length（目标炮管长度/米），按比例缩放 barrel.scale.y——
	   因强制 rotation=(PI/2,0,0) 后 mesh 的 Y 轴映射到 gun_node 的 Z 轴（炮管长度方向）。
	   对 KV-1 这类 mesh 过长/缩放异常的模型，可把 6.65m 长炮管压回真实长度。
	2) 沿 Z 平移使炮尾（最正 Z）对齐 gun_node 局部 z=0（耳轴），
	   使炮管从耳轴向车头前方伸出，避免以 mesh 中心为 pivot 贯穿车身。"""
	if barrel.mesh == null:
		return
	var zr := _calc_auto_barrel_z_range(barrel, gun_node)
	var min_z: float = zr[0]
	var max_z: float = zr[1]
	if min_z == 0.0 and max_z == 0.0:
		return
	# 1) 缩放炮管长度到目标值（配置 barrel_length，允许放大或缩小）
	if model_config.has("barrel_length"):
		var target_len := float(model_config["barrel_length"])
		var cur_len := max_z - min_z
		if target_len > 0.1 and cur_len > 0.1 and abs(target_len - cur_len) > 0.05:
			barrel.scale.y *= target_len / cur_len
			zr = _calc_auto_barrel_z_range(barrel, gun_node)
			min_z = zr[0]
			max_z = zr[1]
	# 2) 平移炮尾对齐耳轴
	var offset := max_z
	if abs(offset) > 0.001:
		barrel.position.z -= offset

# ============ 阶段 8：碰撞盒覆盖 ============

func _map_collision(vehicle, model_config: Dictionary) -> void:
	"""按 model.collision_size 覆盖骨架碰撞盒（真实尺寸模型匹配）。
	vehicle.tscn 默认碰撞盒较小（3.6×1.2×6），glb 车体更长/更高时车头车尾无碰撞。
	配置格式：collision_size=[宽,高,长]、collision_offset=[x,y,z]（盒中心，载具局部坐标）。"""
	if not model_config.has("collision_size"):
		return
	var cs: Array = model_config["collision_size"]
	var col = vehicle.get_node_or_null("CollisionShape3D")
	if col and col.shape is BoxShape3D:
		(col.shape as BoxShape3D).size = Vector3(float(cs[0]), float(cs[1]), float(cs[2]))
		if model_config.has("collision_offset"):
			var co: Array = model_config["collision_offset"]
			col.position = Vector3(float(co[0]), float(co[1]), float(co[2]))
		else:
			col.position = Vector3(0, float(cs[1]) * 0.5, 0)
		print("[ModelMapper] Collision box overridden: size=(%.1f, %.1f, %.1f) at %s" % [
			float(cs[0]), float(cs[1]), float(cs[2]), col.position.round()])
