extends Node
## 数据加载器 - 从外部JSON文件加载载具、武器等配置数据
## 所有数据放在 res://data/ 目录下，方便后续更新和MOD支持
## 支持热重载：运行时修改JSON后调用 reload() 即可更新

signal data_loaded(data_type: String)
signal load_error(file_path: String, error_msg: String)

var vehicle_data: Dictionary = {}
var weapon_data: Dictionary = {}
var map_data: Dictionary = {}
var is_loaded: bool = false

const VEHICLE_DIR = "res://data/vehicles/"
const WEAPON_DIR = "res://data/weapons/"
const MAP_DIR = "res://data/maps/"
const CUSTOM_MAP_DIR = "user://data/maps/"  # 导出后可写的自定义地图目录
const CUSTOM_VEHICLE_DIR = "user://data/vehicles/"  # 导出后可写的自定义载具目录

func _ready() -> void:
	load_all_data()

func load_all_data() -> void:
	load_vehicles()
	load_weapons()
	load_maps()
	is_loaded = true
	print("[DataLoader] All data loaded. Vehicles: %d, Weapons: %d, Maps: %d" % [vehicle_data.size(), weapon_data.size(), map_data.size()])

func load_vehicles() -> void:
	vehicle_data.clear()
	# 先加载内置载具
	var files = _list_json_files(VEHICLE_DIR)
	for file in files:
		var data = _load_json(VEHICLE_DIR + file)
		if data and data.has("id"):
			vehicle_data[data["id"]] = data
			print("[DataLoader] Loaded builtin vehicle: %s (%s)" % [data.get("name", "Unknown"), data["id"]])
	# 再加载自定义载具（user://，导出后可写）
	var custom_files = _list_json_files(CUSTOM_VEHICLE_DIR)
	for file in custom_files:
		var data = _load_json(CUSTOM_VEHICLE_DIR + file)
		if data and data.has("id"):
			if not data.has("source"):
				data["source"] = "custom"
			vehicle_data[data["id"]] = data
			print("[DataLoader] Loaded custom vehicle: %s (%s)" % [data.get("name", "Unknown"), data["id"]])
	data_loaded.emit("vehicle")

func load_weapons() -> void:
	weapon_data.clear()
	var files = _list_json_files(WEAPON_DIR)
	for file in files:
		var data = _load_json(WEAPON_DIR + file)
		if data and data.has("id"):
			weapon_data[data["id"]] = data
	data_loaded.emit("weapon")

func get_vehicle(vehicle_id: String) -> Dictionary:
	return vehicle_data.get(vehicle_id, {})

func get_all_vehicles() -> Dictionary:
	return vehicle_data

func get_weapon(weapon_id: String) -> Dictionary:
	return weapon_data.get(weapon_id, {})

func get_all_weapons() -> Dictionary:
	return weapon_data

func load_maps() -> void:
	map_data.clear()
	# 先加载内置地图
	var files = _list_json_files(MAP_DIR)
	for file in files:
		var data = _load_json(MAP_DIR + file)
		if data and data.has("id"):
			map_data[data["id"]] = data
			print("[DataLoader] Loaded builtin map: %s (%s)" % [data.get("name", "Unknown"), data["id"]])
	# 再加载自定义地图（user://，导出后可写）
	var custom_files = _list_json_files(CUSTOM_MAP_DIR)
	for file in custom_files:
		var data = _load_json(CUSTOM_MAP_DIR + file)
		if data and data.has("id"):
			# 自定义地图标记为 custom（如果未标记）
			if not data.has("source"):
				data["source"] = "custom"
			map_data[data["id"]] = data
			print("[DataLoader] Loaded custom map: %s (%s)" % [data.get("name", "Unknown"), data["id"]])
	data_loaded.emit("map")

func get_map(map_id: String) -> Dictionary:
	return map_data.get(map_id, {})

func get_all_maps() -> Dictionary:
	return map_data

func is_vehicle_builtin(vehicle_id: String) -> bool:
	"""判断载具是否为内置（source == "builtin"），不存在或无标记视为内置"""
	var v = vehicle_data.get(vehicle_id, {})
	if v.is_empty():
		return true
	return v.get("source", "builtin") == "builtin"

func is_map_builtin(map_id: String) -> bool:
	"""判断地图是否为内置（source == "builtin"），不存在或无标记视为内置"""
	var m = map_data.get(map_id, {})
	if m.is_empty():
		return true
	return m.get("source", "builtin") == "builtin"

func get_builtin_vehicles() -> Dictionary:
	"""获取所有内置载具"""
	var result = {}
	for vid in vehicle_data.keys():
		if is_vehicle_builtin(vid):
			result[vid] = vehicle_data[vid]
	return result

func get_custom_vehicles() -> Dictionary:
	"""获取所有自定义载具"""
	var result = {}
	for vid in vehicle_data.keys():
		if not is_vehicle_builtin(vid):
			result[vid] = vehicle_data[vid]
	return result

func get_builtin_maps() -> Dictionary:
	"""获取所有内置地图"""
	var result = {}
	for mid in map_data.keys():
		if is_map_builtin(mid):
			result[mid] = map_data[mid]
	return result

func get_custom_maps() -> Dictionary:
	"""获取所有自定义地图"""
	var result = {}
	for mid in map_data.keys():
		if not is_map_builtin(mid):
			result[mid] = map_data[mid]
	return result

func reload() -> void:
	"""热重载所有数据"""
	load_all_data()

func _list_json_files(dir_path: String) -> Array:
	var files = []
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		load_error.emit(dir_path, "Cannot open directory")
	return files

func _load_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		load_error.emit(file_path, "File not found")
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		load_error.emit(file_path, "Cannot open file")
		return {}
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error.emit(file_path, "Invalid JSON format")
		return {}
	return parsed
