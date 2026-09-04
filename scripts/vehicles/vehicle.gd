extends CharacterBody3D
## 载具基类 - 所有载具（坦克、飞机、舰船）的基础
## 核心协调器：物理、移动、炮塔、自由视角、公共接口转发
## 子组件：VehicleInitializer / VehicleWeaponSystem / VehicleSkillSystem / VehicleRepairSystem / VehicleDamageHandler / VehicleNetworkSync

signal vehicle_destroyed()
signal health_changed(percent: float)
signal speed_changed(speed: float)
signal altitude_changed(altitude: float)
signal weapon_changed(index: int, weapon_id: String)
signal lock_status_changed(target: Node, locked: bool, distance: float)
signal skill_cooldown_changed(skill_id: String, remaining: float)
signal skill_activated(skill_id: String, target_pos: Vector3)

const DamageSystem = preload("res://scripts/core/damage_system.gd")
const Module = preload("res://scripts/core/module.gd")
const GRAVITY: float = 20.0
const CRASH_DAMAGE_COOLDOWN_FRAMES: int = 36
const CRASH_SPEED_MAX: float = 400.0
const FREE_LOOK_RESTORE_SPEED: float = 7.0

@export var vehicle_id: String = ""
@export var is_player_controlled: bool = false
@export var is_server_controlled: bool = true
@export var is_remote_ai: bool = false
@export var team: int = 1
@export var nickname: String = "玩家"
var network_player_id: String = ""

var vehicle_data: Dictionary = {}
var damage_system: DamageSystem = null
var turret_node: Node3D = null
var gun_node: Node3D = null
var muzzle_node: Node3D = null
# 配置生成的额外发射点（model.muzzles），如机翼两侧炮口。
# 非空时开火遍历全部发射点（每枪口一发），为空则回退到 muzzle_node 单发射。
var extra_muzzle_nodes: Array = []
# 副武器"左右交替"模式的轮换索引（muzzle_mode="alternate"，每次开火只用一个发射点、左右轮换）
var alternate_muzzle_index: int = 0
var nickname_label: Label3D = null
var fire_effect: Node = null
var has_exploded: bool = false

# 物理参数
var max_speed: float = 50.0
var max_reverse_speed: float = -10.0
var acceleration: float = 3.0
var deceleration: float = 5.0
var turn_rate: float = 30.0
var turret_turn_rate: float = 40.0
var brake_force: float = 6.0

# 地图边界
var map_half_size: float = 1000.0
var enforce_map_bounds: bool = true
var use_air_boundary: bool = false

# 运行时状态
var current_speed: float = 0.0
var target_speed: float = 0.0
var turret_yaw: float = 0.0
var gun_pitch: float = 0.0
var gun_elevation_min: float = -10.0
var gun_elevation_max: float = 20.0
var is_destroyed: bool = false

# 撞击损伤
var crash_speed_light: float = 12.0
var crash_speed_severe: float = 30.0
var crash_speed_fatal: float = 50.0
var _last_crash_frame: int = -9999
var crash_impact_scale: float = 1.0
var crash_no_spall: bool = false

# 弹药系统
var ammo_types: Array = []
var current_ammo_index: int = 0
var ammo_counts: Dictionary = {}
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_time: float = 6.0
var can_fire: bool = true

# 多武器槽
var weapon_slots: Array = []
var current_weapon_index: int = 0
var _weapon_states: Array = []

# 导弹锁定
var locked_target: Node3D = null
var is_locking: bool = false
var lock_progress: float = 0.0
var lock_range: float = 0.0
var lock_fov: float = 0.0
var lock_time: float = 1.0
var guidance_type: String = "none"
var _lock_search_timer: float = 0.0

# 维修系统
var is_repairing: bool = false
var repair_timer: float = 0.0
var repair_target: String = ""
var repair_duration: float = 8.0
var repair_cooldown: float = 0.0
var repair_ground_only_modules: Array[String] = []
var _repair_saved_pos: Vector3 = Vector3.ZERO
var _repair_saved_rot: float = 0.0
var _repair_saved_turret_rot: float = 0.0
var _repair_saved_gun_rot: float = 0.0
var killer: Node = null

# 自由视角
var is_free_look: bool = false
var free_look_yaw: float = 0.0
var free_look_pitch: float = 0.0

# 输入状态
var input_throttle: float = 0.0
var input_steering: float = 0.0
var input_turret: float = 0.0
var input_gun: float = 0.0
var input_fire: bool = false

# 网络远程状态
var net_target_position: Vector3 = Vector3.ZERO
var net_target_quat: Quaternion = Quaternion.IDENTITY
var net_target_turret_yaw: float = 0.0
var net_target_gun_pitch: float = 0.0
var net_has_state: bool = false
var net_speed: float = 0.0
var net_alpha: float = 0.0
var net_n_load: float = 1.0
var net_delta_a: float = 0.0
var net_delta_e: float = 0.0
var net_delta_r: float = 0.0
var net_throttle: float = 0.0
var net_destroyed: bool = false

# 技能系统
var skills: Dictionary = {}
var _skill_target_pos: Vector3 = Vector3.ZERO
var _pending_skill: String = ""

# 子组件引用
var _initializer: Node = null
var _weapon_system: Node = null
var _skill_system: Node = null
var _repair_system: Node = null
var _damage_handler: Node = null
var _network_sync: Node = null

# 地面对齐射线（四角 + 中心）
var _ground_rays: Array[RayCast3D] = []
var _ground_rays_ready: bool = false

func _ready() -> void:
	add_to_group("vehicle")
	# 动态创建子组件（子类实例也会包含这些组件）
	_create_components()
	_initializer.setup_damage_system()
	_initializer.setup_visual_nodes()
	_initializer.setup_nickname()
	if vehicle_id != "" and vehicle_data.is_empty():
		load_vehicle_data(vehicle_id)
	var parent = get_parent()
	if parent and "map_config" in parent:
		var boundary_key: String = "air_boundary_size" if use_air_boundary else "size"
		var map_size = float(parent.map_config.get(boundary_key, 2000.0))
		map_half_size = map_size * 0.5
	_setup_ground_rays()

func _setup_ground_rays() -> void:
	"""在碰撞盒四角 + 中心创建 RayCast3D 节点，用于多采样地面对齐。
	碰撞盒 size=(3.6, 1.2, 6.0)，底部在 local y=0。
	5 条射线分布在车体四角和中心，同时采样地面高度。"""
	# 四角 + 中心，y=1.0 略高于碰撞盒底部
	var positions := [
		Vector3(-1.6, 1.0, -2.5),   # 前左
		Vector3(1.6, 1.0, -2.5),    # 前右
		Vector3(-1.6, 1.0, 2.5),    # 后左
		Vector3(1.6, 1.0, 2.5),     # 后右
		Vector3(0, 1.0, 0),         # 中心
	]
	for i in range(positions.size()):
		var ray = RayCast3D.new()
		ray.name = "GroundRay_%d" % i
		ray.position = positions[i]
		ray.target_position = Vector3(0, -20, 0)  # 向下 20m
		ray.collision_mask = 1  # 地面层
		ray.enabled = true
		add_child(ray)
		_ground_rays.append(ray)
	_ground_rays_ready = true

func _create_components() -> void:
	_initializer = _add_component("VehicleInitializer", "res://scripts/vehicles/components/vehicle_initializer.gd")
	_weapon_system = _add_component("VehicleWeaponSystem", "res://scripts/vehicles/components/vehicle_weapon_system.gd")
	_skill_system = _add_component("VehicleSkillSystem", "res://scripts/vehicles/components/vehicle_skill_system.gd")
	_repair_system = _add_component("VehicleRepairSystem", "res://scripts/vehicles/components/vehicle_repair_system.gd")
	_damage_handler = _add_component("VehicleDamageHandler", "res://scripts/vehicles/components/vehicle_damage_handler.gd")
	_network_sync = _add_component("VehicleNetworkSync", "res://scripts/vehicles/components/vehicle_network_sync.gd")

func _add_component(name: String, script_path: String) -> Node:
	var node = Node.new()
	node.name = name
	var script = load(script_path)
	if script:
		node.script = script
	add_child(node)
	return node

# === 初始化与数据（转发到 VehicleInitializer） ===

func setup_from_data(data: Dictionary) -> void:
	_initializer.setup_from_data(data)
	_setup_extra_muzzles()

func _setup_extra_muzzles() -> void:
	"""按 model.muzzles 配置创建机翼等额外发射点（载具局部坐标），
	每个 Node3D 挂载具下、默认朝前（局部 -Z）。喷火等固定翼可用左右翼双炮口。"""
	for old in extra_muzzle_nodes:
		if is_instance_valid(old):
			old.queue_free()
	extra_muzzle_nodes.clear()
	var mz: Array = vehicle_data.get("model", {}).get("muzzles", [])
	for i in range(mz.size()):
		var m: Array = mz[i]
		if m.size() < 3:
			continue
		var n := Node3D.new()
		n.name = "MuzzleCfg%d" % i
		n.position = Vector3(float(m[0]), float(m[1]), float(m[2]))
		add_child(n)
		extra_muzzle_nodes.append(n)
	if not extra_muzzle_nodes.is_empty():
		print("[Vehicle] %s 配置了 %d 个机翼发射点" % [vehicle_id, extra_muzzle_nodes.size()])

func _get_muzzle_list() -> Array:
	"""返回本次开火的发射点列表。
	按当前武器 slot 的 muzzle_mode 选择：
	  "node"     → 用 muzzle_node（机头炮塔主武器，如 AH-64 Turret1）
	  "multi"    → 用 model.muzzles 多发射点（机翼挂架副武器齐射，每次齐射每枪口一发）
	  "alternate"→ 用 model.muzzles 但**左右交替**：每次只用一个发射点、轮换（弹药每次 1 发）
	未配置时保持旧行为：多发射点优先，否则回退到 muzzle_node。"""
	var mode := ""
	if current_weapon_index >= 0 and current_weapon_index < weapon_slots.size():
		mode = str(weapon_slots[current_weapon_index].get("muzzle_mode", ""))
	if mode == "node":
		if muzzle_node:
			return [muzzle_node]
	elif mode == "multi":
		if not extra_muzzle_nodes.is_empty():
			return extra_muzzle_nodes
	elif mode == "alternate":
		if not extra_muzzle_nodes.is_empty():
			var n: Node3D = extra_muzzle_nodes[alternate_muzzle_index % extra_muzzle_nodes.size()]
			alternate_muzzle_index = (alternate_muzzle_index + 1) % extra_muzzle_nodes.size()
			return [n]
	if not extra_muzzle_nodes.is_empty():
		return extra_muzzle_nodes
	if muzzle_node:
		return [muzzle_node]
	return []

func load_vehicle_data(id: String) -> void:
	_initializer.load_vehicle_data(id)

func _setup_weapons(weapons_data: Array) -> void:
	_weapon_system.setup_weapons(weapons_data)

func _setup_skills() -> void:
	_skill_system.setup_skills()

func _setup_ammo() -> void:
	_weapon_system.setup_ammo()

func set_nickname(name: String) -> void:
	_initializer.set_nickname(name)

func _get_mobile_controls():
	return get_tree().get_first_node_in_group("mobile_controls")

# === 武器与弹药（转发到 VehicleWeaponSystem） ===

func switch_weapon(index: int) -> void:
	_weapon_system.switch_weapon(index)

func get_weapon_count() -> int:
	return _weapon_system.get_weapon_count()

func get_current_weapon_id() -> String:
	return _weapon_system.get_current_weapon_id()

func select_ammo(index: int) -> void:
	_weapon_system.select_ammo(index)

func get_current_ammo_name() -> String:
	return _weapon_system.get_current_ammo_name()

func get_current_ammo_count() -> int:
	return _weapon_system.get_current_ammo_count()

func get_reload_percent() -> float:
	return _weapon_system.get_reload_percent()

func get_reload_remaining_time() -> float:
	return _weapon_system.get_reload_remaining_time()

func reduce_ammo(amount: int) -> void:
	_weapon_system.reduce_ammo(amount)

func _save_weapon_state(index: int) -> void:
	_weapon_system.save_weapon_state(index)

func get_lock_info() -> Dictionary:
	return _weapon_system.get_lock_info()

# === 技能系统（转发到 VehicleSkillSystem） ===

func can_use_skill(skill_id: String) -> bool:
	return _skill_system.can_use_skill(skill_id)

func get_skill_cooldown(skill_id: String) -> float:
	return _skill_system.get_skill_cooldown(skill_id)

func request_skill(skill_id: String) -> bool:
	return _skill_system.request_skill(skill_id)

func confirm_skill(target_pos: Vector3) -> void:
	_skill_system.confirm_skill(target_pos)

func execute_skill_remote(skill_id: String, target_pos: Vector3) -> void:
	_skill_system.execute_skill_remote(skill_id, target_pos)

func cancel_skill() -> void:
	_skill_system.cancel_skill()

# === 维修系统（转发到 VehicleRepairSystem） ===

func start_repair() -> void:
	_repair_system.start_repair()

func _complete_repair() -> void:
	"""维修完成钩子（tank.gd 重写此方法以同步视角）"""
	_repair_system.complete_repair()

func get_repair_percent() -> float:
	return _repair_system.get_repair_percent()

func get_damaged_modules_count() -> int:
	return _repair_system.get_damaged_modules_count()

func has_repairable_modules() -> bool:
	return _repair_system.has_repairable_modules()

# === 伤害处理（转发到 VehicleDamageHandler） ===

func take_damage(module_name: String, damage: float, dmg_type: int, angle: float = 0.0, attacker: Node = null, penetration: float = 0.0) -> Dictionary:
	return _damage_handler.take_damage(module_name, damage, dmg_type, angle, attacker, penetration)

func get_health_percent() -> float:
	return _damage_handler.get_health_percent()

func _on_vehicle_destroyed() -> void:
	_damage_handler.on_vehicle_destroyed()

func _on_ammo_rack_damaged(rounds_lost: int) -> void:
	_damage_handler.on_ammo_rack_damaged(rounds_lost)

func _on_ammo_exploded() -> void:
	_damage_handler.on_ammo_exploded()

# === 网络同步（转发到 VehicleNetworkSync） ===

func apply_network_state(position: Vector3, quaternion: Quaternion, turret_yaw: float, gun_pitch: float, speed: float, health: float, destroyed: bool, alpha: float, n_load: float, delta_a: float, delta_e: float, delta_r: float, fired: bool) -> void:
	_network_sync.apply_network_state(position, quaternion, turret_yaw, gun_pitch, speed, health, destroyed, alpha, n_load, delta_a, delta_e, delta_r, fired)

func set_network_health(percent: float) -> void:
	_network_sync.set_network_health(percent)

func mark_network_destroyed() -> void:
	_network_sync.mark_network_destroyed()

# === 物理进程 ===

func _physics_process(delta: float) -> void:
	if is_destroyed:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		if is_on_floor():
			velocity.y = 0.0
		return

	_network_sync.interpolate_network_state(delta)
	_weapon_system.update_reload(delta)
	_repair_system.update_repair(delta)
	_skill_system.update_cooldowns(delta)

	if is_player_controlled or (is_server_controlled and not is_remote_ai):
		_update_movement(delta)
		_update_turret(delta)
		_weapon_system.update_lock_on(delta)

	if is_repairing:
		velocity = Vector3.ZERO
		global_position = _repair_saved_pos
		rotation.y = _repair_saved_rot
		if turret_node:
			turret_node.rotation.y = _repair_saved_turret_rot
		if gun_node:
			gun_node.rotation.x = _repair_saved_gun_rot
	else:
		var pre_move_vel := velocity
		move_and_slide()
		if is_on_floor():
			velocity.y = 0.0
		_damage_handler.check_crash_impact(pre_move_vel)
		_align_to_ground(delta)

	if enforce_map_bounds and map_half_size > 0:
		if global_position.x > map_half_size:
			global_position.x = map_half_size
			velocity.x = 0.0
		elif global_position.x < -map_half_size:
			global_position.x = -map_half_size
			velocity.x = 0.0
		if global_position.z > map_half_size:
			global_position.z = map_half_size
			velocity.z = 0.0
		elif global_position.z < -map_half_size:
			global_position.z = -map_half_size
			velocity.z = 0.0

func _align_to_ground(delta: float) -> void:
	if is_repairing:
		return
	# 离地时不做地形对齐，避免空中错误旋转导致落地时姿态异常
	if not is_on_floor():
		return
	# 收集排除 RID（空气边界 + 障碍物）
	var exclude_rids: Array[RID] = [get_rid()]
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		var tb = main_node.get_node_or_null("TerrainBuilder")
		if tb:
			if tb.has_method("get_air_boundary_rids"):
				exclude_rids.append_array(tb.get_air_boundary_rids())
			if tb.has_method("get_obstacle_rids"):
				exclude_rids.append_array(tb.get_obstacle_rids())
	# 使用四角 RayCast3D 节点采样地面
	if _ground_rays_ready and _ground_rays.size() >= 4:
		_align_with_multi_rays(delta, exclude_rids)
	else:
		_align_with_single_ray(delta, exclude_rids)

func _align_with_multi_rays(delta: float, exclude_rids: Array[RID]) -> void:
	"""使用四角 + 中心射线采样地面，计算 Y 和旋转。
	四角射线覆盖碰撞盒范围，在斜坡上也能正确贴地。"""
	# 强制刷新射线（collision_mask=1 已在创建时设置，无需 exclude）
	for ray in _ground_rays:
		ray.force_raycast_update()
	# 收集命中点（世界坐标）
	var hit_points: Array[Vector3] = []
	var hit_normals: Array[Vector3] = []
	for ray in _ground_rays:
		if ray.is_colliding():
			hit_points.append(ray.get_collision_point())
			hit_normals.append(ray.get_collision_normal())
	if hit_points.size() < 3:
		# 命中点太少，回退到单射线
		_align_with_single_ray(delta, exclude_rids)
		return
	# --- 旋转修正（先做旋转，再做 Y）---
	# 用四角命中点的高度差计算俯仰和侧倾
	# 前左(0) + 前右(1) vs 后左(2) + 后右(3)
	var front_y = (hit_points[0].y + hit_points[1].y) * 0.5
	var rear_y = (hit_points[2].y + hit_points[3].y) * 0.5
	var left_y = (hit_points[0].y + hit_points[2].y) * 0.5
	var right_y = (hit_points[1].y + hit_points[3].y) * 0.5
	var wheelbase = 5.0
	var track_width = 3.2
	var target_pitch = atan((front_y - rear_y) / wheelbase)
	var target_roll = atan((left_y - right_y) / track_width)
	# Godot 4 右手坐标系:
	# rotation.x > 0 = 抬头(前部上扬) → 上坡时 front_y > rear_y, target_pitch > 0 → 直接用
	# rotation.z > 0 = 右侧上抬 → 左侧高时 left_y > right_y, target_roll > 0 → 需取反
	rotation.x = lerp_angle(rotation.x, target_pitch, 5.0 * delta)
	rotation.z = lerp_angle(rotation.z, -target_roll, 5.0 * delta)
	# --- Y 修正（旋转后重新更新中心射线，获取正确的地面高度）---
	# 旋转后碰撞盒位置变化，需重新采样
	_ground_rays[4].force_raycast_update()
	var center_y = global_position.y
	if _ground_rays[4].is_colliding():
		center_y = _ground_rays[4].get_collision_point().y
	var y_diff = center_y - global_position.y
	if abs(y_diff) < 0.5:
		global_position.y = center_y
	elif abs(y_diff) < 2.0:
		global_position.y = lerpf(global_position.y, center_y, 10.0 * delta)

func _align_with_single_ray(delta: float, exclude_rids: Array[RID]) -> void:
	"""单射线回退方案（原逻辑）"""
	var space = get_world_3d().direct_space_state
	var from = global_position + Vector3(0, 5.0, 0)
	var to = global_position + Vector3(0, -15.0, 0)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = exclude_rids
	var result = space.intersect_ray(query)
	if result.is_empty() or not result.has("normal"):
		rotation.x = lerp(rotation.x, 0.0, 2.0 * delta)
		rotation.z = lerp(rotation.z, 0.0, 2.0 * delta)
		return
	var ground_y: float = result.position.y
	var y_diff: float = ground_y - global_position.y
	if abs(y_diff) < 0.5:
		global_position.y = ground_y
	elif abs(y_diff) < 2.0:
		global_position.y = lerpf(global_position.y, ground_y, 10.0 * delta)
	var normal = result.normal
	if normal.y > 0.98:
		rotation.x = lerp(rotation.x, 0.0, 2.0 * delta)
		rotation.z = lerp(rotation.z, 0.0, 2.0 * delta)
		return
	if normal.y < 0.3:
		return
	var yaw = rotation.y
	var horiz_forward = Vector3(-sin(yaw), 0, -cos(yaw))
	var up = normal.normalized()
	var right = horiz_forward.cross(up).normalized()
	if right.length() < 0.1:
		return
	var forward = up.cross(right).normalized()
	var target_basis = Basis(right, up, -forward)
	var target_euler = target_basis.get_euler(EULER_ORDER_YXZ)
	rotation.x = lerp_angle(rotation.x, target_euler.x, 2.0 * delta)
	rotation.z = lerp_angle(rotation.z, target_euler.z, 2.0 * delta)

func _update_movement(delta: float) -> void:
	if is_repairing:
		target_speed = lerp(target_speed, 0.0, 5.0 * delta)
		current_speed = target_speed
		var forward = -global_transform.basis.z
		velocity.x = forward.x * current_speed
		velocity.z = forward.z * current_speed
		velocity.y -= GRAVITY * delta
		return
	var left_track_eff = _get_module_effectiveness("track_left")
	var right_track_eff = _get_module_effectiveness("track_right")
	var engine_eff = _get_module_effectiveness("engine")
	var trans_eff = _get_module_effectiveness("transmission")
	var driver_eff = get_driver_effectiveness()
	var mobility_factor = engine_eff * trans_eff * driver_eff
	var turn_factor = (left_track_eff + right_track_eff) * 0.5 * driver_eff
	if input_throttle > 0:
		target_speed = lerp(target_speed, max_speed * input_throttle * mobility_factor, acceleration * delta)
	elif input_throttle < 0:
		target_speed = lerp(target_speed, max_reverse_speed * abs(input_throttle) * mobility_factor, acceleration * delta)
	else:
		target_speed = lerp(target_speed, 0.0, deceleration * delta)
	current_speed = target_speed
	var turn_amount = -input_steering * turn_rate * turn_factor * delta
	rotate_y(deg_to_rad(turn_amount))
	var forward = -global_transform.basis.z
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed
	velocity.y -= GRAVITY * delta
	speed_changed.emit(current_speed)
	altitude_changed.emit(global_position.y)

func _update_turret(delta: float) -> void:
	if not turret_node:
		return
	if is_repairing:
		return
	var turret_eff = _get_module_effectiveness("turret_ring")
	var gunner_eff = get_gunner_effectiveness()
	turret_yaw += input_turret * turret_turn_rate * turret_eff * gunner_eff * delta
	turret_node.rotation.y = deg_to_rad(turret_yaw)
	if gun_node:
		var gun_eff = _get_module_effectiveness("gun")
		gun_pitch = clamp(gun_pitch + input_gun * 20.0 * gun_eff * gunner_eff * delta, gun_elevation_min, gun_elevation_max)
		gun_node.rotation.x = deg_to_rad(gun_pitch)

# === 模块与乘员效能 ===

func _get_module_effectiveness(module_name: String) -> float:
	if damage_system and damage_system.modules.has(module_name):
		return damage_system.modules[module_name].get_effectiveness()
	return 1.0

func _get_crew_effectiveness(crew_name: String) -> float:
	return _get_module_effectiveness(crew_name)

func get_driver_effectiveness() -> float:
	return _get_crew_effectiveness("crew_driver")

func get_loader_effectiveness() -> float:
	return _get_crew_effectiveness("crew_loader")

func get_gunner_effectiveness() -> float:
	return _get_crew_effectiveness("crew_gunner")

func get_commander_effectiveness() -> float:
	return _get_crew_effectiveness("crew_commander")

# === 开火 ===

func fire() -> void:
	if is_destroyed:
		return
	var muzzles := _get_muzzle_list()
	if muzzles.is_empty() or not is_inside_tree():
		return
	if not can_fire or is_reloading:
		return
	if is_repairing:
		return
	var ammo_name = get_current_ammo_name()
	if ammo_counts.get(ammo_name, 0) < muzzles.size():
		print("[Vehicle] %s out of ammo: %s" % [vehicle_id, ammo_name])
		return
	ammo_counts[ammo_name] -= muzzles.size()
	if ammo_counts.get(ammo_name, 0) <= 0:
		var next_idx = _weapon_system.find_next_ammo_with_rounds(current_ammo_index)
		if next_idx >= 0 and next_idx != current_ammo_index:
			current_ammo_index = next_idx
			var new_name = get_current_ammo_name()
			print("[Vehicle] %s 弹药 %s 耗尽，自动切换到 %s" % [vehicle_id, ammo_name, new_name])
		else:
			print("[Vehicle] %s 所有弹药耗尽" % vehicle_id)
	input_fire = true
	var projectile_scene = load("res://scenes/projectile.tscn")
	if not projectile_scene:
		return
	# 每枪口发射一发弹丸（多发射点同时开火，如喷火左右机翼 20mm 炮）
	var main_muzzle_pos := Vector3.ZERO
	var main_muzzle_rot := Vector3.ZERO
	var fire_ammo_type := "kinetic"
	for mz_i in range(muzzles.size()):
		var mz: Node3D = muzzles[mz_i]
		var muzzle_pos = mz.global_position
		var muzzle_rot = mz.global_rotation
		if mz_i == 0:
			main_muzzle_pos = muzzle_pos
			main_muzzle_rot = muzzle_rot
		var projectile = projectile_scene.instantiate()
		projectile.speed = 800.0
		projectile.damage = 100.0
		projectile.penetration = 300.0
		projectile.ammo_type = "kinetic"
		if current_ammo_index < ammo_types.size():
			var ammo = ammo_types[current_ammo_index]
			projectile.speed = ammo.get("muzzle_velocity", 800.0)
			projectile.damage = ammo.get("damage", 100.0)
			projectile.penetration = ammo.get("penetration", 300.0)
			projectile.ammo_type = ammo.get("type", "kinetic")
			projectile.explosive_mass = ammo.get("explosive_mass", 0.0)
			projectile.splash_radius = ammo.get("splash_radius", 0.0)
			projectile.mass = ammo.get("mass", 10.0)
			projectile.drag_coefficient = ammo.get("drag_coefficient", 0.1)
			projectile.guidance = ammo.get("guidance", "none")
			projectile.track_rate = ammo.get("track_rate", 1.0)
			projectile.track_lifetime = ammo.get("track_lifetime", 15.0)
			fire_ammo_type = projectile.ammo_type
		get_tree().current_scene.add_child(projectile)
		projectile.global_position = muzzle_pos
		projectile.global_rotation = muzzle_rot
		projectile.owner_vehicle = self
		if GameManager.network_type == 0 and NetworkManager.is_client and not NetworkManager.is_server:
			projectile.lan_visual_only = true
		if projectile.guidance != "none" and locked_target and lock_progress >= 1.0 and is_instance_valid(locked_target):
			projectile.set_target(locked_target)
		projectile.launch()
		EffectManager.play_muzzle_flash(muzzle_pos, muzzle_rot, 1.0)
		EffectManager.play_sound_3d(EffectManager.SOUND_FIRE, muzzle_pos, -5.0)
	var is_local: bool = false
	var _val2 = get("is_public_local")
	if _val2 != null:
		is_local = _val2
	if is_local and GameManager.network_type == 1:
		# 联机仅上报第一发射点作为代表（远端用 muzzle_node 播放单点特效）
		NetworkManager.game_send_fire({
			"muzzle_position": [main_muzzle_pos.x, main_muzzle_pos.y, main_muzzle_pos.z],
			"muzzle_rotation": [main_muzzle_rot.x, main_muzzle_rot.y, main_muzzle_rot.z],
			"ammo_name": ammo_name,
			"ammo_type": fire_ammo_type,
		})
	can_fire = false
	is_reloading = true
	reload_timer = reload_time
	_weapon_system.save_weapon_state(current_weapon_index)
	print("[Vehicle] %s fired %s x%d, remaining: %d" % [vehicle_id, ammo_name, muzzles.size(), ammo_counts[ammo_name]])

func fire_remote(_fire_data: Dictionary = {}) -> void:
	if is_destroyed or not muzzle_node or not is_inside_tree():
		return
	var muzzle_pos = muzzle_node.global_position
	var muzzle_rot = muzzle_node.global_rotation
	EffectManager.play_muzzle_flash(muzzle_pos, muzzle_rot, 1.0)
	EffectManager.play_sound_3d(EffectManager.SOUND_FIRE, muzzle_pos, -5.0)

# === 自由视角 ===

func set_free_look(active: bool) -> void:
	if is_free_look == active:
		return
	is_free_look = active
	if active:
		free_look_yaw = 0.0
		free_look_pitch = 0.0
		_apply_free_look_hint(true)
	else:
		_apply_free_look_hint(false)

func is_free_look_active() -> bool:
	return is_free_look

func _handle_free_look_input(event: InputEvent) -> void:
	if event.is_action_pressed("free_look"):
		set_free_look(true)
	elif event.is_action_released("free_look"):
		set_free_look(false)

func _process_free_look_restore(delta: float) -> void:
	if is_free_look:
		return
	var k = clampf(1.0 - exp(-FREE_LOOK_RESTORE_SPEED * delta), 0.0, 1.0)
	free_look_yaw = lerpf(free_look_yaw, 0.0, k)
	free_look_pitch = lerpf(free_look_pitch, 0.0, k)
	if absf(free_look_yaw) < 0.01 and absf(free_look_pitch) < 0.01:
		free_look_yaw = 0.0
		free_look_pitch = 0.0

func _apply_free_look_hint(active: bool) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_free_look_active"):
		hud.set_free_look_active(active)

# === 子类兼容转发（helicopter.gd 等子类调用带下划线前缀的方法）===

func _update_lock_on(delta: float) -> void:
	if _weapon_system:
		_weapon_system.update_lock_on(delta)

func _check_crash_impact(pre_vel: Vector3) -> void:
	if _damage_handler:
		_damage_handler.check_crash_impact(pre_vel)

func _interpolate_network_state(delta: float) -> void:
	if _network_sync:
		_network_sync.interpolate_network_state(delta)
