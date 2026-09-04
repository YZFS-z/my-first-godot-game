extends SceneTree
## 测试地面颜色绘制系统

func _init():
	print("\n=== 地面颜色绘制系统检查 ===")
	var failed := 0
	
	# 1. 检查 map_editor.gd 包含颜色绘制相关变量和函数
	var me_text := FileAccess.get_file_as_string("res://scripts/ui/map_editor.gd")
	
	if me_text.contains("color_image") and me_text.contains("color_texture"):
		print("PASS: map_editor 包含颜色 Image/Texture 变量")
	else:
		print("FAIL: map_editor 缺少颜色变量")
		failed += 1
	
	if me_text.contains("_paint_ground_color"):
		print("PASS: map_editor 包含 _paint_ground_color 函数")
	else:
		print("FAIL: map_editor 缺少 _paint_ground_color")
		failed += 1
	
	if me_text.contains("_color_paint_input"):
		print("PASS: map_editor 包含 _color_paint_input 输入处理")
	else:
		print("FAIL: map_editor 缺少 _color_paint_input")
		failed += 1
	
	if me_text.contains("is_color_paint_mode"):
		print("PASS: map_editor 包含颜色绘制模式标志")
	else:
		print("FAIL: map_editor 缺少 is_color_paint_mode")
		failed += 1
	
	if me_text.contains("color_picker_button"):
		print("PASS: map_editor 引用 ColorPickerButton")
	else:
		print("FAIL: map_editor 缺少 color_picker_button 引用")
		failed += 1
	
	if me_text.contains("_init_color_image"):
		print("PASS: map_editor 包含 _init_color_image 初始化函数")
	else:
		print("FAIL: map_editor 缺少 _init_color_image")
		failed += 1
	
	if me_text.contains("save_png"):
		print("PASS: map_editor 保存颜色纹理为 PNG")
	else:
		print("FAIL: map_editor 未保存 PNG")
		failed += 1
	
	if me_text.contains("color_texture"):
		print("PASS: map_editor JSON 包含 color_texture 字段")
	else:
		print("FAIL: map_editor 缺少 color_texture JSON 字段")
		failed += 1
	
	# 2. 检查地形网格含 UV
	if me_text.contains("set_uv"):
		print("PASS: map_editor 地形网格含 UV 坐标")
	else:
		print("FAIL: map_editor 地形网格缺少 UV")
		failed += 1
	
	if me_text.contains('地面颜色') and me_text.contains("7:"):
		print("PASS: map_editor obstacle 选项含 '地面颜色'(索引7)")
	else:
		print("FAIL: map_editor 缺少地面颜色选项")
		failed += 1
	
	# 3. 检查 main.gd 加载颜色纹理
	var main_text := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	
	if main_text.contains("color_texture") and main_text.contains("albedo_texture"):
		print("PASS: main.gd 加载颜色纹理并应用到 albedo_texture")
	else:
		print("FAIL: main.gd 未加载颜色纹理")
		failed += 1
	
	if main_text.contains("set_uv"):
		print("PASS: main.gd 地形网格含 UV 坐标")
	else:
		print("FAIL: main.gd 地形网格缺少 UV")
		failed += 1
	
	# 4. 检查 level_editor.gd 同步 UV
	var le_text := FileAccess.get_file_as_string("res://scripts/ui/level_editor.gd")
	
	if le_text.contains("set_uv"):
		print("PASS: level_editor 地形网格含 UV 坐标")
	else:
		print("FAIL: level_editor 地形网格缺少 UV")
		failed += 1
	
	if le_text.contains("color_texture"):
		print("PASS: level_editor 加载颜色纹理")
	else:
		print("FAIL: level_editor 未加载颜色纹理")
		failed += 1
	
	# 5. 检查 tscn 含 ColorPickerButton
	var tscn_text := FileAccess.get_file_as_string("res://scenes/map_editor.tscn")
	if tscn_text.contains("ColorPickerButton"):
		print("PASS: map_editor.tscn 含 ColorPickerButton 节点")
	else:
		print("FAIL: map_editor.tscn 缺少 ColorPickerButton")
		failed += 1
	
	# 6. 测试 Image 绘制功能（headless 可运行）
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	# 模拟笔刷绘制
	var px := 32
	var py := 32
	var brush_px := 10
	for y in range(max(0, py - brush_px), min(64, py + brush_px + 1)):
		for x in range(max(0, px - brush_px), min(64, px + brush_px + 1)):
			var dx := float(x) - float(px)
			var dy := float(y) - float(py)
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= brush_px:
				var falloff := cos(dist / float(brush_px) * PI * 0.5)
				var existing := img.get_pixel(x, y)
				var blended := existing.lerp(Color(1.0, 0.0, 0.0, 1.0), falloff)
				img.set_pixel(x, y, blended)
	
	var center_color := img.get_pixel(32, 32)
	if center_color.r > 0.9:
		print("PASS: 笔刷绘制中心颜色正确 (R=%.2f)" % center_color.r)
	else:
		print("FAIL: 笔刷绘制中心颜色错误 (R=%.2f)" % center_color.r)
		failed += 1
	
	var edge_color := img.get_pixel(0, 0)
	if edge_color.r < 0.6:
		print("PASS: 笔刷外区域保持原色 (R=%.2f)" % edge_color.r)
	else:
		print("FAIL: 笔刷外区域颜色被污染 (R=%.2f)" % edge_color.r)
		failed += 1
	
	# 7. 测试 PNG 保存/加载
	var test_png := "user://test_color_paint.png"
	var save_err := img.save_png(test_png)
	if save_err == OK:
		print("PASS: Image.save_png 成功")
		var loaded := Image.load_from_file(test_png)
		if loaded and loaded.get_width() == 64:
			var loaded_color := loaded.get_pixel(32, 32)
			if abs(loaded_color.r - center_color.r) < 0.01:
				print("PASS: PNG 加载后颜色一致 (R=%.2f)" % loaded_color.r)
			else:
				print("FAIL: PNG 加载后颜色不一致 (R=%.2f vs %.2f)" % [loaded_color.r, center_color.r])
				failed += 1
		else:
			print("FAIL: PNG 加载失败")
			failed += 1
		# 清理测试文件
		DirAccess.remove_absolute(test_png)
	else:
		print("FAIL: Image.save_png 失败 (err=%d)" % save_err)
		failed += 1
	
	print("\n=== 汇总: failed=%d ===" % failed)
	quit(failed)
