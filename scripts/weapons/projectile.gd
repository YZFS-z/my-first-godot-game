extends Area3D
class_name Projectile
## 弹丸 - 处理弹道物理、碰撞检测、伤害计算
## 支持：动能弹穿深衰减、高爆弹溅射、弹道下坠

signal hit(target: Node, hit_position: Vector3, penetrated: bool)
signal expired()

@export var speed: float = 800.0
@export var mass: float = 10.0
@export var drag_coefficient: float = 0.1
@export var damage: float = 100.0
@export var penetration: float = 500.0
@export var explosive_mass: float = 0.0
@export var splash_radius: float = 0.0
@export var ammo_type: String = "kinetic"
@export var lifetime: float = 10.0

# 制导系统
@export var guidance: String = "none"  # none/infrared/laser
@export var track_rate: float = 1.0  # 跟踪转向速率(rad/s)
@export var track_lifetime: float = 15.0  # 最长跟踪时间(s)

var velocity: Vector3 = Vector3.ZERO
var traveled_distance: float = 0.0
var life_timer: float = 0.0
var is_server: bool = true
var owner_vehicle: Node = null  # 发射者引用
var has_hit: bool = false  # 防止重复命中
var lan_visual_only: bool = false  # 局域网客户端本地弹丸：只做弹道/特效，不结算伤害（伤害以服务器权威为准）
# 跟踪目标
var target: Node3D = null
var is_locked: bool = false
var track_timer: float = 0.0

const GRAVITY: float = 9.81
const DRAG_AREA_FACTOR: float = 0.0003  # 0.5 * 空气密度(1.225) * 典型弹芯截面积(~0.00049m², 直径25mm)

func _get_effective_splash_radius() -> float:
	"""根据炸药量计算有效溅射半径，炸药量为0则无范围伤害"""
	if explosive_mass <= 0:
		return 0.0
	if splash_radius > 0:
		return splash_radius * 0.7
	if ammo_type == "explosive":
		# HE高爆弹：4kg约3.5m
		return explosive_mass * 0.9
	elif ammo_type == "chemical":
		# HEAT破甲弹：2.5kg约2m
		return explosive_mass * 0.8
	return explosive_mass * 0.5

func _get_splash_damage() -> float:
	"""根据炮弹种类计算溅射伤害基数，炸药量为0则无溅射伤害"""
	if explosive_mass <= 0:
		return 0.0
	if ammo_type == "explosive":
		return damage * 0.7
	elif ammo_type == "chemical":
		return damage * 0.4
	return damage * 0.35

func _ready() -> void:
	# 速度方向由发射方在设置完global_rotation后显式调用launch()设置
	# 排除草丛层（层5/bit4/值16），草丛仅遮挡视野不阻挡炮弹
	collision_mask &= ~16

func _get_ground_height(x: float, z: float) -> float:
	"""获取指定XZ位置的地面高度（用于防止炮弹穿透地底的兜底检测）"""
	var tb = get_tree().root.find_child("TerrainBuilder", true, false)
	if tb and tb.has_method("get_terrain_height"):
		return tb.get_terrain_height(x, z)
	return -1000.0

func launch() -> void:
	"""在global_position和global_rotation设置完成后调用，初始化飞行方向"""
	velocity = -Basis.from_euler(global_rotation).z * speed

func set_ammo_data(data: Dictionary) -> void:
	speed = data.get("muzzle_velocity", 800.0)
	mass = data.get("mass", 10.0)
	drag_coefficient = data.get("drag_coefficient", 0.1)
	damage = data.get("damage", 100.0)
	penetration = data.get("penetration", 500.0)
	explosive_mass = data.get("explosive_mass", 0.0)
	splash_radius = data.get("splash_radius", 0.0)
	ammo_type = data.get("type", "kinetic")
	# 制导参数
	guidance = data.get("guidance", "none")
	track_rate = data.get("track_rate", 1.0)
	track_lifetime = data.get("track_lifetime", 15.0)
	# 速度方向由launch()在transform设置完成后计算

func set_target(t: Node3D) -> void:
	"""设置跟踪目标（发射前由载具锁定系统调用）"""
	target = t
	is_locked = t != null
	track_timer = track_lifetime
	# 制导弹药延长lifetime，确保有足够时间命中
	if guidance != "none":
		lifetime = max(lifetime, track_lifetime + 5.0)

func _physics_process(delta: float) -> void:
	if has_hit:
		return

	life_timer += delta
	if life_timer >= lifetime:
		_expire()
		return

	# === 制导跟踪 ===
	if is_locked and guidance != "none" and target and is_instance_valid(target):
		track_timer -= delta
		if track_timer <= 0:
			is_locked = false
			target = null
		else:
			# 检查目标是否被摧毁
			if "is_destroyed" in target and target.is_destroyed:
				is_locked = false
				target = null
			else:
				# 计算目标中心点（用AABB中心更精准）
				var target_center = target.global_position
				if target is Node3D and "get_aabb" in target:
					target_center = target.global_position + target.get_aabb().get_center()
				else:
					target_center = target.global_position + Vector3(0, 1.5, 0)
				# 提前量计算：预测导弹到达时目标的位置
				var dist = global_position.distance_to(target_center)
				var time_to_hit = dist / max(velocity.length(), 1.0)
				var target_vel = Vector3.ZERO
				if target is CharacterBody3D:
					target_vel = target.velocity
				elif "velocity" in target:
					target_vel = target.velocity
				var predicted_pos = target_center + target_vel * time_to_hit * 0.5  # 0.5系数避免过度提前
				# 计算到预测点的方向
				var to_target = predicted_pos - global_position
				dist = to_target.length()
				if dist > 0.1:
					var desired_dir = to_target / dist
					var current_dir = velocity.normalized()
					# 限制转向角度（跟踪速率）
					var max_angle = track_rate * delta
					var dot = clamp(current_dir.dot(desired_dir), -1.0, 1.0)
					var angle = acos(dot)
					if angle > max_angle:
						# 旋转到最大允许角度
						var axis = current_dir.cross(desired_dir).normalized()
						if axis.length() < 0.01:
							axis = Vector3.UP
						current_dir = current_dir.rotated(axis, max_angle)
					else:
						current_dir = desired_dir
					# 保持速度大小，更新方向
					var spd = velocity.length()
					velocity = current_dir * spd

	# 空气阻力（真实公式：0.5*ρ*Cd*A*v²/m，DRAG_AREA_FACTOR已含0.5*ρ*A）
	var drag = drag_coefficient * velocity.length() * velocity.length() / mass * DRAG_AREA_FACTOR
	if velocity.length() > 0:
		velocity -= velocity.normalized() * drag * delta

	# 重力（弹道下坠）
	velocity.y -= GRAVITY * delta

	# 计算本帧移动
	var old_pos = global_position
	var move_amount = velocity * delta
	var new_pos = old_pos + move_amount

	# 射线检测（防止高速弹丸隧道效应）
	# 模块层(4)+世界层(1)优先：模块盒（引擎/翼/炮塔等局部部件）命中时走精确
	# 模块伤害，与主体盒(层2)是否阻挡无关（模块盒在主体盒内部，若混查则永远
	# 先碰主体、模块伤害失效）。
	# 穿模修复：本段位移未命中任何模块/障碍物时，追加含载具主体层(2)的兜底
	# 射线——炮弹打在车体/机身等无模块覆盖的大片表面不再直接穿过，
	# 而是命中主体并结算车体(整体)伤害。制导弹药维持含主体层的既有行为。
	var space = get_world_3d().direct_space_state
	var exclude_list = [get_rid()]
	if owner_vehicle:
		exclude_list.append(owner_vehicle.get_rid())
	var ray_mask = collision_mask
	if guidance != "none":
		ray_mask = collision_mask | 2  # 制导弹药直接含主体层（保持既有行为）
	var query = PhysicsRayQueryParameters3D.create(old_pos, new_pos, ray_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude_list
	var result = space.intersect_ray(query)
	# 模块/世界均未命中：兜底检查是否穿透了载具主体（坦克车体/飞机机身表面）
	if result.is_empty() and guidance == "none":
		var body_q = PhysicsRayQueryParameters3D.create(old_pos, new_pos, collision_mask | 2)
		body_q.collide_with_areas = true
		body_q.collide_with_bodies = true
		body_q.exclude = exclude_list
		var body_hit = space.intersect_ray(body_q)
		if not body_hit.is_empty():
			result = body_hit

	if result:
		has_hit = true
		var hit_pos = result.position
		var collider = result.collider
		global_position = hit_pos
		traveled_distance += old_pos.distance_to(hit_pos)
		# 判断命中模块还是物体
		if collider and collider is Area3D and "module_name" in collider:
			_handle_module_hit(collider, hit_pos)
		else:
			_handle_hit(collider, hit_pos)
		return

	# 无命中，正常移动（兜底：防止穿透地形碰撞体陷入地底）
	var ground_h = _get_ground_height(new_pos.x, new_pos.z)
	if new_pos.y <= ground_h + 0.1:
		# 炮弹已到达地面，直接命中地面（不传 null 给 _handle_hit 避免报错）
		has_hit = true
		var hit_pos = Vector3(new_pos.x, ground_h, new_pos.z)
		global_position = hit_pos
		traveled_distance += old_pos.distance_to(hit_pos)
		# 播放地面命中特效
		if explosive_mass > 0 or ammo_type == "chemical":
			EffectManager.play_explosion(hit_pos, 0.6)
		else:
			EffectManager.play_hit_spark(hit_pos, -global_transform.basis.z, Color(0.8, 0.75, 0.6))
		_expire()
		return
	global_position = new_pos
	traveled_distance += move_amount.length()

	# 更新朝向
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

	# 穿深随距离衰减（动能弹）
	if ammo_type == "kinetic" or ammo_type == "kinetic_explosive":
		penetration = max(penetration * (1.0 - 0.001 * traveled_distance), penetration * 0.3)

func _handle_module_hit(module: Area3D, hit_position: Vector3) -> void:
	"""精确命中具体模块"""
	# 已击毁的载具不再受到任何伤害和特效
	if module.owner_vehicle and "is_destroyed" in module.owner_vehicle and module.owner_vehicle.is_destroyed:
		queue_free()
		return
	var hit_angle = velocity.angle_to(-global_transform.basis.z)
	var dmg_type = 0  # KINETIC
	if ammo_type == "explosive" or ammo_type == "chemical" or ammo_type == "kinetic_explosive":
		dmg_type = 1  # EXPLOSIVE

	var module_name = module.module_name if "module_name" in module else "unknown"
	var module_display = module.display_name if "display_name" in module else module_name

# 通过载具伤害系统造成伤害（触发后效、弹药架殉爆等）
	var result = {"penetrated": false, "damage": 0.0, "module_destroyed": false}
	if module.owner_vehicle and module.owner_vehicle.has_method("take_damage") and not lan_visual_only:
		if owner_vehicle:
			module.owner_vehicle.killer = owner_vehicle
		result = module.owner_vehicle.take_damage(module_name, damage, dmg_type, rad_to_deg(hit_angle), owner_vehicle, penetration)

	var actual_damage = result.get("damage", 0.0)
	var penetrated = result.get("penetrated", false)
	print("[Projectile] Hit module: %s, damage: %.1f, penetrated: %s" % [module_name, actual_damage, penetrated])

	# 公网联机：本地玩家命中时广播命中事件
	if owner_vehicle and "is_public_local" in owner_vehicle and owner_vehicle.is_public_local and NetworkManager.game_connected_flag:
		if module.owner_vehicle and module.owner_vehicle.network_player_id != "":
			NetworkManager.game_send_hit({
				"target_id": module.owner_vehicle.network_player_id,
				"module_name": module_name,
				"damage": actual_damage,
				"penetrated": penetrated,
				"hit_position": [hit_position.x, hit_position.y, hit_position.z],
				"hit_normal": [-global_transform.basis.z.x, -global_transform.basis.z.y, -global_transform.basis.z.z],
				"dmg_type": dmg_type,
				"explosive_mass": explosive_mass,
				"ammo_type": ammo_type,
			})

	# 命中特效
	if dmg_type == 1 or explosive_mass > 0:
		EffectManager.play_explosion(hit_position, 0.55)
	else:
		var spark_color = Color(1, 0.85, 0.3) if penetrated else Color(0.7, 0.7, 0.7)
		EffectManager.play_hit_spark(hit_position, -global_transform.basis.z, spark_color)

	# 范围溅射伤害（根据炮弹种类，HE/HEAT/APFSDS都有不同程度溅射）
	var eff_radius = _get_effective_splash_radius()
	if eff_radius > 0:
		_apply_splash(hit_position, eff_radius)

	# 发送命中提示
	var show_hit = (owner_vehicle and owner_vehicle.is_player_controlled) or GameManager.debug_mode
	if show_hit:
		var msg = ""
		var col = Color.WHITE
		if GameManager.debug_mode:
			var shooter = owner_vehicle.nickname if owner_vehicle and "nickname" in owner_vehicle else "?"
			var target = module.owner_vehicle.nickname if module.owner_vehicle and "nickname" in module.owner_vehicle else "?"
			if not penetrated:
				msg = "[%s→%s] 未击穿 %s (穿深%.0f/角度%.0f°)" % [shooter, target, module_display, penetration, rad_to_deg(hit_angle)]
				col = Color(0.7, 0.7, 0.7)
			elif module.state == 3:
				msg = "[%s→%s] 击毁 %s! (%.0f伤害)" % [shooter, target, module_display, actual_damage]
				col = Color(1, 0.3, 0.3)
			else:
				msg = "[%s→%s] 命中 %s (%.0f伤害/血量%.0f%%)" % [shooter, target, module_display, actual_damage, module.current_health / module.max_health * 100]
				col = Color(1, 1, 0.5)
		else:
			# 简化模式：只显示 未击穿/命中/击毁
			if not penetrated:
				msg = "未击穿"
				col = Color(0.8, 0.8, 0.8)
			elif module.owner_vehicle and module.owner_vehicle.is_destroyed:
				msg = "击毁!"
				col = Color(1, 0.3, 0.3)
			else:
				msg = "命中"
				col = Color(1, 1, 0.5)
		GameManager.hit_message.emit(msg, col)

		# 检查目标是否被摧毁
		if module.owner_vehicle and module.owner_vehicle.is_destroyed:
			var target_name = module.owner_vehicle.nickname if "nickname" in module.owner_vehicle else "目标"
			GameManager.target_destroyed.emit(target_name)

	hit.emit(module, hit_position, penetrated)
	_expire()

func _handle_hit(target: Node, hit_position: Vector3) -> void:
	# 已击毁的载具不再受到伤害和特效
	if "is_destroyed" in target and target.is_destroyed:
		queue_free()
		return
	var penetrated = true
	var hit_angle = velocity.angle_to(-global_transform.basis.z)

# 对载具主体造成伤害（随机模块）
	if target.has_method("take_damage") and not lan_visual_only:
		var dmg_type = 0  # KINETIC
		if ammo_type == "explosive" or ammo_type == "chemical" or ammo_type == "kinetic_explosive":
			dmg_type = 1  # EXPLOSIVE
		target.take_damage("hull", damage, dmg_type, rad_to_deg(hit_angle), owner_vehicle, penetration)
		# 公网联机：广播命中事件
		if owner_vehicle and "is_public_local" in owner_vehicle and owner_vehicle.is_public_local and NetworkManager.game_connected_flag:
			if "network_player_id" in target and target.network_player_id != "":
				NetworkManager.game_send_hit({
					"target_id": target.network_player_id,
					"module_name": "hull",
					"damage": damage,
					"penetrated": true,
					"hit_position": [hit_position.x, hit_position.y, hit_position.z],
					"hit_normal": [-global_transform.basis.z.x, -global_transform.basis.z.y, -global_transform.basis.z.z],
					"dmg_type": dmg_type,
					"explosive_mass": explosive_mass,
					"ammo_type": ammo_type,
				})

	# 命中特效（命中障碍物/地面）
	if explosive_mass > 0 or ammo_type == "chemical":
		EffectManager.play_explosion(hit_position, 0.6)
	else:
		EffectManager.play_hit_spark(hit_position, -global_transform.basis.z, Color(0.8, 0.75, 0.6))

	# 范围溅射伤害（根据炮弹种类，HE/HEAT/APFSDS都有不同程度溅射）
	var eff_radius = _get_effective_splash_radius()
	if eff_radius > 0:
		_apply_splash(hit_position, eff_radius)

	hit.emit(target, hit_position, penetrated)
	_expire()

func _apply_splash(center: Vector3, radius: float) -> void:
	"""范围溅射伤害：检测范围内的载具，距离衰减"""
	var splash_damage = _get_splash_damage()
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 2  # vehicle layer
	var results = space_state.intersect_shape(query)
	for result in results:
		var body = result.collider
		if lan_visual_only:
			break  # 局域网客户端弹丸不结算溅射伤害（服务器权威结算）
		if body and body.has_method("take_damage") and body != owner_vehicle:
			var dist = center.distance_to(body.global_position)
			var falloff = clamp(1.0 - (dist / radius), 0.1, 1.0)
			body.take_damage("hull", splash_damage * falloff, 1)  # EXPLOSIVE
	# 销毁范围内的草丛/灌木丛（威力=溅射伤害）
	var main = get_tree().get_first_node_in_group("main")
	if main and main.has_method("destroy_foliage_in_radius"):
		main.destroy_foliage_in_radius(center, radius, splash_damage)

func _expire() -> void:
	expired.emit()
	queue_free()
