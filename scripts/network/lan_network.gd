extends Node
## 局域网网络子系统 - 由 NetworkManager 门面创建为子节点
## 职责：ENet 服务器/客户端、UDP 房间发现、30Hz 战斗同步、大厅 RPC、地图同步
## 通过 nm 引用访问 NetworkManager 的公共状态与信号

var nm: Node = null  # 父级 NetworkManager（由门面在 _ready 中设置）

# === 局域网常量 ===
const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16
const TICK_RATE: int = 30
const DISCOVERY_PORT: int = 7778
const BROADCAST_INTERVAL: float = 2.0
const ROOM_TIMEOUT: float = 6.0

# === ENet 对等体 ===
var server_peer: ENetMultiplayerPeer = null
var client_peer: ENetMultiplayerPeer = null

# === 局域网房间发现（UDP广播） ===
var broadcast_peer: PacketPeerUDP = null
var broadcast_timer: float = 0.0
var current_room_info: Dictionary = {}
var scan_peer: PacketPeerUDP = null
var discovered_rooms: Dictionary = {}  # ip:port -> {info, last_seen}
var is_scanning: bool = false

# === 局域网战斗期同步（服务器权威 30Hz） ===
var lan_own_vehicle: Node = null  # 客户端：自己的载具（用于采集输入上报）
var lan_latest_inputs: Dictionary = {}  # 服务器：peer_id -> {throttle, steering, ...}
var lan_input_prev_fire: Dictionary = {}  # 服务器：peer_id -> 上一帧开火状态
var lan_fire_pending: Dictionary = {}  # 服务器：peer_id -> 本tick是否发生开火
var lan_input_send_timer: float = 0.0  # 客户端：输入上报计时

# ============================================================
#  生命周期
# ============================================================

func _process(delta: float) -> void:
	# 房间广播（服务器端）
	if broadcast_peer:
		broadcast_timer += delta
		if broadcast_timer >= BROADCAST_INTERVAL:
			broadcast_timer = 0.0
			_broadcast_room()

	# 房间扫描（客户端）
	if is_scanning:
		_process_room_scan()

	# 局域网战斗：客户端30Hz上报本地输入（不可靠）
	if nm.is_client and nm.lan_battle_active and lan_own_vehicle and is_instance_valid(lan_own_vehicle):
		lan_input_send_timer += delta
		if lan_input_send_timer >= 1.0 / TICK_RATE:
			lan_input_send_timer = 0.0
			_lan_send_input()

	if nm.mode == nm.NetworkMode.STANDALONE:
		return

	# 服务器固定tick同步
	if nm.is_server:
		nm.tick_timer += delta
		var tick_interval = 1.0 / TICK_RATE
		while nm.tick_timer >= tick_interval:
			nm.tick_timer -= tick_interval
			nm.current_tick += 1
			_server_tick()
			nm.network_tick.emit(nm.current_tick)

# ============================================================
#  ENet 服务器 / 客户端
# ============================================================

func start_server(port: int = DEFAULT_PORT) -> bool:
	"""启动服务器，端口被占用时自动尝试后续端口"""
	server_peer = ENetMultiplayerPeer.new()
	var actual_port = port
	var error = server_peer.create_server(actual_port, MAX_PLAYERS)
	var retry = 0
	while error != OK and retry < 10:
		retry += 1
		actual_port = port + retry
		server_peer = ENetMultiplayerPeer.new()
		error = server_peer.create_server(actual_port, MAX_PLAYERS)
	if error != OK:
		push_error("[NetworkManager] Failed to start server on port %d: %d" % [port, error])
		return false

	multiplayer.multiplayer_peer = server_peer
	nm.mode = nm.NetworkMode.SERVER
	nm.is_server = true
	nm.is_client = false
	nm.local_player_id = 1
	nm.players[1] = {"name": "Server", "vehicle_id": "", "team": 1}
	# 开始局域网房间广播
	var map_name = ""
	var map_data = DataLoader.get_map(GameManager.selected_map_id)
	if not map_data.is_empty():
		map_name = map_data.get("name", GameManager.selected_map_id)
	start_room_broadcast("%s的房间" % SettingsManager.get_nickname(), map_name, 1, MAX_PLAYERS, actual_port)
	print("[NetworkManager] Server started on port %d" % actual_port)
	return true

func start_client(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> bool:
	"""启动客户端并连接服务器"""
	client_peer = ENetMultiplayerPeer.new()
	var error = client_peer.create_client(address, port)
	if error != OK:
		push_error("[NetworkManager] Failed to create client: %d" % error)
		return false

	multiplayer.multiplayer_peer = client_peer
	nm.mode = nm.NetworkMode.CLIENT
	nm.is_server = false
	nm.is_client = true
	print("[NetworkManager] Client connecting to %s:%d" % [address, port])
	return true

func stop_network() -> void:
	"""停止网络，回到单机模式"""
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	nm.mode = nm.NetworkMode.STANDALONE
	nm.is_server = false
	nm.is_client = false
	nm.players.clear()
	stop_room_broadcast()
	stop_room_scan()
	# 清理局域网战斗期同步状态
	nm.lan_battle_active = false
	lan_own_vehicle = null
	nm.lan_server_vehicles.clear()
	nm.lan_remote_nodes.clear()
	lan_latest_inputs.clear()
	lan_input_prev_fire.clear()
	lan_fire_pending.clear()
	lan_input_send_timer = 0.0
	print("[NetworkManager] Network stopped, back to STANDALONE")

# ============================================================
#  局域网房间发现（UDP广播）
# ============================================================

func start_room_broadcast(room_name: String = "游戏房间", map_name: String = "", player_count: int = 1, max_players: int = 16, port: int = DEFAULT_PORT) -> void:
	"""服务器端：开始广播房间信息到局域网"""
	if broadcast_peer:
		stop_room_broadcast()
	broadcast_peer = PacketPeerUDP.new()
	broadcast_peer.set_broadcast_enabled(true)
	current_room_info = {
		"name": room_name,
		"map": map_name,
		"players": player_count,
		"max_players": max_players,
		"port": port,
	}
	broadcast_timer = 0.0
	if nm.debug_verbose:
		print("[NetworkManager] Room broadcast started: %s on port %d" % [room_name, port])

func stop_room_broadcast() -> void:
	"""停止广播"""
	if broadcast_peer:
		broadcast_peer.close()
		broadcast_peer = null
	if nm.debug_verbose:
		print("[NetworkManager] Room broadcast stopped")

func _broadcast_room() -> void:
	"""发送一次广播包"""
	if not broadcast_peer:
		return
	var data = JSON.stringify(current_room_info).to_utf8_buffer()
	broadcast_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	broadcast_peer.put_packet(data)

func start_room_scan() -> void:
	"""客户端：开始扫描局域网房间"""
	if scan_peer:
		stop_room_scan()
	scan_peer = PacketPeerUDP.new()
	var err = scan_peer.bind(DISCOVERY_PORT)
	if err != OK:
		push_error("[NetworkManager] Failed to bind discovery port %d: %d" % [DISCOVERY_PORT, err])
		scan_peer = null
		return
	discovered_rooms.clear()
	is_scanning = true
	if nm.debug_verbose:
		print("[NetworkManager] Room scan started on port %d" % DISCOVERY_PORT)

func stop_room_scan() -> void:
	"""停止扫描"""
	if scan_peer:
		scan_peer.close()
		scan_peer = null
	is_scanning = false
	discovered_rooms.clear()
	if nm.debug_verbose:
		print("[NetworkManager] Room scan stopped")

func _process_room_scan() -> void:
	"""处理接收到的广播包，清理超时房间"""
	if not scan_peer:
		return
	while scan_peer.get_available_packet_count() > 0:
		var data = scan_peer.get_packet()
		var sender_ip = scan_peer.get_packet_ip()
		var json_str = data.get_string_from_utf8()
		var parsed = JSON.parse_string(json_str)
		if typeof(parsed) == TYPE_DICTIONARY:
			var key = "%s:%d" % [sender_ip, parsed.get("port", DEFAULT_PORT)]
			parsed["ip"] = sender_ip
			discovered_rooms[key] = {"info": parsed, "last_seen": Time.get_ticks_msec() / 1000.0}
			nm.room_discovered.emit(parsed)
	# 清理超时房间
	var now = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	for key in discovered_rooms.keys():
		if now - discovered_rooms[key].last_seen > ROOM_TIMEOUT:
			to_remove.append(key)
	for key in to_remove:
		discovered_rooms.erase(key)

func get_discovered_rooms() -> Array:
	"""获取当前发现的房间列表"""
	var rooms = []
	for key in discovered_rooms.keys():
		rooms.append(discovered_rooms[key].info)
	return rooms

# ============================================================
#  战斗期同步（服务器权威 30Hz）
# ============================================================

func _server_tick() -> void:
	"""服务器每个tick同步所有载具状态"""
	if not nm.is_server or not nm.lan_battle_active:
		return
	for peer_id in nm.lan_server_vehicles.keys():
		var v = nm.lan_server_vehicles[peer_id]
		if v == null or not is_instance_valid(v) or v.is_destroyed:
			continue
		# 应用远端玩家输入（房主本机输入已在本地直接应用）
		if peer_id != 1 and lan_latest_inputs.has(peer_id):
			_lan_apply_input(v, lan_latest_inputs[peer_id], peer_id)
		elif peer_id == 1:
			# 房主自己：本地 fire() 已直接开火，这里仅采样开火标记广播炮口焰，随后清除
			var host_fired: bool = v.input_fire
			v.input_fire = false
			if host_fired:
				lan_fire_pending[peer_id] = true
		# 广播状态给所有客户端（不可靠，本tick开火标记随包下发）
		var q: Quaternion = v.global_transform.basis.get_rotation_quaternion()
		var speed: float = v.current_speed if "current_speed" in v else v.velocity.length()
		var fired: bool = lan_fire_pending.get(peer_id, false)
		lan_fire_pending[peer_id] = false
		nm.rpc("rpc_sync_vehicle_state", peer_id, v.global_position, q, v.turret_yaw, \
			v.gun_pitch, speed, v.get_health_percent(), v.is_destroyed, \
			_lan_get_float(v, "alpha"), _lan_get_float(v, "n_load", 1.0), \
			_lan_get_float(v, "delta_a"), _lan_get_float(v, "delta_e"), \
			_lan_get_float(v, "delta_r"), fired)

func _lan_apply_input(v, inp: Dictionary, peer_id: int) -> void:
	"""服务器：将远端玩家输入应用到权威载具"""
	v.input_throttle = inp.get("throttle", 0.0)
	v.input_steering = inp.get("steering", 0.0)
	v.input_turret = inp.get("turret", 0.0)
	v.input_gun = inp.get("gun", 0.0)
	if "input_pitch" in v:
		v.input_pitch = inp.get("pitch", 0.0)
	if "input_yaw" in v:
		v.input_yaw = inp.get("yaw", 0.0)
	if "target_yaw" in v:
		v.target_yaw = inp.get("target_yaw", 0.0)
	if "target_pitch" in v:
		v.target_pitch = inp.get("target_pitch", 0.0)
	if "collective" in v:
		v.collective = inp.get("collective", 0.0)
	var fire_now: bool = inp.get("fire", false)
	var prev_fire: bool = lan_input_prev_fire.get(peer_id, false)
	lan_input_prev_fire[peer_id] = fire_now
	if fire_now and not prev_fire:
		v.fire()
		lan_fire_pending[peer_id] = true

func _lan_get_float(v: Node, prop: String, default: float = 0.0) -> float:
	"""读取载具数值属性，不存在时返回默认值"""
	var val = v.get(prop)
	if val == null:
		return default
	return float(val)

func _lan_send_input() -> void:
	"""客户端：采集本地载具输入并上报服务器（30Hz）"""
	var v = lan_own_vehicle
	var ty: float = v.get("target_yaw") if v.get("target_yaw") != null else 0.0
	var tp: float = v.get("target_pitch") if v.get("target_pitch") != null else 0.0
	var coll: float = v.get("collective") if v.get("collective") != null else 0.0
	var pitch: float = v.get("input_pitch") if v.get("input_pitch") != null else 0.0
	var yaw: float = v.get("input_yaw") if v.get("input_yaw") != null else 0.0
	var fire_now: bool = v.input_fire
	v.input_fire = false
	nm.rpc_id(1, "rpc_send_input", v.input_throttle, v.input_steering, v.input_turret, \
		v.input_gun, fire_now, ty, tp, coll, pitch, yaw)

# ============================================================
#  战斗期同步 API（供门面转发调用）
# ============================================================

func lan_battle_begin_server() -> void:
	"""服务器：进入战斗期，重置权威副本与输入缓存"""
	nm.lan_battle_active = true
	nm.lan_server_vehicles.clear()
	lan_latest_inputs.clear()
	lan_input_prev_fire.clear()
	lan_fire_pending.clear()

func lan_register_server_vehicle(peer_id: int, vehicle) -> void:
	"""服务器：登记某玩家在服务器上的权威载具副本"""
	nm.lan_battle_active = true
	nm.lan_server_vehicles[peer_id] = vehicle
	if not vehicle.vehicle_destroyed.is_connected(lan_on_server_vehicle_destroyed):
		vehicle.vehicle_destroyed.connect(lan_on_server_vehicle_destroyed.bind(peer_id))

func lan_on_server_vehicle_destroyed(peer_id: int) -> void:
	"""服务器：某玩家的权威副本被击毁 → 停止同步并广播销毁"""
	if nm.lan_server_vehicles.has(peer_id):
		nm.lan_server_vehicles.erase(peer_id)
	lan_latest_inputs.erase(peer_id)
	lan_input_prev_fire.erase(peer_id)
	lan_fire_pending.erase(peer_id)
	lan_broadcast_destroy(peer_id)

func lan_battle_enter(vehicle_id: String, team: int) -> void:
	"""客户端：向服务器上报自己入战"""
	if not nm.is_client:
		return
	nm.lan_battle_active = true
	nm.rpc_id(1, "rpc_lan_battle_enter", vehicle_id, team, SettingsManager.get_nickname())

func lan_broadcast_spawn(peer_id: int, vehicle_id: String, team: int, nickname: String, position: Vector3, rot_y: float) -> void:
	"""服务器：通知所有客户端生成某远程载具"""
	nm.rpc("rpc_spawn_vehicle", peer_id, vehicle_id, team, nickname, position, rot_y)

func lan_broadcast_destroy(peer_id: int) -> void:
	"""服务器：通知所有客户端某载具被摧毁"""
	nm.rpc("rpc_destroy_vehicle", peer_id)

func lan_track_remote_node(peer_id: int, node: Node) -> void:
	"""客户端：登记远程载具节点"""
	nm.lan_remote_nodes[peer_id] = node

func lan_untrack_remote_node(peer_id: int) -> void:
	nm.lan_remote_nodes.erase(peer_id)

func lan_set_own_vehicle(node: Node) -> void:
	"""客户端：登记自己的载具（用于采集输入上报）"""
	lan_own_vehicle = node

# ============================================================
#  RPC 实现（由门面的 @rpc 方法转发调用）
# ============================================================

func on_rpc_send_input(_throttle: float, _steering: float, _turret: float, _gun: float, _fire: bool, _target_yaw: float, _target_pitch: float, _collective: float, _pitch: float, _yaw: float) -> void:
	"""客户端发送输入到服务器（30Hz 不可靠）"""
	if not nm.is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if not nm.lan_server_vehicles.has(sender_id):
		return
	lan_latest_inputs[sender_id] = {
		"throttle": _throttle, "steering": _steering, "turret": _turret,
		"gun": _gun, "fire": _fire, "target_yaw": _target_yaw,
		"target_pitch": _target_pitch, "collective": _collective,
		"pitch": _pitch, "yaw": _yaw,
	}

func on_rpc_lan_battle_enter(vehicle_id: String, team: int, nickname: String) -> void:
	"""服务器：接收客户端入战上报"""
	if not nm.is_server:
		return
	var pid = multiplayer.get_remote_sender_id()
	nm.lan_player_entered_battle.emit(pid, vehicle_id, team, nickname)

func on_rpc_sync_vehicle_state(_peer_id: int, _position: Vector3, _quaternion: Quaternion, _turret_yaw: float, _gun_pitch: float, _speed: float, _health: float, _destroyed: bool, _alpha: float, _n_load: float, _delta_a: float, _delta_e: float, _delta_r: float, _fired: bool) -> void:
	"""服务器同步载具状态到客户端（30Hz 不可靠）"""
	if nm.is_server or not nm.lan_battle_active:
		return
	var node = nm.lan_remote_nodes.get(_peer_id)
	if node == null or not is_instance_valid(node):
		return
	node.apply_network_state(_position, _quaternion, _turret_yaw, _gun_pitch, _speed, _health, _destroyed, _alpha, _n_load, _delta_a, _delta_e, _delta_r, _fired)

func on_rpc_spawn_vehicle(_peer_id: int, _vehicle_id: String, _team: int, _nickname: String, _position: Vector3, _rot_y: float) -> void:
	"""服务器通知客户端生成远程载具"""
	if nm.is_server:
		return
	nm.lan_vehicle_spawned.emit(_peer_id, _vehicle_id, _team, _nickname, _position, _rot_y)

func on_rpc_destroy_vehicle(_peer_id: int) -> void:
	"""服务器通知客户端某载具被摧毁"""
	if nm.is_server:
		return
	nm.lan_vehicle_destroyed.emit(_peer_id)

func on_rpc_chat_message(player_name: String, message: String) -> void:
	"""聊天消息"""
	print("[Chat] %s: %s" % [player_name, message])

# ============================================================
#  局域网房间大厅 RPC
# ============================================================

func lan_register_player(name: String, team: int) -> void:
	"""客户端：注册玩家信息到服务器"""
	if nm.is_client:
		nm.rpc_id(1, "rpc_lan_register", name, team)

func on_rpc_lan_register(name: String, team: int) -> void:
	"""服务器：注册玩家"""
	if not nm.is_server:
		return
	var pid = multiplayer.get_remote_sender_id()
	nm.lan_room_players[pid] = {"name": name, "team": team, "ready": false}
	print("[LAN Lobby] 玩家加入: %s (id:%d 队伍:%d)" % [name, pid, team])
	_lan_broadcast_room()

func lan_request_team(team: int) -> void:
	"""客户端：请求切换队伍"""
	if nm.is_client:
		nm.rpc_id(1, "rpc_lan_team", team)

func on_rpc_lan_team(team: int) -> void:
	"""服务器：切换玩家队伍"""
	if not nm.is_server:
		return
	var pid = multiplayer.get_remote_sender_id()
	if pid in nm.lan_room_players:
		nm.lan_room_players[pid]["team"] = team
		nm.lan_room_players[pid]["ready"] = false
		_lan_broadcast_room()

func lan_request_ready(ready: bool) -> void:
	"""客户端：请求准备/取消准备"""
	if nm.is_client:
		nm.rpc_id(1, "rpc_lan_ready", ready)

func on_rpc_lan_ready(ready: bool) -> void:
	"""服务器：设置玩家准备状态"""
	if not nm.is_server:
		return
	var pid = multiplayer.get_remote_sender_id()
	if pid in nm.lan_room_players:
		nm.lan_room_players[pid]["ready"] = ready
		_lan_broadcast_room()

func lan_start_game() -> void:
	"""房主：开始游戏"""
	if nm.is_server:
		if 1 not in nm.lan_room_players:
			nm.lan_room_players[1] = {"name": SettingsManager.get_nickname(), "team": GameManager.public_player_team, "ready": true}
		nm.rpc("rpc_lan_start")
		nm.lan_game_start.emit()

func on_rpc_lan_start() -> void:
	"""所有客户端：收到开始游戏通知"""
	nm.lan_game_start.emit()

func on_rpc_lan_kill_feed(killer_name: String, victim_name: String, victim_team: int, killer_team: int) -> void:
	"""局域网击毁播报（所有客户端接收）"""
	nm.lan_kill_feed.emit(killer_name, victim_name, victim_team, killer_team)

func _lan_broadcast_room() -> void:
	"""服务器：广播房间状态给所有玩家"""
	if not nm.is_server:
		return
	if 1 not in nm.lan_room_players:
		nm.lan_room_players[1] = {"name": SettingsManager.get_nickname(), "team": GameManager.public_player_team, "ready": false}
	var players_arr = []
	for pid in nm.lan_room_players.keys():
		var p = nm.lan_room_players[pid].duplicate()
		p["id"] = pid
		players_arr.append(p)
	nm.rpc("rpc_lan_sync", players_arr)

func on_rpc_lan_sync(players_arr: Array) -> void:
	"""客户端：收到房间状态同步"""
	nm.lan_room_players.clear()
	for p in players_arr:
		nm.lan_room_players[p["id"]] = {"name": p["name"], "team": p["team"], "ready": p["ready"]}
	nm.lan_room_synced.emit(players_arr)

# ============================================================
#  地图同步
# ============================================================

func request_map() -> void:
	"""客户端调用：向服务器请求当前地图ID"""
	if not nm.is_client:
		if nm.debug_verbose:
			print("[NetworkManager] [客户端] request_map 被调用但 is_client=false，跳过")
		return
	if nm.debug_verbose:
		print("[NetworkManager] [客户端] 发送地图请求 rpc_request_map (本机 peer=%d)" % multiplayer.get_unique_id())
	nm.rpc_id(1, "rpc_request_map")

func on_rpc_request_map() -> void:
	"""服务器端RPC：收到客户端的地图请求"""
	if nm.debug_verbose:
		print("[NetworkManager] [服务器] 收到 rpc_request_map, is_server=%s" % nm.is_server)
	if not nm.is_server:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var map_id = GameManager.selected_map_id
	if nm.debug_verbose:
		print("[NetworkManager] [服务器] 地图请求来自 peer %d, map_id='%s', air_boundary=%.0f" % [sender_id, map_id, GameManager.air_boundary_size])
	if nm.debug_verbose:
		print("[NetworkManager] Sending map '%s' to client %d (air_boundary=%.0f)" % [map_id, sender_id, GameManager.air_boundary_size])
	nm.rpc_id(sender_id, "rpc_receive_map", map_id, GameManager.air_boundary_size)

func on_rpc_receive_map(map_id: String, air_boundary_size: float = 0.0) -> void:
	"""客户端RPC：收到服务器同步的地图ID与飞机边界大小"""
	if nm.debug_verbose:
		print("[NetworkManager] [客户端] 收到 rpc_receive_map, map_id='%s', air_boundary=%.0f" % [map_id, air_boundary_size])
	print("[NetworkManager] Received map from server: %s (air_boundary=%.0f)" % [map_id, air_boundary_size])
	GameManager.selected_map_id = map_id
	if air_boundary_size > 0.0:
		GameManager.air_boundary_size = air_boundary_size
	nm.map_received.emit(map_id)

# ============================================================
#  多人回调（由门面连接 multiplayer 信号后转发）
# ============================================================

func on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % peer_id)
	if nm.is_server:
		nm.players[peer_id] = {"name": "Player_%d" % peer_id, "vehicle_id": ""}
		nm.player_joined.emit(peer_id)
		current_room_info["players"] = nm.players.size()
		_broadcast_room()

func on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % peer_id)
	nm.players.erase(peer_id)
	nm.player_left.emit(peer_id)
	if nm.is_server:
		current_room_info["players"] = nm.players.size()
		_broadcast_room()
		# 战斗期：清理该玩家的权威副本并广播销毁
		lan_latest_inputs.erase(peer_id)
		lan_input_prev_fire.erase(peer_id)
		lan_fire_pending.erase(peer_id)
		if nm.lan_server_vehicles.has(peer_id):
			var v = nm.lan_server_vehicles[peer_id]
			nm.lan_server_vehicles.erase(peer_id)
			if v and is_instance_valid(v):
				v.queue_free()
			lan_broadcast_destroy(peer_id)
	else:
		# 客户端：清理该玩家的远程载具映射
		nm.lan_remote_nodes.erase(peer_id)
		nm.lan_peer_left_battle.emit(peer_id)

func on_connected_to_server() -> void:
	nm.local_player_id = multiplayer.get_unique_id()
	print("[NetworkManager] Connected to server as player %d" % nm.local_player_id)
	nm.connection_succeeded.emit()

func on_connection_failed() -> void:
	print("[NetworkManager] Connection failed")
	nm.connection_failed.emit()
	nm.mode = nm.NetworkMode.STANDALONE

func on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected")
	nm.server_disconnected.emit()
	nm.mode = nm.NetworkMode.STANDALONE
