extends Control
## 弹药编辑器 - 编辑武器JSON中的弹药参数

@onready var weapon_option: OptionButton = $Panel/VBox/TopRow/WeaponOption
@onready var reload_button: Button = $Panel/VBox/TopRow/ReloadButton
@onready var ammo_list: ItemList = $Panel/VBox/AmmoList
@onready var name_input: LineEdit = $Panel/VBox/EditGrid/NameInput
@onready var type_option: OptionButton = $Panel/VBox/EditGrid/TypeOption
@onready var damage_input: LineEdit = $Panel/VBox/EditGrid/DamageInput
@onready var pen_input: LineEdit = $Panel/VBox/EditGrid/PenInput
@onready var speed_input: LineEdit = $Panel/VBox/EditGrid/SpeedInput
@onready var count_input: LineEdit = $Panel/VBox/EditGrid/CountInput
@onready var exp_mass_input: LineEdit = $Panel/VBox/EditGrid/ExpMassInput
@onready var splash_input: LineEdit = $Panel/VBox/EditGrid/SplashInput
@onready var save_button: Button = $Panel/VBox/ButtonRow/SaveButton
@onready var close_button: Button = $Panel/VBox/ButtonRow/CloseButton
@onready var status_label: Label = $Panel/VBox/StatusLabel

var weapon_ids: Array = []
var current_weapon_id: String = ""
var current_weapon_data: Dictionary = {}
var current_ammo_index: int = -1
var _suppress: bool = false

const AMMO_TYPES := ["kinetic", "kinetic_explosive", "explosive", "chemical"]
const AMMO_TYPE_NAMES := {
	"kinetic": "动能弹(AP/APFSDS)",
	"kinetic_explosive": "爆破穿甲弹(APHE)",
	"explosive": "高爆弹(HE)",
	"chemical": "化学能弹(HEAT)"
}

func _ready() -> void:
	_populate_types()
	_populate_weapons()
	weapon_option.item_selected.connect(_on_weapon_selected)
	ammo_list.item_selected.connect(_on_ammo_selected)
	save_button.pressed.connect(_on_save)
	close_button.pressed.connect(_on_close)
	reload_button.pressed.connect(_on_reload)

func _populate_types() -> void:
	type_option.clear()
	for t in AMMO_TYPES:
		type_option.add_item(AMMO_TYPE_NAMES.get(t, t))
		type_option.set_item_metadata(type_option.item_count - 1, t)

func _populate_weapons() -> void:
	weapon_option.clear()
	weapon_ids.clear()
	# 扫描武器目录
	var dir = DirAccess.open("res://data/weapons/")
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".json"):
				var id = file.get_basename()
				weapon_ids.append(id)
				var data = _load_weapon(id)
				weapon_option.add_item(data.get("name", id))
			file = dir.get_next()
		dir.list_dir_end()
	if weapon_ids.size() > 0:
		weapon_option.select(0)
		_on_weapon_selected(0)

func _load_weapon(id: String) -> Dictionary:
	var path = "res://data/weapons/%s.json" % id
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var text = f.get_as_text()
			f.close()
			return JSON.parse_string(text)
	return {}

func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= weapon_ids.size():
		return
	current_weapon_id = weapon_ids[index]
	current_weapon_data = _load_weapon(current_weapon_id)
	_populate_ammo_list()

func _populate_ammo_list() -> void:
	ammo_list.clear()
	var types = current_weapon_data.get("ammo_types", [])
	for ammo in types:
		ammo_list.add_item("%s (%s)" % [ammo.get("name", "?"), ammo.get("type", "?")])
	if types.size() > 0:
		ammo_list.select(0)
		_on_ammo_selected(0)
	else:
		_clear_fields()

func _on_ammo_selected(index: int) -> void:
	_suppress = true
	current_ammo_index = index
	var types = current_weapon_data.get("ammo_types", [])
	if index < 0 or index >= types.size():
		_clear_fields()
		_suppress = false
		return
	var ammo = types[index]
	name_input.text = ammo.get("name", "")
	var ammo_type = ammo.get("type", "kinetic")
	for i in range(type_option.item_count):
		if type_option.get_item_metadata(i) == ammo_type:
			type_option.select(i)
			break
	damage_input.text = str(ammo.get("damage", 100))
	pen_input.text = str(ammo.get("penetration", 300))
	speed_input.text = str(ammo.get("muzzle_velocity", 800))
	count_input.text = str(ammo.get("count", 20))
	exp_mass_input.text = str(ammo.get("explosive_mass", 0))
	splash_input.text = str(ammo.get("splash_radius", 0))
	_suppress = false

func _clear_fields() -> void:
	name_input.text = ""
	damage_input.text = ""
	pen_input.text = ""
	speed_input.text = ""
	count_input.text = ""
	exp_mass_input.text = ""
	splash_input.text = ""

func _on_save() -> void:
	if current_ammo_index < 0:
		status_label.text = "请先选择弹药"
		return
	var types = current_weapon_data.get("ammo_types", [])
	if current_ammo_index >= types.size():
		return
	var ammo = types[current_ammo_index]
	ammo["name"] = name_input.text
	ammo["type"] = type_option.get_item_metadata(type_option.selected)
	ammo["damage"] = float(damage_input.text) if damage_input.text.is_valid_float() else 100.0
	ammo["penetration"] = float(pen_input.text) if pen_input.text.is_valid_float() else 300.0
	ammo["muzzle_velocity"] = float(speed_input.text) if speed_input.text.is_valid_float() else 800.0
	ammo["count"] = int(count_input.text) if count_input.text.is_valid_int() else 20
	ammo["explosive_mass"] = float(exp_mass_input.text) if exp_mass_input.text.is_valid_float() else 0.0
	ammo["splash_radius"] = float(splash_input.text) if splash_input.text.is_valid_float() else 0.0

	# 写回JSON
	var path = "res://data/weapons/%s.json" % current_weapon_id
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(current_weapon_data, "  "))
		f.close()
		status_label.text = "已保存: %s" % current_weapon_data.get("name", current_weapon_id)
		# 重新加载数据
		DataLoader.reload()
	else:
		status_label.text = "保存失败！"

func _on_reload() -> void:
	_populate_weapons()
	status_label.text = "已重新加载武器数据"

func _on_close() -> void:
	queue_free()
