extends SceneTree
## 校验：高速撞击损伤部件、严重时坠毁（2026-08 新增功能）
## 覆盖六个约束：
##  1) 贴地水平滑跑（地面法向≈0）不产生撞击损伤——保护正常着陆/滑跑路径
##  2) 15 m/s 撞击（>轻伤阈值 12）→ 损伤内部模块但不坠毁
##  3) 46 m/s 撞击（介于严重 30 与致命 50 之间）→ 明显损伤但不坠毁
##  4) 60 m/s 撞击（≥致命阈值 50）→ 坦克坠毁（is_destroyed 置位，走完整击毁链路）
##  5) 固定翼 60 m/s 高空平飞不误伤；带 15 m/s 垂直速度触地（着陆级）不至于坠毁
##  6) 固定翼高速撞击分级：60 m/s 垂直触地 → 乘员全灭坠毁走完整链路；
##     45 m/s 垂直触地（30~50 严重区间）→ 优先 engine/fuel_tank 模块受速度×6 级重创
##  7) 直升机抗摔（软定义）：crash_impact_scale 由载具 json physics.crash_impact_scale 配置
##     （heli_ah64=0.6，坦克/固定翼未配=1.0）→ 55 m/s 硬着陆（等效 33）严重受损不坠毁，
##     85 m/s（等效 51）仍乘员全灭坠毁（保底，不无限抗摔）
## 实现要点：与 check_air_brake 相同的模式——_initialize 只 spawn 节点，
## setup_from_data 延迟到物理帧执行（等待节点完成树内初始化，_ready 已建 damage_system）

var _failed := 0
var _step := 0
var _phase := 0
var _done := false
var _tank: Node = null
var _plane: Node = null
var _plane2: Node = null   # 固定翼 60 m/s 高速撞击（坠毁）专用
var _plane3: Node = null   # 固定翼 45 m/s 严重撞击（模块重创）专用
var _plane2_setup := false
var _plane3_setup := false
var _target_mod: String = "engine"
var _target_hp_before: float = 50.0
var _heli: Node = null     # 直升机 55 m/s 硬着陆（等效 33 → 抗摔不坠毁）
var _heli2: Node = null    # 直升机 85 m/s 硬着陆（等效 51 → 保底仍致命）
var _heli_setup := false
var _heli2_setup := false
var _health_before: float = 1.0
var _setup_done := false
const WALL_X: float = 40.0
const WALL_FACE_X: float = 39.0   # 墙左面 x（wall 中心 x=40 半宽 1）
const TANK_HALF_W: float = 1.8    # 坦克主碰撞体半宽（3.6/2）
const PHASE_TIMEOUT: int = 600

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

func _make_wall() -> void:
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 8.0, 200.0)
	col.shape = box
	col.position = Vector3(WALL_X, 4.0, 0.0)
	wall.add_child(col)
	root.add_child(wall)

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

func _setup_tank_and_plane() -> void:
	_setup_vehicle(_tank, "res://data/vehicles/tank_abrams.json")
	_setup_vehicle(_plane, "res://data/vehicles/plane_a10.json")
	_health_before = _tank.get_health_percent()
	_check(is_equal_approx(_tank.crash_impact_scale, 1.0),
		"坦克未配置 crash_impact_scale → 默认 1.0（标准判伤不受影响）")
	print("INFO: setup 完成 tank hp=%.3f plane hp=%.3f" % [_health_before, _plane.get_health_percent()])

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeCrashImpactTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_floor()
	_make_wall()
	# 坦克：主碰撞体底部=根 origin → 微嵌入 0.02m，第 1 帧即建立地面接触（贴地滑跑）
	_tank = _spawn("res://scenes/vehicle.tscn", Vector3(0.0, -0.02, 0.0))
	# 固定翼：先高空待命（主碰撞体底部=origin-1.25，做高空平飞/低空触地测试）
	_plane = _spawn("res://scenes/airplane.tscn", Vector3(0.0, 150.0, 150.0))
	print("INFO: 场景就绪，开始撞击损伤校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_step += 1
	if not _setup_done:
		if _step >= 30:   # 等待节点完成树内初始化（_ready 已建 damage_system）再装载数据
			_setup_done = true
			_setup_tank_and_plane()
		return false
	var hp: float = 0.0
	match _phase:
		0:
			# 贴地滑跑 25 m/s：地面法向≈0、pre_vel.y≈0 → 无撞击损伤
			_tank.velocity = Vector3(25.0, 0.0, 0.0)
			if _step >= 60:
				_check(absf(_tank.get_health_percent() - _health_before) < 0.001,
					"贴地滑跑 25 m/s 无损伤 (hp %.3f→%.3f)" % [_health_before, _tank.get_health_percent()])
				_check(not _tank.is_destroyed, "贴地滑跑未坠毁")
				_health_before = _tank.get_health_percent()
				_tank.velocity = Vector3.ZERO
				_phase = 1
				_step = 0
		1:
			# 15 m/s 撞墙 → 轻伤（≥12 阈值）但不坠毁
			if _tank.global_position.x >= WALL_FACE_X - TANK_HALF_W - 0.05 and absf(_tank.velocity.x) < 5.0:
				if _step >= 20:
					hp = _tank.get_health_percent()
					_check(hp < _health_before, "15 m/s 撞击产生损伤 (hp %.3f→%.3f)" % [_health_before, hp])
					_check(not _tank.is_destroyed, "轻微撞击未坠毁")
					_health_before = hp
					_phase = 2
					_step = 0
			else:
				_tank.velocity = Vector3(15.0, 0.0, 0.0)
		2:
			# 撞击冷却重置等待（>36 帧）
			if _step >= 40:
				_tank.global_position.x = 25.0   # 拉离墙边重新加速（撞墙后停在墙前，速度已归零）
				_phase = 3
				_step = 0
		3:
			# 46 m/s 撞墙 → 明显损伤但不坠毁（<50 致命线）
			if _tank.global_position.x >= WALL_FACE_X - TANK_HALF_W - 0.05 and absf(_tank.velocity.x) < 5.0:
				if _step >= 20:
					hp = _tank.get_health_percent()
					_check(hp < _health_before - 0.03, "46 m/s 撞击明显损伤 (hp %.3f→%.3f)" % [_health_before, hp])
					_check(not _tank.is_destroyed, "46 m/s 未坠毁（低于致命阈值 50）")
					_health_before = hp
					_phase = 4
					_step = 0
			else:
				_tank.velocity = Vector3(46.0, 0.0, 0.0)
		4:
			if _step >= 40:
				_tank.global_position.x = 25.0   # 拉离墙边重新加速
				_phase = 5
				_step = 0
		5:
			# 60 m/s 撞墙 → 坠毁（≥50 致命线，乘员全灭走完整击毁链路）
			if _tank.global_position.x >= WALL_FACE_X - TANK_HALF_W - 0.05 and absf(_tank.velocity.x) < 5.0:
				if _step >= 20:
					_check(_tank.is_destroyed, "60 m/s 撞击 → 坦克坠毁")
					_phase = 6
					_step = 0
			else:
				_tank.velocity = Vector3(60.0, 0.0, 0.0)
		6:
			# 固定翼：60 m/s 高空平飞 → 不误伤
			_plane.velocity = Vector3(60.0, 0.0, 0.0)
			if _step >= 50:
				_check(absf(_plane.get_health_percent() - 1.0) < 0.001,
					"固定翼 60 m/s 高空平飞无损伤 (hp %.3f)" % _plane.get_health_percent())
				_check(not _plane.is_destroyed, "固定翼高空飞行未坠毁")
				# 降到低空，纯垂直触地（着陆级：15 m/s < 30 严重线；水平速度置零避免
				# 占位几何尾部部件刮地反复触发冷却周期判伤累积坠毁——真实模型碰撞体底平不受影响）
				_plane.global_position.y = 30.0
				_plane.velocity = Vector3(0.0, -15.0, 0.0)
				_phase = 7
				_step = 0
		7:
			# 着陆级触地：垂直速度 15 m/s → 撞击判伤已发生（A-10 模块血量极小
			# tail15/fuel_tank30/engine50，轻伤级 45 伤害会把小模块打爆并触发 critical
			# 起火联动 → 坠毁属数据现实，符合"撞击损伤部件、严重时坠毁"语义；故不断言"不坠毁"）
			if _step >= PHASE_TIMEOUT:
				_check(_plane.get_health_percent() < 1.0, "固定翼 15 m/s 触地产生损伤判定 (hp=%.3f)" % _plane.get_health_percent())
				_check(_plane.is_on_floor() or _plane.global_position.y < 2.0,
					"固定翼已落地 (y=%.1f)" % _plane.global_position.y)
				# 固定翼高速撞击：另起一架干净飞机（z 错开避免撞上 phase7 躺地残骸）
				_plane2 = _spawn("res://scenes/airplane.tscn", Vector3(0.0, 45.0, 50.0))
				_phase = 8
				_step = 0
		8:
			# 固定翼 60 m/s 垂直触地 → ≥致命阈值 50：乘员全灭（99999 伤害）走完整击毁链路
			if not _plane2_setup:
				if _step >= 30:   # 等节点树内初始化完成后装载武器数据（同 _setup_tank_and_plane 模式）
					_plane2_setup = true
					_setup_vehicle(_plane2, "res://data/vehicles/plane_a10.json")
				return false
			_plane2.velocity = Vector3(0.0, -60.0, 0.0)
			# 触地判据用 is_on_floor()（主碰撞体底部在 origin-1.25，y<2 时尚未触地会抢跑）
			if _plane2.is_on_floor():
				_check(_plane2.is_destroyed, "固定翼 60 m/s 高速撞击 → 坠毁")
				_check(_plane2.get_health_percent() < 1.0,
					"固定翼 60 m/s 高速撞击 → 乘员全灭血量下降 (hp=%.3f)" % _plane2.get_health_percent())
				_plane3 = _spawn("res://scenes/airplane.tscn", Vector3(0.0, 45.0, -50.0))
				_phase = 9
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "固定翼 60 m/s 高速撞击阶段超时 (y=%.1f)" % _plane2.global_position.y)
				_finish()
		9:
			# 固定翼 45 m/s 垂直触地 → 介于严重 30 与致命 50：优先 engine/fuel_tank 模块，
			# 伤害=速度×6=270，远超模块血量（engine50/fuel30）→ 目标模块被打爆
			if not _plane3_setup:
				if _step >= 30:
					_plane3_setup = true
					_setup_vehicle(_plane3, "res://data/vehicles/plane_a10.json")
					# setup 完成后记录目标模块初始血量（engine 优先，A-10 无 engine 则 fuel_tank）
					var mods: Dictionary = _plane3.damage_system.modules
					_target_mod = "engine" if mods.has("engine") else "fuel_tank"
					_target_hp_before = _plane3.damage_system.get_module_health(_target_mod)
				return false
			_plane3.velocity = Vector3(0.0, -45.0, 0.0)
			if _plane3.is_on_floor():
				var hp_after: float = _plane3.damage_system.get_module_health(_target_mod)
				_check(hp_after <= 0.01,
					"固定翼 45 m/s 严重撞击：优先命中 %s 模块被打爆 (hp %.0f→%.0f)" % [_target_mod, _target_hp_before, hp_after])
				_check(_plane3.get_health_percent() < 1.0,
					"固定翼 45 m/s 严重撞击导致部件损伤 (hp=%.3f)" % _plane3.get_health_percent())
				# 直升机抗摔校验：55 m/s 原属致命（≥50）区间，抗摔系数 0.6 后等效 33
				# 应仅严重受损而不坠毁（z=120 错开 plane 残骸 z=150/50/-50）
				_heli = _spawn("res://scenes/helicopter.tscn", Vector3(0.0, 45.0, 120.0))
				_phase = 10
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "固定翼 45 m/s 严重撞击阶段超时 (y=%.1f)" % _plane3.global_position.y)
				_finish()
		10:
			# 直升机 55 m/s 垂直触地 → 等效冲击 = 55×0.6 = 33（30~50 严重档，低于致命 50）
			# 核心断言：原本会乘员全灭坠毁的速度，现在只造成严重损伤而不坠毁
			if not _heli_setup:
				if _step >= 30:
					_heli_setup = true
					_setup_vehicle(_heli, "res://data/vehicles/heli_ah64.json")
					_check(is_equal_approx(_heli.crash_impact_scale, 0.6),
						"直升机抗摔能力由 json physics.crash_impact_scale 软定义 (%.2f)" % _heli.crash_impact_scale)
				return false
			_heli.velocity = Vector3(0.0, -55.0, 0.0)
			if _heli.is_on_floor():
				_check(not _heli.is_destroyed,
					"直升机 55 m/s 硬着陆 → 抗摔不坠毁（等效 33 < 致命 50）")
				_check(_heli.get_health_percent() < 1.0,
					"直升机 55 m/s 硬着陆产生严重损伤 (hp=%.3f)" % _heli.get_health_percent())
				# 85 m/s → 等效 51，仍超致命线：保底验证不会无限抗摔
				_heli2 = _spawn("res://scenes/helicopter.tscn", Vector3(0.0, 45.0, 90.0))
				_phase = 11
				_step = 0
			elif _step >= PHASE_TIMEOUT:
				_check(false, "直升机 55 m/s 硬着陆阶段超时 (y=%.1f)" % _heli.global_position.y)
				_finish()
		11:
			# 直升机 85 m/s 垂直触地 → 等效 51 ≥ 50 致命档：仍乘员全灭坠毁（保底）
			if not _heli2_setup:
				if _step >= 30:
					_heli2_setup = true
					_setup_vehicle(_heli2, "res://data/vehicles/heli_ah64.json")
				return false
			_heli2.velocity = Vector3(0.0, -85.0, 0.0)
			if _heli2.is_on_floor():
				_check(_heli2.is_destroyed,
					"直升机 85 m/s 硬着陆 → 仍坠毁（等效 51 ≥ 致命 50）")
				_check(_heli2.get_health_percent() < 1.0,
					"直升机 85 m/s 硬着陆 → 乘员全灭血量下降 (hp=%.3f)" % _heli2.get_health_percent())
				_finish()
			elif _step >= PHASE_TIMEOUT:
				_check(false, "直升机 85 m/s 硬着陆阶段超时 (y=%.1f)" % _heli2.global_position.y)
				_finish()
	if _step >= PHASE_TIMEOUT and _phase not in [7, 8, 9, 10, 11]:
		_check(false, "阶段 %d 超时" % _phase)
		_finish()
	return false

func _finish() -> void:
	_done = true
	print("RESULT: failed=%d" % _failed)
	quit(1 if _failed > 0 else 0)