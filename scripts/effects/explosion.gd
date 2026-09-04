extends Node3D
## 爆炸特效 - 火球 + 烟雾 + 点光源 + 冲击波

var fireball: MeshInstance3D = null
var smoke: MeshInstance3D = null
var light: OmniLight3D = null
var shockwave: MeshInstance3D = null
var lifetime: float = 1.5

func _ready() -> void:
	# 火球
	fireball = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	fireball.mesh = sphere
	var fire_mat = StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1, 0.6, 0.1, 1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1, 0.4, 0.0, 1)
	fire_mat.emission_energy_multiplier = 4.0
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fireball.material_override = fire_mat
	fireball.scale = Vector3(0.5, 0.5, 0.5)
	add_child(fireball)

	# 烟雾
	smoke = MeshInstance3D.new()
	var smoke_sphere = SphereMesh.new()
	smoke_sphere.radius = 1.5
	smoke_sphere.height = 3.0
	smoke.mesh = smoke_sphere
	var smoke_mat = StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.3, 0.3, 0.3, 0.6)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.material_override = smoke_mat
	smoke.scale = Vector3(0.3, 0.3, 0.3)
	add_child(smoke)

	# 冲击波（圆环）
	shockwave = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	shockwave.mesh = torus
	var shock_mat = StandardMaterial3D.new()
	shock_mat.albedo_color = Color(1, 0.9, 0.7, 0.8)
	shock_mat.emission_enabled = true
	shock_mat.emission = Color(1, 0.8, 0.5, 1)
	shock_mat.emission_energy_multiplier = 2.0
	shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave.material_override = shock_mat
	shockwave.rotation.x = deg_to_rad(90)
	shockwave.scale = Vector3(0.2, 0.2, 0.2)
	add_child(shockwave)

	# 点光源
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.7, 0.3)
	light.light_energy = 15.0
	light.omni_range = 20.0
	light.shadow_enabled = false
	add_child(light)

	# 动画
	var tween = create_tween()
	tween.set_parallel(true)

	# 火球：快速膨胀然后消失
	tween.tween_property(fireball, "scale", Vector3(3, 3, 3), 0.3)
	tween.tween_property(fireball, "scale", Vector3(4, 4, 4), 0.5)
	tween.tween_property(fireball.material_override, "albedo_color:a", 0.0, 0.8)
	tween.tween_property(fireball.material_override, "emission_energy_multiplier", 0.0, 0.8)

	# 烟雾：缓慢膨胀上升
	tween.tween_property(smoke, "scale", Vector3(4, 4, 4), 1.2)
	tween.tween_property(smoke, "position:y", 2.0, 1.2)
	tween.tween_property(smoke.material_override, "albedo_color:a", 0.0, 1.5)

	# 冲击波：快速扩散消失
	tween.tween_property(shockwave, "scale", Vector3(6, 6, 6), 0.5)
	tween.tween_property(shockwave.material_override, "albedo_color:a", 0.0, 0.5)

	# 光源：快速衰减
	tween.tween_property(light, "light_energy", 0.0, 0.6)

	# 1.5秒后自动释放（用独立Timer，避免parallel模式下callback立即执行）
	get_tree().create_timer(1.5).timeout.connect(queue_free)
