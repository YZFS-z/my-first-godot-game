extends "res://scripts/vehicles/vehicle.gd"
## 坦克载具 - 继承Vehicle基类，实现坦克特有的控制逻辑
## 包含：玩家输入处理、第三人称摄像机、火炮控制、炮镜瞄准

@export var camera_pitch: float = 0.0
@export var camera_distance: float = 18.0
@export var camera_height: float = 7.0
@export var aim_distance: float = 1.0  # 右键瞄准模式的摄像机距离
@export var aim_height: float = 1.5   # 右键瞄准模式的摄像机高度
@export var aim_side: float = 0.5     # 右键瞄准模式的摄像机右偏量（炮管右侧观察）
@export var mouse_sensitivity: float = 0.3
@export var scope_mouse_sensitivity: float = 0.05

var camera_3d: Camera3D = null
var camera_pivot: Node3D = null  # 摄像机支架（替代SpringArm3D，更稳定）
var scope_camera: Camera3D = null
var gun_scope: Control = null
var is_aim_mode: bool = false
var is_scope_mode: bool = false
var scope_config: Dictionary = {}
var default_fov: float = 70.0
var camera_yaw: float = 0.0      # 世界空间视角偏航（度）= view_offset_yaw + 车体偏航
var view_offset_yaw: float = 0.0  # 视角偏航相对车体（度），鼠标直接控制（即时响应）
var mouse_turret_delta: float = 0.0  # 炮镜模式下鼠标累积的炮塔旋转量
var mouse_gun_delta: float = 0.0 # 炮镜模式下鼠标累积的火炮俯仰量
var _saved_mesh_visibility: Dictionary = {}  # 开镜前网格可见状态快照
var manual_turret: bool = false  # 是否手动控制炮塔（Q/E按下时）
var is_public_local: bool = false  # 公网模式下的本地玩家
var _skill_selector: RefCounted = null  # 当前技能目标选择器
var _net_input_timer: float = 0.0
var _net_state_timer: float = 0.0
# 后坐力（炮管轴向缩回动画）：固定耳轴基准 + 单 tween（先 kill 旧的），
# 避免高频开火（如 12.7mm 机枪 9/s）时多个 tween 并行操作 gun_node.position.z
# 且把偏移中的值误当基准，导致炮管逐渐后移无法恢复。
var _recoil_tween: Tween = null
var _gun_rest_z: float = NAN  # 耳轴基准 Z（首次开火记录，固定不漂移）

func _ready() -> void:
	super._ready()
	_setup_camera()
	# 连接移动端控制按钮（如果已创建）
	_connect_mobile_controls()
	# 延迟一帧再试一次（防止时序问题）
	call_deferred("_connect_mobile_controls")

func _complete_repair() -> void:
	"""重写：维修完成后同步视角到炮塔方向，避免视角与炮塔不同步"""
	super._complete_repair()
	# 同步视角到炮塔当前朝向
	view_offset_yaw = turret_yaw
	camera_yaw = turret_yaw + rad_to_deg(rotation.y)
	camera_pitch = gun_pitch

func _connect_mobile_controls() -> void:
	"""连接移动端控制按钮信号（幂等：重复调用不会重复连接）"""
	if not is_player_controlled:
		return
	var mobile = _get_mobile_controls()
	if not mobile:
		return
	if not mobile.fire_pressed.is_connected(fire):
		mobile.fire_pressed.connect(fire)
	if not mobile.scope_toggled.is_connected(_toggle_scope):
		mobile.scope_toggled.connect(_toggle_scope)
	if not mobile.repair_pressed.is_connected(start_repair):
		mobile.repair_pressed.connect(start_repair)
	if not mobile.ammo_selected.is_connected(select_ammo):
		mobile.ammo_selected.connect(select_ammo)
	if not mobile.weapon_selected.is_connected(switch_weapon):
		mobile.weapon_selected.connect(switch_weapon)
	if not mobile.skill_artillery_pressed.is_connected(_on_mobile_artillery):
		mobile.skill_artillery_pressed.connect(_on_mobile_artillery)
	if not mobile.skill_smoke_pressed.is_connected(_on_mobile_smoke):
		mobile.skill_smoke_pressed.connect(_on_mobile_smoke)
	if not mobile.free_look_pressed.is_connected(_on_mobile_free_look_down):
		mobile.free_look_pressed.connect(_on_mobile_free_look_down)
	if not mobile.free_look_released.is_connected(_on_mobile_free_look_up):
		mobile.free_look_released.connect(_on_mobile_free_look_up)
	if mobile.has_signal("range_finder_pressed") and not mobile.range_finder_pressed.is_connected(_start_ranging):
		mobile.range_finder_pressed.connect(_start_ranging)
	# 设置武器槽数量（控制副武器按钮显示）
	if mobile.has_method("set_weapon_count"):
		mobile.set_weapon_count(get_weapon_count())
	print("[Tank] 移动端控制已连接")

func setup_from_data(data: Dictionary) -> void:
	super.setup_from_data(data)
	_setup_scope()

func _setup_camera() -> void:
	# 用Node3D做摄像机支架，top_level脱离物理体，避免抖动
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.top_level = true
	add_child(camera_pivot)

	camera_3d = Camera3D.new()
	camera_3d.name = "Camera3D"
	# 摄像机在支架+Z方向（坦克后方），看向-Z（坦克前方）
	camera_3d.position = Vector3(1.5, camera_height, camera_distance)
	camera_3d.fov = default_fov
	camera_3d.near = 0.05
	camera_pivot.add_child(camera_3d)

	if is_player_controlled:
		camera_3d.current = true

func _setup_scope() -> void:
	"""设置炮镜摄像机和分划板"""
	if scope_camera or gun_scope:
		return  # 已经初始化过

	# 从载具配置读取炮镜参数
	scope_config = vehicle_data.get("scope", {})
	if scope_config.is_empty():
		scope_config = {
			"style": "simple",
			"zoom_levels": [4.0, 8.0],
			"field_of_view": 45.0,
			"reticle_color": "#000000",
			"lens_color": [0.9, 0.9, 0.85, 0.05],
			"has_range_finder": false,
			"has_stadiametric": true
		}

	# 创建炮镜摄像机（挂在炮管上，从炮口方向看出去）
	scope_camera = Camera3D.new()
	scope_camera.name = "ScopeCamera"
	scope_camera.fov = scope_config.get("field_of_view", 40.0)
	# 近裁面缩小到 0.05，避免炮镜贴在炮管内壁时被裁掉
	scope_camera.near = 0.05
	if gun_node:
		gun_node.add_child(scope_camera)
		# 炮镜位置：沿炮管轴线（-Z），Z 值由 vehicle_initializer 从炮管 AABB 自动推算
		# 默认 -0.5（炮尾后方），导入模型后自动修正为炮尾端
		var cam_z: float = -0.5
		if has_meta("scope_camera_z"):
			cam_z = get_meta("scope_camera_z")
		scope_camera.position = Vector3(0, 0, cam_z)
		scope_camera.rotation = Vector3.ZERO
	else:
		add_child(scope_camera)

	# 创建炮镜UI覆盖层
	var scope_scene = load("res://scenes/gun_scope.tscn")
	if scope_scene:
		gun_scope = scope_scene.instantiate()
		gun_scope.apply_config(scope_config)
		gun_scope.scope_opened.connect(_on_scope_opened)
		gun_scope.scope_closed.connect(_on_scope_closed)
		gun_scope.zoom_changed.connect(_on_scope_zoom_changed)
		gun_scope.range_complete.connect(_on_range_complete)
		# 挂到HUD层或直接作为CanvasLayer
		var canvas = CanvasLayer.new()
		canvas.name = "ScopeCanvas"
		canvas.layer = 10
		canvas.add_child(gun_scope)
		add_child(canvas)

func _input(event: InputEvent) -> void:
	if not is_player_controlled or is_destroyed:
		return
	if GameManager.is_chat_open:
		return  # 聊天打开时忽略游戏输入
	if get_tree().get_first_node_in_group("target_selector"):
		return  # 目标选择器打开时忽略游戏输入

	# 自由视角（V键，可自定义；进入时自动退出炮镜）
	if event.is_action_pressed("free_look"):
		if is_scope_mode:
			_close_scope()
		set_free_look(true)
	elif event.is_action_released("free_look"):
		set_free_look(false)

	# 切换炮镜（可自定义按键）
	if event.is_action_pressed("scope"):
		_toggle_scope()
		return
	# 测距（可自定义按键，默认鼠标中键）
	if event.is_action_pressed("range_finder"):
		_start_ranging()
		return

	# 武器槽切换（可自定义按键，默认Z=主武器，X=副武器）
	if event.is_action_pressed("weapon_1"):
		switch_weapon(0)
		return
	if event.is_action_pressed("weapon_2") and get_weapon_count() >= 2:
		switch_weapon(1)
		return

	# 弹药切换/维修（两种模式下都可用，可自定义按键）
	if event.is_action_pressed("ammo_1"):
		select_ammo(0)
	if event.is_action_pressed("ammo_2"):
		select_ammo(1)
	if event.is_action_pressed("ammo_3"):
		select_ammo(2)
	if event.is_action_pressed("repair"):
		start_repair()

	# 技能按键（G=火炮打击，H=烟幕遮蔽）
	var is_artillery = event.is_action_pressed("skill_artillery") or (event is InputEventKey and event.pressed and event.keycode == KEY_G)
	var is_smoke = event.is_action_pressed("skill_smoke") or (event is InputEventKey and event.pressed and event.keycode == KEY_H)
	if is_artillery or is_smoke:
		# 如果已有选择器且打开中，处理重复按键（取消）
		if _skill_selector and _skill_selector.is_open and _skill_selector.handle_key(event):
			return
		if _skill_selector and _skill_selector.is_open:
			return  # 已有选择器，忽略新技能
		_skill_selector = null  # 清理已关闭的引用
		if is_artillery:
			print("[Tank] 火炮打击按键触发")
			_request_skill("artillery")
		else:
			print("[Tank] 烟幕遮蔽按键触发")
			_request_skill("smoke")
		return

	# 目标选择器打开时，忽略所有游戏输入（技能键已在上面处理）
	if _skill_selector and _skill_selector.is_open:
		return

	if is_scope_mode:
		# 炮镜模式：鼠标控制炮塔和火炮（受转速限制）
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			mouse_turret_delta -= event.relative.x * scope_mouse_sensitivity
			# 与飞机一致：鼠标上移(relative.y<0) → mouse_gun_delta增大 → 炮管上仰/准心上移
			mouse_gun_delta -= event.relative.y * scope_mouse_sensitivity
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _get_mobile_controls():
			pass  # 开火已移至 _process 每帧轮询按住状态（连续射击）
		# ESC键不在这里处理，传递到main.gd显示暂停菜单（开镜状态不退出开镜）
		return

# 鼠标直接控制视角（异步：视角即时响应，炮塔/火炮限速跟随）
# 自由视角只转相机观察，不影响炮塔
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if is_free_look_active():
			# 自由视角：只转动观察方向，不写入任何行为参数（炮塔/火炮保持不动）
			free_look_yaw -= event.relative.x * mouse_sensitivity
			# 与飞机一致：鼠标上移 → 视角上仰
			free_look_pitch = clamp(free_look_pitch - event.relative.y * mouse_sensitivity, -85.0, 85.0)
		else:
			# 鼠标直接控制视角偏航和俯仰（即时，不受炮塔转速限制）
			view_offset_yaw -= event.relative.x * mouse_sensitivity
			# 鼠标上移(relative.y<0) → camera_pitch增大 → 炮管上仰/准心上移
			camera_pitch = clamp(camera_pitch - event.relative.y * mouse_sensitivity, gun_elevation_min, gun_elevation_max)

	if event is InputEventMouseButton and not _get_mobile_controls():
		# 左键开火已移至 _process 每帧轮询按住状态（连续射击）
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_aim_mode = event.pressed

	# 普通模式ESC由main.gd处理（呼出暂停菜单）

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_controlled:
		return
	if GameManager.is_chat_open:
		return
	if _skill_selector and _skill_selector.is_open:
		return
	# 移动端由开火按钮处理，忽略触摸模拟的鼠标fire
	if _get_mobile_controls():
		return
	# 开火已移至 _process 每帧轮询按住状态（连续射击），此处不再处理 fire 动作

func _process(delta: float) -> void:
	if not is_player_controlled or is_destroyed:
		return
	if GameManager.is_chat_open:
		input_throttle = 0.0
		input_steering = 0.0
		input_turret = 0.0
		return

	# 读取键盘输入
	input_throttle = Input.get_axis("move_backward", "move_forward")
	input_steering = Input.get_axis("turn_left", "turn_right")

	# 移动端触摸输入（与键盘叠加）
	var mobile = _get_mobile_controls()
	if mobile:
		input_throttle = clamp(input_throttle + mobile.joystick_y, -1.0, 1.0)
		input_steering = clamp(input_steering + mobile.joystick_x, -1.0, 1.0)
		# 视角拖动（维修时锁定视角）
		if mobile.look_delta.length() > 0.01:
			if is_free_look_active():
				free_look_yaw -= mobile.look_delta.x * 0.3
				free_look_pitch = clamp(free_look_pitch - mobile.look_delta.y * 0.3, -85.0, 85.0)
			elif is_scope_mode:
				# 炮镜模式：手指直接控制炮塔/火炮（限速）
				mouse_turret_delta -= mobile.look_delta.x * 0.3
				mouse_gun_delta -= mobile.look_delta.y * 0.3
			else:
				# 第三人称：手指直接控制视角（即时），炮塔/火炮限速跟随
				view_offset_yaw -= mobile.look_delta.x * 0.3
				camera_pitch = clamp(camera_pitch - mobile.look_delta.y * 0.3, gun_elevation_min, gun_elevation_max)
			mobile.look_delta = Vector2.ZERO

	# 按住开火：每帧轮询（fire() 自带装填/冷却门控限速，按住连续射击）
	# 移动端由开火按钮维护 fire_held；桌面端鼠标左键（fire 动作）按住，炮镜/普通模式均可
	var fire_want: bool = false
	if mobile and mobile.fire_held:
		fire_want = true
	elif not mobile and Input.is_action_pressed("fire"):
		fire_want = true
	if fire_want:
		fire()

	# 炮塔/火炮控制：第三人称异步（视角即时，炮塔限速跟随）或炮镜同步
	if not is_repairing:
		var key_turret = Input.get_axis("turret_left", "turret_right")
		manual_turret = abs(key_turret) > 0.01

		if is_scope_mode:
			# === 炮镜模式：鼠标直接控制炮塔/火炮（限速，同步） ===
			if abs(mouse_turret_delta) > 0.001:
				var turret_eff = _get_module_effectiveness("turret_ring")
				var max_step = turret_turn_rate * turret_eff * delta
				var actual = clamp(mouse_turret_delta, -max_step, max_step)
				turret_yaw += actual
				mouse_turret_delta = 0.0

			if manual_turret:
				turret_yaw += key_turret * turret_turn_rate * delta

			if abs(mouse_gun_delta) > 0.001:
				var gun_eff = _get_module_effectiveness("gun")
				var max_gun_step = 20.0 * gun_eff * delta
				var actual_gun = clamp(mouse_gun_delta, -max_gun_step, max_gun_step)
				gun_pitch = clamp(gun_pitch + actual_gun, gun_elevation_min, gun_elevation_max)
				mouse_gun_delta = 0.0

			# 炮镜模式：视角同步炮塔/火炮（退出炮镜时无跳变）
			view_offset_yaw = turret_yaw
			camera_yaw = turret_yaw + rad_to_deg(rotation.y)
			camera_pitch = gun_pitch
		else:
			# === 第三人称模式：视角异步（鼠标即时控制视角，炮塔/火炮限速跟随） ===
			# Q/E 移动视角偏移（炮塔会跟随）
			if manual_turret:
				view_offset_yaw += key_turret * turret_turn_rate * delta

			# 炮塔追踪视角方向（限速）
			var turret_eff = _get_module_effectiveness("turret_ring")
			var turret_diff = wrapf(view_offset_yaw - turret_yaw, -180.0, 180.0)
			if abs(turret_diff) > 0.01:
				var max_step = turret_turn_rate * turret_eff * delta
				var actual = clamp(turret_diff, -max_step, max_step)
				turret_yaw += actual

			# 火炮追踪视角俯仰（限速）
			var gun_eff = _get_module_effectiveness("gun")
			var gun_diff = camera_pitch - gun_pitch
			if abs(gun_diff) > 0.01:
				var max_gun_step = 20.0 * gun_eff * delta
				var actual_gun = clamp(gun_diff, -max_gun_step, max_gun_step)
				gun_pitch = clamp(gun_pitch + actual_gun, gun_elevation_min, gun_elevation_max)

			# 摄像机跟随车体 + 视角偏移（独立于炮塔方向）
			if not is_free_look_active():
				camera_yaw = view_offset_yaw + rad_to_deg(rotation.y)

		input_turret = 0.0
		input_gun = 0.0
	else:
		# 维修时：视角可自由转动观察，炮塔不跟随
		input_turret = 0.0
		input_gun = 0.0
		camera_yaw = view_offset_yaw + rad_to_deg(rotation.y)

# 更新摄像机
	_update_camera(delta)

	# 自由视角退出后，相机偏移平滑衰减还原
	_process_free_look_restore(delta)

	# 鼠标捕获（与飞机一致：桌面端始终捕获，鼠标即炮塔指向）
	if not OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 公网模式：发送输入和状态到服务器
	if is_public_local and NetworkManager.game_connected_flag:
		_net_input_timer += delta
		if _net_input_timer >= 1.0 / 30.0:
			_net_input_timer = 0.0
			NetworkManager.game_send_input(input_throttle, input_steering, input_turret, input_gun, Input.is_action_pressed("fire"))
		_net_state_timer += delta
		if _net_state_timer >= 1.0 / 15.0:
			_net_state_timer = 0.0
			NetworkManager.game_send_state(global_position, global_rotation, turret_yaw, gun_pitch, get_health_percent(), velocity)

func _update_camera(delta: float) -> void:
	if is_scope_mode:
		return

	if not camera_pivot:
		return

	# 手动跟随坦克位置（top_level，避免物理/渲染不同步抖动）
	camera_pivot.global_position = global_position + Vector3(0, 3.5, 0)

# pivot只负责水平旋转（摄像机绕坦克水平轨道）
	camera_pivot.rotation.y = deg_to_rad(camera_yaw + free_look_yaw)
	camera_pivot.rotation.x = 0.0

	# 俯仰由摄像机自身旋转实现（位置不变，只改变视线方向）
	# camera_pitch正值=上仰，Godot 4中rotation.x正=上仰
	camera_3d.rotation.x = deg_to_rad(camera_pitch + free_look_pitch)

	# 右键瞄准：拉近+抬高
	if is_aim_mode:
		camera_3d.position.x = lerp(camera_3d.position.x, aim_side, 8.0 * delta)
		camera_3d.position.y = lerp(camera_3d.position.y, aim_height, 8.0 * delta)
		camera_3d.position.z = lerp(camera_3d.position.z, aim_distance, 8.0 * delta)
		camera_3d.fov = lerp(camera_3d.fov, 40.0, 8.0 * delta)
	else:
		camera_3d.position.x = lerp(camera_3d.position.x, 1.5, 8.0 * delta)
		camera_3d.position.y = lerp(camera_3d.position.y, camera_height, 8.0 * delta)
		camera_3d.position.z = lerp(camera_3d.position.z, camera_distance, 8.0 * delta)
		camera_3d.fov = lerp(camera_3d.fov, default_fov, 8.0 * delta)

func _get_mobile_controls():
	"""查找场景中的移动端控制节点"""
	return get_tree().get_first_node_in_group("mobile_controls")

func _toggle_scope() -> void:
	if is_scope_mode:
		_close_scope()
	else:
		_open_scope()

func _on_mobile_artillery() -> void:
	_request_skill("artillery")

func _on_mobile_smoke() -> void:
	_request_skill("smoke")

func _on_mobile_free_look_down() -> void:
	"""移动端：按住进入自由视角（与V键一致；炮镜模式优先退出）"""
	if is_scope_mode:
		_close_scope()
	set_free_look(true)

func _on_mobile_free_look_up() -> void:
	set_free_look(false)

func _request_skill(skill_id: String) -> void:
	"""请求使用技能，打开目标选择界面"""
	if not request_skill(skill_id):
		return
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if not hud:
		print("[Tank] 未找到HUD")
		confirm_skill(global_position)
		return
	_skill_selector = SkillTargetSelector.new(hud, self, skill_id)
	print("[Tank] 目标选择器已打开")

func _open_scope() -> void:
	is_scope_mode = true
	is_aim_mode = false
	# 进入炮镜时，摄像机俯仰角与炮管对齐（同向），避免视角跳变
	view_offset_yaw = turret_yaw
	camera_pitch = gun_pitch
	camera_yaw = turret_yaw + rad_to_deg(rotation.y)  # 转为世界角度
	if scope_camera:
		scope_camera.current = true
	if camera_3d:
		camera_3d.current = false
	if gun_scope:
		gun_scope.open()
	# 只隐藏准星和左上面板，保留聊天、方位角、底部弹药栏
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		var crosshair = hud.get_node_or_null("Crosshair")
		if crosshair:
			crosshair.visible = false
		var panel = hud.get_node_or_null("Panel")
		if panel:
			panel.visible = false
		# 确保聊天面板始终可见且置顶
		var chat = hud.get_node_or_null("ChatPanel")
		if chat:
			chat.visible = true
			chat.move_to_front()
	# 隐藏载具自身网格（避免遮挡炮镜视角）
	_set_vehicle_meshes_visible(false)
	print("[Tank] Scope opened: %s" % scope_config.get("style", "unknown"))

func _close_scope() -> void:
	is_scope_mode = false
	if camera_3d:
		camera_3d.current = true
	if scope_camera:
		scope_camera.current = false
	if gun_scope:
		gun_scope.close()
	# 恢复准星和左上面板
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		var crosshair = hud.get_node_or_null("Crosshair")
		if crosshair:
			crosshair.visible = true
		var panel = hud.get_node_or_null("Panel")
		if panel:
			panel.visible = true
	# 恢复载具自身网格
	_set_vehicle_meshes_visible(true)
	# 退出炮镜时同步视角到炮塔/火炮当前朝向，避免跳变
	view_offset_yaw = turret_yaw
	camera_pitch = gun_pitch
	camera_yaw = turret_yaw + rad_to_deg(rotation.y)
	print("[Tank] Scope closed")

func _set_vehicle_meshes_visible(visible: bool) -> void:
	"""隐藏/显示载具所有视觉网格（炮镜模式下避免遮挡）。
	开镜时：记录所有 GeometryInstance3D 当前可见状态，然后全部隐藏。
	关镜时：恢复到开镜前的状态（内置占位网格仍保持隐藏，导入网格恢复显示）。"""
	if visible:
		# 关镜：恢复快照中记录的状态
		for path in _saved_mesh_visibility:
			var node = get_node_or_null(path)
			if node and node is GeometryInstance3D:
				node.visible = _saved_mesh_visibility[path]
		_saved_mesh_visibility.clear()
	else:
		# 开镜：先快照当前状态，再全部隐藏
		_saved_mesh_visibility.clear()
		_snapshot_mesh_visibility(self)
		_set_node_and_geometry_children_visible(self, false)

func _set_node_and_geometry_children_visible(node: Node, visible: bool) -> void:
	"""递归隐藏节点及其所有子节点中的 GeometryInstance3D（网格、粒子等可视实例）"""
	if node is GeometryInstance3D:
		node.visible = visible
	for child in node.get_children():
		_set_node_and_geometry_children_visible(child, visible)

func _snapshot_mesh_visibility(node: Node) -> void:
	"""递归记录所有 GeometryInstance3D 的当前可见状态，用节点路径做 key"""
	if node is GeometryInstance3D:
		var path = str(node.get_path())
		_saved_mesh_visibility[path] = node.visible
	for child in node.get_children():
		_snapshot_mesh_visibility(child)

func _on_scope_opened() -> void:
	_update_scope_ballistics()

func _on_scope_closed() -> void:
	pass

func _on_scope_zoom_changed(level: int, fov: float) -> void:
	if scope_camera:
		scope_camera.fov = fov

func _update_scope_ballistics() -> void:
	"""根据当前弹药的初速/阻力/质量更新炮镜距离分划（配合炮弹下坠）"""
	if not gun_scope:
		return
	var v0 := 800.0
	var cd := 0.1
	var m := 10.0
	if current_ammo_index >= 0 and current_ammo_index < ammo_types.size():
		var ammo = ammo_types[current_ammo_index]
		v0 = ammo.get("muzzle_velocity", 800.0)
		cd = ammo.get("drag_coefficient", 0.1)
		m = ammo.get("mass", 10.0)
	gun_scope.set_ballistics(v0, 9.81, cd, m)

func select_ammo(index: int) -> void:
	"""切换弹药后更新炮镜弹道分划"""
	super.select_ammo(index)
	_update_scope_ballistics()

func _start_ranging() -> void:
	"""开始测距（需载具有测距仪；未开镜时自动开镜）"""
	if not gun_scope:
		return
	if not scope_config.get("has_range_finder", false):
		return
	if gun_scope.is_ranging:
		return
	# 未开镜时自动开镜
	if not is_scope_mode:
		_open_scope()
	# 测距时间：配置优先，否则按年代（现代激光测距0.5s，二战光学2.5s）
	var t: float = scope_config.get("range_finder_time", -1.0)
	if t < 0:
		var era = vehicle_data.get("era", "ww2")
		t = 0.5 if era == "modern" else 2.5
	gun_scope.start_ranging(t)

func _on_range_complete() -> void:
	"""测距计时完成，执行射线检测并返回结果（沿炮镜视线，非炮口方向）"""
	if not gun_scope:
		return
	var from_pos: Vector3
	var dir: Vector3
	# 开镜时沿炮镜摄像机视线测距（与玩家看到的方向一致）
	if scope_camera and is_scope_mode:
		from_pos = scope_camera.global_position
		dir = -scope_camera.global_transform.basis.z.normalized()
	elif muzzle_node:
		from_pos = muzzle_node.global_position
		dir = -muzzle_node.global_transform.basis.z.normalized()
	elif gun_node:
		from_pos = gun_node.global_position
		dir = -gun_node.global_transform.basis.z.normalized()
	else:
		gun_scope.set_range_result(-1)
		return
	var query = PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir * 5000.0)
	query.collision_mask = 1 | 2  # world + vehicle（module为Area3D，射线不检测）
	query.exclude = [get_rid()]
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		var dist := from_pos.distance_to(result.position)
		gun_scope.set_range_result(dist)
		# 火控：测距后自动抬高炮管补偿下坠（仅开镜时，需设置开启）
		if is_scope_mode and dist > 0 and SettingsManager.is_auto_aim_elevation():
			var aim_angle: float = gun_scope.get_aim_angle_deg(dist)
			gun_pitch = clamp(gun_pitch + aim_angle, gun_elevation_min, gun_elevation_max)
			camera_pitch = gun_pitch  # 同步视角避免跳变
	else:
		gun_scope.set_range_result(-1)

func _apply_gun_recoil() -> void:
	"""后坐力：沿炮管轴向炮塔内缩回，再恢复到耳轴基准位置。
	- 基准 _gun_rest_z 首次开火时记录并固定，恢复永远回到它（不随偏移累积）；
	- 每次开火先 kill 旧 tween，保证同一时刻只有一个 tween 操作 position.z；
	- 机枪（mg_*）后坐更小（0.05m），主炮 0.3m。"""
	if not gun_node:
		return
	if is_nan(_gun_rest_z):
		_gun_rest_z = gun_node.position.z
	if _recoil_tween:
		_recoil_tween.kill()
	var recoil := 0.3
	if get_current_weapon_id().begins_with("mg_"):
		recoil = 0.05
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(gun_node, "position:z", _gun_rest_z + recoil, 0.05)
	_recoil_tween.tween_property(gun_node, "position:z", _gun_rest_z, 0.2)

func fire() -> void:
	if is_destroyed:
		return
	super.fire()
	# 坦克特有：后坐力（沿炮管轴向炮塔内缩回，再恢复到 pivot 原位置）
	# 注意：不能硬编码还原到 position.z=0——导入模型的 gun_pivot.z 非零，
	# 否则会破坏炮管耳轴位置，导致炮管缩进炮塔。
	_apply_gun_recoil()
	# 公网模式：广播开火事件
	if is_public_local and NetworkManager.game_connected_flag:
		NetworkManager.game_send_fire({
			"muzzle_pos": [muzzle_node.global_position.x, muzzle_node.global_position.y, muzzle_node.global_position.z],
			"ammo_type": get_current_ammo_name(),
		})

func fire_remote(fire_data: Dictionary = {}) -> void:
	"""远程玩家开火：只播放特效，不消耗弹药"""
	if is_destroyed or not muzzle_node:
		return
	var muzzle_pos = muzzle_node.global_position
	var muzzle_rot = muzzle_node.global_rotation
	EffectManager.play_muzzle_flash(muzzle_pos, muzzle_rot, 1.0)
	# 播放开火音效
	EffectManager.play_sound_3d(EffectManager.SOUND_FIRE, muzzle_pos, -5.0)
	# 后坐力（保存 pivot 原值，恢复时回到 pivot 而非 0）
	_apply_gun_recoil()

func stop_turret() -> void:
	"""停止炮塔旋转（击毁时调用）"""
	input_turret = 0.0
	input_gun = 0.0
