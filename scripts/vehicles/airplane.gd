extends "res://scripts/vehicles/vehicle.gd"
## 固定翼飞机载具 - 战雷式鼠标引导飞控
## 准星固定在屏幕中心（视角中心），鼠标移动引导机头朝向目标指向，机头收敛后与准心重合
## 控制：鼠标=引导机头朝向, Shift/Ctrl=油门, W/S=俯仰, A/D=偏航辅助

# 空气密度：按 2× 重力世界标定（1.225 × GRAVITY/9.81 ≈ 2.497 kg/m³）
# 使标准气动公式的 CL 值与真实机型一致（2g 世界需 2× 密度补偿）
const AIR_DENSITY: float = 2.497

@export var max_thrust: float = 48000.0
@export var drag_coefficient: float = 0.02     # 寄生阻力系数 CD0
@export var takeoff_speed: float = 55.0
@export var stall_speed: float = 52.0
# === 质量 / 气动外形 ===
# 注：游戏世界重力 GRAVITY=20（约为真实 2 倍），为保证巡航留足机动余量，
# 翼载荷按游戏世界标定（等效真实机型在 2g 世界的表现）
@export var mass_kg: float = 9000.0            # 质量（kg）
@export var wing_area: float = 75.0            # 机翼面积（m2）
@export var wingspan: float = 17.0             # 翼展（m，滚转/偏航力矩臂）
@export var mean_chord: float = 4.0            # 平均气动弦（m，俯仰力矩臂）
@export var cl_alpha: float = 4.5              # 升力线斜率（1/rad）
@export var cl_zero: float = 0.08              # 零攻角升力系数
@export var induced_drag: float = 0.05         # 诱导阻力系数 k（CD = CD0 + k*CL^2）
@export var max_aoa: float = 0.30              # 最大可控攻角（rad，超限失速）
@export var min_aoa: float = -0.25             # 最小攻角（rad）
# === 气动力矩 ===
@export var inertia_roll: float = 90000.0      # 滚转转动惯量（kg*m2）
@export var inertia_pitch: float = 320000.0    # 俯仰转动惯量
@export var inertia_yaw: float = 350000.0      # 偏航转动惯量
@export var cl_da: float = 0.03                # 副翼滚转力矩系数（1/rad偏转）
@export var cl_de: float = 0.30                # 升降舵俯仰力矩系数
@export var cn_dr: float = 0.03                # 方向舵偏航力矩系数
@export var cm_alpha: float = -0.12            # 纵向静稳定系数（负=低头恢复）
@export var roll_damp: float = 2.4             # 滚转阻尼（1/s，角速度阻尼）
@export var pitch_damp: float = 2.1            # 俯仰阻尼
@export var yaw_damp: float = 1.5              # 偏航阻尼
# === 战雷式飞控（向量引导） ===
@export var aim_sensitivity: float = 0.55       # 鼠标灵敏度（度/像素）：压低后"稍微动一下"只产生小角度目标偏移，机体偏转随之减小
@export var keyboard_pitch_rate: float = 60.0  # W/S 键盘俯仰速率（度/秒）
@export var auto_center_enabled: bool = true    # 视角自动回正：无输入时 target_pitch→0(改平)、target_yaw→当前航向(直飞)
@export var auto_center_delay: float = 0.5      # 无输入多久后开始回正（秒）
@export var auto_center_speed: float = 3.0      # 回正指数收敛速率（1/s，越大越快）
@export var max_aim_pitch_up: float = 175.0     # 目标指向最大抬头角（度）：放宽到可翻过头顶下拉杆筋斗，够不够力由推重比决定
@export var max_aim_pitch_down: float = -175.0  # 目标指向最大俯冲角（度）：-175°=可推杆翻过头底向后掉头（外筋斗，与拉杆 175° 对称），够不够力由推重比决定
@export var guidance_gain: float = 1.3         # 引导速率增益（rad/s 每 rad 误差）：与低灵敏度搭配，小误差温和、大误差快速收敛
@export var max_guidance_rate: float = 0.8     # 最大引导角速度（rad/s，同时受升力过载极限约束）
@export var steer_min_rate: float = 0.05       # 小幅转向最小引导速率（rad/s，≈2.9°/s）：小误差也有平缓连续转动
@export var steer_deadzone_deg: float = 0.5    # yaw 引导死区（度）：滤除鼠标轻碰/静止噪声，防止无意义摆动
@export var bank_smooth_rate: float = 4.0      # 空中压坡平滑速率（1/s）：机翼倾斜角度指数收敛到目标坡度，防止跳变/感官瞬移
@export var rate_gain: float = 2.0              # 内环角速度伺服增益
@export var surface_rate: float = 3.0          # 舵机响应速度（1/s）
@export var rudder_rate: float = 50.0          # A/D 方向舵辅助偏航（度/秒）
@export var rudder_assist_deg: float = 15.0    # A/D 偏航辅助偏置角（度，临时偏置不污染准星）
@export var roll_friction: float = 0.6         # 地面滑跑滚动摩擦减速度（m/s^2，常数）
@export var brake_decel: float = 7.0           # 滑跑刹车减速度（m/s²，起落架贴地 + 按住 Ctrl 减油门时生效）
@export var lift_excess: float = 1.05          # 平飞升力余量系数（过起飞速度后自然抬头离地）
@export var phugoid_damping_gain: float = 3.0  # 长周期（phugoid）阻尼增益：爬升减升力、下降增升力，抑制上下抖动
@export var keyboard_pitch_accel: float = 12.0  # W/S 直接垂直加速度（m/s²）：绕过间接引导链，给玩家即时高度响应
@export var keyboard_trim_deg: float = 20.0     # W/S 视觉俯仰偏移（度）：机头偏离速度方向的最大角，给玩家即时姿态反馈
@export var g_limit: float = 7.0               # 结构过载限制（正过载 g，A-10 真实 7.33G）
@export var align_rate: float = 3.0            # 地面滑跑速度方向对齐机头速率（1/s）
@export var ground_turn_rate: float = 20.0     # 地面滑行最大水平转向速率（度/秒，前轮转向，随滑跑速度增强）
@export var ground_turn_speed_ref: float = 15.0 # 滑跑转向能力全开的参考速度（m/s）：低于此速度转向按 (v/ref)^2 衰减，低速无法大角度转
@export var ground_steer_gain: float = 0.4     # 滑跑转向软收敛增益：机头每帧只走 yaw_err 的比例，鼠标微调只产生小幅度机头转角
@export var ground_steer_max_deg: float = 30.0 # 滑跑偏航指令限幅（度）：鼠标偏置再大也只等效 ±30° 转弯指令，硬限制转向角度
@export var cam_follow_speed: float = 5.0      # 相机跟随目标指向的平滑速度
# === 起落架 ===
@export var gear_retract_speed: float = 1.2    # 起落架收放速度（动画 0→1 所需时间的倒数）
@export var gear_drag_factor: float = 1.35     # 起落架放下时的额外阻力倍率
@export var gear_retract_offset: float = 0.5   # 收起时起落架整体上移距离（缩进机腹，m）

var propeller_node: Node3D = null
# 三点式起落架地面停姿（后三点/前三点通用）：
# 静止时载具机头上仰 ground_pitch_deg，同时模型下移 ground_model_offset 补偿
# 绕原点旋转导致的主轮抬升，使主轮/尾轮同时着地；滑跑与飞行恢复水平与基准 offset。
var ground_pitch_deg: float = 0.0
var ground_model_offset: float = 0.0
var _tail_lift_speed: float = 0.0      # 抬尾轮速度（m/s）：滑跑达到后机头放平（尾轮抬起）
var _model_base_offset_y: float = 0.0  # ImportedModel 基准 offset.y
var _model_ground_state: bool = false  # 当前是否处于三点停姿（模型已下移）
# 螺旋桨旋转轴（propeller 局部坐标）。默认绕局部 Z（机头方向，兼容内置简化杆状螺旋桨）。
# 导入模型若螺旋桨 mesh 厚度轴在其他轴向（如喷火的桨盘厚度沿局部 Y），
# 通过 physics.propeller_axis 配置（"x"/"y"/"z"/"-x"/"-y"/"-z"）指定。
var propeller_axis: Vector3 = Vector3.FORWARD
var angular_velocity: Vector3 = Vector3.ZERO
var throttle: float = 0.0
var is_flying: bool = false
var airspeed: float = 0.0
var camera_3d: Camera3D = null
var camera_pivot: Node3D = null
# 鼠标引导的目标指向（世界系，弧度；yaw 正=左偏，pitch 正=抬头）
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var input_yaw: float = 0.0
var input_pitch: float = 0.0  # W/S 键盘俯仰输入（+1=抬头, -1=低头）
var _mouse_idle_time: float = 999.0  # 鼠标静止时间（秒），初始大值使无输入时立即回正
# A/D 偏航辅助当前偏置角（度）：按 rudder_rate 渐进逼近 ±rudder_assist_deg，
# 平移目标指向（临时），不污染准星
var rudder_assist_cur: float = 0.0
# 空中压坡角当前平滑值（弧度）：bank 目标由每帧向心加速度决定，直接使用会突变；
# 以 bank_smooth_rate 指数收敛使机翼倾斜逐帧连贯
var bank_cur: float = 0.0
# 气动状态（供调试/显示）
var alpha: float = 0.0       # 当前攻角（rad）
var n_load: float = 1.0      # 当前法向过载（g）
# 舵面偏转 [-1,1]
var delta_a: float = 0.0     # 副翼
var delta_e: float = 0.0     # 升降舵
var delta_r: float = 0.0     # 方向舵
var is_public_local: bool = false  # 公网模式下的本地玩家
# 公网状态上报计时（与 tank.gd 一致的 30Hz 输入 + 15Hz 状态）
var _net_input_timer: float = 0.0
var _net_state_timer: float = 0.0
# === 起落架运行时状态 ===
var gear_deployed: bool = true        # 当前是否放下（true=放下；贴地/停机时强制放下）
var gear_anim: float = 1.0            # 收放动画进度：1=完全放下，0=完全收起
var gear_container: Node3D = null     # 模型中的 LandingGear 容器（收起时整体上移缩进机腹）
var _gear_base_y: float = 0.0         # 容器模型基准高度（收起 = 基准 + offset 上移）
# 贴地状态（带滞回）：物理接触立即置真；脱离后需持续离地高度 + 缓冲时间才切回飞行。
# 消除滑跑中 is_on_floor 抖动导致「前轮转向 vs 空中姿态求解」交替控制机头造成的画面抽搐。
var _ground_state: bool = false
var _ground_grace: float = 0.0        # 持续离地时间（秒），超过缓冲阈值才解除贴地
# 筋斗翻越完成自动改平状态机：0=巡航 1=翻越中 2=自动改平
var _loop_state: int = 0
var _loop_peak_vy: float = 0.0        # 翻越中 vdir.y 历史峰值（触发判据：已过顶并回落）
var _loop_fwd: Vector3 = Vector3.FORWARD  # 筋斗开始时世界水平前向（翻越判据的固定参考系）
# 外筋斗（推杆翻越后半球掉头）保护：0=巡航 1=推杆翻越中
var _push_state: int = 0
var _push_nadir_vy: float = 0.0       # 推杆翻越中 vdir.y 历史谷值（触发判据：曾明显下压现回升）
var _push_fwd: Vector3 = Vector3.FORWARD  # 推杆开始时世界水平前向（同 _loop_fwd 语义）
var _bank_h_acc: float = 0.0          # 通道1 水平转向加速度（协调压坡专用；通道2 的水平分量不算转弯）
var is_aim_mode: bool = false             # 右键瞄准视角（拉近+降低观察）
var _default_cam_y: float = 2.0           # 默认相机高度（_setup时记录）
var _default_cam_z: float = 6.0           # 默认相机距离
var _default_cam_fov: float = 70.0        # 默认 fov
# === 弹道计算机（CCIP，现代飞机）===
var has_ccip: bool = false
var _ccip_marker: Sprite3D = null

# 固定翼使用远大于坦克战场的大边界（写 _init 而非重声明，避免遮蔽基类 use_air_boundary）
func _init() -> void:
	use_air_boundary = true
	# 空中禁修名单：引擎/机翼/尾翼/油箱等关键部件须着陆后修复
	repair_ground_only_modules = ["engine", "left_wing", "right_wing", "tail", "fuel_tank"]

func _ready() -> void:
	super._ready()
	_setup_propeller_node()
	_apply_aircraft_params(vehicle_data.get("physics", {}))
	if is_player_controlled:
		_setup_aircraft_camera()
		target_yaw = rotation.y
		target_pitch = rotation.x
		# 立即设置摄像机朝向机头方向，避免初始视角与准心不一致
		_sync_camera_immediate()
		# 兜底：确保鼠标被捕获（飞行载具需要鼠标控制视角）
		if not OS.has_feature("mobile"):
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# 移动端：显示飞行升降按钮（延迟一帧再试一次，防止时序问题）
		_show_mobile_air_buttons()
		call_deferred("_show_mobile_air_buttons")

func setup_from_data(data: Dictionary) -> void:
	# 模型由基类在 super 中动态实例化并挂载，此刻才能找到 LandingGear / Propeller，
	# 重新绑定节点（main.gd 出生流程 add_child 先于 setup_from_data，_ready 时模型尚未挂载）
	super.setup_from_data(data)
	_apply_aircraft_params(data.get("physics", {}))
	_setup_propeller_node()
	_setup_landing_gear()
	has_ccip = data.get("avionics", {}).get("has_ccip", false)

func _setup_landing_gear() -> void:
	"""绑定模型中的 LandingGear 容器（收起时整体上移缩进机腹）"""
	gear_container = find_child("LandingGear", true, false)
	_gear_base_y = gear_container.position.y if gear_container else 0.0

func _apply_mobile_visibility_boost() -> void:
	"""飞机专用移动端可见性增强（重写基类）。
	基类通用 mobile_rim.gdshader 仅边缘发光、无基础自发光，Mobile 渲染器下
	深灰色机体正面在暗环境与天空地面融合，导致"只能看到昵称看不到机体"。
	此处改用 airplane_mobile_vis.gdshader：全模型基础自发光 + 增强边缘轮廓 +
	显式 PBR 参数，确保手机端飞机整体可辨。仅手机模式生效，桌面端零影响。"""
	if _get_mobile_controls() == null:
		return
	var rim_shader = load("res://scripts/vehicles/airplane_mobile_vis.gdshader")
	if rim_shader == null:
		push_warning("[Airplane] 移动端可见性 shader 加载失败，跳过")
		return
	var count := 0
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		# 从原材质提取基色并提亮，保持各部件原有色彩倾向（机身/机翼/螺旋桨/起落架）
		var base := mi.get_active_material(0)
		var base_col := Color(0.6, 0.65, 0.7)
		if base is StandardMaterial3D:
			base_col = (base as StandardMaterial3D).albedo_color.lightened(0.25)
		var mat := ShaderMaterial.new()
		mat.shader = rim_shader
		mat.set_shader_parameter("base_color", base_col)
		mi.material_override = mat
		count += 1
	if count > 0:
		print("[Airplane] Mobile visibility boost applied to %d meshes" % count)

func _show_mobile_air_buttons() -> void:
	"""移动端：显示飞行升降控制按钮"""
	var mobile = _get_mobile_controls()
	if mobile and mobile.has_method("set_air_buttons_visible"):
		mobile.set_air_buttons_visible(true)

func _toggle_landing_gear() -> void:
	"""切换起落架收放。贴地时强制放下（收起状态下滑跑/落地会刮地损坏），
	仅在空中允许收起。真实固定翼起落架必须在起飞后收起、着陆前放下。"""
	if gear_deployed:
		# 请求收起：贴地禁止（低空/着地姿态强制放下）
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
		# 收起 = 向上缩进机腹（gear_retract_offset 米），放下 = 回到模型基准高度
		gear_container.position.y = _gear_base_y + (1.0 - gear_anim) * gear_retract_offset
		gear_container.visible = gear_anim > 0.02

func _setup_propeller_node() -> void:
	# 喷气式飞机（如 A-10）无螺旋桨：glb 中标注为 "Propeller" 的节点实为发动机/进气道，
	# 配置 physics.propeller_disabled=true 时不绑定，避免引擎随螺旋桨旋转。
	if bool(vehicle_data.get("physics", {}).get("propeller_disabled", false)):
		propeller_node = null
		return
	propeller_node = find_child("Propeller", true, false)
	_apply_propeller_axis(vehicle_data)

func _apply_propeller_axis(data: Dictionary) -> void:
	"""按配置 physics.propeller_axis 设置螺旋桨局部旋转轴。
	默认 "z"：绕局部 Z（FORWARD，机头方向）——内置简化螺旋桨的约定。
	导入模型若螺旋桨 mesh 厚度轴在其他轴向（桨盘法线），配置对应字母即可，
	负号（如 "-y"）表示反向旋转（当正角方向与实际螺旋桨转向相反时）。"""
	var axis_name: String = str(data.get("physics", {}).get("propeller_axis", "z")).to_lower()
	match axis_name:
		"x":
			propeller_axis = Vector3.RIGHT
		"-x":
			propeller_axis = -Vector3.RIGHT
		"y":
			propeller_axis = Vector3.UP
		"-y":
			propeller_axis = -Vector3.UP
		"-z":
			propeller_axis = -Vector3.FORWARD
		_:
			propeller_axis = Vector3.FORWARD

func _update_model_ground_pose(delta: float) -> void:
	"""三点式停姿的模型下移补偿：三点停姿时 ImportedModel 下移 ground_model_offset，
	抵消绕载具原点旋转 ground_pitch 造成的主轮抬升；滑跑/飞行平滑恢复基准 offset。"""
	if ground_model_offset <= 0.0:
		return
	var m = find_child("ImportedModel", true, false)
	if not m:
		return
	var target_y: float = _model_base_offset_y
	if _model_ground_state:
		target_y -= ground_model_offset
	m.position.y = lerp(m.position.y, target_y, clamp(delta * 5.0, 0.0, 1.0))

func _setup_aircraft_camera() -> void:
	var pivot = Node3D.new()
	pivot.name = "AircraftCameraPivot"
	# top_level 脱离父级变换：相机锚点不继承机身滚转/俯仰旋转，避免机动时绕机体画圈抖动
	# （与 tank.gd 的 CameraPivot 一致做法）
	pivot.top_level = true
	pivot.position = Vector3(0, 3.0, 0)  # 基准偏移（位置由 _update_camera 手动跟随覆盖）
	add_child(pivot)
	var cam = Camera3D.new()
	cam.name = "AircraftCamera"
	# 移动端机体出画修复：原相机局部 (0,2,6) 叠加 pivot 抬升 3m 后，
	# 相机相对机体 (0,5,6) → 观察角 atan(5/6)≈39.8°，超出 fov70 垂直半角 35°，
	# 机体整体被推出画面底部（起飞/小幅爬升时完全不可见 - 手机端诉求）。
	# 手机端（存在 mobile 控件，与开火门控同一判断口径）改用更高更远的 (0,4.5,16)：
	# 观察角 atan(7.5/16)≈25°，机体完整落入 fov75 视锥内且占据画面中下部；桌面端保持原视角不变。
	if _get_mobile_controls() != null:
		cam.position = Vector3(0, 4.5, 16.0)
		cam.fov = 75.0
	else:
		cam.position = Vector3(0, 2.0, 6.0)
		cam.fov = 70.0
	pivot.add_child(cam)
	cam.current = true
	camera_3d = cam
	camera_pivot = pivot
	_default_cam_y = cam.position.y
	_default_cam_z = cam.position.z
	_default_cam_fov = cam.fov
	
func _physics_process(delta: float) -> void:
	if is_destroyed:
		velocity.y -= GRAVITY * delta
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, delta * 0.3)
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
		# 读取键盘输入（每帧读取比事件驱动更可靠）
		if is_player_controlled and not GameManager.is_chat_open:
			input_throttle = Input.get_axis("throttle_down", "throttle_up")
			input_yaw = Input.get_axis("turn_right", "turn_left")
			input_pitch = Input.get_axis("move_backward", "move_forward")
			# 移动端触摸输入（与键盘叠加）：升降按钮=油门加减，摇杆=前后油门/偏航，拖动=机头引导
			var mobile = _get_mobile_controls()
			if mobile:
				if mobile.pitch_up_active:
					input_throttle = max(input_throttle, 1.0)
				elif mobile.pitch_down_active:
					input_throttle = min(input_throttle, -1.0)
				if abs(mobile.joystick_y) > 0.05:
					input_throttle = clamp(input_throttle + mobile.joystick_y, -1.0, 1.0)
				if abs(mobile.joystick_x) > 0.05:
					input_yaw = clamp(input_yaw + mobile.joystick_x, -1.0, 1.0)
				if mobile.look_delta.length() > 0.01:
					# 手指上滑(look_delta.y<0) → target_pitch增大 → 抬头/准心上移
					target_yaw -= deg_to_rad(mobile.look_delta.x * 0.3)
					target_pitch = clamp(target_pitch - deg_to_rad(mobile.look_delta.y * 0.3), deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
					target_yaw = wrapf(target_yaw, -PI, PI)
					mobile.look_delta = Vector2.ZERO
# 按住开火：每帧轮询（fire() 自带装填/冷却门控限速，按住连续射击）
			# 移动端：触摸会模拟鼠标左键（fire 动作），必须隔离否则点击屏幕任意位置都开火；
			# 有移动端只认开火按钮 fire_held，无移动端认 fire 动作（与 tank.gd 口径一致）
			if (mobile and mobile.fire_held) or (not mobile and Input.is_action_pressed("fire")):
				fire()
		_update_flight(delta)
		_update_turret(delta)
		_update_lock_on(delta)
		_update_ccip()
	if propeller_node:
		propeller_node.rotate_object_local(propeller_axis, throttle * 30.0 * delta)
	# 起落架收放动画推进（放下/收起均平滑过渡，并随状态移动模型容器）
	_update_landing_gear(delta)
	# 三点式停姿的模型下移补偿统一判定：
	# 静止 或 滑跑尚未达到抬尾轮速度（尾轮仍着地）→ 模型下移保持三点；
	# 达到抬尾轮速度（尾轮抬起）或离地飞行 → 恢复基准 offset（水平姿态）
	var pose_3pt := is_on_floor() and airspeed < _tail_lift_speed
	_model_ground_state = pose_3pt
	_update_model_ground_pose(delta)
	var pre_move_vel := velocity
	move_and_slide()
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0.0
	# 高速撞击损伤（正常着陆/滑跑法向≈0 不误伤，撞地/撞障碍物按速度分级）
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
	# 客户端：插值到服务器权威状态（远程飞机纯视觉；本地模拟内部自行忽略）
	_interpolate_network_state(delta)
	# 自由视角退出后，相机偏移平滑衰减还原
	_process_free_look_restore(delta)
	speed_changed.emit(airspeed)
	altitude_changed.emit(global_position.y)
	# 公网模式：发送输入和状态到服务器（与 tank.gd 速率一致，保证 last_seen 持续刷新、进广播列表）
	if is_public_local and NetworkManager.game_connected_flag:
		var mobile = _get_mobile_controls()
		_net_input_timer += delta
		if _net_input_timer >= 1.0 / 30.0:
			_net_input_timer = 0.0
			NetworkManager.game_send_input(input_throttle, input_yaw, 0.0, 0.0, (mobile and mobile.fire_held) or (not mobile and Input.is_action_pressed("fire")))
		_net_state_timer += delta
		if _net_state_timer >= 1.0 / 15.0:
			_net_state_timer = 0.0
			NetworkManager.game_send_state(global_position, global_rotation, turret_yaw, gun_pitch, get_health_percent(), velocity)

func _apply_aircraft_params(physics: Dictionary) -> void:
	# 数据驱动：JSON physics 字段覆盖飞控/气动参数（数据优先于默认值）
	max_thrust = float(physics.get("max_thrust", max_thrust))
	wing_area = float(physics.get("wing_area", wing_area))
	drag_coefficient = float(physics.get("drag_coefficient", drag_coefficient))
	takeoff_speed = float(physics.get("takeoff_speed", takeoff_speed))
	stall_speed = float(physics.get("stall_speed", stall_speed))
	mass_kg = float(physics.get("mass_kg", mass_kg))
	wingspan = float(physics.get("wingspan", wingspan))
	mean_chord = float(physics.get("mean_chord", mean_chord))
	cl_alpha = float(physics.get("cl_alpha", cl_alpha))
	cl_zero = float(physics.get("cl_zero", cl_zero))
	induced_drag = float(physics.get("induced_drag", induced_drag))
	max_aoa = float(physics.get("max_aoa", max_aoa))
	min_aoa = float(physics.get("min_aoa", min_aoa))
	inertia_roll = float(physics.get("inertia_roll", inertia_roll))
	inertia_pitch = float(physics.get("inertia_pitch", inertia_pitch))
	inertia_yaw = float(physics.get("inertia_yaw", inertia_yaw))
	cl_da = float(physics.get("cl_da", cl_da))
	cl_de = float(physics.get("cl_de", cl_de))
	cn_dr = float(physics.get("cn_dr", cn_dr))
	cm_alpha = float(physics.get("cm_alpha", cm_alpha))
	roll_damp = float(physics.get("roll_damp", roll_damp))
	pitch_damp = float(physics.get("pitch_damp", pitch_damp))
	yaw_damp = float(physics.get("yaw_damp", yaw_damp))
	aim_sensitivity = float(physics.get("aim_sensitivity", aim_sensitivity))
	max_aim_pitch_up = float(physics.get("max_aim_pitch_up", max_aim_pitch_up))
	max_aim_pitch_down = float(physics.get("max_aim_pitch_down", max_aim_pitch_down))
	guidance_gain = float(physics.get("guidance_gain", guidance_gain))
	max_guidance_rate = float(physics.get("max_guidance_rate", max_guidance_rate))
	rate_gain = float(physics.get("rate_gain", rate_gain))
	surface_rate = float(physics.get("surface_rate", surface_rate))
	rudder_rate = float(physics.get("rudder_rate", rudder_rate))
	cam_follow_speed = float(physics.get("cam_follow_speed", cam_follow_speed))
	roll_friction = float(physics.get("roll_friction", roll_friction))
	brake_decel = float(physics.get("brake_decel", brake_decel))
	lift_excess = float(physics.get("lift_excess", lift_excess))
	phugoid_damping_gain = float(physics.get("phugoid_damping_gain", phugoid_damping_gain))
	keyboard_pitch_accel = float(physics.get("keyboard_pitch_accel", keyboard_pitch_accel))
	keyboard_trim_deg = float(physics.get("keyboard_trim_deg", keyboard_trim_deg))
	g_limit = float(physics.get("g_limit", g_limit))
	align_rate = float(physics.get("align_rate", align_rate))
	rudder_assist_deg = float(physics.get("rudder_assist_deg", rudder_assist_deg))
	# 起落架 / 地面转向（JSON 可覆盖）
	gear_retract_speed = float(physics.get("gear_retract_speed", gear_retract_speed))
	gear_drag_factor = float(physics.get("gear_drag_factor", gear_drag_factor))
	gear_retract_offset = float(physics.get("gear_retract_offset", gear_retract_offset))
	ground_turn_rate = float(physics.get("ground_turn_rate", ground_turn_rate))
	ground_turn_speed_ref = float(physics.get("ground_turn_speed_ref", ground_turn_speed_ref))
	ground_steer_gain = float(physics.get("ground_steer_gain", ground_steer_gain))
	ground_steer_max_deg = float(physics.get("ground_steer_max_deg", ground_steer_max_deg))
	bank_smooth_rate = float(physics.get("bank_smooth_rate", bank_smooth_rate))
	# 三点式停姿（JSON 可覆盖；0 = 关闭）
	ground_pitch_deg = float(physics.get("ground_pitch_deg", ground_pitch_deg))
	ground_model_offset = float(physics.get("ground_model_offset", ground_model_offset))
	# 抬尾轮速度：滑跑达到该速度后机头放平（尾轮抬起）。默认取起飞速度的 60%
	_tail_lift_speed = float(physics.get("tail_lift_speed", takeoff_speed * 0.6))
	# 记录模型基准 offset.y（vehicle_initializer 按 model.offset 设置的 position）
	var mo: Array = vehicle_data.get("model", {}).get("offset", [0.0, 0.0, 0.0])
	_model_base_offset_y = float(mo[1]) if mo.size() >= 2 else 0.0
	_model_ground_state = false

func _update_ground_state() -> bool:
	"""贴地状态滞回判定：以物理接触（is_on_floor）为进入条件；	脱离接触后需持续 0.15s 才切回飞行态（低空跃起/弹跳不反复翻转）。
	目的：滑跑中机体轻微弹跳不再让 on_ground 逐帧翻转，
	避免前轮转向（写 rotation.y）与空中姿态求解（速度方向重建机头）交替控制机身 → 画面抖动。
	注意：不把「低空低速」扩展为贴地——空中低速悬停/无动力坠落应正常下落触地，
	不能被误判为地面而冻结在半空；AI 俯冲攻击掠过地面时也应快速恢复飞行姿态。"""
	if _ground_state:
		if not is_on_floor():
			_ground_grace += get_physics_process_delta_time()
			if _ground_grace > 0.15:
				_ground_state = false
		else:
			_ground_grace = 0.0
	else:
		if is_on_floor():
			_ground_state = true
	return _ground_state

func _update_flight(delta: float) -> void:
	var engine_eff = _get_module_effectiveness("engine")
	# 油门：Shift=增加(1.0), Ctrl=减小(0.0), 无输入=保持当前油门(不自动变化)
	# input_throttle: Shift=1, Ctrl=-1, 无输入=0
	if input_throttle > 0.1:
		throttle = clamp(throttle + delta * 1.2, 0.0, 1.0)
	elif input_throttle < -0.1:
		throttle = clamp(throttle - delta * 1.2, 0.0, 1.0)
	# W/S 键盘俯仰：以 keyboard_pitch_rate 度/秒调整 target_pitch（与鼠标叠加）
	if abs(input_pitch) > 0.01:
		target_pitch = clamp(target_pitch + deg_to_rad(input_pitch * keyboard_pitch_rate) * delta,
			deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
	# 视角自动回正：无鼠标输入超过延迟后，pitch→0(改平)、yaw→当前航向(直飞)
	# 筋斗/推杆状态机控制 target_pitch 期间禁用，自由视角期间禁用
	if auto_center_enabled and not is_free_look_active() and _loop_state == 0 and _push_state == 0:
		_mouse_idle_time += delta
		if _mouse_idle_time > auto_center_delay:
			var k: float = clampf(1.0 - exp(-auto_center_speed * delta), 0.0, 1.0)
			# 俯仰回正：无 W/S 输入时 target_pitch → 0（改平）
			if abs(input_pitch) < 0.01:
				target_pitch = lerpf(target_pitch, 0.0, k)
				if absf(target_pitch) < deg_to_rad(0.5):
					target_pitch = 0.0
			# 偏航回正：无 A/D 输入时 target_yaw → 当前航向 rotation.y（直飞）
			if abs(input_yaw) < 0.01:
				var yaw_err: float = wrapf(target_yaw - rotation.y, -PI, PI)
				target_yaw = wrapf(rotation.y + yaw_err * (1.0 - k), -PI, PI)
	var on_ground: bool = _update_ground_state()
	# 起落架贴地保护：物理落地（含滑跑/抬轮）立即强制放下，防止收起状态刮地损坏
	if on_ground:
		gear_deployed = true
	# 地面静止锁定（油门最低 + 几乎无速度时锁死）
	# 用 velocity.length() 而非成员变量 airspeed：airspeed 是上一帧末尾设置的（可能已过时），
	# 当速度被外部重置（联机/出生/测试）或刚落地垂直速度被 move_and_slide 清零时，
	# 用当前帧的真实速度判断更准确
	if on_ground and velocity.length() < 2.0 and throttle < 0.1:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		velocity.y = 0.0
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, delta * 5.0)
		# 三点式停姿：静止时机头上仰（后三点尾轮着地），模型下移由 _physics_process 统一补偿
		rotation.x = lerp(rotation.x, deg_to_rad(ground_pitch_deg), delta * 3.0)
		rotation.z = lerp(rotation.z, 0.0, delta * 3.0)
		# 地面静止时机头保持当前朝向，不跟随准星/目标偏航。
		# 真实固定翼停在跑道（未加油门、几乎无速度）不会原地转头指向视角中心，
		# 转向只应发生在滑跑（前轮/舵面）与飞行（速度矢量引导）阶段。
		airspeed = 0.0
		current_speed = 0.0
		_update_camera(delta)
		return
	# 推力（沿机头方向）
	var forward: Vector3 = -global_transform.basis.z
	velocity += forward * (max_thrust * throttle * engine_eff / mass_kg) * delta
	if on_ground:
		# 地面滑跑：滚动摩擦（常数减速度）替代强阻尼——允许加速到起飞速度
		var h_spd: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var h_len: float = h_spd.length()
		if h_len > 0.01:
			var fric: float = min(roll_friction, h_len / max(delta, 0.0001))
			h_spd -= h_spd.normalized() * (fric * delta)
			velocity.x = h_spd.x
			velocity.z = h_spd.z
		# 刹车：起落架触地（on_ground 时 gear_deployed 已被强制放下）+ 按住 Ctrl（减油门）→
		# 在滚动摩擦之上叠加 brake_decel 减速度，明显刹停滑跑中的飞机；空中按 Ctrl 只减油门不刹车。
		if input_throttle < -0.1 and h_len > 0.5:
			var brk: float = min(brake_decel, h_len / max(delta, 0.0001))
			h_spd -= h_spd.normalized() * (brk * delta)
			velocity.x = h_spd.x
			velocity.z = h_spd.z
		# 地面滑跑转向（前轮/方向舵）：机头在水平面以「随速度增强」的速率收敛到准星偏航（target_yaw）。
		# 真实固定翼低速滑跑时前轮附着力/舵面效能弱，无法原地大角度掉头；
		# 转向能力按 (airspeed / ground_turn_speed_ref)^2 从 0 平滑升至全开，低速几乎转不动，
		# 达到参考速度后才有完整 ground_turn_rate 转向。速度矢量随后自然跟随机头（先转机头、再带速度）。
		# ground_steer_gain<1 让机头只部分追目标：鼠标小幅摇动时转向更钝更稳，不会猛甩。
		# 静止锁定分支已提前 return，此处必然是"滑跑中"（有油门或有速度），转向始终生效。
		var yaw_cur: float = wrapf(rotation.y, -PI, PI)
		var yaw_err: float = wrapf(target_yaw - yaw_cur, -PI, PI)
		# 偏航指令限幅：鼠标偏置再大（如扭头 180°）也只等效 ±ground_steer_max_deg 的转弯指令。
		# 没有限幅时机头会一直追着准星转到完全对准——"滑跑转向角度还是很大"的根因；
		# 限幅后滑跑最大转弯等同于额定舵角，转向角度有硬上限。
		var steer_cmd: float = clamp(yaw_err, deg_to_rad(-ground_steer_max_deg), deg_to_rad(ground_steer_max_deg))
		var turn_eff: float = clamp(airspeed / ground_turn_speed_ref, 0.0, 1.0)
		turn_eff = turn_eff * turn_eff  # 低速更迟钝，速度上来后转向能力快速增强
		var step_max: float = deg_to_rad(ground_turn_rate) * turn_eff * delta
		var yaw_step: float = clamp(steer_cmd * ground_steer_gain, -step_max, step_max)
		rotation.y = yaw_cur + yaw_step
		forward = -global_transform.basis.z  # 机头已转，速度对齐使用更新后的前向
		# 滑跑姿态：低于抬尾轮速度保持三点（尾轮着地、机头仰角），达到后缓慢放平（尾轮抬起）
		# 模型下移补偿由 _physics_process 按 _model_ground_state 统一驱动
		if airspeed < _tail_lift_speed:
			rotation.x = lerp(rotation.x, deg_to_rad(ground_pitch_deg), clamp(delta * 3.0, 0.0, 1.0))
		else:
			rotation.x = lerp(rotation.x, 0.0, clamp(delta * 3.0, 0.0, 1.0))
		rotation.z = lerp(rotation.z, 0.0, clamp(delta * 3.0, 0.0, 1.0))
		# 速度方向对齐机头（前三点滑跑走直线）；方向误差极小直接钳平
		var f_al: Vector3 = Vector3(forward.x, 0.0, forward.z)
		if f_al.length() > 0.01 and h_len > 0.5:
			var al_f: float = clamp(delta * align_rate, 0.0, 1.0)
			f_al = f_al.normalized()
			var v_h2: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
			var v_l2: float = v_h2.length()
			if v_l2 > 0.01:
				var al_v: Vector3 = v_h2.lerp(f_al * v_l2, al_f)
				velocity.x = al_v.x
				velocity.z = al_v.z
	# ==== WT 街机式飞控：速度矢量引导（双通道分解，载荷受限,永不失控）====
	var spd: float = velocity.length()
	var vdir: Vector3 = velocity / spd if spd > 3.0 else -global_transform.basis.z
	# 竖直窗口权重：|vdir.y|→1（竖直冲/俯）时航向角在数学上无定义，水平分量由浮点噪声
	# 主导，若仍按它压坡会让机翼左右乱倾（"竖直拉升时飞机左右倾斜"的根因之一）。
	# 0.95 起线性生效，1.0 处衰减 60%；配合通道1 的 v_h 阈值（下面）双保险。
	var vert_w: float = clamp((absf(vdir.y) - 0.95) * 12.0, 0.0, 1.0)

	# 速度-竖直平面内的"机背基准"（升力方向参考）
	# 街机式飞控语义：升力恒沿"垂直 vdir 的世界向上投影"（任何姿态都托着飞机，
	# 收敛后由升力承担重力竖直分量，vdir 保持对准目标；压坡/滚转只是姿态显示）。
	# 【勿改回"机体实际机背投影"】收敛在 150° 后半球时姿态随 roll 侧躺（basis.y≈±X/±Z），
	# 升力被拖向水平 → 竖直天平打破 → 速度被缓慢掰向天顶（筋斗收敛后漂移回归）。
	var up_t: Vector3 = Vector3.UP
	var up_proj: Vector3 = up_t - vdir * up_t.dot(vdir)
	if up_proj.length() < 0.01:
		up_t = Vector3.RIGHT  # vdir 垂直/平行 UP 的退化兜底（竖直机动分支会接管姿态）
	else:
		up_t = up_proj.normalized()
	# 动压与最大升力系数（标准气动公式）
	var q: float = 0.5 * AIR_DENSITY * spd * spd  # 动压 q = 0.5*ρ*V²
	var cl_max: float = cl_zero + cl_alpha * max_aoa  # 最大升力系数（失速边界）
	# 可用过载（g）：CL_max 产生的最大升力 / 重力 —— V² 标度（速度越高可用 G 越大）
	# 低速时 n_max≈1（勉强维持平飞），高速时受结构限制 g_limit 封顶
	var n_max: float = clamp(cl_max * q * wing_area / (mass_kg * GRAVITY), 1.0, g_limit)
	var target_dir: Vector3 = -Basis.from_euler(Vector3(target_pitch, target_yaw, 0.0)).z
	# A/D 偏航辅助：渐进逼近目标偏置角（度），绕世界Y轴平滑偏转目标方向（临时，不污染准星）
	var assist_target: float = -input_yaw * rudder_assist_deg
	rudder_assist_cur = move_toward(rudder_assist_cur, assist_target, rudder_rate * delta)
	if abs(rudder_assist_cur) > 0.01:
		target_dir = (Quaternion(Vector3.UP, deg_to_rad(rudder_assist_cur)) * target_dir).normalized()
	var a_c: Vector3 = Vector3.ZERO
	var steer_axis: Vector3 = Vector3.ZERO
	if spd > 3.0 and not on_ground:
		var target_n: Vector3 = target_dir.normalized()
		_bank_h_acc = 0.0  # 每帧清零：仅记录通道1 实际注入的水平向心加速度（见下方压坡）
		# ---- 通道1：水平转向（绕世界Y轴），产生协调压坡的向心加速度 ----
		var v_h: Vector3 = Vector3(vdir.x, 0.0, vdir.z)
		var t_h: Vector3 = Vector3(target_n.x, 0.0, target_n.z)
		# 竖直窗口内（vdir 水平分量 < 5%，即速度偏离竖直 <~3°）禁行水平转向：
		# 此时 yaw 数学意义丧失，转向指令会由噪声/鼠标抖动主导 → 左右乱偏；
		# 竖直机动（拉升/俯冲）全部由通道2 在速度矢量平面内完成。
		# 注意：v_h 取自单位向量 vdir，阈值用无纲量 0.05（≈sin3°），勿乘 spd（曾致恒 false）。
		if t_h.length() > 0.01 and v_h.length() > 0.05:
			var v_hn: Vector3 = v_h.normalized()
			var t_hn: Vector3 = t_h.normalized()
			var yaw_err: float = acos(clamp(v_hn.dot(t_hn), -1.0, 1.0))
			# 转向方向：垂直于当前航向的水平方向，指向目标（叉积符号定左右）
			var dir_h: Vector3 = Vector3.UP.cross(v_hn)
			if dir_h.dot(t_hn) < 0.0:
				dir_h = -dir_h
			dir_h = dir_h.normalized()
			# 水平转向速率（水平向心加速度 ≤ 载荷余量）
			var h_cap: float = sqrt(max(n_max * n_max - 1.0, 0.0)) * GRAVITY / spd
			var rate_cap: float = min(max_guidance_rate, h_cap)
			var rate_h: float = clamp(yaw_err * guidance_gain, 0.0, rate_cap)
			# 小幅转向最小响应：小误差（>死区）也至少以 steer_min_rate 转动，
			# 消除"误差累计→突然响应"的粘滞卡顿；误差进入死区则完全静止（滤鼠标噪声）
			if yaw_err > deg_to_rad(steer_deadzone_deg) and rate_h < steer_min_rate:
				rate_h = steer_min_rate
			a_c = dir_h * (rate_h * spd)
			steer_axis = v_hn.cross(t_hn)  # 供压坡方向判定（正=左转）
			_bank_h_acc = a_c.length()     # 供协调压坡（通道2 的竖直修正分量不算转弯）
		# ---- 通道2：垂直俯仰（在竖直平面内抬/低头，收敛目标俯仰）----
		# 引导方向 = 目标方向在垂直速度方向平面上的投影：0°~180°（含翻过头顶的后向）连续无歧义。
		# 原实现用 asin(y) 差值 + up_t*sign，两个缺陷导致无法拉杆筋斗：
		#   a) asin 在俯仰 >90° 时折叠（sin95°=sin85°），误差符号反转，引导把速度拉回；
		#   b) up_t 是 UP 在垂直 vdir 平面上的投影，过顶后仍指前上方，升力方向与真实筋斗相反。
		# 改为直接投影目标方向：速度朝后上方时投影指向后下方（把机头继续翻向身后），全程符号正确。
		var a_dir: Vector3 = target_n - vdir * target_n.dot(vdir)
		if a_dir.length() > 0.001:
			a_dir = a_dir.normalized()
		else:
			a_dir = up_t  # 目标与速度共线（严格重合或正对 180°），退化为机背基准兜底
		var pitch_err: float = acos(clamp(target_n.dot(vdir), -1.0, 1.0))
		var v_cap: float = n_max * GRAVITY / spd
		var rate_v: float = clamp(pitch_err * guidance_gain, 0.0, min(max_guidance_rate, v_cap))
		# 死区（与水平通道一致）：收敛后 pitch_err≈浮点噪声，若仍注入引导会持续向 up_t 兜底方向
		# 漂移（150° 巡航时表现为速度被悄悄掰向竖直）——误差进入死区则完全静默
		if pitch_err > deg_to_rad(steer_deadzone_deg):
			a_c += a_dir * (rate_v * spd)
		# ---- 总载荷限制：|a_c| 不得超过过载余量 ----
		var a_len: float = a_c.length()
		var load_limit: float = n_max * GRAVITY
		if a_len > load_limit:
			a_c *= load_limit / a_len
		velocity += a_c * delta
		# ---- 筋斗翻越完成 → 自动改平 ----
		# 语义：玩家拉杆（target_pitch>90° 后向目标）完成"翻越"后，即使准星仍停在
		# 后上方，也自动把目标仰角收回平飞——做完筋斗自动改平收尾，不停留 150° 后上方。
		# 判据（纯物理、无时间依赖，连续回旋/激斗不受影响）：
		#   ① vdir 已深入后半球：vdir·loop_fwd < -0.45（仰角约 >117°，筋斗弧线走完 8 成以上）；
		#   ② 已过顶并回落（peak_vy - vdir.y > 0.25），或玩家目标仰角已达成
		#      （target_pitch 落在 vdir 仰角 + 17° 内，引导已收敛、不再继续翻越）。
		# 改平目标直接写回 target_pitch=0，引导自然把速度拉回水平前方；玩家此刻若
		# 重新移动鼠标会立即覆盖 target_pitch 恢复手动控制。
		if _loop_state == 0 and target_pitch > deg_to_rad(90.0):
			_loop_state = 1
			_loop_peak_vy = vdir.y
			_loop_fwd = -global_transform.basis.z
			_loop_fwd.y = 0.0
			if _loop_fwd.length() > 0.1:
				_loop_fwd = _loop_fwd.normalized()
			else:
				_loop_fwd = Vector3(-sin(target_yaw), 0.0, -cos(target_yaw)).normalized()
		elif _loop_state == 1:
			_loop_peak_vy = max(_loop_peak_vy, vdir.y)
			# 速度"仰角"用 acos(vdir·loop_fwd) 还原全区间 [0,180°]：
			# asin(vdir.y) 只能返回 [-90°,90°]，当 vdir 指向后上方（如 150° 目标
			# 方向 vdir≈(-0.866,0.5,0)）时 asin(0.5)=30° 折叠 → target_reached
			# 永不成立，正常翻越（浅俯冲筋斗 peak vy≈0.74、over_top 差 0.02）
			# 卡死在 state1，只有侥幸残留 peak>0.95 时 over_top 才凑巧成立。
			var v_pitch: float = acos(clamp(vdir.dot(_loop_fwd), -1.0, 1.0))
			var over_top: bool = _loop_peak_vy - vdir.y > 0.25
			var target_reached: bool = target_pitch < v_pitch + deg_to_rad(17.0)
			var deep_back: bool = vdir.dot(_loop_fwd) < -0.45
			if deep_back and (over_top or target_reached):
				_loop_state = 2
				target_pitch = 0.0  # 完成：自动改平
			elif target_pitch > deg_to_rad(90.0) and vdir.dot(_loop_fwd) > 0.5 \
					and vdir.y < 0.3 and _loop_peak_vy - vdir.y > 0.2:
				# 翻越失败：速度/推重比不足（或玩家中途放弃），vdir 从未深入后半球
				# 就被重力压回水平前方。此时若不收回，target_pitch 残留 >90° 会让
				# 相机锁定倒置（target_pitch 只在鼠标移动时写入，玩家松手即残留），
				# 而机身已随速度回落回正 → "机身已回正但视角仍然倒着"的根因。
				# 判据纯物理、无时间依赖：曾明显抬头（_loop_peak_vy 高）现回落到
				# 低仰角（vdir.y<0.3，<~17°）且方向朝前（dot>0.5）→ 筋斗无望，
				# 收回准星复位巡航；玩家此刻若移动鼠标会立即覆盖 target_pitch。
				_loop_state = 0
				target_pitch = 0.0
		elif _loop_state == 2:
			if vdir.dot(_loop_fwd) > 0.5 and vdir.y < 0.2:
				_loop_state = 0  # 已回到水平前方，复位状态机
				if target_pitch > deg_to_rad(90.0):
					# 玩家松手后 target_pitch 残留的后向目标：复位时一并收回，
					# 避免相机重新锁定倒置并再次进入筋斗（与上方翻越失败同源）。
					target_pitch = 0.0
		# ---- 外筋斗（推杆翻越后下方）→ 自动改平 ----
		# 语义：玩家推杆（target_pitch<-90° 后下方目标）完成"底部翻转"后，即使准星
		# 仍停在后下方，也自动把目标仰角收回平飞——完成外筋斗自动改平收尾。
		# 与拉杆筋斗状态机完全镜像（上下对称）：
		#   ① vdir 已深入后半球：vdir·_push_fwd < -0.45；
		#   ② 已过底并回升（vdir.y - _push_nadir_vy > 0.25），或玩家目标仰角已达成
		#      （-target_pitch 落在 vdir 仰角 + 17° 内，引导已收敛、不再继续翻转）。
		# 改平目标直接写回 target_pitch=0；玩家此刻若重新移动鼠标会立即覆盖。
		# 不自动改平的话：翻越完成后松手，target_pitch 残留后下方会把飞机一直压向
		# 后下方直到坠地（拉杆侧残留后上方只是倒飞不坠地）——必须对称回收。
		if _push_state == 0 and target_pitch < deg_to_rad(-90.0):
			_push_state = 1
			_push_nadir_vy = vdir.y
			_push_fwd = -global_transform.basis.z
			_push_fwd.y = 0.0
			if _push_fwd.length() > 0.1:
				_push_fwd = _push_fwd.normalized()
			else:
				_push_fwd = Vector3(-sin(target_yaw), 0.0, -cos(target_yaw)).normalized()
		elif _push_state == 1:
			_push_nadir_vy = min(_push_nadir_vy, vdir.y)
			var v_pitch: float = acos(clamp(vdir.dot(_push_fwd), -1.0, 1.0))
			var over_bottom: bool = vdir.y - _push_nadir_vy > 0.25
			var target_reached: bool = -target_pitch < v_pitch + deg_to_rad(17.0)
			var deep_back: bool = vdir.dot(_push_fwd) < -0.45
			if deep_back and (over_bottom or target_reached):
				_push_state = 2
				target_pitch = 0.0  # 完成：自动改平（外筋斗收尾）
			elif target_pitch < deg_to_rad(-90.0) and vdir.dot(_push_fwd) > 0.5 \
					and vdir.y > -0.3 and vdir.y - _push_nadir_vy > 0.2:
				# 翻越失败：速度/推重比不足（或玩家中途放弃），vdir 从未深入后半球
				# 就被升力拉回水平前方。此时若不收回，target_pitch 残留 <-90° 会把
				# 飞机持续压向后下方直到坠地（且相机锁定倒置），机身却已被拉平——
				# 与拉杆翻越失败同源的对称缺陷。判据纯物理、无时间依赖：
				# 曾明显低头（_push_nadir_vy 深）现回升到接近水平（vdir.y>-0.3）
				# 且方向朝前（dot>0.5）→ 外筋斗无望，收回准星复位巡航。
				_push_state = 0
				target_pitch = 0.0
		elif _push_state == 2:
			if vdir.dot(_push_fwd) > 0.5 and vdir.y < 0.2:
				_push_state = 0  # 已回到水平前方，复位状态机
				if target_pitch < deg_to_rad(-90.0):
					target_pitch = 0.0
	# 虚拟载荷（从引导加速度推算，需在升力前计算——升力/阻力均依赖此值）
	n_load = clamp(sqrt(1.0 + (a_c.length() / max(GRAVITY, 0.1)) * (a_c.length() / max(GRAVITY, 0.1))), 0.5, n_max * 1.2)
	# 标准气动升力 L = q * S * CL
	# CL = 稳态配平值（抵消重力），含 lift_excess 余量使飞机能缓慢爬升
	# 封顶 cl_max → 低于失速速度时 CL 被钳到上限，升力 < 重力 → 自然下沉
	var cl_trim: float = mass_kg * GRAVITY / (q * wing_area) if q > 0.0 else cl_max
	# 长周期（phugoid）阻尼：偏离目标垂直速度时减/增升力，抑制上下抖动
	# 物理依据：爬升时机体动能转为势能→速度降低→动压减小→升力自然下降；
	# 下降时势能转动能→速度增大→动压增大→升力自然上升。显式引入避免阻尼不足。
	# 关键改进：阻尼基于「偏离目标垂直速度的误差」而非绝对 velocity.y。
	# 旧公式用绝对 velocity.y → 爬升时(vy>0)阻尼减升力与转向指令对抗 → 振荡。
	# 新公式：target_vy = sin(target_pitch)*spd 是指令要求的目标垂直速度，
	# 当 vy=target_vy 时不阻尼（稳态爬升），偏离时才阻尼（抑制振荡）。
	var target_vy: float = sin(target_pitch) * spd
	var vy_err: float = velocity.y - target_vy
	var phugoid_factor: float = clamp(1.0 - vy_err * phugoid_damping_gain / max(spd, 10.0), 0.7, 1.3)
	var cl: float = clamp(cl_trim * lift_excess * phugoid_factor, 0.0, cl_max)
	velocity += up_t * (q * wing_area * cl / mass_kg) * delta
	# 重力
	velocity.y -= GRAVITY * delta
	# W/S 直接垂直加速度：绕过间接的 target_pitch→引导→速度→姿态 链，
	# 给玩家即时高度响应。加速度沿世界 Y 轴（上下），与机体姿态无关，
	# 简化操控：按 W 立即上升、按 S 立即下降，不再需要等引导系统慢慢追。
	if not on_ground:
		velocity.y += input_pitch * keyboard_pitch_accel * delta
	# 阻力：寄生 + 诱导（CDi = k * CL²，CL 含机动过载 → 大过载掉速但不再用 n² 过度惩罚）
	var cl_actual: float = clamp(n_load * cl_trim, 0.0, cl_max)
	var cd: float = (drag_coefficient + induced_drag * cl_actual * cl_actual) * (gear_drag_factor if gear_deployed else 1.0)
	if spd > 0.5:
		velocity -= (velocity / spd) * (cd * q * wing_area / mass_kg) * delta
	# 地面滑跑时限制向下速度为微小值（保持 floor 接触检测，不弹跳）：
	# 重力在 move_and_slide 之前叠加→带向下速度撞地→碰撞滑动消耗水平分量→
	# 反复弹跳最终清零水平速度（刹车测试失败根因）。
	# 完全清零 velocity.y 会导致 move_and_slide 无法检测 floor→is_on_floor 闪烁→
	# 测试无法稳定落地。保留 -1.0 m/s 微小向下速度：碰撞吸收、不可见，但 floor 检测可靠。
	# 升力仍正常生效：高速时升力 > 重力 → velocity.y > 0 → 不限制 → 飞机正常起飞。
	if on_ground and velocity.y < -1.0:
		velocity.y = -1.0
	airspeed = velocity.length()
	current_speed = airspeed  # 同步给 HUD/联机（HUD 直读 current_speed）
# ==== 姿态求解：机身跟随速度方向（小攻角配平）+ 协调压坡（bank-to-turn）====
	# 出生/静止自由落体时 vdir 竖直（≈(0,-1,0)）：此时 yaw 无数学定义，
	# 若直接以 vdir 作机头方向，up_t 退化 → x_axis 零向量 → Basis 病态，
	# 会把机体出生朝向（rotation.y）冲掉 → 进游戏视角机头背对战场、与相机相差 180°。
	# 修复分两路：
	#  a) 无动力竖直下落（出生自由落体，throttle≈0）：不做姿态求解，保持出生姿态；
	#  b) 带动力竖直机动（垂直俯冲/爬升轰炸，throttle>0）：保留当前机翼方向重建
	#     右手正交基（机头=速度方向、机翼保持）→ yaw 不丢，垂直轰炸俯冲仍可对准。
	var vdir_vertical: bool = abs(vdir.y) > 0.99
	var f_cur: Vector3 = -global_transform.basis.z
	var trim_alpha: float = alpha
	# 地面滑跑时不执行姿态求解：机头由前轮转向（上方 on_ground 分支）控制，
	# 这里若用速度方向 vdir 重建机头会吃掉前轮转向成果（滑跑转弯失效的历史根因）。
	if spd > 3.0 and not on_ground and (not vdir_vertical or throttle > 0.1):
		var f_n: Vector3 = vdir.normalized()
		if vdir_vertical:
			# 竖直机动：机头=速度方向；机翼=当前机翼在垂直机头平面内的投影（保持 yaw）
			var wn: Vector3 = global_transform.basis.x
			wn = (wn - f_n * wn.dot(f_n)).normalized()
			var x_axis: Vector3 = wn if wn.length() > 0.5 else Vector3.RIGHT
			var y_axis: Vector3 = (-f_n).cross(x_axis).normalized()
			var target_basis: Basis = Basis(x_axis, y_axis, -f_n)
			var cur_q: Quaternion = global_transform.basis.get_rotation_quaternion()
			var tgt_q: Quaternion = target_basis.get_rotation_quaternion()
			var ang_between: float = cur_q.angle_to(tgt_q)
			var max_step: float = clamp(max_guidance_rate * 2.5 * delta, 0.0001, 1.0)
			var rate_f: float = clamp(ang_between / max_step, 0.0, 1.0)
			global_transform.basis = Basis(cur_q.slerp(tgt_q, rate_f))
			var new_q: Quaternion = global_transform.basis.get_rotation_quaternion()
			var rel_q: Quaternion = new_q * cur_q.inverse()
			angular_velocity = rel_q.get_axis() * (rel_q.get_angle() / max(delta, 0.0001))
			delta_a = lerp(delta_a, 0.0, clamp(delta * 6.0, 0.0, 1.0))
			delta_e = lerp(delta_e, clamp(trim_alpha / 0.16, -1.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
			delta_r = lerp(delta_r, 0.0, clamp(delta * 6.0, 0.0, 1.0))
		else:
			# 1) 攻角配平：随过载轻微抬机头，机头始终指向准星（目标方向）
			# W/S 键盘俯仰叠加：给玩家即时视觉反馈——按 W 机头立即上仰、按 S 下俯，
			# 不需要等引导系统慢慢把速度方向掰过来才看到姿态变化。
			trim_alpha = clamp(0.02 + 0.55 * (n_load - 1.0) + input_pitch * deg_to_rad(keyboard_trim_deg), -0.50, 0.50)
			var f_new: Vector3 = vdir
			var right_axis: Vector3 = vdir.cross(Vector3.UP)
			if right_axis.length() > 0.01:
				f_new = Quaternion(right_axis.normalized(), trim_alpha) * vdir
			# 2) 协调压坡：水平向心加速度越大→滚转越大；左转左侧压坡（绕机体前进轴旋转）
			# 只用通道1 的水平向心加速度（_bank_h_acc）：通道2 竖直机动的水平修正分量
			# 不是转弯，若混入压坡会让"竖直拉升"误判成转弯 → 机翼左右乱倾（用户报的缺陷）。
			# 竖直窗口内再乘 (1.0-vert_w) 淡出：确保竖直冲/俯全程横滚中立。
			var a_h: float = _bank_h_acc * (1.0 - vert_w)
			var bank: float = clamp(atan2(a_h, GRAVITY), -1.05, 1.05)
			if steer_axis.length() > 0.01:
				bank *= -sign(steer_axis.y)  # steer_axis.y>0=左转 → 左侧压坡
			# 压坡平滑：a_h 随误差/死区跨越/转向方向切换会突变（如进入死区瞬间 bank 由 ~20° 直落 0°），
			# 直接使用目标坡度会让机翼倾斜角度不连贯 → 感官上像瞬移。
			# 以 bank_smooth_rate 指数收敛，机翼倾角逐帧连续变化。
			bank = lerp(bank_cur, bank, clamp(delta * bank_smooth_rate, 0.0, 1.0))
			bank_cur = bank
			var up_r: Vector3 = Quaternion(f_n, bank) * up_t
			# 3) 组合右手坐标系基：X=侧向, Y=机背, Z=机尾
			var x_axis2: Vector3 = (up_r.cross(-f_n)).normalized()
			var target_basis2: Basis = Basis(x_axis2, up_r.normalized(), -f_n)
			# 4) 以有限角速率平滑收敛到目标姿态（避免跳变，接近物理旋转速率）
			var cur_q2: Quaternion = global_transform.basis.get_rotation_quaternion()
			var tgt_q2: Quaternion = target_basis2.get_rotation_quaternion()
			var ang_between2: float = cur_q2.angle_to(tgt_q2)
			var max_step2: float = clamp(max_guidance_rate * 2.5 * delta, 0.0001, 1.0)
			var rate_f2: float = clamp(ang_between2 / max_step2, 0.0, 1.0)
			global_transform.basis = Basis(cur_q2.slerp(tgt_q2, rate_f2))
			# 5) 导出角速度（供武器/HUD/联机使用），并给出舵面示意偏转
			var new_q2: Quaternion = global_transform.basis.get_rotation_quaternion()
			var rel_q2: Quaternion = new_q2 * cur_q2.inverse()
			angular_velocity = rel_q2.get_axis() * (rel_q2.get_angle() / max(delta, 0.0001))
			delta_a = lerp(delta_a, clamp(bank / 1.05, -1.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
			delta_e = lerp(delta_e, clamp(trim_alpha / 0.16, -1.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
			delta_r = lerp(delta_r, clamp(f_cur.angle_to(vdir) * 0.2, -1.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
	else:
		# 速度过低：姿态保持当前，舵面回中
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, clamp(delta * 3.0, 0.0, 1.0))
		delta_a = lerp(delta_a, 0.0, clamp(delta * 3.0, 0.0, 1.0))
		delta_e = lerp(delta_e, 0.0, clamp(delta * 3.0, 0.0, 1.0))
		delta_r = lerp(delta_r, 0.0, clamp(delta * 3.0, 0.0, 1.0))
	alpha = trim_alpha
	# 更新摄像机（准星方向=目标指向，机头收敛后与其重合）
	_update_camera(delta)
	is_flying = global_position.y > 2.0 and airspeed > takeoff_speed * 0.5

func _update_ccip() -> void:
	"""弹道计算机（CCIP）：实时数值积分炮弹轨迹，在落点显示标记
	仅现代飞机（avionics.has_ccip=true）启用，用与 projectile.gd 一致的物理参数"""
	if not has_ccip or not is_player_controlled or is_destroyed:
		if _ccip_marker:
			_ccip_marker.visible = false
		return
	# 延迟创建 marker
	if not _ccip_marker:
		_ccip_marker = Sprite3D.new()
		var ccip_col := SettingsManager.get_ccip_color()
		# 画一个圆环标记
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for x in range(32):
			for y in range(32):
				var dx = x - 16.0
				var dy = y - 16.0
				var d = sqrt(dx*dx + dy*dy)
				if d > 11.0 and d < 14.0:
					img.set_pixel(x, y, ccip_col)
				elif d < 2.0:
					img.set_pixel(x, y, ccip_col)
		_ccip_marker.texture = ImageTexture.create_from_image(img)
		_ccip_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_ccip_marker.pixel_size = 0.15 * SettingsManager.get_ccip_size()
		_ccip_marker.no_depth_test = true
		# 挂到 current_scene；无场景时（SceneTree 测试/headless）挂到 root 兜底
		var _target_parent: Node = get_tree().current_scene
		if _target_parent == null:
			_target_parent = get_tree().root
		_target_parent.add_child(_ccip_marker)
	# 获取发射点
	var mz: Node3D = muzzle_node if muzzle_node else (extra_muzzle_nodes[0] if not extra_muzzle_nodes.is_empty() else null)
	if not mz:
		_ccip_marker.visible = false
		return
	var start_pos := mz.global_position
	var fire_dir := -mz.global_transform.basis.z.normalized()
	# 获取当前弹药参数
	var v0: float = 800.0
	var cd: float = 0.1
	var m: float = 10.0
	if current_ammo_index < ammo_types.size():
		var ammo = ammo_types[current_ammo_index]
		v0 = ammo.get("muzzle_velocity", 800.0)
		cd = ammo.get("drag_coefficient", 0.1)
		m = ammo.get("mass", 10.0)
	# 初速 = 飞机速度 + 炮弹初速（沿炮管方向）
	var vel := velocity + fire_dir * v0
	var pos := start_pos
	var dt := 0.05
	var t := 0.0
	const DRAG_FACTOR := 0.0003  # 与 projectile.gd 一致
	const PROJ_GRAVITY := 9.81   # 炮弹重力（与载具重力20不同）
	while pos.y > 0.0 and t < 10.0:
		var spd := vel.length()
		if spd > 0.0:
			var drag := cd * spd * spd / m * DRAG_FACTOR
			vel -= vel.normalized() * drag * dt
		vel.y -= PROJ_GRAVITY * dt
		pos += vel * dt
		t += dt
	# 实时更新颜色和大小（设置可能在游戏中改变）
	var ccip_col := SettingsManager.get_ccip_color()
	_ccip_marker.modulate = ccip_col
	_ccip_marker.pixel_size = 0.15 * SettingsManager.get_ccip_size()
	if _ccip_marker.is_inside_tree():
		_ccip_marker.global_position = pos
		_ccip_marker.visible = true

func _update_camera(delta: float) -> void:
	if not camera_pivot:
		return
	# 手动跟随机体位置（top_level 下必须每帧设置），锚点固定在机体正上方基准，
	# 只取世界系偏移，不继承机身滚转/俯仰 -> 机动时不绕机体画圈，消除画面抖动
	camera_pivot.global_position = global_position + Vector3(0, 3.0, 0)
	# 相机在世界系中相对锚点的后上方偏移（跟随目标指向的 yaw/pitch，不随机身滚转）
	# 直接用目标角度构造四元数：等价旧"欧拉→方向→atan2/asin 反解→再欧拉"的语义，
	# 但消除了反解在俯仰接近±90°时 yaw 退化（噪声跳变）导致的视角突然左右切换
	var target_quat: Quaternion = Quaternion(Basis.from_euler(Vector3(
		target_pitch + deg_to_rad(free_look_pitch),
		target_yaw + deg_to_rad(free_look_yaw),
		0.0)))
	var cur_quat: Quaternion = camera_pivot.global_transform.basis.get_rotation_quaternion()
	camera_pivot.global_transform.basis = Basis(cur_quat.slerp(target_quat, clamp(delta * cam_follow_speed, 0.0, 1.0)))
	# 右键瞄准：降低+拉近+fov收窄（观察机头下方/地面，不影响飞行控制）
	if camera_3d:
		var t_y := _default_cam_y - 5.0 if is_aim_mode else _default_cam_y
		var t_z := _default_cam_z - 7.0 if is_aim_mode else _default_cam_z
		var t_fov := 40.0 if is_aim_mode else _default_cam_fov
		camera_3d.position.y = lerp(camera_3d.position.y, t_y, 8.0 * delta)
		camera_3d.position.z = lerp(camera_3d.position.z, t_z, 8.0 * delta)
		camera_3d.fov = lerp(camera_3d.fov, t_fov, 8.0 * delta)
	# 防止摄像机穿到地底：整体抬高 pivot 世界位置（不污染相机局部坐标、不累加，飞高后自然归位）
	if camera_3d and camera_3d.global_position.y < 1.0:
		camera_pivot.global_position.y += 1.0 - camera_3d.global_position.y

func _sync_camera_immediate() -> void:
	"""立即将相机对准机头方向（初始/复位）"""
	if not camera_pivot:
		return
	camera_pivot.global_position = global_position + Vector3(0, 3.0, 0)
	camera_pivot.global_transform.basis = global_transform.basis

func _input(event: InputEvent) -> void:
	if not is_player_controlled or is_destroyed:
		return
	# 自由视角按键（V键，可自定义）
	_handle_free_look_input(event)
	# 右键瞄准视角（机头偏下观察）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		is_aim_mode = event.pressed
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if is_free_look_active():
			# 自由视角：鼠标只转动观察方向，不写入目标指向（飞行可控性不受影响）
			# 鼠标上移(relative.y<0) → free_look_pitch增大 → 视角上仰
			free_look_yaw -= event.relative.x * aim_sensitivity
			free_look_pitch = clamp(free_look_pitch - event.relative.y * aim_sensitivity, -85.0, 85.0)
		else:
			# 鼠标引导目标指向（世界系：右移→右转，上移→抬头/准心上移）
			# 鼠标上移(relative.y<0) → target_pitch增大 → 抬头
			target_yaw -= deg_to_rad(event.relative.x * aim_sensitivity)
			target_pitch -= deg_to_rad(event.relative.y * aim_sensitivity)
			target_yaw = wrapf(target_yaw, -PI, PI)
			target_pitch = clamp(target_pitch, deg_to_rad(max_aim_pitch_down), deg_to_rad(max_aim_pitch_up))
			_mouse_idle_time = 0.0  # 有鼠标移动，重置空闲计时
	# 开火已移至 _physics_process 每帧轮询按住状态（fire 键/移动端按钮连续射击）
	if event.is_action_pressed("landing_gear"):
		_toggle_landing_gear()
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
