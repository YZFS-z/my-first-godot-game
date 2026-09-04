extends Node
## 载具武器系统 - 武器槽管理、弹药管理、装填、导弹锁定
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态
## 注意：fire() 保留在 vehicle.gd 中（可能被子类重写）

func _get_vehicle() -> Node:
	return get_parent()

func setup_weapons(weapons_data: Array) -> void:
	var v = _get_vehicle()
	v.weapon_slots.clear()
	v._weapon_states.clear()
	for w in weapons_data:
		var wid = w.get("weapon_id", "")
		if wid == "":
			continue
		v.weapon_slots.append(w)
		v._weapon_states.append({
			"ammo_types": [],
			"current_ammo_index": 0,
			"ammo_counts": {},
			"is_reloading": false,
			"reload_timer": 0.0,
			"can_fire": true,
			"reload_time": w.get("reload_time", 6.0),
		})
	if v.weapon_slots.is_empty():
		return
	var primary_id = v.weapon_slots[0].get("weapon_id", "")
	var weapon_data = DataLoader.get_weapon(primary_id)
	if not weapon_data.is_empty():
		v.gun_elevation_min = weapon_data.get("elevation_min", -10.0)
		v.gun_elevation_max = weapon_data.get("elevation_max", 20.0)
	v.current_weapon_index = 0
	load_weapon_state(0)

func load_weapon_state(index: int) -> void:
	var v = _get_vehicle()
	if index < 0 or index >= v._weapon_states.size():
		return
	var state = v._weapon_states[index]
	v.ammo_types = state.ammo_types.duplicate(true)
	v.current_ammo_index = state.current_ammo_index
	v.ammo_counts = state.ammo_counts.duplicate(true)
	v.is_reloading = state.is_reloading
	v.reload_timer = state.reload_timer
	v.can_fire = state.can_fire
	v.reload_time = state.reload_time
	if v.ammo_types.is_empty():
		load_ammo_for_weapon(index)

func save_weapon_state(index: int) -> void:
	var v = _get_vehicle()
	if index < 0 or index >= v._weapon_states.size():
		return
	v._weapon_states[index] = {
		"ammo_types": v.ammo_types.duplicate(true),
		"current_ammo_index": v.current_ammo_index,
		"ammo_counts": v.ammo_counts.duplicate(true),
		"is_reloading": v.is_reloading,
		"reload_timer": v.reload_timer,
		"can_fire": v.can_fire,
		"reload_time": v.reload_time,
	}

func load_ammo_for_weapon(index: int) -> void:
	var v = _get_vehicle()
	if index < 0 or index >= v.weapon_slots.size():
		return
	var w = v.weapon_slots[index]
	var weapon_id = w.get("weapon_id", "")
	var weapon_data = DataLoader.get_weapon(weapon_id)
	if weapon_data.is_empty():
		return
	var capacity = w.get("ammo_capacity", 40)
	var types = weapon_data.get("ammo_types", [])
	var state = v._weapon_states[index]
	state.ammo_types.clear()
	state.ammo_counts.clear()
	state.current_ammo_index = 0
	state.can_fire = true
	state.is_reloading = false
	state.reload_timer = 0.0
	state.reload_time = w.get("reload_time", weapon_data.get("reload_time", 6.0))
	var per_type = int(capacity / max(types.size(), 1))
	for ammo in types:
		var name = ammo.get("name", "unknown")
		state.ammo_types.append(ammo)
		state.ammo_counts[name] = per_type
	if index == v.current_weapon_index:
		v.ammo_types = state.ammo_types.duplicate(true)
		v.current_ammo_index = state.current_ammo_index
		v.ammo_counts = state.ammo_counts.duplicate(true)
		v.can_fire = state.can_fire
		v.is_reloading = state.is_reloading
		v.reload_timer = state.reload_timer
		v.reload_time = state.reload_time

func setup_ammo() -> void:
	var v = _get_vehicle()
	for i in range(v.weapon_slots.size()):
		load_ammo_for_weapon(i)

func switch_weapon(index: int) -> void:
	var v = _get_vehicle()
	if index < 0 or index >= v.weapon_slots.size():
		return
	if index == v.current_weapon_index:
		return
	save_weapon_state(v.current_weapon_index)
	v.current_weapon_index = index
	load_weapon_state(index)
	var wid = v.weapon_slots[index].get("weapon_id", "")
	v.weapon_changed.emit(index, wid)
	print("[Vehicle] %s switched to weapon %d: %s" % [v.vehicle_id, index, wid])

func get_weapon_count() -> int:
	return _get_vehicle().weapon_slots.size()

func get_current_weapon_id() -> String:
	var v = _get_vehicle()
	if v.current_weapon_index < v.weapon_slots.size():
		return v.weapon_slots[v.current_weapon_index].get("weapon_id", "")
	return ""

func select_ammo(index: int) -> void:
	var v = _get_vehicle()
	if index < 0 or index >= v.ammo_types.size():
		return
	if index == v.current_ammo_index:
		return
	v.current_ammo_index = index
	v.is_reloading = true
	v.can_fire = false
	v.reload_timer = v.reload_time
	save_weapon_state(v.current_weapon_index)
	print("[Vehicle] %s selected ammo: %s, reloading..." % [v.vehicle_id, get_current_ammo_name()])

func find_next_ammo_with_rounds(from_index: int) -> int:
	var v = _get_vehicle()
	if v.ammo_types.is_empty():
		return -1
	for i in range(1, v.ammo_types.size() + 1):
		var idx = (from_index + i) % v.ammo_types.size()
		var name = v.ammo_types[idx].get("name", "?")
		if v.ammo_counts.get(name, 0) > 0:
			return idx
	return -1

func get_current_ammo_name() -> String:
	var v = _get_vehicle()
	if v.current_ammo_index < v.ammo_types.size():
		return v.ammo_types[v.current_ammo_index].get("name", "?")
	return "?"

func get_current_ammo_count() -> int:
	var v = _get_vehicle()
	var name = get_current_ammo_name()
	return v.ammo_counts.get(name, 0)

func get_reload_percent() -> float:
	var v = _get_vehicle()
	if not v.is_reloading or v.reload_time <= 0:
		return 1.0
	return 1.0 - (v.reload_timer / v.reload_time)

func get_reload_remaining_time() -> float:
	var v = _get_vehicle()
	if not v.is_reloading:
		return 0.0
	var loader_eff = v.get_loader_effectiveness()
	var reload_speed_factor = 0.4 + 0.6 * loader_eff
	if reload_speed_factor <= 0:
		return 999.0
	return v.reload_timer / reload_speed_factor

func update_reload(delta: float) -> void:
	"""每帧更新装填计时器（由 vehicle.gd 的 _physics_process 调用）"""
	var v = _get_vehicle()
	if v.is_reloading:
		var loader_eff = v.get_loader_effectiveness()
		var reload_speed_factor = 0.4 + 0.6 * loader_eff
		v.reload_timer -= delta * reload_speed_factor
		if v.reload_timer <= 0:
			v.is_reloading = false
			v.can_fire = true
			v.reload_timer = 0.0
			save_weapon_state(v.current_weapon_index)

func reduce_ammo(amount: int) -> void:
	var v = _get_vehicle()
	var ammo_name = get_current_ammo_name()
	if v.ammo_counts.has(ammo_name):
		v.ammo_counts[ammo_name] = max(0, v.ammo_counts[ammo_name] - amount)
		save_weapon_state(v.current_weapon_index)
		print("[Vehicle] %s lost %d rounds of %s, remaining: %d" % [v.vehicle_id, amount, ammo_name, v.ammo_counts[ammo_name]])

func get_current_ammo_data() -> Dictionary:
	var v = _get_vehicle()
	if v.current_ammo_index < v.ammo_types.size():
		return v.ammo_types[v.current_ammo_index]
	return {}

# === 导弹锁定系统 ===

func update_lock_on(delta: float) -> void:
	var v = _get_vehicle()
	var current_ammo = get_current_ammo_data()
	v.guidance_type = current_ammo.get("guidance", "none")
	v.lock_range = float(current_ammo.get("lock_range", 0.0))
	v.lock_fov = float(current_ammo.get("lock_fov", 0.0))
	v.lock_time = float(current_ammo.get("lock_time", 1.0))
	if v.guidance_type == "none" or v.lock_range <= 0.0:
		if v.locked_target:
			v.locked_target = null
			v.is_locking = false
			v.lock_progress = 0.0
			v.lock_status_changed.emit(null, false, 0.0)
		return
	if v.locked_target and (not is_instance_valid(v.locked_target) or ("is_destroyed" in v.locked_target and v.locked_target.is_destroyed)):
		v.locked_target = null
		v.is_locking = false
		v.lock_progress = 0.0
	v._lock_search_timer -= delta
	if v._lock_search_timer <= 0.0:
		v._lock_search_timer = 0.2
		find_lock_target()
	if v.is_locking and v.locked_target:
		v.lock_progress += delta / v.lock_time
		if v.lock_progress >= 1.0:
			v.lock_progress = 1.0
			v.is_locking = false
			var dist = v.global_position.distance_to(v.locked_target.global_position)
			v.lock_status_changed.emit(v.locked_target, true, dist)
	elif v.locked_target and v.lock_progress >= 1.0:
		var dist = v.global_position.distance_to(v.locked_target.global_position)
		var aim_dir = -v.global_transform.basis.z
		if v.muzzle_node:
			aim_dir = -v.muzzle_node.global_transform.basis.z
		aim_dir = aim_dir.normalized()
		var to_target = (v.locked_target.global_position - v.global_position).normalized()
		var angle = aim_dir.angle_to(to_target)
		var lose_angle = deg_to_rad(v.lock_fov * 1.5)
		if dist > v.lock_range * 1.2 or (v.lock_fov > 0 and angle > lose_angle):
			v.locked_target = null
			v.lock_progress = 0.0
			v.lock_status_changed.emit(null, false, 0.0)
		else:
			v.lock_status_changed.emit(v.locked_target, true, dist)

func find_lock_target() -> void:
	var v = _get_vehicle()
	if v.lock_range <= 0.0:
		return
	var aim_dir = -v.global_transform.basis.z
	if v.muzzle_node:
		aim_dir = -v.muzzle_node.global_transform.basis.z
	aim_dir = aim_dir.normalized()
	var fov_rad = deg_to_rad(v.lock_fov)
	var vehicles = v.get_tree().get_nodes_in_group("vehicle")
	var nearest: Node3D = null
	var nearest_dist = v.lock_range
	for veh in vehicles:
		if veh == v:
			continue
		if "is_destroyed" in veh and veh.is_destroyed:
			continue
		if "team" in veh and veh.team == v.team:
			continue
		var dist = v.global_position.distance_to(veh.global_position)
		if dist > nearest_dist:
			continue
		var to_target = (veh.global_position - v.global_position).normalized()
		var angle = aim_dir.angle_to(to_target)
		if angle > fov_rad:
			continue
		nearest_dist = dist
		nearest = veh
	if nearest:
		if nearest != v.locked_target:
			v.locked_target = nearest
			v.is_locking = true
			v.lock_progress = 0.0
			v.lock_status_changed.emit(v.locked_target, false, nearest_dist)
	elif v.locked_target and v.lock_progress < 1.0:
		v.locked_target = null
		v.is_locking = false
		v.lock_progress = 0.0
		v.lock_status_changed.emit(null, false, 0.0)

func get_lock_info() -> Dictionary:
	var v = _get_vehicle()
	return {
		"has_lock": v.locked_target != null and v.lock_progress >= 1.0,
		"is_locking": v.is_locking,
		"progress": v.lock_progress,
		"range": v.lock_range,
		"fov": v.lock_fov,
		"guidance": v.guidance_type,
		"target": v.locked_target,
		"distance": v.global_position.distance_to(v.locked_target.global_position) if v.locked_target else 0.0,
	}
