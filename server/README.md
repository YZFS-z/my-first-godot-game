# 公网联机服务器

Python 3.10+，仅使用标准库，无需安装第三方依赖。

服务器同时提供 **TCP 大厅服务**（账号/好友/组队/房间匹配）和 **UDP 游戏战斗服务**（状态同步），二者共用同一端口。

## 功能

### 大厅服务（TCP）
- 用户注册 / 登录 / 登出 / 删除账号 / 重置密码
- 邮箱验证码（注册、重置密码时发送，可禁用）
- 房间列表、创建 / 加入 / 离开房间、房间聊天、准备 / 切换队伍 / 选择载具
- 好友系统（添加 / 删除 / 接受 / 拒绝请求 / 在线状态推送）
- 组队系统（邀请 / 接受 / 离开 / 提升队长）
- 游戏开始协调（分配游戏实例，通知玩家连接 UDP 战斗服务）

### 游戏战斗服务（UDP）
- 自定义可靠 UDP 协议（零依赖，标准库实现）
  - 不可靠通道：输入上报、状态同步（30Hz，丢包可接受）
  - 可靠通道：开火、命中、击毁等事件（ACK 重传，超时 1 秒，最多 5 次）
- 服务器权威状态同步
- AI 载具状态管理

## 模块结构

```
server/
├── main.py              # 入口：交互式配置 + 启动 TCP 大厅 + UDP 游戏服务 + 管理控制台
├── config.py            # 配置：端口、公网域名、数据库、游戏参数、日志、邮箱 SMTP
├── protocol.py          # 通信协议常量定义（JSON 行消息）
├── database.py          # JSON 文件数据库（用户、好友关系，SHA-256 密码哈希）
├── client_handler.py    # TCP 客户端连接处理（消息路由、认证、房间/好友/组队逻辑）
├── room_manager.py      # 房间管理（创建/加入/离开/聊天/开始游戏）
├── party_manager.py     # 组队管理（邀请/接受/离开/队长）
├── game_server.py       # UDP 游戏战斗服务（自定义可靠 UDP、状态同步、AI 管理）
├── email_sender.py      # 邮箱验证码发送（SMTP SSL）
├── resource_manager.py  # 资源管理（联机内容校验相关）
├── start_server.bat     # Windows 一键启动脚本
├── README.md            # 本文档
└── data/                # 运行时数据（首次启动自动创建）
    ├── users.json       # 用户数据
    └── friends.json     # 好友关系
```

## 部署

### 1. 直接运行

```bash
python main.py
```

启动时自动探测公网 IP 和内网 IP 并显示，随后进入三步交互式配置：

1. **端口号**：TCP 大厅与 UDP 游戏共用，默认 8765，回车使用默认
2. **邮件服务器**：可选自定义 SMTP 地址、端口、加密方式（SSL/STARTTLS/无加密）、发件邮箱；回车使用 `config.py` 中的默认配置
3. **邮箱密码**：使用 `getpass` 安全输入（不回显），需二次确认；回车跳过则禁用邮箱验证

Windows 用户可直接双击 `start_server.bat`。

> 云服务器 SSH 场景下，密码输入通过 `getpass` 隐藏，不会在终端历史或屏幕上显示明文。

### 2. 内网穿透映射

将公网域名映射到本机端口。默认公网地址：`game.thefeishu.top:8765`

推荐工具：
- frp: `./frpc -c frpc.ini`
- ngrok: `ngrok tcp 8765`
- 花生壳 / 神卓互联等

frpc 配置示例（TCP 大厅 + UDP 游戏需分别映射，共用端口时两条规则指向同一本地端口）：
```ini
[common]
server_addr = 你的frp服务器地址
server_port = 7000

[lobby_tcp]
type = tcp
local_ip = 127.0.0.1
local_port = 8765
remote_port = 8765

[game_udp]
type = udp
local_ip = 127.0.0.1
local_port = 8765
remote_port = 8765
```

### 3. 配置

编辑 `config.py`：

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `HOST` | `0.0.0.0` | 监听地址（所有网卡） |
| `PORT` | `8765` | 统一端口（TCP 大厅 + UDP 游戏共用） |
| `PUBLIC_HOST` | `game.thefeishu.top` | 公网域名（客户端连接用） |
| `DATA_DIR` | `data` | 数据存储目录 |
| `MAX_PLAYERS_PER_ROOM` | `16` | 每房间最大人数 |
| `MAX_FRIENDS` | `100` | 最大好友数 |
| `HEARTBEAT_INTERVAL` | `30` | 心跳间隔（秒） |
| `HEARTBEAT_TIMEOUT` | `90` | 心跳超时（秒），超时自动断开 |
| `ROOM_EMPTY_TIMEOUT` | `300` | 空房间保留时间（秒） |
| `LOG_LEVEL` | `INFO` | 日志级别（DEBUG / INFO / WARNING / ERROR） |
| `EMAIL_USERNAME` | `yzfs@thefeishu.top` | 发件邮箱（可启动时覆盖） |
| `SMTP_HOST` | `mail.spacemail.com` | SMTP 服务器（可启动时覆盖） |
| `SMTP_PORT` | `465` | SMTP 端口（SSL=465, STARTTLS=587, 无加密=25） |
| `SMTP_ENCRYPTION` | `ssl` | 加密方式：`ssl` / `starttls` / `none` |

> 邮箱密码不在配置文件中存储，启动时通过 `getpass` 交互式安全输入。

## 管理控制台

服务器启动后，命令行显示 `server> ` 提示符，输入 `help` 查看命令：

| 命令 | 说明 |
|---|---|
| `help` / `?` | 显示帮助 |
| `status` | 显示服务器状态（运行时长/端口/注册数/在线数/房间数/邮箱状态） |
| `list` | 列出所有注册用户（用户名、ID、邮箱、在线状态） |
| `online` | 列出当前在线用户（及所在房间） |
| `rooms` | 列出当前房间（房间ID、名称、人数、地图、玩家列表） |
| `delete <用户名>` | 删除指定账号（管理员操作，无需密码，在线则同时踢下线） |
| `kick <用户名>` | 踢下线指定用户 |
| `reload data` | 重新读取 users.json / friends.json（手动编辑后生效） |
| `reload config` | 重载 config 模块并重建邮件发送器 |
| `reload email` | 重建邮件发送器（使用当前配置） |
| `reload module <名>` | 重载指定代码模块（仅新连接生效，实验性） |
| `reload all` | 重载 data + config + email |
| `clear` | 清屏 |
| `quit` / `exit` / `stop` | 关闭服务器 |

## 数据存储

- `data/users.json`：用户数据（用户名、SHA-256 密码哈希、邮箱、注册时间、user_id）
- `data/friends.json`：好友关系（user_id → {friend_id: status}，status 为 pending/accepted）

首次运行自动创建 `data/` 目录及数据文件。密码使用 SHA-256 哈希存储，不保存明文。

## 通信协议

所有消息为 **JSON 行格式**，每条消息以 `\n` 结尾：

```json
{"type": "auth_login", "data": {"username": "xxx", "password": "xxx"}, "req_id": "可选请求ID"}
```

### 消息分类

| 类别 | 方向 | 主要消息类型 |
|---|---|---|
| 认证 | C→S | `auth_register`, `auth_login`, `auth_logout`, `auth_reset_password`, `auth_send_code`, `auth_delete_account`, `heartbeat` |
| 认证 | S→C | `auth_result`, `auth_reset_result`, `auth_send_code_result`, `auth_delete_result`, `error` |
| 房间 | C→S | `room_list`, `room_create`, `room_join`, `room_leave`, `room_settings`, `room_start`, `room_kick`, `room_chat`, `room_ready`, `room_team`, `room_vehicle` |
| 房间 | S→C | `room_list_result`, `room_info`, `room_join_result`, `room_create_result`, `room_player_joined`, `room_player_left`, `room_chat_message`, `game_start_info` |
| 好友 | C→S | `friend_list`, `friend_add`, `friend_remove`, `friend_accept`, `friend_decline`, `friend_requests` |
| 好友 | S→C | `friend_list_result`, `friend_online`, `friend_offline`, 等 |
| 组队 | C→S | `party_invite`, `party_accept`, `party_leave`, `party_promote` |
| 组队 | S→C | `party_info_result`, `party_invite_received`, 等 |

完整协议常量定义见 `protocol.py`，消息处理逻辑见 `client_handler.py`。

### UDP 游戏协议

游戏战斗使用自定义二进制 UDP 协议（非 JSON），详见 `game_server.py`：
- 包头：标志位（不可靠/可靠/ACK）+ 序列号
- 不可靠包：玩家输入、载具状态（30Hz 广播）
- 可靠包：开火、命中、击毁事件（带 ACK 确认与重传）
