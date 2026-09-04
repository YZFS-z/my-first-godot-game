# War Tank

一个类似战争雷霆的模块化伤害载具战斗游戏框架，基于 **Godot 4.6**（Mobile 渲染器，兼容移动端）开发。

支持三种载具类型（坦克 / 直升机 / 固定翼）、外部 JSON 数据驱动、敌方 AI、局域网与公网联机，并内置地图 / 关卡 / 弹药 / 载具四个可视化编辑器。

当前版本：**1.26.8.8**

## 核心特性

### 1. 模块化伤害系统
- 每个载具由独立模块组成（发动机、传动、主炮、弹药架、装甲、旋翼、乘员等）
- 模块有独立血量、装甲厚度、关键程度标记
- 多种伤害类型：动能弹（APFSDS/APCBC/APHE）、高爆弹（HE）、破片、燃烧
- 穿深计算：考虑装甲厚度和命中角度，动能弹穿深随距离衰减
- 连锁效应：弹药殉爆、模块损坏影响载具性能（发动机损坏→减速，旋翼损坏→坠毁）
- 弹丸命中按模块做精确碰撞检测（Area3D），弹道带下坠与溅射

### 2. 三种载具类型
| 类型 | 载具 | 挂载武器 |
|---|---|---|
| 坦克 | M1A2 Abrams / T-34-85 / KV-1 | 坦克炮 + 机枪 + 炮镜瞄准 |
| 直升机 | AH-64 阿帕奇 | 30mm 链炮 + 地狱火导弹，悬停 / 升降，战雷式鼠标引导（机头朝向视角中心） |
| 固定翼 | A-10 雷电 II / 喷火 Mk.IX | A-10: GAU-8 机炮 + AGM-65 小牛导弹；喷火: Hispano 20mm 机炮 + Browning 7.7mm 机枪，战雷式飞控（机头朝向视角中心）+ 油门 |

### 3. 外部数据驱动
- 载具、武器、地图、关卡全部为 `data/` 下的 JSON 文件，新增内容无需改代码
- `DataLoader`（Autoload）提供热重载：弹药编辑器等工具保存后自动调用 `reload()` 刷新数据
- 支持自定义内容：导出后可将自定义载具/地图放入 `user://data/` 目录，联机时需所有玩家勾选"允许自定义内容"

### 4. 客户端 / 服务器架构
- **局域网**：Godot ENet API，服务器权威模式（Server Authority），固定 30Hz Tick 同步，UDP 房间发现广播（默认端口 7777，发现广播 7778）
- **公网**：独立 Python 服务器（`server/`），TCP 大厅 + UDP 游戏战斗共用同一端口，提供账号、好友、组队、房间与游戏协调
- 同时支持单机 AI 对战 / 局域网联机 / 公网联机三种模式

### 5. 技能系统
- 火炮支援（G）：选定区域炮击，带冷却
- 烟幕遮蔽（H）：在目标位置生成烟幕带遮挡视野

### 6. 敌方 AI
- `tank_ai.gd` 坦克 AI 状态机：巡逻 → 发现目标 → 追击 → 攻击 →（血量低）撤退，通过设置载具的 `input_*` 变量控制
- `aircraft_ai.gd` 飞行器 AI：支持直升机与固定翼的自动飞行、索敌与攻击

### 7. 开发工具集
- **地图编辑器**：可视放置障碍物、植被、出生点，保存/加载 JSON 地图，支持导入外部 3D 模型；内置地形高度图绘制（抬升/降低/平整，可调笔刷半径与强度），地形碰撞自动生成 trimesh 精确匹配可视网格；支持地面颜色画笔绘制（256×256 ImageTexture，软边缘笔刷，可逐区域涂色而非整片改色）；从地形/颜色绘制模式切换到其他障碍物类型时自动恢复放置/选择模式，无需手动重置
- **关卡编辑器**：在地图上布置双方载具，定义型号与位置；切换地图时自动加载对应地形网格与碰撞体，放置载具时按射线检测的地表高度定位，避免在起伏地势下出生被卡；内置环境光与方向光照明，摄像机高度随地图规模自适应缩放
- **弹药编辑器**：调整武器 JSON 中的弹药参数（穿深、装药、初速等）
- **载具导入器**：导入外部 3D 模型文件（.glb/.gltf），自动复制并生成载具 JSON 配置；运行时用 `GLTFDocument` 加载 glb，自动识别 Turret/Gun 节点并 reparent 到载具骨架（`turret_node` / `gun_node`）；**自动识别旋转中心**——从 glb 中 Turret/Gun 节点的位置自动设置 `turret_node`/`gun_node` 的坐标，使炮塔旋转和炮管俯仰围绕模型设计的正确中心进行；自动从炮管网格 AABB 推算炮口位置；支持手动覆盖（JSON `model` 中 `turret_pivot` / `gun_pivot` / `muzzle_offset`）；支持 MeshInstance3D（自身即网格）与 Node3D（容器节点）两种结构；**无 Gun 节点时自动识别细长炮管网格**（AABB 长短比>3:1）reparent 到 `gun_node`，reparent 时用 `global_transform` 保留世界变换避免丢失父节点旋转/缩放，并修正炮管 local rotation 为 `(PI/2, 0, 0)` 使圆柱体 mesh Y 轴映射到 -Z（前方），修复 glb 中炮管继承 Turret 复杂旋转导致 gun_node 俯仰控制失效的问题；用 AABB 8 角点变换到 gun_node 本地坐标正确计算炮口位置和炮镜 Z 偏移

### 8. 其他
- 特效系统：爆炸（火球+烟雾+冲击波）、持续燃烧、命中火花、炮口焰、烟幕
- 炮镜瞄准镜：按载具配置渲染多种分划板样式（现代 / 二战德国 / 二战苏联 / 简易）
- 设置管理器：窗口、语言、声音、画质、按键设置持久化
- 移动端支持：虚拟摇杆 + 拖动瞄准 + 可自定义触控按钮（含退出/暂停）、系统返回键防误触退出，已配置 Android 导出
- 难度系统：简单 / 普通 / 困难 / 专家 四档 AI 难度
- 调试模式：可启用调试信息显示，桌面端可强制启用移动端控制用于测试

## 全局单例（Autoload）

| 单例名 | 脚本 | 职责 |
|---|---|---|
| `DataLoader` | `scripts/core/data_loader.gd` | 加载/热重载载具、武器、地图 JSON 数据 |
| `NetworkManager` | `scripts/network/network_manager.gd` | 局域网/公网连接管理、玩家同步、RPC、房间发现 |
| `GameManager` | `scripts/core/game_manager.gd` | 游戏状态、载具生成、关卡配置、联机内容检查 |
| `EffectManager` | `scripts/effects/effect_manager.gd` | 特效实例化与生命周期管理 |
| `SettingsManager` | `scripts/core/settings_manager.gd` | 设置项的读取、保存与持久化 |

## 物理层

| 层 | 名称 | 用途 |
|---|---|---|
| 1 | world | 地面、地形、静态障碍物 |
| 2 | vehicle | 载具主体碰撞 |
| 3 | projectile | 弹丸碰撞 |
| 4 | module | 载具子模块（用于精确命中检测） |

## 项目结构

```
war_thunder_like/
├── project.godot              # Godot 项目配置（入口: scenes/main_menu.tscn）
├── export_presets.cfg         # 导出配置（Windows / Android，版本 1.26.8.8）
├── icon.svg                   # 应用图标
├── 启动动画.png                # 启动画面
├── assets/                    # 资源
│   ├── icons/                 # UI 图标（火炮、维修、烟幕、聊天、锁定、瞄准等）
│   ├── sounds/                # 音效（开火等）
│   ├── backgrounds/           # 主菜单背景图片（可选，放入对应文件名自动加载）
│   ├── map_models/            # 地图编辑器导入的外部 3D 模型
│   ├── materials/             # 材质资源
│   ├── models/                # 3D 模型资源
│   └── textures/              # 纹理贴图
├── data/                      # 外部数据（JSON 驱动）
│   ├── vehicles/              # 载具：tank_abrams / tank_t34_85 / tank_kv1 / heli_ah64 / plane_a10 / plane_supermarine_spitfire
│   ├── weapons/               # 武器：主炮、机炮、链炮、机枪、导弹（共 11 种）
│   ├── maps/                  # 地图：map_desert(沙漠训练场) / map_europe(欧洲小镇) / map_valley(山谷要塞)
│   └── levels/                # 关卡：level_duel(双人对决) / 狭路相逢
├── scenes/                    # 场景
│   ├── main_menu.tscn         # 主菜单（多级导航 → 开始 / 编辑器）
│   ├── main.tscn              # 主战斗场景（动态生成地形与障碍物）
│   ├── lan_lobby.tscn         # 局域网房间大厅
│   ├── public_lobby.tscn      # 公网联机大厅（登录/房间/好友/组队）
│   ├── settings.tscn          # 设置界面
│   ├── vehicle.tscn           # 载具基类场景
│   ├── airplane.tscn / helicopter.tscn  # 飞行器场景
│   ├── airplane_model.tscn   # 飞行器模型
│   ├── projectile.tscn        # 弹丸
│   ├── gun_scope.tscn         # 炮镜瞄准镜
│   ├── smoke_screen.tscn      # 烟幕
│   ├── target_selector.tscn   # 技能目标选择器
│   ├── ammo_editor.tscn       # 弹药编辑器
│   ├── map_editor.tscn        # 地图编辑器
│   ├── level_editor.tscn      # 关卡编辑器
│   ├── vehicle_importer.tscn  # 载具导入器
│   └── effects/               # 特效：爆炸、燃烧烟雾、命中火花、炮口焰
├── scripts/                   # GDScript
│   ├── core/                  # 核心：data_loader / damage_system / module / game_manager / settings_manager + main（219 行轻量协调器）
│   │   └── battle/            # 战斗场景拆分组件：battle_network（联机协调）/ battle_ui（暂停·输入·返回键）/ terrain_builder（地形·边界·障碍）/ foliage_manager（草丛·视距剔除）/ vehicle_spawner（载具·AI 生成）
│   ├── vehicles/              # vehicle 基类（744 行）+ tank / helicopter / airplane
│   │   └── components/        # 载具功能拆分：damage_handler / initializer / network_sync / repair_system / skill_system / weapon_system
│   ├── weapons/               # cannon（发射/弹药/后坐力）+ projectile（弹道/穿深/溅射）
│   ├── ai/                    # tank_ai 坦克 AI + aircraft_ai 飞行器 AI
│   ├── network/               # network_manager（ENet 局域网 + 公网协议）
│   ├── effects/               # 特效管理器与各特效逻辑（爆炸/燃烧/火花/炮口焰/烟幕）
│   └── ui/                    # 主菜单、HUD、大厅、瞄准镜、移动端控制、编辑器、技能目标选择器、_target_input_helper
│       └── editors/map_editor/ # 地图编辑器拆分：核心协调器 + terrain（地形绘制）/ color（颜色绘制）/ objects（障碍物）/ io（保存加载）
├── server/                    # 公网联机服务器（Python 3.10+，纯标准库，TCP大厅+UDP游戏）
├── tests/                     # 功能测试脚本（51 项，覆盖飞行、移动端、网络、UI、glb 导入、地形碰撞对齐、炮镜网格隐藏、KV-1 内置坦克数据校验等）
└── android/                   # Android 构建产物（Gradle 工程）
```

## 载具与武器数据

所有性能数据来自 `data/` 下的 JSON，在弹药编辑器内重新加载即可生效，或重启游戏。

| 载具 | 类型 | 国家 | 武器 | 弹药 |
|---|---|---|---|---|
| M1A2 Abrams | 坦克 | 美国 | M256 120mm 滑膛炮 | APFSDS M829A3 / HEAT M830A1 / HE M1028 |
| T-34-85 | 坦克 | 苏联 | ZiS-S-53 85mm 线膛炮 | APCBC BR-365A / APHE BR-365K / HE O-365K |
| KV-1 | 坦克 | 苏联 | ZiS-5 76mm 线膛炮 + DT 7.62mm 机枪 | BR-350A APHEBC / BR-350P APCR / OF-350 HE / DT 穿甲·穿甲燃烧·曳光 |
| AH-64 阿帕奇 | 直升机 | 美国 | M230 30mm 链炮 + AGM-114 地狱火导弹 | M789 HIEDP / M799 HE / AGM-114K |
| A-10 雷电 II | 固定翼 | 美国 | GAU-8 30mm 机炮 + AGM-65 小牛导弹 | PGU-14B API / PGU-13B HEI / AGM-65D |
| 喷火 Mk.IX | 固定翼 | 英国 | Hispano Mk.II 20mm 机炮 + Browning 7.7mm 机枪 | 20mm HEFI 高爆燃烧 / 20mm API 穿甲燃烧 / 0.303 AP 穿甲 / 0.303 API 穿甲燃烧 |

> 直升机 / 固定翼均为**战雷式鼠标引导飞控**：准星固定在屏幕中心（视角中心），鼠标移动设定目标指向，机头自动向准星收敛（固定翼按速度矢量引导 + 协调压坡 bank-to-turn，带过载限幅与诱导阻力掉速；直升机同样为机头限速率收敛 + WASD 改视角（W/S 俯仰、A/D+Q/E 偏航、bank 自动协调）、滚轮总距升降，前进推力来自机体俯仰后升力矢量自然前倾）。飞控手感参数（鼠标灵敏度、引导增益、最大引导角速率、压坡角上限、键盘俯仰/偏航速率、自动回正、地面滑跑摩擦等）可在 `data/vehicles/plane_a10.json` 与 `heli_ah64.json` 的 `physics` 中调整。

> 坦克**第三人称异步视角**（类似战雷）：鼠标即时控制相机方向（`view_offset_yaw` / `camera_pitch`），不受炮塔转速限制；炮塔和火炮以各自转速限速追踪视角方向（`wrapf` 角度差 + `clamp` 限速），玩家可直观看到炮塔旋转追赶准星。相机跟随车体偏航 + 鼠标偏移（`camera_yaw = view_offset_yaw + hull_yaw`），转向时相机随机体联动。HUD 双标记：**十字准心**始终跟踪炮管在世界空间的投影位置（炮弹实际落点方向），**圆圈标记**固定在屏幕中心代表视角方向，两者偏移量即炮塔追赶差值。炮镜模式（Shift）切换为同步控制（鼠标直接驱动炮塔/火炮），圆圈隐藏、十字回归中心，退出时视角自动同步到炮塔当前指向，无跳变。

## 操作说明

| 操作 | 按键 |
|---|---|
| 前进 / 后退 | W / S |
| 转向 | A / D |
| 炮塔左 / 右转 | Q / E |
| 开火 | 鼠标左键 |
| 缩放瞄准 | 鼠标滚轮 |
| 炮镜瞄准 | Shift |
| 维修 | R |
| 飞机操控（固定翼） | 鼠标移动＝引导机头指向（准星固定屏幕中心，战雷式飞控）；W/S＝俯仰（机头上下）；A/D＝偏航辅助（协调压坡） |
| 直升机操控 | 鼠标移动＝引导机头指向（准星固定屏幕中心，战雷式飞控）；滚轮＝总距（升降）；W/S＝俯仰（机头上下，低头前飞/抬头后飞）；A/D＝偏航（左右转向，bank 自动协调）；Q/E＝偏航 |
| 高度悬停（直升机） | F |
| 收起 / 放下起落架（飞机） | 空格 |
| 切换弹药 1/2/3 | 1 / 2 / 3 |
| 切换武器 1/2 | Z / X |
| 火炮支援 | G |
| 烟幕遮蔽 | H |
| 自由视角（按住） | V |
| 聊天 | Enter |

> 所有按键均可在 **设置 → 按键设置** 中自定义；移动端提供对应触控按钮。

> 自由视角：按住 V 进入自由观察视角，此时鼠标只转动观察方向，不影响载具操控（炮塔/炮管保持不动），松开后平滑恢复。

> 高度悬停（直升机）：空中按 F 锁定当前高度并自动制动水平速度，直升机悬停于原地；垂直方向由高度控制器接管（滚轮不再调整总距），再按一次 F 退出并恢复滚轮总距手感。贴地时不生效。

> 起落架（固定翼 / 直升机）：空中按空格收起 / 放下起落架（收起后阻力减小、机轮缩进机腹）；贴地时强制放下，无法收起。固定翼地面滑跑时前轮转向跟随准星偏航方向（推油门进入滑跑/飞行段后由速度矢量引导转向；油门为 0 静止时机头保持当前朝向）。

## 快速开始

1. 用 Godot 4.6 打开 `project.godot`，直接运行（入口为主菜单）
2. 主菜单选择**单机 AI 对战**：选择地图与载具、设置双方 AI 数量与难度即可开战
3. **局域网联机**：主机"创建房间"（默认端口 7777，UDP 7778 广播发现），队友在列表中选择加入
4. **公网联机**：先启动服务器（见下），游戏内进入"公网大厅"登录注册、创建/加入房间

### 启动公网服务器

```bash
cd server
python main.py
```

启动时会交互式配置端口号（默认 8765）和邮箱密码（用于注册/重置密码验证码，可回车跳过）。Windows 用户可直接双击 `start_server.bat`。

服务器同时提供 **TCP 大厅**（账号/好友/组队/房间）和 **UDP 游戏战斗**（自定义可靠 UDP 协议，30Hz 状态同步），二者共用同一端口。

详细配置、内网穿透方案、管理控制台命令与 JSON 行协议见 `server/README.md`。

## 数据扩展

| 要做什么 | 做法 |
|---|---|
| 新增载具 | 复制 `data/vehicles/` 下任一 JSON 修改，或直接用游戏内"载具导入器" |
| 新增武器/弹药 | 在 `data/weapons/` 添加 JSON，并在载具的 `weapons` 字段引用其 `id` |
| 新地图 | 用游戏内地图编辑器可视化搭建后保存（支持地形起伏绘制） |
| 新关卡 | 用游戏内关卡编辑器布置双方载具后保存 |
| 自定义内容（导出后） | 将 JSON 放入 `user://data/vehicles/` 或 `user://data/maps/`，游戏自动加载 |
| 生效 | 在弹药编辑器内点"重新加载"，或重启游戏 |

> **联机注意**：使用自定义载具或地图时，房间内所有玩家都需勾选"允许自定义内容"，否则无法开始游戏。内置内容（`res://data/` 下的）无此限制。

### 地形编辑器操作

在地图编辑器的障碍物下拉框中选择"地形"进入地形绘制模式：

| 操作 | 按键 |
|---|---|
| 抬升地形 | 鼠标左键（按住持续绘制） |
| 降低地形 | 鼠标右键（按住持续绘制） |
| 平整地形到 0m | F |
| 调整笔刷半径 | Shift + 滚轮 |
| 调整笔刷强度 | Ctrl + 滚轮 |
| 退出地形模式 | ESC，或在障碍物下拉框切换到其他类型 |

地形数据以 `terrain` 字段（含 `grid_size` 和 `heights` 数组）保存到地图 JSON 中。战斗场景加载时自动从高度图重建可视网格与碰撞体：平坦地形（所有高度≈0）用 BoxShape3D 避免三角边线卡住载具，起伏地形用 **ConcavePolygonShape3D**（三角网格碰撞体），逐网格单元生成 2 个三角形（6 顶点），顶点坐标直接使用世界坐标 `Vector3(xg*cell-half, h, zg*cell-half)` 与可视网格完全一致，设置 `backface_collision=true` 确保射线双向命中。`get_terrain_height` 使用与碰撞网格相同的三角形重心插值（按 v01-v10 对角线拆分三角形），而非双线性插值，消除两者在非平面区域的偏差。所有场景物体（载具生成点、障碍物、草丛/灌木丛）的 Y 坐标均通过射线检测获取真实地表高度（`get_ground_height`）；草丛内每个 10m 方格独立采样地形高度，确保大面积植被贴合起伏地表。射线检测排除空气边界碰撞体与障碍物碰撞体。地形地图中空气边界碰撞体自动下沉至地形最低点以下 5m，避免与地形面重叠导致载具在低地区域弹跳起伏；`terrain_builder` 追踪所有障碍物 RID 并通过 `get_obstacle_rids()` 暴露，供载具对地射线排除。`_ready()` 中等待一帧物理更新确保碰撞体已就绪后再执行射线检测。载具 CharacterBody3D 已配置 `floor_snap_length=2.0`、`floor_max_angle=1.0472`（60°，覆盖山谷地图最陡坡度 57.8°）和 `safe_margin=0.04`，确保在各类碰撞体上稳定着地与滑行；`_align_to_ground` 使用 **5 节点 RayCast3D 多射线对齐系统**——在碰撞盒四角 `(-1.6,1.0,-2.5)` / `(1.6,1.0,-2.5)` / `(-1.6,1.0,2.5)` / `(1.6,1.0,2.5)` 及中心 `(0,1.0,0)` 各创建一条向下 20m 的 RayCast3D 节点（`collision_mask=1`），在 `_ready()` 中挂载；每物理帧先刷新 5 条射线采样地面高度，用四角命中点高度差计算俯仰角 `atan((front-rear)/wheelbase)` 和侧倾角 `atan((left-right)/track_width)`（Godot 4 右手系：`rotation.x` 正值=抬头、`rotation.z` 正值=右倾，故 roll 取反），lerp 平滑（速度 5.0）后旋转修正先于 Y 修正——旋转后重新更新中心射线获取正确地面高度，再做分段 Y 修正（差值<0.5m 直接吸附，0.5~2.0m 用 lerp 速度 10.0），避免旋转导致碰撞盒一角穿地后 `move_and_slide` 下帧把整车推高；仅在 `is_on_floor()` 时执行对齐，避免离地时错误倾斜；射线命中不足 3 条时回退到单射线 `intersect_ray` 方案。

> **历史背景**：Godot 4 的 HeightMapShape3D 忽略 `CollisionShape3D.position` 偏移，碰撞体始终在本地 `(0,0)~(grid_size,grid_size)` 坐标系，而可视网格在 `(-half,-half)~(half,half)` 世界坐标系，两者偏移 `half` 导致射线命中错误高度，载具出现 0.5m 缝隙或陷入地底。改用 ConcavePolygonShape3D 后顶点直接使用世界坐标，天然对齐，问题彻底解决。

### 地面颜色绘制

在地图编辑器的障碍物下拉框中选择"地面颜色"进入颜色绘制模式：

| 操作 | 按键 |
|---|---|
| 绘制颜色 | 鼠标左键（按住持续绘制） |
| 擦除（恢复默认色） | 鼠标右键（按住持续擦除） |
| 选择颜色 | 工具栏 ColorPickerButton |
| 调整笔刷半径 | Shift + 滚轮 |
| 退出颜色模式 | ESC，或在障碍物下拉框切换到其他类型 |

颜色绘制系统使用 256×256 分辨率的 `Image` 作为画布，通过 `ImageTexture` 应用到地形材质的 `albedo_texture`。笔刷使用余弦衰减实现软边缘（中心不透明、边缘渐变），可像画画一样在地面逐区域涂色。地形网格已添加 UV 坐标确保纹理正确映射。加载地图时自动读取 `ground_color` 作为画布初始填充色和擦除色；笔刷半径随地图尺寸自适应（默认 `map_size * 5%`，最小 15m），确保大地图上笔刷可见。绘制后纹理立即重新赋值到材质确保刷新。颜色数据以 PNG 文件保存到 `user://data/maps/{map_id}_color.png`，地图 JSON 的 `terrain.color_texture` 字段记录文件名。战斗场景和关卡编辑器加载时自动检测并应用颜色纹理，无颜色数据的旧地图向后兼容（使用纯色 albedo_color）。地图编辑器摄像机高度在加载地图时自动调整到 `camera_max_height * 0.5`，避免大地图加载后摄像机在地形内部；摄像机远裁面 `far = 8000` 确保大地图不被裁切；编辑器背景色为中性深灰，避免与地面颜色混淆。

## 测试

`tests/` 目录包含 56 个功能测试脚本，命名格式为 `check_<功能>.gd`，覆盖：
- 飞行器：飞行边界、减速、筋斗、俯冲、维修、速度 HUD、转向、起落架、坠毁冲击、地面姿态、生成与方向舵
- 直升机：悬停、旋翼、垂直阻尼、键盘飞控（W/S 俯仰 + A/D+Q/E 偏航 + bank 自动协调 + 自动回正）
- 坦克：异步视角（第三人称鼠标即时控制 + 炮塔限速追踪）、炮镜准心同步（炮镜/第三人称准心与炮管方向一致）、glb 模型导入（炮塔/炮管 reparent 全局变换保留、MeshInstance3D 与容器节点双分支）
- 移动端：布局、按钮透明度、开火门限、暂停按钮、飞机相机/控制、载具可见性、坦克炮镜触控
- 网络：公网本地连接、飞行器网络上报、LAN/公网联机 5 条链路综合校验（服务器建权威副本/玩家入战广播/客户端远程幽灵/击杀播报接HUD/断线清理+公网断线返回主菜单）
- UI：HUD 重叠、暂停设置层、返回键防护、相机稳定
- 其他：弹丸命中、AI、长按开火、地形系统（高度图绘制/碰撞/采样）、地面颜色绘制、颜色/地形绘制修复、深蓝色地面修复、山谷地图验证、平坦地面移动、关卡编辑器地形加载、关卡加载修复、地形出生点与物体高度适配、空气边界、HeightMapShape3D 碰撞体隔离测试（验证 Godot 4 HeightMapShape3D 忽略 position 偏移的 bug）、载具碰撞对齐（ConcavePolygonShape3D 三角网格 + 三角形重心插值 + 直接吸附 Y 修正，消除山谷图下沉/悬空，5 点物理帧测试 gap=0.0000）、**斜坡贴地多射线对齐**（5 节点 RayCast3D 四角+中心采样，旋转先于 Y 避免碰撞盒穿地被推高，pitch/roll 符号按 Godot 4 右手系修正，10~19° 坡度 5 点 gap<0.03m）、炮镜网格隐藏（导入 glb 坦克开镜后递归隐藏 ImportedModel 下所有 GeometryInstance3D，修复 Node3D 容器类型判断 bug 导致的摄像机遮挡）、KV-1 内置坦克数据校验（source=builtin + res:// glb 模型，内置占位网格自动隐藏，glb 炮管柱体_104 自动 reparent 到 gun_node；76mm ZiS-5 炮含 BR-350A APHEBC/BR-350P APCR/OF-350 HE 三种真实弹药，43吨/35km/h/75-110mm 装甲/5 乘员/114 发弹药；副武器 DT 7.62mm 机枪含穿甲/穿甲燃烧/曳光三种弹药，600rpm/1000 发；炮管俯仰 glb 网格跟随移动；开镜后所有网格隐藏、关镜后恢复）

测试脚本可在 Godot 编辑器中直接 Attach 到场景节点运行，用于回归验证。

## 导出

- `export_presets.cfg` 预置 **Windows Desktop** 与 **Android**（包名 `top.thefeishu.wartank`）两套导出配置
- 渲染器为 Mobile + ETC2/ASTC 纹理压缩，主力适配移动端
- 当前版本号：`1.26.8.8`
- 输出路径：Windows → `../out/WarTank.exe`，Android → `../out/WarTank.apk`
- Android 仅构建 arm64-v8a 架构，已配置 INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE 权限
