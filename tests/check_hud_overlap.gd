extends SceneTree
## 回归校验：HUD 布局防重叠（2026-08 新增）
## 覆盖约束：
##  1) 飞机/直升机（速度信息 4 行）spawn 后，SpeedLabel/HealthBar/ModuleContainer 三者矩形两两不相交
##  2) 坦克（速度 1 行）不触发重排，保持 main.tscn 默认布局（SpeedLabel 30~55）
##  3) 顶部提示队列（锁定状态/距离/目标、自由视角、悬停）两两不相交，且不与 HitMessage/KillMessage 相交
##  4) 悬停提示下移至 KillMessage 之下（y=390），不再压住命中提示

var _failed := 0
var _frame := 0
var _done := false
var _main: Node = null
var _hud: CanvasLayer = null

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _rects_disjoint(a: Rect2, b: Rect2) -> bool:
	return not a.intersects(b, false)

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")

class FakeVehicle:
	extends Node
	var vehicle_data: Dictionary = {}
	var damage_system = null

func _fake_vehicle(vtype: String) -> Node:
	var v := FakeVehicle.new()
	v.vehicle_data = {"type": vtype, "name": "Test"}
	return v

func _run_checks() -> void:
	_hud = _main.get_node_or_null("HUD") as CanvasLayer
	_check(_hud != null, "找到 HUD CanvasLayer")
	if _hud == null or not _hud.has_method("_on_player_vehicle_spawned"):
		_check(false, "HUD 脚本可加载并暴露 _on_player_vehicle_spawned")
		_done = true
		return

	var speed_label: Control = _hud.get_node_or_null("Panel/SpeedLabel")
	var health_bar: Control = _hud.get_node_or_null("Panel/HealthBar")
	var module_container: Control = _hud.get_node_or_null("Panel/ModuleContainer")
	var hit_message: Control = _hud.get_node_or_null("HitMessage")
	var kill_message: Control = _hud.get_node_or_null("KillMessage")
	_check(speed_label != null and health_bar != null and module_container != null, "左上信息面板节点齐全")

	# --- 坦克：1 行信息，保持默认布局 ---
	_hud._on_player_vehicle_spawned(_fake_vehicle("tank"))
	_check(absf(speed_label.offset_top - 30.0) < 0.001 and absf(speed_label.offset_bottom - 55.0) < 0.001,
		"坦克 SpeedLabel 保持默认布局 30~55 (实际 %.0f~%.0f)" % [speed_label.offset_top, speed_label.offset_bottom])
	_check(absf(health_bar.offset_top - 55.0) < 0.001, "坦克 HealthBar 保持默认 y=55 (实际 %.0f)" % health_bar.offset_top)

	# --- 飞机：4 行速度信息，左侧面板重排 ---
	_hud._on_player_vehicle_spawned(_fake_vehicle("airplane"))
	var s_r: Rect2 = speed_label.get_global_rect()
	var h_r: Rect2 = health_bar.get_global_rect()
	var m_r: Rect2 = module_container.get_global_rect()
	var label_h: float = s_r.size.y
	var flight_lines: int = 4
	_check(label_h >= flight_lines * 20.0, "飞机 SpeedLabel 高度容纳 4 行文本 (实际 %.0fpx)" % label_h)
	_check(_rects_disjoint(s_r, h_r), "飞机 速度区/血条 不相交")
	_check(_rects_disjoint(h_r, m_r), "飞机 血条/模块区 不相交")
	_check(_rects_disjoint(s_r, m_r), "飞机 速度区/模块区 不相交")
	_check(h_r.position.y >= s_r.position.y + s_r.size.y, "飞机 血条位于速度区之下")
	_check(m_r.position.y >= h_r.position.y + h_r.size.y, "飞机 模块区位于血条之下")

	# --- 直升机：同样 4 行信息 ---
	_hud._on_player_vehicle_spawned(_fake_vehicle("helicopter"))
	s_r = speed_label.get_global_rect()
	h_r = health_bar.get_global_rect()
	m_r = module_container.get_global_rect()
	_check(_rects_disjoint(s_r, h_r), "直升机 速度区/血条 不相交")
	_check(_rects_disjoint(h_r, m_r), "直升机 血条/模块区 不相交")

	# --- 顶部提示队列（动态创建） ---
	_hud.set_free_look_active(true)
	_hud.set_hover_active(true)
	var hover_label: Control = _hud.get_node_or_null("HoverLabel")
	var free_look_label: Control = _hud.get_node_or_null("FreeLookLabel")
	var lock_status: Control = _hud.get_node_or_null("LockHUD/LockStatusLabel")
	var lock_distance: Control = _hud.get_node_or_null("LockHUD/LockDistanceLabel")
	var lock_target: Control = _hud.get_node_or_null("LockHUD/LockTargetLabel")
	_check(hover_label != null and free_look_label != null, "悬停/自由视角提示节点已创建")
	_check(lock_status != null and lock_distance != null and lock_target != null, "锁定提示节点已创建")
	if hover_label and free_look_label and lock_status and lock_distance and lock_target:
		_check(absf(hover_label.position.y - 390.0) < 0.001, "悬停提示位于 y=390 (实际 %.0f)" % hover_label.position.y)
		var queue: Array = [lock_status, lock_distance, lock_target, free_look_label, hover_label]
		var refs: Array = [hit_message, kill_message]
		var all_ok := true
		for i in range(queue.size()):
			for j in range(i + 1, queue.size()):
				if not _rects_disjoint(queue[i].get_global_rect(), queue[j].get_global_rect()):
					all_ok = false
					print("   冲突: %s 与 %s" % [queue[i].name, queue[j].name])
			for k in refs.size():
				if queue[i].visible and not _rects_disjoint(queue[i].get_global_rect(), refs[k].get_global_rect()):
					all_ok = false
					print("   冲突: %s 与 %s" % [queue[i].name, refs[k].name])
		_check(all_ok, "顶部提示队列两两不相交且不压命中/击杀提示")

	_done = true

func _physics_process(delta: float) -> bool:
	if _done:
		# 汇总后退出
		print("RESULT: failed=%d" % _failed)
		quit(0 if _failed == 0 else 1)
		return false
	_frame += 1
	if _main == null:
		_main = current_scene
		return false
	if _frame < 10:
		return false
	_run_checks()
	return false

func _process(delta: float) -> bool:
	return _physics_process(delta)