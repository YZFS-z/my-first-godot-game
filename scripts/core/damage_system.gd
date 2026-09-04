extends Node3D
## 模块化伤害系统 - 挂载在载具上，管理所有模块的伤害计算
## 支持：模块命中检测、穿深计算、伤害传导、连锁效应（弹药殉爆等）

signal vehicle_destroyed()
signal module_hit(module_name: String, damage: float, penetrated: bool)
signal vehicle_fire_started()
signal vehicle_fire_extinguished()
signal ammo_exploded()  # 弹药殉爆（用于特效和弹药清零）
signal ammo_rack_damaged(rounds_lost: int)  # 弹药架被击伤，丢失弹药

const Module = preload("res://scripts/core/module.gd")

var modules: Dictionary = {}  # module_name -> Module节点
var is_destroyed: bool = false
var total_crew: int = 4
var alive_crew: int = 4

func _ready() -> void:
	# 查找所有子节点中的Module
	for child in get_children():
		if child is Module:
			modules[child.module_name] = child
			child.module_destroyed.connect(_on_module_destroyed.bind(child.module_name))

func register_module(module_node: Module) -> void:
	"""动态注册模块"""
	modules[module_node.module_name] = module_node
	module_node.module_destroyed.connect(_on_module_destroyed.bind(module_node.module_name))

func hit_module(module_name: String, damage: float, dmg_type: int, hit_angle: float = 0.0, skip_post_penetration := false, penetration: float = 0.0) -> Dictionary:
	"""命中指定模块，返回伤害结果字典。
	skip_post_penetration: 跳过穿甲后效（破片杀伤乘员）——供载具撞击等"结构冲击"类伤害使用，
	默认 false 不影响武器命中链路。"""
	var result = {
		"penetrated": false,
		"damage": 0.0,
		"module_destroyed": false,
		"vehicle_destroyed": false
	}

	if is_destroyed or not modules.has(module_name):
		return result

	var mod = modules[module_name]
	var actual_damage = mod.take_damage(damage, dmg_type, hit_angle, penetration)
	result["damage"] = actual_damage
	result["penetrated"] = actual_damage > damage * 0.1
	result["module_destroyed"] = mod.state == Module.ModuleState.DESTROYED

	# ── 穿甲后效（破片伤害）──（撞击专用伤害可跳过，见 hit_module 说明）
	if result["penetrated"] and not skip_post_penetration:
		_apply_post_penetration(module_name, damage, dmg_type)

	# ── 弹药架被击伤：丢失弹药 ──
	if module_name == "ammo_rack" and result["penetrated"]:
		var rounds_lost = randi_range(2, 6)
		ammo_rack_damaged.emit(rounds_lost)
		# 弹药越多，殉爆概率越高
		var explosion_chance = 0.15 + (actual_damage / max(mod.max_health, 1.0)) * 0.35
		if randf() < explosion_chance:
			_ammo_explosion()

	# ── 弹药架被摧毁：必定殉爆 ──
	if module_name == "ammo_rack" and result["module_destroyed"]:
		_ammo_explosion()

	# 发动机/油箱被击穿可能起火
	if (module_name == "engine" or module_name == "fuel_tank") and result["penetrated"]:
		if randf() < 0.25:
			_start_vehicle_fire()

	module_hit.emit(module_name, actual_damage, result["penetrated"])
	return result

func get_module(module_name: String) -> Module:
	return modules.get(module_name, null)

func get_module_health(module_name: String) -> float:
	if modules.has(module_name):
		return modules[module_name].current_health
	return 0.0

func get_module_state(module_name: String) -> int:
	if modules.has(module_name):
		return modules[module_name].state
	return Module.ModuleState.DESTROYED

func get_overall_health_percent() -> float:
	"""获取载具整体血量百分比（所有模块平均）"""
	if modules.is_empty():
		return 0.0
	var total = 0.0
	for mod in modules.values():
		total += mod.current_health / mod.max_health
	return total / modules.size()

func set_overall_health_floor(percent: float) -> void:
	"""客户端远程载具：按服务器整体血量百分比收敛血量（只降低不抬升）。
	不触发乘员阵亡判定——击毁状态一律由服务器 destroyed 标记决定，避免客户端提前判死。"""
	if modules.is_empty() or is_destroyed:
		return
	var target = clampf(percent, 0.0, 1.0)
	var cur = get_overall_health_percent()
	if cur <= target:
		return
	var scale = target / maxf(cur, 0.001)
	for mod in modules.values():
		mod.current_health = minf(mod.current_health, mod.max_health) * scale

func _apply_splash_damage(source_module: String, damage: float, dmg_type: int) -> void:
	"""对相邻模块施加溅射伤害"""
	for name in modules.keys():
		if name != source_module:
			modules[name].take_damage(damage * 0.5, dmg_type)

func _apply_post_penetration(source_module: String, damage: float, dmg_type: int) -> void:
	"""穿甲后效：破片和冲击波在车内杀伤车组和模块"""
	var crew_modules = []
	var other_modules = []
	for name in modules.keys():
		if name == source_module:
			continue
		if name.begins_with("crew_"):
			crew_modules.append(name)
		else:
			other_modules.append(name)

	if dmg_type == Module.DamageType.KINETIC:
		# 动能弹穿甲后效：破片飞溅，优先杀伤车组
		# 主破片：高概率杀伤1-2名车组
		var spall_count = randi_range(1, 3)
		for i in range(spall_count):
			if crew_modules.is_empty():
				break
			var idx = randi() % crew_modules.size()
			var target = crew_modules[idx]
			var spall_dmg = randf_range(damage * 0.25, damage * 0.55)
			modules[target].take_damage(spall_dmg, Module.DamageType.FRAGMENTATION)
			crew_modules.remove_at(idx)
		# 二次破片：可能损伤其他模块
		if randf() < 0.5 and not other_modules.is_empty():
			var idx = randi() % other_modules.size()
			modules[other_modules[idx]].take_damage(randf_range(damage * 0.1, damage * 0.25), Module.DamageType.FRAGMENTATION)
	else:
		# 爆炸弹穿甲后效：车内爆炸，全员受伤+模块损伤
		for name in crew_modules:
			modules[name].take_damage(randf_range(damage * 0.3, damage * 0.6), Module.DamageType.EXPLOSIVE)
		for name in other_modules:
			modules[name].take_damage(randf_range(damage * 0.15, damage * 0.35), Module.DamageType.EXPLOSIVE)

func _ammo_explosion() -> void:
	"""弹药殉爆 - 杀死所有车组乘员，摧毁所有模块，载具失去战斗力"""
	if is_destroyed:
		return
	# 发射殉爆信号（载具端清零弹药、播放大爆炸特效）
	ammo_exploded.emit()
	# 车组全员阵亡
	for mod in modules.values():
		if mod.module_name.begins_with("crew_"):
			mod.take_damage(999.0, Module.DamageType.EXPLOSIVE)
		else:
			mod.take_damage(300.0, Module.DamageType.EXPLOSIVE)
	_check_crew_destruction()
	print("[DamageSystem] AMMO EXPLOSION! Vehicle destroyed.")

func _start_vehicle_fire() -> void:
	"""载具起火 - 随机点燃一个模块"""
	var burnable = []
	for name in modules.keys():
		if modules[name].state != Module.ModuleState.DESTROYED:
			burnable.append(name)
	if not burnable.is_empty():
		var target = burnable[randi() % burnable.size()]
		modules[target].start_fire()
		vehicle_fire_started.emit()

func _on_module_destroyed(module_name: String) -> void:
	"""模块被摧毁时检查车组状态"""
	if module_name.begins_with("crew_"):
		alive_crew = _count_alive_crew()
		_check_crew_destruction()

func _count_alive_crew() -> int:
	"""统计仍有战斗力的车组乘员数量"""
	var count = 0
	for name in modules.keys():
		if name.begins_with("crew_"):
			if modules[name].state != Module.ModuleState.DESTROYED:
				count += 1
	return count

func _check_crew_destruction() -> void:
	"""检查是否所有车组乘员都失去战斗力，若是则载具被击毁"""
	if is_destroyed:
		return
	var alive = _count_alive_crew()
	alive_crew = alive
	if alive <= 0:
		is_destroyed = true
		vehicle_destroyed.emit()
		print("[DamageSystem] Vehicle destroyed: all crew knocked out")

func get_alive_crew_count() -> int:
	return _count_alive_crew()

func get_total_crew_count() -> int:
	var count = 0
	for name in modules.keys():
		if name.begins_with("crew_"):
			count += 1
	return count

func repair_all() -> void:
	for mod in modules.values():
		if mod.state != Module.ModuleState.DESTROYED:
			mod.repair(mod.max_health)
	# 只有仍有存活车组时才能恢复战斗力
	if _count_alive_crew() > 0:
		is_destroyed = false
