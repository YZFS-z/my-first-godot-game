extends Node3D
class_name Cannon
## 火炮系统 - 处理发射、弹药、后坐力
## 从外部JSON配置加载武器数据

signal fired(weapon_id: String, ammo_type: String)
signal reload_started(reload_time: float)
signal reload_finished()
signal ammo_changed(current: int, max: int)

@export var weapon_id: String = ""
@export var ammo_capacity: int = 42
@export var reload_time: float = 5.0

var weapon_data: Dictionary = {}
var current_ammo: int = 0
var current_ammo_type_index: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0
var muzzle_position: Node3D = null

func _ready() -> void:
	current_ammo = ammo_capacity
	muzzle_position = get_node_or_null("Muzzle") as Node3D
	if weapon_id != "":
		load_weapon_data(weapon_id)

func load_weapon_data(id: String) -> void:
	weapon_data = DataLoader.get_weapon(id)
	if not weapon_data.is_empty():
		reload_time = weapon_data.get("reload_time", reload_time)
		print("[Cannon] Loaded weapon: %s" % weapon_data.get("name", id))

func fire() -> bool:
	if is_reloading or current_ammo <= 0:
		return false

	current_ammo -= 1
	ammo_changed.emit(current_ammo, ammo_capacity)

	var ammo_types = weapon_data.get("ammo_types", [])
	var ammo_type = {}
	if current_ammo_type_index < ammo_types.size():
		ammo_type = ammo_types[current_ammo_type_index]

	fired.emit(weapon_id, ammo_type.get("id", "default"))

	# 生成弹丸
	_spawn_projectile(ammo_type)

	# 开始装填
	_start_reload()
	return true

func _spawn_projectile(ammo_type: Dictionary) -> void:
	if not muzzle_position:
		return

	var projectile_scene = load("res://scenes/projectile.tscn")
	if not projectile_scene:
		return

	var projectile = projectile_scene.instantiate()
	projectile.global_position = muzzle_position.global_position
	projectile.global_rotation = muzzle_position.global_rotation
	projectile.set_ammo_data(ammo_type)
	get_tree().current_scene.add_child(projectile)

func _start_reload() -> void:
	is_reloading = true
	reload_timer = reload_time
	reload_started.emit(reload_time)
	var tween = create_tween()
	tween.tween_interval(reload_time)
	tween.tween_callback(_finish_reload)

func _finish_reload() -> void:
	is_reloading = false
	reload_finished.emit()

func switch_ammo_type(index: int) -> void:
	var ammo_types = weapon_data.get("ammo_types", [])
	if index >= 0 and index < ammo_types.size():
		current_ammo_type_index = index
		print("[Cannon] Switched to: %s" % ammo_types[index].get("name", "Unknown"))

func get_current_ammo_type() -> Dictionary:
	var ammo_types = weapon_data.get("ammo_types", [])
	if current_ammo_type_index < ammo_types.size():
		return ammo_types[current_ammo_type_index]
	return {}

func get_reload_progress() -> float:
	if not is_reloading:
		return 1.0
	return 1.0 - (reload_timer / reload_time)
