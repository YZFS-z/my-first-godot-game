extends Node
## 载具技能系统 - 火炮打击、烟幕遮蔽、技能冷却管理
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态

# 炮兵阵地配置（M1型155毫米榴弹炮 x3）
const ARTILLERY_DISTANCE_KM: float = 10.0
const ARTILLERY_GUN_COUNT: int = 3
const ARTILLERY_GUN_SPACING: float = 25.0
const ARTILLERY_MUZZLE_VELOCITY: float = 564.0
const ARTILLERY_AVG_SPEED: float = 320.0
const ARTILLERY_MAX_TRAJECTORY_HEIGHT: float = 800.0
const OBSTACLE_COLLISION_LAYER: int = 1 << 3

func _get_vehicle() -> Node:
	return get_parent()

func setup_skills() -> void:
	var v = _get_vehicle()
	v.skills.clear()
	v.skills["artillery"] = {
		"name": "火炮打击",
		"cooldown": 45.0,
		"current_cooldown": 0.0,
		"radius": 25.0,
		"damage": 250.0,
		"spotter_delay": 1.5,
		"first_volley_delay": 8.0,
		"spotter_damage_mult": 0.4,
		"spotter_explosion_mult": 0.5,
		"volleys": 3,
		"volley_interval": 10.0,
		"explosion_scale": 3.0,
	}
	v.skills["smoke"] = {
		"name": "烟幕遮蔽",
		"cooldown": 30.0,
		"current_cooldown": 0.0,
		"radius": 6.0,
		"duration": 20.0,
		"delay": 1.5,
	}

func can_use_skill(skill_id: String) -> bool:
	var v = _get_vehicle()
	if not v.skills.has(skill_id):
		return false
	return v.skills[skill_id].current_cooldown <= 0.0 and not v.is_destroyed

func get_skill_cooldown(skill_id: String) -> float:
	var v = _get_vehicle()
	if not v.skills.has(skill_id):
		return 0.0
	return v.skills[skill_id].current_cooldown

func update_cooldowns(delta: float) -> void:
	var v = _get_vehicle()
	for skill_id in v.skills.keys():
		var skill = v.skills[skill_id]
		if skill.current_cooldown > 0:
			skill.current_cooldown = max(0.0, skill.current_cooldown - delta)
			v.skill_cooldown_changed.emit(skill_id, skill.current_cooldown)

func request_skill(skill_id: String) -> bool:
	var v = _get_vehicle()
	if not can_use_skill(skill_id):
		print("[Vehicle] %s 技能 %s 不可用" % [v.vehicle_id, skill_id])
		return false
	v._pending_skill = skill_id
	print("[Vehicle] %s 请求技能: %s，请选择目标位置" % [v.vehicle_id, skill_id])
	return true

func confirm_skill(target_pos: Vector3) -> void:
	var v = _get_vehicle()
	if v._pending_skill == "":
		return
	var skill_id = v._pending_skill
	v._pending_skill = ""
	if not v.skills.has(skill_id):
		return
	var skill = v.skills[skill_id]
	skill.current_cooldown = skill.cooldown
	v.skill_activated.emit(skill_id, target_pos)
	print("[Vehicle] %s 执行技能: %s @ %s" % [v.vehicle_id, skill_id, target_pos])
	var is_local: bool = false
	var _val = v.get("is_public_local")
	if _val != null:
		is_local = _val
	if is_local and GameManager.network_type == 1:
		NetworkManager.game_send_skill(skill_id, target_pos)
	if skill_id == "artillery":
		_call_artillery_strike(target_pos, skill)
	elif skill_id == "smoke":
		_call_smoke_screen(target_pos, skill)

func execute_skill_remote(skill_id: String, target_pos: Vector3) -> void:
	var v = _get_vehicle()
	if not v.skills.has(skill_id):
		return
	var skill = v.skills[skill_id]
	skill.current_cooldown = skill.cooldown
	print("[Vehicle] %s 远程执行技能: %s @ %s" % [v.vehicle_id, skill_id, target_pos])
	if skill_id == "artillery":
		_call_artillery_strike(target_pos, skill)
	elif skill_id == "smoke":
		_call_smoke_screen(target_pos, skill)

func cancel_skill() -> void:
	_get_vehicle()._pending_skill = ""

func _get_artillery_positions() -> Array:
	var v = _get_vehicle()
	var positions = []
	var rear_z = -ARTILLERY_DISTANCE_KM * 1000.0 if v.team == 1 else ARTILLERY_DISTANCE_KM * 1000.0
	for i in range(ARTILLERY_GUN_COUNT):
		var x = (i - 1) * ARTILLERY_GUN_SPACING
		positions.append(Vector3(x, 0.0, rear_z))
	return positions

func _calculate_artillery_flight_time(start: Vector3, target: Vector3) -> float:
	var distance = start.distance_to(target)
	return distance / ARTILLERY_AVG_SPEED

func _check_artillery_path_obstructed(start: Vector3, target: Vector3) -> Dictionary:
	var v = _get_vehicle()
	var space_state = v.get_world_3d().direct_space_state
	var distance = start.distance_to(target)
	var samples = 15
	for i in range(1, samples):
		var t = float(i) / samples
		var x = start.x + (target.x - start.x) * t
		var z = start.z + (target.z - start.z) * t
		var y = 4.0 * ARTILLERY_MAX_TRAJECTORY_HEIGHT * t * (1.0 - t)
		var point = Vector3(x, y, z)
		var to = point + Vector3.UP * 500.0
		var query = PhysicsRayQueryParameters3D.create(point, to, OBSTACLE_COLLISION_LAYER)
		var result = space_state.intersect_ray(query)
		if result:
			return {"obstructed": true, "hit_point": point, "collider": result.collider}
	return {"obstructed": false}

func _random_point_in_radius(center: Vector3, radius: float) -> Vector3:
	var angle = randf() * TAU
	var dist = sqrt(randf()) * radius
	return center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

func _call_artillery_strike(target_pos: Vector3, skill: Dictionary) -> void:
	var v = _get_vehicle()
	var radius = skill.get("radius", 18.0)
	var spotter_delay = skill.get("spotter_delay", 1.5)
	var first_volley_delay = skill.get("first_volley_delay", 2.5)
	var volleys = skill.get("volleys", 3)
	var volley_interval = skill.get("volley_interval", 10.0)
	var gun_positions = _get_artillery_positions()

	var spotter_target = _random_point_in_radius(target_pos, radius)
	var spotter_gun = gun_positions[0]
	var spotter_flight_time = _calculate_artillery_flight_time(spotter_gun, spotter_target)
	var spotter_path = _check_artillery_path_obstructed(spotter_gun, spotter_target)
	var spotter_impact_pos = spotter_path.hit_point if spotter_path.obstructed else spotter_target
	var spotter_skill = skill.duplicate()
	spotter_skill.damage = skill.get("damage", 250.0) * skill.get("spotter_damage_mult", 0.4)
	spotter_skill.explosion_scale = skill.get("explosion_scale", 3.0) * skill.get("spotter_explosion_mult", 0.5)
	print("[Artillery] 校准弹: 炮位%s → 目标%s, 飞行%.1fs, 遮挡:%s, 伤害%.0f" % [str(spotter_gun), str(spotter_target), spotter_flight_time, str(spotter_path.obstructed), spotter_skill.damage])
	v.get_tree().create_timer(spotter_delay + spotter_flight_time).timeout.connect(func():
		_artillery_round_impact(spotter_impact_pos, spotter_skill)
	)

	for volley in range(volleys):
		var volley_start = first_volley_delay + volley * volley_interval
		for g in range(ARTILLERY_GUN_COUNT):
			var gun_pos = gun_positions[g]
			var hit_target = _random_point_in_radius(target_pos, radius)
			var flight_time = _calculate_artillery_flight_time(gun_pos, hit_target)
			var path_check = _check_artillery_path_obstructed(gun_pos, hit_target)
			var impact_pos = path_check.hit_point if path_check.obstructed else hit_target
			var total_delay = volley_start + flight_time
			print("[Artillery] 第%d轮第%d门: 飞行%.1fs, 遮挡:%s" % [volley+1, g+1, flight_time, str(path_check.obstructed)])
			v.get_tree().create_timer(total_delay).timeout.connect(func():
				_artillery_round_impact(impact_pos, skill)
			)

func _artillery_round_impact(pos: Vector3, skill: Dictionary) -> void:
	var v = _get_vehicle()
	var explosion_scale = skill.get("explosion_scale", 2.8)
	var impact_pos = Vector3(pos.x, max(pos.y, 0.5), pos.z)
	EffectManager.play_explosion(impact_pos, explosion_scale)
	print("[Artillery] 炮弹落地爆炸 @ %s, scale=%.1f" % [str(impact_pos), explosion_scale])
	EffectManager.play_sound_3d(EffectManager.SOUND_ARTILLERY, impact_pos, 0.0)
	var radius = skill.get("radius", 25.0)
	var damage = skill.get("damage", 250.0)
	for veh in v.get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(veh):
			continue
		if veh.is_destroyed:
			continue
		var dist = veh.global_position.distance_to(impact_pos)
		if dist <= radius:
			var dmg = damage * (1.0 - dist / radius * 0.5)
			veh.take_damage("engine", dmg, 1, 0.0, v)
	var main = v.get_tree().get_first_node_in_group("main")
	if main and main.has_method("destroy_foliage_in_radius"):
		main.destroy_foliage_in_radius(impact_pos, radius, damage)

func _call_smoke_screen(target_pos: Vector3, skill: Dictionary) -> void:
	var v = _get_vehicle()
	var delay = skill.get("delay", 1.5)
	var duration = skill.get("duration", 20.0)
	var radius = skill.get("radius", 6.0)
	var gun_positions = _get_artillery_positions()
	var gun_pos = gun_positions[0]
	var flight_time = _calculate_artillery_flight_time(gun_pos, target_pos)
	var path_check = _check_artillery_path_obstructed(gun_pos, target_pos)
	var impact_pos = path_check.hit_point if path_check.obstructed else target_pos
	print("[Artillery] 烟幕弹: 飞行%.1fs, 遮挡:%s" % [flight_time, str(path_check.obstructed)])
	v.get_tree().create_timer(delay + flight_time).timeout.connect(func():
		_spawn_smoke(impact_pos, radius, duration)
	)

func _spawn_smoke(pos: Vector3, radius: float, duration: float) -> void:
	var v = _get_vehicle()
	var smoke_scene = load("res://scenes/smoke_screen.tscn")
	if smoke_scene:
		var smoke = smoke_scene.instantiate()
		smoke.set("radius", radius)
		smoke.set("duration", duration)
		v.get_tree().current_scene.add_child(smoke)
		smoke.global_position = pos
		EffectManager.play_sound_3d(EffectManager.SOUND_SMOKE, pos, -10.0)
	else:
		print("[Vehicle] 烟幕已部署 @ %s, 半径%.1f, 持续%.1fs" % [pos, radius, duration])
