extends SceneTree
## Quick debug: verify airplane ground physics works

var _plane: Node = null
var _data: Dictionary = {}
var _step := 0

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _initialize() -> void:
	_data = _load_json("res://data/vehicles/plane_a10.json")
	_plane = load("res://scenes/airplane.tscn").instantiate()
	_plane.is_player_controlled = true
	_plane.is_server_controlled = false
	_plane.team = 1
	root.add_child(_plane)
	_plane.global_position = Vector3(1.0, 2.0, 0)
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 8000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

func _physics_process(delta: float) -> bool:
	_step += 1
	if _step < 15 or _plane.damage_system == null:
		return false
	if _step == 15:
		_plane.setup_from_data(_data)
		_plane.throttle = 0.0
		_plane.velocity = Vector3(20.0, 0.0, 0.0)
		_plane.rotation.y = deg_to_rad(-90.0)
		_plane.target_yaw = deg_to_rad(-90.0)
		_plane.input_throttle = 0.0
		print("Step 15: setup done, vel=%s, on_floor=%s" % [str(_plane.velocity), _plane.is_on_floor()])
		return false
	if _step <= 45:
		if _step % 10 == 0:
			print("Step %d: vel=%s, h_spd=%.3f, on_floor=%s, throttle=%.2f" % [
				_step, str(_plane.velocity), Vector3(_plane.velocity.x, 0, _plane.velocity.z).length(),
				_plane.is_on_floor(), _plane.throttle])
		return false
	print("Final: vel=%s, h_spd=%.3f" % [str(_plane.velocity), Vector3(_plane.velocity.x, 0, _plane.velocity.z).length()])
	quit()
	return true
