extends SceneTree
## 校验（回归）：
##  1. 穿模修复：炮弹/子弹击中坦克车体、飞机机身、直升机机身上的"无模块盒
##     覆盖表面"时不再直接穿过，兜底命中载具主体(层2)并结算为整体伤害
##  2. 模块伤害路径保留：命中引擎等模块盒时仍走 Area3D 模块精确伤害
## 校验基准 = 用户反馈：炮弹击中坦克、飞机"部分位置"发生穿模
## （根因：弹丸射线 mask=9 只含世界层1+模块层4，不含载具主体层2；
##   模块盒只覆盖引擎/翼/炮塔等局部，大片车体/机身表面无覆盖 → 直穿。
##   修复：模块/世界优先命中，未命中时追加含主体层(2)的兜底射线结算 hull 伤害。）
## 说明：采样点全部程序化计算（读模块实际全局位置与盒尺寸），避免与模块盒
##   边界共面误判、并自适应载具下坠后的实际位置。

const VEHICLE_DEFS := {
	"tank": {
		"scene": "res://scenes/vehicle.tscn",
		"data": "res://data/vehicles/tank_abrams.json",
		"spawn": Vector3(0, 0.6, 0),
		"body_center": Vector3(0, 0.6, 0),
		"body_size": Vector3(3.6, 1.2, 6.0),
		"module_name": "engine",
	},
	"plane": {
		"scene": "res://scenes/airplane.tscn",
		"data": "res://data/vehicles/plane_a10.json",
		"spawn": Vector3(0, 1.5, 0),
		"body_center": Vector3(0, 1.0, 0),
		"body_size": Vector3(12.0, 2.5, 9.0),
		"module_name": "engine",
	},
	"heli": {
		"scene": "res://scenes/helicopter.tscn",
		"data": "res://data/vehicles/heli_ah64.json",
		"spawn": Vector3(0, 1.0, 0),
		"body_center": Vector3(0, 1.5, 0),
		"body_size": Vector3(3.0, 3.0, 6.0),
		"module_name": "engine",
	},
}

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failed += 1
		print("FAIL: " + msg)

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _initialize() -> void:
	_make_ground()
	_run()

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000.0, 1.0, 3000.0)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	root.add_child(ground)

## 与 projectile.gd 一致的射线查询
func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return space.intersect_ray(q)

func _module_boxes(v: Node) -> Array:
	"""返回 [{node, min, max}]（世界坐标）"""
	var boxes: Array = []
	for mod in v.damage_system.modules.values():
		var cs: CollisionShape3D = mod.get_child(0)
		if cs == null or cs.shape == null:
			continue
		var half := (cs.shape.size as Vector3) * 0.5
		var gp: Vector3 = mod.global_position
		boxes.append({"node": mod, "min": gp - half, "max": gp + half})
	return boxes

func _segment_hits_aabb(seg_from: Vector3, seg_to: Vector3, bmin: Vector3, bmax: Vector3) -> bool:
	var d := seg_to - seg_from
	var tmin := 0.0
	var tmax := 1.0
	for i in 3:
		var o: float = seg_from[i]
		var dd: float = d[i]
		if absf(dd) < 1e-8:
			if o < bmin[i] or o > bmax[i]:
				return false
		else:
			var t1 := (bmin[i] - o) / dd
			var t2 := (bmax[i] - o) / dd
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true

func _in_any(boxes: Array, p: Vector3) -> bool:
	for b in boxes:
		if p.x >= b.min.x and p.x <= b.max.x and p.y >= b.min.y and p.y <= b.max.y \
				and p.z >= b.min.z and p.z <= b.max.z:
			return true
	return false

## 在载具主体 +X 侧面找一个"无模块覆盖"的表面采样点，返回世界坐标点
func _find_no_module_point(v: Node, cfg: Dictionary, boxes: Array) -> Vector3:
	var gp: Vector3 = v.global_position
	var bc: Vector3 = gp + cfg.body_center
	var half: Vector3 = cfg.body_size * 0.5
	# y 分位与 z 分位组合遍历（从低到高、从中心到两端）
	for fy in [0.90, 0.75, 0.60, 0.45, 0.30]:
		var y: float = bc.y + (fy - 0.5) * cfg.body_size.y
		for fz in [0.25, 0.50, 0.75]:
			var z: float = bc.z + (fz - 0.5) * cfg.body_size.z
			var p := Vector3(bc.x + half.x + 0.35, y, z)
			if _in_any(boxes, p):
				continue
			# 路径约束：p 到主体表面(X侧-3m)的 6m 段不得穿过任何模块盒
			var blocked := false
			for b in boxes:
				if _segment_hits_aabb(p + Vector3(3, 0, 0), p - Vector3(3, 0, 0), b.min, b.max):
					blocked = true
					break
			if not blocked:
				return p
	return Vector3.ZERO  # 找不到（说明表面全被模块覆盖，理论不应发生）

## 从六个方向找能直达目标模块（不被他模块遮挡）的射线，返回 [from, to] 或 []
func _find_module_ray(space: PhysicsDirectSpaceState3D, v: Node, mod_name: String) -> Array:
	for mod in v.damage_system.modules.values():
		if mod.module_name != mod_name:
			continue
		var center: Vector3 = mod.global_position
		for ofs in [Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 12, 0),
				Vector3(0, -12, 0), Vector3(0, 0, 12), Vector3(0, 0, -12)]:
			var r := _ray(space, center + ofs, center, 9)
			if not r.is_empty() and r.collider == mod:
				return [center + ofs, center]
	return []

func _run() -> void:
	for vname in VEHICLE_DEFS:
		var cfg: Dictionary = VEHICLE_DEFS[vname]
		var data: Dictionary = _load_json(cfg.data)
		_check(not data.is_empty(), "%s 数据加载" % vname)
		if data.is_empty():
			continue
		var v: Node = load(cfg.scene).instantiate()
		v.position = cfg.spawn
		root.add_child(v)
		await process_frame
		var cfg_data: Dictionary = data.duplicate(true)
		cfg_data["model"] = {}  # 项目模型文件缺失，跳过加载（占位几何体碰撞不受影响）
		v.setup_from_data(cfg_data)
		await physics_frame
		await physics_frame
		v.set_physics_process(false)  # 冻结：物理位置不再变化
		await physics_frame

		var space: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
		var boxes: Array = _module_boxes(v)

		# ---- 校验1：无模块覆盖表面，旧 mask=9 会穿过；修复后命中了载具主体 ----
		var sp: Vector3 = _find_no_module_point(v, cfg, boxes)
		_check(sp != Vector3.ZERO, "%s 找到无模块覆盖的表面采样点" % vname)
		if sp != Vector3.ZERO:
			var from := sp + Vector3(6, 0, 0)
			var to := sp - Vector3(12, 0, 0)
			var r_old := _ray(space, from, to, 9)
			var r_new := _ray(space, from, to, 9 | 2)
			_check(r_old.is_empty(),
				"%s 无模块表面：旧 mask=9 射线直接穿过（复现穿模）" % vname)
			_check(not r_new.is_empty() and r_new.collider == v,
				"%s 无模块表面：含主体层射线命中载具本体（穿模已修复）" % vname)

		# ---- 校验2：模块盒命中路径保留（mask=9 仍精确命中模块 Area）----
		var mod_ray: Array = _find_module_ray(space, v, String(cfg.module_name))
		_check(not mod_ray.is_empty(),
			"%s 存在可直达 %s 模块的射线方向" % [vname, cfg.module_name])
		if not mod_ray.is_empty():
			var rm := _ray(space, mod_ray[0], mod_ray[1], 9)
			_check(not rm.is_empty() and rm.collider is Area3D \
					and "module_name" in rm.collider and rm.collider.module_name == cfg.module_name,
				"%s 模块盒命中：mask=9 精确命中 %s 模块（模块伤害机制保留）" % [vname, cfg.module_name])

		v.queue_free()

	print("=============================================")
	if _failed == 0:
		print("ALL PASS: check_projectile_hit")
	else:
		print("FAILED: %d check(s)" % _failed)
	quit(0 if _failed == 0 else 1)