extends SceneTree
## 校验：所有武器「按住开火键连续射击」（hold-to-fire 每帧轮询）
## 1. 固定翼：移动端 fire_held 按住 → 装填门控下连续开火（0.5s/发），松开停止
## 2. 固定翼：桌面端 fire 动作（鼠标左键）按住 → 连续开火，松开停止
## 3. 直升机：移动端 fire_held 按住 → 连续开火，松开停止
## 4. 坦克：移动端 fire_held 按住 → 主炮装填完成后自动续射（5s/发门控），松开停止
## 5. 事件驱动已移除：开火只由按住状态轮询驱动，无双重触发

const MAX_FRAMES := 360

var _failed := 0
var _frame := 0
var _phase := 0
var _mobile: Node = null
var _airplane: Node = null
var _heli: Node = null
var _tank: Node = null
var _sm: Node = null
var _ammo0 := 0
var _done := false

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

func _spawn_mobile() -> Node:
	var ml := CanvasLayer.new()
	ml.name = "MobileControlsTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	return ml

func _spawn_vehicle(scene_path: String, json_path: String, spawn_pos: Vector3 = Vector3(0, 500, 0)) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = false
	v.team = 1
	# 物理体入树前先就位：若三载具都按默认 (0,0,0) 同点入树，解算器会把重叠体"挤飞"
	# （可达数千 m/s 幽灵速度），纠缠后各帧随机触发撞击误判 → 开火段载具早死、断言间歇失败。
	v.global_position = spawn_pos
	root.add_child(v)
	v.setup_from_data(_load_json(json_path))
	return v

func _ammo_of(v: Node) -> int:
	var name = v.get_current_ammo_name()
	return v.ammo_counts.get(name, 0)

func _initialize() -> void:
	# --script 模式下没有 current_scene，挂一个假场景节点
	var fake_scene := Node.new()
	fake_scene.name = "FakeFireHeldTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面（物理结算需要）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	_sm = root.get_node_or_null("SettingsManager")
	if _sm == null:
		_sm = Node.new()
		_sm.name = "SettingsManager"
		_sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(_sm)
	_mobile = _spawn_mobile()
	print("INFO: 载具挂载准备完成，开始生成三载具...")
	_phase = 0

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES * 8:
		print("FAIL: 测试全局超时")
		_finish()
		return false
	match _phase:
		0:
			if _mobile.is_inside_tree() and _frame > 8:
				_airplane = _spawn_vehicle("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json", Vector3(0, 120, 0))
				_heli = _spawn_vehicle("res://scenes/helicopter.tscn", "res://data/vehicles/heli_ah64.json", Vector3(0, 150, 0))
				_tank = _spawn_vehicle("res://scenes/vehicle.tscn", "res://data/vehicles/tank_abrams.json", Vector3(0, 1, 0))
				_phase = 1
				_frame = 0
		1:
			if _airplane.is_inside_tree() and _heli.is_inside_tree() and _tank.is_inside_tree() and _frame > 8:
				_airplane.global_position = Vector3(0, 120, 0)
				_heli.global_position = Vector3(0, 150, 0)
				_tank.global_position = Vector3(0, 1, 0)
				# 隔离：仅固定翼玩家控制
				_heli.is_player_controlled = false
				_tank.is_player_controlled = false
				_check(_airplane.can_fire, "前置：固定翼初始可开火")
				_ammo0 = _ammo_of(_airplane)
				_check(_ammo0 > 0, "前置：固定翼有备弹 (%d)" % _ammo0)
				# 移动端按住开火
				_mobile._on_fire_down()
				_check(_mobile.fire_held, "移动端：按钮按下→fire_held=true")
				_phase = 2
				_frame = 0
		2:
			# 按住 1.5s（机炮装填 0.5s → 理想约3发），期间持续悬空重置防止触地
			_airplane.global_position = Vector3(0, 120, 0)
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_airplane)
				_check(spent >= 2, "固定翼：移动端按住→连续开火≥2发 (消耗%d)" % spent)
				_ammo0 = _ammo_of(_airplane)
				_mobile._on_fire_up()
				_check(not _mobile.fire_held, "移动端：按钮松开→fire_held=false")
				_phase = 3
				_frame = 0
		3:
			_airplane.global_position = Vector3(0, 120, 0)
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_airplane)
				_check(spent == 0, "固定翼：移动端松开→停止开火 (消耗%d)" % spent)
# ── 桌面端：fire 动作（鼠标左键）按住 ──
				# 新语义：存在移动端节点时仅认 fire_held（防触摸模拟鼠标误触）；纯桌面无移动端才认 fire 动作。
				# 此段模拟纯桌面环境：先移出移动端节点，断言 fire 动作仍可正常开火
				if _mobile != null and _mobile.is_inside_tree():
					root.remove_child(_mobile)
				_ammo0 = _ammo_of(_airplane)
				Input.action_press("fire")
				_phase = 4
				_frame = 0
		4:
			_airplane.global_position = Vector3(0, 120, 0)
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_airplane)
				_check(spent >= 2, "固定翼：桌面端fire动作按住→连续开火≥2发 (消耗%d)" % spent)
				_ammo0 = _ammo_of(_airplane)
				Input.action_release("fire")
				_phase = 5
				_frame = 0
		5:
			_airplane.global_position = Vector3(0, 120, 0)
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_airplane)
				_check(spent == 0, "固定翼：桌面端松开→停止开火 (消耗%d)" % spent)
				# 移回移动端节点，继续验证直升机/坦克移动端 fire_held 链路
				if _mobile != null and not _mobile.is_inside_tree():
					root.add_child(_mobile)
				# ── 直升机：移动端按住 ──
				_airplane.is_player_controlled = false
				_heli.is_player_controlled = true
				_check(_heli.can_fire, "前置：直升机初始可开火")
				_ammo0 = _ammo_of(_heli)
				_check(_ammo0 > 0, "前置：直升机有备弹 (%d)" % _ammo0)
				_mobile._on_fire_down()
				_phase = 6
				_frame = 0
		6:
			_heli.global_position = Vector3(0, 150, 0)
			if _frame >= 120:
				var spent: int = _ammo0 - _ammo_of(_heli)
				_check(spent >= 1, "直升机：移动端按住→连续开火≥1发 (消耗%d)" % spent)
				_ammo0 = _ammo_of(_heli)
				_mobile._on_fire_up()
				_phase = 7
				_frame = 0
		7:
			_heli.global_position = Vector3(0, 150, 0)
			if _frame >= 120:
				var spent: int = _ammo0 - _ammo_of(_heli)
				_check(spent == 0, "直升机：移动端松开→停止开火 (消耗%d)" % spent)
				# ── 坦克：移动端按住（测试打桩装填0.5s快速验证连发；不改游戏配置）──
				# 注：测试环境未初始化乘员组 → loader效能0 → 真实5s装填变12.5s太慢，
				# 与 check_air_loop 打桩推力同理，此处仅加速装填门控验证
				_heli.is_player_controlled = false
				_tank.is_player_controlled = true
				_tank.is_reloading = false
				_tank.can_fire = true
				_tank.reload_timer = 0.0
				_tank.reload_time = 0.5
				_check(_tank.can_fire, "前置：坦克可开火（打桩装填0.5s）")
				_ammo0 = _ammo_of(_tank)
				_check(_ammo0 > 0, "前置：坦克有备弹 (%d)" % _ammo0)
				_mobile._on_fire_down()
				_phase = 8
				_frame = 0
		8:
			# 按住 1.5s（打桩装填0.5s/发 → 理想约3发）：验证装填完成后自动续射
			_heli.global_position = Vector3(0, 150, 0)  # 直升机测试已结束：保持悬空，避免无控制自由落体撞地噪音
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_tank)
				_check(spent >= 2, "坦克：移动端按住→装填完成后自动续射≥2发 (消耗%d)" % spent)
				_ammo0 = _ammo_of(_tank)
				_mobile._on_fire_up()
				_phase = 9
				_frame = 0
		9:
			if _frame >= 90:
				var spent: int = _ammo0 - _ammo_of(_tank)
				_check(spent == 0, "坦克：移动端松开→停止开火 (消耗%d)" % spent)
				_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
