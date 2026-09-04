extends "res://scripts/vehicles/vehicle.gd"
## 直升机载具 - 战雷式鼠标引导飞控
## 准星固定在屏幕中心（视角中心），鼠标移动引导机头朝向目标指向，机头收敛后与准心重合
## 控制：鼠标=引导机头朝向, 滚轮=总距(升降), W/S=俯仰(机头上下+前飞/后飞推力), A/D=滚转(左右翻滚), Q/E=偏航
const AIR_DENSITY: float = 1.225  # 海平面空气密度（kg/m³，ISA 标准大气）

# === P0-P8 物理模型参数（SI 单位，数据驱动）===
@export var mass_kg: float = 8000.0              # 质量（kg，AH-64 空重5165/最大10433）
@export var rotor_radius: float = 7.3            # 主旋翼半径（m）
@export var rotor_omega_nominal: float = 30.0    # 标称旋翼角速度（rad/s ≈ 289 RPM）
@export var ct_max: float = 0.035               # 最大拉力系数（collective=1.0 时 C_T）
@export var drag_area: float = 6.0               # 寄生阻力面积 Cd0×S_ref（m²）
@export var max_cyclic_angle: float = 0.175     # 最大周期变距角（rad，~10°）
@export var vne: float = 81.4                   # 不可逾越速度（m/s = 293 km/h）
@export var moment_of_inertia: float = 1.0 # 姿态响应惯量（P2 力矩/惯量→角加速度；1.0 使 PD 控制器 τ≈0.22s）
@export var rotor_inertia: float = 1000.0       # 旋翼转动惯量（kg·m²，RPM 动态用）
@export var max_engine_power: float = 7000000.0 # 发动机最大功率（W，游戏重力20：诱导3.17+剖面2.68=5.85MW需7MW余量）
@export var yaw_torque: float = 2.0          # A/D 偏航辅助速率
@export var pitch_torque: float = 1.5
@export var roll_torque: float = 1.5         # 滚转改平速率
@export var auto_stabilize: float = 3.0
@export var collective_wheel_step: float = 0.08
# === W/S 键盘俯仰 + Q/E 键盘偏航 + 自动回正 ===
@export var keyboard_pitch_rate: float = 60.0  # W/S 调整 target_pitch 速率（度/秒）
@export var keyboard_yaw_rate: float = 45.0    # Q/E 调整 target_yaw 速率（度/秒）
@export var auto_center_enabled: bool = true   # 无输入时自动改平
@export var auto_center_delay: float = 0.5     # 无输入多久后开始改平（秒）
@export var auto_center_speed: float = 3.0     # 改平收敛速率
# === 战雷式鼠标引导飞控（速度矢量引导：机头最短旋转收敛到准星，转弯协调压坡）===
@export var aim_sensitivity: float = 0.9     # 鼠标灵敏度（度/像素）
@export var max_aim_pitch_up: float = 40.0   # 目标指向最大抬头角（度）
@export var max_aim_pitch_down: float = -90.0 # 目标指向最大俯冲角（度）：-90°=垂直俯冲（与 heli_ah64.json 覆盖值一致）
@export var guidance_gain: float = 1.2        # 引导速率增益（rad/s 每 rad 误差）
@export var max_guidance_rate: float = 1.6    # 最大引导角速度（rad/s，同时是姿态收敛速率上限）
@export var bank_limit: float = 0.7           # 协调压坡角上限（rad）
@export var rudder_assist_deg: float = 18.0   # A/D 偏航辅助偏置（度）
@export var ground_turn_rate: float = 45.0    # 地面滑行水平转向速率（度/秒，前轮转向，跟随准星偏航）
@export var cam_follow_speed: float = 5.0    # 相机跟随目标指向的平滑速度

# === 起落架 ===
@export var gear_retract_speed: float = 1.2    # 起落架收放速度（动画 0→1 所需时间的倒数）
@export var gear_retract_offset: float = 0.5   # 收起时起落架整体上移距离（缩进机腹，m）

var gear_deployed: bool = true        # 当前是否放下（true=放下；贴地/停机时强制放下）
var gear_anim: float = 1.0            # 收放动画进度：1=完全放下，0=完全收起
var gear_container: Node3D = null     # 模型中的 LandingGear 容器
var _gear_base_y: float = 0.0         # 容器模型基准高度（收起 = 基准 + offset 上移）
# === 战雷式鼠标引导飞控参数 ===
var main_rotor_node: Node3D = null
var tail_rotor_node: Node3D = null
# 旋翼 RPM（rad/s，P4 动态变化；驱动升力+视觉旋转）
var rotor_omega: float = 30.0
# 衍生几何量（_apply_helicopter_params 中从 rotor_radius 计算）
var rotor_diameter: float = 14.6
var rotor_area: float = 167.42
var angular_velocity: Vector3 = Vector3.ZERO
var is_flying: bool = false
var camera_3d: Camera3D = null
var camera_pivot: Node3D = null
# 鼠标引导的目标指向（世界系，弧度；yaw 正=左偏，pitch 正=抬头）
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var collective: float = 0.0
var input_yaw: float = 0.0
var input_pitch: float = 0.0  # W/S -> 俯仰输入（键盘控制 target_pitch，机体俯仰后升力矢量自然前倾产生前进推力）
var _mouse_idle_time: float = 999.0  # 鼠标空闲计时（用于 auto_center）
# 高度悬停（F键，可在设置中自定义）：激活时锁定当前高度并制动水平速度
var hover_active: bool = false
var hover_target_y: float = 0.0
# 物理高度悬停（总距级联控制，而非直接设速度）：
#   外环：高度误差 → 目标垂直速度；内环：垂直速度误差 → 总距（升力），形成真实二阶悬停
var hover_height_gain: float = 1.2      # 外环增益：1m 高度误差 → 目标垂直速度(m/s)
var hover_speed_limit: float = 5.0      # 外环目标垂直速度上限(m/s)
var hover_speed_gain: float = 0.06      # 内环增益：1m/s 速度误差 → 总距增量（也即悬停阻尼）
var hover_collective_rate: float = 3.0  # 悬停总距作动速率（0~1 全行程所需秒数的倒数）
# 非悬停模式垂直阻尼增益（旋翼入流反馈：爬升减推力、下降增推力）
# 物理依据：动量理论中诱导速度随垂直速度变化，爬升时入流减小→有效推力降，
# 下降时入流增大→有效推力升，形成天然阻尼。悬停模式由内环速度阻尼提供，不叠加。
@export var vertical_damping_gain: float = 0.5
var is_public_local: bool = false  # 公网模式下的本地玩家
var _skill_selector: RefCounted = null  # 当前技能目标选择器（移动端技能按钮）
# 公网状态上报计时（与 tank.gd 一致的 30Hz 输入 + 15Hz 状态）
var _net_input_timer: float = 0.0
var _net_state_timer: float = 0.0

# 直升机使用远大于坦克战场的大边界（写 _init 而非重声明，避免遮蔽基类 use_air_boundary）
func _init() -> void:
	use_air_boundary = true
	# 抗摔能力由载具 json physics.crash_impact_scale 软定义（vehicle.gd _apply_physics_params 读取），
	# 不在此硬编码，方便后续玩家导入自定义直升机时逐车配置
	# 空中禁修名单：引擎/传动/主旋翼/尾桨/油箱须着陆后修复
	repair_ground_only_modules = ["engine", "transmission", "main_rotor", "tail_rotor", "fuel_tank"]

func _ready() -> void:
	super._ready()
	_setup_rotor_nodes()
	if is_player_controlled:
		_setup_aircraft_camera()
		_apply_helicopter_params(vehicle_data.get("physics", {}))
		target_yaw = rotation.y
		target_pitch = rotation.x
		# 立即设置摄像机朝向机头方向，避免初始视角与准心不一致
		_sync_camera_immediate()
		# 移动端：显示飞行升降按钮（延迟一帧再试一次，防止时序问题）
		_show_mobile_air_buttons()
		call_deferred("_show_mobile_air_buttons")
		# 移动端：连接武器/弹药/维修/技能/自由视角信号（幂等）
		_connect_mobile_controls()
		call_deferred("_connect_mobile_controls")

func _connect_mobile_controls() -> void:
	"""连接移动端控制按钮信号（幂等：重复调用不会重复连接）。
	缺失会导致移动端无法切换武器/弹药/维修/技能/自由视角——对齐 tank.gd 的完整连接。"""
	if not is_player_controlled:
		return
	var mobile = _get_mobile_controls()
	if not mobile:
		return
	if not mobile.repair_pressed.is_connected(start_repair):
		mobile.repair_pressed.connect(start_repair)
	if not mobile.ammo_selected.is_connected(select_ammo):
		mobile.ammo_selected.connect(select_ammo)
	if not mobile.weapon_selected.is_connected(switch_weapon):
		mobile.weapon_selected.connect(switch_weapon)
	if not mobile.skill_artillery_pressed.is_connected(_on_mobile_artillery):
		mobile.skill_artillery_pressed.connect(_on_mobile_artillery)
	if not mobile.skill_smoke_pressed.is_connected(_on_mobile_smoke):
		mobile.skill_smoke_pressed.connect(_on_mobile_smoke)
	if not mobile.free_look_pressed.is_connected(_on_mobile_free_look_down):
		mobile.free_look_pressed.connect(_on_mobile_free_look_down)
	if not mobile.free_look_released.is_connected(_on_mobile_free_look_up):
		mobile.free_look_released.connect(_on_mobile_free_look_up)
	if mobile.has_method("set_weapon_count"):
		mobile.set_weapon_count(get_weapon_count())
	print("[Helicopter] 移动端控制已连接")

func _on_mobile_artillery() -> void:
	_request_skill("artillery")

func _on_mobile_smoke() -> void:
	_request_skill("smoke")

func _on_mobile_free_look_down() -> void:
	"""移动端：按住进入自由视角（与 V 键一致）"""
	set_free_look(true)

func _on_mobile_free_look_up() -> void:
	set_free_look(false)

func _request_skill(skill_id: String) -> void:
	"""请求使用技能，打开目标选择界面"""
	if not request_skill(skill_id):
		return
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if not hud:
		confirm_skill(global_position)
		return
	_skill_selector = SkillTargetSelector.new(hud, self, skill_id)

func _show_mobile_air_buttons() -> void:
	"""移动端：显示飞行升降控制按钮"""
	var mobile = _get_mobile_controls()
	if mobile and mobile.has_method("set_air_buttons_visible"):
		mobile.set_air_buttons_visible(true)

func _get_terrain_builder() -> Node:
	"""查找地形构建器节点（用于查询地面高度）"""
	return get_tree().root.find_child("TerrainBuilder", true, false)

func _get_ground_height_at(x: float, z: float) -> float:
	"""获取指定XZ位置的地面高度（无地形返回0）"""
	var tb = _get_terrain_builder()
	if tb and tb.has_method("get_terrain_height"):
		return tb.get_terrain_height(x, z)
	return 0.0

func _get_agl() -> float:
	"""获取直升机当前位置相对于地面的高度（Above Ground Level）"""
	return global_position.y - _get_ground_height_at(global_position.x, global_position.z)

func setup_from_data(data: Dictionary) -> void:
	# 模型由基类在 super 中动态实例化并挂载，此刻才能找到旋翼 Pivot，重新绑定旋转节点
	super.setup_from_data(data)
	# main.gd 出生流程 add_child 先于 setup_from_data，_ready 时 vehicle_data 尚为空，
	# 在此统一补一次参数应用，保证 JSON 飞行参数（升力/灵敏度等）对玩家直升机始终生效
	_apply_helicopter_params(data.get("physics", {}))
	_setup_rotor_nodes()
	_setup_landing_gear()
	# 按模型 Turret2（机翼挂架）实际位置自动生成副武器发射点（改模型后无需手配）
	if data.get("model", {}).get("muzzles_from_model", false):
		_setup_muzzles_from_turret2()
	_setup_missile_visuals()
	# 武器槽此时已 setup，重连移动端保证 set_weapon_count 按钮数量正确（幂等）
	_connect_mobile_controls()

func _setup_muzzles_from_turret2() -> void:
	"""把副武器发射点直接绑定到模型 Turret2（机翼挂架）节点下，跟随模型变换。
	改模型后发射点/导弹视觉自动跟随挂架位置，无需手配坐标。
	发射点取挂架 AABB 左右两端（x min/max）、中心 y/z 为挂架中轴。"""
	var model_cfg: Dictionary = vehicle_data.get("model", {})
	var turret2 = find_child("Turret2", true, false) as MeshInstance3D
	if turret2 == null or turret2.mesh == null:
		push_warning("[Helicopter] muzzles_from_model 但找不到 Turret2 挂架节点，使用 JSON 手配 muzzles")
		return
	# 清理基类在 vehicle 下创建的旧发射点
	for old in extra_muzzle_nodes:
		if is_instance_valid(old):
			old.queue_free()
	extra_muzzle_nodes.clear()
	# 在 Turret2 节点下创建左右发射点（相对 Turret2 局部坐标；Turret2 在模型原点、mesh 顶点自带偏移）
	var bb := turret2.get_aabb()
	var cy: float = bb.get_center().y
	var cz: float = bb.get_center().z
	var mz := []
	for side_x in [bb.position.x, bb.position.x + bb.size.x]:
		var n := Node3D.new()
		n.name = "MuzzleFromModel%d" % extra_muzzle_nodes.size()
		n.position = Vector3(side_x, cy, cz)  # 相对 Turret2（跟随模型）
		turret2.add_child(n)
		extra_muzzle_nodes.append(n)
		var lp := to_local(n.global_position)  # 载具局部（同步给 JSON，供联机/调试）
		mz.append([lp.x, lp.y, lp.z])
	model_cfg["muzzles"] = mz
	print("[Helicopter] 发射点绑定 Turret2 节点（跟随模型）: ", mz)

func _setup_landing_gear() -> void:
	"""绑定模型中的 LandingGear 容器（收起时整体上移缩进机腹）"""
	gear_container = find_child("LandingGear", true, false)
	_gear_base_y = gear_container.position.y if gear_container else 0.0

func _setup_missile_visuals() -> void:
	"""AH-64 机翼挂架（Turret2）副武器视觉：在发射点生成地狱火导弹模型。
	glb 的 Turret2 只有挂架 mesh（Mesh12_back panel）不含导弹，用户反馈"挂架没有武器"。
	配置 model.missile_visual 后在每个发射点下方生成 count 枚导弹（圆柱体，长轴沿 Z 朝前）。
	导弹直接挂在发射点节点下（发射点已绑定 Turret2 时跟随模型挂架）。"""
	var model_cfg: Dictionary = vehicle_data.get("model", {})
	if not model_cfg.has("missile_visual"):
		return
	var mv: Dictionary = model_cfg["missile_visual"]
	var count: int = int(mv.get("count", 2))
	var mlen: float = float(mv.get("length", 1.6))
	var mrad: float = float(mv.get("radius", 0.09))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.25, 0.22)
	mat.roughness = 0.7
	var idx := 0
	# 优先用发射点节点（muzzles_from_model 时已绑定 Turret2，导弹跟随模型）；否则回退 JSON 坐标（挂 vehicle 下）
	if not extra_muzzle_nodes.is_empty():
		for base in extra_muzzle_nodes:
			# 发射点在模型节点下会继承 ImportedModel 的 scale（AH-64 为 0.4），
			# 导弹的几何尺寸/偏移须反补偿（÷scale），否则导弹缩小/偏移变短
			var s := Vector3.ONE
			if base is Node3D:
				s = (base as Node3D).global_transform.basis.get_scale()
			var sx := maxf(s.x, 0.001)
			var sy := maxf(s.y, 0.001)
			var sz := maxf(s.z, 0.001)
			for i in count:
				var miss := MeshInstance3D.new()
				miss.name = "HellfireVisual%d" % idx
				idx += 1
				var body := CylinderMesh.new()
				body.top_radius = mrad / sx
				body.bottom_radius = mrad / sx
				body.height = mlen / sy
				miss.mesh = body
				miss.material_override = mat
				# 圆柱默认长轴沿 Y，转到 Z（导弹沿前后轴，-Z 为前方）
				miss.rotation_degrees = Vector3(90, 0, 0)
				# 导弹在发射点下方并排（沿 Z 前后排列），相对发射点（offset ÷ scale 反补偿）
				miss.position = Vector3(0, -0.2 / sy, (i - (count - 1) / 2.0) * (mlen * 0.6) / sz)
				base.add_child(miss)
	elif model_cfg.has("muzzles"):
		for m in model_cfg["muzzles"]:
			var base := Vector3(float(m[0]), float(m[1]), float(m[2]))
			for i in count:
				var miss := MeshInstance3D.new()
				miss.name = "HellfireVisual%d" % idx
				idx += 1
				var body := CylinderMesh.new()
				body.top_radius = mrad
				body.bottom_radius = mrad
				body.height = mlen
				miss.mesh = body
				miss.material_override = mat
				miss.rotation_degrees = Vector3(90, 0, 0)
				miss.position = base + Vector3(0, -0.2, (i - (count - 1) / 2.0) * (mlen * 0.6))
				add_child(miss)
	print("[Vehicle] 添加 %d 枚地狱火导弹视觉" % idx)

func _setup_rotor_nodes() -> void:
	# 优先绑定场景中的 Pivot 容器（保持桨叶本体不旋转，由 Pivot 统一转动）
	main_rotor_node = find_child("MainRotorPivot", true, false)
	# 兼容旧模型：无 Pivot 时退化为直接旋转可见节点
	var main_rotor_merged := false  # 新结构：MainRotor 是"主轴+桨盘"合体 MeshInstance3D（无独立 Pivot 容器）
	if main_rotor_node == null:
		main_rotor_node = find_child("MainRotor", true, false)
		if main_rotor_node is MeshInstance3D and (main_rotor_node as MeshInstance3D).mesh:
			main_rotor_merged = true
	var model_cfg: Dictionary = vehicle_data.get("model", {})
	# AH-64 glb：尾桨（TailRotorPivot 的 mesh 轴+盘一体）。tail_rotor_static=false 时绑定并旋转。
	# 尾桨 mesh 相对节点有 x/y 偏移（AH-64: (0.61,-0.02)），直接绕节点 Z 转会公转；
	# 新建容器放节点位置、mesh 中心对齐容器原点 → 绕容器 Z 转即绕自身转（自转）
	if not model_cfg.get("tail_rotor_static", false):
		tail_rotor_node = find_child("TailRotorPivot", true, false)
		if tail_rotor_node == null:
			tail_rotor_node = find_child("TailRotor", true, false)
		if tail_rotor_node is MeshInstance3D and (tail_rotor_node as MeshInstance3D).mesh:
			var tr := tail_rotor_node as MeshInstance3D
			var cc: Vector3 = tr.get_aabb().get_center()
			if absf(cc.x) > 0.05 or absf(cc.y) > 0.05:
				var old_parent := tr.get_parent()
				var old_pos := tr.position  # 记录 TailRotorPivot 原位置（机尾上方），容器必须放这里
				# 可选整体偏移（model.tail_rotor_offset，ImportedModel 局部坐标/模型米，X 为左右）
				var tro: Array = model_cfg.get("tail_rotor_offset", [])
				var off := Vector3.ZERO
				if tro.size() >= 3:
					off = Vector3(float(tro[0]), float(tro[1]), float(tro[2]))
				var container := Node3D.new()
				container.name = "TailRotorRuntimePivot"
				container.position = old_pos + off
				old_parent.remove_child(tr)
				old_parent.add_child(container)
				container.add_child(tr)
				tr.position = -cc  # mesh 中心对齐容器原点（=TailRotorPivot 原位置）
				tail_rotor_node = container
	# AH-64 glb：MainRotorPivot 节点自身在模型原点 (0,0,0)，而主旋翼/桨盘 mesh 在模型坐标别处，
	# 直接 rotate_y 会绕模型原点转导致"旋翼旋转位置不对"。按 model.main_rotor_pivot（模型原始坐标）
	# 把旋转中心平移到旋翼轴心，隐藏 pivot 自身 mesh（主轴/桨毂，非对称不可随旋转），
	# 桨盘 mesh 中心 = pivot + main_rotor_offset（桨盘相对主轴中心的偏移，模型坐标）。
	if main_rotor_node:
		var pivot := Vector3.ZERO
		if model_cfg.has("main_rotor_pivot"):
			pivot = Vector3(
				float(model_cfg["main_rotor_pivot"][0]),
				float(model_cfg["main_rotor_pivot"][1]),
				float(model_cfg["main_rotor_pivot"][2]))
		elif main_rotor_merged:
			# 以模型为准：合体（主轴+桨盘）mesh 中心即旋转中心，未配置时自动读取。
			# 必须加节点 position——get_aabb() 是节点局部 AABB，mesh 顶点相对节点有偏移，
			# 仅取 mesh 中心会漏掉节点位置（新模型节点携带部件布局，如 AH-64 MainRotor 节点在 (0.07,9.62,0)）。
			pivot = (main_rotor_node as Node3D).position + (main_rotor_node as MeshInstance3D).get_aabb().get_center()
			print("[Helicopter] main_rotor_pivot 自动（合体 mesh 全局中心）: ", pivot)
		# 按模型位置关系（不自动找位置、不移动 mesh）：MainRotor 是"主轴+桨盘"合体 MeshInstance3D，
		# 其 mesh 相对节点 x/z≈0（mesh 在节点轴线上），直接绕 MainRotor 节点局部 Y 旋转即自转，
		# mesh 保持模型原始位置。不新建容器、不做 mesh 中心对齐、不隐藏 mesh。
		if main_rotor_merged:
			main_rotor_node = find_child("MainRotor", true, false)
			return
		# 先记录主轴半高（模型坐标），再移动 pivot——移动后 mesh 顶点叠加 pivot 坐标会翻倍错位
		var pivot_half_h := 0.0
		if main_rotor_node is MeshInstance3D and (main_rotor_node as MeshInstance3D).mesh:
			pivot_half_h = (main_rotor_node as MeshInstance3D).get_aabb().size.y * 0.5
		# 移动 pivot 到旋转轴心（模型原始坐标）
		main_rotor_node.position = pivot
		# 隐藏 pivot 自身及子树中所有非 MainRotor 的 mesh（主轴/桨毂，非对称不可随旋转）。
		# glb 节点 translation=[0,0,0]，mesh 顶点含模型坐标；移动 pivot 后 mesh 出现在 pivot+vertex
		# （坐标翻倍），必须隐藏否则 mast 会绕 pivot 大半径公转（"旋翼绕机体公转"bug）。
		# 兼容两种 GLTF 导入结果：pivot 自身为 MeshInstance3D（直接 mesh=null），
		# 或 pivot 为 Node3D 容器（需遍历子 mesh 逐一隐藏）。
		if main_rotor_node is MeshInstance3D and (main_rotor_node as MeshInstance3D).mesh:
			(main_rotor_node as MeshInstance3D).mesh = null
		for mi in main_rotor_node.find_children("*", "MeshInstance3D", true, false):
			if mi.name != "MainRotor":
				mi.visible = false
		var rotor = find_child("MainRotor", true, false)
		if rotor:
			# glb 桨盘 mesh 顶点相对 MainRotor 节点有大偏移（模型坐标），
			# 取 mesh 局部中心取负抵消之，再加 main_rotor_offset（桨盘相对主轴中心的偏移，模型坐标）。
			# 未配置 offset 时默认 offset.y = 主轴半高，使桨盘落在旋翼轴顶（AH-64 桨盘应高出机身顶 ~1.5m，
			# 否则桨盘贴近机身顶、旋翼轴几乎不可见，看起来"轴不对"）。
			var offset := Vector3(0, pivot_half_h, 0)
			if model_cfg.has("main_rotor_offset"):
				offset = Vector3(
					float(model_cfg["main_rotor_offset"][0]),
					float(model_cfg["main_rotor_offset"][1]),
					float(model_cfg["main_rotor_offset"][2]))
			if rotor is MeshInstance3D and (rotor as MeshInstance3D).mesh:
				rotor.position = -(rotor as MeshInstance3D).get_aabb().get_center() + offset
			else:
				rotor.position = offset

func _setup_aircraft_camera() -> void:
	var pivot = Node3D.new()
	pivot.name = "AircraftCameraPivot"
	# top_level 脱离父级变换：相机锚点不继承机身滚转/俯仰旋转，避免机动时绕机体画圈抖动
	# （与 airplane.gd / tank.gd 的 CameraPivot 一致做法）
	pivot.top_level = true
	pivot.position = Vector3(0, 3.0, 0)  # 基准偏移（位置由 _update_camera 手动跟随覆盖）
	add_child(pivot)
	var cam = Camera3D.new()
	cam.name = "AircraftCamera"
	cam.position = Vector3(0, 5.5, 20.0)
	cam.fov = 70.0
	pivot.add_child(cam)
	cam.current = true
	camera_3d = cam
	camera_pivot = pivot

func _physics_process(delta: float) -> void:
	if is_destroyed:
		velocity.y -= GRAVITY * delta
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, delta * 0.5)
		rotation.x += angular_velocity.x * delta
		rotation.y += angular_velocity.y * delta
		rotation.z += angular_velocity.z * delta
		move_and_slide()
		return
	if is_repairing:
		velocity = Vector3.ZERO
		# 维修计时/完成必须在此推进（此前提前 return 导致永远卡在维修冻结态）
		repair_timer -= delta
		if repair_timer <= 0:
			_complete_repair()
		return
	if is_reloading:
		var loader_eff = get_loader_effectiveness()
		var reload_speed_factor = 0.4 + 0.6 * loader_eff
		reload_timer -= delta * reload_speed_factor
		if reload_timer <= 0:
			is_reloading = false
			can_fire = true
			reload_timer = 0.0
	if repair_cooldown > 0:
		repair_cooldown -= delta
	for skill_id in skills.keys():
		var skill = skills[skill_id]
		if skill.current_cooldown > 0:
			skill.current_cooldown = max(0.0, skill.current_cooldown - delta)
			skill_cooldown_changed.emit(skill_id, skill.current_cooldown)
	if is_player_controlled or (is_server_controlled and not is_remote_ai):
		if is_player_controlled and not GameManager.is_chat_open:
			# W/S = 俯仰（改视角 target_pitch），A/D + Q/E = 偏航（改视角 target_yaw）
			input_pitch = Input.get_axis("move_backward", "move_forward")
			# A/D 和 Q/E 都修改 target_yaw（改视角，机体由引导系统自然跟随）
			var ad_yaw := Input.get_axis("turn_left", "turn_right")  # A=-1, D=+1
			var qe_yaw := Input.get_axis("turret_left", "turret_right")  # Q=-1, E=+1
			var total_yaw := ad_yaw + qe_yaw
			if abs(total_yaw) > 0.01:
				target_yaw = wrapf(target_yaw - deg_to_rad(total_yaw * keyboard_yaw_rate) * delta, -PI, PI)
			# 键盘输入重置自动回正计时（释放后有 auto_center_delay 秒缓冲再回正）
			if abs(input_pitch) > 0.01 or abs(total_yaw) > 0.01:
				_mouse_idle_time = 0.0
			# input_yaw 仍用于网络同步（保留 A/D 方向信息）
			input_yaw = Input.get_axis("turn_right", "turn_left")
			# 移动端触摸输入（与键盘叠加）：升降按钮=总距（替代滚轮），摇杆=前后/偏航，拖动=机头引导
			var mobile = _get_mobile_controls()
			if mobile:
				if (mobile.pitch_up_active or mobile.pitch_down_active) and hover_active:
					_toggle_hover()  # 悬停中按升降：先退出悬停，再手动调整总距
				var step_scale: float = 1.0
				if hover_active:
					step_scale = 0.0  # 悬停中总距由高度控制器接管
				if mobile.pitch_up_active:
					collective = clamp(collective + collective_wheel_step * 1.5 * step_scale, 0.0, 1.0)
				elif mobile.pitch_down_active:
					collective = clamp(collective - collective_wheel_step * 1.5 * step_scale, 0.0, 1.0)
				if abs(mobile.joystick_y) > 0.05:
					input_pitch = clamp(input_pitch + mobile.joystick_y, -1.0, 1.0)
				if abs(mobile.joystick_x) > 0.05:
					# 移动端摇杆左右 → 修改 target_yaw（改视角）
					target_yaw = wrapf(target_yaw + deg_to_rad(mobile.joystick_x * keyboard_yaw_rate) * delta, -PI, PI)
				if mobile.look_delta.length() > 0.01:
					# 手指上滑(look_delta.y<0) → target_pitch增大 → 抬头/准心上移
					target_yaw -= deg_to_rad(mobile.look_delta.x * 0.3)
					target_pitch = clamp(target_pitch - deg_to_rad(mobile.look_delta.y * 0.3), deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
					target_yaw = wrapf(target_yaw, -PI, PI)
					_mouse_idle_time = 0.0
					mobile.look_delta = Vector2.ZERO
			# 按住开火：每帧轮询（fire() 自带装填/冷却门控限速，按住连续射击）
			# 移动端：触摸会模拟鼠标左键（fire 动作），必须隔离否则点击屏幕任意位置都开火；
			# 有移动端只认开火按钮 fire_held，无移动端认 fire 动作（与 tank.gd 口径一致）
			if (mobile and mobile.fire_held) or (not mobile and Input.is_action_pressed("fire")):
				fire()
		_update_flight(delta)
		_update_turret(delta)
		_update_lock_on(delta)
	if main_rotor_node:
		# 主桨：绕 Pivot 局部 Y 轴旋转，转速=实际 RPM（P4：不再固定 30 rad/s）
		main_rotor_node.rotate_y(delta * rotor_omega)
	if tail_rotor_node:
		# 尾桨：绕局部 X 轴自转（盘面法线沿 X），转速=主桨×1.5×尾桨效率
		var te: float = _get_module_effectiveness("tail_rotor")
		tail_rotor_node.rotate_x(delta * rotor_omega * 1.5 * te)
	# 起落架收放动画推进（含贴地强制放下）
	if is_on_floor() or _get_agl() < 2.5:
		gear_deployed = true
	_update_landing_gear(delta)
	# 尾桨失效自旋已在 _update_flight 姿态力矩中处理（P5：发动机反扭矩）
	var pre_move_vel := velocity
	move_and_slide()
	# 地面高度兜底：防止穿透 trimesh 地形碰撞体陷入地底
	var ground_h = _get_ground_height_at(global_position.x, global_position.z)
	if global_position.y < ground_h + 0.5:
		global_position.y = ground_h + 0.5
		if velocity.y < 0:
			velocity.y = 0.0
	# 高速撞击损伤（悬停/贴地低速法向≈0 不误伤，高速撞地/撞障碍物按速度分级）
	_check_crash_impact(pre_move_vel)
	if enforce_map_bounds and map_half_size > 0:
		if global_position.x > map_half_size:
			global_position.x = map_half_size
			velocity.x = 0.0
		elif global_position.x < -map_half_size:
			global_position.x = -map_half_size
			velocity.x = 0.0
		if global_position.z > map_half_size:
			global_position.z = map_half_size
			velocity.z = 0.0
		elif global_position.z < -map_half_size:
			global_position.z = -map_half_size
			velocity.z = 0.0
	# 客户端：插值到服务器权威状态（远程直升机纯视觉；本地模拟内部自行忽略）
	_interpolate_network_state(delta)
	# 自由视角退出后，相机偏移平滑衰减还原
	_process_free_look_restore(delta)
	current_speed = velocity.length()  # 同步给 HUD/联机（HUD 直读 current_speed）
	speed_changed.emit(velocity.length())
	altitude_changed.emit(global_position.y)
	# 公网模式：发送输入和状态到服务器（与 tank.gd 速率一致，保证 last_seen 持续刷新、进广播列表）
	if is_public_local and NetworkManager.game_connected_flag:
		var mobile = _get_mobile_controls()
		_net_input_timer += delta
		if _net_input_timer >= 1.0 / 30.0:
			_net_input_timer = 0.0
			NetworkManager.game_send_input(input_pitch, input_yaw, 0.0, 0.0, (mobile and mobile.fire_held) or (not mobile and Input.is_action_pressed("fire")))
		_net_state_timer += delta
		if _net_state_timer >= 1.0 / 15.0:
			_net_state_timer = 0.0
			NetworkManager.game_send_state(global_position, global_rotation, turret_yaw, gun_pitch, get_health_percent(), velocity)

func _update_flight(delta: float) -> void:
	var engine_eff: float = _get_module_effectiveness("engine")
	var trans_eff: float = _get_module_effectiveness("transmission")
	var power_factor: float = engine_eff * trans_eff
	# 主旋翼完好度：全毁=0 → 失去升力/前飞/悬停能力，只能坠机（与尾桨同源逻辑）
	var rotor_eff: float = _get_module_effectiveness("main_rotor")
	# 贴地判定：物理接触，或低空且无爬升（出生/滑行期 is_on_floor 往往延迟一拍才置位）
	var on_ground: bool = is_on_floor()
	if not on_ground and _get_agl() <= 2.6 and velocity.y < 1.5:
		on_ground = true
	if on_ground and collective < 0.05 and velocity.length() < 1.0:
		velocity = Vector3.ZERO
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, delta * 5.0)
		rotation.x = lerp(rotation.x, 0.0, delta * 3.0)
		rotation.z = lerp(rotation.z, 0.0, delta * 3.0)
		# 地面水平转向：机体绕世界Y平滑收敛到准星偏航（前轮转向，保持水平不抬头不滚转）
		if is_player_controlled:
			var yaw_cur: float = rotation.y
			var yaw_err: float = wrapf(target_yaw - yaw_cur, -PI, PI)
			var yaw_step: float = clamp(yaw_err, -deg_to_rad(ground_turn_rate) * delta, deg_to_rad(ground_turn_rate) * delta)
			rotation.y = wrapf(yaw_cur + yaw_step, -PI, PI)
		_update_camera(delta)
		return
	# === W/S 键盘俯仰：以 keyboard_pitch_rate 度/秒调整 target_pitch（与鼠标叠加）===
	# W(move_backward) → input_pitch=-1 → target_pitch 减小 → 低头（俯冲/前飞加速）
	# S(move_forward)  → input_pitch=+1 → target_pitch 增大 → 抬头（爬升/减速）
	if abs(input_pitch) > 0.01:
		target_pitch = clamp(target_pitch + deg_to_rad(input_pitch * keyboard_pitch_rate) * delta,
			deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
	# === 自动回正：无键盘+无鼠标输入超过延迟后，pitch→0(改平)、yaw→当前航向(直飞) ===
	if auto_center_enabled and not is_free_look_active():
		_mouse_idle_time += delta
		if _mouse_idle_time > auto_center_delay:
			var k: float = clampf(1.0 - exp(-auto_center_speed * delta), 0.0, 1.0)
			# 俯仰回正：无 W/S 输入时 target_pitch → 0（改平）
			if abs(input_pitch) < 0.01:
				target_pitch = lerpf(target_pitch, 0.0, k)
				if absf(target_pitch) < deg_to_rad(0.5):
					target_pitch = 0.0
			# 偏航回正：无 A/D + Q/E 输入时 target_yaw → 当前航向 rotation.y（直飞）
			if abs(Input.get_axis("turn_left", "turn_right")) < 0.01 and abs(Input.get_axis("turret_left", "turret_right")) < 0.01:
				var yaw_err: float = wrapf(target_yaw - rotation.y, -PI, PI)
				target_yaw = wrapf(rotation.y + yaw_err * (1.0 - k), -PI, PI)
	# === 战雷式鼠标引导：机头最短旋转收敛到准星（目标指向），bank 由协调压坡自动计算 ===
	var target_dir: Vector3 = -Basis.from_euler(Vector3(target_pitch, target_yaw, 0.0)).z
	# 协调压坡角：基于期望转向速率与水平速度（向心加速度 → 滚转角）
	var bank: float = 0.0
	var f_h: Vector3 = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	if f_h.length() > 0.01:
		f_h = f_h.normalized()
		var t_h: Vector3 = Vector3(target_dir.x, 0.0, target_dir.z)
		if t_h.length() > 0.01:
			t_h = t_h.normalized()
			var turn_err: float = acos(clamp(f_h.dot(t_h), -1.0, 1.0))
			var turn_sign: float = sign(f_h.cross(t_h).y)  # 正=目标在机头左侧（左转）
			var want_rate: float = clamp(turn_err * guidance_gain, -max_guidance_rate, max_guidance_rate)
			var v_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
			var lat_accel: float = abs(want_rate) * v_h.length()
			bank = clamp(atan2(lat_accel, GRAVITY), -bank_limit, bank_limit) * turn_sign
	# === 地面（未离地）约束：仅保留水平朝向，禁止俯仰/滚转，防止桨叶触地 ===
	if on_ground:
		var flat: Vector3 = Vector3(target_dir.x, 0.0, target_dir.z)
		if flat.length() < 0.01:
			flat = -global_transform.basis.z
			flat.y = 0.0
			if flat.length() < 0.01:
				flat = Vector3.FORWARD
		target_dir = flat.normalized()
		bank = 0.0
	# === P3：环境参数（空气密度随高度衰减 + 地面效应）===
	var rho: float = AIR_DENSITY * exp(-global_position.y / 8500.0)
	var agl: float = _get_agl()
	var ge_factor: float = 1.0
	if agl < rotor_diameter:
		ge_factor = 1.0 + 0.15 * (1.0 - agl / rotor_diameter)
	# === 姿态目标基（机头=target_dir，机背绕机头轴压坡 bank）===
	var f_n: Vector3 = target_dir.normalized()
	var ref_up: Vector3 = Vector3.UP
	if abs(f_n.dot(ref_up)) > 0.9999:
		ref_up = Vector3.LEFT
	var up_r: Vector3 = Quaternion(f_n, bank) * ref_up
	up_r = (up_r - f_n * up_r.dot(f_n)).normalized()
	if up_r.length() < 0.01:
		up_r = Vector3.RIGHT
	var x_axis: Vector3 = (up_r.cross(-f_n)).normalized()
	if x_axis.length() < 0.01:
		x_axis = Vector3.RIGHT
	var target_basis: Basis = Basis(x_axis, up_r, -f_n)
	# === P2：姿态力矩积分（替代 slerp 有限速率收敛）===
	var cur_q: Quaternion = global_transform.basis.get_rotation_quaternion()
	var tgt_q: Quaternion = target_basis.get_rotation_quaternion()
	var err_q: Quaternion = tgt_q * cur_q.inverse()
	if err_q.w < 0.0:
		err_q = -err_q
	var err_axis: Vector3 = err_q.get_axis()
	var err_angle: float = err_q.get_angle()
	if err_angle < 0.001:
		err_axis = Vector3.ZERO
	var desired_omega: Vector3 = err_axis * (err_angle * guidance_gain)
	if desired_omega.length() > max_guidance_rate:
		desired_omega = desired_omega.normalized() * max_guidance_rate
	# 体系坐标力矩（pitch=X, yaw=Y, roll=Z）
	var body_desired: Vector3 = global_transform.basis.inverse() * desired_omega
	var body_cur: Vector3 = global_transform.basis.inverse() * angular_velocity
	var body_torque: Vector3 = Vector3(
		pitch_torque * (body_desired.x - body_cur.x) - auto_stabilize * body_cur.x,
		yaw_torque * (body_desired.y - body_cur.y) - auto_stabilize * body_cur.y,
		roll_torque * (body_desired.z - body_cur.z) - auto_stabilize * body_cur.z
	)
	# P5：尾桨失效 → 发动机反扭矩失衡（体系 Y 轴净力矩）
	var tail_eff: float = _get_module_effectiveness("tail_rotor")
	if tail_eff < 1.0 and not on_ground:
		var engine_torque_mag: float = max_engine_power * power_factor / max(rotor_omega, 1.0)
		body_torque.y += engine_torque_mag * (1.0 - tail_eff)
	var torque: Vector3 = global_transform.basis * body_torque
	var ang_accel: Vector3 = torque / moment_of_inertia
	angular_velocity += ang_accel * delta
	# 应用旋转（世界系四元数）
	var omega_len: float = angular_velocity.length()
	if omega_len > 0.0001:
		var axis_w: Vector3 = angular_velocity / omega_len
		var angle_w: float = omega_len * delta
		var rot_q: Quaternion = Quaternion(axis_w, angle_w)
		global_transform.basis = Basis(rot_q) * global_transform.basis
		global_transform.basis = global_transform.basis.orthonormalized()
	# === P4：旋翼 RPM 动态（功率平衡驱动 RPM droop）===
	if rotor_eff < 0.01:
		rotor_omega = 0.0 # 旋翼全毁：无驱动扭矩，桨叶立即停转
	else:
		var tip_speed: float = rotor_omega * rotor_radius
		var ct_est: float = collective * ct_max
		var thrust_est: float = ct_est * rho * rotor_area * tip_speed * tip_speed * rotor_eff * ge_factor
		var v_h_est: float = Vector3(velocity.x, 0.0, velocity.z).length()
		var v_i_h_est: float = sqrt(max(thrust_est, 0.0) / max(2.0 * rho * rotor_area, 0.001))
		var v_i_est: float = v_i_h_est
		if v_h_est > 0.1:
			v_i_est = v_i_h_est * v_i_h_est / sqrt(v_h_est * v_h_est + v_i_h_est * v_i_h_est)
		var p_induced: float = thrust_est * v_i_est
		var p_profile: float = 0.00125 * rho * rotor_area * tip_speed * tip_speed * tip_speed
		var p_parasite: float = 0.5 * rho * v_h_est * v_h_est * drag_area * v_h_est
		var p_required: float = p_induced + p_profile + p_parasite
		var p_avail: float = max_engine_power * power_factor
		# P3：自转（发动机失效+下降时，上升气流驱动旋翼维持 RPM）
		if power_factor < 0.1 and velocity.y < -3.0:
			var auto_p: float = abs(velocity.y) * rho * rotor_area * rotor_radius * 0.1
			p_avail = max(p_avail, auto_p)
		# 发动机调速器：功率充裕时维持额定 RPM，不足时 droop
		if p_avail >= p_required:
			rotor_omega = move_toward(rotor_omega, rotor_omega_nominal, delta * 10.0)
		else:
			var domega: float = (p_avail - p_required) / max(rotor_inertia * max(rotor_omega, 1.0), 1.0)
			rotor_omega = clamp(rotor_omega + domega * delta, 0.0, rotor_omega_nominal * 1.1)
	# === 悬停高度控制器（级联：高度→目标垂直速度→总距）===
	if hover_active and rotor_eff >= 0.01:
		var tip_speed_h: float = rotor_omega * rotor_radius
		var denom: float = ct_max * rho * rotor_area * tip_speed_h * tip_speed_h * rotor_eff * ge_factor
		var hover_balance: float = (mass_kg * GRAVITY) / max(denom, 0.001)
		var want_vy: float = clamp((hover_target_y - global_position.y) * hover_height_gain, -hover_speed_limit, hover_speed_limit)
		var ctrl: float = hover_balance + (want_vy - velocity.y) * hover_speed_gain
		collective = move_toward(collective, clamp(ctrl, 0.0, 1.0), hover_collective_rate * delta)
	# === P0：拉力计算（动量理论 T = C_T × ρ × A × (ωR)²）===
	var tip_speed3: float = rotor_omega * rotor_radius
	var ct: float = collective * ct_max
	var thrust: float = ct * rho * rotor_area * tip_speed3 * tip_speed3 * rotor_eff * ge_factor
	# === P3：涡环态（大下降率 + 低前飞速度 → 升力骤降）===
	var v_h2: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var v_i_h2: float = sqrt(max(thrust, 0.0) / max(2.0 * rho * rotor_area, 0.001))
	var descent_rate: float = max(0.0, -velocity.y)
	if descent_rate > 0.75 * v_i_h2 and v_h2 < 0.3 * v_i_h2 and thrust > 0.0:
		thrust *= 0.35
	# === P3：后行桨失速（高速时后退桨叶失速 → V_NE 限制）===
	var advance_ratio: float = v_h2 / max(tip_speed3, 0.001)
	if advance_ratio > 0.35:
		var stall_factor: float = clamp(1.0 - (advance_ratio - 0.35) / 0.15, 0.3, 1.0)
		thrust *= stall_factor
	# === 非悬停模式垂直阻尼（旋翼入流反馈：爬升减推力、下降增推力）===
	# 悬停模式由 hover_speed_gain 内环提供速度阻尼，不叠加此修正
	if not hover_active and rotor_eff > 0.01:
		var v_ref: float = max(v_i_h2, 5.0)
		thrust *= clamp(1.0 - velocity.y * vertical_damping_gain / v_ref, 0.5, 1.5)
	# === P0：升力（沿机体竖轴）+ 重力 ===
	var up_dir: Vector3 = global_transform.basis.y
	var lift_accel: float = thrust / mass_kg
	velocity += up_dir * lift_accel * delta
	velocity.y -= GRAVITY * delta
	# === P1：阻力（寄生 V² + 诱导 Glauert）===
	var V: float = velocity.length()
	if V > 0.1:
		var f_parasite: float = 0.5 * rho * V * V * drag_area
		var f_induced: float = 0.0
		if v_h2 > 1.0 and thrust > 0.0:
			var v_i_fw: float = v_i_h2 * v_i_h2 / sqrt(v_h2 * v_h2 + v_i_h2 * v_i_h2)
			f_induced = thrust * v_i_fw / v_h2
		var f_drag: float = f_parasite + f_induced
		velocity -= (velocity / V) * (f_drag / mass_kg) * delta
	# === 前进推力：来自旋翼拉力的水平分量（机体俯仰后拉力矢量自然前倾）===
	# WASD 只改视角（target_pitch/target_yaw），机体由引导系统收敛到目标姿态后，
	# 升力沿机体竖轴 up_dir 施加，低头时 up_dir 前倾 → 自然产生前进推力
	# === 悬停水平制动（垂直阻尼由控制器内环提供）===
	if hover_active:
		if rotor_eff < 0.01:
			hover_active = false
			_apply_hover_hint(false)
		else:
			velocity.x = lerp(velocity.x, 0.0, clamp(delta * 5.0, 0.0, 1.0))
			velocity.z = lerp(velocity.z, 0.0, clamp(delta * 5.0, 0.0, 1.0))
	# 更新摄像机（准星方向=目标指向，机头收敛后与其重合）
	_update_camera(delta)
	is_flying = _get_agl() > 1.0 or abs(velocity.y) > 1.0

func _update_camera(delta: float) -> void:
	if not camera_pivot:
		return
	# 手动跟随机体位置（top_level 下必须每帧设置），锚点固定在机体正上方基准，
	# 只取世界系偏移，不继承机身滚转/俯仰 -> 机动时不绕机体画圈，消除画面抖动
	camera_pivot.global_position = global_position + Vector3(0, 3.0, 0)
	# 相机朝向 = 目标指向（准星）的世界方向 + 自由视角偏移，水平保持（不随机体滚转）
	# 直接用目标角度构造四元数，去掉 atan2/asin 反解：俯仰接近±90°时反解 yaw 会
	# 因方向向量水平分量趋零而退化（噪声跳变），导致视角突然左右切换
	var target_quat: Quaternion = Quaternion(Basis.from_euler(Vector3(
		target_pitch + deg_to_rad(free_look_pitch),
		target_yaw + deg_to_rad(free_look_yaw),
		0.0)))
	var cur_quat: Quaternion = camera_pivot.global_transform.basis.get_rotation_quaternion()
	camera_pivot.global_transform.basis = Basis(cur_quat.slerp(target_quat, clamp(delta * cam_follow_speed, 0.0, 1.0)))
	# 防止摄像机穿到地底：整体抬高 pivot 世界位置（覆盖式、不累加局部坐标——
	# 旧实现 camera_pivot.position.y += diff 会把局部偏移永久残留，导致恢复飞行后相机一直偏高）
	if camera_3d and camera_3d.global_position.y < 1.0:
		camera_pivot.global_position.y += 1.0 - camera_3d.global_position.y

func _sync_camera_immediate() -> void:
	# 立即将相机对准机头方向（初始/复位）
	if not camera_pivot:
		return
	camera_pivot.global_position = global_position + Vector3(0, 3.0, 0)
	camera_pivot.global_transform.basis = global_transform.basis

func _toggle_hover() -> void:
	"""切换高度悬停：激活时锁定当前高度并制动水平速度，再按一次退出。
	贴地（y<2.6）时不激活，避免锁定贴地高度后升空又被拉回。"""
	if hover_active:
		hover_active = false
		_apply_hover_hint(false)
		return
	if global_position.y < 2.6:
		return
	hover_active = true
	hover_target_y = global_position.y
	_apply_hover_hint(true)

func _toggle_landing_gear() -> void:
	"""切换起落架收放。贴地（含低空 2.5m 内）时强制放下，仅在空中允许收起。"""
	if gear_deployed:
		if is_on_floor() or global_position.y < 2.5:
			gear_deployed = true
			return
		gear_deployed = false
	else:
		gear_deployed = true

func _update_landing_gear(delta: float) -> void:
	"""起落架动画：gear_anim 1=完全放下 → 0=完全收起（平滑过渡），
	并让整个 LandingGear 容器上移缩进机腹。"""
	var target: float = 1.0 if gear_deployed else 0.0
	if gear_anim < target:
		gear_anim = min(gear_anim + gear_retract_speed * delta, target)
	elif gear_anim > target:
		gear_anim = max(gear_anim - gear_retract_speed * delta, target)
	if gear_container:
		gear_container.position.y = _gear_base_y + (1.0 - gear_anim) * gear_retract_offset
		gear_container.visible = gear_anim > 0.02

func _apply_hover_hint(active: bool) -> void:
	"""同步 HUD 上的悬停状态提示（文案在 hud.gd 中维护）"""
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hover_active"):
		hud.set_hover_active(active)

func _apply_helicopter_params(physics: Dictionary) -> void:
	# P0-P8 物理模型参数（SI 单位，JSON 可覆盖）
	mass_kg = float(physics.get("mass_kg", mass_kg))
	rotor_radius = float(physics.get("rotor_radius", rotor_radius))
	rotor_omega_nominal = float(physics.get("rotor_omega_nominal", rotor_omega_nominal))
	ct_max = float(physics.get("ct_max", ct_max))
	drag_area = float(physics.get("drag_area", drag_area))
	max_cyclic_angle = float(physics.get("max_cyclic_angle", max_cyclic_angle))
	vne = float(physics.get("vne", vne))
	moment_of_inertia = float(physics.get("moment_of_inertia", moment_of_inertia))
	rotor_inertia = float(physics.get("rotor_inertia", rotor_inertia))
	max_engine_power = float(physics.get("max_engine_power", max_engine_power))
	# 衍生几何量
	rotor_diameter = rotor_radius * 2.0
	rotor_area = PI * rotor_radius * rotor_radius
	# 初始化 RPM 到标称值
	rotor_omega = rotor_omega_nominal
	# 姿态控制器参数
	yaw_torque = float(physics.get("yaw_torque", yaw_torque))
	pitch_torque = float(physics.get("pitch_torque", pitch_torque))
	roll_torque = float(physics.get("roll_torque", roll_torque))
	auto_stabilize = float(physics.get("auto_stabilize", auto_stabilize))
	collective_wheel_step = float(physics.get("collective_wheel_step", collective_wheel_step))
	# W/S 俯仰 + Q/E 偏航 + 自动回正
	keyboard_pitch_rate = float(physics.get("keyboard_pitch_rate", keyboard_pitch_rate))
	keyboard_yaw_rate = float(physics.get("keyboard_yaw_rate", keyboard_yaw_rate))
	auto_center_enabled = bool(physics.get("auto_center_enabled", auto_center_enabled))
	auto_center_delay = float(physics.get("auto_center_delay", auto_center_delay))
	auto_center_speed = float(physics.get("auto_center_speed", auto_center_speed))
	# 鼠标引导飞控
	aim_sensitivity = float(physics.get("aim_sensitivity", aim_sensitivity))
	max_aim_pitch_up = float(physics.get("max_aim_pitch_up", max_aim_pitch_up))
	max_aim_pitch_down = float(physics.get("max_aim_pitch_down", max_aim_pitch_down))
	guidance_gain = float(physics.get("guidance_gain", guidance_gain))
	max_guidance_rate = float(physics.get("max_guidance_rate", max_guidance_rate))
	bank_limit = float(physics.get("bank_limit", bank_limit))
	rudder_assist_deg = float(physics.get("rudder_assist_deg", rudder_assist_deg))
	ground_turn_rate = float(physics.get("ground_turn_rate", ground_turn_rate))
	cam_follow_speed = float(physics.get("cam_follow_speed", cam_follow_speed))
	# 起落架
	gear_retract_speed = float(physics.get("gear_retract_speed", gear_retract_speed))
	gear_retract_offset = float(physics.get("gear_retract_offset", gear_retract_offset))
	# 悬停级联控制参数
	hover_height_gain = float(physics.get("hover_height_gain", hover_height_gain))
	hover_speed_limit = float(physics.get("hover_speed_limit", hover_speed_limit))
	hover_speed_gain = float(physics.get("hover_speed_gain", hover_speed_gain))
	hover_collective_rate = float(physics.get("hover_collective_rate", hover_collective_rate))
	vertical_damping_gain = float(physics.get("vertical_damping_gain", vertical_damping_gain))

func _input(event: InputEvent) -> void:
	if not is_player_controlled or is_destroyed:
		return
	# 自由视角按键（V键，可自定义）
	_handle_free_look_input(event)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if is_free_look_active():
			# 自由视角：鼠标只转动观察方向（基类偏移单位为度），不写入目标指向
			# 鼠标上移(relative.y<0) → free_look_pitch增大 → 视角上仰
			free_look_yaw -= event.relative.x * aim_sensitivity
			free_look_pitch = clamp(free_look_pitch - event.relative.y * aim_sensitivity, -85.0, 85.0)
		else:
			# 鼠标引导目标指向（世界系：右移→右转，上移→抬头/准心上移）
			# 鼠标上移(relative.y<0) → target_pitch增大 → 抬头
			target_yaw -= deg_to_rad(event.relative.x * aim_sensitivity)
			target_pitch -= deg_to_rad(event.relative.y * aim_sensitivity)
			target_yaw = wrapf(target_yaw, -PI, PI)
			_mouse_idle_time = 0.0  # 重置自动回正计时器
	target_pitch = clamp(target_pitch, deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
	# 鼠标滚轮控制总距（升降）；悬停中由高度控制器接管，滚轮不调整
	if event is InputEventMouseButton and event.pressed and not hover_active:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			collective = clamp(collective + collective_wheel_step, 0.0, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			collective = clamp(collective - collective_wheel_step, 0.0, 1.0)
	# 高度悬停（F键，可自定义）：再按一次退出
	if event.is_action_pressed("hover"):
		_toggle_hover()
	# 起落架收放（空格键，可自定义）：贴地强制放下，空中可收起
	if event.is_action_pressed("landing_gear"):
		_toggle_landing_gear()
	# 开火已移至 _physics_process 每帧轮询按住状态（fire 键/移动端按钮连续射击）
	if event.is_action_pressed("repair"):
		start_repair()
	# 武器槽切换（Z=主武器，X=副武器）
	if event.is_action_pressed("weapon_1"):
		switch_weapon(0)
	if event.is_action_pressed("weapon_2") and get_weapon_count() >= 2:
		switch_weapon(1)
	# 弹药切换
	if event.is_action_pressed("ammo_1"):
		select_ammo(0)
	if event.is_action_pressed("ammo_2"):
		select_ammo(1)
	if event.is_action_pressed("ammo_3"):
		select_ammo(2)
