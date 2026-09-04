"""
客户端连接处理器
每个连接一个实例，负责消息收发和路由
"""
import asyncio
import json
import time
from typing import Optional

import config
import protocol
from database import db
from room_manager import room_manager
from party_manager import party_manager


class ClientHandler:
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, server):
        self.reader = reader
        self.writer = writer
        self.server = server
        self.user_id = None
        self.username = None
        self.authenticated = False
        self.last_heartbeat = time.time()
        self._lock = asyncio.Lock()

    @property
    def addr(self):
        return self.writer.get_extra_info("peername")

    def close(self):
        """关闭客户端连接（由管理控制台踢人时调用，线程安全）"""
        try:
            self.writer.close()
        except Exception:
            pass

    async def send(self, msg: dict):
        """发送消息到客户端"""
        try:
            data = (json.dumps(msg, ensure_ascii=False) + "\n").encode("utf-8")
            async with self._lock:
                self.writer.write(data)
                await self.writer.drain()
        except (ConnectionError, asyncio.CancelledError):
            pass

    async def send_error(self, code: int, message: str, req_id: str = None):
        await self.send(protocol.make_error(code, message, req_id))

    async def handle(self):
        """主处理循环"""
        print(f"[Client] 新连接: {self.addr}")
        try:
            buffer = ""
            while True:
                data = await self.reader.read(4096)
                if not data:
                    break
                buffer += data.decode("utf-8", errors="ignore")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                        await self._dispatch(msg)
                    except json.JSONDecodeError:
                        await self.send_error(protocol.ERR_UNKNOWN, "消息格式错误")
        except (ConnectionResetError, asyncio.CancelledError):
            pass
        finally:
            await self._cleanup()
            print(f"[Client] 断开连接: {self.addr} ({self.username or '未登录'})")

    async def _dispatch(self, msg: dict):
        """消息路由"""
        msg_type = msg.get("type", "")
        data = msg.get("data", {})
        req_id = msg.get("req_id")

        # 未登录只能访问认证相关
        if not self.authenticated and msg_type not in (protocol.AUTH_REGISTER, protocol.AUTH_LOGIN, protocol.AUTH_RESET_PASSWORD, protocol.AUTH_SEND_CODE):
            await self.send_error(protocol.ERR_INVALID_TOKEN, "请先登录", req_id)
            return
        handler = getattr(self, f"_handle_{msg_type}", None)
        if handler:
            await handler(data, req_id)
        else:
            await self.send_error(protocol.ERR_UNKNOWN, f"未知消息类型: {msg_type}", req_id)

    # ========== 认证 ==========
    async def _handle_auth_register(self, data: dict, req_id: str):
        import email_sender
        username = data.get("username", "").strip()
        password = data.get("password", "")
        email = data.get("email", "").strip()
        code = data.get("code", "").strip()
        if len(username) < 2 or len(username) > 20:
            await self.send_error(protocol.ERR_AUTH_FAILED, "用户名长度2-20", req_id)
            return
        if len(password) < 4:
            await self.send_error(protocol.ERR_AUTH_FAILED, "密码至少4位", req_id)
            return
        # 邮箱验证（如果启用）
        if email_sender.email_sender:
            if not email:
                await self.send_error(protocol.ERR_AUTH_FAILED, "请输入邮箱", req_id)
                return
            if not code:
                await self.send_error(protocol.ERR_AUTH_FAILED, "请输入验证码", req_id)
                return
            if not email_sender.email_sender.verify_code(email, code):
                await self.send_error(protocol.ERR_AUTH_FAILED, "验证码错误或已过期", req_id)
                return
        user = db.register_user(username, password, email)
        if not user:
            await self.send_error(protocol.ERR_USER_EXISTS, "用户名已存在", req_id)
            return
        # 注册成功后自动登录
        self.user_id = user["user_id"]
        self.username = user["username"]
        self.authenticated = True
        self.last_heartbeat = time.time()
        self.server.add_client(self)
        await self.send(protocol.make_message(protocol.AUTH_RESULT, {
            "success": True, "message": "注册并登录成功", **user
        }, req_id))
        # 通知好友上线
        await self.server.notify_friends_status(self.user_id, online=True)
        print(f"[Auth] {self.username} 注册并登录成功")

    async def _handle_auth_login(self, data: dict, req_id: str):
        username = data.get("username", "").strip()
        password = data.get("password", "")
        user = db.login_user(username, password)
        if not user:
            await self.send_error(protocol.ERR_AUTH_FAILED, "用户名或密码错误", req_id)
            return
        # 如果该用户已在线，踢掉旧连接
        old = self.server.get_client_by_user(user["user_id"])
        if old:
            await old.send(protocol.make_message(protocol.ERROR, {
                "code": protocol.ERR_AUTH_FAILED, "message": "账号在其他地方登录"
            }))
            # 立即从字典移除，防止旧连接断开时删掉新连接
            self.server.remove_client(old)
            old.writer.close()

        self.user_id = user["user_id"]
        self.username = user["username"]
        self.authenticated = True
        self.last_heartbeat = time.time()
        self.server.add_client(self)
        await self.send(protocol.make_message(protocol.AUTH_RESULT, {
            "success": True, "message": "登录成功", **user
        }, req_id))
        # 通知好友上线
        await self.server.notify_friends_status(self.user_id, online=True)
        print(f"[Auth] {self.username} 登录成功")

    async def _handle_auth_send_code(self, data: dict, req_id: str):
        """发送邮箱验证码"""
        import email_sender
        email = data.get("email", "").strip()
        username = data.get("username", "").strip()
        action = data.get("action", "register")  # register / reset
        if not email_sender.email_sender:
            await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                "success": False, "message": "服务器未启用邮箱验证"
            }, req_id))
            return
        if not email or "@" not in email:
            await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                "success": False, "message": "请输入有效的邮箱地址"
            }, req_id))
            return
        # 重置密码时验证用户名和邮箱匹配
        if action == "reset":
            if not username:
                await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                    "success": False, "message": "请输入用户名"
                }, req_id))
                return
            user = db.find_user_by_email(email)
            if not user or user["username"] != username:
                await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                    "success": False, "message": "用户名与邮箱不匹配"
                }, req_id))
                return
        ok = email_sender.email_sender.send_verification_code(email, username, action)
        if ok:
            await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                "success": True, "message": "验证码已发送，请查收邮件（10分钟内有效）"
            }, req_id))
        else:
            await self.send(protocol.make_message(protocol.AUTH_SEND_CODE_RESULT, {
                "success": False, "message": "验证码发送失败，请检查邮箱或稍后重试"
            }, req_id))

    async def _handle_auth_reset_password(self, data: dict, req_id: str):
        """重置密码：需要邮箱验证码"""
        import email_sender
        username = data.get("username", "").strip()
        email = data.get("email", "").strip()
        code = data.get("code", "").strip()
        new_password = data.get("new_password", "")
        if len(username) < 2 or len(username) > 20:
            await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                "success": False, "message": "用户名长度2-20"
            }, req_id))
            return
        if len(new_password) < 4:
            await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                "success": False, "message": "新密码至少4位"
            }, req_id))
            return
        # 邮箱验证（如果启用）
        if email_sender.email_sender:
            if not email:
                await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                    "success": False, "message": "请输入邮箱"
                }, req_id))
                return
            if not code:
                await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                    "success": False, "message": "请输入验证码"
                }, req_id))
                return
            if not email_sender.email_sender.verify_code(email, code):
                await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                    "success": False, "message": "验证码错误或已过期"
                }, req_id))
                return
        success = db.reset_password(username, email, new_password)
        if success:
            await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                "success": True, "message": "密码重置成功，请使用新密码登录"
            }, req_id))
            print(f"[Auth] {username} 密码已重置")
        else:
            await self.send(protocol.make_message(protocol.AUTH_RESET_RESULT, {
                "success": False, "message": "用户名与邮箱不匹配"
            }, req_id))

    async def _handle_auth_delete_account(self, data: dict, req_id: str):
        """删除账号（需已登录且验证密码）"""
        if not self.authenticated:
            await self.send_error(protocol.ERR_INVALID_TOKEN, "请先登录", req_id)
            return
        password = data.get("password", "")
        if not password:
            await self.send(protocol.make_message(protocol.AUTH_DELETE_RESULT, {
                "success": False, "message": "请输入密码"
            }, req_id))
            return
        # 验证密码
        user = db.login_user(self.username, password)
        if not user:
            await self.send(protocol.make_message(protocol.AUTH_DELETE_RESULT, {
                "success": False, "message": "密码错误"
            }, req_id))
            return
        success = db.delete_user(self.username, password)
        if success:
            await self.send(protocol.make_message(protocol.AUTH_DELETE_RESULT, {
                "success": True, "message": "账号已删除"
            }, req_id))
            print(f"[Auth] {self.username} 账号已删除")
            # 断开连接
            self.authenticated = False
            self.server.remove_client(self)
            await self.close()
        else:
            await self.send(protocol.make_message(protocol.AUTH_DELETE_RESULT, {
                "success": False, "message": "删除失败"
            }, req_id))

    async def _handle_auth_logout(self, data: dict, req_id: str):
        await self._cleanup()
        self.writer.close()

    async def _handle_heartbeat(self, data: dict, req_id: str):
        self.last_heartbeat = time.time()

    # ========== 房间 ==========
    async def _handle_room_list(self, data: dict, req_id: str):
        rooms = room_manager.list_rooms()
        await self.send(protocol.make_message(protocol.ROOM_LIST_RESULT, {"rooms": rooms}, req_id))

    async def _handle_room_create(self, data: dict, req_id: str):
        name = data.get("name", f"{self.username}的房间")[:32]
        map_id = data.get("map_id", "map_desert")
        max_players = data.get("max_players", 8)
        password = data.get("password", "")
        ai_config = data.get("ai_config", {"team1_count": 0, "team1_difficulty": 1, "team2_count": 2, "team2_difficulty": 1})
        room = room_manager.create_room(name, map_id, max_players, self.user_id, self.username, password, ai_config)
        await self.send(protocol.make_message(protocol.ROOM_CREATE_RESULT, {
            "success": True, "room_id": room.room_id, "room_info": room.to_full_info()
        }, req_id))
        # 通知房间内玩家（目前只有自己）
        await self.server.broadcast_room_info(room)

    async def _handle_room_join(self, data: dict, req_id: str):
        room_id = data.get("room_id", "")
        password = data.get("password", "")
        success, message, room = room_manager.join_room(room_id, self.user_id, self.username, password)
        if not success:
            await self.send_error(protocol.ERR_ROOM_FULL if "满" in message else protocol.ERR_ROOM_NOT_FOUND, message, req_id)
            return
        await self.send(protocol.make_message(protocol.ROOM_JOIN_RESULT, {
            "success": True, "room_info": room.to_full_info()
        }, req_id))
        # 通知房间内其他玩家
        await self.server.broadcast_room_event(room, protocol.ROOM_PLAYER_JOINED, {
            "user_id": self.user_id, "username": self.username
        })
        await self.server.broadcast_room_info(room)

    async def _handle_room_leave(self, data: dict, req_id: str):
        room = room_manager.leave_room(self.user_id)
        if room:
            await self.server.broadcast_room_event(room, protocol.ROOM_PLAYER_LEFT, {
                "user_id": self.user_id, "username": self.username
            })
            await self.server.broadcast_room_info(room)

    async def _handle_room_settings(self, data: dict, req_id: str):
        success, message = room_manager.update_settings(
            self.user_id,
            name=data.get("name"),
            map_id=data.get("map_id"),
            max_players=data.get("max_players"),
            password=data.get("password")
        )
        if success:
            room = room_manager.get_user_room(self.user_id)
            if room:
                await self.server.broadcast_room_info(room)
        else:
            await self.send_error(protocol.ERR_ROOM_NOT_HOST, message, req_id)

    async def _handle_room_start(self, data: dict, req_id: str):
        success, message, room = room_manager.start_game(self.user_id)
        if not success:
            await self.send_error(protocol.ERR_ROOM_NOT_HOST, message, req_id)
            return
        # 通知所有玩家游戏开始，包含游戏服务器连接信息
        game_info = {
            "game_host": config.PUBLIC_HOST,
            "game_port": room.game_port,
            "room_id": room.room_id,
            "map_id": room.map_id,
            "ai_config": room.ai_config,
            "players": [{"user_id": uid, **info} for uid, info in room.players.items()]
        }
        await self.server.broadcast_room(room, protocol.GAME_START_INFO, game_info)
        print(f"[Game] 房间 {room.room_id} 开始游戏，端口 {room.game_port}")

    async def _handle_room_chat(self, data: dict, req_id: str):
        message = data.get("message", "")[:200]
        room = room_manager.get_user_room(self.user_id)
        if room and message:
            await self.server.broadcast_room(room, protocol.ROOM_CHAT_MESSAGE, {
                "user_id": self.user_id, "username": self.username, "message": message
            })

    async def _handle_room_ready(self, data: dict, req_id: str):
        """玩家准备/取消准备"""
        ready = data.get("ready", False)
        room = room_manager.get_user_room(self.user_id)
        if room:
            room_manager.set_player_ready(self.user_id, ready)
            # 广播房间信息更新
            await self.server.broadcast_room_info(room)

    async def _handle_room_team(self, data: dict, req_id: str):
        """玩家切换队伍"""
        team = data.get("team", 1)
        if team not in (1, 2):
            return
        room = room_manager.get_user_room(self.user_id)
        if room:
            room_manager.set_player_team(self.user_id, team)
            await self.server.broadcast_room_info(room)

    async def _handle_room_vehicle(self, data: dict, req_id: str):
        """玩家选择载具"""
        vehicle_id = data.get("vehicle_id", "tank_abrams")
        room = room_manager.get_user_room(self.user_id)
        if room:
            room.set_vehicle(self.user_id, vehicle_id)
            await self.server.broadcast_room_info(room)

    async def _handle_resource_ready(self, data: dict, req_id: str):
        """玩家资源下载完成/未完成"""
        ready = data.get("ready", False)
        room = room_manager.get_user_room(self.user_id)
        if room:
            room.set_resource_ready(self.user_id, ready)
            # 广播给房间内所有玩家
            for uid in room.players:
                client = self.server.get_client_by_user(uid)
                if client:
                    await client.send(protocol.make_message(protocol.RESOURCE_READY_BROADCAST, {
                        "user_id": self.user_id,
                        "username": self.username,
                        "ready": ready
                    }))

    # ========== 好友 ==========
    async def _handle_friend_list(self, data: dict, req_id: str):
        friends = db.get_friends(self.user_id)
        # 附加在线状态
        for f in friends:
            client = self.server.get_client_by_user(f["user_id"])
            f["online"] = client is not None
            f["in_game"] = client is not None and room_manager.get_user_room(f["user_id"]) is not None
        await self.send(protocol.make_message(protocol.FRIEND_LIST_RESULT, {"friends": friends}, req_id))

    async def _handle_friend_requests(self, data: dict, req_id: str):
        requests = db.get_friend_requests(self.user_id)
        await self.send(protocol.make_message(protocol.FRIEND_REQUESTS_RESULT, {"requests": requests}, req_id))

    async def _handle_friend_add(self, data: dict, req_id: str):
        username = data.get("username", "").strip()
        target = db.find_user_by_name(username)
        if not target:
            await self.send_error(protocol.ERR_FRIEND_NOT_FOUND, "用户不存在", req_id)
            return
        if target["user_id"] == self.user_id:
            await self.send_error(protocol.ERR_FRIEND_SELF, "不能添加自己为好友", req_id)
            return
        if db.are_friends(self.user_id, target["user_id"]):
            await self.send_error(protocol.ERR_FRIEND_ALREADY, "已经是好友", req_id)
            return
        success = db.add_friend_request(self.user_id, target["user_id"])
        if not success:
            await self.send_error(protocol.ERR_FRIEND_ALREADY, "已发送过请求", req_id)
            return
        await self.send(protocol.make_message(protocol.FRIEND_ADD_RESULT, {"success": True}, req_id))
        # 通知对方收到好友请求
        target_client = self.server.get_client_by_user(target["user_id"])
        if target_client:
            await target_client.send(protocol.make_message(protocol.FRIEND_REQUEST, {
                "user_id": self.user_id, "username": self.username
            }))

    async def _handle_friend_accept(self, data: dict, req_id: str):
        friend_id = data.get("user_id", "")
        success = db.accept_friend(self.user_id, friend_id)
        if success:
            friend = db.get_user(friend_id)
            # 通知双方好友列表更新
            await self.send(protocol.make_message(protocol.FRIEND_LIST_RESULT, {
                "friends": db.get_friends(self.user_id)
            }))
            friend_client = self.server.get_client_by_user(friend_id)
            if friend_client:
                await friend_client.send(protocol.make_message(protocol.FRIEND_LIST_RESULT, {
                    "friends": db.get_friends(friend_id)
                }))

    async def _handle_friend_decline(self, data: dict, req_id: str):
        friend_id = data.get("user_id", "")
        db.decline_friend(self.user_id, friend_id)

    async def _handle_friend_remove(self, data: dict, req_id: str):
        friend_id = data.get("user_id", "")
        db.remove_friend(self.user_id, friend_id)

    # ========== 组队 ==========
    async def _handle_party_invite(self, data: dict, req_id: str):
        target_id = data.get("user_id", "")
        target = db.get_user(target_id)
        if not target:
            await self.send_error(protocol.ERR_FRIEND_NOT_FOUND, "用户不存在", req_id)
            return
        success, message, party = party_manager.invite(self.user_id, target_id, self.username)
        if not success:
            await self.send_error(protocol.ERR_PARTY_FULL, message, req_id)
            return
        # 通知被邀请者
        target_client = self.server.get_client_by_user(target_id)
        if target_client:
            await target_client.send(protocol.make_message(protocol.PARTY_INVITE_RECEIVED, {
                "party_id": party.party_id,
                "inviter_id": self.user_id,
                "inviter_name": self.username
            }))

    async def _handle_party_accept(self, data: dict, req_id: str):
        party_id = data.get("party_id", "")
        success, message, party = party_manager.accept_invite(self.user_id, self.username, party_id)
        if not success:
            await self.send_error(protocol.ERR_PARTY_NOT_FOUND, message, req_id)
            return
        await self.server.broadcast_party_info(party)

    async def _handle_party_decline(self, data: dict, req_id: str):
        party_id = data.get("party_id", "")
        party_manager.decline_invite(self.user_id, party_id)

    async def _handle_party_leave(self, data: dict, req_id: str):
        party = party_manager.leave_party(self.user_id)
        if party:
            await self.server.broadcast_party_event(party, protocol.PARTY_MEMBER_LEFT, {
                "user_id": self.user_id, "username": self.username
            })
            await self.server.broadcast_party_info(party)

    async def _handle_party_info(self, data: dict, req_id: str):
        party = party_manager.get_user_party(self.user_id)
        if party:
            await self.send(protocol.make_message(protocol.PARTY_INFO_RESULT, party.to_info(), req_id))
        else:
            await self.send(protocol.make_message(protocol.PARTY_INFO_RESULT, {"party_id": "", "leader_id": "", "members": []}, req_id))

    async def _handle_party_promote(self, data: dict, req_id: str):
        new_leader = data.get("user_id", "")
        success, message = party_manager.promote_leader(self.user_id, new_leader)
        if success:
            party = party_manager.get_user_party(self.user_id)
            if party:
                await self.server.broadcast_party_info(party)
        else:
            await self.send_error(protocol.ERR_PARTY_NOT_LEADER, message, req_id)

    # ========== 自定义资源同步 ==========
    async def _handle_resource_check(self, data: dict, req_id: str):
        """检查资源是否存在于服务器，返回哈希"""
        import resource_manager
        resource_type = data.get("type", "")
        resource_id = data.get("id", "")
        exists = resource_manager.resource_manager.exists(resource_type, resource_id)
        resource_hash = resource_manager.resource_manager.get_hash(resource_type, resource_id) if exists else ""
        await self.send(protocol.make_message(protocol.RESOURCE_CHECK_RESULT, {
            "type": resource_type,
            "id": resource_id,
            "exists": exists,
            "hash": resource_hash
        }, req_id))

    async def _handle_resource_upload(self, data: dict, req_id: str):
        """上传自定义资源，校验哈希"""
        import resource_manager
        resource_type = data.get("type", "")
        resource_id = data.get("id", "")
        resource_data = data.get("data", {})
        client_hash = data.get("hash", "")
        if resource_type not in ("vehicle", "map"):
            await self.send(protocol.make_message(protocol.RESOURCE_UPLOAD_RESULT, {
                "success": False,
                "message": "不支持的资源类型",
                "hash": ""
            }, req_id))
            return
        if not resource_id or not resource_data:
            await self.send(protocol.make_message(protocol.RESOURCE_UPLOAD_RESULT, {
                "success": False,
                "message": "资源ID或数据为空",
                "hash": ""
            }, req_id))
            return
        result = resource_manager.resource_manager.save(resource_type, resource_id, resource_data, client_hash)
        await self.send(protocol.make_message(protocol.RESOURCE_UPLOAD_RESULT, result, req_id))

    async def _handle_resource_download(self, data: dict, req_id: str):
        """下载自定义资源，返回哈希"""
        import resource_manager
        resource_type = data.get("type", "")
        resource_id = data.get("id", "")
        resource_data = resource_manager.resource_manager.get(resource_type, resource_id)
        if not resource_data:
            await self.send_error(protocol.ERR_UNKNOWN, f"资源不存在: {resource_type}/{resource_id}", req_id)
            return
        resource_hash = resource_manager.resource_manager.get_hash(resource_type, resource_id)
        # 当前实现为单块完整传输（JSON配置通常不大），后续可扩展分块
        await self.send(protocol.make_message(protocol.RESOURCE_DOWNLOAD_DATA, {
            "type": resource_type,
            "id": resource_id,
            "data": resource_data,
            "chunk": 1,
            "total": 1,
            "hash": resource_hash
        }, req_id))

    async def _handle_resource_verify(self, data: dict, req_id: str):
        """校验客户端资源哈希是否与服务器一致"""
        import resource_manager
        resource_type = data.get("type", "")
        resource_id = data.get("id", "")
        client_hash = data.get("hash", "")
        server_hash = resource_manager.resource_manager.get_hash(resource_type, resource_id)
        valid = (server_hash != "" and server_hash == client_hash)
        await self.send(protocol.make_message(protocol.RESOURCE_VERIFY_RESULT, {
            "type": resource_type,
            "id": resource_id,
            "valid": valid,
            "server_hash": server_hash
        }, req_id))

    async def _cleanup(self):
        """连接清理"""
        if self.authenticated and self.user_id:
            # 离开房间
            room = room_manager.leave_room(self.user_id)
            if room:
                await self.server.broadcast_room_event(room, protocol.ROOM_PLAYER_LEFT, {
                    "user_id": self.user_id, "username": self.username
                })
                await self.server.broadcast_room_info(room)
            # 离开组队
            party = party_manager.leave_party(self.user_id)
            if party:
                await self.server.broadcast_party_event(party, protocol.PARTY_MEMBER_LEFT, {
                    "user_id": self.user_id, "username": self.username
                })
                await self.server.broadcast_party_info(party)
            # 通知好友下线
            await self.server.notify_friends_status(self.user_id, online=False)
            self.server.remove_client(self)
        self.authenticated = False
        self.user_id = None
