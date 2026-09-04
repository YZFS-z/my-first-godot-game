extends Node
## 载具伤害处理 - 击毁、弹药殉爆、撞击损伤、击杀播报
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态
## 注意：take_damage() 保留在 vehicle.gd 中作为转发代理

func _get_vehicle() -> Node:
	return get_parent()

func take_damage(module_name: String, damage: float, dmg_type: int, angle: float = 0.0, attacker: Node = null, penetration: float = 0.0) -> Dictionary:
	var v = _get_vehicle()
	if v.is_destroyed:
		return {"hit": false, "destroyed": true, "module": module_name, "damage": 0.0}
	if attacker:
		v.killer = attacker
	if module_name == "hull" or not v.damage_system.modules.has(module_name):
		var module_names = v.damage_system.modules.keys()
		if module_names.size() > 0:
			module_name = module_names[randi() % module_names.size()]
	return v.damage_system.hit_module(module_name, damage, dmg_type, angle, false, penetration)

func on_vehicle_destroyed() -> void:
	var v = _get_vehicle()
	if v.is_destroyed:
		return
	v.mark_network_destroyed()
	var killer_name = v.killer.nickname if v.killer and "nickname" in v.killer else "未知"
	var killer_team = v.killer.team if v.killer and "team" in v.killer else 0
	GameManager.kill_feed.emit(killer_name, v.nickname, v.team, killer_team)
	if NetworkManager.game_connected_flag:
		var killer_is_local: bool = false
		var killer_is_ai: bool = false
		if v.killer != null:
			var _kl = v.killer.get("is_public_local")
			if _kl != null:
				killer_is_local = _kl
			var _ka = v.killer.get("is_server_controlled")
			if _ka != null:
				killer_is_ai = _ka
		var self_is_local: bool = false
		var _sl = v.get("is_public_local")
		if _sl != null:
			self_is_local = _sl
		var should_send: bool = false
		if killer_is_local:
			should_send = true
		elif self_is_local and killer_is_ai:
			should_send = true
		elif self_is_local and v.killer == null:
			should_send = true
		if should_send:
			var killer_id = ""
			if v.killer != null:
				var _kid = v.killer.get("network_player_id")
				if _kid != null:
					killer_id = _kid
			NetworkManager.game_send_destroy({
				"target_id": v.network_player_id,
				"killer_id": killer_id,
				"killer_name": killer_name,
				"killer_team": killer_team,
				"victim_name": v.nickname,
				"victim_team": v.team,
				"position": [v.global_position.x, v.global_position.y, v.global_position.z],
			})
	if NetworkManager.is_server and NetworkManager.mode == NetworkManager.NetworkMode.SERVER:
		NetworkManager.rpc("rpc_lan_kill_feed", killer_name, v.nickname, v.team, killer_team)
	print("[Vehicle] %s 已击毁，免疫后续伤害" % v.vehicle_id)

func on_ammo_rack_damaged(rounds_lost: int) -> void:
	_get_vehicle().reduce_ammo(rounds_lost)

func on_ammo_exploded() -> void:
	var v = _get_vehicle()
	for name in v.ammo_counts.keys():
		v.ammo_counts[name] = 0
	v._save_weapon_state(v.current_weapon_index)
	print("[Vehicle] %s AMMO DETONATED! All ammo lost." % v.vehicle_id)
	print("[Vehicle] %s destroyed by %s!" % [v.vehicle_id, v.killer.nickname if v.killer else "unknown"])
	if not v.has_exploded:
		v.has_exploded = true
		var explode_pos = v.global_position + Vector3(0, 1.5, 0)
		EffectManager.play_explosion(explode_pos, 2.5)
		if v.is_inside_tree() and v.fire_effect == null:
			v.fire_effect = EffectManager.play_fire_smoke(v, Vector3(0, 1.0, 0))
		if v.nickname_label:
			v.nickname_label.modulate = Color(0.5, 0.5, 0.5, 0.6)
			v.nickname_label.text = v.nickname + " (已摧毁)"
		var main = v.get_tree().get_first_node_in_group("main")
		if main and main.has_method("destroy_foliage_in_radius"):
			main.destroy_foliage_in_radius(explode_pos, 15.0, 200.0)
	else:
		var explode_pos = v.global_position + Vector3(0, 1.5, 0)
		EffectManager.play_explosion(explode_pos, 2.0)

func get_health_percent() -> float:
	var v = _get_vehicle()
	if v.damage_system:
		return v.damage_system.get_overall_health_percent()
	return 1.0

# === 高速撞击损伤 ===

func check_crash_impact(pre_vel: Vector3) -> void:
	var v = _get_vehicle()
	if v.is_destroyed or v.damage_system == null or v.damage_system.is_destroyed:
		return
	if Engine.get_physics_frames() - v._last_crash_frame < v.CRASH_DAMAGE_COOLDOWN_FRAMES:
		return
	if v.get_slide_collision_count() <= 0:
		return
	var impact: float = 0.0
	for i in v.get_slide_collision_count():
		var col: KinematicCollision3D = v.get_slide_collision(i)
		if col == null:
			continue
		var n: float = absf(pre_vel.dot(col.get_normal()))
		if n > impact:
			impact = n
	impact *= v.crash_impact_scale
	if impact < v.crash_speed_light:
		return
	if impact > v.CRASH_SPEED_MAX:
		print("[Vehicle] %s 忽略异常撞击速度 %.0f m/s（物理异常帧）" % [v.vehicle_id, impact])
		return
	v._last_crash_frame = Engine.get_physics_frames()
	var mods: Dictionary = v.damage_system.modules
	if impact >= v.crash_speed_fatal:
		print("[Vehicle] %s 高速撞击 %.0f m/s ── 机体解体坠毁" % [v.vehicle_id, impact])
		destroy_by_crash()
		return
	if impact >= v.crash_speed_severe:
		var target: String = "engine"
		if not mods.has(target):
			target = "fuel_tank"
		if not mods.has(target):
			target = mods.keys()[randi() % mods.size()]
		var dmg: float = impact * 6.0
		v.damage_system.hit_module(target, dmg, v.Module.DamageType.KINETIC, 0.0, v.crash_no_spall)
		print("[Vehicle] %s 严重撞击 %.0f m/s ── %s 损伤 %.0f" % [v.vehicle_id, impact, target, dmg])
	else:
		var target: String = mods.keys()[randi() % mods.size()]
		var dmg: float = impact * 3.0
		v.damage_system.hit_module(target, dmg, v.Module.DamageType.KINETIC, 0.0, v.crash_no_spall)
		print("[Vehicle] %s 撞击 %.0f m/s ── %s 损伤 %.0f" % [v.vehicle_id, impact, target, dmg])

func destroy_by_crash() -> void:
	var v = _get_vehicle()
	if v.damage_system == null:
		v.mark_network_destroyed()
		return
	for name in v.damage_system.modules.keys():
		if name.begins_with("crew_"):
			v.damage_system.hit_module(name, 99999.0, v.Module.DamageType.KINETIC, 0.0)
	if not v.damage_system.is_destroyed:
		v.mark_network_destroyed()
