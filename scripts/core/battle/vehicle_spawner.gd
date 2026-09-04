extends Node3D
## 载具生成器 - 负责玩家/AI载具生成、AI挂载、出生点管理
## 作为 Main 节点的子节点，通过 get_parent() 访问共享状态

const AI_NICKNAMES: Array = [
	"钢铁猛兽", "闪电战", "幽灵骑士", "沙漠之狐", "铁血战士",
	"暗夜猎手", "雷霆一击", "重装坦克", "迅捷斥候", "堡垒",
	"毁灭者", "守护者", "先锋官", "老兵", "菜鸟一号",
	"车长老王", "炮手小李", "驾驶员老张", "装填手小刘", "车长伊万",
	"TigerAce", "PanzerLeader", "Sherman", "ComradeTank", "IronFist",
	"静默之狼", "烈焰战车", "寒霜", "岩石", "疾风"
]

var used_nicknames: Array = []

func _get_main() -> Node:
	return get_parent()

func _get_map_config() -> Dictionary:
	return _get_main().map_config

func _get_random_nickname() -> String:
	var available = AI_NICKNAMES.duplicate()
	for n in used_nicknames:
		available.erase(n)
	if available.is_empty():
		used_nicknames.clear()
		available = AI_NICKNAMES.duplicate()
	var name = available[randi() % available.size()]
	used_nicknames.append(name)
	return name

func get_vehicle_scene(vehicle_id: String) -> PackedScene:
	var data = DataLoader.get_vehicle(vehicle_id)
	var vtype = data.get("type", "tank")
	var scene_path = "res://scenes/vehicle.tscn"
	if vtype == "helicopter":
		scene_path = "res://scenes/helicopter.tscn"
	elif vtype == "airplane":
		scene_path = "res://scenes/airplane.tscn"
	var scene = load(scene_path)
	if not scene:
		push_error("[VehicleSpawner] Failed to load vehicle scene: %s" % scene_path)
		return null
	return scene

func spawn_player_tank(vehicle_id: String) -> void:
	var main = _get_main()
	var player_team: int = GameManager.public_player_team if GameManager.public_player_team > 0 else 1
	var spawn = get_spawn_point(player_team)
	var tank_scene = get_vehicle_scene(vehicle_id)
	if not tank_scene:
		push_error("[VehicleSpawner] Vehicle scene not found")
		return

	main.player_tank = tank_scene.instantiate()
	main.player_tank.position = spawn.origin
	main.player_tank.rotation.y = spawn.basis.get_euler().y
	main.player_tank.is_player_controlled = true
	main.player_tank.is_server_controlled = true
	main.player_tank.team = player_team
	main.player_tank.nickname = SettingsManager.get_nickname()
	main.player_tank.network_player_id = NetworkManager.public_user_id if GameManager.network_type == 1 else ""
	main.add_child(main.player_tank)

	var data = DataLoader.get_vehicle(vehicle_id)
	if not data.is_empty():
		main.player_tank.setup_from_data(data)

	GameManager.set_player_vehicle(main.player_tank)
	print("[VehicleSpawner] Player spawned: %s at %s" % [data.get("name", vehicle_id), str(spawn.origin)])
	if not main._get_mobile_controls():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func spawn_enemy_tank() -> void:
	var main = _get_main()
	var spawn = get_spawn_point(2)
	var enemy_id = "tank_t34_85"
	if GameManager.selected_vehicle_id == "tank_t34_85":
		enemy_id = "tank_abrams"
	var tank_scene = get_vehicle_scene(enemy_id)
	if not tank_scene:
		return

	main.enemy_tank = tank_scene.instantiate()
	main.enemy_tank.position = spawn.origin
	main.enemy_tank.rotation.y = spawn.basis.get_euler().y
	main.enemy_tank.is_player_controlled = false
	main.enemy_tank.is_server_controlled = true
	main.enemy_tank.team = 2
	main.enemy_tank.nickname = _get_random_nickname()
	main.add_child(main.enemy_tank)

	var data = DataLoader.get_vehicle(enemy_id)
	if not data.is_empty():
		main.enemy_tank.setup_from_data(data)

	attach_ai(main.enemy_tank, 2)
	print("[VehicleSpawner] Enemy spawned: %s at %s" % [data.get("name", enemy_id), str(spawn.origin)])

func attach_ai(tank: Node, ai_team: int, difficulty: int = 1) -> void:
	var vtype: String = "tank"
	if tank and tank.vehicle_data:
		vtype = tank.vehicle_data.get("type", "tank")
	var is_aircraft: bool = vtype == "helicopter" or vtype == "airplane"
	var ai_path: String = "res://scripts/ai/aircraft_ai.gd" if is_aircraft else "res://scripts/ai/tank_ai.gd"
	var ai_script = load(ai_path)
	if not ai_script:
		push_error("[VehicleSpawner] AI script not found: %s" % ai_path)
		return
	var ai = ai_script.new()
	ai.team = ai_team
	match difficulty:
		0:
			ai.aggression = 0.3
			ai.accuracy = 0.4
			ai.fire_cooldown = 5.0
			ai.reaction_min = 1.0
			ai.reaction_max = 2.5
			if is_aircraft:
				ai.detection_range = 300.0
				ai.attack_range = 320.0
		2:
			ai.aggression = 0.8
			ai.accuracy = 0.85
			ai.fire_cooldown = 2.0
			ai.reaction_min = 0.2
			ai.reaction_max = 0.6
			if is_aircraft:
				ai.detection_range = 700.0
				ai.attack_range = 700.0
		_:
			ai.aggression = 0.5
			ai.accuracy = 0.65
			ai.fire_cooldown = 3.0
			ai.reaction_min = 0.5
			ai.reaction_max = 1.5
	if is_aircraft:
		var weapon_range: float = ai.attack_range
		var weapon_slots: Array = tank.vehicle_data.get("weapons", [])
		for w in weapon_slots:
			var weapon_data = DataLoader.get_weapon(w.get("weapon_id", ""))
			if weapon_data.is_empty():
				continue
			for at in weapon_data.get("ammo_types", []):
				var lr: float = float(at.get("lock_range", 0.0))
				if lr > 0.0:
					weapon_range = max(weapon_range, min(lr, 800.0))
		ai.attack_range = weapon_range
	else:
		var physics = tank.vehicle_data.get("physics", {})
		var max_speed = physics.get("max_speed", 50.0)
		if max_speed > 60:
			ai.aggression = clamp(ai.aggression + 0.15, 0, 1)
		elif max_speed < 40:
			ai.aggression = clamp(ai.aggression - 0.15, 0, 1)
			ai.fire_cooldown += 1.0
	tank.add_child(ai)
	print("[VehicleSpawner] AI attached to %s (type %s, team %d, difficulty %d)" % [tank.vehicle_id, vtype, ai_team, difficulty])

func spawn_ai_tanks(count_per_team: int = 1) -> void:
	var map_config = _get_map_config()
	var vehicle_ids = ["tank_abrams", "tank_t34_85"]
	var map_size = map_config.get("size", 200)

	for team in [1, 2]:
		for i in range(count_per_team):
			var spawn = get_spawn_point(team)
			var offset = Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
			var pos = spawn.origin + offset
			pos.x = clamp(pos.x, -map_size/2 + 10, map_size/2 - 10)
			pos.z = clamp(pos.z, -map_size/2 + 10, map_size/2 - 10)
			if map_config.has("terrain"):
				var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")
				if terrain_builder:
					pos.y = terrain_builder.get_ground_height(pos.x, pos.z) + 1.0

			var vid = vehicle_ids[randi() % vehicle_ids.size()]
			var tank_scene = get_vehicle_scene(vid)
			var ai_tank = tank_scene.instantiate()
			ai_tank.position = pos
			ai_tank.rotation.y = spawn.basis.get_euler().y + randf_range(-0.3, 0.3)
			ai_tank.is_player_controlled = false
			ai_tank.is_server_controlled = true
			ai_tank.team = team
			ai_tank.nickname = _get_random_nickname()
			_get_main().add_child(ai_tank)

			var data = DataLoader.get_vehicle(vid)
			if not data.is_empty():
				ai_tank.setup_from_data(data)
			attach_ai(ai_tank, team)

func spawn_level_tanks() -> void:
	if NetworkManager.is_client:
		print("[VehicleSpawner] Client mode: skipping local AI spawn, waiting for server sync")
		return
	if not GameManager.level_data.is_empty():
		_spawn_from_level_data()
		return

	var cfg = GameManager.level_config
	var enemy_count = cfg.get("enemy_count", 3)
	var friendly_count = cfg.get("friendly_count", 0)
	var enemy_vehicle = cfg.get("enemy_vehicle", "tank_t34_85")
	var friendly_vehicle = cfg.get("friendly_vehicle", "tank_abrams")
	var map_size = _get_map_config().get("size", 200)

	for i in range(enemy_count):
		_spawn_ai_tank_at(enemy_vehicle, 2, map_size, i)
	for i in range(friendly_count):
		_spawn_ai_tank_at(friendly_vehicle, 1, map_size, i)

	print("[VehicleSpawner] Level spawn: %d enemies (%s), %d friendlies (%s)" % [enemy_count, enemy_vehicle, friendly_count, friendly_vehicle])

func _spawn_from_level_data() -> void:
	var main = _get_main()
	var map_config = _get_map_config()
	var data = GameManager.level_data
	var tanks = data.get("tanks", [])
	var player_spawned = false

	for t in tanks:
		var team = t.get("team", 2)
		var vid = t.get("vehicle_id", "tank_t34_85")
		var pos_arr = t.get("position", [0, 1, 0])
		var rot = t.get("rotation", 0.0)
		var pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		if map_config.has("terrain"):
			var terrain_builder = main.get_node_or_null("TerrainBuilder")
			if terrain_builder:
				pos.y = terrain_builder.get_ground_height(pos.x, pos.z) + 1.0

		if team == 1 and not player_spawned:
			main.player_tank.position = pos
			main.player_tank.rotation.y = rot
			player_spawned = true
			print("[VehicleSpawner] Player from level data at %s" % str(pos))
		else:
			_spawn_ai_tank_exact(vid, team, pos, rot)

	print("[VehicleSpawner] Level data spawn: %d tanks" % tanks.size())

func _spawn_ai_tank_exact(vehicle_id: String, team: int, pos: Vector3, rot_y: float) -> void:
	var map_config = _get_map_config()
	var tank_scene = get_vehicle_scene(vehicle_id)
	if not tank_scene:
		return
	var final_pos = pos
	if map_config.has("terrain"):
		var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")
		if terrain_builder:
			final_pos.y = terrain_builder.get_ground_height(pos.x, pos.z) + 1.0
	var ai_tank = tank_scene.instantiate()
	ai_tank.position = final_pos
	ai_tank.rotation.y = rot_y
	ai_tank.is_player_controlled = false
	ai_tank.is_server_controlled = true
	ai_tank.team = team
	ai_tank.nickname = _get_random_nickname()
	_get_main().add_child(ai_tank)

	var data = DataLoader.get_vehicle(vehicle_id)
	if not data.is_empty():
		ai_tank.setup_from_data(data)
	attach_ai(ai_tank, team)

func _spawn_ai_tank_at(vehicle_id: String, team: int, map_size: float, index: int, difficulty: int = 1, network_id: String = "") -> void:
	var map_config = _get_map_config()
	var spawn = get_spawn_point(team)
	var offset = Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
	var pos = spawn.origin + offset
	pos.x = clamp(pos.x, -map_size/2 + 10, map_size/2 - 10)
	pos.z = clamp(pos.z, -map_size/2 + 10, map_size/2 - 10)
	if map_config.has("terrain"):
		var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")
		if terrain_builder:
			pos.y = terrain_builder.get_ground_height(pos.x, pos.z) + 1.0

	var tank_scene = get_vehicle_scene(vehicle_id)
	if not tank_scene:
		return
	var ai_tank = tank_scene.instantiate()
	ai_tank.position = pos
	ai_tank.rotation.y = spawn.basis.get_euler().y + randf_range(-0.3, 0.3)
	ai_tank.is_player_controlled = false
	ai_tank.is_server_controlled = true
	ai_tank.team = team
	ai_tank.nickname = _get_random_nickname()
	if network_id != "":
		ai_tank.network_player_id = network_id
	_get_main().add_child(ai_tank)

	var data = DataLoader.get_vehicle(vehicle_id)
	if not data.is_empty():
		ai_tank.setup_from_data(data)
	attach_ai(ai_tank, team, difficulty)

func spawn_public_ai() -> void:
	var map_config = _get_map_config()
	var cfg = GameManager.public_ai_config
	var team1_count = int(cfg.get("team1_count", 0))
	var team1_diff = int(cfg.get("team1_difficulty", 1))
	var team2_count = int(cfg.get("team2_count", 2))
	var team2_diff = int(cfg.get("team2_difficulty", 1))
	var vehicle_ids = ["tank_abrams", "tank_t34_85"]
	var map_size = map_config.get("size", 200)

	for i in range(team1_count):
		var vid = vehicle_ids[i % vehicle_ids.size()]
		_spawn_ai_tank_at(vid, 1, map_size, i, team1_diff, "ai_1_%d" % i)
	for i in range(team2_count):
		var vid = vehicle_ids[(i + 1) % vehicle_ids.size()]
		_spawn_ai_tank_at(vid, 2, map_size, i, team2_diff, "ai_2_%d" % i)
	print("[VehicleSpawner] 公网AI生成: 队伍1 %d辆(难度%d), 队伍2 %d辆(难度%d)" % [team1_count, team1_diff, team2_count, team2_diff])

func get_spawn_point(team: int) -> Transform3D:
	var map_config = _get_map_config()
	var spawn_points = map_config.get("spawn_points", [])
	for sp in spawn_points:
		if sp.get("team", 0) == team:
			var pos = sp.get("position", [0, 1, 0])
			var rot_y = sp.get("rotation", 0)
			var t = Transform3D()
			var y = float(pos[1])
			if map_config.has("terrain"):
				var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")
				if terrain_builder:
					y = terrain_builder.get_ground_height(float(pos[0]), float(pos[2])) + 1.0
			t.origin = Vector3(pos[0], y, pos[2])
			t.basis = Basis(Vector3.UP, deg_to_rad(rot_y))
			return t
	var t = Transform3D()
	var default_y = 1.0
	if map_config.has("terrain"):
		var terrain_builder = _get_main().get_node_or_null("TerrainBuilder")
		if terrain_builder:
			default_y = terrain_builder.get_ground_height(0, 50 if team == 1 else -50) + 1.0
	t.origin = Vector3(0, default_y, 50 if team == 1 else -50)
	t.basis = Basis(Vector3.UP, deg_to_rad(0 if team == 1 else 180))
	return t
