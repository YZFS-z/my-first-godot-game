extends SceneTree
## 测试：炮镜模式与第三人称准心一致性
## 验证：
## 1. is_scope 检测正确（get("is_scope_mode") == true 而非 has_method）
## 2. 炮镜模式下 HUD 准星隐藏（gun_scope 分划板接管）
## 3. 第三人称模式下 HUD 准星可见，跟踪炮管投影
## 4. 炮镜相机零偏移挂在 gun_node 上，中心=炮管方向
## 5. fire() 使用 muzzle_node 方向，与准心一致

var _pass: int = 0
var _fail: int = 0
var _errors: Array = []

func _init():
	print("=== check_scope_crosshair_sync ===")
	_test_no_has_method_bug()
	_test_scope_hides_hud_crosshair()
	_test_third_person_shows_crosshair()
	_test_raycast_hit_point()
	_test_scope_camera_alignment()
	_test_fire_direction_matches_crosshair()
	_test_tank_is_scope_mode_is_var()
	_report()

func _test_no_has_method_bug():
	# 核心验证：hud.gd 不再使用 has_method("is_scope_mode")
	var hud_src = _read_file("res://scripts/ui/hud.gd")

	if hud_src.find('has_method("is_scope_mode")') == -1:
		_pass_test("hud.gd does not use has_method('is_scope_mode') [BUG FIXED]")
	else:
		_fail_test("hud.gd still uses has_method('is_scope_mode') - bug NOT fixed")

	# 验证使用 get() == true 模式
	if hud_src.find('get("is_scope_mode") == true') != -1:
		_pass_test("hud.gd uses get('is_scope_mode') == true for property detection")
	else:
		_fail_test("hud.gd should use get('is_scope_mode') == true")

	# 验证不使用 get 带两个参数（Godot 4 不支持）
	if hud_src.find('get("is_scope_mode",') == -1:
		_pass_test("hud.gd does not use get() with 2 args (Godot 4 incompatible)")
	else:
		_fail_test("hud.gd uses get() with 2 args - Godot 4 parse error")

func _test_scope_hides_hud_crosshair():
	var hud_src = _read_file("res://scripts/ui/hud.gd")

	# 验证炮镜模式分支存在
	var scope_branch = hud_src.find("is_tank and is_scope")
	if scope_branch != -1:
		_pass_test("hud.gd has 'is_tank and is_scope' branch")
	else:
		_fail_test("hud.gd missing 'is_tank and is_scope' branch")
		return

	# 验证炮镜分支中 crosshair.visible = false
	var after_scope = hud_src.substr(scope_branch, 300)
	if after_scope.find("crosshair.visible = false") != -1:
		_pass_test("scope mode branch hides HUD crosshair")
	else:
		_fail_test("scope mode branch should hide HUD crosshair")

	# 验证炮镜分支中 view_marker = false
	if after_scope.find("_update_view_marker(center, false)") != -1:
		_pass_test("scope mode branch hides view_marker")
	else:
		_fail_test("scope mode branch should hide view_marker")

func _test_third_person_shows_crosshair():
	var hud_src = _read_file("res://scripts/ui/hud.gd")

	# 验证第三人称分支存在
	var tp_idx = hud_src.find("is_tank and player_vehicle.is_player_controlled")
	if tp_idx != -1:
		_pass_test("third-person branch exists")
	else:
		_fail_test("third-person branch missing")
		return

	var after_tp = hud_src.substr(tp_idx, 1000)

	# 验证使用 muzzle_node 投影
	if after_tp.find("muzzle_node.global_transform.basis.z") != -1:
		_pass_test("third-person uses muzzle_node transform for projection")
	else:
		_fail_test("third-person should use muzzle_node transform")

	# 验证 crosshair.visible = true 在第三人称分支中
	if after_tp.find("crosshair.visible = true") != -1:
		_pass_test("third-person shows crosshair")
	else:
		_fail_test("third-person should show crosshair")

	# 验证 view_marker 在第三人称中显示
	if after_tp.find("_update_view_marker(center, true)") != -1:
		_pass_test("third-person shows view_marker")
	else:
		_fail_test("third-person should show view_marker")

func _test_raycast_hit_point():
	var hud_src = _read_file("res://scripts/ui/hud.gd")

	# 验证 _raycast_gun_hit_point 函数存在
	var ray_fn = hud_src.find("func _raycast_gun_hit_point")
	if ray_fn != -1:
		_pass_test("_raycast_gun_hit_point function exists")
	else:
		_fail_test("_raycast_gun_hit_point function missing")
		return

	var fn_body = hud_src.substr(ray_fn, 800)

	# 验证使用 PhysicsRayQueryParameters3D.create
	if fn_body.find("PhysicsRayQueryParameters3D.create") != -1:
		_pass_test("uses PhysicsRayQueryParameters3D.create for raycast")
	else:
		_fail_test("should use PhysicsRayQueryParameters3D.create")

	# 验证 collision_mask = 3（world + vehicles）
	if fn_body.find("collision_mask = 3") != -1:
		_pass_test("collision_mask = 3 (world + vehicles)")
	else:
		_fail_test("collision_mask should be 3 (world + vehicles)")

	# 验证排除自身载具
	if fn_body.find("player_vehicle.get_rid()") != -1:
		_pass_test("excludes player vehicle RID")
	else:
		_fail_test("should exclude player vehicle RID")

	# 验证排除空气边界
	if fn_body.find("get_air_boundary_rids") != -1:
		_pass_test("excludes air boundary RIDs")
	else:
		_fail_test("should exclude air boundary RIDs")

	# 验证第三人称分支调用 _raycast_gun_hit_point
	var tp_idx = hud_src.find("is_tank and player_vehicle.is_player_controlled")
	if tp_idx != -1:
		var after_tp = hud_src.substr(tp_idx, 600)
		if after_tp.find("_raycast_gun_hit_point") != -1:
			_pass_test("third-person calls _raycast_gun_hit_point")
		else:
			_fail_test("third-person should call _raycast_gun_hit_point")
	else:
		_fail_test("third-person branch not found")

	# 验证不再使用固定 500m 投影（仅作为 fallback）
	var fixed_500 = hud_src.find("gun_dir * 500.0")
	if fixed_500 == -1:
		# 也检查 fallback 中的 500.0
		var fallback_500 = fn_body.find("dir * 500.0")
		if fallback_500 != -1:
			_pass_test("500m only used as raycast fallback")
		else:
			_fail_test("500m fallback missing in _raycast_gun_hit_point")
	else:
		_fail_test("still uses fixed 500m projection in third-person (not raycast)")

func _test_scope_camera_alignment():
	var tank_src = _read_file("res://scripts/vehicles/tank.gd")

	# 找到 _setup_scope 函数（注意函数名是 _setup_scope 不是 _setup_scope_camera）
	var setup_idx = tank_src.find("func _setup_scope")
	if setup_idx == -1:
		_fail_test("_setup_scope function not found")
		return
	_pass_test("_setup_scope function found")

	var func_body = tank_src.substr(setup_idx, 1500)

	# scope_camera 挂在 gun_node 上
	if func_body.find("gun_node.add_child(scope_camera)") != -1:
		_pass_test("scope_camera is child of gun_node")
	else:
		_fail_test("scope_camera should be child of gun_node")

	# 位置沿炮管轴线（Z 由 AABB 自动推算），X/Y 为零消除横向视差
	if func_body.find("scope_camera.position = Vector3(0, 0, cam_z)") != -1:
		_pass_test("scope_camera position = (0,0,cam_z) along gun axis (auto from AABB)")
	else:
		_fail_test("scope_camera should use cam_z from AABB/meta for Z position")

	# 零旋转偏移
	if func_body.find("scope_camera.rotation = Vector3.ZERO") != -1:
		_pass_test("scope_camera rotation = ZERO (aligned with gun)")
	else:
		_fail_test("scope_camera should have zero rotation offset")

func _test_fire_direction_matches_crosshair():
	var vehicle_src = _read_file("res://scripts/vehicles/vehicle.gd")

	# fire() 使用 muzzle_node 的全局位置和旋转
	if vehicle_src.find("muzzle_node.global_position") != -1:
		_pass_test("fire() uses muzzle_node.global_position")
	else:
		_fail_test("fire() should use muzzle_node.global_position")

	if vehicle_src.find("muzzle_node.global_rotation") != -1:
		_pass_test("fire() uses muzzle_node.global_rotation")
	else:
		_fail_test("fire() should use muzzle_node.global_rotation")

	# projectile.launch() 方向
	var proj_src = _read_file("res://scripts/weapons/projectile.gd")
	if proj_src.find("-Basis.from_euler(global_rotation).z") != -1:
		_pass_test("projectile uses -Basis.from_euler(global_rotation).z (matches muzzle)")
	else:
		_fail_test("projectile direction should match muzzle_node transform")

	# HUD 十字准心使用 -muzzle_node.global_transform.basis.z
	var hud_src = _read_file("res://scripts/ui/hud.gd")
	if hud_src.find("-player_vehicle.muzzle_node.global_transform.basis.z") != -1:
		_pass_test("HUD crosshair uses -muzzle_node.global_transform.basis.z (same as fire)")
	else:
		_fail_test("HUD crosshair should use muzzle_node transform basis")

func _test_tank_is_scope_mode_is_var():
	var tank_src = _read_file("res://scripts/vehicles/tank.gd")

	# 验证 is_scope_mode 声明为 var（属性），不是 func（方法）
	var var_decl = tank_src.find("var is_scope_mode:")
	if var_decl != -1:
		_pass_test("is_scope_mode declared as var (property) in tank.gd")
	else:
		_fail_test("is_scope_mode should be declared as var in tank.gd")

	# 验证没有 func is_scope_mode 方法声明
	var func_decl = tank_src.find("func is_scope_mode")
	if func_decl == -1:
		_pass_test("no 'func is_scope_mode' method (correctly a property)")
	else:
		_fail_test("is_scope_mode should NOT be a method")

func _read_file(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("  ERROR: Cannot read %s" % path)
		return ""
	var content = file.get_as_text()
	file.close()
	return content

func _pass_test(msg: String):
	_pass += 1
	print("  PASS: %s" % msg)

func _fail_test(msg: String):
	_fail += 1
	_errors.append(msg)
	print("  FAIL: %s" % msg)

func _report():
	print("")
	print("=== Results: %d passed, %d failed ===" % [_pass, _fail])
	if _errors.size() > 0:
		print("Errors:")
		for e in _errors:
			print("  - %s" % e)
		quit(1)
	else:
		quit(0)
