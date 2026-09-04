extends Control
## 载具资源导入对话框
## 功能：选择外部3D模型文件，自动复制到项目目录并生成载具JSON配置

signal import_finished(vehicle_id: String)
signal cancelled()

@onready var file_dialog: FileDialog = $FileDialog
@onready var model_path_label: Label = $Panel/Scroll/VBox/ModelRow/ModelPathLabel
@onready var browse_button: Button = $Panel/Scroll/VBox/ModelRow/BrowseButton
@onready var id_input: LineEdit = $Panel/Scroll/VBox/FormGrid/IDInput
@onready var name_input: LineEdit = $Panel/Scroll/VBox/FormGrid/NameInput
@onready var nation_input: LineEdit = $Panel/Scroll/VBox/FormGrid/NationInput
@onready var type_option: OptionButton = $Panel/Scroll/VBox/FormGrid/TypeOption
@onready var era_input: LineEdit = $Panel/Scroll/VBox/FormGrid/EraInput
@onready var mass_input: LineEdit = $Panel/Scroll/VBox/FormGrid/MassInput
@onready var speed_input: LineEdit = $Panel/Scroll/VBox/FormGrid/SpeedInput
@onready var turret_rate_label: Label = $Panel/Scroll/VBox/FormGrid/TurretRateLabel
@onready var turret_rate_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TurretRateInput
@onready var weapon_option: OptionButton = $Panel/Scroll/VBox/FormGrid/WeaponOption
@onready var fire_rate_input: LineEdit = $Panel/Scroll/VBox/FormGrid/FireRateInput
@onready var ammo_capacity_input: LineEdit = $Panel/Scroll/VBox/FormGrid/AmmoCapacityInput
@onready var reload_time_input: LineEdit = $Panel/Scroll/VBox/FormGrid/ReloadTimeInput
@onready var secondary_weapon_option: OptionButton = $Panel/Scroll/VBox/FormGrid/SecondaryWeaponOption
@onready var sec_fire_rate_input: LineEdit = $Panel/Scroll/VBox/FormGrid/SecFireRateInput
@onready var sec_ammo_cap_input: LineEdit = $Panel/Scroll/VBox/FormGrid/SecAmmoCapInput
@onready var sec_reload_input: LineEdit = $Panel/Scroll/VBox/FormGrid/SecReloadInput
# 装甲参数
@onready var hull_front_input: LineEdit = $Panel/Scroll/VBox/FormGrid/HullFrontInput
@onready var hull_side_input: LineEdit = $Panel/Scroll/VBox/FormGrid/HullSideInput
@onready var hull_rear_input: LineEdit = $Panel/Scroll/VBox/FormGrid/HullRearInput
@onready var turret_front_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TurretFrontInput
@onready var turret_side_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TurretSideInput
@onready var turret_rear_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TurretRearInput
# 机动参数
@onready var acceleration_input: LineEdit = $Panel/Scroll/VBox/FormGrid/AccelerationInput
@onready var deceleration_input: LineEdit = $Panel/Scroll/VBox/FormGrid/DecelerationInput
@onready var turn_rate_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TurnRateInput
@onready var brake_force_input: LineEdit = $Panel/Scroll/VBox/FormGrid/BrakeForceInput
@onready var gun_elev_max_input: LineEdit = $Panel/Scroll/VBox/FormGrid/GunElevMaxInput
@onready var gun_elev_min_input: LineEdit = $Panel/Scroll/VBox/FormGrid/GunElevMinInput
# 模块参数（18个模块，每个模块：血量+装甲+标题）
@onready var mod_engine_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_engine_Title
@onready var mod_engine_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_engine_TitleSpacer
@onready var mod_engine_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_engine_HealthLabel
@onready var mod_engine_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_engine_HealthInput
@onready var mod_engine_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_engine_ArmorLabel
@onready var mod_engine_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_engine_ArmorInput
@onready var mod_transmission_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_transmission_Title
@onready var mod_transmission_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_transmission_TitleSpacer
@onready var mod_transmission_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_transmission_HealthLabel
@onready var mod_transmission_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_transmission_HealthInput
@onready var mod_transmission_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_transmission_ArmorLabel
@onready var mod_transmission_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_transmission_ArmorInput
@onready var mod_track_left_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_left_Title
@onready var mod_track_left_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_left_TitleSpacer
@onready var mod_track_left_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_left_HealthLabel
@onready var mod_track_left_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_track_left_HealthInput
@onready var mod_track_left_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_left_ArmorLabel
@onready var mod_track_left_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_track_left_ArmorInput
@onready var mod_track_right_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_right_Title
@onready var mod_track_right_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_right_TitleSpacer
@onready var mod_track_right_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_right_HealthLabel
@onready var mod_track_right_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_track_right_HealthInput
@onready var mod_track_right_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_track_right_ArmorLabel
@onready var mod_track_right_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_track_right_ArmorInput
@onready var mod_turret_ring_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_Title
@onready var mod_turret_ring_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_TitleSpacer
@onready var mod_turret_ring_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_HealthLabel
@onready var mod_turret_ring_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_HealthInput
@onready var mod_turret_ring_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_ArmorLabel
@onready var mod_turret_ring_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_turret_ring_ArmorInput
@onready var mod_gun_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_gun_Title
@onready var mod_gun_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_gun_TitleSpacer
@onready var mod_gun_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_gun_HealthLabel
@onready var mod_gun_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_gun_HealthInput
@onready var mod_gun_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_gun_ArmorLabel
@onready var mod_gun_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_gun_ArmorInput
@onready var mod_ammo_rack_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_Title
@onready var mod_ammo_rack_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_TitleSpacer
@onready var mod_ammo_rack_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_HealthLabel
@onready var mod_ammo_rack_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_HealthInput
@onready var mod_ammo_rack_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_ArmorLabel
@onready var mod_ammo_rack_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_ammo_rack_ArmorInput
@onready var mod_fuel_tank_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_Title
@onready var mod_fuel_tank_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_TitleSpacer
@onready var mod_fuel_tank_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_HealthLabel
@onready var mod_fuel_tank_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_HealthInput
@onready var mod_fuel_tank_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_ArmorLabel
@onready var mod_fuel_tank_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_fuel_tank_ArmorInput
@onready var mod_crew_driver_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_Title
@onready var mod_crew_driver_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_TitleSpacer
@onready var mod_crew_driver_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_HealthLabel
@onready var mod_crew_driver_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_HealthInput
@onready var mod_crew_driver_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_ArmorLabel
@onready var mod_crew_driver_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_driver_ArmorInput
@onready var mod_crew_commander_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_Title
@onready var mod_crew_commander_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_TitleSpacer
@onready var mod_crew_commander_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_HealthLabel
@onready var mod_crew_commander_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_HealthInput
@onready var mod_crew_commander_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_ArmorLabel
@onready var mod_crew_commander_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_commander_ArmorInput
@onready var mod_crew_gunner_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_Title
@onready var mod_crew_gunner_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_TitleSpacer
@onready var mod_crew_gunner_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_HealthLabel
@onready var mod_crew_gunner_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_HealthInput
@onready var mod_crew_gunner_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_ArmorLabel
@onready var mod_crew_gunner_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_gunner_ArmorInput
@onready var mod_crew_loader_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_Title
@onready var mod_crew_loader_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_TitleSpacer
@onready var mod_crew_loader_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_HealthLabel
@onready var mod_crew_loader_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_HealthInput
@onready var mod_crew_loader_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_ArmorLabel
@onready var mod_crew_loader_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_loader_ArmorInput
@onready var mod_main_rotor_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_Title
@onready var mod_main_rotor_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_TitleSpacer
@onready var mod_main_rotor_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_HealthLabel
@onready var mod_main_rotor_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_HealthInput
@onready var mod_main_rotor_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_ArmorLabel
@onready var mod_main_rotor_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_main_rotor_ArmorInput
@onready var mod_tail_rotor_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_Title
@onready var mod_tail_rotor_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_TitleSpacer
@onready var mod_tail_rotor_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_HealthLabel
@onready var mod_tail_rotor_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_HealthInput
@onready var mod_tail_rotor_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_ArmorLabel
@onready var mod_tail_rotor_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_tail_rotor_ArmorInput
@onready var mod_crew_pilot_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_Title
@onready var mod_crew_pilot_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_TitleSpacer
@onready var mod_crew_pilot_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_HealthLabel
@onready var mod_crew_pilot_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_HealthInput
@onready var mod_crew_pilot_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_ArmorLabel
@onready var mod_crew_pilot_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_crew_pilot_ArmorInput
@onready var mod_left_wing_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_Title
@onready var mod_left_wing_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_TitleSpacer
@onready var mod_left_wing_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_HealthLabel
@onready var mod_left_wing_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_HealthInput
@onready var mod_left_wing_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_ArmorLabel
@onready var mod_left_wing_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_left_wing_ArmorInput
@onready var mod_right_wing_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_Title
@onready var mod_right_wing_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_TitleSpacer
@onready var mod_right_wing_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_HealthLabel
@onready var mod_right_wing_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_HealthInput
@onready var mod_right_wing_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_ArmorLabel
@onready var mod_right_wing_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_right_wing_ArmorInput
@onready var mod_tail_title: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_Title
@onready var mod_tail_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_TitleSpacer
@onready var mod_tail_health_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_HealthLabel
@onready var mod_tail_health_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_tail_HealthInput
@onready var mod_tail_armor_label: Label = $Panel/Scroll/VBox/FormGrid/Mod_tail_ArmorLabel
@onready var mod_tail_armor_input: LineEdit = $Panel/Scroll/VBox/FormGrid/Mod_tail_ArmorInput
# 直升机参数
@onready var max_lift_force_input: LineEdit = $Panel/Scroll/VBox/FormGrid/MaxLiftForceInput
@onready var hover_collective_input: LineEdit = $Panel/Scroll/VBox/FormGrid/HoverCollectiveInput
@onready var yaw_torque_input: LineEdit = $Panel/Scroll/VBox/FormGrid/YawTorqueInput
@onready var pitch_torque_input: LineEdit = $Panel/Scroll/VBox/FormGrid/PitchTorqueInput
@onready var roll_torque_input: LineEdit = $Panel/Scroll/VBox/FormGrid/RollTorqueInput
@onready var bank_limit_input: LineEdit = $Panel/Scroll/VBox/FormGrid/BankLimitInput
@onready var cruise_speed_input: LineEdit = $Panel/Scroll/VBox/FormGrid/CruiseSpeedInput
@onready var crash_impact_input: LineEdit = $Panel/Scroll/VBox/FormGrid/CrashImpactInput
# 飞机参数
@onready var max_thrust_input: LineEdit = $Panel/Scroll/VBox/FormGrid/MaxThrustInput
@onready var wing_area_input: LineEdit = $Panel/Scroll/VBox/FormGrid/WingAreaInput
@onready var cl_alpha_input: LineEdit = $Panel/Scroll/VBox/FormGrid/ClAlphaInput
@onready var drag_coeff_input: LineEdit = $Panel/Scroll/VBox/FormGrid/DragCoeffInput
@onready var max_aoa_input: LineEdit = $Panel/Scroll/VBox/FormGrid/MaxAoaInput
@onready var takeoff_speed_input: LineEdit = $Panel/Scroll/VBox/FormGrid/TakeoffSpeedInput
@onready var stall_speed_input: LineEdit = $Panel/Scroll/VBox/FormGrid/StallSpeedInput
@onready var inertia_roll_input: LineEdit = $Panel/Scroll/VBox/FormGrid/InertiaRollInput
# 分组标题（用于显示/隐藏）
@onready var heli_title_label: Label = $Panel/Scroll/VBox/FormGrid/HeliTitleLabel
@onready var heli_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/HeliTitleSpacer
@onready var plane_title_label: Label = $Panel/Scroll/VBox/FormGrid/PlaneTitleLabel
@onready var plane_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/PlaneTitleSpacer
@onready var max_lift_force_label: Label = $Panel/Scroll/VBox/FormGrid/MaxLiftForceLabel
@onready var hover_collective_label: Label = $Panel/Scroll/VBox/FormGrid/HoverCollectiveLabel
@onready var yaw_torque_label: Label = $Panel/Scroll/VBox/FormGrid/YawTorqueLabel
@onready var pitch_torque_label: Label = $Panel/Scroll/VBox/FormGrid/PitchTorqueLabel
@onready var roll_torque_label: Label = $Panel/Scroll/VBox/FormGrid/RollTorqueLabel
@onready var bank_limit_label: Label = $Panel/Scroll/VBox/FormGrid/BankLimitLabel
@onready var cruise_speed_label: Label = $Panel/Scroll/VBox/FormGrid/CruiseSpeedLabel
@onready var crash_impact_label: Label = $Panel/Scroll/VBox/FormGrid/CrashImpactLabel
@onready var max_thrust_label: Label = $Panel/Scroll/VBox/FormGrid/MaxThrustLabel
@onready var wing_area_label: Label = $Panel/Scroll/VBox/FormGrid/WingAreaLabel
@onready var cl_alpha_label: Label = $Panel/Scroll/VBox/FormGrid/ClAlphaLabel
@onready var drag_coeff_label: Label = $Panel/Scroll/VBox/FormGrid/DragCoeffLabel
@onready var max_aoa_label: Label = $Panel/Scroll/VBox/FormGrid/MaxAoaLabel
@onready var takeoff_speed_label: Label = $Panel/Scroll/VBox/FormGrid/TakeoffSpeedLabel
@onready var stall_speed_label: Label = $Panel/Scroll/VBox/FormGrid/StallSpeedLabel
@onready var inertia_roll_label: Label = $Panel/Scroll/VBox/FormGrid/InertiaRollLabel
@onready var physics_title_label: Label = $Panel/Scroll/VBox/FormGrid/PhysicsTitleLabel
@onready var physics_title_spacer: Label = $Panel/Scroll/VBox/FormGrid/PhysicsTitleSpacer
@onready var gun_elev_max_label: Label = $Panel/Scroll/VBox/FormGrid/GunElevMaxLabel
@onready var gun_elev_min_label: Label = $Panel/Scroll/VBox/FormGrid/GunElevMinLabel
@onready var import_button: Button = $Panel/Scroll/VBox/ImportButton
@onready var cancel_button: Button = $Panel/Scroll/VBox/CancelButton
@onready var status_label: Label = $Panel/Scroll/VBox/StatusLabel

var selected_file_path: String = ""
# 所有模块名称列表
var module_names: Array = ['engine', 'transmission', 'track_left', 'track_right', 'turret_ring', 'gun', 'ammo_rack', 'fuel_tank', 'crew_driver', 'crew_commander', 'crew_gunner', 'crew_loader', 'main_rotor', 'tail_rotor', 'crew_pilot', 'left_wing', 'right_wing', 'tail']

func _ready() -> void:
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(_on_file_selected)
	browse_button.pressed.connect(func(): file_dialog.popup_centered())
	import_button.pressed.connect(_on_import)
	cancel_button.pressed.connect(_on_cancel)

	type_option.item_selected.connect(_on_type_changed)
	type_option.clear()
	# 地面载具
	type_option.add_item("轻型坦克", 0)
	type_option.add_item("中型坦克", 1)
	type_option.add_item("重型坦克", 2)
	type_option.add_item("主战坦克", 3)
	type_option.add_item("坦克歼击车", 4)
	type_option.add_item("自行火炮", 5)
	# 空中载具
	type_option.add_item("直升机", 6)
	type_option.add_item("固定翼飞机", 7)
	type_option.select(3)

	# 默认值
	nation_input.text = "USA"
	era_input.text = "modern"
	mass_input.text = "40000"
	speed_input.text = "55"
	turret_rate_input.text = "40"
	# 装甲默认值
	hull_front_input.text = "100"
	hull_side_input.text = "50"
	hull_rear_input.text = "30"
	turret_front_input.text = "120"
	turret_side_input.text = "60"
	turret_rear_input.text = "40"
	# 机动默认值
	acceleration_input.text = "3.0"
	deceleration_input.text = "5.0"
	turn_rate_input.text = "30"
	brake_force_input.text = "6.0"
	gun_elev_max_input.text = "20"
	gun_elev_min_input.text = "-10"
	# 模块默认值
	mod_engine_health_input.text = "100"
	mod_engine_armor_input.text = "12"
	mod_transmission_health_input.text = "70"
	mod_transmission_armor_input.text = "8"
	mod_track_left_health_input.text = "50"
	mod_track_left_armor_input.text = "5"
	mod_track_right_health_input.text = "50"
	mod_track_right_armor_input.text = "5"
	mod_turret_ring_health_input.text = "80"
	mod_turret_ring_armor_input.text = "40"
	mod_gun_health_input.text = "70"
	mod_gun_armor_input.text = "25"
	mod_ammo_rack_health_input.text = "40"
	mod_ammo_rack_armor_input.text = "15"
	mod_fuel_tank_health_input.text = "60"
	mod_fuel_tank_armor_input.text = "8"
	mod_crew_driver_health_input.text = "30"
	mod_crew_driver_armor_input.text = "0"
	mod_crew_commander_health_input.text = "30"
	mod_crew_commander_armor_input.text = "0"
	mod_crew_gunner_health_input.text = "30"
	mod_crew_gunner_armor_input.text = "0"
	mod_crew_loader_health_input.text = "30"
	mod_crew_loader_armor_input.text = "0"
	mod_main_rotor_health_input.text = "80"
	mod_main_rotor_armor_input.text = "0"
	mod_tail_rotor_health_input.text = "40"
	mod_tail_rotor_armor_input.text = "0"
	mod_crew_pilot_health_input.text = "30"
	mod_crew_pilot_armor_input.text = "0"
	mod_left_wing_health_input.text = "70"
	mod_left_wing_armor_input.text = "5"
	mod_right_wing_health_input.text = "70"
	mod_right_wing_armor_input.text = "5"
	mod_tail_health_input.text = "40"
	mod_tail_armor_input.text = "3"
	# 直升机默认参数
	max_lift_force_input.text = "25000"
	hover_collective_input.text = "0.55"
	yaw_torque_input.text = "800"
	pitch_torque_input.text = "1200"
	roll_torque_input.text = "1000"
	bank_limit_input.text = "60"
	cruise_speed_input.text = "40"
	crash_impact_input.text = "1.0"
	# 飞机默认参数
	max_thrust_input.text = "80000"
	wing_area_input.text = "25.0"
	cl_alpha_input.text = "4.5"
	drag_coeff_input.text = "0.02"
	max_aoa_input.text = "15"
	takeoff_speed_input.text = "45"
	stall_speed_input.text = "35"
	inertia_roll_input.text = "5000"
	fire_rate_input.text = "6"
	ammo_capacity_input.text = "40"
	reload_time_input.text = "5.0"

	# 填充武器下拉列表
	_populate_weapons()
	# 初始根据类型显示/隐藏相关字段
	_on_type_changed(type_option.selected)

func _on_type_changed(index: int) -> void:
	"""根据载具类型动态显示/隐藏相关输入字段"""
	var type_idx = type_option.get_item_id(index) if index >= 0 else 3
	var is_helicopter = type_idx == 6
	var is_airplane = type_idx == 7
	var is_aircraft = is_helicopter or is_airplane
	# 飞机/直升机没有炮塔，隐藏炮塔转速字段
	turret_rate_label.visible = not is_aircraft
	turret_rate_input.visible = not is_aircraft
	# 飞机/直升机没有主炮俯仰角，隐藏相关字段
	gun_elev_max_label.visible = not is_aircraft
	gun_elev_max_input.visible = not is_aircraft
	gun_elev_min_label.visible = not is_aircraft
	gun_elev_min_input.visible = not is_aircraft
	# 显示/隐藏直升机参数
	var show_heli = is_helicopter
	heli_title_label.visible = show_heli
	heli_title_spacer.visible = show_heli
	max_lift_force_label.visible = show_heli
	max_lift_force_input.visible = show_heli
	hover_collective_label.visible = show_heli
	hover_collective_input.visible = show_heli
	yaw_torque_label.visible = show_heli
	yaw_torque_input.visible = show_heli
	pitch_torque_label.visible = show_heli
	pitch_torque_input.visible = show_heli
	roll_torque_label.visible = show_heli
	roll_torque_input.visible = show_heli
	bank_limit_label.visible = show_heli
	bank_limit_input.visible = show_heli
	cruise_speed_label.visible = show_heli
	cruise_speed_input.visible = show_heli
	crash_impact_label.visible = show_heli
	crash_impact_input.visible = show_heli
	# 显示/隐藏飞机参数
	var show_plane = is_airplane
	plane_title_label.visible = show_plane
	plane_title_spacer.visible = show_plane
	max_thrust_label.visible = show_plane
	max_thrust_input.visible = show_plane
	wing_area_label.visible = show_plane
	wing_area_input.visible = show_plane
	cl_alpha_label.visible = show_plane
	cl_alpha_input.visible = show_plane
	drag_coeff_label.visible = show_plane
	drag_coeff_input.visible = show_plane
	max_aoa_label.visible = show_plane
	max_aoa_input.visible = show_plane
	takeoff_speed_label.visible = show_plane
	takeoff_speed_input.visible = show_plane
	stall_speed_label.visible = show_plane
	stall_speed_input.visible = show_plane
	inertia_roll_label.visible = show_plane
	inertia_roll_input.visible = show_plane
	if is_aircraft:
		turret_rate_input.text = "0"
		gun_elev_max_input.text = "0"
		gun_elev_min_input.text = "0"
	# 根据载具类型显示/隐藏模块参数
	var visible_modules: Array = []
	if is_helicopter:
		visible_modules = ['engine', 'transmission', 'main_rotor', 'tail_rotor', 'crew_pilot', 'crew_gunner', 'fuel_tank', 'ammo_rack']
	elif is_airplane:
		visible_modules = ['engine', 'left_wing', 'right_wing', 'tail', 'crew_pilot', 'fuel_tank', 'ammo_rack']
	else:
		visible_modules = ['engine', 'transmission', 'track_left', 'track_right', 'turret_ring', 'gun', 'ammo_rack', 'fuel_tank', 'crew_driver', 'crew_commander', 'crew_gunner', 'crew_loader']
	for mod in module_names:
		var is_visible = mod in visible_modules
		get("mod_" + mod + "_title").visible = is_visible
		get("mod_" + mod + "_title_spacer").visible = is_visible
		get("mod_" + mod + "_health_label").visible = is_visible
		get("mod_" + mod + "_health_input").visible = is_visible
		get("mod_" + mod + "_armor_label").visible = is_visible
		get("mod_" + mod + "_armor_input").visible = is_visible

func _populate_weapons() -> void:
	"""从DataLoader加载所有武器，填充主/副武器下拉列表"""
	var weapons = DataLoader.get_all_weapons()
	# 主武器
	weapon_option.clear()
	var idx = 0
	for weapon_id in weapons.keys():
		var w = weapons[weapon_id]
		var display_name = w.get("name", weapon_id)
		weapon_option.add_item(display_name, idx)
		weapon_option.set_item_metadata(idx, weapon_id)
		idx += 1
	if weapon_option.item_count == 0:
		weapon_option.add_item("M256 120mm滑膛炮", 0)
		weapon_option.set_item_metadata(0, "gun_120mm_m256")
	# 副武器（第一个选项为"无"）
	secondary_weapon_option.clear()
	secondary_weapon_option.add_item("无", 0)
	secondary_weapon_option.set_item_metadata(0, "")
	idx = 1
	for weapon_id in weapons.keys():
		var w = weapons[weapon_id]
		var display_name = w.get("name", weapon_id)
		secondary_weapon_option.add_item(display_name, idx)
		secondary_weapon_option.set_item_metadata(idx, weapon_id)
		idx += 1

func _build_weapons_array(primary_id: String, p_fire: float, p_cap: int, p_reload: float, sec_id: String, s_fire: float, s_cap: int, s_reload: float) -> Array:
	var arr = [
		{"slot": "primary", "weapon_id": primary_id, "fire_rate": p_fire, "ammo_capacity": p_cap, "reload_time": p_reload}
	]
	if sec_id != "":
		arr.append({"slot": "secondary", "weapon_id": sec_id, "fire_rate": s_fire, "ammo_capacity": s_cap, "reload_time": s_reload})
	return arr

func _on_file_selected(path: String) -> void:
	selected_file_path = path
	model_path_label.text = path.get_file()
	# 自动填充ID和名称
	var base_name = path.get_file().get_basename().to_lower()
	if id_input.text == "":
		id_input.text = "tank_" + base_name
	if name_input.text == "":
		name_input.text = base_name.capitalize()
	status_label.text = "已选择模型文件"
	status_label.modulate = Color(0.5, 0.8, 1.0)

func _on_import() -> void:
	if selected_file_path == "":
		_set_error("请先选择3D模型文件！")
		return
	if id_input.text.strip_edges() == "":
		_set_error("请输入载具ID！")
		return
	if name_input.text.strip_edges() == "":
		_set_error("请输入载具名称！")
		return

	var vehicle_id = id_input.text.strip_edges()
	# 根据载具类型设置ID前缀
	var type_idx = type_option.selected
	var vehicle_class = "tank"
	if type_idx >= 0:
		var tid = type_option.get_item_id(type_idx)
		if tid == 6:
			vehicle_class = "helicopter"
		elif tid == 7:
			vehicle_class = "airplane"
	var id_prefix = "tank_"
	if vehicle_class == "helicopter":
		id_prefix = "heli_"
	elif vehicle_class == "airplane":
		id_prefix = "plane_"
	# 先移除已有的前缀（避免 plane_tank_xxx 这种重复前缀）
	for old_prefix in ["tank_", "heli_", "plane_"]:
		if vehicle_id.begins_with(old_prefix):
			vehicle_id = vehicle_id.substr(old_prefix.length())
			break
	# 清理ID中的非法字符（只保留字母、数字、下划线、连字符）
	var clean_id = ""
	for ch in vehicle_id:
		if ch.is_valid_ascii_identifier() or ch == "-" or ch == "_":
			clean_id += ch
	vehicle_id = clean_id if clean_id != "" else "vehicle"
	# 检查ID是否有效（不能只有连字符/下划线）
	var has_alphanumeric = false
	for ch in vehicle_id:
		if ch.is_valid_ascii_identifier() and ch != "_":
			has_alphanumeric = true
			break
	if not has_alphanumeric:
		_set_error("载具ID无效，请包含字母或数字")
		return
	# 加上正确的前缀
	vehicle_id = id_prefix + vehicle_id

	# 1. 复制模型文件到 user:// 目录（导出后可写）
	var model_ext = selected_file_path.get_extension().to_lower()
	var model_filename = "%s.%s" % [vehicle_id, model_ext]
	var model_dir = "user://assets/models/"
	# 使用 globalize_path 将 user:// 转为绝对路径，再用 make_dir_recursive_absolute 创建
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(model_dir))
	var dest_path = model_dir + model_filename

	var source_file = FileAccess.open(selected_file_path, FileAccess.READ)
	if not source_file:
		_set_error("无法读取源文件: %s" % selected_file_path)
		return
	var file_data = source_file.get_buffer(source_file.get_length())
	source_file.close()

	var dest_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest_file:
		_set_error("无法写入目标文件: %s" % dest_path)
		return
	dest_file.store_buffer(file_data)
	dest_file.close()
	# 验证文件是否写入成功
	if not FileAccess.file_exists(dest_path):
		_set_error("模型文件写入失败: %s" % dest_path)
		return
	print("[VehicleImporter] 模型文件已复制: %s (%d bytes)" % [dest_path, file_data.size()])

	# 2. 生成载具场景包装（如果是glb/gltf，Godot可以直接加载）
	var scene_path = model_dir + "%s.tscn" % vehicle_id
	if model_ext in ["glb", "gltf"]:
		# glb可以直接作为场景加载，不需要额外包装
		scene_path = dest_path
	else:
		# 其他格式生成一个简单的tscn包装
		_generate_model_scene(vehicle_id, dest_path, scene_path)

	# 3. 生成载具JSON配置（保存到 user://，导出后可写）
	var vehicle_data = _generate_vehicle_config(vehicle_id, scene_path)
	var vehicle_dir = "user://data/vehicles/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vehicle_dir))
	var json_path = vehicle_dir + "%s.json" % vehicle_id
	var json_file = FileAccess.open(json_path, FileAccess.WRITE)
	if not json_file:
		_set_error("无法写入配置文件: %s" % json_path)
		return
	json_file.store_string(JSON.stringify(vehicle_data, "  "))
	json_file.close()
	# 验证配置文件是否写入成功
	if not FileAccess.file_exists(json_path):
		_set_error("配置文件写入失败: %s" % json_path)
		return
	print("[VehicleImporter] 配置文件已保存: %s" % json_path)

	# 4. 重新加载数据
	DataLoader.load_vehicles()

	status_label.text = "导入成功！载具: %s" % name_input.text
	status_label.modulate = Color(0.3, 1.0, 0.3)
	import_finished.emit(vehicle_id)

	# 2秒后自动关闭
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _generate_model_scene(vehicle_id: String, model_path: String, scene_path: String) -> void:
	# 生成一个简单的tscn，引用外部模型
	var tscn_content = """[gd_scene load_steps=2 format=3 uid="uid://%s"]

[ext_resource type="PackedScene" path="%s" id="1_model"]

[node name="%s" instance=ExtResource("1_model")]
""" % [vehicle_id.md5_text().substr(0, 12), model_path, vehicle_id]
	var f = FileAccess.open(scene_path, FileAccess.WRITE)
	if f:
		f.store_string(tscn_content)
		f.close()

func _get_crew_count(vclass: String) -> int:
	"""根据载具类型返回乘员数量"""
	if vclass == "helicopter":
		return 2
	elif vclass == "airplane":
		return 1
	else:
		return 4

func _get_modules_config(vclass: String) -> Array:
	"""根据载具类型生成模块配置，使用用户输入的每个模块的血量和装甲"""
	var base_modules: Array = []
	if vclass == "helicopter":
		base_modules = [
			{"name": "engine", "display_name": "发动机", "max_health": 100, "armor_thickness": 12, "is_critical": false, "position": [0, 0.5, -1.5], "size": [1.0, 0.8, 1.5]},
			{"name": "transmission", "display_name": "传动系统", "max_health": 70, "armor_thickness": 8, "is_critical": false, "position": [0, 0.8, -0.5], "size": [0.8, 0.5, 0.8]},
			{"name": "main_rotor", "display_name": "主旋翼", "max_health": 80, "armor_thickness": 0, "is_critical": true, "position": [0, 2.5, 0], "size": [8.0, 0.2, 0.5]},
			{"name": "tail_rotor", "display_name": "尾旋翼", "max_health": 40, "armor_thickness": 0, "is_critical": false, "position": [0, 1.5, -4.0], "size": [0.3, 1.5, 0.3]},
			{"name": "crew_pilot", "display_name": "飞行员", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0, 1.0, 0.5], "size": [0.5, 0.7, 0.5]},
			{"name": "crew_gunner", "display_name": "武器官", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0, 1.0, -0.3], "size": [0.5, 0.7, 0.5]},
			{"name": "fuel_tank", "display_name": "油箱", "max_health": 60, "armor_thickness": 8, "is_critical": false, "position": [0, 0.5, -1.0], "size": [1.0, 0.6, 1.0]},
			{"name": "ammo_rack", "display_name": "弹药架", "max_health": 40, "armor_thickness": 15, "is_critical": true, "position": [0, 0.6, 0.0], "size": [1.0, 0.5, 0.8]}
		]
	elif vclass == "airplane":
		base_modules = [
			{"name": "engine", "display_name": "发动机", "max_health": 100, "armor_thickness": 12, "is_critical": false, "position": [0, 0.5, -3.0], "size": [1.0, 1.0, 2.0]},
			{"name": "left_wing", "display_name": "左机翼", "max_health": 70, "armor_thickness": 5, "is_critical": false, "position": [-5.0, 0.3, 0], "size": [8.0, 0.3, 2.0]},
			{"name": "right_wing", "display_name": "右机翼", "max_health": 70, "armor_thickness": 5, "is_critical": false, "position": [5.0, 0.3, 0], "size": [8.0, 0.3, 2.0]},
			{"name": "tail", "display_name": "尾翼", "max_health": 40, "armor_thickness": 3, "is_critical": false, "position": [0, 0.8, -5.0], "size": [3.0, 0.2, 1.5]},
			{"name": "crew_pilot", "display_name": "飞行员", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0, 0.8, 1.0], "size": [0.5, 0.7, 0.5]},
			{"name": "fuel_tank", "display_name": "油箱", "max_health": 80, "armor_thickness": 8, "is_critical": false, "position": [0, 0.4, -0.5], "size": [2.0, 0.6, 3.0]},
			{"name": "ammo_rack", "display_name": "弹药架", "max_health": 40, "armor_thickness": 15, "is_critical": true, "position": [0, 0.5, 0.5], "size": [1.0, 0.5, 1.0]}
		]
	else:
		# 坦克默认模块
		base_modules = [
			{"name": "engine", "display_name": "发动机", "max_health": 100, "armor_thickness": 12, "is_critical": false, "position": [0, 0.5, -1.8], "size": [1.2, 0.8, 1.2]},
			{"name": "transmission", "display_name": "传动系统", "max_health": 70, "armor_thickness": 8, "is_critical": false, "position": [0, 0.3, -0.8], "size": [1.0, 0.5, 0.7]},
			{"name": "track_left", "display_name": "左履带", "max_health": 50, "armor_thickness": 5, "is_critical": false, "position": [-1.5, 0.3, 0], "size": [0.4, 0.5, 5.0]},
			{"name": "track_right", "display_name": "右履带", "max_health": 50, "armor_thickness": 5, "is_critical": false, "position": [1.5, 0.3, 0], "size": [0.4, 0.5, 5.0]},
			{"name": "turret_ring", "display_name": "炮塔座圈", "max_health": 80, "armor_thickness": 40, "is_critical": false, "position": [0, 1.0, 0], "size": [2.0, 0.25, 2.0]},
			{"name": "gun", "display_name": "主炮", "max_health": 70, "armor_thickness": 25, "is_critical": false, "position": [0, 1.3, 2.0], "size": [0.25, 0.25, 2.5]},
			{"name": "ammo_rack", "display_name": "弹药架", "max_health": 40, "armor_thickness": 15, "is_critical": true, "position": [0, 0.8, -0.3], "size": [1.2, 0.6, 0.8]},
			{"name": "fuel_tank", "display_name": "油箱", "max_health": 60, "armor_thickness": 8, "is_critical": false, "position": [-0.8, 0.4, -1.2], "size": [0.6, 0.5, 0.8]},
			{"name": "crew_driver", "display_name": "驾驶员", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0, 0.7, 1.2], "size": [0.5, 0.7, 0.5]},
			{"name": "crew_commander", "display_name": "车长", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0.4, 1.2, -0.2], "size": [0.5, 0.7, 0.5]},
			{"name": "crew_gunner", "display_name": "炮手", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [-0.4, 1.2, 0.3], "size": [0.5, 0.7, 0.5]},
			{"name": "crew_loader", "display_name": "装填手", "max_health": 30, "armor_thickness": 0, "is_critical": false, "position": [0.4, 1.2, 0.3], "size": [0.5, 0.7, 0.5]}
		]
	# 使用用户输入的每个模块的血量和装甲
	var result: Array = []
	for m in base_modules:
		var mod = m.duplicate()
		var mod_name = mod["name"]
		var health_input = get("mod_" + mod_name + "_health_input")
		var armor_input = get("mod_" + mod_name + "_armor_input")
		if health_input and str(health_input.text).is_valid_float():
			mod["max_health"] = int(float(health_input.text))
		if armor_input and str(armor_input.text).is_valid_float():
			mod["armor_thickness"] = int(float(armor_input.text))
		result.append(mod)
	return result

func _get_armor_config() -> Dictionary:
	"""从输入框获取装甲配置"""
	var hf = float(hull_front_input.text) if hull_front_input.text.is_valid_float() else 100.0
	var hs = float(hull_side_input.text) if hull_side_input.text.is_valid_float() else 50.0
	var hr = float(hull_rear_input.text) if hull_rear_input.text.is_valid_float() else 30.0
	var tf = float(turret_front_input.text) if turret_front_input.text.is_valid_float() else 120.0
	var ts = float(turret_side_input.text) if turret_side_input.text.is_valid_float() else 60.0
	var tr = float(turret_rear_input.text) if turret_rear_input.text.is_valid_float() else 40.0
	return {
		"hull_front": int(hf),
		"hull_side": int(hs),
		"hull_rear": int(hr),
		"turret_front": int(tf),
		"turret_side": int(ts),
		"turret_rear": int(tr),
		"armor_type": "rolled_homogeneous"
	}

func _get_default_physics(vclass: String, mass: float, speed: float, turret_rate: float) -> Dictionary:
	"""根据载具大类返回默认物理参数"""
	if vclass == "helicopter":
		return {
			"mass": int(mass) if mass > 0 else 8000,
			"max_speed": speed if speed > 0 else 293.0,
			"max_reverse_speed": -50.0,
			"acceleration": 8.0,
			"deceleration": 5.0,
			"turn_rate": 60.0,
			"turret_turn_rate": turret_rate,
			"max_lift_force": 35000.0,
			"hover_collective": 0.5,
			"yaw_torque": 2.0,
			"pitch_torque": 1.5,
			"roll_torque": 1.5,
			"auto_stabilize": 3.0,
			"collective_wheel_step": 0.08,
			"forward_pitch_offset": 0.25,
			"aim_sensitivity": 0.9,
			"max_aim_pitch_up": 90.0,
			"max_aim_pitch_down": -90.0,
			"guidance_gain": 1.2,
			"max_guidance_rate": 1.6,
			"bank_limit": 0.7,
			"cruise_speed": 30.0,
			"vh_follow_rate": 2.0,
			"rudder_assist_deg": 18.0,
			"crash_impact_scale": 0.6,
			"crash_no_spall": true
		}
	elif vclass == "airplane":
		return {
			"mass": int(mass) if mass > 0 else 9000,
			"max_speed": speed if speed > 0 else 706.0,
			"max_reverse_speed": 0.0,
			"acceleration": 15.0,
			"deceleration": 3.0,
			"turn_rate": 30.0,
			"turret_turn_rate": 0.0,
			"max_thrust": 48000.0,
			"wing_area": 75.0,
			"wingspan": 17.0,
			"mean_chord": 4.0,
			"drag_coefficient": 0.02,
			"cl_alpha": 4.5,
			"cl_zero": 0.08,
			"induced_drag": 0.05,
			"max_aoa": 0.3,
			"min_aoa": -0.25,
			"inertia_roll": 90000.0,
			"inertia_pitch": 320000.0,
			"brake_force": 2.0
		}
	else:
		var acc = float(acceleration_input.text) if acceleration_input.text.is_valid_float() else 3.0
		var dec = float(deceleration_input.text) if deceleration_input.text.is_valid_float() else 5.0
		var turn = float(turn_rate_input.text) if turn_rate_input.text.is_valid_float() else 30.0
		var brake = float(brake_force_input.text) if brake_force_input.text.is_valid_float() else 6.0
		var gun_max = float(gun_elev_max_input.text) if gun_elev_max_input.text.is_valid_float() else 20.0
		var gun_min = float(gun_elev_min_input.text) if gun_elev_min_input.text.is_valid_float() else -10.0
		return {
			"mass": int(mass),
			"max_speed": speed,
			"max_reverse_speed": -10.0,
			"acceleration": acc,
			"deceleration": dec,
			"turn_rate": turn,
			"turret_turn_rate": turret_rate,
			"gun_elevation_max": gun_max,
			"gun_elevation_min": gun_min,
			"brake_force": brake
		}

func _generate_vehicle_config(vehicle_id: String, scene_path: String) -> Dictionary:
	var mass = float(mass_input.text) if mass_input.text.is_valid_float() else 40000.0
	var speed = float(speed_input.text) if speed_input.text.is_valid_float() else 55.0

	var type_names = ["light_tank", "medium_tank", "heavy_tank", "main_battle_tank", "tank_destroyer", "spg"]
	var type_idx = type_option.get_item_id(type_option.selected)
	var vehicle_type = type_names[type_idx] if type_idx < type_names.size() else "medium_tank"
	# 载具大类：tank/helicopter/airplane（用于游戏逻辑区分地面/空中载具）
	var vehicle_class = "tank"
	if type_idx == 6:
		vehicle_class = "helicopter"
		vehicle_type = "helicopter"
	elif type_idx == 7:
		vehicle_class = "airplane"
		vehicle_type = "airplane"

	var turret_rate = float(turret_rate_input.text) if turret_rate_input.text.to_float() > 0 else 40.0
	var fire_rate = float(fire_rate_input.text) if fire_rate_input.text.is_valid_float() else 6.0
	var ammo_capacity = int(float(ammo_capacity_input.text)) if ammo_capacity_input.text.is_valid_float() else 40
	var reload_time = float(reload_time_input.text) if reload_time_input.text.is_valid_float() else 5.0
	var weapon_id = "gun_120mm_m256"
	if weapon_option.item_count > 0:
		weapon_id = str(weapon_option.get_item_metadata(weapon_option.selected))
	# 副武器
	var sec_weapon_id = ""
	if secondary_weapon_option.item_count > 0 and secondary_weapon_option.selected > 0:
		sec_weapon_id = str(secondary_weapon_option.get_item_metadata(secondary_weapon_option.selected))
	var sec_fire_rate = float(sec_fire_rate_input.text) if sec_fire_rate_input.text.is_valid_float() else 200.0
	var sec_ammo_cap = int(float(sec_ammo_cap_input.text)) if sec_ammo_cap_input.text.is_valid_float() else 2000
	var sec_reload = float(sec_reload_input.text) if sec_reload_input.text.is_valid_float() else 0.5

	return {
		"id": vehicle_id,
		"name": name_input.text.strip_edges(),
		"type": vehicle_class,
		"nation": nation_input.text.strip_edges(),
		"era": era_input.text.strip_edges(),
		"source": "custom",
		"description": "导入的载具: %s" % name_input.text.strip_edges(),
		"model": {
			"scene_path": scene_path,
			"mesh_path": "",
			"scale": 1.0
		},
		"physics": _get_default_physics(vehicle_class, mass, speed, turret_rate),
		"armor": _get_armor_config(),
		"modules": _get_modules_config(vehicle_class),
		"weapons": _build_weapons_array(weapon_id, fire_rate, ammo_capacity, reload_time, sec_weapon_id, sec_fire_rate, sec_ammo_cap, sec_reload),
		"crew_count": _get_crew_count(vehicle_class),
		"scope": {
			"style": "modern",
			"zoom_levels": [3.0, 6.0, 10.0],
			"field_of_view": 40.0,
			"reticle_color": "#00ff44",
			"lens_color": [0.88, 0.94, 1.0, 0.06],
			"has_range_finder": false,
			"has_stadiametric": true
		}
	}

func _set_error(msg: String) -> void:
	status_label.text = msg
	status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
