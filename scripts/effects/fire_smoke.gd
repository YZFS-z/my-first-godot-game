extends Node3D
## 持续燃烧特效 - 火焰 + 烟雾，用于击毁后燃烧的载具

var fire_particles: Array = []
var smoke_particles: Array = []
var is_burning: bool = true
var burn_duration: float = 30.0  # 燃烧持续时间
var burn_timer: float = 0.0
var spawn_timer: float = 0.0

func _ready() -> void:
	# 预生成一些粒子
	for i in range(8):
		var fire = _create_particle(Color(1, 0.5, 0.1), 0.4, 0.3)
		fire.visible = false
		fire_particles.append(fire)
	for i in range(6):
		var smoke = _create_particle(Color(0.2, 0.2, 0.2), 1.0, 0.6)
		smoke.visible = false
		smoke_particles.append(smoke)

func _create_particle(color: Color, size: float, opacity: float) -> MeshInstance3D:
	var p = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2
	p.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, opacity)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = mat
	add_child(p)
	return p

func _process(delta: float) -> void:
	if not is_burning:
		return

	burn_timer += delta
	if burn_timer > burn_duration:
		stop_burning()
		return

	# 生成新粒子
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = 0.05
		_spawn_fire()
		_spawn_smoke()

	# 更新粒子
	for p in fire_particles:
		if p.visible:
			p.position.y += delta * randf_range(1.5, 3.0)
			p.scale += Vector3(delta * 2, delta * 2, delta * 2)
			p.material_override.albedo_color.a -= delta * 1.5
			if p.material_override.albedo_color.a <= 0:
				p.visible = false

	for p in smoke_particles:
		if p.visible:
			p.position.y += delta * randf_range(0.8, 1.5)
			p.position.x += delta * randf_range(-0.3, 0.3)
			p.position.z += delta * randf_range(-0.3, 0.3)
			p.scale += Vector3(delta * 1.5, delta * 1.5, delta * 1.5)
			p.material_override.albedo_color.a -= delta * 0.3
			if p.material_override.albedo_color.a <= 0:
				p.visible = false

func _spawn_fire() -> void:
	for p in fire_particles:
		if not p.visible:
			p.visible = true
			p.position = Vector3(randf_range(-0.5, 0.5), randf_range(0, 0.5), randf_range(-0.5, 0.5))
			p.scale = Vector3(randf_range(0.5, 1.0), randf_range(0.5, 1.0), randf_range(0.5, 1.0))
			p.material_override.albedo_color.a = randf_range(0.6, 1.0)
			break

func _spawn_smoke() -> void:
	for p in smoke_particles:
		if not p.visible:
			p.visible = true
			p.position = Vector3(randf_range(-0.8, 0.8), randf_range(0.5, 1.0), randf_range(-0.8, 0.8))
			p.scale = Vector3(randf_range(0.8, 1.5), randf_range(0.8, 1.5), randf_range(0.8, 1.5))
			p.material_override.albedo_color.a = randf_range(0.3, 0.6)
			break

func stop_burning() -> void:
	is_burning = false
	# 淡出所有粒子
	for p in fire_particles:
		p.visible = false
	for p in smoke_particles:
		p.visible = false
	queue_free()
