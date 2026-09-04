extends SceneTree
## 校验：LAN/公网联机 5 条链路 + 公网断线清理
## 通过代码静态检查验证 battle_network.gd 中各链路的关键调用和信号连接
## 1. 服务器端: lan_battle_begin_server + lan_register_server_vehicle + lan_battle_started.emit
## 2. 玩家入战: lan_player_entered_battle 信号连接 + _lan_on_player_entered 生成+注册+广播
## 3. 客户端入战: lan_vehicle_spawned/destroyed/peer_left/kill_feed 连接 + lan_set_own_vehicle + lan_track_remote_node + lan_battle_enter
## 4. 击杀播报: _lan_on_kill_feed -> GameManager.kill_feed.emit
## 5. 断线清理: _on_lan_server_disconnected 返回主菜单 + cleanup_on_exit 停止网络 + _on_game_disconnected 公网清理

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _initialize() -> void:
	print("=== check_lan_linkages ===")
	var bn := _read_file("res://scripts/core/battle/battle_network.gd")
	var nm := _read_file("res://scripts/network/network_manager.gd")
	var lan_nm := _read_file("res://scripts/network/lan_network.gd")
	var main := _read_file("res://scripts/core/main.gd")
	var vdh := _read_file("res://scripts/vehicles/components/vehicle_damage_handler.gd")

	# === 链路1: 服务器端初始化 ===
	_check(bn.find("lan_battle_begin_server()") >= 0,
		"[链1] 服务器调用 lan_battle_begin_server()")
	_check(bn.find("lan_register_server_vehicle(1, main.player_tank)") >= 0,
		"[链1] 服务器登记房主载具 lan_register_server_vehicle(1, player_tank)")
	_check(bn.find("lan_battle_started.emit()") >= 0,
		"[链1] 服务器发射 lan_battle_started 信号")
	_check(bn.find("NetworkManager.is_server") >= 0 and bn.find("setup_lan_battle") >= 0,
		"[链1] setup_lan_battle() 中有 is_server 分支")

	# === 链路2: 玩家入战 ===
	_check(bn.find("lan_player_entered_battle.connect(_lan_on_player_entered)") >= 0,
		"[链2] 服务器连接 lan_player_entered_battle 信号")
	_check(bn.find("func _lan_on_player_entered") >= 0,
		"[链2] _lan_on_player_entered 函数存在")
	_check(bn.find("v.is_server_controlled = true") >= 0,
		"[链2] 入战载具标记为服务器控制")
	_check(bn.find("NetworkManager.lan_register_server_vehicle(peer_id, v)") >= 0,
		"[链2] 入战载具注册到服务器权威副本")
	_check(bn.find("NetworkManager.lan_broadcast_spawn(") >= 0,
		"[链2] 服务器广播现有载具出生")

	# === 链路3: 客户端入战 ===
	_check(bn.find("lan_vehicle_spawned.connect(_lan_on_vehicle_spawned)") >= 0,
		"[链3] 客户端连接 lan_vehicle_spawned 信号")
	_check(bn.find("lan_vehicle_destroyed.connect(_lan_on_vehicle_destroyed)") >= 0,
		"[链3] 客户端连接 lan_vehicle_destroyed 信号")
	_check(bn.find("lan_peer_left_battle.connect(_lan_on_peer_left_battle)") >= 0,
		"[链3] 客户端连接 lan_peer_left_battle 信号")
	_check(bn.find("lan_kill_feed.connect(_lan_on_kill_feed)") >= 0,
		"[链3] 客户端连接 lan_kill_feed 信号")
	_check(bn.find("NetworkManager.lan_set_own_vehicle(main.player_tank)") >= 0,
		"[链3] 客户端登记自己的载具 lan_set_own_vehicle")
	_check(bn.find("NetworkManager.lan_track_remote_node(NetworkManager.local_player_id, main.player_tank)") >= 0,
		"[链3] 客户端追踪自己的载具 lan_track_remote_node")
	_check(bn.find("NetworkManager.lan_battle_enter(vid, team)") >= 0,
		"[链3] 客户端调用 lan_battle_enter 上报入战")
	_check(bn.find("func _lan_on_vehicle_spawned") >= 0,
		"[链3] _lan_on_vehicle_spawned 函数存在")
	_check(bn.find("v.is_player_controlled = false") >= 0 and bn.find("v.is_server_controlled = false") >= 0,
		"[链3] 远程幽灵标记为非玩家非服务器控制")
	_check(bn.find("NetworkManager.lan_track_remote_node(peer_id, v)") >= 0,
		"[链3] 远程幽灵注册到 lan_track_remote_node")

	# === 链路4: 击杀播报 ===
	_check(bn.find("func _lan_on_kill_feed") >= 0,
		"[链4] _lan_on_kill_feed 函数存在")
	_check(bn.find("GameManager.kill_feed.emit(killer_name, victim_name, victim_team, killer_team)") >= 0,
		"[链4] _lan_on_kill_feed 发射 GameManager.kill_feed 信号")
	_check(main.find("GameManager.kill_feed.connect") >= 0,
		"[链4] main.gd 连接 GameManager.kill_feed 到胜负检测")
	_check(main.find("on_kill_check_victory") >= 0,
		"[链4] 胜负检测回调 on_kill_check_victory 存在")
	# 服务器端击毁时广播 kill feed
	_check(vdh.find("rpc_lan_kill_feed") >= 0,
		"[链4] vehicle_damage_handler 服务器端广播 rpc_lan_kill_feed")
	_check(nm.find("func rpc_lan_kill_feed") >= 0,
		"[链4] network_manager 定义 rpc_lan_kill_feed RPC")
	_check(nm.find('@"any_peer", "call_local"') >= 0 or nm.find('"any_peer", "call_local"') >= 0,
		"[链4] rpc_lan_kill_feed 标记为 call_local（服务器自身也接收）")

	# === 链路5: 断线清理 ===
	# LAN 客户端断线
	_check(bn.find("server_disconnected.connect(_on_lan_server_disconnected)") >= 0,
		"[链5] 客户端连接 server_disconnected 信号")
	_check(bn.find("func _on_lan_server_disconnected") >= 0,
		"[链5] _on_lan_server_disconnected 函数存在")
	_check(bn.find("NetworkManager.stop_network()") >= 0,
		"[链5] 断线时调用 stop_network()")
	_check(bn.find('change_scene_to_file("res://scenes/main_menu.tscn")') >= 0,
		"[链5] 断线后返回主菜单")
	# LAN 服务器端玩家离开清理（实现已拆分到 lan_network.gd）
	_check(lan_nm.find("lan_broadcast_destroy(peer_id)") >= 0,
		"[链5] 服务器端玩家断开时广播销毁 lan_broadcast_destroy")
	_check(lan_nm.find("lan_peer_left_battle.emit(peer_id)") >= 0,
		"[链5] 客户端端玩家断开时发射 lan_peer_left_battle")
	_check(bn.find("func _lan_on_peer_left_battle") >= 0,
		"[链5] _lan_on_peer_left_battle 函数存在")
	_check(bn.find("node.queue_free()") >= 0,
		"[链5] 玩家离开时 queue_free 远程载具")
	# 退出清理
	_check(bn.find("func cleanup_on_exit") >= 0,
		"[链5] cleanup_on_exit 函数存在")
	_check(bn.find("NetworkManager.game_disconnect()") >= 0,
		"[链5] 公网退出时调用 game_disconnect()")
	_check(bn.find("NetworkManager.stop_network()") >= 0,
		"[链5] LAN 退出时调用 stop_network()")

	# === 公网模式断线清理（修复验证） ===
	_check(bn.find("func _on_game_disconnected") >= 0,
		"[公网] _on_game_disconnected 函数存在")
	_check(bn.find("main.remote_tanks.clear()") >= 0,
		"[公网] 断线时清理 remote_tanks")
	_check(bn.find("change_scene_to_file") >= 0 and bn.find("_on_game_disconnected") >= 0,
		"[公网] 断线后返回主菜单")
	var disc_func_start := bn.find("func _on_game_disconnected")
	var disc_func_end := bn.find("func ", disc_func_start + 10)
	if disc_func_end < 0:
		disc_func_end = bn.length()
	var disc_func := bn.substr(disc_func_start, disc_func_end - disc_func_start)
	_check(disc_func.find("queue_free()") >= 0,
		"[公网] 断线时 queue_free 远程载具和AI载具")
	_check(disc_func.find("chat_message") >= 0,
		"[公网] 断线时发送系统消息")

	# === is_public_local 三类载具声明 ===
	var tank_src := _read_file("res://scripts/vehicles/tank.gd")
	var heli_src := _read_file("res://scripts/vehicles/helicopter.gd")
	var plane_src := _read_file("res://scripts/vehicles/airplane.gd")
	_check(tank_src.find("var is_public_local: bool = false") >= 0,
		"[属性] tank.gd 声明 is_public_local")
	_check(heli_src.find("var is_public_local: bool = false") >= 0,
		"[属性] helicopter.gd 声明 is_public_local")
	_check(plane_src.find("var is_public_local: bool = false") >= 0,
		"[属性] airplane.gd 声明 is_public_local")

	# === 公网模式状态上报 ===
	_check(tank_src.find("game_send_state(") >= 0,
		"[公网上报] tank.gd 调用 game_send_state()")
	_check(heli_src.find("game_send_state(") >= 0,
		"[公网上报] helicopter.gd 调用 game_send_state()")
	_check(plane_src.find("game_send_state(") >= 0,
		"[公网上报] airplane.gd 调用 game_send_state()")

	# === LAN 服务器 tick 同步（实现已拆分到 lan_network.gd，RPC 桩保留在 network_manager.gd） ===
	_check(lan_nm.find("func _server_tick") >= 0,
		"[LAN同步] _server_tick 函数存在")
	_check(nm.find("rpc_sync_vehicle_state") >= 0,
		"[LAN同步] rpc_sync_vehicle_state RPC 定义")
	_check(nm.find("func rpc_send_input") >= 0,
		"[LAN同步] rpc_send_input RPC 定义（客户端上报输入）")
	_check(lan_nm.find("func _lan_apply_input") >= 0,
		"[LAN同步] _lan_apply_input 函数存在（服务器应用远端输入）")

	_finish()

func _finish() -> void:
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
