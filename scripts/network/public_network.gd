extends Node
## 公网网络子系统 - 由 NetworkManager 门面创建为子节点
## 职责：TCP 大厅（账号/好友/组队/房间）、自定义资源同步、UDP 游戏连接（可靠UDP协议）
## 通过 nm 引用访问 NetworkManager 的公共状态与信号

var nm: Node = null  # 父级 NetworkManager（由门面在 _ready 中设置）

# === 公网服务器常量 ===
const PUBLIC_SERVER_HOST: String = "game.thefeishu.top"
const PUBLIC_SERVER_PORT: int = 8765
const PUBLIC_RECONNECT_INTERVAL: float = 5.0

# === TCP 大厅内部状态 ===
var public_tcp: StreamPeerTCP = null
var public_connected_flag: bool = false
var public_recv_buffer: PackedByteArray = PackedByteArray()
var public_heartbeat_timer: float = 0.0
var public_req_counter: int = 0

# === UDP 游戏连接内部状态 ===
var game_udp: PacketPeerUDP = null
var game_server_host: String = ""
var game_server_port: int = 0
var game_room_id: String = ""
var game_player_id: String = ""
var game_next_seq: int = 0
var game_reliable_pending: Dictionary = {}  # seq -> {packet, time, retries}
var game_reliable_recv: Dictionary = {}  # 去重：player_id -> last_seq
var game_input_send_timer: float = 0.0
var game_state_send_timer: float = 0.0

const GAME_INPUT_RATE: float = 30.0
const GAME_STATE_RATE: float = 15.0
const GAME_RELIABLE_TIMEOUT: float = 1.0
const GAME_MAX_RETRIES: int = 5

# ============================================================
#  生命周期
# ============================================================

func _process(delta: float) -> void:
	# TCP 大厅轮询
	_public_poll()
	if public_connected_flag and nm.public_authenticated:
		public_heartbeat_timer += delta
		if public_heartbeat_timer >= 25.0:
			public_heartbeat_timer = 0.0
			_public_send("heartbeat", {})

	# UDP 游戏轮询
	if nm.game_connected_flag:
		_game_poll()
		_game_retransmit_check(delta)

# ============================================================
#  TCP 大厅连接
# ============================================================

func get_public_server_host() -> String:
	if SettingsManager and SettingsManager.settings.has("network"):
		return SettingsManager.settings.network.get("public_server_host", PUBLIC_SERVER_HOST)
	return PUBLIC_SERVER_HOST

func get_public_server_port() -> int:
	if SettingsManager and SettingsManager.settings.has("network"):
		return SettingsManager.settings.network.get("public_server_port", PUBLIC_SERVER_PORT)
	return PUBLIC_SERVER_PORT

func public_connect(host: String = "", port: int = -1) -> void:
	"""连接公网大厅服务器，不传参数则使用设置中的地址"""
	if host == "":
		host = get_public_server_host()
	if port < 0:
		port = get_public_server_port()
	if public_tcp:
		public_disconnect()
	nm.public_current_host = host
	nm.public_current_port = port
	public_tcp = StreamPeerTCP.new()
	public_tcp.connect_to_host(host, port)
	print("[PublicNet] 正在连接 %s:%d ..." % [host, port])

func public_disconnect() -> void:
	"""断开公网服务器连接"""
	if public_tcp:
		public_tcp.disconnect_from_host()
		public_tcp = null
	public_connected_flag = false
	nm.public_authenticated = false
	nm.public_user_id = ""
	nm.public_username = ""
	public_recv_buffer = PackedByteArray()
	nm.public_disconnected.emit()
	print("[PublicNet] 已断开公网服务器")

func public_is_connected() -> bool:
	return public_connected_flag and nm.public_authenticated

func public_is_tcp_connected() -> bool:
	return public_connected_flag

func _public_send(msg_type: String, data: Dictionary = {}) -> void:
	"""发送消息到公网服务器"""
	if not public_tcp or not public_connected_flag:
		return
	var msg: Dictionary = {"type": msg_type, "data": data}
	var json_str: String = JSON.stringify(msg) + "\n"
	public_tcp.put_data(json_str.to_utf8_buffer())

func _public_poll() -> void:
	"""轮询接收服务器消息（在 _process 中调用）"""
	if not public_tcp:
		return
	public_tcp.poll()
	var status: int = public_tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not public_connected_flag:
			public_connected_flag = true
			nm.public_connected.emit()
			print("[PublicNet] 已连接公网服务器")
		var available: int = public_tcp.get_available_bytes()
		if available > 0:
			var data: Array = public_tcp.get_data(available)
			if data[0] == OK:
				public_recv_buffer.append_array(data[1])
				while true:
					var newline_pos = -1
					for i in range(public_recv_buffer.size()):
						if public_recv_buffer[i] == 0x0A:
							newline_pos = i
							break
					if newline_pos == -1:
						break
					var line_bytes: PackedByteArray = public_recv_buffer.slice(0, newline_pos)
					var line: String = line_bytes.get_string_from_utf8()
					public_recv_buffer = public_recv_buffer.slice(newline_pos + 1)
					line = line.strip_edges()
					if line != "":
						_public_dispatch(line)
	elif status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		if public_connected_flag:
			print("[PublicNet] 连接断开")
			public_connected_flag = false
			nm.public_authenticated = false
			nm.public_disconnected.emit()

func _public_dispatch(json_str: String) -> void:
	"""分发服务器消息"""
	var json: JSON = JSON.new()
	var result: int = json.parse(json_str)
	if result != OK:
		print("[PublicNet] JSON解析失败: %s" % json_str)
		return
	var msg: Dictionary = json.data
	var msg_type: String = msg.get("type", "")
	var data: Dictionary = msg.get("data", {})
	match msg_type:
		"auth_result":
			var success: bool = data.get("success", false)
			nm.public_authenticated = success
			if success:
				nm.public_user_id = data.get("user_id", "")
				nm.public_username = data.get("username", "")
			nm.public_login_result.emit(success, data.get("message", ""), data)
		"auth_reset_result":
			nm.public_reset_result.emit(data.get("success", false), data.get("message", ""))
		"auth_send_code_result":
			nm.public_send_code_result.emit(data.get("success", false), data.get("message", ""))
		"auth_delete_result":
			nm.public_delete_result.emit(data.get("success", false), data.get("message", ""))
		"room_list_result":
			nm.public_room_list.emit(data.get("rooms", []))
		"room_info":
			nm.public_room_info.emit(data)
		"room_create_result":
			nm.public_room_create_result.emit(data.get("success", false), data.get("message", ""), data.get("room_id", ""))
		"room_player_joined":
			nm.public_room_player_joined.emit(data.get("user_id", ""), data.get("username", ""))
		"room_player_left":
			nm.public_room_player_left.emit(data.get("user_id", ""), data.get("username", ""))
		"room_chat_message":
			nm.public_room_chat.emit(data.get("user_id", ""), data.get("username", ""), data.get("message", ""))
		"resource_ready_broadcast":
			nm.public_resource_ready.emit(data.get("user_id", ""), data.get("username", ""), data.get("ready", false))
		"game_start_info":
			nm.public_game_start.emit(data)
		"friend_list_result":
			nm.public_friend_list.emit(data.get("friends", []))
		"friend_request":
			nm.public_friend_request.emit(data.get("user_id", ""), data.get("username", ""))
		"friend_online":
			nm.public_friend_online.emit(data.get("user_id", ""))
		"friend_offline":
			nm.public_friend_offline.emit(data.get("user_id", ""))
		"party_invite_received":
			nm.public_party_invite.emit(data.get("party_id", ""), data.get("inviter_id", ""), data.get("inviter_name", ""))
		"party_info_result":
			nm.public_party_info.emit(data)
		"resource_check_result":
			nm.public_resource_check.emit(data)
		"resource_download_data":
			nm.public_resource_download.emit(data)
		"resource_upload_result":
			nm.public_resource_upload_result.emit(data.get("success", false), data.get("message", ""), data.get("hash", ""))
		"resource_verify_result":
			nm.public_resource_verify_result.emit(data)
		"error":
			nm.public_error.emit(data.get("code", 0), data.get("message", ""))
		_:
			print("[PublicNet] 未处理的消息类型: %s" % msg_type)

# ============================================================
#  公网服务器 API
# ============================================================

func public_register(username: String, password: String, email: String = "", code: String = "") -> void:
	_public_send("auth_register", {"username": username, "password": password, "email": email, "code": code})

func public_login(username: String, password: String) -> void:
	_public_send("auth_login", {"username": username, "password": password})

func public_reset_password(username: String, email: String, code: String, new_password: String) -> void:
	_public_send("auth_reset_password", {"username": username, "email": email, "code": code, "new_password": new_password})

func public_send_code(email: String, username: String, action: String) -> void:
	_public_send("auth_send_code", {"email": email, "username": username, "action": action})

func public_delete_account(password: String) -> void:
	_public_send("auth_delete_account", {"password": password})

func public_logout() -> void:
	_public_send("auth_logout", {})
	public_disconnect()

func public_request_room_list() -> void:
	_public_send("room_list", {})

func public_create_room(name: String, map_id: String, max_players: int, password: String = "", ai_config: Dictionary = {}) -> void:
	_public_send("room_create", {
		"name": name, "map_id": map_id,
		"max_players": max_players, "password": password,
		"ai_config": ai_config
	})

func public_join_room(room_id: String, password: String = "") -> void:
	_public_send("room_join", {"room_id": room_id, "password": password})

func public_leave_room() -> void:
	_public_send("room_leave", {})

func public_start_game() -> void:
	_public_send("room_start", {})

func public_send_room_chat(message: String) -> void:
	_public_send("room_chat", {"message": message})

func public_set_ready(ready: bool) -> void:
	_public_send("room_ready", {"ready": ready})

func public_set_team(team: int) -> void:
	_public_send("room_team", {"team": team})

func public_set_vehicle(vehicle_id: String) -> void:
	_public_send("room_vehicle", {"vehicle_id": vehicle_id})

func public_send_resource_ready(ready: bool) -> void:
	_public_send("resource_ready", {"ready": ready})

func public_request_friend_list() -> void:
	_public_send("friend_list", {})

func public_add_friend(username: String) -> void:
	_public_send("friend_add", {"username": username})

func public_accept_friend(user_id: String) -> void:
	_public_send("friend_accept", {"user_id": user_id})

func public_decline_friend(user_id: String) -> void:
	_public_send("friend_decline", {"user_id": user_id})

func public_remove_friend(user_id: String) -> void:
	_public_send("friend_remove", {"user_id": user_id})

func public_request_friend_requests() -> void:
	_public_send("friend_requests", {})

func public_send_party_invite(user_id: String) -> void:
	_public_send("party_invite", {"user_id": user_id})

func public_party_accept(party_id: String) -> void:
	_public_send("party_accept", {"party_id": party_id})

func public_party_decline(party_id: String) -> void:
	_public_send("party_decline", {"party_id": party_id})

func public_party_leave() -> void:
	_public_send("party_leave", {})

func public_request_party_info() -> void:
	_public_send("party_info", {})

# ============================================================
#  自定义资源同步（载具/地图上传下载）
# ============================================================

func public_check_resource(resource_type: String, resource_id: String) -> void:
	_public_send("resource_check", {"type": resource_type, "id": resource_id})

func public_upload_resource(resource_type: String, resource_id: String, resource_data: Dictionary, resource_hash: String = "") -> void:
	_public_send("resource_upload", {
		"type": resource_type,
		"id": resource_id,
		"data": resource_data,
		"hash": resource_hash
	})

func public_download_resource(resource_type: String, resource_id: String) -> void:
	_public_send("resource_download", {"type": resource_type, "id": resource_id})

func public_verify_resource(resource_type: String, resource_id: String, resource_hash: String) -> void:
	_public_send("resource_verify", {
		"type": resource_type,
		"id": resource_id,
		"hash": resource_hash
	})

# ============================================================
#  公网游戏UDP连接（状态同步）
#  自定义可靠UDP协议，与Python game_server.py通信
#  FLAG: 0=不可靠, 1=可靠, 2=ACK
# ============================================================

func game_connect(host: String, port: int, room_id: String, player_id: String, username: String, team: int, vehicle_id: String) -> void:
	"""连接UDP游戏服务器"""
	if game_udp:
		game_udp.close()
	game_udp = PacketPeerUDP.new()
	var err = game_udp.bind(0)
	if err != OK:
		print("[GameNet] UDP绑定失败: %d" % err)
		return
	game_server_host = host
	game_server_port = port
	game_room_id = room_id
	game_player_id = player_id
	nm.game_connected_flag = true
	print("[GameNet] UDP连接 %s:%d 房间:%s" % [host, port, room_id])
	_game_send_reliable({
		"type": "game_join",
		"room_id": room_id,
		"player_id": player_id,
		"username": username,
		"team": team,
		"vehicle_id": vehicle_id,
		"map_id": GameManager.selected_map_id,
	})
	nm.game_connected.emit()

func game_disconnect() -> void:
	if game_udp and nm.game_connected_flag:
		_game_send_reliable({
			"type": "game_leave",
			"room_id": game_room_id,
			"player_id": game_player_id,
		})
	if game_udp:
		game_udp.close()
		game_udp = null
	nm.game_connected_flag = false
	game_reliable_pending.clear()
	game_reliable_recv.clear()
	nm.game_disconnected.emit()
	print("[GameNet] UDP断开")

func game_send_input(throttle: float, steering: float, turret: float, gun: float, fire: bool) -> void:
	"""发送玩家输入（不可靠，30Hz）"""
	if not nm.game_connected_flag or not game_udp:
		return
	_game_send_unreliable({
		"type": "game_input",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"throttle": throttle,
		"steering": steering,
		"turret": turret,
		"gun": gun,
		"fire": fire,
	})

func game_send_state(position: Vector3, rotation: Vector3, turret_yaw: float, gun_pitch: float, health: float, velocity: Vector3) -> void:
	"""上报自己的载具状态（不可靠，15Hz）"""
	if not nm.game_connected_flag or not game_udp:
		return
	_game_send_unreliable({
		"type": "game_state",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"position": [position.x, position.y, position.z],
		"rotation": [rotation.x, rotation.y, rotation.z],
		"turret_yaw": turret_yaw,
		"gun_pitch": gun_pitch,
		"health": health,
		"velocity": [velocity.x, velocity.y, velocity.z],
	})

func game_send_ai_state(ai_states: Array) -> void:
	"""房主上报AI状态（不可靠，10Hz）"""
	if not nm.game_connected_flag or not game_udp:
		return
	_game_send_unreliable({
		"type": "game_ai_state",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"ai_states": ai_states,
	})

func game_send_fire(projectile_data: Dictionary) -> void:
	"""开火事件（可靠）"""
	var msg = {"type": "game_fire", "room_id": game_room_id, "player_id": game_player_id}
	msg.merge(projectile_data, true)
	_game_send_reliable(msg)

func game_send_hit(hit_data: Dictionary) -> void:
	"""命中事件（可靠）"""
	var msg = {"type": "game_hit", "room_id": game_room_id, "player_id": game_player_id}
	msg.merge(hit_data, true)
	_game_send_reliable(msg)

func game_send_destroy(destroy_data: Dictionary) -> void:
	"""击毁事件（可靠）"""
	var msg = {"type": "game_destroy", "room_id": game_room_id, "player_id": game_player_id}
	msg.merge(destroy_data, true)
	_game_send_reliable(msg)

func game_send_foliage_destroy(center: Vector3, radius: float) -> void:
	"""植被破坏同步（可靠）"""
	_game_send_reliable({
		"type": "game_foliage_destroy",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"center": [center.x, center.y, center.z],
		"radius": radius,
	})

func game_send_chat(message: String) -> void:
	"""局内聊天（可靠）"""
	_game_send_reliable({
		"type": "game_chat",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"username": nm.public_username,
		"message": message,
	})

func game_send_skill(skill_type: String, target_position: Vector3) -> void:
	"""技能释放（火炮打击/烟幕遮蔽）（可靠）"""
	_game_send_reliable({
		"type": "game_skill",
		"room_id": game_room_id,
		"player_id": game_player_id,
		"skill_type": skill_type,
		"target_position": [target_position.x, target_position.y, target_position.z],
	})

# ============================================================
#  可靠 UDP 协议内部实现
# ============================================================

func _game_send_unreliable(msg: Dictionary) -> void:
	if not game_udp:
		return
	var json_str = JSON.stringify(msg)
	var packet = PackedByteArray([0]) + json_str.to_utf8_buffer()
	_udp_send(packet)

func _game_send_reliable(msg: Dictionary) -> void:
	if not game_udp:
		return
	msg["seq"] = game_next_seq
	game_next_seq += 1
	var json_str = JSON.stringify(msg)
	var packet = PackedByteArray([1]) + json_str.to_utf8_buffer()
	game_reliable_pending[msg["seq"]] = {"packet": packet, "time": Time.get_ticks_msec() / 1000.0, "retries": 0}
	_udp_send(packet)

func _game_send_ack(seq: int) -> void:
	if not game_udp:
		return
	var packet = PackedByteArray([2])
	packet.append((seq >> 24) & 0xFF)
	packet.append((seq >> 16) & 0xFF)
	packet.append((seq >> 8) & 0xFF)
	packet.append(seq & 0xFF)
	_udp_send(packet)

func _udp_send(packet: PackedByteArray) -> void:
	game_udp.set_dest_address(game_server_host, game_server_port)
	game_udp.put_packet(packet)

func _game_poll() -> void:
	"""处理收到的UDP包"""
	if not game_udp or not nm.game_connected_flag:
		return
	while game_udp.get_available_packet_count() > 0:
		var packet = game_udp.get_packet()
		if packet.size() < 1:
			continue
		var flag = packet[0]
		var payload = packet.slice(1)
		if flag == 2:  # ACK
			if payload.size() >= 4:
				var seq = (payload[0] << 24) | (payload[1] << 16) | (payload[2] << 8) | payload[3]
				game_reliable_pending.erase(seq)
			continue
		var json_str = payload.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(json_str) != OK:
			continue
		var msg = json.data
		var msg_type = msg.get("type", "")
		if flag == 1:  # 可靠消息：发送ACK
			var seq = msg.get("seq", 0)
			_game_send_ack(seq)
		match msg_type:
			"game_state":
				nm.game_state_received.emit(msg)
			"game_input":
				nm.game_remote_input.emit(msg.get("player_id", ""), msg)
			"game_player_joined":
				nm.game_player_joined.emit(msg)
			"game_player_left":
				nm.game_player_left.emit(msg.get("player_id", ""))
			"game_fire":
				nm.game_fire_event.emit(msg)
			"game_hit":
				nm.game_hit_event.emit(msg)
			"game_destroy":
				nm.game_destroy_event.emit(msg)
			"game_chat":
				nm.game_chat_message.emit(msg)
			"game_skill":
				nm.game_skill_event.emit(msg)
			"game_foliage_destroy":
				nm.game_foliage_destroy.emit(msg)

func _game_retransmit_check(delta: float) -> void:
	"""可靠消息重传检查"""
	var now = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	for seq in game_reliable_pending.keys():
		var entry = game_reliable_pending[seq]
		if now - entry.time > GAME_RELIABLE_TIMEOUT:
			if entry.retries >= GAME_MAX_RETRIES:
				to_remove.append(seq)
			else:
				_udp_send(entry.packet)
				entry.time = now
				entry.retries += 1
	for seq in to_remove:
		game_reliable_pending.erase(seq)

# ============================================================
#  旧版公网占位接口（保留向后兼容）
# ============================================================

func connect_public_server(server_address: String, server_port: int = 7777) -> bool:
	"""公网联机：连接公网中转服务器（已弃用，改用 public_connect）"""
	push_warning("[NetworkManager] 公网联机功能请使用 public_connect()")
	return false

func create_public_room(room_name: String = "") -> bool:
	"""公网联机：在公网服务器创建房间（已弃用，改用 public_create_room）"""
	push_warning("[NetworkManager] 公网联机功能请使用 public_create_room()")
	return false

func join_public_room(room_id: String) -> bool:
	"""公网联机：加入公网服务器上的房间（已弃用，改用 public_join_room）"""
	push_warning("[NetworkManager] 公网联机功能请使用 public_join_room()")
	return false
