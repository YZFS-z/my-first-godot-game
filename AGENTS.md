# AGENTS.md — War Thunder Like 项目开发指引

> 本文件面向 AI 助手和开发者，记录需要读多个文件才能理解的架构约束、非显而易见的开发规则和关键操作命令。
> 完整的功能说明和操作手册见 `README.md`。

## 1. 快速运行

```bash
# 游戏客户端（Godot 4.6）
godot --path .                           # 编辑器
godot --path . --headless --script tests/check_xxx.gd   # 运行单个测试

# 公网服务器（Python 3.10+，纯标准库）
cd server && python main.py              # 交互式配置端口和邮箱
# Windows: 双击 server/start_server.bat
```

- 入口场景：`scenes/main_menu.tscn`（`project.godot` → `run/main_scene`）
- 渲染器：**Mobile**（`project.godot` → `rendering_method="mobile"`），非 Forward+。新增 shader/材质需确认 Mobile 兼容。
- Godot 版本：4.6（`config/features=PackedStringArray("4.6", "Forward Plus")` 中的 Forward Plus 是特性标记，实际渲染器为 mobile）

## 2. 全局单例（Autoload）

在 `project.godot` 的 `[autoload]` 段注册，全局可直接按类名访问：

| 单例 | 脚本 | 职责 |
|---|---|---|
| `DataLoader` | `scripts/core/data_loader.gd` | JSON 数据加载/热重载（载具/武器/地图/关卡） |
| `NetworkManager` | `scripts/network/network_manager.gd` | 网络门面（见第 4 节） |
| `GameManager` | `scripts/core/game_manager.gd` | 游戏状态机、载具生成、关卡配置、联机内容校验 |
| `EffectManager` | `scripts/effects/effect_manager.gd` | 特效实例化与生命周期 |
| `SettingsManager` | `scripts/core/settings_manager.gd` | 设置持久化（窗口/语言/声音/画质/按键） |

## 3. 场景与组件架构

### 主战斗场景（`scenes/main.tscn`）

`main.gd` 是**轻量协调器**（~219 行），不包含具体逻辑。战斗功能拆为子节点组件：

```
Main (Node3D, scripts/core/main.gd)
├── TerrainBuilder   (scripts/core/battle/terrain_builder.gd)   地形/边界/障碍物
├── FoliageManager   (scripts/core/battle/foliage_manager.gd)   草丛/视距剔除
├── VehicleSpawner   (scripts/core/battle/vehicle_spawner.gd)   载具/AI 生成
├── BattleNetwork    (scripts/core/battle/battle_network.gd)    联机协调（LAN+公网）
└── BattleUI         (scripts/core/battle/battle_ui.gd)         暂停/输入/返回键
```

组件通过 `get_parent()` 访问 Main 的共享状态（`player_tank`、`remote_tanks`、`map_config`、`is_public_mode`、`is_ai_host`）。

### 载具体系（组件化）

```
vehicle.gd (基类, CharacterBody3D) ── 物理/移动/炮塔/自由视角协调
├── tank.gd        第三人称异步视角 + 炮镜同步
├── helicopter.gd  战雷式鼠标引导 + W/S 俯仰 + A/D 滚转 + Q/E 偏航 + 总距/悬停
└── airplane.gd    速度矢量引导 + W/S 俯仰 + A/D 偏航辅助 + bank-to-turn + 油门
    └── components/
        ├── vehicle_initializer.gd    数据初始化（从 JSON）；模型导入映射委托给 ModelMapper
        ├── vehicle_weapon_system.gd  武器/弹药/开火
        ├── vehicle_damage_handler.gd 伤害转发到 DamageSystem
        ├── vehicle_repair_system.gd  维修（R 键）
        ├── vehicle_skill_system.gd   火炮支援(G)/烟幕(H)
        └── vehicle_network_sync.gd   apply_network_state() 等
```

**3D 模型导入映射集中在 `scripts/vehicles/model_mapper.gd`（ModelMapper，RefCounted）**：
`vehicle_initializer.gd::load_model_from_data()` 只做加载入口 + 调 `ModelMapper.load_and_map(vehicle, model_config)`。Mapper 把映射拆成 8 个清晰阶段（`load_and_map` 依次执行）：
1. **加载场景**（glb/gltf 用 GLTFDocument 运行时加载；tscn/scn 用 `load()`）
2. **基础变换**（scale 缩放 + offset 整体平移，offset 是叠加 `+=`）
3. **隐藏内置模型**（骨架 Hull/Track/TurretMesh/GunMesh 占位）
4. **材质修复**（glb 默认双面 → 强制 `CULL_BACK`）
5. **部件识别**（`_identify_parts`：Turret/Turret1 炮塔、Gun/gun 炮管，返回 `{turret, gun}`）
6. **前方对齐**（`_align_model_yaw`：按 Gun 相对 Turret 方向绕 Y 旋转到 -Z，`yaw_offset` 可覆盖）
7. **炮塔/炮管映射**（`_map_turret_gun`：pivot 定位、muzzle 识别、reparent 挂载、自动炮管识别）
8. **碰撞盒覆盖**（`_map_collision`：collision_size / collision_offset）

**所有配置字段向后兼容**（scale/offset/yaw_offset/turret_pivot/gun_pivot/muzzle_offset/scope_camera_z/barrel_length/collision_size/collision_offset），已有 JSON 无需改动。新增/修改导入逻辑优先在 Mapper 中做，不要往 vehicle_initializer 加逻辑。源码匹配测试 `check_glb_turret_gun_import.gd` 读的是 **model_mapper.gd**（不是 vehicle_initializer.gd）。

载具基类通过 `preload` 引用 `DamageSystem` 和 `Module`，模块化伤害系统挂载在载具节点下。

## 4. 网络架构（重要）

`NetworkManager` 已拆分为**门面 + 两个子系统**，修改网络逻辑时注意：

```
NetworkManager (Autoload, scripts/network/network_manager.gd)  ← 门面
├── 所有信号定义（53 个）、公共状态、@rpc 方法（14 个）
├── 74 个薄转发方法
└── 子节点（_ready 中动态创建）
    ├── LanNetwork     (scripts/network/lan_network.gd)      局域网全部逻辑
    └── PublicNetwork  (scripts/network/public_network.gd)   公网全部逻辑
```

### 关键约束

- **`@rpc` 方法必须在 `NetworkManager` 节点上**：Godot 多人 RPC 按节点路径（`/root/NetworkManager`）路由。子系统中实现为 `on_rpc_xxx()`，门面的 `@rpc func rpc_xxx()` 转发调用。**不要把 `@rpc` 装饰器移到子节点。**
- **子系统通过 `nm` 引用访问门面**：`lan_network.gd` 和 `public_network.gd` 都有 `var nm: Node`，在门面 `_ready()` 中设置为 `self`。发射信号用 `nm.signal_name.emit(...)`，读写公共状态用 `nm.is_server` 等。
- **`_process` 由节点树自动调度**：门面的 `_process` 为空，子节点各自的 `_process` 由 Godot 自动调用，无需手动转发。

### 两种联机模式

| 模式 | 技术 | 同步频率 | 发现/连接 |
|---|---|---|---|
| 局域网 | ENet（UDP），房主即服务器 | 30Hz 服务器权威 | UDP 广播 7778，游戏端口 7777 |
| 公网 | Python 服务器：TCP 大厅 + UDP 战斗（共用端口） | 输入 30Hz / 状态 15Hz | 默认 `game.thefeishu.top:8765` |

公网 UDP 使用自定义可靠协议（FLAG: 0=不可靠, 1=可靠+ACK, 2=ACK），实现在 `public_network.gd` 的 `_game_send_reliable` / `_game_poll` / `_game_retransmit_check`。

## 5. 数据驱动设计

所有游戏内容为 `data/` 下的 JSON，新增内容无需改代码：

```
data/
├── vehicles/   载具配置（id/name/type/physics/armor/modules/weapons）
├── weapons/    武器+弹药配置（gun_*.json / missile_*.json / mg_*.json）
├── maps/       地图（size/spawn_points/obstacles/terrain/ground_color）
└── levels/     关卡（双方载具布置）
```

- `source: "builtin"` 标记内置内容；自定义内容放在 `user://data/`，联机时需所有玩家勾选"允许自定义内容"。
- `DataLoader.reload()` 支持热重载，弹药编辑器保存后自动调用。
- 载具 JSON 的 `model` 字段支持 `scene_path`（内置 .tscn）或 glb 运行时加载（`vehicle_importer.gd` 自动识别 Turret/Gun 节点）。

## 6. 物理层

在 `project.godot` 的 `[layer_names]` 定义，**不要随意更改层编号**：

| 层 | 名称 | 用途 |
|---|---|---|
| 1 | world | 地面、地形、静态障碍物 |
| 2 | vehicle | 载具主体碰撞 |
| 3 | projectile | 弹丸碰撞 |
| 4 | module | 载具子模块（Area3D 精确命中检测） |

载具为 `CharacterBody3D`，配置 `floor_snap_length=2.0`、`floor_max_angle=1.0472`（60°）、`safe_margin=0.04`。

## 7. 地形系统（非显而易见的坑）

- **碰撞体用 `ConcavePolygonShape3D`，不用 `HeightMapShape3D`**：Godot 4 的 HeightMapShape3D 忽略 `CollisionShape3D.position` 偏移，导致碰撞体与可视网格偏移半格，载具出现 0.5m 缝隙或陷入地底。
- 地形顶点直接使用世界坐标，与可视网格完全一致；`backface_collision=true` 确保射线双向命中。
- `get_terrain_height()` 使用三角形重心插值（与碰撞网格相同拆分方式），**不是双线性插值**，消除非平面区域偏差。
- 载具贴地用 **5 节点 RayCast3D 多射线对齐**（碰撞盒四角+中心），旋转修正先于 Y 修正，避免碰撞盒穿地后 `move_and_slide` 把整车推高。
- 所有场景物体（出生点/障碍物/草丛）的 Y 坐标通过射线检测获取真实地表高度，排除空气边界碰撞体。
- **地形起伏生成约定**（`tools/_gen_terrain.py` 可复用调参）：高度图用正弦叠加（`heights` 数组，`grid_size=64` 即 65×65=4225 个值），但必须控制坡度——
  - **最大坡度建议 <25°**（载具贴地 RayCast 在陡坡易异常），网格 cell 越小（europe 7.8m）频率要越低：europe 主波长 ≥250m / 振幅 ≤4m；desert cell 31m 可到波长 240m / 振幅 7m。
  - **避免高频小波纹**（波长 <50m 的振幅会让 cell 间高差过大→陡坡，M1A2 贴地测试曾出现 34° 陡坡）。
  - **平坦区用圆形衰减** `h *= max(0,1-d/r)^2`（半径 r 内平滑归 0），且要覆盖建筑区全范围（x/z 双向），不要只压单方向导致建筑区横向仍起伏。
  - 验证：`godot --headless --script` 扫描「碰撞体命中 vs 插值高度」一致性（应 0 异常）+ 坡度（无 >24° 格）+ M1A2 贴地测试（车 y 与地面差 <0.8m）。

## 8. 测试

`tests/` 目录含 56 个 `check_*.gd` 脚本，为**手动回归测试**（非 CI 自动化）：

```bash
# 在 Godot 编辑器中 Attach 到场景节点运行，或命令行：
godot --path . --headless --script tests/check_lan_linkages.gd
```

测试覆盖：飞行器飞控（phugoid 阻尼、直升机旋翼/悬停/垂直阻尼、键盘 W/S 俯仰 + A/D 滚转 + Q/E 偏航）、移动端 UI、网络链路（`check_lan_linkages.gd` 做静态代码校验）、地形碰撞对齐、glb 模型导入、炮镜网格隐藏等。

- `check_lan_linkages.gd` 读取源文件做字符串匹配，修改网络代码后需同步更新其断言（已适配 `lan_network.gd` 拆分）。
- 部分测试（如 `check_air_net_report.gd`）继承 `SceneTree`，可独立运行模拟物理帧。

## 9. 导出

`export_presets.cfg` 预置两套配置：

| 平台 | 输出路径 | 架构 | 备注 |
|---|---|---|---|
| Windows Desktop | `../out/WarTank.exe` | x86_64 | S3TC/BPTC 纹理 |
| Android | `../out/WarTank.apk` | arm64-v8a | ETC2/ASTC，包名 `top.thefeishu.wartank` |

版本号在 `export_presets.cfg` 中维护（当前 `1.26.8.8`）。Android 已配置 INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE 权限，横屏沉浸式。

## 10. 开发约定

- **GDScript 缩进用 Tab**（项目现有风格），注释使用中文。
- **信号优先于直接调用**：模块间通信通过 signal 解耦，载具基类定义了 `vehicle_destroyed` / `health_changed` / `weapon_changed` 等信号。
- **新增网络方法**：在门面加转发方法 + 在对应子系统加实现；若是 RPC，门面加 `@rpc` 桩、子系统加 `on_rpc_xxx()`。
- **新增载具类型**：继承 `vehicle.gd`，实现 `_physics_process` 飞控逻辑，在 `data/vehicles/` 加 JSON，`vehicle_initializer.gd` 会自动按 `type` 字段初始化。
- **多发射点（机翼双炮口等）**：在载具 JSON 的 `model.muzzles` 配坐标数组（载具局部坐标，单位米），`vehicle.gd` 的 `_setup_extra_muzzles()` 会创建发射节点，`fire()` 开火时每枪口各发一发弹丸（弹药按发射点数消耗）。**配置了 `muzzles` 时取代单个 `muzzle_node`**；联机仅上报第一发射点代表位置，远端用 `muzzle_node` 播单点特效。
- **螺旋桨/旋翼旋转轴**：`airplane.gd` 默认绕局部 Z（机头）转（兼容内置简化杆状螺旋桨）；导入模型若桨盘厚度轴在其他方向（如喷火 glb 节点带 180° 旋转、厚度在局部 Y），在 `physics.propeller_axis` 配 `"x"/"y"/"z"/"-x/-y/-z"`，负号反方向。
- **glb 坦克模型的 Turret/Gun 识别**：`vehicle_initializer.gd` 按名字识别 `Turret` 和 `Gun`（**大小写兼容 `Gun`/`gun`**）节点，将其网格 reparent 到 `vehicle.tscn` 骨架的 `Turret`/`Turret/Gun` 旋转节点，保留全局位姿。若 glb 无 Gun 节点，会按"细长网格"自动识别炮管。
- **glb 旋转中心在 y=0 的坑**：很多模型把 Turret/gun 节点（旋转中心）放在原点 y=0，但炮塔/炮管 mesh 上移（如 M1A2 在 y 1.3~3.0）。此时挂在 gun_node 下的 `muzzle_node` 和 `scope_camera` 会落到 y=0（车底），导致**炮弹从车底射出、开镜被车体遮挡**。必须在 model 配置 `"gun_pivot": [0, <炮管高度>, 0]`（相对 turret 的耳轴高度），muzzle/炮镜自动跟随。
- **`model.yaw_offset`（弧度）**：模型前方默认对齐游戏 -Z；`_get_model_yaw_align_angle` 用 Gun 相对 Turret 偏移自动判断，gun 与 turret 同原点时无法判断（返回 0）。glTF 规范导出（炮管朝 +Z）的模型需手动配 `"yaw_offset": 3.14159`（**弧度，不是度**，`rotate_y` 直接使用）。
- **`model.collision_size` / `collision_offset`**：`vehicle.tscn` 骨架碰撞盒较小（3.6×1.2×6），真实尺寸 glb 车体更长/更高时需覆盖。`collision_size=[宽,高,长]`、`collision_offset=[x,y,z]`（盒中心，载具局部坐标，省略时自动取 `[0, 高/2, 0]`）。
- **`model.offset`（视觉贴地）**：glb 车底（履带最低点）不在载具原点 y=0 时坦克会"视觉离地/悬空"（碰撞盒贴地、视觉履带离地 → 炮弹能从视觉空隙命中）。用 `offset: [x,y,z]` 整体平移 ImportedModel 使履带贴地，**offset 是叠加**（`position += offset`，非覆盖，避免破坏 yaw 对齐补偿）。炮塔/炮管 pivot 自动跟随（reparent 保留全局位姿），但 **JSON 里 `modules` 的 position 需手动同步减同一 y**（模块在骨架 DamageSystem 下，不随 offset）。测量：`MeshInstance3D.global_transform * get_aabb()`（**用 `global_transform * get_aabb()`，无 `get_transformed_aabb`**），只统计 `visible` 网格（骨架占位网格已隐藏）。KV-1 曾离地 0.256m（offset -0.256）、T-34 0.039m（offset -0.039）。
- **`android/build/` 是 Gradle 构建产物**，不要手动编辑，由 Godot 导出时生成。
- **glb 直升机（AH-64）模型约定**（`heli_ah64.json` + `assets/models/ah64_helicopter.glb`）：
  - glb 各部件节点（Fuselage/MainRotor/Turret1 等）**都在模型原点 (0,0,0)**，mesh 顶点自带模型坐标偏移（模型未居中、偏大）。导入需 `model.scale=0.4` 缩放 + `model.offset=[-8.93,0,8.20]` 把机身 x/z 居中（**offset.x 取 -0.4×机身中心 x≈-8.93 使机身 x=0 居中**，曾配 -8.18 使机身偏右 0.75m）、底 y=0 贴地（起落架底）。缩放后整机 ≈16.3×4.6×20.6m，接近真实 AH-64。
  - **旋翼旋转位置不对的根因**：`MainRotorPivot` 节点在原点、主旋翼 mesh 顶点在模型坐标别处，直接 `rotate_y` 会绕原点转错位。配置 `model.main_rotor_pivot=[主轴中心·模型原始坐标]`，`helicopter.gd _setup_rotor_nodes()` 把 pivot 平移到轴心、隐藏 pivot 自身 mesh（主轴/桨毂非对称不可随转），并把桨盘（MainRotor）mesh 中心对齐到 pivot：`rotor.position = -get_aabb().get_center() + main_rotor_offset`。**`main_rotor_offset` 是桨盘 mesh 中心相对主轴中心的偏移（模型坐标），必须保持 x/z=0**（桨盘在主轴轴线上）；若 z≠0 桨盘会绕主轴**公转**（绕 pivot 画圆），出现"旋翼转动轴不对"（曾误配 z=5.60，改回 0 后桨盘绕自身中心自转）。**offset.y 应为主轴半高**（让桨盘落在旋翼轴顶，AH-64 桨盘应高出机身顶 ~1.5m；曾配 y=1.12 使桨盘贴近机身顶 0.29m、旋翼轴几乎不可见，看起来"轴不对"）。**代码默认取主轴 AABB 半高（隐藏 mesh 前记录），JSON 可覆盖**。**AABB 必须在移动 pivot 之前读取**——移动后 mesh 顶点叠加 pivot 坐标导致 AABB 翻倍错位（"旋翼绕机体公转"bug 的根因之一）。**隐藏主轴 mesh 时必须遍历 pivot 的所有 MeshInstance3D 子节点**（`find_children`），仅设 `mesh=null` 只处理 pivot 自身为 MeshInstance3D 的情况；glb 导入若 pivot 为 Node3D 容器（子节点含 mast mesh），不遍历则 mast 仍可见且绕 pivot 大半径公转。**`main_rotor_pivot` 应取机体中心位置**（桨盘居中，视觉上"桨盘绕机体中心旋转"；曾配 z=-30.54 使桨盘偏机头 2.1m，用户反馈"旋翼塔、桨盘绕机体中心旋转"）。AH-64 主轴中心 [22.31, 8.23, -24.94]（模型，z 取**桨盘中心 z**→ 载具 z-1.78 机体中心，与机身中心 z-1.90 差 0.12m；曾配 z=-25.25 桨盘略偏、z=-30.54 偏机头 2.1m）、桨盘 offset [0,4.12,0]→缩放后桨盘中心 y≈5.44（高出机身顶 ~1.5m）。
  - **新模型结构（2026-08-28 用户重新导出）**：各部件**节点 position 携带部件布局**（Fuselage (0.14,5.39,-1.69)、LandingGear (0.07,1.59,-1.45)、MainRotor (0.07,9.62,0)、Turret1 (0.11,1.73,-7.52)、Turret2 (0.18,3.58,-0.58)），mesh 已居中（`get_aabb()` 中心≈节点附近但**≠节点位置**，mesh 相对节点有偏移）。**`model.offset` 改为 `[0,0,0]`**（模型已居中贴地：LandingGear mesh 底 y=0）。`scale=0.4` 不变。**`main_rotor_pivot` 自动（合体）必须用 `node.position + get_aabb().get_center()`**——`get_aabb()` 是节点局部 AABB（mesh 相对节点偏移），仅取 mesh 中心会漏掉节点位置（漏了 MainRotor 节点 y9.62，pivot 错位 9.6m；旧模型节点在原点所以没暴露）。**turret_pivot 自动用 `to_global(get_aabb().get_center())`（含节点位置）正确**。modules 位置随模型更新：main_rotor=[0,3.4,0]、tail_rotor=[0.3,3.2,9.5]（尾旋翼在 z+9.5）。gun_pivot=[0,0.2,0]/muzzle_offset=[0,0.1,-0.85] 不变（Turret1 内部结构未变）。视觉尺寸：机身 ≈3.9×3.0×10.2m、桨盘盘面在机顶上方 ~1.5m。
  - **合体主旋翼"按模型位置"简化（2026-08-28 用户要求不自动找位置）**：`_setup_rotor_nodes()` 合体分支**不再新建 MainRotorRuntimePivot 容器、不移动 mesh、不隐藏**——因为合体 mesh 相对节点 x/z≈0（mesh 在节点轴线上），`main_rotor_node` 直接=MainRotor 节点，`_physics_process` 绕节点局部 Y 旋转即自转（公转仅 0.008m），mesh 保持模型原始位置。旧容器逻辑已删除（曾用于 mesh 中心对齐旋转中心）。
  - **尾桨旋转（`tail_rotor_static=false`，2026-08-28 起 AH-64 尾桨旋转）**：TailRotorPivot 的 mesh 轴+盘一体，mesh 相对节点有 x/y 偏移（AH-64: (0.61,-0.02)），直接绕节点 Z 转会公转。`helicopter.gd _setup_rotor_nodes()` 绑定 TailRotorPivot 后，若 mesh 中心相对节点 x/y 偏移 >0.05 则**新建 `TailRotorRuntimePivot` 容器、`container.position = tr.position`（必须继承 TailRotorPivot 原位置！）**，mesh reparent 进容器并 `position=-get_aabb().get_center()`（mesh 中心对齐容器原点）→ `_physics_process` 绕容器 Z 转即自转（公转 0.0000）。**坑：容器若不设 position（默认 0）会落在 ImportedModel 原点（机体底部中心），尾桨在机体底部旋转**——`old_parent.remove_child(tr)` 会丢失 tr 的 position，必须在移除前 `var old_pos := tr.position` 并赋给容器。验证尾桨 mesh 全局中心 ≈ (-0.72, 3.68, 9.50)（机尾上方）。`tail_rotor_static=true` 仍可强制静态（旧逻辑）。**尾桨旋转轴：绕局部 X 轴（`rotate_x(delta * tail_rotor_speed)`，正方向=从右侧看逆时针/从左侧看顺时针，符合 AH-64 "Top blade aft"）**——诊断依据：尾桨 mesh AABB size x=2.7/y=7.1/z=7.3，盘面在 **Y-Z 平面、法线沿 X** → 必须绕 X 自转；曾误用 `rotate_z` 导致盘面绕错轴翻转（+X 法线端点绕 Z 转 90° 位移 0.884m）。验证：绕 X 转 90° 法线端点位移 0.000（自转正确）。**通用判定法：读 mesh AABB 最小尺寸轴即盘面法线，尾桨绕该轴旋转**（AH-64 模型导出的盘面法线为 X，与真实绕机身纵向不同，以模型为准）。**`model.tail_rotor_offset`（ImportedModel 局部坐标/模型米，可整体右移尾桨）**：AH-64 配 `[0.375,0,0]`（×scale 0.4 = 全局右移 0.15m，mesh X -0.72→-0.57）；容器 position = TailRotorPivot 原位置 + offset。
  - **射速由 `reload_time` 控制（不是 `fire_rate`）**：`vehicle.gd fire()` 每次开火后 `reload_timer = reload_time`、`is_reloading=true`（fire_rate 字段在代码中未被使用，仅作配置记录）。**AH-64 主武器（M230 30mm 链炮）真实射速 625 发/分** → `reload_time=0.1`（=600 发/分，接近真实）。**副武器（地狱火导弹）真实无"装填"概念（挂架导弹发射即脱离，空中无法装填）** → 不再配 20 秒装填，`reload_time=0.6`（逐发连射间隔 1.7 发/秒，左右交替）；弹药用完即止（reload 不恢复弹药，符合"空中装不了"）。
  - **物理高度悬停（2026-08-28，总距级联控制，不是直接设垂直速度）**：原悬停直接改 `velocity.y`（一阶速度控制，不物理）；现改为**用总距（collective）控制升力的真实二阶悬停**。`helicopter.gd _update_flight` 在升力计算前：**动态配平 `hover_balance = GRAVITY / (max_lift_force*0.003*power_factor*rotor_eff)`**（平衡总距随引擎/旋翼效率自适应，半损悬停自动加大总距维持）+ **级联**：外环 `want_vy = clamp(高度误差*hover_height_gain, ±hover_speed_limit)`（高度→目标垂直速度）、内环 `ctrl = hover_balance + (want_vy-velocity.y)*hover_speed_gain`（速度误差→总距，同时就是悬停阻尼），总距经 `move_toward(…, hover_collective_rate*delta)` 作动器限速平滑。悬停时**垂直不做 `velocity.lerp(velocity*0.98,delta*2)` 阻尼**（内环即阻尼，避免额外衰减削弱升力），仅保留水平衰减；悬停分支只留失速退出+水平制动。**参数全 JSON physics 可配**（`hover_height_gain=1.2` / `hover_speed_limit=5.0` / `hover_speed_gain=0.06` / `hover_collective_rate=3.0`，`heli_ah64.json` 已配）。**调参坑**：纯 PD 直接控总距在二阶系统上增益失配会过冲振荡（曾爬升停在 9.23/8.85）；必须"动态配平（算准平衡）+ 级联（速度环内置阻尼）"才稳。**回归测试 `tests/check_helicopter_hover.gd`**（SceneTree 驱动真实 `_physics_process`）：基础悬停/低位爬升/外力扰动三场景末 1 秒偏差 <0.5m 且帧间振幅 <0.05。
  - **Turret1/Turret2 命名**：`vehicle_initializer.gd` 在无 `Turret` 时回退识别 `Turret1` 作为主炮塔。**机头主炮塔 Turret1 是"炮塔+炮管"整体网格，配置了 `gun_pivot` 时会 reparent 到 `gun_node`（跟随 yaw+pitch）**——否则只跟随 turret_node 的 yaw 不俯仰，瞄准时炮塔不指向目标（"Turret1 位置不对"）。**reparent 后必须把 Turret1 整体平移使 mesh 全局中心对齐 gun_node 耳轴**——否则节点 origin 在模型 offset 处（远离 gun_node），gun 俯仰时 origin 绕 gun_node 大半径公转，炮塔"浮空/朝下"。**取 mesh 全局中心用 `to_global(get_aabb().get_center())`**（mesh 局部 AABB 中心经节点全局变换得到真实世界坐标）；**不要用 `(global_transform * get_aabb()).get_center()`**——后者对 AABB 做世界变换后取包围盒中心，含 scale/rotation 时给出的是轴对齐包围盒中心而非 mesh 实际中心，偏差导致炮塔偏移。Turret2（机翼挂架）不识别为炮塔，仅用 `model.muzzles` 作副武器发射点。
  - **机翼挂架副武器视觉（Turret2）**：glb 的 Turret2 只有挂架 mesh（无导弹），配置 `model.missile_visual={count,length,radius}` 后 `helicopter.gd _setup_missile_visuals()` 在每个 muzzles 发射点下方生成 count 枚地狱火导弹（CylinderMesh 圆柱体，长轴转 Z 朝前，挂在载具节点下）。
  - **主/副武器不同发射点**：weapon slot 加 `"muzzle_mode"`——`"node"` 用 `muzzle_node`（机头炮塔主武器）、`"multi"` 用 `model.muzzles` 多发射点（机翼副武器齐射，每次齐射扣 N 发）、`"alternate"` 用 `model.muzzles` 但**左右交替**（`vehicle.gd alternate_muzzle_index` 轮换，每次只用一个发射点、弹药扣 1 发；AH-64 副武器现用此模式）。`vehicle.gd _get_muzzle_list()` 按当前武器 slot 读此字段；未配置时保持旧行为（muzzles 优先）。
  - **`model.muzzles_from_model`（按模型绑定副武器发射点）**：配置 `true` 时 `helicopter.gd _setup_muzzles_from_turret2()`（`setup_from_data` 中、`_setup_missile_visuals` 前调用）把副武器发射点**直接创建为模型 Turret2（机翼挂架）节点的子节点**（`MuzzleFromModel0/1`，位置取挂架 AABB 左右端 x + 中轴 y/z，Turret2 局部坐标），并替换 `extra_muzzle_nodes`。发射点**跟随模型变换**（Turret2 动发射点跟着动），改模型后自动适配。同时把载具局部坐标写回 `model.muzzles`。`_setup_missile_visuals()` 把地狱火导弹视觉挂在发射点节点下（跟随模型）——**但发射点在 ImportedModel 下会继承 scale（AH-64 为 0.4），导弹的几何尺寸/偏移必须 ÷scale 反补偿**（`body.height = mlen/scale`、`miss.position.y = -0.2/scale`），否则导弹缩小 0.4 倍、下移量变短。`muzzles` 字段保留作 fallback（Turret2 找不到时用）。
  - **`turret_pivot` / `main_rotor_pivot` 自动与显式**：
    - `model_mapper.gd::_map_turret_gun` 未配置 `turret_pivot` 时，若 Turret 是 **MeshInstance3D 且带 mesh**，自动用 `to_global(get_aabb().get_center())`（mesh AABB 中心）经 `vehicle.to_local()` 作炮塔旋转中心——AH-64 等部件节点在原点、mesh 在别处的模型必须走此分支（`model_turret.global_position` 是节点位置=原点，错误）。坦克有 Gun 子节点的模型不受影响（Turret 节点位置即炮塔中心）。
    - `helicopter.gd::_setup_rotor_nodes` 未配置 `main_rotor_pivot` 且**合体结构**（MainRotor 是 MeshInstance3D）时，自动用 `get_aabb().get_center()`（合体 mesh 中心=旋转中心）。
    - **AH-64 现用"按模型位置"显式模式（2026-08-28 用户要求不自动找位置）**：`turret_pivot=[0.012,0.8,-3.2]`（=0.4×Turret1 mesh 全局中心，载具局部）、`gun_pivot=[0,0,0]`（gun 放 turret mesh 中心=模型位置）、`muzzle_offset=[0,0,-0.95]`（=Turret1 mesh 前端相对 gun，炮口在炮管前端，与前端差 0.003m）。**`gun_pivot=0` 时 Turret1 reparent 到 gun_node 后 mesh 中心=gun_node 原点，mapper 的"对齐耳轴"delta 自动≈0，不移动 mesh**（真正按模型位置）。muzzle 高度=Turret1 mesh 中心（炮口 y1.3 全局，比旧 gun_pivot 0.2 时低 0.3m）。
  - **直升机移动端信号连接（曾缺失）**：`helicopter.gd::_connect_mobile_controls()`（`_ready` + `setup_from_data` 后各调一次，幂等）连接 `weapon_selected→switch_weapon`、`ammo_selected→select_ammo`、`repair_pressed→start_repair`、`skill_artillery_pressed/_on_mobile_artillery`、`skill_smoke_pressed/_on_mobile_smoke`、`free_look_pressed→set_free_look(true)`、`free_look_released→set_free_look(false)`，并 `set_weapon_count(get_weapon_count())`。**缺失会导致移动端副武器切换按钮无效**（`weapon_selected` 无监听）。直升机的开火不用 `fire_pressed`（在 `_physics_process` 轮询 `mobile.fire_held` 按住连续射击），故不连接 fire_pressed 避免重复。
  - 无 Gun 节点且配置了 `model.gun_pivot` 的模型，`vehicle_initializer` 会**跳过自动炮管识别**（用配置定位 gun/muzzle），避免把 Turret1 整网格误判为炮管；内层 `gun_pivot` 计算已加 `model_gun` 非空判断，避免 Nil 访问。
  - **自定义载具 `heli_ah-_helicopter`（"Ah 64 Helicopter"）已删除（2026-08-28 用户要求只留内置）**：原位于 `user://data/vehicles/heli_ah-_helicopter.json` + `user://assets/models/heli_ah-_helicopter.glb`，连同 `.bak` 一并删除，现在只保留内置 `heli_ah64`（"AH-64 阿帕奇"）。之前该自定义载具曾位置错乱（8/26 旧模型 + scale 1.0 + 无映射），已通过复制最新模型 + 补齐映射配置临时修复后按用户要求删除。
- **glb 固定翼（A-10）模型约定**（`plane_a10.json` + `assets/models/plane_a10.glb`，2026-08-28 替换内置）：
  - glb 8 个部件（Fuselage/gun1/gun2/MainWing/Propeller/TailWing/VerticalStab/LandingGear）全在根级、**各带 rot=[0,0.7071,0,0.7071]（90° Y 旋转，glTF 规范导出，炮朝 +Z）**。gun1=机头机炮（识别为 Gun）、gun2=机翼导弹挂架（scale=(0.617,0.617,0.92)）、Propeller=喷气式引擎（**不可旋转**）。
  - **`yaw_offset=-1.5708`（-90°）是唯一正确朝向**：机头（gun1）在模型 -X 端，部件 90° 后转 +Z。`rotate_y(-90°)` 使机头 -X→-Z（游戏前方）、机长 X→Z。**坑：`+90°` 机头会朝 +Z（反）**；`180°` 尺寸虽不互换但机长沿 X（飞机横着）——因为部件自带 90° 旋转 + ImportedModel 旋转叠加，90° 奇数倍才互换 X/Z（机长转 Z），且必须 -90° 让机头朝 -Z。**调试方法：`rotate_y` 后看 muzzle_node 是否在 -Z（机头前）**。
  - **`model.offset=[0.91,-0.47,-0.37]`**：yaw -90° 后 ImportedModel position=(-0.70,1.77,4.49)（offset 前）→ 需平移使模型底贴地、x/z 居中。最终 position=(0.30,-0.47,0.84)。**offset.y 为负**（模型最低点在 ImportedModel 局部 y≈+0.27 而非负值——glb 部件节点 y 全为正、最低 LandingGear mesh 底 0.21，不是轴对齐盒 min -1.74，**以 setup 后实测 AABB 反推 offset**）。最终整体 AABB：尺寸 X=17.83（翼展）/Y=4.54/Z=16.31（机长），min y≈0，中心 x/z=0。
  - **主武器（机炮）必须配 `"muzzle_mode": "node"`**：gun1 reparent 到 `Turret/Gun`，mapper auto-detect muzzle 到 gun1 mesh 前端（-Z 机头前 z≈-8.29，机炮真实位于机头下方，muzzle y≈1.0）。**不配则 `_get_muzzle_list` 回退 muzzles 优先 → 机炮从机翼挂架发射（错）**。
  - **副武器（AGM-65）`muzzle_mode: "multi"`（左右齐射）**：`model.muzzles=[[-3.95,1.16,-0.28],[3.95,1.16,-0.28]]`（gun2 挂架 mesh 左右端实测，载具局部，y=挂架中心 1.16）。
  - **`physics.propeller_disabled=true`**：`airplane.gd::_setup_propeller_node` 检测到后 `propeller_node=null` 直接返回，Propeller（引擎）节点不随螺旋桨逻辑旋转。**配置了 propeller_disabled 时 reg 不检查 propeller_node**。
  - 尺寸/武器数据：`scale=1.02`、`collision_size=[18,3.37,16.3]`；主武器 gun_30mm_gau8 `reload_time=0.015`（≈3900 发/分，真实 GAU-8 3900 发/分）、副武器 missile_agm65 `reload_time=1.0` ammo=6。回归：`tests/check_air_net_report.gd` 会加载 plane_a10.json 的 glb 做 setup_from_data。
- **键盘飞控方案（2026-09-03，直升机 + 固定翼统一）**：
  - **直升机**（`helicopter.gd`）：WASD **只改视角**（target_pitch/target_yaw），机体由引导系统自然跟随。W/S 以 `keyboard_pitch_rate`（60°/s）修改 `target_pitch`（W=低头俯冲+前飞，S=抬头爬升+后飞）；A/D + Q/E 合并以 `keyboard_yaw_rate`（45°/s）修改 `target_yaw`（偏航），**bank 由协调压坡逻辑自动计算**（不再直接设 bank）。前进推力来自机体俯仰后升力矢量自然前倾（移除了 `cyclic_angle` 直通推力）。鼠标与键盘叠加修改 `target_pitch`/`target_yaw`。`auto_center`（延迟 0.5s）无 W/S 时 pitch→0 改平，无 A/D+Q/E 时 yaw→当前航向直飞。键盘输入重置 `_mouse_idle_time` 使释放后才开始回正计时。参数全 JSON physics 可配（`keyboard_pitch_rate` / `keyboard_yaw_rate` / `auto_center_enabled` / `auto_center_delay` / `auto_center_speed`）。
  - **固定翼**（`airplane.gd`）：W/S 同样以 `keyboard_pitch_rate` 修改 `target_pitch`，A/D 为偏航辅助（临时偏置 target_dir → 协调压坡），Q/E 在飞机中不处理。W/S 还有**直接垂直加速度注入**（`keyboard_pitch_accel=12.0 m/s²`）和**视觉俯仰偏移**（`keyboard_trim_deg=20.0`）两条直通路径，弥补引导系统间接性使玩家感知不到 W/S 响应。`phugoid_damping_gain=3.0`（相对目标垂直速度误差阻尼，非绝对 vy 阻尼）消除爬升振荡。
  - **输入映射**（`project.godot`）：`move_forward`=W(87), `move_backward`=S(83), `turn_left`=A(65), `turn_right`=D(68), `turret_left`=Q(81), `turret_right`=E(69)。`Input.get_axis("move_backward", "move_forward")`：W→+1, S→-1。`user://input.cfg`（SettingsManager 加载）可覆盖物理按键映射但不改动作名。
