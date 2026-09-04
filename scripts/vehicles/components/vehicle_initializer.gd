extends Node
## 载具初始化与视觉 - 数据加载、模型加载、模块创建、昵称、移动端增强
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态
##
## 3D 模型导入映射逻辑已抽离到 scripts/vehicles/model_mapper.gd（ModelMapper），
## 本文件仅负责：加载数据 → 调 ModelMapper 完成模型导入映射 → 模块/武器/昵称等。

var _model_mapper: RefCounted = null

func _get_vehicle() -> Node:
	return get_parent()

func setup_from_data(data: Dictionary) -> void:
	var v = _get_vehicle()
	v.vehicle_data = data
	v.vehicle_id = data.get("id", "")
	apply_physics_params(data.get("physics", {}))
	load_model_from_data(data.get("model", {}))
	create_modules_from_data(data.get("modules", []))
	v._setup_weapons(data.get("weapons", []))
	v._setup_skills()
	v._setup_ammo()

func load_vehicle_data(id: String) -> void:
	var v = _get_vehicle()
	var data = DataLoader.get_vehicle(id)
	if not data.is_empty():
		setup_from_data(data)

func apply_physics_params(physics: Dictionary) -> void:
	var v = _get_vehicle()
	v.max_speed = float(physics.get("max_speed", 50.0)) / 3.6
	v.max_reverse_speed = float(physics.get("max_reverse_speed", -10.0)) / 3.6
	v.acceleration = physics.get("acceleration", 3.0)
	v.deceleration = physics.get("deceleration", 5.0)
	v.turn_rate = physics.get("turn_rate", 30.0)
	v.turret_turn_rate = physics.get("turret_turn_rate", 40.0)
	v.brake_force = physics.get("brake_force", 6.0)
	v.crash_impact_scale = float(physics.get("crash_impact_scale", 1.0))
	v.crash_no_spall = bool(physics.get("crash_no_spall", false))

func load_model_from_data(model_config: Dictionary) -> void:
	"""加载并映射外部 3D 模型（glb/tscn）到载具骨架。
	实际导入映射逻辑（部件识别/对齐/挂载/炮口/碰撞）在 ModelMapper.load_and_map()。"""
	var v = _get_vehicle()
	var scene_path: String = model_config.get("scene_path", "")
	if scene_path == "":
		return
	# 导出 EXE 后 pck 里没有原始 glb 文件，FileAccess.file_exists 会返回 false 导致外部模型被跳过；
	# 用 ResourceLoader.exists()（能识别已导入的 glb 资源）或文件存在兜底，保证导出后仍能加载外部模型。
	if not ResourceLoader.exists(scene_path) and not FileAccess.file_exists(scene_path):
		return
	if _model_mapper == null:
		_model_mapper = preload("res://scripts/vehicles/model_mapper.gd").new()
	if _model_mapper.load_and_map(v, model_config):
		print("[Vehicle] Loaded external model: %s" % scene_path)
	apply_mobile_visibility_boost()

func apply_mobile_visibility_boost() -> void:
	var v = _get_vehicle()
	if v._get_mobile_controls() == null:
		return
	var rim_shader = load("res://scripts/vehicles/mobile_rim.gdshader")
	if rim_shader == null:
		push_warning("[Vehicle] 机体轮廓 shader 加载失败，跳过可见性增强")
		return
	var count := 0
	for node in v.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		var base: Material = mi.get_active_material(0)
		var base_col := Color(0.55, 0.6, 0.65)
		if base is StandardMaterial3D:
			base_col = (base as StandardMaterial3D).albedo_color.lightened(0.15)
		var mat := ShaderMaterial.new()
		mat.shader = rim_shader
		mat.set_shader_parameter("base_color", base_col)
		mi.material_override = mat
		count += 1
	if count > 0:
		print("[Vehicle] Mobile visibility boost applied to %d meshes" % count)

func setup_damage_system() -> void:
	var v = _get_vehicle()
	v.damage_system = v.DamageSystem.new()
	v.damage_system.name = "DamageSystem"
	v.add_child(v.damage_system)
	v.damage_system.vehicle_destroyed.connect(v._on_vehicle_destroyed)
	v.damage_system.ammo_exploded.connect(v._on_ammo_exploded)
	v.damage_system.ammo_rack_damaged.connect(v._on_ammo_rack_damaged)

func setup_visual_nodes() -> void:
	var v = _get_vehicle()
	v.turret_node = v.get_node_or_null("Turret") as Node3D
	v.gun_node = v.get_node_or_null("Turret/Gun") as Node3D
	v.muzzle_node = v.get_node_or_null("Turret/Gun/Muzzle") as Node3D

func setup_nickname() -> void:
	var v = _get_vehicle()
	v.nickname_label = Label3D.new()
	v.nickname_label.name = "NicknameLabel"
	v.nickname_label.text = v.nickname
	v.nickname_label.position = Vector3(0, 3.5, 0)
	v.nickname_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	v.nickname_label.font_size = 48
	v.nickname_label.outline_size = 4
	v.nickname_label.outline_modulate = Color(0, 0, 0, 0.8)
	v.nickname_label.modulate = get_team_color()
	v.nickname_label.no_depth_test = true
	v.add_child(v.nickname_label)

func set_nickname(name: String) -> void:
	var v = _get_vehicle()
	v.nickname = name
	if v.nickname_label:
		v.nickname_label.text = name

func get_team_color() -> Color:
	var v = _get_vehicle()
	if v.team == 1:
		return Color(0.3, 1.0, 0.4)
	else:
		return Color(1.0, 0.3, 0.3)

func create_modules_from_data(modules_data: Array) -> void:
	var v = _get_vehicle()
	for mod_data in modules_data:
		var mod = v.Module.new()
		mod.module_name = mod_data.get("name", "unknown")
		mod.display_name = mod_data.get("display_name", mod_data.get("name", "unknown"))
		mod.max_health = mod_data.get("max_health", 100.0)
		mod.armor_thickness = mod_data.get("armor_thickness", 10.0)
		mod.is_critical = mod_data.get("is_critical", false)
		mod.performance_falloff = float(mod_data.get("performance_falloff", 0.5))
		mod.name = "Module_%s" % mod.module_name
		mod.owner_vehicle = v
		var pos = mod_data.get("position", [0, 0, 0])
		mod.position = Vector3(pos[0], pos[1], pos[2])
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		var size = mod_data.get("size", [1.0, 1.0, 1.0])
		box.size = Vector3(size[0], size[1], size[2])
		col.shape = box
		mod.add_child(col)
		v.damage_system.add_child(mod)
		v.damage_system.register_module(mod)
