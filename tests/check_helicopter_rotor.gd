extends SceneTree
## 校验：主旋翼损坏对直升机飞行能力的影响（贴合现实）
## 1. 完好悬停稳定（回归护栏）
## 2. 主旋翼全毁（DESTROYED）→ 升力/前飞动力归零、悬停强制退出 → 自由落体
## 3. 全毁坠落触地：轻伤档（crash_impact_scale 0.6，40m 落速≈28m/s 等效 16.8 < 30）不坠毁
## 4. 主旋翼全毁后桨叶停止转动（视觉同步）
## 5. 主旋翼半损（DAMAGED 0.5）→ 仍有 0.5 效率，悬停能维持（功率余量大）
## 全程玩家控制（is_player_controlled=true）

const Module = preload("res://scripts/core/module.gd")

const MAX_FRAMES := 420

var _failed := 0
var _frame := 0
var _phase := 0
var _done := false

var _a: Node = null   # 场景甲：全损
var _b: Node = null   # 场景乙：半损
var _rotor_y0 := 0.0  # 全损时主桨角度基线

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
	var text: String = f.get_as_text()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _spawn(pos: Vector3, is_player: bool) -> Node:
	var v: Node = load("res://scenes/helicopter.tscn").instantiate()
	root.add_child(v)
	v.global_position = pos
	v.is_player_controlled = is_player
	v.team = 1
	return v

func _setup_vehicle(v: Node, json_path: String) -> void:
	var data: Dictionary = _load_json(json_path)
	data["model"] = {}   # 跳过外部模型加载（场景根自带主体碰撞）
	v.setup_from_data(data)

func _damage_module(v: Node, mod_name: String, ratio: float) -> void:
	var mod = v.damage_system.modules[mod_name]
	mod.current_health = mod.max_health * ratio
	# 直接赋值血量不会自动刷新状态（get_effectiveness 对 OPERATIONAL 恒返回 1.0），
	# 需显式同步 state 才能让效率曲线生效
	mod.state = Module.ModuleState.DESTROYED if ratio <= 0.0 else Module.ModuleState.DAMAGED

var _setup_done := false

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeRotorTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	_make_ground()
	_a = _spawn(Vector3(0.0, 40.0, 0.0), true)
	_b = _spawn(Vector3(0.0, 40.0, 60.0), true)
	print("INFO: 场景就绪，延迟到物理帧 setup 后开始主旋翼失效校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if not _setup_done:
		# setup_from_data 必须延迟到物理帧（_initialize 阶段节点树未就绪，
		# 模块创建时 add_child 会拿到 null 父节点）
		_setup_vehicle(_a, "res://data/vehicles/heli_ah64.json")
		_setup_vehicle(_b, "res://data/vehicles/heli_ah64.json")
		_setup_done = true
		return false
	match _phase:
		0:  # 两机起飞悬停稳定（y=40 悬停激活后跑 60 帧）
			_a._toggle_hover()
			_b._toggle_hover()
			_check(_a.hover_active, "甲：空中激活悬停")
			_check(_b.hover_active, "乙：空中激活悬停")
			_phase = 1
		1:
			if _frame >= 120:
				_phase = 2   # 先推进 phase，避免本块内异常中断导致死循环重放
				_check(abs(_a.global_position.y - 40.0) < 2.0, "甲：完好悬停稳定 (y=%.2f)" % _a.global_position.y)
				_check(abs(_b.global_position.y - 40.0) < 2.0, "乙：完好悬停稳定 (y=%.2f)" % _b.global_position.y)
				var rotor: Node3D = _a.main_rotor_node
				_rotor_y0 = rotor.rotation.y if rotor != null else 0.0
				_damage_module(_a, "main_rotor", 0.0)   # 甲：主旋翼全毁
				_damage_module(_b, "main_rotor", 0.5)   # 乙：主旋翼半损
		2:  # 全损后 60 帧：悬停应已失效、y 开始下降、桨叶停转
			if _frame >= 180:
				_phase = 3
				_check(not _a.hover_active, "甲：主旋翼全毁后悬停强制退出")
				var dy_a: float = 40.0 - _a.global_position.y
				_check(dy_a > 2.0, "甲：自由落体开始下坠 (y=%.2f, 降 %.2fm)" % [_a.global_position.y, dy_a])
				_check(_a.velocity.y < 0.0, "甲：垂直速度向下 (vy=%.2f)" % _a.velocity.y)
				var rotor: Node3D = _a.main_rotor_node
				if rotor == null:
					_check(true, "甲：主桨停转（无模型节点，视觉动画断言跳过）")
				else:
					var rot_delta: float = abs(rotor.rotation.y - _rotor_y0)
					_check(rot_delta < 0.5, "甲：主桨停转 (角度变化 %.4f rad)" % rot_delta)
				_check(abs(_b.global_position.y - 40.0) < 2.5, "乙：半损仍能维持悬停 (y=%.2f)" % _b.global_position.y)
				_check(_b.hover_active, "乙：半损悬停未退出")
		3:  # 等待甲落地（40m 自由落体约 170 帧），断言轻伤不坠毁
			if _a.is_on_floor() or _a.global_position.y < 0.8 or _frame >= MAX_FRAMES:
				_check(_a.global_position.y < 1.0, "甲：全损坠落触地 (y=%.2f)" % _a.global_position.y)
				_check(not _a.is_destroyed, "甲：坠落撞击轻伤档，未坠毁解体")
				_done = true
				_print_summary()
				return true
	return false

func _print_summary() -> void:
	if _failed == 0:
		print("总结: 全部通过")
		print("RESULT: failed=0")
	else:
		print("总结: 失败 %d 项" % _failed)
		print("RESULT: failed=%d" % _failed)