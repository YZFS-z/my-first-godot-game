extends SceneTree
## 校验：空中维修限制 + 维修不卡死 + 尾桨失效自旋（2026-08 新增）
## 覆盖六条约束：
##  1) 固定翼贴地维修可完成：start_repair 后 is_repairing 自动解除（回归「按维修卡住」bug：
##     airplane.gd/helicopter.gd 维修分支提前 return 跳过计时 → 永久卡在维修冻结态）
##  2) 贴地允许维修飞行关键部件（engine 降至 30% → 修到 80%）
##  3) 空中禁修：直升机空中 engine 受损 → start_repair 被拒绝（is_repairing 保持 false）
##  4) 空中允许维修名单外模块（ammo_rack 受损仍可空中修）
##  5) 尾桨健康时无自旋（非玩家直升机 rotation.y 稳定）
##  6) 尾桨受损/损毁 → 反扭矩失衡绕竖直轴自旋：半损转速 < 全毁转速，旋转方向一致
## 实现要点：与 check_crash_impact 同模式——_initialize 只 spawn 节点，
## setup_from_data 延迟到物理帧执行；非玩家载具走公共物理段（含维修计时/尾桨自旋）

const Module = preload("res://scripts/core/module.gd")

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _plane: Node = null
var _plane_setup := false
var _heli: Node = null
var _heli_setup := false
var _engine_hp_before: float = 1.0
var _yaw0: float = 0.0
var _yaw1: float = 0.0
var _yaw2: float = 0.0
var _dy_half: float = 0.0   # 尾桨半损 30 帧偏航增量（rad）
const PHASE_TIMEOUT: int = 1200

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _make_floor() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _spawn(scene_path: String, pos: Vector3) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = false
	v.is_server_controlled = false
	v.is_remote_ai = false
	v.team = 1
	root.add_child(v)
	v.global_position = pos
	return v

func _setup_vehicle(v: Node, json_path: String) -> void:
	var data: Dictionary = _load_json(json_path)
	data["model"] = {}   # 跳过外部模型加载（场景根自带主体碰撞）
	v.setup_from_data(data)

func _damage_module(v: Node, mod_name: String, ratio: float) -> void:
	var mod = v.damage_system.modules[mod_name]
	mod.current_health = mod.max_health * ratio
	# 直接赋值血量不会自动刷新状态（get_effectiveness 会按 OPERATIONAL 恒返回 1.0），
	# 需显式同步 state 才能让效率曲线/自旋生效
	mod.state = Module.ModuleState.DESTROYED if ratio <= 0.0 else Module.ModuleState.DAMAGED

func _mod_hp(v: Node, mod_name: String) -> float:
	var mod = v.damage_system.modules[mod_name]
	return mod.current_health / mod.max_health

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeAirRepairTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_floor()
	_plane = _spawn("res://scenes/airplane.tscn", Vector3(0.0, 10.0, 0.0))
	print("INFO: 场景就绪，开始空中维修/尾桨自旋校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if not _plane_setup:
		if _step >= 30:   # 等节点完成树内初始化（_ready 已建 damage_system）
			_plane_setup = true
			_setup_vehicle(_plane, "res://data/vehicles/plane_a10.json")
		return false
	match _phase:
		0:
			# 固定翼缓慢下坠贴地（速度 5 m/s < 轻伤阈值 12 → 落地不产生撞击损伤）
			_plane.velocity = Vector3(0.0, -5.0, 0.0)
			if _plane.is_on_floor():
				_plane.velocity = Vector3.ZERO
				_phase = 1
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "固定翼落地超时 (y=%.1f)" % _plane.global_position.y)
				_finish()
		1:
			# 落地稳定后：打伤 engine（名单内关键件，贴地允许修）→ 开始维修
			if _step >= 20:
				_damage_module(_plane, "engine", 0.3)
				_engine_hp_before = _mod_hp(_plane, "engine")
				_check(_engine_hp_before < 0.8, "engine 已损坏至 %.0f%%" % (_engine_hp_before * 100))
				_plane.start_repair()
				_check(_plane.is_repairing, "贴地 start_repair 进入维修（engine %.0f%%" % (_engine_hp_before * 100) + "）")
				_phase = 2
				_step = 0
		2:
			# 等待维修完成（repair_duration=8s=480帧）：修复前 bug 此阶段永远等不到，
			# is_repairing 恒 true（提前 return 跳过计时）→ 用超时断言回归
			if not _plane.is_repairing and _step >= 480:
				var hp := _mod_hp(_plane, "engine")
				_check(absf(hp - 0.8) < 0.01,
					"维修完成不卡死：engine 修至 %.0f%%（上限 80%%）" % (hp * 100))
				_check(not _plane.is_destroyed, "维修后未坠毁")
				_heli = _spawn("res://scenes/helicopter.tscn", Vector3(0.0, 40.0, 100.0))
				_phase = 3
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "贴地维修超时未完成（is_repairing=%s）——「按维修卡住」未修复" % str(_plane.is_repairing))
				_finish()
		3:
			# 直升机空中（非玩家无重力 → 恒悬空）：空中禁修关键部件
			if not _heli_setup:
				if _step >= 30:
					_heli_setup = true
					_setup_vehicle(_heli, "res://data/vehicles/heli_ah64.json")
				return false
			_damage_module(_heli, "engine", 0.3)
			_heli.start_repair()
			_check(not _heli.is_repairing, "空中 engine 受损 → 拒绝维修（须着陆）")
			_check(not _heli.is_on_floor(), "直升机确实处于空中 (y=%.1f)" % _heli.global_position.y)
			_phase = 4
			_step = 0
		4:
			# 空中可修名单外模块：ammo_rack 受损 → 允许维修并完成
			_damage_module(_heli, "ammo_rack", 0.3)
			_heli.start_repair()
			_check(_heli.is_repairing, "空中 ammo_rack 受损 → 允许维修（名单外模块）")
			_phase = 5
			_step = 0
		5:
			# 等待修完（480帧）+ 维修冷却（3s=180帧）
			if not _heli.is_repairing and _step >= 660:
				_check(absf(_mod_hp(_heli, "ammo_rack") - 0.8) < 0.01,
					"空中维修完成：ammo_rack 修至 %.0f%%" % (_mod_hp(_heli, "ammo_rack") * 100))
				_yaw0 = _heli.rotation.y
				_phase = 6
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "空中维修 ammo_rack 超时")
				_finish()
		6:
			# 尾桨健康：无外部转动源 → 30 帧内偏航稳定
			if _step >= 30:
				_check(absf(_heli.rotation.y - _yaw0) < 0.01,
					"尾桨健康时无自旋 (Δyaw=%.4f)" % (_heli.rotation.y - _yaw0))
				_damage_module(_heli, "tail_rotor", 0.5)   # 半损 → 效率≈0.25 → 自旋 1.5 rad/s
				_yaw1 = _heli.rotation.y
				_phase = 7
				_step = 0
		7:
			# 尾桨半损：绕竖直轴持续自旋（30帧≈0.5s，约 +0.75 rad）
			if _step >= 30:
				_dy_half = _heli.rotation.y - _yaw1
				_check(_dy_half > 0.3 and _dy_half < 1.8, "尾桨半损 → 机身自旋 (Δyaw=%.3f rad, 方向为正)" % _dy_half)
				_damage_module(_heli, "tail_rotor", 0.0)   # 打爆 → 效率 0 → 自旋 2.0 rad/s
				_yaw2 = _heli.rotation.y
				_phase = 8
				_step = 0
		8:
			# 尾桨全毁：自转更快且方向一致
			if _step >= 30:
				var dy2: float = _heli.rotation.y - _yaw2
				_check(dy2 > 0.5 and dy2 < 3.0, "尾桨全毁 → 自旋加剧 (Δyaw=%.3f rad)" % dy2)
				_check(dy2 > _dy_half, "尾桨全毁 30 帧自旋增量(%.3f) > 半损(%.3f)，方向一致" % [dy2, _dy_half])
				_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("\nALL PASS: 空中维修/尾桨自旋校验全部通过")
	else:
		print("\n%d FAILED" % _failed)
	quit(_failed)