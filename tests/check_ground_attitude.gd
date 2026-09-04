extends SceneTree
## 校验：直升机未离地时禁止前倾（防桨触地），离地后恢复正常低头
## 地面：StaticBody3D + BoxShape3D 顶面 y=0；直升机碰撞盒底部贴地（机体 y≈0）

var _heli: Node3D = null
var _frame_count := 0
var _max_frames := 90
var _failed := 0
var _done := false
var _phase := 0  # 0=地面约束验证, 1=离地恢复验证

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _heli_pitch_deg() -> float:
	var fwd: Vector3 = -_heli.global_transform.basis.z
	return rad_to_deg(asin(clamp(fwd.y, -1.0, 1.0)))

func _initialize() -> void:
	# 地面
	var ground := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	ground_col.shape = box
	ground_col.position = Vector3(0, -0.5, 0)
	ground.add_child(ground_col)
	ground.position = Vector3(0, 0, 0)
	root.add_child(ground)

	var heli_scene: PackedScene = load("res://scenes/helicopter.tscn")
	var data: Dictionary = {
		"id": "heli_ah64",
		"model": {"scene_path": "res://scenes/helicopter_model.tscn", "scale": 1.0},
		"physics": {},
		"modules": [],
		"weapons": [],
		"skills": [],
	}
	_heli = heli_scene.instantiate()
	_heli.is_player_controlled = true
	# 升力调到极小，保证测试阶段不会真的飞离地面
	_heli.max_lift_force = 300.0
	# 顺序与 game_manager.spawn_vehicle 一致：先 setup 再入树
	# （main.gd 玩家流程 add_child 在前，但 _ready 里 target_pitch=rotation.x 属正常初始化）
	_heli.global_position = Vector3(0, 0.2, 0)
	_heli.setup_from_data(data)
	root.add_child(_heli)
	print("INFO: 阶段0 - 地面约束验证（物理帧1注入 collective=0.5, target_pitch=-85°）")
	print("INFO: 等待 %d 个真实物理帧..." % _max_frames)

func _physics_process(delta: float) -> bool:
	if _done:
		return false
	_frame_count += 1
	if _phase == 0:
		# 帧1 注入玩家操作：滚轮加总距 + 鼠标大幅下压准星（模拟出生即低头）
		if _frame_count == 1:
			_heli.collective = 0.5
			_heli.target_pitch = deg_to_rad(-85.0)
			print("INFO: 注入玩家操作 target_pitch=%.1f° collective=%.2f" % [rad_to_deg(_heli.target_pitch), _heli.collective])
		if _frame_count <= 3 or _frame_count % 30 == 0:
			print("DBG phase0 frame=%d y=%.2f on_floor=%s pitch=%.2f tp=%.1f" % [_frame_count, _heli.global_position.y, _heli.is_on_floor(), _heli_pitch_deg(), rad_to_deg(_heli.target_pitch)])
	if _phase == 0 and _frame_count >= _max_frames:
		var pitch: float = _heli_pitch_deg()
		_check(abs(pitch) < 5.0, "未离地时机体保持水平 (俯仰角=%.2f°)" % pitch)
		var on_floor: bool = _heli.is_on_floor()
		var y: float = _heli.global_position.y
		_check(on_floor, "测试期间确实仍在地面 (y=%.2f)" % y)
		# 滚转也应保持水平（bank 被强制清零）——通过机背向上分量验证
		var up_world: Vector3 = _heli.global_transform.basis.y
		_check(up_world.y > 0.95, "未离地时机背竖直 (up.y=%.3f)" % up_world.y)
		# === 阶段1：手动抬到空中，验证离地后恢复正常低头 ===
		_heli.global_position.y = 8.0
		_heli.max_lift_force = 35000.0
		_heli.collective = 0.5
		_heli.target_pitch = deg_to_rad(-85.0)  # 玩家保持低头指令
		_frame_count = 0
		_phase = 1
		print("INFO: 阶段1 - 离地恢复验证（y=8, target_pitch 仍为 -85°）")
		return false
	if _phase == 1 and _frame_count >= 45:
		_done = true
		var pitch: float = _heli_pitch_deg()
		_check(pitch < -20.0, "离地后机头能正常下压 (俯仰角=%.2f°)" % pitch)
		_heli.queue_free()
		if _failed == 0:
			print("RESULT: failed=0")
			quit(0)
		else:
			print("RESULT: failed=%d" % _failed)
			quit(1)
	elif _phase == 1:
		# 调试：输出关键帧状态
		if _frame_count <= 5 or _frame_count % 15 == 0:
			print("DBG phase1 frame=%d y=%.2f on_floor=%s pitch=%.2f vel_y=%.2f tp=%.1f basis=%s" % [_frame_count, _heli.global_position.y, _heli.is_on_floor(), _heli_pitch_deg(), _heli.velocity.y, rad_to_deg(_heli.target_pitch), _heli.global_transform.basis.get_euler()])
	return false