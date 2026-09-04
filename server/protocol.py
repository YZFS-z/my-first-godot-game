"""
客户端-服务器通信协议定义
所有消息为 JSON 格式，以换行符 \\n 分隔
消息结构: {"type": "消息类型", "data": {...}, "req_id": "可选请求ID"}
"""

# ========== 认证相关 ==========
# 客户端 -> 服务器
AUTH_REGISTER = "auth_register"      # 注册: {username, password, email, code}
AUTH_LOGIN = "auth_login"            # 登录: {username, password}
AUTH_LOGOUT = "auth_logout"          # 登出: {}
AUTH_RESET_PASSWORD = "auth_reset_password"  # 重置密码: {username, email, code, new_password}
AUTH_SEND_CODE = "auth_send_code"    # 发送验证码: {email, username, action}
AUTH_DELETE_ACCOUNT = "auth_delete_account"  # 删除账号: {username, password}
HEARTBEAT = "heartbeat"              # 心跳: {}

# 服务器 -> 客户端
AUTH_RESULT = "auth_result"          # 认证结果: {success, message, user_id, username, token}
AUTH_RESET_RESULT = "auth_reset_result"  # 重置密码结果: {success, message}
AUTH_SEND_CODE_RESULT = "auth_send_code_result"  # 发送验证码结果: {success, message}
AUTH_DELETE_RESULT = "auth_delete_result"  # 删除账号结果: {success, message}
ERROR = "error"                      # 通用错误: {code, message}

# ========== 房间相关 ==========
# 客户端 -> 服务器
ROOM_LIST = "room_list"              # 获取房间列表: {}
ROOM_CREATE = "room_create"          # 创建房间: {name, map_id, max_players, password}
ROOM_JOIN = "room_join"              # 加入房间: {room_id, password}
ROOM_LEAVE = "room_leave"            # 离开房间: {}
ROOM_SETTINGS = "room_settings"      # 修改房间设置: {name, map_id, max_players, password}
ROOM_START = "room_start"            # 房主开始游戏: {}
ROOM_KICK = "room_kick"              # 踢出玩家: {user_id}
ROOM_CHAT = "room_chat"              # 房间聊天: {message}
ROOM_READY = "room_ready"            # 准备/取消准备: {ready}
ROOM_TEAM = "room_team"              # 切换队伍: {team}
ROOM_VEHICLE = "room_vehicle"        # 选择载具: {vehicle_id}
RESOURCE_READY = "resource_ready"    # 资源下载完成: {ready}  # 客户端->服务器
RESOURCE_READY_BROADCAST = "resource_ready_broadcast"  # 服务器->客户端: {user_id, username, ready}

# 服务器 -> 客户端
ROOM_LIST_RESULT = "room_list_result"  # 房间列表: {rooms: [{room_id, name, map_id, players, max_players, has_password}]}
ROOM_INFO = "room_info"              # 房间信息更新: {room_id, name, map_id, max_players, host_id, players: [{user_id, username, team, ready, vehicle_id}]}
ROOM_JOIN_RESULT = "room_join_result"  # 加入结果: {success, message, room_info}
ROOM_CREATE_RESULT = "room_create_result"  # 创建结果: {success, message, room_id}
ROOM_PLAYER_JOINED = "room_player_joined"  # 玩家加入: {user_id, username}
ROOM_PLAYER_LEFT = "room_player_left"      # 玩家离开: {user_id, username}
ROOM_CHAT_MESSAGE = "room_chat_message"    # 房间聊天: {user_id, username, message}
GAME_START_INFO = "game_start_info"  # 游戏开始: {game_host, game_port, room_id, map_id, players: [...]}

# ========== 好友相关 ==========
# 客户端 -> 服务器
FRIEND_LIST = "friend_list"          # 获取好友列表: {}
FRIEND_ADD = "friend_add"            # 添加好友: {username}
FRIEND_REMOVE = "friend_remove"      # 删除好友: {user_id}
FRIEND_ACCEPT = "friend_accept"      # 接受好友请求: {user_id}
FRIEND_DECLINE = "friend_decline"    # 拒绝好友请求: {user_id}
FRIEND_REQUESTS = "friend_requests"  # 获取好友请求列表: {}

# 服务器 -> 客户端
FRIEND_LIST_RESULT = "friend_list_result"  # 好友列表: {friends: [{user_id, username, online, in_game}]}
FRIEND_REQUESTS_RESULT = "friend_requests_result"  # 好友请求: {requests: [{user_id, username}]}
FRIEND_ADD_RESULT = "friend_add_result"    # 添加结果: {success, message}
FRIEND_REQUEST = "friend_request"          # 收到好友请求: {user_id, username}
FRIEND_ONLINE = "friend_online"            # 好友上线: {user_id}
FRIEND_OFFLINE = "friend_offline"          # 好友下线: {user_id}

# ========== 组队相关 ==========
# 客户端 -> 服务器
PARTY_INVITE = "party_invite"        # 邀请组队: {user_id}
PARTY_ACCEPT = "party_accept"        # 接受邀请: {party_id}
PARTY_DECLINE = "party_decline"      # 拒绝邀请: {party_id}
PARTY_LEAVE = "party_leave"          # 离开组队: {}
PARTY_INFO = "party_info"            # 获取组队信息: {}
PARTY_PROMOTE = "party_promote"      # 提升队长: {user_id}

# 服务器 -> 客户端
PARTY_INVITE_RECEIVED = "party_invite_received"  # 收到组队邀请: {party_id, inviter_id, inviter_name}
PARTY_INFO_RESULT = "party_info_result"  # 组队信息: {party_id, leader_id, members: [{user_id, username, ready}]}
PARTY_MEMBER_JOINED = "party_member_joined"  # 成员加入: {user_id, username}
PARTY_MEMBER_LEFT = "party_member_left"      # 成员离开: {user_id, username}
PARTY_DISBANDED = "party_disbanded"          # 组队解散: {}

# ========== 自定义资源同步（载具/地图） ==========
# 客户端 -> 服务器
RESOURCE_CHECK = "resource_check"        # 检查资源: {type, id}
RESOURCE_UPLOAD = "resource_upload"      # 上传资源: {type, id, data, hash}
RESOURCE_DOWNLOAD = "resource_download"  # 下载资源: {type, id}
RESOURCE_VERIFY = "resource_verify"      # 校验资源哈希: {type, id, hash}

# 服务器 -> 客户端
RESOURCE_CHECK_RESULT = "resource_check_result"  # 检查结果: {type, id, exists, hash}
RESOURCE_DOWNLOAD_DATA = "resource_download_data"  # 资源数据: {type, id, data, chunk, total, hash}
RESOURCE_UPLOAD_RESULT = "resource_upload_result"  # 上传结果: {success, message, hash}
RESOURCE_VERIFY_RESULT = "resource_verify_result"  # 校验结果: {type, id, valid, server_hash}

# ========== 错误码 ==========
ERR_SUCCESS = 0
ERR_UNKNOWN = 1
ERR_AUTH_FAILED = 100
ERR_USER_EXISTS = 101
ERR_USER_NOT_FOUND = 102
ERR_INVALID_TOKEN = 103
ERR_ROOM_FULL = 200
ERR_ROOM_NOT_FOUND = 201
ERR_ROOM_WRONG_PASSWORD = 202
ERR_ROOM_NOT_HOST = 203
ERR_ROOM_NAME_TOO_LONG = 204
ERR_FRIEND_ALREADY = 300
ERR_FRIEND_NOT_FOUND = 301
ERR_FRIEND_SELF = 302
ERR_PARTY_FULL = 400
ERR_PARTY_NOT_FOUND = 401
ERR_PARTY_NOT_LEADER = 402


def make_message(msg_type: str, data: dict = None, req_id: str = None) -> dict:
    """构造消息"""
    msg = {"type": msg_type, "data": data or {}}
    if req_id:
        msg["req_id"] = req_id
    return msg


def make_error(code: int, message: str, req_id: str = None) -> dict:
    """构造错误消息"""
    return make_message(ERROR, {"code": code, "message": message}, req_id)
