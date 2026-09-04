"""
公网联机服务器配置
服务器地址预留: game.thefeishu.top
通过内网穿透映射到本机
"""

# ========== 网络配置 ==========
# 监听地址（0.0.0.0 表示所有网卡，内网穿透映射到此端口）
HOST = "0.0.0.0"
# 统一端口：TCP用于大厅匹配，UDP用于游戏战斗（ENet）
PORT = 8765
# 兼容旧变量名
LOBBY_PORT = PORT
GAME_PORT = PORT
# 公网域名（客户端连接用）
PUBLIC_HOST = "game.thefeishu.top"

# ========== 数据库配置 ==========
DATA_DIR = "data"
USERS_FILE = "users.json"
FRIENDS_FILE = "friends.json"
ROOMS_FILE = "rooms.json"

# ========== 游戏配置 ==========
# 最大房间人数
MAX_PLAYERS_PER_ROOM = 16
# 最大好友数
MAX_FRIENDS = 100
# 心跳间隔（秒）
HEARTBEAT_INTERVAL = 30
# 心跳超时（秒）
HEARTBEAT_TIMEOUT = 90
# 房间空房保留时间（秒）
ROOM_EMPTY_TIMEOUT = 300

# ========== 日志配置 ==========
LOG_LEVEL = "INFO"  # DEBUG / INFO / WARNING / ERROR

# ========== 邮箱配置 ==========
# 发件邮箱（可在启动时交互式覆盖）
EMAIL_USERNAME = "yzfs@thefeishu.top"
# SMTP 服务器配置（可在启动时交互式覆盖）
SMTP_HOST = "mail.spacemail.com"
SMTP_PORT = 465  # SSL常用465, STARTTLS常用587, 无加密常用25
# 加密方式: "ssl" / "starttls" / "none"
SMTP_ENCRYPTION = "ssl"
# 邮箱密码在启动时通过 getpass 安全输入，不存储在此文件
