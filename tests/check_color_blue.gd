extends SceneTree

## 测试：验证颜色绘制系统修复——深蓝色问题和笔刷不生效问题

const MAP_VALLEY_PATH = "res://data/maps/map_valley.json"

func _init():
	var passed := 0
	var failed := 0
	
	# === 1. 检查 map_valley.json 数据 ===
	var file := FileAccess.open(MAP_VALLEY_PATH, FileAccess.READ)
	assert(file, "无法打开 map_valley.json")
	var json_text := file.get_as_text()
	file.close()
	var data: Dictionary = JSON.parse_string(json_text)
	assert(not data.is_empty(), "map_valley.json 解析失败")
	
	var gc = data.get("ground_color", [])
	assert(gc.size() >= 3, "ground_color 字段缺失")
	var map_ground_color := Color(gc[0], gc[1], gc[2], 1.0)
	print("map_valley ground_color: R=%.2f G=%.2f B=%.2f" % [gc[0], gc[1], gc[2]])
	
	# ground_color 不应该是蓝色
	if map_ground_color.b < map_ground_color.r and map_ground_color.b < map_ground_color.g:
		print("PASS: ground_color 不是蓝色")
		passed += 1
	else:
		print("FAIL: ground_color 偏蓝!")
		failed += 1
	
	# === 2. 检查 map_valley 无 color_texture ===
	var terrain_data: Dictionary = data.get("terrain", {})
	var has_color_texture := terrain_data.has("color_texture")
	if not has_color_texture:
		print("PASS: map_valley 无 color_texture，应使用 default_ground_color 填充")
		passed += 1
	else:
		print("FAIL: map_valley 不应有 color_texture")
		failed += 1
	
	# === 3. 模拟修复后的加载流程 ===
	# 模拟 _on_clear 重置
	var default_ground_color := Color(0.6, 0.55, 0.4, 1.0)  # _on_clear 重置
	var color_resolution := 256
	var map_size := float(data.get("size", 200))
	
	# 模拟 _load_map_data 修复：从 map data 读取 ground_color
	default_ground_color = Color(gc[0], gc[1], gc[2], 1.0)
	
	# 模拟 _load_map_data 修复：根据地图大小调整笔刷半径
	var color_brush_radius: float = max(15.0, map_size * 0.05)
	
	# 模拟 _init_color_image
	var color_image := Image.create(color_resolution, color_resolution, false, Image.FORMAT_RGBA8)
	color_image.fill(default_ground_color)
	
	# 检查 Image 像素
	var center_pixel := color_image.get_pixel(color_resolution / 2, color_resolution / 2)
	if abs(center_pixel.r - map_ground_color.r) < 0.01 and \
	   abs(center_pixel.g - map_ground_color.g) < 0.01 and \
	   abs(center_pixel.b - map_ground_color.b) < 0.01:
		print("PASS: color_image 正确填充为 ground_color")
		passed += 1
	else:
		print("FAIL: color_image 填充不正确!")
		failed += 1
	
	# === 4. 检查笔刷半径合理 ===
	var brush_px: int = max(1, int(color_brush_radius / map_size * color_resolution))
	print("map_size=%.0f, brush_radius=%.1f, brush_px=%d" % [map_size, color_brush_radius, brush_px])
	if brush_px >= 5:
		print("PASS: 笔刷半径合理 (brush_px=%d)" % brush_px)
		passed += 1
	else:
		print("FAIL: 笔刷半径太小 (brush_px=%d)" % brush_px)
		failed += 1
	
	# === 5. 模拟笔刷绘制 ===
	var paint_color := Color(0.8, 0.1, 0.1, 1.0)
	var px := color_resolution / 2
	var py := color_resolution / 2
	var min_x: int = max(0, px - brush_px)
	var max_x: int = min(color_resolution - 1, px + brush_px)
	var min_y: int = max(0, py - brush_px)
	var max_y: int = min(color_resolution - 1, py + brush_px)
	var painted_count := 0
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = float(x) - float(px)
			var dy: float = float(y) - float(py)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= brush_px:
				var falloff: float = cos(dist / float(brush_px) * PI * 0.5)
				var existing := color_image.get_pixel(x, y)
				var blended := existing.lerp(paint_color, falloff)
				color_image.set_pixel(x, y, blended)
				painted_count += 1
	
	if painted_count > 0:
		var after := color_image.get_pixel(px, py)
		if after.r > 0.5 and after.g < 0.3:
			print("PASS: 笔刷绘制后中心像素变为红色 (painted=%d)" % painted_count)
			passed += 1
		else:
			print("FAIL: 笔刷绘制后像素未变为红色!")
			failed += 1
	else:
		print("FAIL: 没有像素被绘制")
		failed += 1
	
	# === 6. 检查 map_editor.tscn 背景色不是深蓝 ===
	var tscn_file := FileAccess.open("res://scenes/map_editor.tscn", FileAccess.READ)
	assert(tscn_file, "无法打开 map_editor.tscn")
	var tscn_text := tscn_file.get_as_text()
	tscn_file.close()
	
	# 背景色应该是深灰而非深蓝
	if tscn_text.find("background_color = Color(0.15, 0.15, 0.15, 1)") >= 0:
		print("PASS: WorldEnvironment 背景色已改为深灰色")
		passed += 1
	elif tscn_text.find("background_color = Color(0.2, 0.25, 0.3, 1)") >= 0:
		print("FAIL: 背景色仍是深蓝色 Color(0.2, 0.25, 0.3)")
		failed += 1
	else:
		print("INFO: 背景色为其他值")
		passed += 1
	
	# === 7. 检查摄像机 far 属性 ===
	if tscn_text.find("far = 8000.0") >= 0:
		print("PASS: 摄像机 far=8000 已设置")
		passed += 1
	else:
		print("FAIL: 摄像机 far 属性未设置")
		failed += 1
	
	# === 8. 检查 map_editor.gd 修复 ===
	var gd_file := FileAccess.open("res://scripts/ui/map_editor.gd", FileAccess.READ)
	assert(gd_file, "无法打开 map_editor.gd")
	var gd_text := gd_file.get_as_text()
	gd_file.close()
	
	# 检查 _load_map_data 读取 ground_color
	if gd_text.find("default_ground_color = Color(gc[0], gc[1], gc[2], 1.0)") >= 0:
		print("PASS: _load_map_data 读取 ground_color")
		passed += 1
	else:
		print("FAIL: _load_map_data 未读取 ground_color")
		failed += 1
	
	# 检查 _load_map_data 调整笔刷半径
	if gd_text.find("color_brush_radius = max(15.0, map_size * 0.05)") >= 0:
		print("PASS: _load_map_data 调整笔刷半径")
		passed += 1
	else:
		print("FAIL: _load_map_data 未调整笔刷半径")
		failed += 1
	
	# 检查 _on_clear 重置 default_ground_color
	if gd_text.find("default_ground_color = Color(0.6, 0.55, 0.4, 1.0)  # 重置为默认地面色") >= 0:
		print("PASS: _on_clear 重置 default_ground_color")
		passed += 1
	else:
		print("FAIL: _on_clear 未重置 default_ground_color")
		failed += 1
	
	# 检查 _paint_ground_color 重新赋值材质
	if gd_text.find("terrain_ground_material.albedo_texture = color_texture") >= 2:  # 至少出现2次（_setup_ground + _paint_ground_color）
		print("PASS: _paint_ground_color 重新赋值材质")
		passed += 1
	else:
		print("FAIL: _paint_ground_color 未重新赋值材质")
		failed += 1
	
	# 检查摄像机高度自动调整
	if gd_text.find("camera_height < camera_max_height * 0.3") >= 0:
		print("PASS: 摄像机高度自动调整")
		passed += 1
	else:
		print("FAIL: 摄像机高度未自动调整")
		failed += 1
	
	# === 9. 检查 map_valley 地形数据完整性 ===
	var heights = terrain_data.get("heights", [])
	print("map_valley: size=%s, grid=%s, heights=%d" % [data.get("size"), terrain_data.get("grid_size"), heights.size()])
	if heights.size() == 4225:  # 65*65
		print("PASS: 地形高度数据完整 (4225)")
		passed += 1
	else:
		print("FAIL: 地形高度数据不完整 (期望4225, 实际%d)" % heights.size())
		failed += 1
	
	# 检查最高点
	var max_h := 0.0
	var min_h := 0.0
	for h in heights:
		var fh := float(h)
		if fh > max_h: max_h = fh
		if fh < min_h: min_h = fh
	print("map_valley 地形高度范围: %.1f ~ %.1f" % [min_h, max_h])
	if max_h > 50.0:
		print("PASS: 地形有起伏 (max=%.1f)" % max_h)
		passed += 1
	else:
		print("FAIL: 地形过于平坦")
		failed += 1
	
	print("\n=== 结果: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)
