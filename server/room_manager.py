"""
房间管理器
创建、加入、离开、销毁房间
"""
import uuid
import time
from typing import Optional

import config
import protocol


class Room:
    def __init__(self, room_id: str, name: str, map_id: str, max_players: int,
                 host_id: str, password: str = "", ai_config: dict = None):
        self.room_id = room_id
        self.name = name
        self.map_id = map_id
        self.max_players = min(max_players, config.MAX_PLAYERS_PER_ROOM)
        self.host_id = host_id
        self.password = password
        self.ai_config = ai_config or {"team1_count": 0, "team1_difficulty": 1, "team2_count": 2, "team2_difficulty": 1}
        self.players = {}  # user_id -> {username, team, ready}
        self.created_at = time.time()
        self.last_activity = time.time()
        self.in_game = False
        self.game_port = None  # 分配的游戏端口

    def add_player(self, user_id: str, username: str) -> bool:
        if user_id in self.players:
            return True
        if len(self.players) >= self.max_players:
            return False
        # 自动分配队伍
        team1 = sum(1 for p in self.players.values() if p["team"] == 1)
        team2 = sum(1 for p in self.players.values() if p["team"] == 2)
        team = 1 if team1 <= team2 else 2
        self.players[user_id] = {"username": username, "team": team, "ready": False, "vehicle_id": "tank_abrams", "resource_ready": False}
        self.last_activity = time.time()
        return True

    def set_vehicle(self, user_id: str, vehicle_id: str):
        """设置玩家选择的载具"""
        if user_id in self.players:
            self.players[user_id]["vehicle_id"] = vehicle_id
            self.last_activity = time.time()

    def set_resource_ready(self, user_id: str, ready: bool):
        """设置玩家资源下载完成状态"""
        if user_id in self.players:
            self.players[user_id]["resource_ready"] = ready
            self.last_activity = time.time()

    def remove_player(self, user_id: str):
        if user_id in self.players:
            del self.players[user_id]
        self.last_activity = time.time()

    def is_empty(self) -> bool:
        return len(self.players) == 0

    def has_password(self) -> bool:
        return bool(self.password)

    def check_password(self, password: str) -> bool:
        return self.password == password

    def to_list_info(self) -> dict:
        """房间列表中的简要信息"""
        return {
            "room_id": self.room_id,
            "name": self.name,
            "map_id": self.map_id,
            "players": len(self.players),
            "max_players": self.max_players,
            "has_password": self.has_password(),
            "in_game": self.in_game
        }

    def to_full_info(self) -> dict:
        """房间详细信息"""
        return {
            "room_id": self.room_id,
            "name": self.name,
            "map_id": self.map_id,
            "max_players": self.max_players,
            "host_id": self.host_id,
            "ai_config": self.ai_config,
            "players": [
                {"user_id": uid, **info}
                for uid, info in self.players.items()
            ]
        }


class RoomManager:
    def __init__(self):
        self.rooms = {}  # room_id -> Room
        self.user_room = {}  # user_id -> room_id

    def create_room(self, name: str, map_id: str, max_players: int,
                    host_id: str, host_name: str, password: str = "",
                    ai_config: dict = None) -> Optional[Room]:
        """创建房间"""
        # 如果用户已在其他房间，先离开
        self.leave_room(host_id)

        room_id = str(uuid.uuid4())[:8]
        room = Room(room_id, name, map_id, max_players, host_id, password, ai_config)
        room.add_player(host_id, host_name)
        self.rooms[room_id] = room
        self.user_room[host_id] = room_id
        return room

    def join_room(self, room_id: str, user_id: str, username: str,
                  password: str = "") -> tuple:
        """加入房间，返回 (success, message, room)"""
        room = self.rooms.get(room_id)
        if not room:
            return False, "房间不存在", None
        if room.in_game:
            return False, "游戏已开始", None
        if room.has_password() and not room.check_password(password):
            return False, "密码错误", None
        if len(room.players) >= room.max_players:
            return False, "房间已满", None

        # 先离开其他房间
        self.leave_room(user_id)

        room.add_player(user_id, username)
        self.user_room[user_id] = room_id
        return True, "加入成功", room

    def leave_room(self, user_id: str) -> Optional[Room]:
        """离开房间，返回离开的房间（如果有）"""
        room_id = self.user_room.get(user_id)
        if not room_id:
            return None
        room = self.rooms.get(room_id)
        if room:
            room.remove_player(user_id)
            # 如果房主离开，转移房主或销毁房间
            if room.host_id == user_id:
                if room.players:
                    room.host_id = next(iter(room.players.keys()))
                else:
                    # 空房间，延迟销毁（立即删除）
                    del self.rooms[room_id]
        del self.user_room[user_id]
        return room

    def get_room(self, room_id: str) -> Optional[Room]:
        return self.rooms.get(room_id)

    def get_user_room(self, user_id: str) -> Optional[Room]:
        room_id = self.user_room.get(user_id)
        if room_id:
            return self.rooms.get(room_id)
        return None

    def list_rooms(self) -> list:
        """获取所有公开房间列表"""
        return [room.to_list_info() for room in self.rooms.values() if not room.in_game]

    def get_all_rooms(self) -> list:
        """获取所有房间（含游戏中），返回原始 Room 对象列表（管理控制台用）"""
        return list(self.rooms.values())

    def set_player_ready(self, user_id: str, ready: bool):
        room = self.get_user_room(user_id)
        if room and user_id in room.players:
            room.players[user_id]["ready"] = ready
            room.last_activity = time.time()

    def set_player_team(self, user_id: str, team: int):
        room = self.get_user_room(user_id)
        if room and user_id in room.players:
            room.players[user_id]["team"] = team
            room.last_activity = time.time()

    def update_settings(self, user_id: str, name: str = None, map_id: str = None,
                        max_players: int = None, password: str = None) -> tuple:
        """房主修改房间设置"""
        room = self.get_user_room(user_id)
        if not room:
            return False, "不在房间中"
        if room.host_id != user_id:
            return False, "只有房主可以修改设置"
        if name:
            room.name = name[:32]
        if map_id:
            room.map_id = map_id
        if max_players:
            room.max_players = min(max_players, config.MAX_PLAYERS_PER_ROOM)
        if password is not None:
            room.password = password
        room.last_activity = time.time()
        return True, "设置已更新"

    def start_game(self, user_id: str) -> tuple:
        """房主开始游戏"""
        room = self.get_user_room(user_id)
        if not room:
            return False, "不在房间中", None
        if room.host_id != user_id:
            return False, "只有房主可以开始游戏", None
        if len(room.players) < 2:
            return False, "至少需要2名玩家", None

        # 分配游戏端口
        room.game_port = self._allocate_game_port()
        room.in_game = True
        return True, "游戏开始", room

    def _allocate_game_port(self) -> int:
        """游戏端口固定为统一端口（UDP与TCP共用）"""
        return config.GAME_PORT

    def cleanup_empty_rooms(self):
        """清理长时间空的房间"""
        now = time.time()
        to_remove = []
        for rid, room in self.rooms.items():
            if room.is_empty() and (now - room.last_activity) > config.ROOM_EMPTY_TIMEOUT:
                to_remove.append(rid)
        for rid in to_remove:
            del self.rooms[rid]
        if to_remove:
            print(f"[RoomManager] 清理了 {len(to_remove)} 个空房间")


# 全局单例
room_manager = RoomManager()
