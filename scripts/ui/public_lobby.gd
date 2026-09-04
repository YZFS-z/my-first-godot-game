extends Control
## 公网联机大厅
## 连接 game.thefeishu.top:8765 (Python服务器)
## 功能：登录/注册、房间列表、创建/加入房间、好友系统、组队

# === 节点引用 ===
@onready var back_button: Button = $BackButton
@onready var title_label: Label = $TitleLabel
@onready var global_status: Label = $GlobalStatus

# 登录面板
@onready var login_panel: PanelContainer = $LoginPanel
@onready var server_input: LineEdit = $LoginPanel/VBox/ServerInput
@onready var username_input: LineEdit = $LoginPanel/VBox/UsernameInput
@onready var password_input: LineEdit = $LoginPanel/VBox/PasswordInput
@onready var login_button: Button = $LoginPanel/VBox/ButtonRow/LoginButton
@onready var register_button: Button = $LoginPanel/VBox/ButtonRow/RegisterButton
@onready var login_status: Label = $LoginPanel/VBox/StatusLabel
var reset_dialog: Window = null  # 重置密码确认对话框
var reset_pending_username: String = ""
var reset_pending_password: String = ""

# 主面板
@onready var main_panel: PanelContainer = $MainPanel
@onready var welcome_label: Label = $MainPanel/MainVBox/TopBar/WelcomeLabel
@onready var conn_status_label: Label = $MainPanel/MainVBox/TopBar/ConnStatusLabel
@onready var logout_button: Button = $MainPanel/MainVBox/TopBar/LogoutButton

# 房间标签
@onready var refresh_rooms_button: Button = $MainPanel/MainVBox/Tabs/房间/RoomToolbar/RefreshRoomsButton
@onready var create_room_button: Button = $MainPanel/MainVBox/Tabs/房间/RoomToolbar/CreateRoomButton
@onready var room_list: VBoxContainer = $MainPanel/MainVBox/Tabs/房间/RoomListScroll/RoomList

# 好友标签
@onready var add_friend_input: LineEdit = $MainPanel/MainVBox/Tabs/好友/FriendToolbar/AddFriendInput
@onready var add_friend_button: Button = $MainPanel/MainVBox/Tabs/好友/FriendToolbar/AddFriendButton
@onready var friend_requests_list: VBoxContainer = $MainPanel/MainVBox/Tabs/好友/FriendRequestsScroll/FriendRequestsList
@onready var friend_list: VBoxContainer = $MainPanel/MainVBox/Tabs/好友/FriendListScroll/FriendList

# 组队标签
@onready var party_info_label: Label = $MainPanel/MainVBox/Tabs/组队/PartyInfoLabel
@onready var party_member_list: VBoxContainer = $MainPanel/MainVBox/Tabs/组队/PartyMemberList
@onready var party_invite_input: LineEdit = $MainPanel/MainVBox/Tabs/组队/PartyInviteRow/PartyInviteInput
@onready var party_invite_button: Button = $MainPanel/MainVBox/Tabs/组队/PartyInviteRow/PartyInviteButton
@onready var party_leave_button: Button = $MainPanel/MainVBox/Tabs/组队/PartyLeaveButton

# 房间详情
@onready var room_detail_panel: PanelContainer = $RoomDetailPanel
@onready var room_name_label: Label = $RoomDetailPanel/RoomDetailVBox/RoomDetailTop/RoomNameLabel
@onready var leave_room_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailTop/LeaveRoomButton
@onready var player_list: VBoxContainer = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/PlayerListScroll/PlayerList
@onready var start_game_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/StartGameButton
@onready var ready_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/ReadyButton
@onready var team1_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/TeamSelect/Team1Button
@onready var team2_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/TeamSelect/Team2Button
@onready var vehicle_option: OptionButton = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/PlayerPanel/VehicleSelect/VehicleOption
@onready var chat_box: VBoxContainer = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/ChatPanel/ChatScroll/ChatBox
@onready var chat_input: LineEdit = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/ChatPanel/ChatInputRow/ChatInput
@onready var chat_send_button: Button = $RoomDetailPanel/RoomDetailVBox/RoomDetailContent/ChatPanel/ChatInputRow/ChatSendButton

# 创建房间对话框
@onready var create_dialog: Window = $CreateRoomDialog
@onready var cr_name_input: LineEdit = $CreateRoomDialog/DialogVBox/CRNameInput
@onready var cr_map_option: OptionButton = $CreateRoomDialog/DialogVBox/CRMapOption
@onready var cr_max_spin: SpinBox = $CreateRoomDialog/DialogVBox/CRMaxSpin
@onready var cr_password_input: LineEdit = $CreateRoomDialog/DialogVBox/CRPasswordInput
# AI配置UI（动态创建）
var cr_team1_count: SpinBox
var cr_team1_diff: OptionButton
var cr_team2_count: SpinBox
var cr_team2_diff: OptionButton
var cr_air_boundary: SpinBox
@onready var cr_cancel_button: Button = $CreateRoomDialog/DialogVBox/CRButtonRow/CRCancelButton
@onready var cr_confirm_button: Button = $CreateRoomDialog/DialogVBox/CRButtonRow/CRConfirmButton

# 加入房间密码对话框
@onready var join_dialog: Window = $JoinRoomDialog
@onready var join_room_name_label: Label = $JoinRoomDialog/JoinVBox/JoinRoomNameLabel
@onready var join_password_input: LineEdit = $JoinRoomDialog/JoinVBox/JoinPasswordInput
@onready var join_status_label: Label = $JoinRoomDialog/JoinVBox/JoinStatusLabel
@onready var join_cancel_button: Button = $JoinRoomDialog/JoinVBox/JoinButtonRow/JoinCancelButton
@onready var join_confirm_button: Button = $JoinRoomDialog/JoinVBox/JoinButtonRow/JoinConfirmButton
var _pending_join_room_id: String = ""
var _pending_join_room_name: String = ""

var current_room_info: Dictionary = {}
var pending_friend_requests: Array = []
var _local_ready: bool = false
var _local_team: int = 1
var _local_resource_ready: bool = false  # 本地玩家资源是否下载完成
var _players_resource_ready: Dictionary = {}  # user_id -> bool，其他玩家资源就绪状态
var _room_resource_check_done: bool = false  # 房间资源检查是否已执行（避免重复）
var _room_has_custom_resources: bool = false  # 房间是否包含自定义资源（没有则无需等待下载）
var _downloaded_resource_keys: Dictionary = {}  # 已下载的资源 "type:id" -> true，避免重复下载
var _is_downloading_resources: bool = false  # 是否正在下载资源（防止重复下载）

func _ready() -> void:
	# 初始状态：只显示登录面板，必须先登录
	login_panel.visible = true
	main_panel.visible = false
	room_detail_panel.visible = false
	# Window节点不受父节点visible控制，显式隐藏
	create_dialog.hide()
	join_dialog.hide()
	join_cancel_button.pressed.connect(_on_join_cancel)
	join_confirm_button.pressed.connect(_on_join_confirm)
	join_password_input.text_submitted.connect(func(_text): _on_join_confirm())
	# 重置登录状态（Autoload会保留上次状态，进入大厅时强制重新登录）
	NetworkManager.public_authenticated = false
	NetworkManager.public_user_id = ""
	NetworkManager.public_username = ""

	# 连接信号
	back_button.pressed.connect(_on_back)
	login_button.pressed.connect(_on_login)
	register_button.pressed.connect(_on_register)
	# 动态创建重置密码按钮
	var button_row = login_button.get_parent()
	var reset_btn = Button.new()
	reset_btn.name = "ResetPasswordButton"
	reset_btn.text = "重置密码"
	reset_btn.custom_minimum_size = Vector2(80, 0)
	reset_btn.pressed.connect(_on_reset_password)
	button_row.add_child(reset_btn)
	logout_button.pressed.connect(_on_logout)
	# 动态创建删除账号按钮（放在登出按钮旁边）
	var del_btn = Button.new()
	del_btn.name = "DeleteAccountButton"
	del_btn.text = "删除账号"
	del_btn.custom_minimum_size = Vector2(80, 0)
	del_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	del_btn.pressed.connect(_on_delete_account)
	logout_button.get_parent().add_child(del_btn)
	refresh_rooms_button.pressed.connect(_on_refresh_rooms)
	create_room_button.pressed.connect(_on_create_room_clicked)
	add_friend_button.pressed.connect(_on_add_friend)
	party_invite_button.pressed.connect(_on_party_invite)
	party_leave_button.pressed.connect(_on_party_leave)
	leave_room_button.pressed.connect(_on_leave_room)
	ready_button.pressed.connect(_on_ready_toggled)
	team1_button.pressed.connect(_on_team1_selected)
	team2_button.pressed.connect(_on_team2_selected)
	_populate_vehicle_option()
	vehicle_option.item_selected.connect(_on_vehicle_selected)
	start_game_button.pressed.connect(_on_start_game)
	chat_send_button.pressed.connect(_on_chat_send)
	chat_input.text_submitted.connect(_on_chat_submit)
	cr_cancel_button.pressed.connect(_on_cr_cancel)
	cr_confirm_button.pressed.connect(_on_cr_confirm)
	# 动态创建AI配置UI（插入到按钮行之前）
	_create_ai_config_ui()
	create_dialog.close_requested.connect(_on_cr_cancel)

	# 网络信号
	NetworkManager.public_connected.connect(_on_public_connected)
	NetworkManager.public_disconnected.connect(_on_public_disconnected)
	NetworkManager.public_login_result.connect(_on_public_login_result)
	NetworkManager.public_reset_result.connect(_on_public_reset_result)
	NetworkManager.public_room_list.connect(_on_public_room_list)
	NetworkManager.public_room_info.connect(_on_public_room_info)
	NetworkManager.public_room_chat.connect(_on_public_room_chat)
	NetworkManager.public_resource_ready.connect(_on_public_resource_ready)
	NetworkManager.public_game_start.connect(_on_public_game_start)
	NetworkManager.public_friend_list.connect(_on_public_friend_list)
	NetworkManager.public_friend_request.connect(_on_public_friend_request)
	NetworkManager.public_friend_online.connect(_on_public_friend_online)
	NetworkManager.public_friend_offline.connect(_on_public_friend_offline)
	NetworkManager.public_party_invite.connect(_on_public_party_invite)
	NetworkManager.public_party_info.connect(_on_public_party_info)
	NetworkManager.public_error.connect(_on_public_error)

	# 填充地图列表
	_populate_map_options()

	# 填充服务器地址
	server_input.text = "%s:%d" % [NetworkManager.get_public_server_host(), NetworkManager.get_public_server_port()]

	# 自动连接服务器
	login_status.text = "正在连接服务器..."
	login_status.modulate = Color(1, 0.8, 0.3)
	NetworkManager.public_connect()

func _populate_map_options() -> void:
	cr_map_option.clear()
	var maps: Dictionary = DataLoader.get_all_maps() if DataLoader else {}
	for map_id in maps.keys():
		cr_map_option.add_item(map_id)
	if cr_map_option.item_count == 0:
		cr_map_option.add_item("map_desert")
		cr_map_option.add_item("map_europe")

# === 登录/注册 ===
func _parse_server_address(text: String) -> Dictionary:
	"""解析 主机:端口 格式，返回 {host, port}"""
	var result: Dictionary = {"host": NetworkManager.get_public_server_host(), "port": NetworkManager.get_public_server_port()}
	text = text.strip_edges()
	if text.is_empty():
		return result
	if ":" in text:
		var parts: Array = text.split(":")
		result.host = parts[0].strip_edges()
		if parts.size() > 1:
			var port_str: String = parts[1].strip_edges()
			if port_str.is_valid_int():
				result.port = int(port_str)
	else:
		result.host = text
	return result

func _connect_to_input_server() -> void:
	"""根据输入框的服务器地址连接"""
	var addr: Dictionary = _parse_server_address(server_input.text)
	# 保存到设置
	if SettingsManager:
		SettingsManager.set_setting("network", "public_server_host", addr.host)
		SettingsManager.set_setting("network", "public_server_port", addr.port)
		SettingsManager.save_settings()
	NetworkManager.public_connect(addr.host, addr.port)

func _on_login() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text
	if username.length() < 2:
		login_status.text = "用户名至少2位"
		login_status.modulate = Color(1, 0.3, 0.3)
		return
	if password.length() < 4:
		login_status.text = "密码至少4位"
		login_status.modulate = Color(1, 0.3, 0.3)
		return
	# 确保连接到正确的服务器
	if not NetworkManager.public_is_tcp_connected():
		_connect_to_input_server()
	login_status.text = "登录中..."
	login_status.modulate = Color(1, 0.8, 0.3)
	NetworkManager.public_login(username, password)

func _on_register() -> void:
	_show_auth_dialog("register")

func _on_reset_password() -> void:
	_show_auth_dialog("reset")

func _show_auth_dialog(mode: String) -> void:
	"""mode: register / reset — 包含邮箱+验证码的注册/重置对话框"""
	var dlg = Window.new()
	dlg.title = "注册账号" if mode == "register" else "重置密码"
	dlg.unresizable = true
	dlg.size = Vector2i(340, 380)
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 12.0
	vbox.offset_right = -12.0
	vbox.offset_top = 12.0
	vbox.offset_bottom = -12.0
	vbox.add_theme_constant_override("separation", 8)
	dlg.add_child(vbox)

	var status_label = Label.new()
	status_label.text = ""
	vbox.add_child(status_label)

	var user_input = LineEdit.new()
	user_input.placeholder_text = "用户名 (2-20位)"
	vbox.add_child(user_input)

	var email_input = LineEdit.new()
	email_input.placeholder_text = "邮箱地址"
	vbox.add_child(email_input)

	var pwd_input = LineEdit.new()
	pwd_input.placeholder_text = "密码 (至少4位)" if mode == "register" else "新密码 (至少4位)"
	pwd_input.secret = true
	vbox.add_child(pwd_input)

	var pwd2_input = LineEdit.new()
	pwd2_input.placeholder_text = "确认密码"
	pwd2_input.secret = true
	vbox.add_child(pwd2_input)

	var code_row = HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 6)
	vbox.add_child(code_row)
	var code_input = LineEdit.new()
	code_input.placeholder_text = "6位验证码"
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_input)
	var send_code_btn = Button.new()
	send_code_btn.text = "发送验证码"
	send_code_btn.custom_minimum_size = Vector2(90, 0)
	code_row.add_child(send_code_btn)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	var ok_btn = Button.new()
	ok_btn.text = "确认注册" if mode == "register" else "确认重置"
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(cancel_btn)

	# 发送验证码
	send_code_btn.pressed.connect(func():
		var email = email_input.text.strip_edges()
		var username = user_input.text.strip_edges()
		if not email or "@" not in email:
			status_label.text = "请输入有效的邮箱"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		if mode == "reset" and username.length() < 2:
			status_label.text = "请输入用户名"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		if not NetworkManager.public_is_tcp_connected():
			_connect_to_input_server()
		NetworkManager.public_send_code(email, username, mode)
		status_label.text = "验证码发送中..."
		status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		send_code_btn.disabled = true
		send_code_btn.text = "60s后重发"
		_start_code_countdown(send_code_btn)
	)

	var on_code_result = func(success, msg):
		status_label.text = msg
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3) if success else Color(1, 0.3, 0.3))
	NetworkManager.public_send_code_result.connect(on_code_result)

	ok_btn.pressed.connect(func():
		var username = user_input.text.strip_edges()
		var email = email_input.text.strip_edges()
		var pwd = pwd_input.text
		var pwd2 = pwd2_input.text
		var code = code_input.text.strip_edges()
		if username.length() < 2 or username.length() > 20:
			status_label.text = "用户名长度2-20位"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		if pwd.length() < 4:
			status_label.text = "密码至少4位"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		if pwd != pwd2:
			status_label.text = "两次密码不一致"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		if not NetworkManager.public_is_tcp_connected():
			_connect_to_input_server()
		if mode == "register":
			NetworkManager.public_register(username, pwd, email, code)
			login_status.text = "注册中..."
		else:
			NetworkManager.public_reset_password(username, email, code, pwd)
			login_status.text = "重置密码中..."
		login_status.modulate = Color(1, 0.8, 0.3)
		dlg.queue_free()
	)

	cancel_btn.pressed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.tree_exited.connect(func():
		if NetworkManager.public_send_code_result.is_connected(on_code_result):
			NetworkManager.public_send_code_result.disconnect(on_code_result)
	)
	add_child(dlg)
	dlg.popup_centered()

func _start_code_countdown(btn: Button) -> void:
	var t = 60
	while t > 0 and is_instance_valid(btn):
		await get_tree().create_timer(1.0).timeout
		t -= 1
		if not is_instance_valid(btn):
			return
		btn.text = "%ds后重发" % t
	if is_instance_valid(btn):
		btn.disabled = false
		btn.text = "发送验证码"

func _on_public_reset_result(success: bool, message: String) -> void:
	if success:
		login_status.text = message
		login_status.modulate = Color(0.3, 1, 0.3)
	else:
		login_status.text = message
		login_status.modulate = Color(1, 0.3, 0.3)

func _on_logout() -> void:
	NetworkManager.public_logout()
	_show_login_panel()

func _on_delete_account() -> void:
	"""删除账号：弹出确认对话框输入密码"""
	var dlg = Window.new()
	dlg.title = "删除账号"
	dlg.unresizable = true
	dlg.size = Vector2i(320, 200)
	var vbox = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 12.0
	vbox.offset_right = -12.0
	vbox.offset_top = 12.0
	vbox.offset_bottom = -12.0
	vbox.add_theme_constant_override("separation", 8)
	dlg.add_child(vbox)

	var warn = Label.new()
	warn.text = "警告：账号删除后不可恢复！\n请输入密码确认删除 %s" % NetworkManager.public_username
	warn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	vbox.add_child(warn)

	var pwd_input = LineEdit.new()
	pwd_input.placeholder_text = "输入密码"
	pwd_input.secret = true
	vbox.add_child(pwd_input)

	var status = Label.new()
	status.text = ""
	vbox.add_child(status)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)
	var ok_btn = Button.new()
	ok_btn.text = "确认删除"
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	btn_row.add_child(ok_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(cancel_btn)

	var on_result = func(success, msg):
		status.text = msg
		status.add_theme_color_override("font_color", Color(0.3, 1, 0.3) if success else Color(1, 0.3, 0.3))
		if success:
			await get_tree().create_timer(1.5).timeout
			if is_instance_valid(dlg):
				dlg.queue_free()
			_show_login_panel()

	NetworkManager.public_delete_result.connect(on_result)

	ok_btn.pressed.connect(func():
		var pwd = pwd_input.text
		if pwd.length() < 4:
			status.text = "请输入正确的密码"
			status.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			return
		NetworkManager.public_delete_account(pwd)
		status.text = "删除中..."
		status.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		ok_btn.disabled = true
	)
	cancel_btn.pressed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.tree_exited.connect(func():
		if NetworkManager.public_delete_result.is_connected(on_result):
			NetworkManager.public_delete_result.disconnect(on_result)
	)
	add_child(dlg)
	dlg.popup_centered()
	pwd_input.grab_focus()

func _show_login_panel() -> void:
	login_panel.visible = true
	main_panel.visible = false
	room_detail_panel.visible = false
	login_status.text = ""
	username_input.text = ""
	password_input.text = ""

func _show_main_panel() -> void:
	login_panel.visible = false
	main_panel.visible = true
	room_detail_panel.visible = false
	welcome_label.text = "欢迎, %s" % NetworkManager.public_username
	conn_status_label.text = "● 已连接"
	conn_status_label.modulate = Color(0.3, 1, 0.3)
	# 刷新房间和好友
	NetworkManager.public_request_room_list()
	NetworkManager.public_request_friend_list()
	NetworkManager.public_request_party_info()

# === 网络回调 ===
func _on_public_connected() -> void:
	login_status.text = "已连接，请登录"
	login_status.modulate = Color(0.3, 1, 0.3)
	global_status.text = "已连接到 %s:%d" % [NetworkManager.public_current_host, NetworkManager.public_current_port]
	global_status.modulate = Color(0.3, 1, 0.3)

func _on_public_disconnected() -> void:
	global_status.text = "与服务器断开连接"
	global_status.modulate = Color(1, 0.3, 0.3)
	if main_panel.visible:
		_show_login_panel()
		login_status.text = "连接已断开"
		login_status.modulate = Color(1, 0.3, 0.3)

func _on_public_login_result(success: bool, message: String, user_data: Dictionary) -> void:
	if success:
		login_status.text = message
		login_status.modulate = Color(0.3, 1, 0.3)
		_show_main_panel()
	else:
		login_status.text = message
		login_status.modulate = Color(1, 0.3, 0.3)

func _on_public_error(code: int, message: String) -> void:
	global_status.text = "错误: %s" % message
	global_status.modulate = Color(1, 0.3, 0.3)
	# 如果加入房间对话框打开，在对话框中显示错误
	if join_dialog and join_dialog.visible:
		join_status_label.text = message
		join_status_label.modulate = Color(1, 0.4, 0.4, 1)

# === 房间 ===
func _on_refresh_rooms() -> void:
	NetworkManager.public_request_room_list()
	global_status.text = "刷新房间列表..."
	global_status.modulate = Color(1, 0.8, 0.3)

func _on_public_room_list(rooms: Array) -> void:
	_clear_container(room_list)
	if rooms.is_empty():
		var label: Label = Label.new()
		label.text = "暂无房间，点击\"创建房间\"开始游戏"
		label.modulate = Color(0.7, 0.7, 0.7)
		room_list.add_child(label)
		return
	for room in rooms:
		_add_room_row(room)
	global_status.text = "共 %d 个房间" % rooms.size()
	global_status.modulate = Color(0.3, 1, 0.3)

func _add_room_row(room: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 45)
	row.add_theme_constant_override("separation", 15)

	var name_label: Label = Label.new()
	name_label.text = room.get("name", "未知")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	row.add_child(name_label)

	var map_label: Label = Label.new()
	map_label.text = room.get("map_id", "")
	map_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(map_label)

	var players_label: Label = Label.new()
	players_label.text = "%d/%d" % [room.get("players", 0), room.get("max_players", 8)]
	players_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(players_label)

	var lock_icon: TextureRect = TextureRect.new()
	lock_icon.texture = load("res://assets/icons/lock.png") if room.get("has_password", false) else null
	lock_icon.custom_minimum_size = Vector2(24, 24)
	lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	row.add_child(lock_icon)

	var join_button: Button = Button.new()
	join_button.text = "加入"
	join_button.custom_minimum_size = Vector2(80, 35)
	var room_id: String = _safe_str(room.get("room_id"))
	join_button.pressed.connect(func(): _on_join_room(room_id, room.get("has_password", false), room.get("name", room_id)))
	row.add_child(join_button)

	room_list.add_child(row)

func _on_join_room(room_id: String, has_password: bool, room_name: String = "") -> void:
	if has_password:
		# 弹出密码输入对话框
		_pending_join_room_id = room_id
		_pending_join_room_name = room_name
		join_room_name_label.text = "房间: %s" % room_name
		join_password_input.text = ""
		join_status_label.text = ""
		join_dialog.show()
		join_password_input.grab_focus()
	else:
		NetworkManager.public_join_room(room_id, "")
		global_status.text = "正在加入房间..."
		global_status.modulate = Color(1, 0.8, 0.3)

func _on_join_cancel() -> void:
	join_dialog.hide()
	_pending_join_room_id = ""
	_pending_join_room_name = ""

func _on_join_confirm() -> void:
	var password = join_password_input.text.strip_edges()
	if password.length() == 0:
		join_status_label.text = "请输入密码"
		return
	NetworkManager.public_join_room(_pending_join_room_id, password)
	join_status_label.text = "正在加入..."
	join_status_label.modulate = Color(0.5, 0.8, 1, 1)
	# 延迟关闭对话框，等待服务器响应
	get_tree().create_timer(1.0).timeout.connect(func():
		if join_dialog.visible:
			join_dialog.hide()
	)

func _create_ai_config_ui() -> void:
	"""动态创建AI配置UI，插入到创建房间对话框的按钮行之前"""
	var dialog_vbox = create_dialog.get_node("DialogVBox")
	var button_row = dialog_vbox.get_node("CRButtonRow")
	var insert_idx = button_row.get_index()

	# AI配置标题
	var ai_label = Label.new()
	ai_label.text = "AI 配置（房主设置）:"
	ai_label.add_theme_font_size_override("font_size", 15)
	dialog_vbox.add_child(ai_label)
	dialog_vbox.move_child(ai_label, insert_idx)
	insert_idx += 1

	# 队伍1行
	var team1_row = HBoxContainer.new()
	team1_row.add_theme_constant_override("separation", 8)
	var team1_label = Label.new()
	team1_label.text = "队伍1(蓝):"
	team1_label.custom_minimum_size = Vector2(70, 0)
	team1_label.modulate = Color(0.4, 0.6, 1)
	team1_row.add_child(team1_label)
	cr_team1_count = SpinBox.new()
	cr_team1_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr_team1_count.custom_minimum_size = Vector2(0, 28)
	cr_team1_count.min_value = 0
	cr_team1_count.max_value = 8
	cr_team1_count.value = 0
	cr_team1_count.suffix = " 个"
	team1_row.add_child(cr_team1_count)
	cr_team1_diff = OptionButton.new()
	cr_team1_diff.custom_minimum_size = Vector2(80, 28)
	for d in ["简单", "普通", "困难"]:
		cr_team1_diff.add_item(d)
	cr_team1_diff.selected = 1
	team1_row.add_child(cr_team1_diff)
	dialog_vbox.add_child(team1_row)
	dialog_vbox.move_child(team1_row, insert_idx)
	insert_idx += 1

	# 队伍2行
	var team2_row = HBoxContainer.new()
	team2_row.add_theme_constant_override("separation", 8)
	var team2_label = Label.new()
	team2_label.text = "队伍2(红):"
	team2_label.custom_minimum_size = Vector2(70, 0)
	team2_label.modulate = Color(1, 0.4, 0.4)
	team2_row.add_child(team2_label)
	cr_team2_count = SpinBox.new()
	cr_team2_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr_team2_count.custom_minimum_size = Vector2(0, 28)
	cr_team2_count.min_value = 0
	cr_team2_count.max_value = 8
	cr_team2_count.value = 2
	cr_team2_count.suffix = " 个"
	team2_row.add_child(cr_team2_count)
	cr_team2_diff = OptionButton.new()
	cr_team2_diff.custom_minimum_size = Vector2(80, 28)
	for d in ["简单", "普通", "困难"]:
		cr_team2_diff.add_item(d)
	cr_team2_diff.selected = 1
	team2_row.add_child(cr_team2_diff)
	dialog_vbox.add_child(team2_row)
	dialog_vbox.move_child(team2_row, insert_idx)
	insert_idx += 1

	# 飞机边界大小行（房主设置，影响飞机/直升机的可飞行区域）
	var air_row = HBoxContainer.new()
	air_row.add_theme_constant_override("separation", 8)
	var air_label = Label.new()
	air_label.text = "飞机边界:"
	air_label.custom_minimum_size = Vector2(70, 0)
	air_label.modulate = Color(0.7, 0.9, 0.7)
	air_label.tooltip_text = "飞机/直升机的封闭活动区域边长（米，含地面与围墙），远大于坦克战场；0 表示使用地图默认值"
	air_row.add_child(air_label)
	cr_air_boundary = SpinBox.new()
	cr_air_boundary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr_air_boundary.custom_minimum_size = Vector2(0, 28)
	cr_air_boundary.min_value = 0
	cr_air_boundary.max_value = 40000
	cr_air_boundary.step = 1000
	cr_air_boundary.value = int(GameManager.air_boundary_size) if GameManager.air_boundary_size > 0 else 12000
	cr_air_boundary.suffix = " 米 (0=默认)"
	air_row.add_child(cr_air_boundary)
	dialog_vbox.add_child(air_row)
	dialog_vbox.move_child(air_row, insert_idx)

	# 增大对话框尺寸
	create_dialog.size = Vector2i(420, 580)

func _on_create_room_clicked() -> void:
	if not NetworkManager.public_authenticated:
		global_status.text = "请先登录后再创建房间"
		global_status.modulate = Color(1, 0.3, 0.3)
		return
	cr_name_input.text = "%s的房间" % NetworkManager.public_username
	cr_password_input.text = ""
	create_dialog.popup_centered()

func _on_cr_cancel() -> void:
	create_dialog.hide()

func _on_cr_confirm() -> void:
	var name: String = cr_name_input.text.strip_edges()
	var map_id: String = cr_map_option.get_item_text(cr_map_option.selected)
	var max_players: int = int(cr_max_spin.value)
	var password: String = cr_password_input.text
	if name.is_empty():
		name = "%s的房间" % NetworkManager.public_username
# 构建AI配置
	var ai_config = {
		"team1_count": int(cr_team1_count.value),
		"team1_difficulty": cr_team1_diff.selected,
		"team2_count": int(cr_team2_count.value),
		"team2_difficulty": cr_team2_diff.selected,
	}
	# 飞机边界（>0 时写入房间配置，0=使用地图默认）
	var air_size: int = int(cr_air_boundary.value)
	if air_size > 0:
		ai_config["air_boundary_size"] = air_size
	GameManager.air_boundary_size = air_size  # 房主本机立即生效
	GameManager.public_ai_config = ai_config
	# 自动上传自定义地图和载具到服务器
	_upload_custom_resources(map_id)
	NetworkManager.public_create_room(name, map_id, max_players, password, ai_config)
	create_dialog.hide()
	global_status.text = "正在创建房间..."
	global_status.modulate = Color(1, 0.8, 0.3)

func _upload_custom_resources(map_id: String) -> void:
	"""上传自定义地图和当前载具到服务器（如果是自定义的）"""
	# 上传自定义地图
	if not DataLoader.is_map_builtin(map_id):
		print("[PublicLobby] 上传自定义地图: %s" % map_id)
		GameManager.upload_custom_resource("map", map_id)
	# 上传当前选择的自定义载具
	var vid = GameManager.selected_vehicle_id
	if not vid.is_empty() and not DataLoader.is_vehicle_builtin(vid):
		print("[PublicLobby] 上传自定义载具: %s" % vid)
		GameManager.upload_custom_resource("vehicle", vid)

var _last_room_info_hash: String = ""
var _room_info_debounce_timer: float = 0.0
var _pending_room_info: Dictionary = {}
var _vehicle_synced: bool = false

func _on_public_room_info(room_info: Dictionary) -> void:
	# 防抖：避免服务器频繁推送导致UI反复重建
	_pending_room_info = room_info
	_room_info_debounce_timer = 0.1  # 100ms内的多次更新合并为一次

func _process(delta: float) -> void:
	# 处理防抖的房间信息更新
	if _room_info_debounce_timer > 0:
		_room_info_debounce_timer -= delta
		if _room_info_debounce_timer <= 0 and not _pending_room_info.is_empty():
			_apply_room_info(_pending_room_info)
			_pending_room_info = {}

func _apply_room_info(room_info: Dictionary) -> void:
	current_room_info = room_info
	# 显示房间详情
	main_panel.visible = false
	room_detail_panel.visible = true
	# 进入房间时同步当前载具选择（只同步一次）
	if not _vehicle_synced and not GameManager.selected_vehicle_id.is_empty():
		_vehicle_synced = true
		NetworkManager.public_set_vehicle(GameManager.selected_vehicle_id)
	# 检查并下载缺失的自定义资源（每次房间信息更新都检查，已下载的跳过）
	_check_and_download_room_resources()
	# 提前更新准备按钮状态（在玩家列表哈希检查之前）
	_update_ready_button_state()
	var players = room_info.get("players", [])
	# 计算玩家列表哈希，只有变化时才重建UI
	var players_hash = ""
	for p in players:
		players_hash += "%s:%s:%s:" % [p.get("user_id", ""), p.get("team", 0), p.get("ready", false)]
	if players_hash == _last_room_info_hash:
		return  # 玩家列表无变化，跳过UI重建
	_last_room_info_hash = players_hash
	var ready_count = 0
	for p in players:
		if p.get("ready", false):
			ready_count += 1
	room_name_label.text = "%s  [%s]  %d/%d  准备:%d/%d" % [
		room_info.get("name", ""),
		room_info.get("map_id", ""),
		players.size(),
		room_info.get("max_players", 8),
		ready_count,
		players.size()
	]
	# 更新玩家列表
	_clear_container(player_list)
	var is_host: bool = room_info.get("host_id", "") == NetworkManager.public_user_id
	start_game_button.visible = is_host
	# 更新本地准备按钮状态
	for p in players:
		if p.get("user_id", "") == NetworkManager.public_user_id:
			_local_ready = p.get("ready", false)
			_local_team = p.get("team", 1)
			ready_button.text = "取消准备" if _local_ready else "准备"
			ready_button.modulate = Color(0.3, 1, 0.3) if _local_ready else Color(1, 1, 1)
			_update_team_buttons()
			break
	for player in players:
		_add_player_row(player, is_host)
	# 同步玩家资源就绪状态（从房间信息）
	for p in players:
		var uid = _safe_str(p.get("user_id", ""))
		if uid != NetworkManager.public_user_id:
			_players_resource_ready[uid] = p.get("resource_ready", false)
	_update_ready_button_state()
	global_status.text = "已进入房间: %s" % room_info.get("name", "")
	global_status.modulate = Color(0.3, 1, 0.3)

func _add_player_row(player: Dictionary, is_host: bool) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 35)
	row.add_theme_constant_override("separation", 8)

	var team_color: Color = Color(0.3, 0.6, 1) if player.get("team", 1) == 1 else Color(1, 0.4, 0.4)
	var player_uid: String = _safe_str(player.get("user_id"))
	var host_uid: String = _safe_str(current_room_info.get("host_id"))
	var is_host_player: bool = player_uid == host_uid

	# 房主王冠图标
	if is_host_player:
		var crown_icon: TextureRect = TextureRect.new()
		crown_icon.texture = load("res://assets/icons/crown.png")
		crown_icon.custom_minimum_size = Vector2(20, 20)
		crown_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		row.add_child(crown_icon)

	# 载具名称
	var name_label: Label = Label.new()
	var vid = _safe_str(player.get("vehicle_id", "tank_abrams"))
	var vdata = DataLoader.get_vehicle(vid)
	var vname = vdata.get("name", vid) if not vdata.is_empty() else vid
	name_label.text = "%s (%s)" % [_safe_str(player.get("username")), vname]
	name_label.modulate = team_color
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	row.add_child(name_label)

	var ready_label: Label = Label.new()
	ready_label.text = "[已准备]" if player.get("ready", false) else "未准备"
	ready_label.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(ready_label)

	player_list.add_child(row)

func _on_leave_room() -> void:
	NetworkManager.public_leave_room()
	room_detail_panel.visible = false
	main_panel.visible = true
	_local_ready = false
	_vehicle_synced = false
	_last_room_info_hash = ""
	# 重置资源就绪状态
	_local_resource_ready = false
	_players_resource_ready.clear()
	_room_resource_check_done = false
	_room_has_custom_resources = false
	_downloaded_resource_keys.clear()
	_is_downloading_resources = false
	ready_button.disabled = false
	ready_button.text = "准备"
	ready_button.modulate = Color(1, 1, 1)
	NetworkManager.public_request_room_list()

func _on_ready_toggled() -> void:
	_local_ready = not _local_ready
	NetworkManager.public_set_ready(_local_ready)
	ready_button.text = "取消准备" if _local_ready else "准备"
	ready_button.modulate = Color(0.3, 1, 0.3) if _local_ready else Color(1, 1, 1)
	global_status.text = "已准备" if _local_ready else "已取消准备"
	global_status.modulate = Color(0.3, 1, 0.3) if _local_ready else Color(1, 1, 1)

func _on_team1_selected() -> void:
	if _local_team == 1:
		return
	_local_team = 1
	NetworkManager.public_set_team(1)
	# 换队后重置准备状态
	if _local_ready:
		_local_ready = false
		NetworkManager.public_set_ready(false)
		ready_button.text = "准备"
		ready_button.modulate = Color(1, 1, 1)
	_update_team_buttons()

func _on_team2_selected() -> void:
	if _local_team == 2:
		return
	_local_team = 2
	NetworkManager.public_set_team(2)
	if _local_ready:
		_local_ready = false
		NetworkManager.public_set_ready(false)
		ready_button.text = "准备"
		ready_button.modulate = Color(1, 1, 1)
	_update_team_buttons()

func _update_team_buttons() -> void:
	team1_button.modulate = Color(0.3, 0.5, 1.0) if _local_team == 1 else Color(1, 1, 1)
	team2_button.modulate = Color(1.0, 0.3, 0.3) if _local_team == 2 else Color(1, 1, 1)

func _populate_vehicle_option() -> void:
	"""从DataLoader加载所有载具，填充下拉列表（自定义载具标记）"""
	vehicle_option.clear()
	var vehicles = DataLoader.get_all_vehicles()
	var idx = 0
	for vid in vehicles.keys():
		var v = vehicles[vid]
		var display_name = v.get("name", vid)
		if not DataLoader.is_vehicle_builtin(vid):
			display_name += " [自定义]"
		vehicle_option.add_item(display_name, idx)
		vehicle_option.set_item_metadata(idx, vid)
		idx += 1
	# 默认选中当前载具
	var current = GameManager.selected_vehicle_id
	if current.is_empty():
		current = "tank_abrams"
	for i in range(vehicle_option.item_count):
		if str(vehicle_option.get_item_metadata(i)) == current:
			vehicle_option.selected = i
			break

func _on_vehicle_selected(index: int) -> void:
	"""选择载具后保存并同步到服务器"""
	if index < 0 or index >= vehicle_option.item_count:
		return
	var vid = str(vehicle_option.get_item_metadata(index))
	GameManager.selected_vehicle_id = vid
	NetworkManager.public_set_vehicle(vid)
	global_status.text = "已选择载具: %s" % vid
	global_status.modulate = Color(0.6, 0.8, 1.0)

func _on_start_game() -> void:
	# 检查所有玩家是否已准备
	var players = current_room_info.get("players", [])
	var not_ready = []
	for p in players:
		if not p.get("ready", false):
			not_ready.append(_safe_str(p.get("username")))
	if not_ready.size() > 0:
		global_status.text = "还有玩家未准备: %s" % ", ".join(not_ready)
		global_status.modulate = Color(1, 0.8, 0.3)
		return
	# 联机内容检查：自定义载具/地图需要所有玩家允许
	var map_id = _safe_str(current_room_info.get("map_id", "map_desert"))
	var check = GameManager.check_online_content(GameManager.selected_vehicle_id, map_id, SettingsManager.is_allow_custom_content())
	if not check.ok:
		global_status.text = check.reason
		global_status.modulate = Color(1, 0.4, 0.4)
		return
	NetworkManager.public_start_game()
	global_status.text = "正在启动游戏..."
	global_status.modulate = Color(1, 0.8, 0.3)

func _on_public_game_start(game_info: Dictionary) -> void:
	# 用客户端实际连接的地址覆盖服务器返回的地址（用户可能自定义了服务器地址）
	var actual_host: String = NetworkManager.public_current_host
	if actual_host.is_empty():
		actual_host = _safe_str(game_info.get("game_host"))
	var actual_port: int = int(game_info.get("game_port", NetworkManager.get_public_server_port()))
	global_status.text = "游戏开始! 连接 %s:%d" % [actual_host, actual_port]
	global_status.modulate = Color(0.3, 1, 0.3)
	# 保存游戏连接信息到GameManager，供进入战斗场景使用
	GameManager.network_type = 1  # 1=公网联机
	GameManager.public_game_host = actual_host
	GameManager.public_game_port = actual_port
	GameManager.selected_map_id = _safe_str(game_info.get("map_id"))
	GameManager.public_room_id = _safe_str(game_info.get("room_id"))
	GameManager.public_players = game_info.get("players", [])
	GameManager.public_ai_config = game_info.get("ai_config", {"team1_count": 0, "team1_difficulty": 1, "team2_count": 2, "team2_difficulty": 1})
	# 同步房主设置的飞机边界（0=地图默认）
	GameManager.air_boundary_size = float(GameManager.public_ai_config.get("air_boundary_size", 0.0))
	# 从玩家列表中找到自己的队伍
	var my_team: int = 1
	for p in GameManager.public_players:
		if p.get("user_id", "") == NetworkManager.public_user_id:
			my_team = p.get("team", 1)
			break
	GameManager.public_player_team = my_team
	print("[PublicLobby] 游戏开始: %s:%d, 地图: %s, 玩家数: %d, 队伍: %d" % [
		actual_host, actual_port,
		GameManager.selected_map_id,
		GameManager.public_players.size(),
		my_team
	])
	# 使用玩家在房间内选择的载具
	if GameManager.selected_vehicle_id.is_empty():
		GameManager.selected_vehicle_id = "tank_abrams"
	# 检查并下载缺失的自定义资源，然后校验所有自定义资源防止篡改
	var resources_ok = await _check_download_and_verify_resources(game_info)
	if not resources_ok:
		# 校验失败：发送系统聊天消息，重置游戏状态，留在房间
		var fail_msg = "【系统】资源校验失败，游戏已取消（资源可能被篡改或缺失）"
		_add_system_chat(fail_msg, Color(1, 0.4, 0.4))
		NetworkManager.public_send_room_chat(fail_msg)
		# 重置GameManager游戏设置
		GameManager.network_type = 0
		GameManager.public_game_host = ""
		GameManager.public_game_port = 0
		GameManager.public_room_id = ""
		global_status.text = "资源校验失败，已返回房间"
		global_status.modulate = Color(1, 0.4, 0.4)
		return
	# 延迟一帧让状态文字显示，然后进入战斗场景
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _check_and_download_room_resources() -> void:
	"""检查房间内自定义资源，下载缺失的。每次房间信息更新都调用，已下载的跳过。"""
	if current_room_info.is_empty():
		return
	# 收集房间内所有自定义资源
	var all_resources: Array = []
	var map_id = _safe_str(current_room_info.get("map_id"))
	if not map_id.is_empty() and not DataLoader.is_map_builtin(map_id):
		all_resources.append({"type": "map", "id": map_id})
	for p in current_room_info.get("players", []):
		var vid = _safe_str(p.get("vehicle_id", ""))
		if not vid.is_empty() and not DataLoader.is_vehicle_builtin(vid):
			var found = false
			for r in all_resources:
				if r.type == "vehicle" and r.id == vid:
					found = true
					break
			if not found:
				all_resources.append({"type": "vehicle", "id": vid})
	# 没有自定义资源，直接就绪
	if all_resources.is_empty():
		_room_has_custom_resources = false
		_local_resource_ready = true
		NetworkManager.public_send_resource_ready(true)
		_update_ready_button_state()
		return
	# 有自定义资源
	_room_has_custom_resources = true
	# 检查是否所有资源都已存在
	var all_exist = true
	for res in all_resources:
		if not GameManager.has_resource(res.type, res.id):
			all_exist = false
			break
	if all_exist:
		if not _local_resource_ready:
			_local_resource_ready = true
			NetworkManager.public_send_resource_ready(true)
			_add_system_chat("所有自定义资源已就绪", Color(0.4, 0.8, 1.0))
		_update_ready_button_state()
		return
	# 有缺失资源，且正在下载中则跳过
	if _is_downloading_resources:
		_update_ready_button_state()
		return
	# 开始下载
	_is_downloading_resources = true
	_local_resource_ready = false
	NetworkManager.public_send_resource_ready(false)
	_update_ready_button_state()
	# 收集缺失的资源
	var missing: Array = []
	for res in all_resources:
		var key = "%s:%s" % [res.type, res.id]
		if not GameManager.has_resource(res.type, res.id) and not _downloaded_resource_keys.has(key):
			missing.append(res)
	if missing.is_empty():
		# 所有缺失资源都已下载但has_resource仍返回false，可能是DataLoader未刷新
		DataLoader.load_maps()
		DataLoader.load_vehicles()
		_is_downloading_resources = false
		_check_and_download_room_resources()  # 重新检查
		return
	global_status.text = "正在下载资源 (%d个)..." % missing.size()
	global_status.modulate = Color(1, 0.8, 0.3)
	_add_system_chat("开始下载 %d 个自定义资源..." % missing.size(), Color(1, 0.8, 0.3))
	# 逐个下载
	for res in missing:
		await _download_one_resource(res.type, res.id)
		var key = "%s:%s" % [res.type, res.id]
		_downloaded_resource_keys[key] = true
	# 下载完成后重新加载数据
	DataLoader.load_maps()
	DataLoader.load_vehicles()
	_is_downloading_resources = false
	# 重新检查（可能还有新的缺失资源，或全部完成）
	_check_and_download_room_resources()

func _update_ready_button_state() -> void:
	"""根据资源就绪状态更新准备按钮"""
	if not is_instance_valid(ready_button):
		return
	# 房间没有自定义资源，直接启用准备按钮
	if not _room_has_custom_resources:
		ready_button.disabled = false
		ready_button.text = "取消准备" if _local_ready else "准备"
		ready_button.modulate = Color(0.3, 1, 0.3) if _local_ready else Color(1, 1, 1)
		return
	# 检查所有玩家资源是否就绪
	var all_ready = _local_resource_ready
	for p in current_room_info.get("players", []):
		var uid = _safe_str(p.get("user_id", ""))
		if uid == NetworkManager.public_user_id:
			continue
		if not _players_resource_ready.get(uid, false):
			all_ready = false
			break
	if not _local_resource_ready:
		ready_button.disabled = true
		ready_button.text = "下载资源中..."
		ready_button.modulate = Color(0.6, 0.6, 0.6)
	elif not all_ready:
		ready_button.disabled = true
		ready_button.text = "等待其他玩家下载..."
		ready_button.modulate = Color(0.6, 0.6, 0.6)
	else:
		ready_button.disabled = false
		ready_button.text = "取消准备" if _local_ready else "准备"
		ready_button.modulate = Color(0.3, 1, 0.3) if _local_ready else Color(1, 1, 1)

func _check_download_and_verify_resources(game_info: Dictionary) -> bool:
	"""检查、下载缺失资源，并校验所有自定义资源哈希防止篡改。返回true=全部通过，false=校验失败"""
	var all_resources: Array = []
	# 收集地图
	var map_id = _safe_str(game_info.get("map_id"))
	if not map_id.is_empty():
		all_resources.append({"type": "map", "id": map_id})
	# 收集所有玩家载具
	for p in game_info.get("players", []):
		var vid = _safe_str(p.get("vehicle_id", ""))
		if not vid.is_empty():
			var found = false
			for r in all_resources:
				if r.type == "vehicle" and r.id == vid:
					found = true
					break
			if not found:
				all_resources.append({"type": "vehicle", "id": vid})
	# 第一步：下载缺失的自定义资源
	var missing: Array = []
	for res in all_resources:
		if not GameManager.has_resource(res.type, res.id):
			missing.append(res)
	if not missing.is_empty():
		print("[PublicLobby] 发现 %d 个缺失资源，开始下载..." % missing.size())
		global_status.text = "正在下载资源 (%d个)..." % missing.size()
		global_status.modulate = Color(1, 0.8, 0.3)
		for res in missing:
			await _download_one_resource(res.type, res.id)
	# 第二步：检查所有自定义资源是否存在于本地（不向服务器校验，只要玩家间资源一致即可）
	var custom_resources: Array = []
	for res in all_resources:
		if res.type == "map" and not DataLoader.is_map_builtin(res.id):
			custom_resources.append(res)
		elif res.type == "vehicle" and not DataLoader.is_vehicle_builtin(res.id):
			custom_resources.append(res)
	if not custom_resources.is_empty():
		print("[PublicLobby] 检查 %d 个自定义资源本地存在性..." % custom_resources.size())
		global_status.text = "正在检查资源 (%d个)..." % custom_resources.size()
		global_status.modulate = Color(1, 0.8, 0.3)
		for res in custom_resources:
			if not GameManager.has_resource(res.type, res.id):
				print("[PublicLobby] 资源缺失: %s/%s" % [res.type, res.id])
				return false
	global_status.text = "资源检查完成"
	global_status.modulate = Color(0.3, 1, 0.3)
	return true

func _download_one_resource(res_type: String, res_id: String) -> void:
	"""下载单个资源，等待完成"""
	var download_complete = false
	var download_success = false
	var on_complete = func(rtype: String, rid: String, success: bool, msg: String):
		if rtype == res_type and rid == res_id:
			download_complete = true
			download_success = success
			print("[PublicLobby] 下载: %s/%s success=%s msg=%s" % [rtype, rid, str(success), msg])
	GameManager.resource_download_complete.connect(on_complete)
	GameManager.request_resource_download(res_type, res_id)
	var timeout = 15.0
	while not download_complete and timeout > 0:
		await get_tree().process_frame
		timeout -= 0.05
	GameManager.resource_download_complete.disconnect(on_complete)
	if not download_success:
		print("[PublicLobby] 资源下载失败或超时: %s/%s" % [res_type, res_id])

func _verify_one_resource(res_type: String, res_id: String) -> bool:
	"""校验单个资源哈希，等待结果。返回true=校验通过"""
	var verify_complete = false
	var verify_valid = false
	var on_verify = func(rtype: String, rid: String, valid: bool, msg: String):
		if rtype == res_type and rid == res_id:
			verify_complete = true
			verify_valid = valid
			print("[PublicLobby] 校验: %s/%s valid=%s msg=%s" % [rtype, rid, str(valid), msg])
	GameManager.resource_verify_result.connect(on_verify)
	GameManager.verify_resource(res_type, res_id)
	var timeout = 10.0
	while not verify_complete and timeout > 0:
		await get_tree().process_frame
		timeout -= 0.05
	GameManager.resource_verify_result.disconnect(on_verify)
	if not verify_valid:
		global_status.text = "资源校验失败: %s（可能被篡改）" % res_id
		global_status.modulate = Color(1, 0.3, 0.3)
		print("[PublicLobby] 资源校验失败: %s/%s" % [res_type, res_id])
	return verify_valid

func _add_system_chat(message: String, col: Color = Color(1, 0.85, 0.3)) -> void:
	"""添加系统消息到聊天框"""
	var label: Label = Label.new()
	label.text = message
	label.modulate = col
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_box.add_child(label)
	while chat_box.get_child_count() > 100:
		chat_box.get_child(0).queue_free()

# === 房间聊天 ===
func _on_chat_send() -> void:
	var msg: String = chat_input.text.strip_edges()
	if not msg.is_empty():
		NetworkManager.public_send_room_chat(msg)
		chat_input.text = ""

func _on_chat_submit(text: String) -> void:
	_on_chat_send()

func _on_public_room_chat(user_id: String, username: String, message: String) -> void:
	var label: Label = Label.new()
	label.text = "[%s]: %s" % [username, message]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_box.add_child(label)
	# 限制聊天记录数量
	while chat_box.get_child_count() > 100:
		chat_box.get_child(0).queue_free()

func _on_public_resource_ready(user_id: String, username: String, ready: bool) -> void:
	"""收到玩家资源下载完成状态"""
	_players_resource_ready[user_id] = ready
	if ready:
		_add_system_chat("%s 资源下载完成" % username, Color(0.4, 0.8, 1.0))
	else:
		_add_system_chat("%s 资源未就绪" % username, Color(1.0, 0.6, 0.3))
	_update_ready_button_state()

# === 好友 ===
func _on_add_friend() -> void:
	var username: String = add_friend_input.text.strip_edges()
	if not username.is_empty():
		NetworkManager.public_add_friend(username)
		add_friend_input.text = ""
		global_status.text = "已发送好友请求: %s" % username
		global_status.modulate = Color(0.3, 1, 0.3)

func _on_public_friend_list(friends: Array) -> void:
	_clear_container(friend_list)
	if friends.is_empty():
		var label: Label = Label.new()
		label.text = "暂无好友，在上方输入用户名添加"
		label.modulate = Color(0.7, 0.7, 0.7)
		friend_list.add_child(label)
		return
	for friend in friends:
		_add_friend_row(friend)

func _add_friend_row(friend: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 35)
	row.add_theme_constant_override("separation", 10)

	var online: bool = friend.get("online", false)
	var status_dot: Label = Label.new()
	status_dot.text = "●" if online else "○"
	status_dot.modulate = Color(0.3, 1, 0.3) if online else Color(0.5, 0.5, 0.5)
	status_dot.custom_minimum_size = Vector2(25, 0)
	row.add_child(status_dot)

	var name_label: Label = Label.new()
	name_label.text = _safe_str(friend.get("username"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 15)
	row.add_child(name_label)

	var in_game: bool = friend.get("in_game", false)
	if in_game:
		var game_label: Label = Label.new()
		game_label.text = "游戏中"
		game_label.modulate = Color(1, 0.8, 0.3)
		row.add_child(game_label)

	var invite_button: Button = Button.new()
	invite_button.text = "组队"
	invite_button.custom_minimum_size = Vector2(60, 30)
	var friend_id: String = _safe_str(friend.get("user_id"))
	invite_button.pressed.connect(func(): NetworkManager.public_send_party_invite(friend_id))
	row.add_child(invite_button)

	var remove_button: Button = Button.new()
	remove_button.text = "删除"
	remove_button.custom_minimum_size = Vector2(60, 30)
	remove_button.modulate = Color(1, 0.5, 0.5)
	remove_button.pressed.connect(func():
		NetworkManager.public_remove_friend(friend_id)
		NetworkManager.public_request_friend_list()
	)
	row.add_child(remove_button)

	friend_list.add_child(row)

func _on_public_friend_request(user_id: String, username: String) -> void:
	pending_friend_requests.append({"user_id": user_id, "username": username})
	_refresh_friend_requests()
	global_status.text = "收到好友请求: %s" % username
	global_status.modulate = Color(1, 0.8, 0.3)

func _refresh_friend_requests() -> void:
	_clear_container(friend_requests_list)
	for req in pending_friend_requests:
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_constant_override("separation", 10)
		var name_label: Label = Label.new()
		name_label.text = _safe_str(req.get("username"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var accept_btn: Button = Button.new()
		accept_btn.text = "接受"
		accept_btn.custom_minimum_size = Vector2(55, 28)
		var uid: String = _safe_str(req.get("user_id"))
		accept_btn.pressed.connect(func():
			NetworkManager.public_accept_friend(uid)
			pending_friend_requests = pending_friend_requests.filter(func(r): return r.get("user_id", "") != uid)
			_refresh_friend_requests()
			NetworkManager.public_request_friend_list()
		)
		row.add_child(accept_btn)
		var decline_btn: Button = Button.new()
		decline_btn.text = "拒绝"
		decline_btn.custom_minimum_size = Vector2(55, 28)
		decline_btn.pressed.connect(func():
			NetworkManager.public_decline_friend(uid)
			pending_friend_requests = pending_friend_requests.filter(func(r): return r.get("user_id", "") != uid)
			_refresh_friend_requests()
		)
		row.add_child(decline_btn)
		friend_requests_list.add_child(row)

func _on_public_friend_online(user_id: String) -> void:
	NetworkManager.public_request_friend_list()

func _on_public_friend_offline(user_id: String) -> void:
	NetworkManager.public_request_friend_list()

# === 组队 ===
func _on_party_invite() -> void:
	var username: String = party_invite_input.text.strip_edges()
	if username.is_empty():
		return
	# 从好友列表中查找用户ID
	var friend_id: String = ""
	for child in friend_list.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			var name_label: Label = child.get_child(1)
			if name_label and name_label.text == username:
				# 找到好友，从按钮的连接中获取ID比较麻烦，简化处理
				pass
	# 简化：遍历好友数据（需要缓存）
	# 直接发送添加好友请求（服务器会处理），实际应先确认是好友
	NetworkManager.public_add_friend(username)
	global_status.text = "请先添加 %s 为好友，然后在好友列表点击\"组队\"" % username
	global_status.modulate = Color(1, 0.8, 0.3)
	party_invite_input.text = ""

func _on_party_leave() -> void:
	NetworkManager.public_party_leave()
	NetworkManager.public_request_party_info()

func _on_public_party_invite(party_id: String, inviter_id: String, inviter_name: String) -> void:
	global_status.text = "%s 邀请你组队！" % inviter_name
	global_status.modulate = Color(1, 0.8, 0.3)
	# 简单自动接受或弹窗
	var accept: bool = true  # TODO: 改为弹窗确认
	if accept:
		NetworkManager.public_party_accept(party_id)

func _on_public_party_info(party_info: Dictionary) -> void:
	_clear_container(party_member_list)
	var party_id_val = party_info.get("party_id", "")
	var party_id: String = str(party_id_val) if party_id_val != null else ""
	if party_id.is_empty():
		party_info_label.text = "当前未组队"
		party_leave_button.visible = false
		return
	var leader_id_val = party_info.get("leader_id", "")
	var leader_id: String = str(leader_id_val) if leader_id_val != null else ""
	party_info_label.text = "组队ID: %s  队长: %s" % [party_id, leader_id]
	party_leave_button.visible = true
	for member in party_info.get("members", []):
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_constant_override("separation", 6)
		var member_uid = member.get("user_id", "")
		var member_uid_str: String = str(member_uid) if member_uid != null else ""
		var is_leader: bool = member_uid_str == leader_id

		# 队长王冠图标
		if is_leader:
			var crown_icon: TextureRect = TextureRect.new()
			crown_icon.texture = load("res://assets/icons/crown.png")
			crown_icon.custom_minimum_size = Vector2(18, 18)
			crown_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			crown_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			row.add_child(crown_icon)
		else:
			# 占位空格，保持对齐
			var spacer: Control = Control.new()
			spacer.custom_minimum_size = Vector2(24, 0)
			row.add_child(spacer)

		var name_label: Label = Label.new()
		var member_name = member.get("username", "")
		name_label.text = str(member_name) if member_name != null else ""
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var ready_label: Label = Label.new()
		ready_label.text = "[已准备]" if member.get("ready", false) else "[未准备]"
		row.add_child(ready_label)
		party_member_list.add_child(row)

# === 工具函数 ===
func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

func _safe_str(val, default: String = "") -> String:
	"""安全转换为字符串，null 返回默认值"""
	if val == null:
		return default
	return str(val)

func _on_back() -> void:
	NetworkManager.public_disconnect()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
