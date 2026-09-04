extends Node3D
## 特效管理器 - 全局单例
## 提供统一的特效播放接口，自动管理特效生命周期

const MUZZLE_FLASH = preload("res://scenes/effects/muzzle_flash.tscn")
const HIT_SPARK = preload("res://scenes/effects/hit_spark.tscn")
const EXPLOSION = preload("res://scenes/effects/explosion.tscn")
const FIRE_SMOKE = preload("res://scenes/effects/fire_smoke.tscn")

# 音效文件路径（预留mp3，文件存在就播放，不存在跳过）
const SOUND_FIRE = "res://assets/sounds/fire.mp3"
const SOUND_ARTILLERY = "res://assets/sounds/artillery.mp3"
const SOUND_SMOKE = "res://assets/sounds/smoke.mp3"

# 音效流缓存
static var _sound_cache: Dictionary = {}

static func _load_sound(path: String) -> AudioStream:
	"""加载音效流，带缓存；文件不存在返回null"""
	if _sound_cache.has(path):
		return _sound_cache[path]
	if ResourceLoader.exists(path):
		_sound_cache[path] = load(path)
	else:
		_sound_cache[path] = null
	return _sound_cache[path]

func play_sound_3d(sound_path: String, position: Vector3, volume_db: float = 0.0) -> void:
	"""播放3D音效（有位置感），文件不存在则跳过"""
	var stream = _load_sound(sound_path)
	if not stream:
		return
	var player = AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = position
	player.volume_db = volume_db
	player.bus = "Master"
	player.finished.connect(player.queue_free)
	get_tree().current_scene.add_child(player)
	player.play()

func play_sound_2d(sound_path: String, volume_db: float = 0.0) -> void:
	"""播放2D音效（全局，无位置感），文件不存在则跳过"""
	var stream = _load_sound(sound_path)
	if not stream:
		return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Master"
	player.finished.connect(player.queue_free)
	get_tree().current_scene.add_child(player)
	player.play()

func play_muzzle_flash(spawn_pos: Vector3, spawn_rotation: Vector3 = Vector3.ZERO, scale: float = 1.0) -> void:
	"""播放炮口焰"""
	var effect = MUZZLE_FLASH.instantiate()
	effect.position = spawn_pos
	effect.rotation = spawn_rotation
	effect.scale = Vector3(scale, scale, scale)
	get_tree().current_scene.add_child(effect)

func play_hit_spark(spawn_pos: Vector3, normal: Vector3 = Vector3.UP, color: Color = Color(1, 0.8, 0.3)) -> void:
	"""播放命中火花"""
	var effect = HIT_SPARK.instantiate()
	effect.position = spawn_pos
	effect.look_at_from_position(spawn_pos, spawn_pos + normal, Vector3.UP)
	effect.set_spark_color(color)
	get_tree().current_scene.add_child(effect)

func play_explosion(spawn_pos: Vector3, scale: float = 1.0) -> void:
	"""播放爆炸"""
	var effect = EXPLOSION.instantiate()
	effect.position = spawn_pos
	effect.scale = Vector3(scale, scale, scale)
	get_tree().current_scene.add_child(effect)

func play_fire_smoke(parent: Node, local_position: Vector3 = Vector3.ZERO) -> Node:
	"""播放持续燃烧烟雾（返回节点引用，可手动停止）"""
	var effect = FIRE_SMOKE.instantiate()
	effect.position = local_position
	parent.add_child(effect)
	return effect
