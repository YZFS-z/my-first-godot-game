## 烟幕遮蔽效果 - 3个并排半透明球体阻挡视野
extends Node3D

var radius: float = 6.0
var duration: float = 20.0
var _timer: float = 0.0
var _smoke_meshes: Array = []
const SMOKE_ALPHA: float = 0.85  # 透明度（接近不透明）

func _ready() -> void:
	# 创建3个并排的半透明球体模拟烟幕带
	var ball_radius = radius * 1.1
	var spacing = radius * 1.5
	for i in range(3):
		var smoke_mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = ball_radius
		sphere.height = ball_radius * 2
		smoke_mesh.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.5, 0.5, SMOKE_ALPHA)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smoke_mesh.material_override = mat
		# 3个球横向并排（X轴方向），中间球在原点
		smoke_mesh.position.x = (i - 1) * spacing
		add_child(smoke_mesh)
		_smoke_meshes.append(smoke_mesh)
	# 缓慢上升动画
	var tween = create_tween()
	tween.tween_property(self, "position:y", 1.0, duration).set_ease(Tween.EASE_IN_OUT)
	print("[SmokeScreen] 烟幕已部署, 3球并排, 半径%.1f, 持续%.1fs" % [radius, duration])

func _process(delta: float) -> void:
	_timer += delta
	# 快结束时淡出
	if _timer > duration - 3.0:
		var fade = 1.0 - (_timer - (duration - 3.0)) / 3.0
		for m in _smoke_meshes:
			if m and m.material_override:
				m.material_override.albedo_color.a = SMOKE_ALPHA * max(0, fade)
	if _timer >= duration:
		queue_free()
