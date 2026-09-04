extends SceneTree
## 校验：移动端开火门控（点屏幕任意位置不再误开火）
## 背景：移动端触摸会模拟鼠标左键 → Input.is_action_pressed("fire") 在任意触摸时恒真；
## 飞机/直升机原先 `Input... or mobile.fire_held` 导致任意点击屏幕都触发开火。
## 修复后（与 tank.gd 口径一致）：有移动端只认开火按钮 fire_held，无移动端认 fire 动作。
## 1. 有移动端：fire 动作按下（模拟触摸）→ 不消耗弹药（不误开火）
## 2. 有移动端：fire_held=true → 消耗弹药（开火按钮按住连发）
## 3. 无移动端：fire 动作按下 → 消耗弹药（PC 鼠标左键行为不变）

const MAX_FRAMES := 300

var _failed := 0
var _frame := 0
var _phase := 0
var _done := false
var _mobile: Node = null
var _plane: Node = null
var _ammo0 := 0

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
	ml.name = "MobileControlsFireGateTest"
	ml.set_script(load("res://scripts/ui/mobile_controls.gd"))
	ml.add_to_group("mobile_controls")
	root.add_child(ml)
	return ml

func _spawn_vehicle(scene_path: String, json_path: String) -> Node:
	var v: Node = load(scene_path).instantiate()
	v.is_player_controlled = true
	v.is_server_controlled = false
	v.team = 1
	root.add_child(v)
	v.setup_from_data(_load_json(json_path))
	return v

func _ammo_total(v: Node) -> int:
	var t := 0
	for k in v.ammo_counts:
		t += v.ammo_counts[k]
	return t

func _initialize() -> void:
	var fake_scene := Node.new()
	fake_scene.name = "FakeMobileFireGateTest"
	root.add_child(fake_scene)
	current_scene = fake_scene
	# 地面（物理结算需要，飞机防下沉）
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5000.0, 1.0, 5000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)
	# SettingsManager：-s 主脚本编译期无法解析 autoload 名，改用节点动态访问
	if root.get_node_or_null("SettingsManager") == null:
		var sm := Node.new()
		sm.name = "SettingsManager"
		sm.set_script(load("res://scripts/core/settings_manager.gd"))
		root.add_child(sm)
	_mobile = _spawn_mobile()
	print("INFO: 场景就绪，开始移动端开火门控校验...")

func _physics_process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _frame > MAX_FRAMES:
		print("FAIL: 测试全局超时")
		_finish()
		return false
	match _phase:
		0:
			if _mobile.is_inside_tree() and _frame > 8:
				if not InputMap.has_action("fire"):
					_check(false, "前置条件：fire 动作已注册")
					_finish()
					return false
				_plane = _spawn_vehicle("res://scenes/airplane.tscn", "res://data/vehicles/plane_a10.json")
				_plane.global_position = Vector3(0, 60, 0)
				print("INFO: 固定翼已生成（玩家控制），进入开火门控校验...")
				_phase = 1
				_frame = 0
		1:
			# 等飞机完成 _ready/setup，记弹药基线
			if _plane.is_inside_tree() and _frame > 8:
				_ammo0 = _ammo_total(_plane)
				_check(_ammo0 > 0, "前置条件：固定翼有备弹 (%d)" % _ammo0)
				# 模拟触摸产生的 fire 动作（移动端点击屏幕任意位置 → 鼠标左键 → fire）
				Input.action_press("fire")
				_phase = 2
				_frame = 0
		2:
			if _frame >= 5:
				_check(_ammo_total(_plane) == _ammo0, "有移动端：fire 动作按下（触摸模拟）→ 不误开火 (%d→%d)" % [_ammo0, _ammo_total(_plane)])
				Input.action_release("fire")
				_ammo0 = _ammo_total(_plane)
				_mobile.fire_held = true
				_phase = 3
				_frame = 0
		3:
			if _frame >= 5:
				_check(_ammo_total(_plane) < _ammo0, "有移动端：开火按钮 fire_held → 按住连发消耗弹药 (%d→%d)" % [_ammo0, _ammo_total(_plane)])
				_mobile.fire_held = false
				# 移除移动端，模拟 PC：fire 动作应恢复直接开火
				root.remove_child(_mobile)
				_mobile.free()
				_mobile = null
				_phase = 4
				_frame = 0
		4:
			if _frame >= 5:
				# 开火后进入装填（can_fire=false），装填与门控无关，直接复位以验证 PC 链路
				_plane.can_fire = true
				_plane.is_reloading = false
				_plane.reload_timer = 0.0
				_ammo0 = _ammo_total(_plane)
				Input.action_press("fire")
				_phase = 5
				_frame = 0
		5:
			if _frame >= 5:
				_check(_ammo_total(_plane) < _ammo0, "无移动端：fire 动作按下 → 正常开火（PC 行为不变） (%d→%d)" % [_ammo0, _ammo_total(_plane)])
				Input.action_release("fire")
				_finish()
	return false

func _finish() -> void:
	_done = true
	if _failed == 0:
		print("总结: 全部通过")
		quit(0)
	else:
		print("总结: 失败 %d 项" % _failed)
		quit(1)