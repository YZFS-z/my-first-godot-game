extends Node
## 网络管理器 - 全局单例（门面 / Facade）
##
## 职责拆分：
##   局域网逻辑 → scripts/network/lan_network.gd（子节点 LanNetwork，引用 .lan）
##   公网逻辑   → scripts/network/public_network.gd（子节点 PublicNetwork，引用 .public_net）
##
## 本文件保留：所有信号定义、公共状态、@rpc 方法（Godot 多人 RPC 按节点路径路由，必须在此节点）、
## 以及对外部保持兼容的薄转发方法。实际实现均在子节点中。

# ============================================================
#  信号（统一在此定义，子节点通过 nm 引用发射）
# ============================================================

# ── 通用连接信号 ──
signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal player_joined(player_id: int)
signal player_left(player_id: int)
signal network_tick(tick: int)
signal map_received(map_id: String)

# ── 局域网信号 ──
signal room_discovered(room_info: Dictionary)
signal lan_room_synced(players: Array)
signal lan_game_start()
signal lan_kill_feed(killer_name: String, victim_name: String, victim_team: int, killer_team: int)
signal lan_battle_started()
signal lan_player_entered_battle(peer_id: int, vehicle_id: String, team: int, nickname: String)
signal lan_vehicle_spawned(peer_id: int, vehicle_id: String, team: int, nickname: String, position: Vector3, rot_y: float)
signal lan_vehicle_destroyed(peer_id: int)
signal lan_peer_left_battle(peer_id: int)

# ── 公网大厅信号 ──
signal public_connected()
signal public_disconnected()
signal public_login_result(success: bool, message: String, user_data: Dictionary)
signal public_reset_result(success: bool, message: String)
signal public_send_code_result(success: bool, message: String)
signal public_delete_result(success: bool, message: String)
signal public_room_list(rooms: Array)
signal public_room_info(room_info: Dictionary)
signal public_room_chat(user_id: String, username: String, message: String)
signal public_resource_ready(user_id: String, username: String, ready: bool)
signal public_room_create_result(success: bool, message: String, room_id: String)
signal public_room_player_joined(user_id: String, username: String)
signal public_room_player_left(user_id: String, username: String)
signal public_game_start(game_info: Dictionary)
signal public_friend_list(friends: Array)
signal public_friend_request(user_id: String, username: String)
signal public_friend_online(user_id: String)
signal public_friend_offline(user_id: String)
signal public_party_invite(party_id: String, inviter_id: String, inviter_name: String)
signal public_resource_check(result: Dictionary)
signal public_resource_download(data: Dictionary)
signal public_resource_upload_result(success: bool, message: String, hash: String)
signal public_resource_verify_result(result: Dictionary)
signal public_party_info(party_info: Dictionary)
signal public_error(code: int, message: String)

# ── 公网游戏UDP信号 ──
signal game_connected()
signal game_disconnected()
signal game_state_received(state: Dictionary)
signal game_player_joined(player_data: Dictionary)
signal game_player_left(player_id: String)
signal game_remote_input(player_id: String, input_data: Dictionary)
signal game_fire_event(fire_data: Dictionary)
signal game_hit_event(hit_data: Dictionary)
signal game_destroy_event(destroy_data: Dictionary)
signal game_chat_message(chat_data: Dictionary)
signal game_skill_event(skill_data: Dictionary)
signal game_foliage_destroy(foliage_data: Dictionary)

# ============================================================
#  常量与枚举
# ============================================================

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16
const TICK_RATE: int = 30

enum NetworkMode {
	STANDALONE,  # 单机模式
	SERVER,      # 服务器端（监听）
	CLIENT       # 客户端（连接）
}

# ============================================================
#  公共状态（子节点通过 nm 引用读写）
# ============================================================

## 详细调试输出开关（默认关闭，需要排查网络问题时设为 true）
var debug_verbose: bool = false

var mode: NetworkMode = NetworkMode.STANDALONE
var is_server: bool = false
var is_client: bool = false
var local_player_id: int = 1
var players: Dictionary = {}
var current_tick: int = 0
var tick_timer: float = 0.0

# 局域网共享状态（外部直接访问）
var lan_battle_active: bool = false
var lan_room_players: Dictionary = {}
var lan_server_vehicles: Dictionary = {}
var lan_remote_nodes: Dictionary = {}

# 公网共享状态（外部直接访问）
var public_user_id: String = ""
var public_username: String = ""
var public_authenticated: bool = false
var public_current_host: String = ""
var public_current_port: int = 0
var game_connected_flag: bool = false

# ============================================================
#  子管理器
# ============================================================

var lan: Node = null          # LanNetwork 实例
var public_net: Node = null   # PublicNetwork 实例

# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# 连接 Godot 多人全局信号（回调转发给 lan 子系统）
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# 创建子系统
	lan = load("res://scripts/network/lan_network.gd").new()
	lan.nm = self
	add_child(lan)

	public_net = load("res://scripts/network/public_network.gd").new()
	public_net.nm = self
	add_child(public_net)

	print("[NetworkManager] Initialized in STANDALONE mode (LAN + Public sub-systems ready)")

func _process(delta: float) -> void:
	# 子系统各自的 _process 已由节点树自动调用；
	# 此处保留空实现以备将来需要门面级协调。
	pass

# ============================================================
#  通用 / 局域网方法（转发到 lan）
# ============================================================

func start_server(port: int = DEFAULT_PORT) -> bool:
	return lan.start_server(port)

func start_client(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> bool:
	return lan.start_client(address, port)

func stop_network() -> void:
	lan.stop_network()

func get_mode_string() -> String:
	match mode:
		NetworkMode.STANDALONE: return "STANDALONE"
		NetworkMode.SERVER: return "SERVER"
		NetworkMode.CLIENT: return "CLIENT"
	return "UNKNOWN"

func request_map() -> void:
	lan.request_map()

func get_discovered_rooms() -> Array:
	return lan.get_discovered_rooms()

# ── 房间发现 ──

func start_room_broadcast(room_name: String = "游戏房间", map_name: String = "", player_count: int = 1, max_players: int = 16, port: int = DEFAULT_PORT) -> void:
	lan.start_room_broadcast(room_name, map_name, player_count, max_players, port)

func stop_room_broadcast() -> void:
	lan.stop_room_broadcast()

func start_room_scan() -> void:
	lan.start_room_scan()

func stop_room_scan() -> void:
	lan.stop_room_scan()

# ── 战斗期同步 API ──

func lan_battle_begin_server() -> void:
	lan.lan_battle_begin_server()

func lan_register_server_vehicle(peer_id: int, vehicle) -> void:
	lan.lan_register_server_vehicle(peer_id, vehicle)

func lan_battle_enter(vehicle_id: String, team: int) -> void:
	lan.lan_battle_enter(vehicle_id, team)

func lan_broadcast_spawn(peer_id: int, vehicle_id: String, team: int, nickname: String, position: Vector3, rot_y: float) -> void:
	lan.lan_broadcast_spawn(peer_id, vehicle_id, team, nickname, position, rot_y)

func lan_broadcast_destroy(peer_id: int) -> void:
	lan.lan_broadcast_destroy(peer_id)

func lan_track_remote_node(peer_id: int, node: Node) -> void:
	lan.lan_track_remote_node(peer_id, node)

func lan_untrack_remote_node(peer_id: int) -> void:
	lan.lan_untrack_remote_node(peer_id)

func lan_set_own_vehicle(node: Node) -> void:
	lan.lan_set_own_vehicle(node)

# ── 局域网大厅 API ──

func lan_register_player(name: String, team: int) -> void:
	lan.lan_register_player(name, team)

func lan_request_team(team: int) -> void:
	lan.lan_request_team(team)

func lan_request_ready(ready: bool) -> void:
	lan.lan_request_ready(ready)

func lan_start_game() -> void:
	lan.lan_start_game()

func _lan_broadcast_room() -> void:
	"""外部调用的房间状态广播（battle_network 等）"""
	lan._lan_broadcast_room()

# ============================================================
#  公网大厅方法（转发到 public_net）
# ============================================================

func get_public_server_host() -> String:
	return public_net.get_public_server_host()

func get_public_server_port() -> int:
	return public_net.get_public_server_port()

func public_connect(host: String = "", port: int = -1) -> void:
	public_net.public_connect(host, port)

func public_disconnect() -> void:
	public_net.public_disconnect()

func public_is_connected() -> bool:
	return public_net.public_is_connected()

func public_is_tcp_connected() -> bool:
	return public_net.public_is_tcp_connected()

func public_register(username: String, password: String, email: String = "", code: String = "") -> void:
	public_net.public_register(username, password, email, code)

func public_login(username: String, password: String) -> void:
	public_net.public_login(username, password)

func public_reset_password(username: String, email: String, code: String, new_password: String) -> void:
	public_net.public_reset_password(username, email, code, new_password)

func public_send_code(email: String, username: String, action: String) -> void:
	public_net.public_send_code(email, username, action)

func public_delete_account(password: String) -> void:
	public_net.public_delete_account(password)

func public_logout() -> void:
	public_net.public_logout()

func public_request_room_list() -> void:
	public_net.public_request_room_list()

func public_create_room(name: String, map_id: String, max_players: int, password: String = "", ai_config: Dictionary = {}) -> void:
	public_net.public_create_room(name, map_id, max_players, password, ai_config)

func public_join_room(room_id: String, password: String = "") -> void:
	public_net.public_join_room(room_id, password)

func public_leave_room() -> void:
	public_net.public_leave_room()

func public_start_game() -> void:
	public_net.public_start_game()

func public_send_room_chat(message: String) -> void:
	public_net.public_send_room_chat(message)

func public_set_ready(ready: bool) -> void:
	public_net.public_set_ready(ready)

func public_set_team(team: int) -> void:
	public_net.public_set_team(team)

func public_set_vehicle(vehicle_id: String) -> void:
	public_net.public_set_vehicle(vehicle_id)

func public_send_resource_ready(ready: bool) -> void:
	public_net.public_send_resource_ready(ready)

func public_request_friend_list() -> void:
	public_net.public_request_friend_list()

func public_add_friend(username: String) -> void:
	public_net.public_add_friend(username)

func public_accept_friend(user_id: String) -> void:
	public_net.public_accept_friend(user_id)

func public_decline_friend(user_id: String) -> void:
	public_net.public_decline_friend(user_id)

func public_remove_friend(user_id: String) -> void:
	public_net.public_remove_friend(user_id)

func public_request_friend_requests() -> void:
	public_net.public_request_friend_requests()

func public_send_party_invite(user_id: String) -> void:
	public_net.public_send_party_invite(user_id)

func public_party_accept(party_id: String) -> void:
	public_net.public_party_accept(party_id)

func public_party_decline(party_id: String) -> void:
	public_net.public_party_decline(party_id)

func public_party_leave() -> void:
	public_net.public_party_leave()

func public_request_party_info() -> void:
	public_net.public_request_party_info()

# ── 资源同步 ──

func public_check_resource(resource_type: String, resource_id: String) -> void:
	public_net.public_check_resource(resource_type, resource_id)

func public_upload_resource(resource_type: String, resource_id: String, resource_data: Dictionary, resource_hash: String = "") -> void:
	public_net.public_upload_resource(resource_type, resource_id, resource_data, resource_hash)

func public_download_resource(resource_type: String, resource_id: String) -> void:
	public_net.public_download_resource(resource_type, resource_id)

func public_verify_resource(resource_type: String, resource_id: String, resource_hash: String) -> void:
	public_net.public_verify_resource(resource_type, resource_id, resource_hash)

# ── 旧版公网占位接口（向后兼容） ──

func connect_public_server(server_address: String, server_port: int = 7777) -> bool:
	return public_net.connect_public_server(server_address, server_port)

func create_public_room(room_name: String = "") -> bool:
	return public_net.create_public_room(room_name)

func join_public_room(room_id: String) -> bool:
	return public_net.join_public_room(room_id)

# ============================================================
#  公网游戏UDP方法（转发到 public_net）
# ============================================================

func game_connect(host: String, port: int, room_id: String, player_id: String, username: String, team: int, vehicle_id: String) -> void:
	public_net.game_connect(host, port, room_id, player_id, username, team, vehicle_id)

func game_disconnect() -> void:
	public_net.game_disconnect()

func game_send_input(throttle: float, steering: float, turret: float, gun: float, fire: bool) -> void:
	public_net.game_send_input(throttle, steering, turret, gun, fire)

func game_send_state(position: Vector3, rotation: Vector3, turret_yaw: float, gun_pitch: float, health: float, velocity: Vector3) -> void:
	public_net.game_send_state(position, rotation, turret_yaw, gun_pitch, health, velocity)

func game_send_ai_state(ai_states: Array) -> void:
	public_net.game_send_ai_state(ai_states)

func game_send_fire(projectile_data: Dictionary) -> void:
	public_net.game_send_fire(projectile_data)

func game_send_hit(hit_data: Dictionary) -> void:
	public_net.game_send_hit(hit_data)

func game_send_destroy(destroy_data: Dictionary) -> void:
	public_net.game_send_destroy(destroy_data)

func game_send_foliage_destroy(center: Vector3, radius: float) -> void:
	public_net.game_send_foliage_destroy(center, radius)

func game_send_chat(message: String) -> void:
	public_net.game_send_chat(message)

func game_send_skill(skill_type: String, target_position: Vector3) -> void:
	public_net.game_send_skill(skill_type, target_position)

# ============================================================
#  @rpc 方法（必须在此节点，Godot 多人 RPC 按节点路径路由）
#  实现均转发给 lan 子系统
# ============================================================

@rpc("any_peer", "unreliable")
func rpc_send_input(_throttle: float, _steering: float, _turret: float, _gun: float, _fire: bool, _target_yaw: float, _target_pitch: float, _collective: float, _pitch: float, _yaw: float) -> void:
	lan.on_rpc_send_input(_throttle, _steering, _turret, _gun, _fire, _target_yaw, _target_pitch, _collective, _pitch, _yaw)

@rpc("any_peer")
func rpc_lan_battle_enter(vehicle_id: String, team: int, nickname: String) -> void:
	lan.on_rpc_lan_battle_enter(vehicle_id, team, nickname)

@rpc("authority", "unreliable")
func rpc_sync_vehicle_state(_peer_id: int, _position: Vector3, _quaternion: Quaternion, _turret_yaw: float, _gun_pitch: float, _speed: float, _health: float, _destroyed: bool, _alpha: float, _n_load: float, _delta_a: float, _delta_e: float, _delta_r: float, _fired: bool) -> void:
	lan.on_rpc_sync_vehicle_state(_peer_id, _position, _quaternion, _turret_yaw, _gun_pitch, _speed, _health, _destroyed, _alpha, _n_load, _delta_a, _delta_e, _delta_r, _fired)

@rpc("authority")
func rpc_spawn_vehicle(_peer_id: int, _vehicle_id: String, _team: int, _nickname: String, _position: Vector3, _rot_y: float) -> void:
	lan.on_rpc_spawn_vehicle(_peer_id, _vehicle_id, _team, _nickname, _position, _rot_y)

@rpc("authority")
func rpc_destroy_vehicle(_peer_id: int) -> void:
	lan.on_rpc_destroy_vehicle(_peer_id)

@rpc("any_peer")
func rpc_chat_message(player_name: String, message: String) -> void:
	lan.on_rpc_chat_message(player_name, message)

@rpc("any_peer")
func rpc_lan_register(name: String, team: int) -> void:
	lan.on_rpc_lan_register(name, team)

@rpc("any_peer")
func rpc_lan_team(team: int) -> void:
	lan.on_rpc_lan_team(team)

@rpc("any_peer")
func rpc_lan_ready(ready: bool) -> void:
	lan.on_rpc_lan_ready(ready)

@rpc("any_peer", "call_local")
func rpc_lan_start() -> void:
	lan.on_rpc_lan_start()

@rpc("any_peer", "call_local")
func rpc_lan_kill_feed(killer_name: String, victim_name: String, victim_team: int, killer_team: int) -> void:
	lan.on_rpc_lan_kill_feed(killer_name, victim_name, victim_team, killer_team)

@rpc("any_peer", "call_local")
func rpc_lan_sync(players_arr: Array) -> void:
	lan.on_rpc_lan_sync(players_arr)

@rpc("any_peer")
func rpc_request_map() -> void:
	lan.on_rpc_request_map()

@rpc("authority")
func rpc_receive_map(map_id: String, air_boundary_size: float = 0.0) -> void:
	lan.on_rpc_receive_map(map_id, air_boundary_size)

# ============================================================
#  多人回调（连接到全局 multiplayer 信号，转发给 lan）
# ============================================================

func _on_peer_connected(peer_id: int) -> void:
	lan.on_peer_connected(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	lan.on_peer_disconnected(peer_id)

func _on_connected_to_server() -> void:
	lan.on_connected_to_server()

func _on_connection_failed() -> void:
	lan.on_connection_failed()

func _on_server_disconnected() -> void:
	lan.on_server_disconnected()
