extends Node
## 载具网络同步 - 局域网/公网状态应用、插值、血量同步、击毁标记
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态

func _get_vehicle() -> Node:
	return get_parent()

func apply_network_state(position: Vector3, quaternion: Quaternion, turret_yaw: float, gun_pitch: float, speed: float, health: float, destroyed: bool, alpha: float, n_load: float, delta_a: float, delta_e: float, delta_r: float, fired: bool) -> void:
	var v = _get_vehicle()
	if v.is_destroyed:
		return
	if v.is_player_controlled:
		set_network_health(health)
		if destroyed:
			mark_network_destroyed()
		return
	v.net_target_position = position
	v.net_target_quat = quaternion
	v.net_target_turret_yaw = turret_yaw
	v.net_target_gun_pitch = gun_pitch
	v.net_speed = speed
	v.net_alpha = alpha
	v.net_n_load = n_load
	v.net_delta_a = delta_a
	v.net_delta_e = delta_e
	v.net_delta_r = delta_r
	v.net_destroyed = destroyed
	v.net_throttle = clamp(speed / 80.0, 0.0, 1.0)
	if not v.net_has_state:
		v.net_has_state = true
		v.global_position = position
		v.global_transform.basis = Basis(quaternion)
	if fired:
		v.fire_remote({})

func interpolate_network_state(delta: float) -> void:
	var v = _get_vehicle()
	if not v.net_has_state:
		return
	if v.is_player_controlled or (v.is_server_controlled and not v.is_remote_ai):
		return
	if v.net_destroyed and not v.is_destroyed:
		mark_network_destroyed()
		return
	var k: float = clamp(delta * 12.0, 0.0, 1.0)
	v.global_position = v.global_position.lerp(v.net_target_position, k)
	var cur_q: Quaternion = v.global_transform.basis.get_rotation_quaternion()
	v.global_transform.basis = Basis(cur_q.slerp(v.net_target_quat, k))
	v.turret_yaw = v.net_target_turret_yaw
	v.gun_pitch = v.net_target_gun_pitch
	if v.turret_node:
		v.turret_node.rotation.y = deg_to_rad(v.net_target_turret_yaw)
	if v.gun_node:
		v.gun_node.rotation.x = deg_to_rad(v.net_target_gun_pitch)
	if v.get("throttle") != null:
		v.set("throttle", lerpf(float(v.get("throttle")), v.net_throttle, k))

func set_network_health(percent: float) -> void:
	var v = _get_vehicle()
	if v.is_destroyed or v.damage_system == null:
		return
	v.damage_system.set_overall_health_floor(percent)
	v.health_changed.emit(v.get_health_percent())

func mark_network_destroyed() -> void:
	var v = _get_vehicle()
	if v.is_destroyed:
		return
	v.is_destroyed = true
	v.vehicle_destroyed.emit()
	v.velocity = Vector3.ZERO
	if v.has_method("stop_turret"):
		v.call("stop_turret")
	if not v.has_exploded:
		v.has_exploded = true
		var explode_pos = v.global_position + Vector3(0, 1.0, 0)
		EffectManager.play_explosion(explode_pos, 1.2)
		if v.is_inside_tree() and v.fire_effect == null:
			v.fire_effect = EffectManager.play_fire_smoke(v, Vector3(0, 0.8, 0))
	if v.nickname_label:
		v.nickname_label.modulate = Color(0.5, 0.5, 0.5, 0.6)
		v.nickname_label.text = v.nickname + " (已摧毁)"
