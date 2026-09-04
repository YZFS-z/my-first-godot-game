extends Node
## 战斗网络协调器 - 负责局域网和公网联机的战斗场景协调
## 作为 Main 节点的子节点，通过 get_parent() 访问共享状态

var _ai_send_timer: float = 0.0
var _lan_kill_feed_connected: bool = false

func _get_main() -> Node:
	return get_parent()

func process_ai_sync(delta: float) -> void:
	"""公网模式：AI主机发送AI状态（10Hz），由 main._process 调用"""
	var main = _get_main()
	if main.is_public_mode and main.is_ai_host and NetworkManager.game_connected_flag:
		_ai_send_timer += delta
		if _ai_send_timer >= 0.1:
			_ai_send_timer = 0.0
			send_ai_states()

func send_ai_states() -> void:
	var main = _get_main()
	var ai_states = []
	for child in main.get_children():
		if not (child is Node3D):
			continue
		if not "network_player_id" in child:
			continue
		var nid = child.network_player_id
		if not nid or not nid.begins_with("ai_"):
			continue
		if not is_instance_valid(child) or child.is_destroyed:
			continue
		ai_states.append({
			"ai_id": nid,
			"position": [child.global_position.x, child.global_position.y, child.global_position.z],
			"rotation": [child.global_rotation.x, child.global_rotation.y, child.global_rotation.z],
			"turret_yaw": child.turret_yaw,
			"gun_pitch": child.gun_pitch,
			"health": child.get_health_percent(),
			"destroyed": child.is_destroyed,
		})
	if not ai_states.is_empty():
		NetworkManager.game_send_ai_state(ai_states)

# === 局域网战斗 ===

func setup_lan_battle() -> void:
	var main = _get_main()
	if NetworkManager.debug_verbose:
		print("[BattleNetwork] 局域网对战初始化 (server=%s client=%s)" % [str(NetworkManager.is_server), str(NetworkManager.is_client)])
	var vid = GameManager.selected_vehicle_id
	if vid == "":
		vid = "tank_abrams"
	var team = GameManager.public_player_team if GameManager.public_player_team > 0 else 1

	if NetworkManager.is_server:
		NetworkManager.lan_player_entered_battle.connect(_lan_on_player_entered)
		NetworkManager.lan_battle_begin_server()
		NetworkManager.lan_register_server_vehicle(1, main.player_tank)
		NetworkManager.lan_battle_started.emit()
		print("[BattleNetwork] LAN 房主入战: %s 队伍%d" % [vid, team])
	else:
		NetworkManager.lan_vehicle_spawned.connect(_lan_on_vehicle_spawned)
		NetworkManager.lan_vehicle_destroyed.connect(_lan_on_vehicle_destroyed)
		NetworkManager.lan_peer_left_battle.connect(_lan_on_peer_left_battle)
		if not _lan_kill_feed_connected:
			NetworkManager.lan_kill_feed.connect(_lan_on_kill_feed)
			_lan_kill_feed_connected = true
		NetworkManager.lan_set_own_vehicle(main.player_tank)
		NetworkManager.lan_track_remote_node(NetworkManager.local_player_id, main.player_tank)
		NetworkManager.lan_battle_enter(vid, team)
		if not NetworkManager.server_disconnected.is_connected(_on_lan_server_disconnected):
			NetworkManager.server_disconnected.connect(_on_lan_server_disconnected)
		if NetworkManager.debug_verbose:
			print("[BattleNetwork] LAN 客户端上报入战: %s 队伍%d (peer=%d)" % [vid, team, NetworkManager.local_player_id])

func _on_lan_server_disconnected() -> void:
	print("[BattleNetwork] LAN 服务器断开，返回主菜单")
	NetworkManager.stop_network()
	GameManager.chat_message.emit("系统", "与房主的连接已断开。", 0)
	var main = _get_main()
	if main.victory_panel:
		main.victory_panel.queue_free()
		main.victory_panel = null
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _lan_on_player_entered(peer_id: int, vehicle_id: String, team: int, nickname: String) -> void:
	var main = _get_main()
	var vehicle_spawner = main.get_node_or_null("VehicleSpawner")
	var spawn = vehicle_spawner.get_spawn_point(team) if vehicle_spawner else Transform3D()
	var scene = vehicle_spawner.get_vehicle_scene(vehicle_id) if vehicle_spawner else null
	if not scene:
		push_error("[BattleNetwork] LAN 无法加载载具场景: %s" % vehicle_id)
		return
	var v = scene.instantiate()
	v.position = spawn.origin
	v.rotation.y = spawn.basis.get_euler().y
	v.is_player_controlled = false
	v.is_server_controlled = true
	v.is_remote_ai = false
	v.team = team
	v.nickname = nickname
	v.network_player_id = str(peer_id)
	main.add_child(v)
	var data = DataLoader.get_vehicle(vehicle_id)
	if not data.is_empty():
		v.setup_from_data(data)
	NetworkManager.lan_register_server_vehicle(peer_id, v)
	for pid in NetworkManager.lan_server_vehicles.keys():
		var tv = NetworkManager.lan_server_vehicles[pid]
		if tv == null or not is_instance_valid(tv):
			continue
		NetworkManager.lan_broadcast_spawn(pid, tv.vehicle_id, tv.team, tv.nickname, tv.global_position, tv.rotation.y)
	print("[BattleNetwork] LAN 玩家%d入战: %s (%s) 队伍%d" % [peer_id, nickname, vehicle_id, team])

func _lan_on_vehicle_spawned(peer_id: int, vehicle_id: String, team: int, nickname: String, position: Vector3, rot_y: float) -> void:
	var main = _get_main()
	var vehicle_spawner = main.get_node_or_null("VehicleSpawner")
	if NetworkManager.lan_remote_nodes.has(peer_id):
		return
	if peer_id == NetworkManager.local_player_id:
		NetworkManager.lan_track_remote_node(peer_id, main.player_tank)
		return
	var scene = vehicle_spawner.get_vehicle_scene(vehicle_id) if vehicle_spawner else null
	if not scene:
		push_error("[BattleNetwork] LAN 无法加载远程载具场景: %s" % vehicle_id)
		return
	var v = scene.instantiate()
	v.is_player_controlled = false
	v.is_server_controlled = false
	v.is_remote_ai = false
	v.team = team
	v.nickname = nickname
	v.network_player_id = str(peer_id)
	main.add_child(v)
	v.global_position = position
	v.global_rotation = Vector3(0, rot_y, 0)
	var data = DataLoader.get_vehicle(vehicle_id)
	if not data.is_empty():
		v.setup_from_data(data)
	NetworkManager.lan_track_remote_node(peer_id, v)
	if NetworkManager.debug_verbose:
		print("[BattleNetwork] LAN 远程载具生成: %s (%s) 队伍%d peer=%d" % [nickname, vehicle_id, team, peer_id])

func _lan_on_vehicle_destroyed(peer_id: int) -> void:
	var node = NetworkManager.lan_remote_nodes.get(peer_id)
	if node and is_instance_valid(node) and not node.is_destroyed:
		node.mark_network_destroyed()
		print("[BattleNetwork] LAN 远程载具被击毁: peer=%d %s" % [peer_id, node.nickname])

func _lan_on_peer_left_battle(peer_id: int) -> void:
	var node = NetworkManager.lan_remote_nodes.get(peer_id)
	if node and is_instance_valid(node):
		node.queue_free()
		print("[BattleNetwork] LAN 玩家离开：移除远程载具 peer=%d" % peer_id)

func _lan_on_kill_feed(killer_name: String, victim_name: String, victim_team: int, killer_team: int) -> void:
	GameManager.kill_feed.emit(killer_name, victim_name, victim_team, killer_team)

# === 公网联机 ===

func setup_public_game() -> void:
	var main = _get_main()
	main.is_public_mode = true
	var host = GameManager.public_game_host
	var port = GameManager.public_game_port
	var room_id = GameManager.public_room_id
	var player_id = NetworkManager.public_user_id
	var username = NetworkManager.public_username
	var vehicle_id = GameManager.selected_vehicle_id
	var team = GameManager.public_player_team
	if host.is_empty() or port <= 0:
		print("[BattleNetwork] 公网游戏地址无效，回退单机模式")
		var vehicle_spawner = main.get_node_or_null("VehicleSpawner")
		if vehicle_spawner:
			vehicle_spawner.spawn_level_tanks()
		return
	print("[BattleNetwork] 连接公网游戏服务器: %s:%d 队伍:%d" % [host, port, team])

	NetworkManager.game_state_received.connect(_on_game_state)
	NetworkManager.game_player_joined.connect(_on_game_player_joined)
	NetworkManager.game_player_left.connect(_on_game_player_left)
	NetworkManager.game_remote_input.connect(_on_game_remote_input)
	NetworkManager.game_fire_event.connect(_on_game_fire)
	NetworkManager.game_hit_event.connect(_on_game_hit)
	NetworkManager.game_destroy_event.connect(_on_game_destroy)
	NetworkManager.game_chat_message.connect(_on_game_chat)
	NetworkManager.game_skill_event.connect(_on_game_skill)
	NetworkManager.game_foliage_destroy.connect(_on_foliage_destroy)
	NetworkManager.game_disconnected.connect(_on_game_disconnected)

	NetworkManager.game_connect(host, port, room_id, player_id, username, team, vehicle_id)

	if main.player_tank:
		main.player_tank.is_public_local = true

	var vehicle_spawner = main.get_node_or_null("VehicleSpawner")
	if vehicle_spawner:
		vehicle_spawner.spawn_public_ai()

	main.is_ai_host = true

func _on_game_state(state: Dictionary) -> void:
	var main = _get_main()
	var players = state.get("players", [])
	var my_id = NetworkManager.public_user_id
	var all_ids = [my_id]
	for p in players:
		all_ids.append(p.get("player_id", ""))
	all_ids.sort()
	main.is_ai_host = (all_ids.size() > 0 and all_ids[0] == my_id)

	for p in players:
		var pid = p.get("player_id", "")
		if pid == my_id:
			continue
		if pid in main.remote_tanks:
			var tank = main.remote_tanks[pid]
			var pos = p.get("position", [0, 0, 0])
			var rot = p.get("rotation", [0, 0, 0])
			tank.global_position = Vector3(pos[0], pos[1], pos[2])
			tank.global_rotation = Vector3(rot[0], rot[1], rot[2])
			tank.turret_yaw = p.get("turret_yaw", 0)
			tank.gun_pitch = p.get("gun_pitch", 0)
			if tank.turret_node:
				tank.turret_node.rotation.y = deg_to_rad(tank.turret_yaw)
			if tank.gun_node:
				tank.gun_node.rotation.x = deg_to_rad(tank.gun_pitch)
		else:
			_spawn_remote_tank(p)

	if not main.is_ai_host:
		var ai_states = state.get("ai_states", [])
		for ai_data in ai_states:
			var ai_id = ai_data.get("ai_id", "")
			if ai_id.is_empty():
				continue
			var ai_tank = find_vehicle_by_network_id(ai_id)
			if ai_tank and is_instance_valid(ai_tank):
				var pos = ai_data.get("position", [0, 0, 0])
				var rot = ai_data.get("rotation", [0, 0, 0])
				ai_tank.global_position = Vector3(pos[0], pos[1], pos[2])
				ai_tank.global_rotation = Vector3(rot[0], rot[1], rot[2])
				ai_tank.turret_yaw = ai_data.get("turret_yaw", 0)
				ai_tank.gun_pitch = ai_data.get("gun_pitch", 0)
				if ai_tank.turret_node:
					ai_tank.turret_node.rotation.y = deg_to_rad(ai_tank.turret_yaw)
				if ai_tank.gun_node:
					ai_tank.gun_node.rotation.x = deg_to_rad(ai_tank.gun_pitch)
				ai_tank.is_remote_ai = true
				ai_tank.is_server_controlled = true
				ai_tank.is_player_controlled = false

func _spawn_remote_tank(player_data: Dictionary) -> void:
	var main = _get_main()
	var vehicle_spawner = main.get_node_or_null("VehicleSpawner")
	var pid = player_data.get("player_id", "")
	var vid = player_data.get("vehicle_id", "tank_abrams")
	var team = player_data.get("team", 2)
	var username = player_data.get("username", "玩家")
	var tank_scene = vehicle_spawner.get_vehicle_scene(vid) if vehicle_spawner else null
	if not tank_scene:
		return
	var tank = tank_scene.instantiate()
	tank.is_player_controlled = false
	tank.is_server_controlled = false
	tank.team = team
	tank.nickname = username
	tank.vehicle_id = vid
	tank.network_player_id = pid
	main.add_child(tank)
	var pos = player_data.get("position", [0, 0, 0])
	var rot = player_data.get("rotation", [0, 0, 0])
	tank.global_position = Vector3(pos[0], pos[1], pos[2])
	tank.global_rotation = Vector3(rot[0], rot[1], rot[2])
	var data = DataLoader.get_vehicle(vid)
	if not data.is_empty():
		tank.setup_from_data(data)
	main.remote_tanks[pid] = tank
	print("[BattleNetwork] 远程玩家加入: %s (%s)" % [username, pid])

func _on_game_player_joined(player_data: Dictionary) -> void:
	var main = _get_main()
	var pid = player_data.get("player_id", "")
	if pid == NetworkManager.public_user_id:
		return
	if pid not in main.remote_tanks:
		_spawn_remote_tank(player_data)

func _on_game_player_left(player_id: String) -> void:
	var main = _get_main()
	if player_id in main.remote_tanks:
		main.remote_tanks[player_id].queue_free()
		main.remote_tanks.erase(player_id)
		print("[BattleNetwork] 远程玩家离开: %s" % player_id)

func _on_game_remote_input(player_id: String, input_data: Dictionary) -> void:
	pass

func _on_game_fire(fire_data: Dictionary) -> void:
	var main = _get_main()
	var pid = fire_data.get("player_id", "")
	if pid in main.remote_tanks:
		var tank = main.remote_tanks[pid]
		if tank and tank.has_method("fire_remote"):
			tank.fire_remote(fire_data)

func _on_game_hit(hit_data: Dictionary) -> void:
	var target_id = hit_data.get("target_id", "")
	var damage = hit_data.get("damage", 0.0)
	var module_name = hit_data.get("module_name", "hull")
	var hit_pos = hit_data.get("hit_position", [0, 0, 0])
	var pos = Vector3(hit_pos[0], hit_pos[1], hit_pos[2])
	var penetrated = hit_data.get("penetrated", false)
	var dmg_type = hit_data.get("dmg_type", 0)
	var explosive_mass = hit_data.get("explosive_mass", 0.0)
	var normal_arr = hit_data.get("hit_normal", [0, 0, -1])
	var hit_normal = Vector3(normal_arr[0], normal_arr[1], normal_arr[2])
	if hit_normal.length() < 0.01:
		hit_normal = Vector3.FORWARD
	if dmg_type == 1 or explosive_mass > 0:
		EffectManager.play_explosion(pos, 0.55)
	else:
		var spark_color = Color(1, 0.85, 0.3) if penetrated else Color(0.7, 0.7, 0.7)
		EffectManager.play_hit_spark(pos, hit_normal, spark_color)
	var target = find_vehicle_by_network_id(target_id)
	if target and not target.is_destroyed:
		target.take_damage(module_name, damage, 0, 0.0, null)
		if NetworkManager.debug_verbose:
			print("[BattleNetwork] 同步命中: %s 模块:%s 伤害:%.1f 击穿:%s" % [target_id, module_name, damage, penetrated])

func _on_game_destroy(destroy_data: Dictionary) -> void:
	var main = _get_main()
	var target_id = destroy_data.get("target_id", "")
	var target = find_vehicle_by_network_id(target_id)
	if target and not target.is_destroyed:
		target.is_destroyed = true
		target.velocity = Vector3.ZERO
		var pos = destroy_data.get("position", [0, 0, 0])
		var explode_pos = Vector3(pos[0], pos[1], pos[2]) + Vector3(0, 1.0, 0)
		EffectManager.play_explosion(explode_pos, 1.5)
		var foliage_manager = main.get_node_or_null("FoliageManager")
		if foliage_manager:
			foliage_manager.destroy_foliage_in_radius(explode_pos, 8.0, 80.0)
		if target.is_inside_tree() and target.get("fire_effect") == null:
			EffectManager.play_fire_smoke(target, Vector3(0, 0.8, 0))
		if target.nickname_label:
			target.nickname_label.modulate = Color(0.5, 0.5, 0.5, 0.6)
			target.nickname_label.text = target.nickname + " (已摧毁)"
		print("[BattleNetwork] 同步击毁: %s" % target_id)

	var battle_ui = main.get_node_or_null("BattleUI")
	if battle_ui:
		battle_ui.check_victory()

	if target_id == NetworkManager.public_user_id:
		return
	var killer_name = destroy_data.get("killer_name", "未知")
	var victim_name = destroy_data.get("victim_name", target_id)
	var killer_team = int(destroy_data.get("killer_team", 0))
	var victim_team = int(destroy_data.get("victim_team", 0))
	GameManager.kill_feed.emit(killer_name, victim_name, victim_team, killer_team)

func find_vehicle_by_network_id(network_id: String) -> Node:
	var main = _get_main()
	if network_id == "":
		return null
	if network_id == NetworkManager.public_user_id and main.player_tank:
		return main.player_tank
	if network_id in main.remote_tanks:
		return main.remote_tanks[network_id]
	for child in main.get_children():
		if child and "network_player_id" in child and child.network_player_id == network_id:
			return child
	return null

func _on_game_chat(chat_data: Dictionary) -> void:
	var sender = chat_data.get("username", "玩家")
	var msg = chat_data.get("message", "")
	if GameManager.has_signal("chat_message"):
		GameManager.chat_message.emit(sender, msg, 0)
	print("[BattleChat] %s: %s" % [sender, msg])

func _on_game_skill(skill_data: Dictionary) -> void:
	var pid = skill_data.get("player_id", "")
	if pid == NetworkManager.public_user_id:
		return
	var skill_type = skill_data.get("skill_type", "")
	var target_pos_arr = skill_data.get("target_position", [0, 0, 0])
	var target_pos = Vector3(target_pos_arr[0], target_pos_arr[1], target_pos_arr[2])
	var target = find_vehicle_by_network_id(pid)
	if target and target.has_method("execute_skill_remote"):
		target.execute_skill_remote(skill_type, target_pos)
		if NetworkManager.debug_verbose:
			print("[BattleNetwork] 同步技能: %s 释放 %s @ %s" % [pid, skill_type, target_pos])
	else:
		if NetworkManager.debug_verbose:
			print("[BattleNetwork] 同步技能: 未找到载具 %s，直接播放特效" % pid)
		if skill_type == "smoke":
			EffectManager.play_smoke_screen(target_pos, 15.0)

func _on_foliage_destroy(foliage_data: Dictionary) -> void:
	var main = _get_main()
	var pid = foliage_data.get("player_id", "")
	if pid == NetworkManager.public_user_id:
		return
	var center_arr = foliage_data.get("center", [0, 0, 0])
	var center = Vector3(center_arr[0], center_arr[1], center_arr[2])
	var radius = foliage_data.get("radius", 5.0)
	main._is_remote_foliage_destroy = true
	var foliage_manager = main.get_node_or_null("FoliageManager")
	if foliage_manager:
		foliage_manager.destroy_foliage_in_radius(center, radius)
	main._is_remote_foliage_destroy = false
	if NetworkManager.debug_verbose:
		print("[BattleNetwork] 同步植被销毁: 中心%s 半径%.1f" % [str(center), radius])

func _on_game_disconnected() -> void:
	var main = _get_main()
	print("[BattleNetwork] 公网游戏断开")
	# 清理所有远程载具
	for pid in main.remote_tanks.keys():
		var tank = main.remote_tanks[pid]
		if tank and is_instance_valid(tank):
			tank.queue_free()
	main.remote_tanks.clear()
	# 清理公网 AI 载具
	for child in main.get_children():
		if child and "network_player_id" in child:
			var nid = child.network_player_id
			if nid and nid.begins_with("ai_") and is_instance_valid(child):
				child.queue_free()
	# 通知 HUD
	if GameManager.has_signal("chat_message"):
		GameManager.chat_message.emit("系统", "与公网服务器的连接已断开。", 0)
	# 返回主菜单
	if main.victory_panel:
		main.victory_panel.queue_free()
		main.victory_panel = null
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func cleanup_on_exit() -> void:
	"""退出场景树时的网络清理，由 main._exit_tree 调用"""
	var main = _get_main()
	if main.is_public_mode and NetworkManager.game_connected_flag:
		NetworkManager.game_disconnect()
	if GameManager.network_type == 0 and (NetworkManager.is_server or NetworkManager.is_client):
		NetworkManager.stop_network()
