extends Node3D
## 命中火花特效 - 多个小粒子向外飞溅

var spark_color: Color = Color(1, 0.8, 0.3)
var sparks: Array = []
var lifetime: float = 0.5

func _ready() -> void:
	# 生成10-15个火花
	var count = randi_range(10, 15)
	for i in range(count):
		var spark = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.05, 0.05, 0.15)
		spark.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = spark_color
		mat.emission_enabled = true
		mat.emission = spark_color
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = mat
		add_child(spark)
		# 随机方向和速度
		var dir = Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)).normalized()
		var speed = randf_range(3, 8)
		sparks.append({"node": spark, "velocity": dir * speed, "life": randf_range(0.2, 0.5)})

func _process(delta: float) -> void:
	var alive = false
	for spark in sparks:
		if spark.life > 0:
			alive = true
			spark.life -= delta
			spark.velocity.y -= 15.0 * delta  # 重力
			spark.node.position += spark.velocity * delta
			spark.node.rotation += Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)) * delta
			var alpha = clamp(spark.life / 0.5, 0, 1)
			spark.node.material_override.albedo_color.a = alpha
			spark.node.material_override.emission_energy_multiplier = 3.0 * alpha
	if not alive:
		queue_free()

func set_spark_color(color: Color) -> void:
	spark_color = color
