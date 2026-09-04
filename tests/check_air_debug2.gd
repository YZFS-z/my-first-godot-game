extends SceneTree
## Debug: replicate brake test phase 1 flow

var _plane: Node = null
var _data: Dictionary = {}
var _step := 0
var _phase := 0
var _ground_frames: int = 0
var _armed: bool = false

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

func _h_speed() -> float:
	return Vector3(_plane.velocity.x, 0.0, _plane.velocity.z).length()

func _physics_process(delta: float) -> bool:
	_step += 1
	match _phase:
		0:
			if _step < 15 or _plane.damage_system == null:
				return false
			_plane.setup_from_data(_data)
			_plane.throttle = 0.0
			_plane.velocity = Vector3(20.0, 0.0, 0.0)
			_plane.rotation.y = deg_to_rad(-90.0)
			_plane.target_yaw = deg_to_rad(-90.0)
			_plane.input_throttle = 0.0
			_phase = 1
			_step = 0
		1:
			if not _plane.is_on_floor():
				if not _armed:
					pass
				else:
					_armed = false
				return false
			if not _armed:
				_armed = true
				_ground_frames = 0
				print("Armed at step %d" % _step)
				return false
			_ground_frames += 1
			if _ground_frames <= 5:
				return false
			if _ground_frames == 6:
				_plane.velocity = Vector3(20.0, 0.0, 0.0)
				print("GF=6: set vel=(20,0,0), on_floor=%s" % _plane.is_on_floor())
				return false
			if _ground_frames <= 6 + 30:
				if _ground_frames == 7 or _ground_frames == 37:
					print("GF=%d: vel=%s, h_spd=%.3f, on_floor=%s, throttle=%.2f" % [
						_ground_frames, str(_plane.velocity), _h_speed(),
						_plane.is_on_floor(), _plane.throttle])
				return false
			var v_no_brake: float = _h_speed()
			print("RESULT: h_spd=%.3f (expected ~19.7)" % v_no_brake)
			quit()
			return true
	return false
