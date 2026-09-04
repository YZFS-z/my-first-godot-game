extends Node
## 载具维修系统 - 维修开始/完成、维修百分比、损坏模块统计
## 作为 Vehicle 节点的子节点，通过 get_parent() 访问共享状态
## 注意：_complete_repair() 保留在 vehicle.gd 中作为钩子（tank.gd 重写它），调用本组件的 complete_repair()

func _get_vehicle() -> Node:
	return get_parent()

func start_repair() -> void:
	var v = _get_vehicle()
	if v.is_destroyed:
		print("[Vehicle] %s 已损毁，无法维修" % v.vehicle_id)
		return
	if v.is_repairing:
		print("[Vehicle] %s 正在维修中" % v.vehicle_id)
		return
	if v.repair_cooldown > 0:
		print("[Vehicle] %s 维修冷却中: %.1fs" % [v.vehicle_id, v.repair_cooldown])
		return
	if not v.damage_system:
		return
	var airborne: bool = not v.is_on_floor()
	var target = ""
	var worst_health = 0.8
	for mod_name in v.damage_system.modules.keys():
		var mod = v.damage_system.modules[mod_name]
		if mod_name.begins_with("crew_") and mod.state == v.Module.ModuleState.DESTROYED:
			continue
		if airborne and (mod.state == v.Module.ModuleState.DESTROYED or mod_name in v.repair_ground_only_modules):
			continue
		var health_ratio = mod.current_health / mod.max_health
		if health_ratio < 0.8 and health_ratio < worst_health:
			worst_health = health_ratio
			target = mod_name
	if target == "":
		if airborne:
			print("[Vehicle] %s 飞行中：关键部件无法在空中维修，需着陆" % v.vehicle_id)
			return
		var dead_crew = 0
		for mod_name in v.damage_system.modules.keys():
			if mod_name.begins_with("crew_") and v.damage_system.modules[mod_name].state == v.Module.ModuleState.DESTROYED:
				dead_crew += 1
		if dead_crew > 0:
			print("[Vehicle] %s 阵亡乘员%d人不可维修，无其他可维修模块" % [v.vehicle_id, dead_crew])
		else:
			print("[Vehicle] %s 所有模块正常，无需维修" % v.vehicle_id)
		return
	v.repair_target = target
	v.is_repairing = true
	v.repair_timer = v.repair_duration
	v.input_throttle = 0.0
	v.input_steering = 0.0
	v.input_turret = 0.0
	v.input_gun = 0.0
	v._repair_saved_pos = v.global_position
	v._repair_saved_rot = v.rotation.y
	if v.turret_node:
		v._repair_saved_turret_rot = v.turret_node.rotation.y
	if v.gun_node:
		v._repair_saved_gun_rot = v.gun_node.rotation.x
	print("[Repair] 开始 - pos=(%.1f,%.1f,%.1f) body_rot.y=%.3f turret_rot.y=%.3f gun_rot.x=%.3f" % [
		v._repair_saved_pos.x, v._repair_saved_pos.y, v._repair_saved_pos.z,
		v._repair_saved_rot, v._repair_saved_turret_rot, v._repair_saved_gun_rot])
	print("[Vehicle] %s 开始维修: %s (%.0f%%), 需%.0f秒" % [v.vehicle_id, target, worst_health * 100, v.repair_duration])

func complete_repair() -> void:
	"""完成维修的具体逻辑（由 vehicle.gd 的 _complete_repair 钩子调用）"""
	var v = _get_vehicle()
	if v.repair_target != "" and v.damage_system and v.damage_system.modules.has(v.repair_target):
		var mod = v.damage_system.modules[v.repair_target]
		var target_health = mod.max_health * 0.8
		var repair_amount = target_health - mod.current_health
		if repair_amount > 0:
			mod.repair(repair_amount)
			print("[Vehicle] %s 维修完成: %s → %.0f%%" % [v.vehicle_id, v.repair_target, (mod.current_health / mod.max_health) * 100])
	v.is_repairing = false
	v.repair_target = ""
	v.repair_cooldown = 3.0
	if v.turret_node:
		v.turret_yaw = rad_to_deg(v.turret_node.rotation.y)
	if v.gun_node:
		v.gun_pitch = rad_to_deg(v.gun_node.rotation.x)
	print("[Repair] 完成 - turret_yaw=%.1f gun_pitch=%.1f turret_rot.y=%.3f gun_rot.x=%.3f" % [
		v.turret_yaw, v.gun_pitch, v.turret_node.rotation.y if v.turret_node else 0, v.gun_node.rotation.x if v.gun_node else 0])

func update_repair(delta: float) -> void:
	"""每帧更新维修计时器（由 vehicle.gd 的 _physics_process 调用）"""
	var v = _get_vehicle()
	if v.is_repairing:
		v.repair_timer -= delta
		if v.repair_timer <= 0:
			v._complete_repair()
	elif v.repair_cooldown > 0:
		v.repair_cooldown -= delta

func get_repair_percent() -> float:
	var v = _get_vehicle()
	if not v.is_repairing or v.repair_duration <= 0:
		return 0.0
	return 1.0 - (v.repair_timer / v.repair_duration)

func get_damaged_modules_count() -> int:
	var v = _get_vehicle()
	if not v.damage_system:
		return 0
	var count = 0
	for mod_name in v.damage_system.modules.keys():
		var mod = v.damage_system.modules[mod_name]
		if mod_name.begins_with("crew_") and mod.state == v.Module.ModuleState.DESTROYED:
			continue
		if mod.state > 0:
			count += 1
	return count

func has_repairable_modules() -> bool:
	return get_damaged_modules_count() > 0
