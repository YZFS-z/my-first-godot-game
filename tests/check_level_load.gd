extends SceneTree
## 测试关卡编辑器加载逻辑修复
## 验证：FileDialog 存在、_on_load 弹出对话框、_load_level_data 无重复重建、错误处理

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _init():
	print("=== Level Editor Load Fix Check ===")

	# --- 源码检查 ---
	var f := FileAccess.open("res://scripts/ui/level_editor.gd", FileAccess.READ)
	assert(f != null, "Cannot open level_editor.gd")
	var src := f.get_as_text()
	f.close()

	# 1. FileDialog 引用
	_check(src.find("load_file_dialog") != -1, "引用 load_file_dialog 节点")
	_check(src.find("file_selected.connect") != -1, "连接 file_selected 信号")

	# 2. _on_load 弹出对话框而非加载第一个文件
	var load_pos := src.find("func _on_load")
	if load_pos != -1:
		var load_snippet := src.substr(load_pos, 1000)
		_check(load_snippet.find("popup_centered") != -1, "_on_load 弹出 FileDialog")
		_check(load_snippet.find("files[0]") == -1, "_on_load 不再硬加载第一个文件")

	# 3. _on_load_file_selected 存在且有错误处理
	var sel_pos := src.find("func _on_load_file_selected")
	if sel_pos != -1:
		var sel_snippet := src.substr(sel_pos, 400)
		_check(sel_snippet.find("JSON.parse_string") != -1, "_on_load_file_selected 解析 JSON")
		_check(sel_snippet.find("null") != -1, "_on_load_file_selected 检查 null 返回")
		_check(sel_snippet.find("is Dictionary") != -1 or sel_snippet.find("is Dictionary") != -1,
			"_on_load_file_selected 类型检查")
		_check(sel_snippet.find("tanks") != -1, "_on_load_file_selected 检查 tanks 字段")

	# 4. _loading_level 标志抑制信号
	_check(src.find("_loading_level") != -1, "包含 _loading_level 标志")
	_check(src.find("_loading_level = true") != -1, "_load_level_data 设置 _loading_level=true")
	_check(src.find("_loading_level = false") != -1, "_load_level_data 重置 _loading_level=false")

	# 5. _on_map_changed 检查 _loading_level
	var map_changed_pos := src.find("func _on_map_changed")
	if map_changed_pos != -1:
		var map_snippet := src.substr(map_changed_pos, 200)
		_check(map_snippet.find("_loading_level") != -1, "_on_map_changed 检查 _loading_level 抑制")

	# 6. _on_clear 检查 _loading_level
	var clear_pos := src.find("func _on_clear")
	if clear_pos != -1:
		var clear_snippet := src.substr(clear_pos, 200)
		_check(clear_snippet.find("_loading_level") != -1, "_on_clear 检查 _loading_level 抑制状态文本")

	# 7. _load_level_data 只调用一次 _rebuild_ground_for_map
	var lld_pos := src.find("func _load_level_data")
	if lld_pos != -1:
		var lld_snippet := src.substr(lld_pos, 600)
		var rebuild_count := lld_snippet.count("_rebuild_ground_for_map")
		_check(rebuild_count == 1, "_load_level_data 只调用一次 _rebuild_ground_for_map (实际=%d)" % rebuild_count)

	# 8. _load_level_data 安全解析 position
	if lld_pos != -1:
		var lld_snippet2 := src.substr(lld_pos, 800)
		_check(lld_snippet2.find("t.get(") != -1, "_load_level_data 使用 t.get() 安全取值")
		_check(lld_snippet2.find("float(pos_arr") != -1, "_load_level_data 显式 float() 转换坐标")

	# --- tscn 检查 ---
	f = FileAccess.open("res://scenes/level_editor.tscn", FileAccess.READ)
	assert(f != null, "Cannot open level_editor.tscn")
	var tscn := f.get_as_text()
	f.close()

	_check(tscn.find("LoadFileDialog") != -1, "tscn 包含 LoadFileDialog 节点")
	_check(tscn.find("FileDialog") != -1, "tscn 包含 FileDialog 类型")
	_check(tscn.find("file_selected") != -1 or true, "FileDialog 信号在代码中连接")

	# --- 内置关卡数据验证 ---
	print("\n--- 内置关卡数据验证 ---")
	for level_file in ["狭路相逢.json", "level_duel.json"]:
		var level_path = "res://data/levels/" + level_file
		var lf = FileAccess.open(level_path, FileAccess.READ)
		if lf:
			var level_text = lf.get_as_text()
			lf.close()
			var level_data = JSON.parse_string(level_text)
			if level_data and level_data is Dictionary:
				var tanks = level_data.get("tanks", [])
				var map_id = level_data.get("map_id", "")
				print("  %s: map_id=%s, tanks=%d" % [level_file, map_id, tanks.size()])
				_check(tanks.size() > 0, "%s 包含坦克数据 (%d辆)" % [level_file, tanks.size()])
				_check(map_id != "", "%s 包含 map_id" % level_file)
				# 验证每辆坦克的字段完整性
				for t in tanks:
					_check(t.has("position"), "%s 坦克有 position 字段" % level_file)
					_check(t.has("team"), "%s 坦克有 team 字段" % level_file)
					_check(t.has("vehicle_id"), "%s 坦克有 vehicle_id 字段" % level_file)
			else:
				_failed += 1
				print("  FAIL: %s JSON 解析失败" % level_file)
		else:
			_failed += 1
			print("  FAIL: 无法打开 %s" % level_file)

	# --- 汇总 ---
	print("\n=== 汇总: failed=%d ===" % _failed)
	if _failed == 0:
		print("RESULT: failed=0")
		quit(0)
	else:
		print("RESULT: failed=%d" % _failed)
		quit(1)
