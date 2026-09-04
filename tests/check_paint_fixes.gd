extends SceneTree
## 测试地图编辑器颜色/地形绘制修复

func _init():
	print("\n=== 地图编辑器颜色/地形绘制修复检查 ===")
	var failed := 0
	var me_text := FileAccess.get_file_as_string("res://scripts/ui/map_editor.gd")

	# Bug 1: _setup_ground 不应在加载时擦除地形高度
	if me_text.contains("_setup_ground(init_heights: bool = true)"):
		print("PASS: _setup_ground 有 init_heights 参数")
	else:
		print("FAIL: _setup_ground 缺少 init_heights 参数")
		failed += 1

	if me_text.contains("_setup_ground(false)"):
		print("PASS: _load_map_data 传 false 保留地形高度")
	else:
		print("FAIL: _load_map_data 未传 false")
		failed += 1

	if me_text.contains("if init_heights:"):
		print("PASS: _setup_ground 条件初始化高度")
	else:
		print("FAIL: _setup_ground 无条件初始化高度")
		failed += 1

	# Bug 2: _on_clear 重置分辨率
	if me_text.contains("color_resolution = 256  # 重置为默认分辨率"):
		print("PASS: _on_clear 重置 color_resolution")
	else:
		print("FAIL: _on_clear 未重置 color_resolution")
		failed += 1

	if me_text.contains("terrain_grid_size = 64  # 重置为默认网格大小"):
		print("PASS: _on_clear 重置 terrain_grid_size")
	else:
		print("FAIL: _on_clear 未重置 terrain_grid_size")
		failed += 1

	# Bug 3: 地形绘制不在每帧重建碰撞体
	if me_text.contains("terrain_collision_dirty"):
		print("PASS: 地形绘制使用 dirty 标志延迟重建碰撞体")
	else:
		print("FAIL: 地形绘制缺少碰撞体延迟重建")
		failed += 1

	if me_text.contains("_flush_terrain_collision"):
		print("PASS: 有 _flush_terrain_collision 函数")
	else:
		print("FAIL: 缺少 _flush_terrain_collision")
		failed += 1

	# 检查松开鼠标时调用 flush
	var flush_count := me_text.count("_flush_terrain_collision()")
	if flush_count >= 3:
		print("PASS: 松开左键/右键/F键后调用 _flush_terrain_collision (%d处)" % flush_count)
	else:
		print("FAIL: _flush_terrain_collision 调用不足 (%d处)" % flush_count)
		failed += 1

	# Bug 4: 颜色笔刷 brush_px 最小为 1
	if me_text.contains("max(1, int(color_brush_radius"):
		print("PASS: 颜色笔刷 brush_px 最小为 1")
	else:
		print("FAIL: 颜色笔刷 brush_px 可能为 0")
		failed += 1

	# Bug 5: 射线长度自适应
	if me_text.contains("max(2000.0, camera_max_height * 2.0)"):
		print("PASS: 射线长度自适应摄像机最大高度")
	else:
		print("FAIL: 射线长度固定 1000 不够大地图")
		failed += 1

	# Bug 6: 颜色 alpha 强制为 1.0
	if me_text.contains("color_picker_button.color.b, 1.0)"):
		print("PASS: 绘制颜色 alpha 强制为 1.0")
	else:
		print("FAIL: 绘制颜色可能带 alpha 导致透明")
		failed += 1

	# 验证 _paint_terrain 不再直接调用 _rebuild_terrain_collision
	var paint_func_start := me_text.find("func _paint_terrain(")
	var paint_func_end := me_text.find("\n\n", paint_func_start)
	var paint_func_text := me_text.substr(paint_func_start, paint_func_end - paint_func_start)
	if not paint_func_text.contains("_rebuild_terrain_collision()"):
		print("PASS: _paint_terrain 不直接调用 _rebuild_terrain_collision")
	else:
		print("FAIL: _paint_terrain 仍直接调用 _rebuild_terrain_collision")
		failed += 1

	# 验证 _flatten_terrain 不再直接调用 _rebuild_terrain_collision
	var flatten_func_start := me_text.find("func _flatten_terrain(")
	var flatten_func_end := me_text.find("\n\n", flatten_func_start)
	var flatten_func_text := me_text.substr(flatten_func_start, flatten_func_end - flatten_func_start)
	if not flatten_func_text.contains("_rebuild_terrain_collision()"):
		print("PASS: _flatten_terrain 不直接调用 _rebuild_terrain_collision")
	else:
		print("FAIL: _flatten_terrain 仍直接调用 _rebuild_terrain_collision")
		failed += 1

	print("\n=== 汇总: failed=%d ===" % failed)
	quit(failed)
