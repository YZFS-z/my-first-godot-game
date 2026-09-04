extends Control
## 局域网房间大厅 - 选队伍、准备、房主开始游戏

@onready var room_info_label: Label = $Panel/VBox/RoomInfo
@onready var player_list: VBoxContainer = $Panel/VBox/PlayerListScroll/PlayerList
@onready var team1_button: Button = $Panel/VBox/TeamSelect/Team1Button
@onready var team2_button: Button = $Panel/VBox/TeamSelect/Team2Button
@onready var ready_button: Button = $Panel/VBox/ReadyButton
@onready var start_button: Button = $Panel/VBox/StartButton
@onready var leave_button: Button = $Panel/VBox/LeaveButton

var local_team: int = 1
var local_ready: bool = false
var is_host: bool = false

func _ready() -> void:
	is_host = NetworkManager.is_server
	local_team = GameManager.public_player_team if GameManager.public_player_team > 0 else 1
	# 连接信号
	NetworkManager.lan_room_synced.connect(_on_room_synced)
	NetworkManager.lan_game_start.connect(_on_game_start)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	team1_button.pressed.connect(_on_team1)
	team2_button.pressed.connect(_on_team2)
	ready_button.pressed.connect(_on_ready_toggled)
	start_button.pressed.connect(_on_start_game)
	leave_button.pressed.connect(_on_leave)
	# 房主：注册自己，开始广播
	if is_host:
		NetworkManager.lan_room_players[1] = {
			"name": SettingsManager.get_nickname(),
			"team": local_team,
			"ready": false,
		}
		NetworkManager._lan_broadcast_room()
	else:
		# 客户端：注册自己
		NetworkManager.lan_register_player(SettingsManager.get_nickname(), local_team)
	_update_team_buttons()
	_update_ready_button()
	start_button.visible = is_host
	room_info_label.text = "房主: %s  地图: %s" % [
		SettingsManager.get_nickname() if is_host else "房主",
		GameManager.selected_map_id
	]

func _on_team1() -> void:
	if local_team == 1:
		return
	local_team = 1
	GameManager.public_player_team = 1
	if is_host:
		NetworkManager.lan_room_players[1]["team"] = 1
		NetworkManager.lan_room_players[1]["ready"] = false
		NetworkManager._lan_broadcast_room()
	else:
		NetworkManager.lan_request_team(1)
	local_ready = false
	_update_team_buttons()
	_update_ready_button()

func _on_team2() -> void:
	if local_team == 2:
		return
	local_team = 2
	GameManager.public_player_team = 2
	if is_host:
		NetworkManager.lan_room_players[1]["team"] = 2
		NetworkManager.lan_room_players[1]["ready"] = false
		NetworkManager._lan_broadcast_room()
	else:
		NetworkManager.lan_request_team(2)
	local_ready = false
	_update_team_buttons()
	_update_ready_button()

func _on_ready_toggled() -> void:
	local_ready = not local_ready
	if is_host:
		NetworkManager.lan_room_players[1]["ready"] = local_ready
		NetworkManager._lan_broadcast_room()
	else:
		NetworkManager.lan_request_ready(local_ready)
	_update_ready_button()

func _on_start_game() -> void:
	# 检查所有玩家是否准备
	var all_ready = true
	for pid in NetworkManager.lan_room_players.keys():
		if not NetworkManager.lan_room_players[pid]["ready"]:
			all_ready = false
			break
	if not all_ready:
		room_info_label.text = "还有玩家未准备！"
		return
	# 联机内容检查
	var check = GameManager.check_online_content(GameManager.selected_vehicle_id, GameManager.selected_map_id, SettingsManager.is_allow_custom_content())
	if not check.ok:
		room_info_label.text = check.reason
		return
	# 房主自己也要准备
	NetworkManager.lan_room_players[1]["ready"] = true
	NetworkManager.lan_start_game()

func _on_leave() -> void:
	NetworkManager.stop_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_server_disconnected() -> void:
	room_info_label.text = "与房主断开连接！"
	await get_tree().create_timer(2.0).timeout
	NetworkManager.stop_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_room_synced(players: Array) -> void:
	_refresh_player_list(players)
	# 更新本地状态
	var my_id = 1 if is_host else multiplayer.get_unique_id()
	if my_id in NetworkManager.lan_room_players:
		local_team = NetworkManager.lan_room_players[my_id]["team"]
		local_ready = NetworkManager.lan_room_players[my_id]["ready"]
		_update_team_buttons()
		_update_ready_button()

func _on_game_start() -> void:
	if not is_inside_tree():
		return
	room_info_label.text = "游戏开始！进入战场..."
	# 使用call_deferred避免await期间节点被释放
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")

func _refresh_player_list(players: Array) -> void:
	for child in player_list.get_children():
		child.queue_free()
	for p in players:
		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override("separation", 6)
		var team_color = Color(0.3, 0.6, 1) if p.team == 1 else Color(1, 0.4, 0.4)

		# 房主王冠图标
		if p.id == 1:
			var crown_icon = TextureRect.new()
			crown_icon.texture = load("res://assets/icons/crown.png")
			crown_icon.custom_minimum_size = Vector2(18, 18)
			crown_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			crown_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			row.add_child(crown_icon)
		else:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(24, 0)
			row.add_child(spacer)

		var name_label = Label.new()
		name_label.text = p.name
		name_label.modulate = team_color
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 15)
		row.add_child(name_label)
		var ready_label = Label.new()
		ready_label.text = "[已准备]" if p.ready else "未准备"
		ready_label.modulate = Color(0.4, 1, 0.4) if p.ready else Color(0.6, 0.6, 0.6)
		ready_label.add_theme_font_size_override("font_size", 14)
		row.add_child(ready_label)
		player_list.add_child(row)

func _update_team_buttons() -> void:
	team1_button.modulate = Color(0.3, 0.5, 1.0) if local_team == 1 else Color(1, 1, 1)
	team2_button.modulate = Color(1.0, 0.3, 0.3) if local_team == 2 else Color(1, 1, 1)

func _update_ready_button() -> void:
	ready_button.text = "取消准备" if local_ready else "准备"
	ready_button.modulate = Color(0.3, 1, 0.3) if local_ready else Color(1, 1, 1)
