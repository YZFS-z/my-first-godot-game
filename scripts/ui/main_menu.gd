extends Control
## 主菜单 - 多级导航：主界面 → 开始/编辑子菜单 → 战斗设置/编辑器

# ── 主界面按钮 ──
@onready var start_button: Button = $MenuArea/MainPanel/StartButton
@onready var settings_button: Button = $MenuArea/MainPanel/SettingsButton
@onready var edit_button: Button = $MenuArea/MainPanel/EditButton
@onready var exit_button: Button = $MenuArea/MainPanel/ExitButton

# ── 开始子菜单 ──
@onready var start_panel: PanelContainer = $StartPanel
@onready var single_button: Button = $StartPanel/VBox/SingleButton
@onready var lan_button: Button = $StartPanel/VBox/LanButton
@onready var public_button: Button = $StartPanel/VBox/PublicButton
@onready var start_back_button: Button = $StartPanel/VBox/StartBackButton
@onready var public_panel: Panel = $PublicPanel
@onready var public_back_button: Button = $PublicPanel/PublicVBox/PublicBackButton

# ── 编辑子菜单 ──
@onready var edit_panel: PanelContainer = $EditPanel
@onready var map_edit_button: Button = $EditPanel/VBox/MapEditButton
@onready var vehicle_edit_button: Button = $EditPanel/VBox/VehicleEditButton
@onready var ammo_edit_button: Button = $EditPanel/VBox/AmmoEditButton
@onready var edit_back_button: Button = $EditPanel/VBox/EditBackButton

# ── 背景 ──
@onready var background_image: TextureRect = $BackgroundImage
@onready var background_dim: ColorRect = $BackgroundDim

# ── 关卡设置面板 ──
@onready var level_panel: Panel = $LevelPanel
@onready var level_select_option: OptionButton = $LevelPanel/LevelVBox/LevelSelectRow/LevelSelectOption
@onready var level_editor_button: Button = $LevelPanel/LevelVBox/LevelSelectRow/LevelEditorButton
@onready var difficulty_option: OptionButton = $LevelPanel/LevelVBox/DifficultyRow/DifficultyOption
@onready var level_info: RichTextLabel = $LevelPanel/LevelVBox/LevelInfo
@onready var level_start_button: Button = $LevelPanel/LevelVBox/LevelButtonRow/LevelStartButton
@onready var level_back_button: Button = $LevelPanel/LevelVBox/LevelButtonRow/LevelBackButton

# ── 战斗设置面板（多人联机） ──
@onready var battle_panel: Panel = $BattlePanel
@onready var battle_title: Label = $BattlePanel/Scroll/BattleVBox/BattleTitle
@onready var vehicle_list: ItemList = $BattlePanel/Scroll/BattleVBox/VehicleRow/VehicleList
@onready var vehicle_info: RichTextLabel = $BattlePanel/Scroll/BattleVBox/VehicleRow/VehicleInfo
@onready var map_list: ItemList = $BattlePanel/Scroll/BattleVBox/MapRow/MapList
@onready var map_info: RichTextLabel = $BattlePanel/Scroll/BattleVBox/MapRow/MapInfo
@onready var map_row: HBoxContainer = $BattlePanel/Scroll/BattleVBox/MapRow
@onready var mode_option: OptionButton = $BattlePanel/Scroll/BattleVBox/NetworkRow/ModeOption
@onready var ip_input: LineEdit = $BattlePanel/Scroll/BattleVBox/NetworkRow/IPInput
@onready var port_input: LineEdit = $BattlePanel/Scroll/BattleVBox/NetworkRow/PortInput
@onready var enemy_ai_row: HBoxContainer = $BattlePanel/Scroll/BattleVBox/EnemyAIRow
@onready var enemy_ai_slider: HSlider = $BattlePanel/Scroll/BattleVBox/EnemyAIRow/EnemyAISlider
@onready var enemy_ai_count: Label = $BattlePanel/Scroll/BattleVBox/EnemyAIRow/EnemyAICount
@onready var friendly_ai_row: HBoxContainer = $BattlePanel/Scroll/BattleVBox/FriendlyAIRow
@onready var friendly_ai_slider: HSlider = $BattlePanel/Scroll/BattleVBox/FriendlyAIRow/FriendlyAISlider
@onready var friendly_ai_count: Label = $BattlePanel/Scroll/BattleVBox/FriendlyAIRow/FriendlyAICount
@onready var team1_button: Button = $BattlePanel/Scroll/BattleVBox/TeamRow/Team1Button
@onready var team2_button: Button = $BattlePanel/Scroll/BattleVBox/TeamRow/Team2Button
@onready var room_list_row: VBoxContainer = $BattlePanel/Scroll/BattleVBox/RoomListRow
@onready var room_list: ItemList = $BattlePanel/Scroll/BattleVBox/RoomListRow/RoomList
@onready var refresh_room_button: Button = $BattlePanel/Scroll/BattleVBox/RoomListRow/RefreshButton
@onready var air_boundary_input: LineEdit = $BattlePanel/Scroll/BattleVBox/AirBoundaryRow/AirBoundaryInput
@onready var battle_start_button: Button = $BattlePanel/Scroll/BattleVBox/BattleButtonRow/BattleStartButton
@onready var battle_back_button: Button = $BattlePanel/Scroll/BattleVBox/BattleButtonRow/BattleBackButton

@onready var status_label: Label = $StatusLabel

var selected_vehicle_id: String = ""
var selected_map_id: String = ""
var selected_team: int = 1  # 局域网联机选择的队伍
var vehicle_ids: Array = []

# ── 地图同步状态（用成员变量而非 lambda 捕获局部，避免值捕获导致超时误判） ──
var _map_received := false
var _received_map_id := ""

func _on_map_received(mid: String) -> void:
	_received_map_id = mid
	_map_received = true
var map_ids: Array = []
var is_multiplayer: bool = false  # 当前是否为多人模式

# ── 背景预设 ──
const BG_PRESETS := {
	"classic": {"name": "深色经典", "colors": [], "dim": 0.25},
	"desert": {"name": "沙漠黄昏", "colors": [Color(0.85, 0.55, 0.25), Color(0.35, 0.2, 0.12)], "dim": 0.25},
	"forest": {"name": "欧洲森林", "colors": [Color(0.3, 0.45, 0.25), Color(0.12, 0.18, 0.12)], "dim": 0.3},
	"snow": {"name": "寒带雪原", "colors": [Color(0.8, 0.88, 0.95), Color(0.45, 0.55, 0.7)], "dim": 0.15},
	"night": {"name": "夜幕战场", "colors": [Color(0.1, 0.1, 0.35), Color(0.02, 0.02, 0.08)], "dim": 0.2},
	"ruins": {"name": "废墟都市", "colors": [Color(0.5, 0.45, 0.4), Color(0.15, 0.13, 0.12)], "dim": 0.35},
}

func _apply_background() -> void:
	var bg_id = SettingsManager.get_menu_background()
	if not BG_PRESETS.has(bg_id):
		bg_id = "classic"
	var preset = BG_PRESETS[bg_id]

	# 优先尝试加载 assets/backgrounds/ 中的真实图片
	var image_path = _find_background_image(bg_id)
	if image_path != "":
		var tex = load(image_path)
		if tex:
			background_image.visible = true
			background_image.texture = tex
			background_dim.color = Color(0.06, 0.07, 0.1, preset.dim)
			return

	# 兜底：渐变背景
	if preset.colors.is_empty():
		background_image.texture = null
		background_image.visible = false
		background_dim.color = Color(0.1, 0.12, 0.16, 1.0)
	else:
		background_image.visible = true
		var grad = Gradient.new()
		grad.set_color(0, preset.colors[0])
		grad.set_color(1, preset.colors[1])
		var tex = GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 256
		tex.height = 256
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(0, 1)
		background_image.texture = tex
		background_dim.color = Color(0.06, 0.07, 0.1, preset.dim)

func _find_background_image(bg_id: String) -> String:
	"""在 assets/backgrounds/ 中查找对应预设的图片文件"""
	for ext in [".png", ".jpg", ".jpeg", ".webp"]:
		var path = "res://assets/backgrounds/%s%s" % [bg_id, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await get_tree().process_frame
	_apply_background()
	_populate_vehicles()
	_populate_maps()
	_setup_network_options()
	_connect_signals()

	# 默认选择
	if vehicle_ids.size() > 0:
		vehicle_list.select(0)
		_on_vehicle_selected(0)
	if map_ids.size() > 0:
		map_list.select(0)
		_on_map_selected(0)

	ip_input.text = "127.0.0.1"
	port_input.text = "7777"

	# 命令行 --mobile
	if "--mobile" in OS.get_cmdline_args():
		SettingsManager.set_mobile_mode(true)
		GameManager.force_mobile = true
		status_label.text = "移动端测试模式已启用"

func _connect_signals() -> void:
	# 主界面
	start_button.pressed.connect(_show_start_panel)
	settings_button.pressed.connect(_on_settings)
	edit_button.pressed.connect(_show_edit_panel)
	exit_button.pressed.connect(_on_exit)
	# 开始子菜单
	single_button.pressed.connect(_on_level)
	lan_button.pressed.connect(_on_lan_multiplayer)
	public_button.pressed.connect(_on_public_multiplayer)
	start_back_button.pressed.connect(_show_main_panel)
	public_back_button.pressed.connect(_show_start_panel)
	# 编辑子菜单
	map_edit_button.pressed.connect(_on_map_editor)
	vehicle_edit_button.pressed.connect(_on_vehicle_editor)
	ammo_edit_button.pressed.connect(_on_ammo_editor)
	edit_back_button.pressed.connect(_show_main_panel)
	# 关卡设置
	level_select_option.item_selected.connect(_on_saved_level_selected)
	difficulty_option.item_selected.connect(_on_difficulty_changed)
	level_editor_button.pressed.connect(_on_level_editor)
	level_start_button.pressed.connect(_on_level_start)
	level_back_button.pressed.connect(_show_start_panel)
	# 战斗设置（多人）
	vehicle_list.item_selected.connect(_on_vehicle_selected)
	map_list.item_selected.connect(_on_map_selected)
	mode_option.item_selected.connect(_on_mode_changed)
	enemy_ai_slider.value_changed.connect(_on_enemy_ai_changed)
	friendly_ai_slider.value_changed.connect(_on_friendly_ai_changed)
	room_list.item_selected.connect(_on_room_selected)
	refresh_room_button.pressed.connect(_on_refresh_rooms)
	battle_start_button.pressed.connect(_on_start_battle)
	battle_back_button.pressed.connect(_show_start_panel)
	team1_button.pressed.connect(_on_team1_selected)
	team2_button.pressed.connect(_on_team2_selected)

# ── 面板切换 ──

func _show_main_panel() -> void:
	start_panel.visible = false
	edit_panel.visible = false
	level_panel.visible = false
	battle_panel.visible = false
	public_panel.visible = false
	status_label.text = ""

func _show_start_panel() -> void:
	# 停止房间扫描
	if NetworkManager.room_discovered.is_connected(_on_room_discovered):
		NetworkManager.room_discovered.disconnect(_on_room_discovered)
	NetworkManager.stop_room_scan()
	start_panel.visible = true
	edit_panel.visible = false
	level_panel.visible = false
	battle_panel.visible = false
	public_panel.visible = false
	status_label.text = ""

func _show_edit_panel() -> void:
	start_panel.visible = false
	edit_panel.visible = true
	level_panel.visible = false
	battle_panel.visible = false
	public_panel.visible = false
	status_label.text = ""

func _show_level_panel() -> void:
	start_panel.visible = false
	edit_panel.visible = false
	level_panel.visible = true
	battle_panel.visible = false
	public_panel.visible = false
	status_label.text = ""

func _show_battle_panel() -> void:
	start_panel.visible = false
	edit_panel.visible = false
	level_panel.visible = false
	battle_panel.visible = true
	public_panel.visible = false
	_update_start_button()
	_update_team_buttons()

func _show_public_panel() -> void:
	start_panel.visible = false
	edit_panel.visible = false
	level_panel.visible = false
	battle_panel.visible = false
	public_panel.visible = true
	status_label.text = ""

# ── 开始子菜单 ──

func _on_level() -> void:
	# 关卡模式：选择关卡 + 难度
	_populate_saved_levels()
	_populate_difficulty()
	_on_saved_level_selected(level_select_option.selected)
	_show_level_panel()

func _populate_difficulty() -> void:
	difficulty_option.clear()
	difficulty_option.add_item("简单 - 人机反应慢、精度低", 0)
	difficulty_option.add_item("普通 - 标准人机", 1)
	difficulty_option.add_item("困难 - 人机反应快、精度高", 2)
	difficulty_option.add_item("专家 - 极限人机", 3)
	difficulty_option.select(1)  # 默认普通

func _on_difficulty_changed(index: int) -> void:
	pass  # 难度在开始时读取

func _populate_saved_levels() -> void:
	level_select_option.clear()
	level_select_option.add_item("（快速设置）")
	level_select_option.set_item_metadata(0, "")
	# 扫描内置(res://)和自定义(user://)关卡
	for dir_path in ["res://data/levels/", "user://data/levels/"]:
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file = dir.get_next()
			while file != "":
				if file.ends_with(".json"):
					var level_id = file.get_basename()
					var path = dir_path + file
					var f = FileAccess.open(path, FileAccess.READ)
					if f:
						var data = JSON.parse_string(f.get_as_text())
						f.close()
						var name = data.get("name", level_id)
						var tank_count = data.get("tanks", []).size()
						level_select_option.add_item("%s (%d辆)" % [name, tank_count])
						level_select_option.set_item_metadata(level_select_option.item_count - 1, path)
				file = dir.get_next()
			dir.list_dir_end()
	level_select_option.select(0)

func _on_saved_level_selected(index: int) -> void:
	var path = level_select_option.get_item_metadata(index)
	if path == "" or path == null:
		level_info.text = "[color=gray]请选择一个关卡，或点击\"关卡编辑器\"创建新关卡[/color]"
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		var name = data.get("name", "未知")
		var map_id = data.get("map_id", "未知")
		var map_data = DataLoader.get_map(map_id)
		var map_name = map_data.get("name", map_id) if not map_data.is_empty() else map_id
		var tanks = data.get("tanks", [])
		var friendly = 0
		var enemy = 0
		for t in tanks:
			if t.get("team", 0) == 1:
				friendly += 1
			else:
				enemy += 1
		level_info.text = "[b]%s[/b]\n" % name
		level_info.text += "地图：%s\n" % map_name
		level_info.text += "友方：%d辆 | 敌方：%d辆 | 总计：%d辆" % [friendly, enemy, tanks.size()]
		status_label.text = "已选择关卡: %s" % name

func _on_level_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/level_editor.tscn")

func _on_lan_multiplayer() -> void:
	# 局域网联机：房主作为服务器，其他玩家作为客户端
	is_multiplayer = true
	battle_title.text = "局域网联机"
	# 模式选项改为：创建房间(房主) / 加入房间
	mode_option.clear()
	mode_option.add_item("创建房间（房主）", 1)
	mode_option.add_item("加入房间", 2)
	mode_option.select(0)
	_on_mode_changed(0)
	_show_battle_panel()

func _on_public_multiplayer() -> void:
	# 公网联机：进入公网大厅（连接 game.thefeishu.top Python服务器）
	get_tree().change_scene_to_file("res://scenes/public_lobby.tscn")

# ── 编辑子菜单 ──

func _on_map_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")

func _on_vehicle_editor() -> void:
	# 打开载具导入/编辑器
	var importer_scene = load("res://scenes/vehicle_importer.tscn")
	if importer_scene:
		var importer = importer_scene.instantiate()
		add_child(importer)
		importer.import_finished.connect(func(_id):
			_populate_vehicles()
		)

func _on_ammo_editor() -> void:
	# 打开弹药编辑器
	var ammo_editor_scene = load("res://scenes/ammo_editor.tscn")
	if ammo_editor_scene:
		var editor = ammo_editor_scene.instantiate()
		add_child(editor)
	else:
		status_label.text = "弹药编辑器场景未找到"

# ── 设置/退出 ──

func _on_settings() -> void:
	var settings_scene = load("res://scenes/settings.tscn")
	if settings_scene:
		var settings = settings_scene.instantiate()
		add_child(settings)
		settings.tree_exited.connect(_apply_background)

func _on_exit() -> void:
	get_tree().quit()

# ── 数据填充 ──

func _populate_vehicles() -> void:
	vehicle_list.clear()
	vehicle_ids.clear()
	var vehicles = DataLoader.get_all_vehicles()
	for id in vehicles.keys():
		var v = vehicles[id]
		vehicle_ids.append(id)
		var label = "%s [%s]" % [v.get("name", id), v.get("nation", "?")]
		if not DataLoader.is_vehicle_builtin(id):
			label += " [自定义]"
		vehicle_list.add_item(label)

func _populate_maps() -> void:
	map_list.clear()
	map_ids.clear()
	var maps = DataLoader.get_all_maps()
	for id in maps.keys():
		var m = maps[id]
		map_ids.append(id)
		var name = m.get("name", id)
		if not DataLoader.is_map_builtin(id):
			name += " [自定义]"
		map_list.add_item(name)

func _setup_network_options() -> void:
	mode_option.clear()
	mode_option.add_item("单机模式", 0)
	mode_option.add_item("创建房间（服务器）", 1)
	mode_option.add_item("加入游戏（客户端）", 2)

# ── 选择回调 ──

func _on_vehicle_selected(index: int) -> void:
	if index < 0 or index >= vehicle_ids.size():
		return
	selected_vehicle_id = vehicle_ids[index]
	var v = DataLoader.get_vehicle(selected_vehicle_id)
	var physics = v.get("physics", {})
	var armor = v.get("armor", {})
	var vtype = v.get("type", "tank")
	var nation_map := {"USA": "美国", "USSR": "苏联", "GB": "英国", "Germany": "德国", "Japan": "日本"}
	var era_map := {"ww2": "二战", "modern": "现代", "cold_war": "冷战"}
	var nation_str = nation_map.get(v.get("nation", ""), v.get("nation", "?"))
	var era_str = era_map.get(v.get("era", ""), v.get("era", "?"))
	vehicle_info.text = "[b]%s[/b]\n" % v.get("name", "Unknown")
	vehicle_info.text += "[color=silver]%s | %s[/color]\n" % [nation_str, era_str]
	var desc = v.get("description", "")
	if desc != "":
		vehicle_info.text += "%s\n\n" % desc
	var hist = v.get("history", "")
	if hist != "":
		vehicle_info.text += "%s\n\n" % hist
	vehicle_info.text += "[b]性能参数[/b]\n"
	vehicle_info.text += "重量: %d kg | 最大速度: %.0f km/h\n" % [physics.get("mass", 0), physics.get("max_speed", 0)]
	if vtype == "airplane":
		vehicle_info.text += "座舱/机身装甲: %d mm\n" % armor.get("hull_front", 0)
	elif vtype == "helicopter":
		vehicle_info.text += "机身装甲: %d mm" % armor.get("hull_front", 0)
		if armor.get("turret_front", 0) > 0:
			vehicle_info.text += " | 炮塔装甲: %d mm" % armor.get("turret_front", 0)
		vehicle_info.text += "\n"
	else:
		vehicle_info.text += "车体前装甲: %d mm | 炮塔前装甲: %d mm\n" % [armor.get("hull_front", 0), armor.get("turret_front", 0)]
	vehicle_info.text += "乘员: %d人" % v.get("crew_count", 0)
	_update_start_button()

func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_ids.size():
		return
	selected_map_id = map_ids[index]
	var m = DataLoader.get_map(selected_map_id)
	map_info.text = "[b]%s[/b]\n" % m.get("name", "Unknown")
	map_info.text += "%s\n" % m.get("description", "")
	map_info.text += "地图大小: %dx%d\n" % [m.get("size", 0), m.get("size", 0)]
	map_info.text += "障碍物: %d个" % m.get("obstacles", []).size()
	_update_start_button()

func _on_mode_changed(index: int) -> void:
	var mode = mode_option.get_item_id(index)
	ip_input.editable = (mode == 2)
	ip_input.modulate.a = 1.0 if mode == 2 else 0.4
	# 加入房间时地图由房主决定，客户端不需要选地图
	map_row.visible = (mode != 2)
# 只有房主（创建房间）能设置AI数量
	enemy_ai_row.visible = (mode == 1)
	friendly_ai_row.visible = (mode == 1)
	# 只有房主（创建局域网房间）能设置飞机边界大小
	air_boundary_input.get_parent().visible = (mode == 1)
	# 加入房间时显示房间列表并启动扫描
	room_list_row.visible = (mode == 2)
	refresh_room_button.visible = (mode == 2)
	if mode == 2:
		room_list.clear()
		NetworkManager.room_discovered.connect(_on_room_discovered)
		NetworkManager.start_room_scan()
	else:
		if NetworkManager.room_discovered.is_connected(_on_room_discovered):
			NetworkManager.room_discovered.disconnect(_on_room_discovered)
		NetworkManager.stop_room_scan()
	_update_start_button()

func _on_enemy_ai_changed(value: float) -> void:
	enemy_ai_count.text = str(int(value))

func _on_friendly_ai_changed(value: float) -> void:
	friendly_ai_count.text = str(int(value))

func _on_refresh_rooms() -> void:
	"""手动刷新房间列表：清空并重启扫描"""
	room_list.clear()
	# 重启扫描
	if NetworkManager.room_discovered.is_connected(_on_room_discovered):
		NetworkManager.room_discovered.disconnect(_on_room_discovered)
	NetworkManager.stop_room_scan()
	NetworkManager.room_discovered.connect(_on_room_discovered)
	NetworkManager.start_room_scan()
	refresh_room_button.text = "刷新中..."
	refresh_room_button.disabled = true
	await get_tree().create_timer(2.0).timeout
	refresh_room_button.text = "刷新房间列表"
	refresh_room_button.disabled = false

func _on_room_discovered(room_info: Dictionary) -> void:
	"""收到房间广播，更新房间列表"""
	var ip = room_info.get("ip", "")
	var port = room_info.get("port", 7777)
	var key = "%s:%d" % [ip, port]
	# 检查是否已存在
	for i in range(room_list.item_count):
		if room_list.get_item_metadata(i) == key:
			# 更新显示
			var text = _format_room_text(room_info)
			room_list.set_item_text(i, text)
			return
	# 新增房间
	var text = _format_room_text(room_info)
	room_list.add_item(text)
	room_list.set_item_metadata(room_list.item_count - 1, key)

func _format_room_text(room_info: Dictionary) -> String:
	var name = room_info.get("name", "未知房间")
	var map_name = room_info.get("map", "未知地图")
	var players = room_info.get("players", 0)
	var max_p = room_info.get("max_players", 16)
	var ip = room_info.get("ip", "")
	return "%s  [%s]  %d/%d人  %s" % [name, map_name, players, max_p, ip]

func _on_room_selected(index: int) -> void:
	"""选择房间后自动填充IP和端口"""
	var key = room_list.get_item_metadata(index)
	if typeof(key) != TYPE_STRING:
		return
	var parts = key.split(":")
	if parts.size() == 2:
		ip_input.text = parts[0]
		port_input.text = parts[1]
		status_label.text = "已选择房间: %s" % room_list.get_item_text(index)

func _update_start_button() -> void:
	var mode = mode_option.get_item_id(mode_option.selected)
	# 加入房间时地图由房主决定，只需选载具
	var need_map = (mode != 2)
	battle_start_button.disabled = selected_vehicle_id == "" or (need_map and selected_map_id == "")
	if battle_start_button.disabled:
		if selected_vehicle_id == "":
			battle_start_button.text = "请选择载具"
		elif need_map and selected_map_id == "":
			battle_start_button.text = "请选择地图"
		else:
			battle_start_button.text = "请选择载具和地图"
	else:
		match mode:
			0: battle_start_button.text = "开始战斗"
			1: battle_start_button.text = "创建房间并开始"
			2: battle_start_button.text = "连接并加入"

# ── 关卡设置 ──

func _on_level_start() -> void:
	# 必须选择一个关卡
	var selected_idx = level_select_option.selected
	var level_path = level_select_option.get_item_metadata(selected_idx)
	if selected_idx <= 0 or level_path == "" or level_path == null:
		status_label.text = "请先选择一个关卡！"
		return

	var f = FileAccess.open(level_path, FileAccess.READ)
	if not f:
		status_label.text = "关卡文件读取失败！"
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()

	# 读取难度
	var difficulty = difficulty_option.get_item_id(difficulty_option.selected)
	GameManager.difficulty = difficulty

	# 应用关卡数据
	GameManager.level_data = data
	GameManager.selected_map_id = data.get("map_id", "map_desert")
	GameManager.selected_vehicle_id = ""
	for t in data.get("tanks", []):
		if t.get("team", 0) == 1:
			GameManager.selected_vehicle_id = t.get("vehicle_id", "tank_abrams")
			break
	if GameManager.selected_vehicle_id == "":
		GameManager.selected_vehicle_id = "tank_abrams"

	GameManager.network_mode = 0
	NetworkManager.mode = NetworkManager.NetworkMode.STANDALONE
	var diff_names = ["简单", "普通", "困难", "专家"]
	status_label.text = "正在进入战场: %s [%s]..." % [data.get("name", "关卡"), diff_names[difficulty]]
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _get_local_ip() -> String:
	"""获取本机局域网IP地址"""
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		# 跳过IPv6和回环地址，取第一个IPv4局域网地址
		if addr != "127.0.0.1" and addr.count(":") == 0 and not addr.begins_with("169.254"):
			return addr
	return "127.0.0.1"

# ── 开始战斗 ──

func _on_team1_selected() -> void:
	selected_team = 1
	_update_team_buttons()

func _on_team2_selected() -> void:
	selected_team = 2
	_update_team_buttons()

func _update_team_buttons() -> void:
	team1_button.modulate = Color(0.3, 0.5, 1.0) if selected_team == 1 else Color(1, 1, 1)
	team2_button.modulate = Color(1.0, 0.3, 0.3) if selected_team == 2 else Color(1, 1, 1)

func _on_start_battle() -> void:
	var mode = mode_option.get_item_id(mode_option.selected)
	var port = int(port_input.text) if port_input.text.is_valid_int() else 7777

	GameManager.selected_vehicle_id = selected_vehicle_id
	GameManager.selected_map_id = selected_map_id
	GameManager.network_mode = mode
	GameManager.network_type = 0  # 局域网联机
	GameManager.public_player_team = selected_team  # 局域网也使用此字段保存队伍

	match mode:
		0:
			NetworkManager.mode = NetworkManager.NetworkMode.STANDALONE
			status_label.text = "正在进入战场..."
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		1:
			# 房主设置AI数量
			GameManager.level_config = {
				"enemy_count": int(enemy_ai_slider.value),
				"friendly_count": int(friendly_ai_slider.value),
				"enemy_vehicle": "tank_t34_85",
				"friendly_vehicle": "tank_abrams",
			}
			GameManager.level_data = {}  # 联机模式不用关卡编辑器数据
			# 房主自定义飞机边界（米）：0/空 = 使用地图默认
			GameManager.air_boundary_size = float(air_boundary_input.text) if air_boundary_input.text.is_valid_float() else 0.0
			if NetworkManager.start_server(port):
				var local_ip = _get_local_ip()
				status_label.text = "房间已创建！IP: %s 端口: %d\n进入房间大厅..." % [local_ip, port]
				await get_tree().create_timer(0.5).timeout
				get_tree().change_scene_to_file("res://scenes/lan_lobby.tscn")
			else:
				status_label.text = "创建房间失败！端口可能被占用"
		2:
			var ip = ip_input.text.strip_edges()
			if ip == "":
				status_label.text = "请输入房主IP地址或从列表选择房间！"
				return
			# 停止扫描，准备连接
			if NetworkManager.room_discovered.is_connected(_on_room_discovered):
				NetworkManager.room_discovered.disconnect(_on_room_discovered)
			NetworkManager.stop_room_scan()
			if NetworkManager.start_client(ip, port):
				status_label.text = "正在连接 %s:%d..." % [ip, port]
				var connected = false
				var timeout = 8.0
				var timer = 0.0
				while timer < timeout:
					await get_tree().process_frame
					timer += get_process_delta_time()
					if NetworkManager.is_client and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
						connected = true
						break
				if not connected:
					status_label.text = "连接超时！请检查IP和端口是否正确"
					NetworkManager.stop_network()
					return

				# 连接成功，向服务器请求地图同步
				status_label.text = "连接成功！正在同步地图..."
				_map_received = false
				_received_map_id = ""
				NetworkManager.map_received.connect(_on_map_received)
				NetworkManager.request_map()

				# 等待地图同步（超时5秒，用真实墙钟计时，避免帧率/process_delta 误差）
				var map_timeout_msec := 5000
				var start_msec := Time.get_ticks_msec()
				while Time.get_ticks_msec() - start_msec < map_timeout_msec and not _map_received:
					await get_tree().process_frame

				if NetworkManager.map_received.is_connected(_on_map_received):
					NetworkManager.map_received.disconnect(_on_map_received)

				if not _map_received:
					status_label.text = "地图同步超时！"
					NetworkManager.stop_network()
					return

				GameManager.selected_map_id = _received_map_id
				status_label.text = "地图同步完成：%s\n进入房间大厅..." % _received_map_id
				await get_tree().create_timer(0.3).timeout
				get_tree().change_scene_to_file("res://scenes/lan_lobby.tscn")
			else:
				status_label.text = "连接失败！"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		var new_val = not SettingsManager.is_mobile_mode()
		SettingsManager.set_mobile_mode(new_val)
		GameManager.force_mobile = new_val
		status_label.text = "移动端模式: %s（按M切换）" % ("开" if new_val else "关")
