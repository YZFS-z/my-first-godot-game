extends CanvasLayer
## HUD - 战斗界面
## 显示：速度、血量、模块状态、弹药、小地图等

@onready var speed_label: Label = $Panel/SpeedLabel
@onready var health_bar: ProgressBar = $Panel/HealthBar
@onready var vehicle_name_label: Label = $Panel/VehicleNameLabel
@onready var module_container: VBoxContainer = $Panel/ModuleContainer
@onready var crosshair: Control = $Crosshair
@onready var crosshair_v: ColorRect = $Crosshair/CrosshairV
@onready var crosshair_h: ColorRect = $Crosshair/CrosshairH
@onready var compass_label: Label = $Compass/CompassLabel
@onready var network_label: Label = $NetworkLabel
@onready var hit_message: Label = $HitMessage
@onready var kill_message: Label = $KillMessage
@onready var ammo_slot1: Panel = $BottomBar/AmmoSlot1
@onready var ammo_slot2: Panel = $BottomBar/AmmoSlot2
@onready var ammo_slot3: Panel = $BottomBar/AmmoSlot3
@onready var bottom_reload_bar: ProgressBar = $BottomBar/ReloadBar
@onready var reload_label: Label = $BottomBar/ReloadLabel
@onready var repair_status: Label = $BottomBar/RepairStatus
@onready var chat_panel: Panel = $ChatPanel
@onready var chat_container: VBoxContainer = $ChatPanel/MessageContainer
@onready var chat_input: LineEdit = $ChatPanel/ChatInput

var player_vehicle: Node = null
var module_labels: Dictionary = {}
var hit_fade_timer: float = 0.0
var kill_fade_timer: float = 0.0
var chat_messages: Array = []  # {label, timer}
var is_chat_open: bool = false

# 导弹锁定HUD
var lock_hud: Control = null
var lock_status_label: Label = null
var lock_distance_label: Label = null
var lock_target_label: Label = null
var lock_box: ColorRect = null
var lock_range_circle: Control = null
var _lock_hud_created: bool = false

# 自由视角HUD提示
var free_look_label: Label = null
var _free_look_hint_created: bool = false

# 坦克异步视角圆圈（视角方向标记）
var view_marker: Control = null
var _view_marker_created: bool = false

# 悬停HUD提示
var hover_label: Label = null
var _hover_hint_created: bool = false

func _ready() -> void:
	GameManager.player_vehicle_spawned.connect(_on_player_vehicle_spawned)
	GameManager.hit_message.connect(_on_hit_message)
	GameManager.target_destroyed.connect(_on_target_destroyed)
	GameManager.kill_feed.connect(_on_kill_feed)
	GameManager.chat_message.connect(_on_chat_message)
	NetworkManager.lan_kill_feed.connect(_on_kill_feed)  # 局域网击毁播报
	if network_label:
		network_label.text = "Mode: %s" % NetworkManager.get_mode_string()
	chat_input.text_submitted.connect(_on_chat_submitted)
	# 欢迎消息
	_add_chat_message("系统", "战斗开始！击毁所有敌方载具获胜。", Color(0.8, 0.8, 1.0))
	_apply_crosshair_settings()
	_create_lock_hud()
	_create_view_marker()

func _process(delta: float) -> void:
	# 命中提示淡出
	if hit_fade_timer > 0:
		hit_fade_timer -= delta
		if hit_fade_timer <= 0:
			hit_message.modulate.a = 0.0
		else:
			hit_message.modulate.a = clamp(hit_fade_timer / 1.5, 0.0, 1.0)

	# 击杀提示淡出
	if kill_fade_timer > 0:
		kill_fade_timer -= delta
		if kill_fade_timer <= 0:
			kill_message.modulate.a = 0.0
		else:
			kill_message.modulate.a = clamp(kill_fade_timer / 2.5, 0.0, 1.0)

	# 聊天消息淡出
	for i in range(chat_messages.size() - 1, -1, -1):
		var msg = chat_messages[i]
		msg.timer -= delta
		if msg.timer <= 0:
			# 淡出
			msg.label.modulate.a = max(0, msg.label.modulate.a - delta * 2)
			if msg.label.modulate.a <= 0:
				msg.label.queue_free()
				chat_messages.remove_at(i)
		elif msg.timer < 3.0:
			# 最后3秒开始淡出
			msg.label.modulate.a = msg.timer / 3.0

	if not player_vehicle:
		return

	# 更新导弹锁定HUD
	_update_lock_hud()

	# 更新速度、高度、飞行状态
	var speed_kmh = abs(player_vehicle.current_speed) * 3.6
	var altitude_m = player_vehicle.global_position.y
	var vtype = player_vehicle.vehicle_data.get("type", "tank")
	if vtype == "airplane":
		var throttle_pct = int(player_vehicle.throttle * 100)
		var gear_txt = "放下" if player_vehicle.gear_deployed else "收起"
		speed_label.text = "速度: %d km/h\n高度: %d m\n油门: %d%%\n起落架: %s" % [int(speed_kmh), int(altitude_m), throttle_pct, gear_txt]
	elif vtype == "helicopter":
		var collective_pct = int(player_vehicle.collective * 100)
		var gear_txt2 = "放下" if player_vehicle.gear_deployed else "收起"
		speed_label.text = "速度: %d km/h\n高度: %d m\n总距: %d%%\n起落架: %s" % [int(speed_kmh), int(altitude_m), collective_pct, gear_txt2]
	else:
		speed_label.text = "速度: %d km/h" % int(speed_kmh)

	# 更新血量
	var health = player_vehicle.get_health_percent() * 100
	health_bar.value = health

	# 更新模块状态
	_update_module_status()

	# 网络状态
	var debug_str = " | DEBUG" if GameManager.debug_mode else ""
	network_label.text = "Mode: %s | Tick: %d%s" % [NetworkManager.get_mode_string(), NetworkManager.current_tick, debug_str]
	if GameManager.debug_mode:
		network_label.modulate = Color(1, 0.5, 1, 1)
	else:
		network_label.modulate = Color(1, 1, 1, 1)

	# 方位角（炮塔朝向）
	_update_compass()

	# 动态准星（指向炮口方向实际弹着点）
	_update_dynamic_crosshair()

	# 更新底部弹药栏
	_update_ammo_bar()

func _on_player_vehicle_spawned(vehicle: Node) -> void:
	player_vehicle = vehicle
	vehicle_name_label.text = vehicle.vehicle_data.get("name", "Unknown")
	_setup_module_display()
	_layout_left_panel()

func _layout_left_panel() -> void:
	"""按载具类型重排左上信息面板，避免速度文本压住血条/模块列表。
	坦克速度仅 1 行，保持 tscn 默认布局；飞机/直升机为 4 行（速度/高度/油门或总距/起落架），
	需把 SpeedLabel 加高并让 HealthBar、ModuleContainer 顺延。"""
	if not player_vehicle:
		return
	var vtype = player_vehicle.vehicle_data.get("type", "tank")
	if vtype != "airplane" and vtype != "helicopter":
		return
	# 4 行 × 行高 20 + 底部留白
	var label_h := 4 * 20 + 6
	speed_label.offset_top = 30
	speed_label.offset_bottom = 30 + label_h
	health_bar.offset_top = speed_label.offset_bottom + 4
	health_bar.offset_bottom = health_bar.offset_top + 20
	# HealthBar 主题最小高度可能撑高实际渲染区域，按实际最小尺寸错开，保证不压住模块列表
	var health_h: float = max(health_bar.get_combined_minimum_size().y, 20.0)
	module_container.offset_top = health_bar.offset_top + health_h + 4
	module_container.offset_bottom = 410

func _setup_module_display() -> void:
	# 清除旧的
	for child in module_container.get_children():
		child.queue_free()
	module_labels.clear()

	if not player_vehicle or not player_vehicle.damage_system:
		return

	for mod_name in player_vehicle.damage_system.modules.keys():
		var label = Label.new()
		label.name = "Module_%s" % mod_name
		module_container.add_child(label)
		module_labels[mod_name] = label

func _update_module_status() -> void:
	if not player_vehicle or not player_vehicle.damage_system:
		return

	for mod_name in module_labels.keys():
		var mod = player_vehicle.damage_system.modules[mod_name]
		var state_text = ""
		var color = Color.GREEN
		match mod.state:
			0: state_text = "正常"
			1: state_text = "受损"; color = Color.YELLOW
			2: state_text = "重伤"; color = Color.ORANGE
			3: state_text = "损毁"; color = Color.RED
		var display_name = mod.display_name if "display_name" in mod else mod.module_name
		if mod.is_on_fire:
			state_text = "起火!"
			color = Color.RED
		module_labels[mod_name].text = "%s: %s (%.0f%%)" % [display_name, state_text, mod.current_health / mod.max_health * 100]
		module_labels[mod_name].add_theme_color_override("font_color", color)

func _on_hit_message(message: String, color: Color) -> void:
	if not hit_message:
		return
	hit_message.text = message
	hit_message.modulate = Color(color.r, color.g, color.b, 1.0)
	hit_fade_timer = 1.5

func _input(event: InputEvent) -> void:
	# 聊天输入
	if event is InputEventKey and event.pressed:
		if not is_chat_open and (event.keycode == KEY_ENTER or event.keycode == KEY_T):
			_open_chat()
			get_viewport().set_input_as_handled()
		elif is_chat_open and event.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()

func _open_chat() -> void:
	is_chat_open = true
	GameManager.is_chat_open = true
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_chat() -> void:
	is_chat_open = false
	GameManager.is_chat_open = false
	chat_input.visible = false
	chat_input.text = ""
	if player_vehicle and player_vehicle.is_player_controlled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_chat_submitted(text: String) -> void:
	var trimmed = text.strip_edges()
	# 调试模式作弊码
	if trimmed.to_lower() == "asd":
		GameManager.debug_mode = not GameManager.debug_mode
		var status = "已开启" if GameManager.debug_mode else "已关闭"
		_add_chat_message("系统", "调试模式%s（显示所有命中信息）" % status, Color(1.0, 0.5, 1.0))
		_close_chat()
		return
	if trimmed == "":
		_close_chat()
		return
	var sender = player_vehicle.nickname if player_vehicle else "玩家"
	var team = player_vehicle.team if player_vehicle else 1
	# 公网模式：发送到服务器，同时本地显示
	if GameManager.network_type == 1 and NetworkManager.game_connected_flag:
		NetworkManager.game_send_chat(trimmed)
	GameManager.chat_message.emit(sender, trimmed, team)
	_close_chat()

func _on_chat_message(sender: String, message: String, team: int) -> void:
	var color = Color.WHITE
	if team == 1:
		color = Color(0.4, 0.8, 1.0)  # 友方蓝色
	elif team == 2:
		color = Color(1.0, 0.4, 0.4)  # 敌方红色
	_add_chat_message(sender, message, color)

func _on_kill_feed(killer_name: String, victim_name: String, victim_team: int, killer_team: int) -> void:
	var killer_col = Color(0.4, 0.8, 1.0) if killer_team == 1 else Color(1.0, 0.4, 0.4)
	var victim_col = Color(0.4, 0.8, 1.0) if victim_team == 1 else Color(1.0, 0.4, 0.4)
	# 用富文本格式显示击杀播报
	var msg = "%s 击毁了 %s" % [killer_name, victim_name]
	_add_chat_message("击杀", msg, Color(1.0, 0.85, 0.3), true)

func _add_chat_message(sender: String, message: String, color: Color, is_system: bool = false) -> void:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(360, 0)
	if is_system:
		label.text = "[%s] %s" % [sender, message]
	else:
		label.text = "%s: %s" % [sender, message]
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	label.modulate.a = 0.0
	chat_container.add_child(label)
	chat_messages.append({"label": label, "timer": 12.0})  # 12秒后淡出
	# 最多保留8条消息
	while chat_container.get_child_count() > 8:
		var old = chat_container.get_child(0)
		chat_messages.pop_front()
		old.queue_free()
	# 滚动到底部（如果有滚动容器的话）
	# 淡入
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)

func _on_target_destroyed(vehicle_name: String) -> void:
	if not kill_message:
		return
	kill_message.text = "已摧毁: %s" % vehicle_name
	kill_message.modulate = Color(1.0, 0.3, 0.3, 1.0)
	kill_fade_timer = 2.5

func _update_compass() -> void:
	if not compass_label:
		return
	if not player_vehicle:
		compass_label.text = "N 000°"
		return
	# 炮塔世界朝向 = 车体朝向 + 炮塔相对角度
	var world_yaw = player_vehicle.rotation.y + deg_to_rad(player_vehicle.turret_yaw)
	var degrees = rad_to_deg(world_yaw)
	# 归一化到 0-360
	degrees = fmod(degrees, 360.0)
	if degrees < 0:
		degrees += 360.0
	# 0°=北(N), 90°=东(E), 180°=南(S), 270°=西(W)
	var directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx = int(round(degrees / 45.0)) % 8
	var dir_name = directions[idx]
	compass_label.text = "%s %03d°" % [dir_name, int(degrees)]

func _apply_crosshair_settings() -> void:
	"""应用自定义准心颜色和大小"""
	var color = SettingsManager.get_crosshair_color()
	if crosshair_v:
		crosshair_v.color = color
	if crosshair_h:
		crosshair_h.color = color
	# 整体缩放（以中心为枢轴）
	var size_scale = SettingsManager.get_crosshair_size()
	crosshair.pivot_offset = Vector2(10, 10)
	crosshair.scale = Vector2(size_scale, size_scale)

func _update_dynamic_crosshair() -> void:
	"""准星定位逻辑：
	- 飞机/直升机：准星固定在屏幕中心（视角=武器指向，同步）
	- 坦克炮镜模式：隐藏HUD准星（gun_scope分划板在屏幕中心代表炮管方向）
	- 坦克第三人称异步：十字准心跟踪炮管射线检测的实际弹着点，
	  圆圈标记在屏幕中心代表视角方向（两者偏离量=炮塔追赶差值）
	"""
	if not player_vehicle:
		return
	var center = get_viewport().get_visible_rect().size * 0.5
	var vtype = player_vehicle.vehicle_data.get("type", "tank")
	var is_tank = (vtype == "tank" or vtype == "")
	# is_scope_mode 是 tank.gd 的属性（var），不是方法；用 get() 检测避免 has_method 误判
	# get() 不存在该属性时返回 null， == true 确保 false/null 都为 false
	var is_scope = player_vehicle.get("is_scope_mode") == true

	if is_tank and is_scope:
		# 坦克炮镜模式：隐藏HUD准星和圆圈
		# gun_scope 分划板已在屏幕中心代表炮管方向（scope_camera 零偏移挂在 gun_node 上）
		# 不需要 HUD 十字准心重复显示，避免投影偏差
		crosshair.visible = false
		_update_view_marker(center, false)
	elif is_tank and player_vehicle.is_player_controlled:
		# 坦克第三人称异步：十字跟踪炮管实际弹着点
		var cam = get_viewport().get_camera_3d()
		if cam and player_vehicle.muzzle_node:
			var gun_dir = -player_vehicle.muzzle_node.global_transform.basis.z
			var gun_origin = player_vehicle.muzzle_node.global_position
			# 射线检测炮管方向上的实际命中点（消除第三人称相机视差）
			var aim_point = _raycast_gun_hit_point(gun_origin, gun_dir)
			if not cam.is_position_behind(aim_point):
				var screen_pos = cam.unproject_position(aim_point)
				# 十字准心定位到实际弹着点投影
				crosshair.offset_left = screen_pos.x - 10
				crosshair.offset_top = screen_pos.y - 10
				crosshair.offset_right = screen_pos.x + 10
				crosshair.offset_bottom = screen_pos.y + 10
				crosshair.visible = true
			else:
				crosshair.visible = false
		else:
			crosshair.visible = false
		_update_view_marker(center, true)
	else:
		# 飞机/直升机：准星在屏幕中心
		crosshair.offset_left = center.x - 10
		crosshair.offset_top = center.y - 10
		crosshair.offset_right = center.x + 10
		crosshair.offset_bottom = center.y + 10
		crosshair.visible = true
		_update_view_marker(center, false)

func _raycast_gun_hit_point(origin: Vector3, dir: Vector3) -> Vector3:
	"""射线检测炮管方向上的实际命中点，消除第三人称相机视差。
	返回命中点世界坐标；未命中任何物体时返回远点（500m）。
	"""
	var world = get_viewport().get_world_3d()
	if not world:
		return origin + dir * 500.0
	var space_state = world.direct_space_state
	var to = origin + dir * 2000.0
	var query = PhysicsRayQueryParameters3D.create(origin, to)
	# collision_mask: 1=world/terrain, 2=vehicles（可瞄准敌方载具）
	query.collision_mask = 3
	# 排除自身载具
	var exclude_rids: Array[RID] = []
	if player_vehicle:
		exclude_rids.append(player_vehicle.get_rid())
	# 排除空气边界碰撞体（避免误命中不可见碰撞体）
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node:
		var tb = main_node.get_node_or_null("TerrainBuilder")
		if tb and tb.has_method("get_air_boundary_rids"):
			exclude_rids.append_array(tb.get_air_boundary_rids())
	query.exclude = exclude_rids
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		# 未命中（指向天空）：用远点投影，保持准心可见
		return origin + dir * 500.0
	return result["position"]

func _create_view_marker() -> void:
	"""创建坦克异步视角圆圈标记（视角方向指示器）"""
	if _view_marker_created:
		return
	_view_marker_created = true
	view_marker = Control.new()
	view_marker.name = "ViewMarker"
	view_marker.size = Vector2(30, 30)
	view_marker.visible = false
	view_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_marker.draw.connect(func():
		var c = view_marker.size * 0.5
		var r = view_marker.size.x * 0.5
		# 圆形边框
		var pts = PackedVector2Array()
		for i in range(65):
			var ang = TAU * i / 64.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		view_marker.draw_polyline(pts, Color(1, 1, 1, 0.6), 1.5)
		# 中心小点
		view_marker.draw_circle(c, 2.0, Color(1, 1, 1, 0.5))
	)
	add_child(view_marker)

func _update_view_marker(center: Vector2, visible: bool) -> void:
	"""更新视角圆圈标记位置（屏幕中心）"""
	if not view_marker:
		return
	view_marker.visible = visible
	if visible:
		view_marker.position = center - view_marker.size * 0.5
		view_marker.queue_redraw()

func _update_ammo_bar() -> void:
	if not player_vehicle:
		return
	var slots = [ammo_slot1, ammo_slot2, ammo_slot3]
	for i in range(3):
		var slot = slots[i]
		if not slot:
			continue
		if i < player_vehicle.ammo_types.size():
			slot.visible = true
			var ammo = player_vehicle.ammo_types[i]
			var name_label = slot.get_node_or_null("NameLabel")
			var count_label = slot.get_node_or_null("CountLabel")
			if name_label:
				name_label.text = ammo.get("name", "?")
			var count = player_vehicle.ammo_counts.get(ammo.get("name", "?"), 0)
			if count_label:
				count_label.text = "x%d" % count
			# 高亮当前选中
			if i == player_vehicle.current_ammo_index:
				slot.modulate = Color(1.2, 1.2, 0.8, 1.0)
			else:
				slot.modulate = Color(1, 1, 1, 1.0)
			# 无弹药变灰
			if count <= 0:
				slot.modulate = Color(0.5, 0.5, 0.5, 0.6)
		else:
			slot.visible = false

	# 武器槽指示（多武器时显示）
	var weapon_prefix = ""
	if player_vehicle.has_method("get_weapon_count") and player_vehicle.get_weapon_count() > 1:
		weapon_prefix = "[武器%d/%d] " % [player_vehicle.current_weapon_index + 1, player_vehicle.get_weapon_count()]

	# 装填状态
	if player_vehicle.is_reloading:
		if bottom_reload_bar:
			bottom_reload_bar.value = player_vehicle.get_reload_percent()
		if reload_label:
			reload_label.text = "%s装填中 %.1fs" % [weapon_prefix, player_vehicle.get_reload_remaining_time()]
		if bottom_reload_bar:
			bottom_reload_bar.modulate = Color(1, 0.8, 0.3, 1)
	else:
		if bottom_reload_bar:
			bottom_reload_bar.value = 1.0
		if reload_label:
			reload_label.text = "%s就绪" % weapon_prefix
		if bottom_reload_bar:
			bottom_reload_bar.modulate = Color(0.3, 1, 0.3, 1)

	# 维修状态
	if not repair_status:
		return
	if player_vehicle.is_repairing:
		repair_status.text = "维修中: %s (%d%%)" % [player_vehicle.repair_target, int(player_vehicle.get_repair_percent() * 100)]
		repair_status.modulate = Color(0.5, 0.8, 1, 1)
	elif player_vehicle.repair_cooldown > 0:
		repair_status.text = "维修冷却: %.1fs" % player_vehicle.repair_cooldown
		repair_status.modulate = Color(0.6, 0.6, 0.6, 1)
	elif player_vehicle.get_damaged_modules_count() > 0:
		repair_status.text = "按R维修 (%d个模块受损)" % player_vehicle.get_damaged_modules_count()
		repair_status.modulate = Color(0.5, 0.8, 1, 0.8)
	else:
		repair_status.text = ""

# === 自由视角HUD提示 ===
func set_free_look_active(active: bool) -> void:
	"""显示/隐藏自由视角提示（由载具基类调用）"""
	if not _free_look_hint_created:
		_free_look_hint_created = true
		free_look_label = Label.new()
		free_look_label.name = "FreeLookLabel"
		free_look_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		free_look_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		free_look_label.position = Vector2(0, 200)
		free_look_label.size = Vector2(300, 36)
		free_look_label.add_theme_font_size_override("font_size", 20)
		free_look_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4, 1))
		free_look_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		free_look_label.add_theme_constant_override("outline_size", 5)
		free_look_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 显示当前绑定的按键名（可在设置中自定义）
		var key_name = OS.get_keycode_string(SettingsManager.get_action_keycode("free_look"))
		free_look_label.text = "自由视角（按住 %s）" % key_name
		add_child(free_look_label)
	free_look_label.visible = active

# === 高度悬停HUD提示 ===
func set_hover_active(active: bool) -> void:
	"""显示/隐藏高度悬停提示（由直升机脚本调用，切换式：按一下开启，再按退出）"""
	if not _hover_hint_created:
		_hover_hint_created = true
		hover_label = Label.new()
		hover_label.name = "HoverLabel"
		hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hover_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		hover_label.position = Vector2(0, 390)
		hover_label.size = Vector2(300, 36)
		hover_label.add_theme_font_size_override("font_size", 20)
		hover_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7, 1))
		hover_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		hover_label.add_theme_constant_override("outline_size", 5)
		hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key_name = OS.get_keycode_string(SettingsManager.get_action_keycode("hover"))
		hover_label.text = "高度悬停中（%s）" % key_name
		add_child(hover_label)
	hover_label.visible = active

# === 导弹锁定HUD ===
func _create_lock_hud() -> void:
	"""创建导弹锁定HUD界面"""
	if _lock_hud_created:
		return
	_lock_hud_created = true
	# 容器
	lock_hud = Control.new()
	lock_hud.name = "LockHUD"
	lock_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lock_hud)
	# 锁定状态标签（屏幕中央偏上）
	lock_status_label = Label.new()
	lock_status_label.name = "LockStatusLabel"
	lock_status_label.position = Vector2(0, 80)
	lock_status_label.size = Vector2(300, 30)
	lock_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lock_status_label.add_theme_font_size_override("font_size", 18)
	lock_status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	lock_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lock_status_label.add_theme_constant_override("outline_size", 4)
	lock_hud.add_child(lock_status_label)
	# 目标距离标签
	lock_distance_label = Label.new()
	lock_distance_label.name = "LockDistanceLabel"
	lock_distance_label.position = Vector2(0, 110)
	lock_distance_label.size = Vector2(300, 24)
	lock_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_distance_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lock_distance_label.add_theme_font_size_override("font_size", 14)
	lock_distance_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3, 1))
	lock_distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lock_distance_label.add_theme_constant_override("outline_size", 3)
	lock_hud.add_child(lock_distance_label)
	# 目标名称标签
	lock_target_label = Label.new()
	lock_target_label.name = "LockTargetLabel"
	lock_target_label.position = Vector2(0, 134)
	lock_target_label.size = Vector2(300, 20)
	lock_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_target_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lock_target_label.add_theme_font_size_override("font_size", 12)
	lock_target_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	lock_target_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lock_target_label.add_theme_constant_override("outline_size", 3)
	lock_hud.add_child(lock_target_label)
	# 锁定框（围绕目标）
	lock_box = ColorRect.new()
	lock_box.name = "LockBox"
	lock_box.color = Color(1, 0.2, 0.2, 0.9)
	lock_box.size = Vector2(30, 30)
	lock_box.visible = false
	lock_hud.add_child(lock_box)
	# 锁定范围圆圈（跟随准心位置）
	lock_range_circle = Control.new()
	lock_range_circle.name = "LockRangeCircle"
	lock_range_circle.size = Vector2(200, 200)
	lock_range_circle.visible = false
	lock_range_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 用draw绘制圆形
	lock_range_circle.draw.connect(func():
		var center = lock_range_circle.size * 0.5
		var radius = lock_range_circle.size.x * 0.5
		# 半透明填充
		lock_range_circle.draw_circle(center, radius, Color(1, 0.3, 0.3, 0.06))
		# 圆形边框（用多段线画圆）
		var points = PackedVector2Array()
		for i in range(65):
			var ang = TAU * i / 64.0
			points.append(center + Vector2(cos(ang), sin(ang)) * radius)
		lock_range_circle.draw_polyline(points, Color(1, 0.3, 0.3, 0.5), 1.5)
	)
	lock_hud.add_child(lock_range_circle)

func _update_lock_hud() -> void:
	"""更新锁定HUD显示"""
	if not lock_hud or not player_vehicle or not player_vehicle.has_method("get_lock_info"):
		return
	var info = player_vehicle.get_lock_info()
	var guidance = info.get("guidance", "none")
	var lock_range = info.get("range", 0.0)
	var lock_fov = info.get("fov", 0.0)
	# 非制导弹药，隐藏所有锁定UI
	if guidance == "none" or lock_range <= 0.0:
		lock_status_label.visible = false
		lock_distance_label.visible = false
		lock_target_label.visible = false
		lock_box.visible = false
		lock_range_circle.visible = false
		return
	# 显示锁定范围圆圈（基于lock_fov角度计算大小，位置跟随准心）
	lock_range_circle.visible = true
	var cam = get_viewport().get_camera_3d()
	var cam_fov = cam.fov if cam else 70.0
	var vp_size = get_viewport().get_visible_rect().size
	# 锁定视场角在屏幕上的半径（基于垂直FOV比例）
	var circle_radius = int((lock_fov / cam_fov) * (vp_size.y * 0.5))
	circle_radius = clamp(circle_radius, 30, int(vp_size.y * 0.4))
	lock_range_circle.size = Vector2(circle_radius * 2, circle_radius * 2)
	# 位置跟随屏幕中心（视角方向，而非十字准心——坦克异步视角时两者不同）
	var vp_center = get_viewport().get_visible_rect().size * 0.5
	lock_range_circle.position = vp_center - Vector2(circle_radius, circle_radius)
	lock_range_circle.queue_redraw()
	# 锁定状态
	lock_status_label.visible = true
	if info.get("has_lock", false):
		lock_status_label.text = "● 已锁定"
		lock_status_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	elif info.get("is_locking", false):
		var prog = int(info.get("progress", 0.0) * 100)
		lock_status_label.text = "◎ 锁定中 %d%%" % prog
		lock_status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
	else:
		lock_status_label.text = "○ 搜索目标"
		lock_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	# 距离和目标
	var target = info.get("target", null)
	var dist = info.get("distance", 0.0)
	if target and info.get("has_lock", false):
		lock_distance_label.visible = true
		lock_distance_label.text = "距离: %.0fm" % dist
		lock_target_label.visible = true
		var tname = target.nickname if "nickname" in target else "目标"
		lock_target_label.text = "目标: %s" % tname
		# 在目标位置显示锁定框
		if cam:
			var target_pos = target.global_position + Vector3(0, 1.5, 0)
			var screen_pos = cam.unproject_position(target_pos)
			var is_behind = cam.is_position_behind(target_pos)
			if not is_behind and screen_pos.x >= 0 and screen_pos.x <= get_viewport().size.x and screen_pos.y >= 0 and screen_pos.y <= get_viewport().size.y:
				lock_box.visible = true
				# 锁定框大小随距离变化（缩小避免挡视野）
				var box_size = int(clamp(40 - dist * 0.008, 16, 40))
				lock_box.size = Vector2(box_size, box_size)
				lock_box.position = screen_pos - Vector2(box_size * 0.5, box_size * 0.5)
			else:
				lock_box.visible = false
	else:
		lock_distance_label.visible = false
		lock_target_label.visible = false
		lock_box.visible = false
