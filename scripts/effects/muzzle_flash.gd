extends Node3D
## 炮口焰特效 - 明亮闪光 + 点光源，快速缩放淡出

var flash_mesh: MeshInstance3D = null
var light: OmniLight3D = null
var lifetime: float = 0.15

func _ready() -> void:
	# 闪光球体
	flash_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	flash_mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.9, 0.5, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.2, 1)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mesh.material_override = mat
	add_child(flash_mesh)

	# 点光源
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.8, 0.4)
	light.light_energy = 8.0
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)

	# 动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_mesh, "scale", Vector3(2.5, 2.5, 2.5), lifetime * 0.3)
	tween.tween_property(flash_mesh, "scale", Vector3(0.1, 0.1, 0.1), lifetime * 0.7)
	tween.tween_property(flash_mesh.material_override, "albedo_color:a", 0.0, lifetime)
	tween.tween_property(light, "light_energy", 0.0, lifetime)
	tween.tween_callback(queue_free)

func _process(_delta: float) -> void:
	# 持续面向摄像机（billboard效果）
	if flash_mesh and get_viewport():
		var cam = get_viewport().get_camera_3d()
		if cam:
			flash_mesh.look_at_from_position(flash_mesh.global_position, cam.global_position, Vector3.UP)
