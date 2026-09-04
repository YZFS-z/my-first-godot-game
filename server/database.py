"""
简单的 JSON 文件数据库
存储用户、好友关系
"""
import json
import os
import hashlib
import uuid
import time
from typing import Optional

import config


class Database:
    def __init__(self):
        os.makedirs(config.DATA_DIR, exist_ok=True)
        self.users_path = os.path.join(config.DATA_DIR, config.USERS_FILE)
        self.friends_path = os.path.join(config.DATA_DIR, config.FRIENDS_FILE)
        self.users = {}       # user_id -> {username, password_hash, created_at}
        self.friends = {}     # user_id -> {friend_id: status}  status: "pending"/"accepted"
        self.username_index = {}  # username -> user_id
        self._load()

    def _load(self):
        if os.path.exists(self.users_path):
            with open(self.users_path, "r", encoding="utf-8") as f:
                self.users = json.load(f)
            for uid, u in self.users.items():
                self.username_index[u["username"]] = uid
        if os.path.exists(self.friends_path):
            with open(self.friends_path, "r", encoding="utf-8") as f:
                self.friends = json.load(f)
        print(f"[DB] 已加载 {len(self.users)} 个用户, {len(self.friends)} 个好友关系")

    def reload(self):
        """热重载：从磁盘重新读取数据文件（不影响已在线用户的会话）"""
        old_users = len(self.users)
        old_friends = len(self.friends)
        # 清空索引后重建
        self.username_index.clear()
        self.users.clear()
        self.friends.clear()
        self._load()
        return {
            "users_before": old_users,
            "users_after": len(self.users),
            "friends_before": old_friends,
            "friends_after": len(self.friends),
        }

    def _save_users(self):
        with open(self.users_path, "w", encoding="utf-8") as f:
            json.dump(self.users, f, ensure_ascii=False, indent=2)

    def _save_friends(self):
        with open(self.friends_path, "w", encoding="utf-8") as f:
            json.dump(self.friends, f, ensure_ascii=False, indent=2)

    @staticmethod
    def _hash_password(password: str) -> str:
        return hashlib.sha256(password.encode("utf-8")).hexdigest()

    # ========== 用户管理 ==========
    def register_user(self, username: str, password: str, email: str = "") -> Optional[dict]:
        """注册用户，返回 user_info 或 None（用户名已存在）"""
        if username in self.username_index:
            return None
        user_id = str(uuid.uuid4())[:8]
        self.users[user_id] = {
            "username": username,
            "password_hash": self._hash_password(password),
            "email": email,
            "created_at": time.time()
        }
        self.username_index[username] = user_id
        self.friends[user_id] = {}
        self._save_users()
        self._save_friends()
        return {"user_id": user_id, "username": username}

    def login_user(self, username: str, password: str) -> Optional[dict]:
        """登录验证，返回 user_info 或 None"""
        user_id = self.username_index.get(username)
        if not user_id:
            return None
        user = self.users.get(user_id)
        if not user or user["password_hash"] != self._hash_password(password):
            return None
        return {"user_id": user_id, "username": username}

    def reset_password(self, username: str, email: str, new_password: str) -> bool:
        """重置密码，需要用户名和邮箱匹配，返回是否成功"""
        user_id = self.username_index.get(username)
        if not user_id:
            return False
        user = self.users.get(user_id)
        if not user or user.get("email", "") != email:
            return False
        user["password_hash"] = self._hash_password(new_password)
        self._save_users()
        return True

    def delete_user(self, username: str, password: str) -> bool:
        """删除账号（需验证密码），返回是否成功"""
        user_id = self.username_index.get(username)
        if not user_id:
            return False
        user = self.users.get(user_id)
        if not user or user["password_hash"] != self._hash_password(password):
            return False
        del self.users[user_id]
        del self.username_index[username]
        if user_id in self.friends:
            del self.friends[user_id]
        # 从其他用户的好友列表中移除
        for uid in self.friends:
            if username in self.friends[uid]:
                del self.friends[uid][username]
        self._save_users()
        self._save_friends()
        return True

    def get_user(self, user_id: str) -> Optional[dict]:
        user = self.users.get(user_id)
        if not user:
            return None
        return {"user_id": user_id, "username": user["username"]}

    def find_user_by_name(self, username: str) -> Optional[dict]:
        user_id = self.username_index.get(username)
        if not user_id:
            return None
        return self.get_user(user_id)

    def find_user_by_email(self, email: str) -> Optional[dict]:
        """按邮箱查找用户"""
        for uid, u in self.users.items():
            if u.get("email", "") == email:
                return {"user_id": uid, "username": u["username"]}
        return None

    def get_all_users(self) -> list:
        """列出所有注册用户"""
        result = []
        for uid, u in self.users.items():
            result.append({
                "user_id": uid,
                "username": u["username"],
                "email": u.get("email", ""),
                "created_at": u.get("created_at", 0)
            })
        return result

    # ========== 好友管理 ==========
    def add_friend_request(self, from_id: str, to_id: str) -> bool:
        """发送好友请求"""
        if from_id == to_id:
            return False
        if to_id not in self.friends:
            self.friends[to_id] = {}
        # 已经是好友或已有请求
        if from_id in self.friends.get(to_id, {}):
            return False
        self.friends[to_id][from_id] = "pending"
        self._save_friends()
        return True

    def accept_friend(self, user_id: str, friend_id: str) -> bool:
        """接受好友请求"""
        if friend_id not in self.friends.get(user_id, {}):
            return False
        if self.friends[user_id][friend_id] != "pending":
            return False
        # 双向建立好友关系
        self.friends[user_id][friend_id] = "accepted"
        if user_id not in self.friends:
            self.friends[user_id] = {}
        if friend_id not in self.friends:
            self.friends[friend_id] = {}
        self.friends[friend_id][user_id] = "accepted"
        self._save_friends()
        return True

    def decline_friend(self, user_id: str, friend_id: str) -> bool:
        """拒绝好友请求"""
        if friend_id not in self.friends.get(user_id, {}):
            return False
        del self.friends[user_id][friend_id]
        self._save_friends()
        return True

    def remove_friend(self, user_id: str, friend_id: str) -> bool:
        """删除好友（双向移除）"""
        removed = False
        if friend_id in self.friends.get(user_id, {}):
            del self.friends[user_id][friend_id]
            removed = True
        if user_id in self.friends.get(friend_id, {}):
            del self.friends[friend_id][user_id]
            removed = True
        if removed:
            self._save_friends()
        return removed

    def get_friends(self, user_id: str) -> list:
        """获取好友列表（已接受的）"""
        result = []
        for fid, status in self.friends.get(user_id, {}).items():
            if status == "accepted":
                friend = self.get_user(fid)
                if friend:
                    result.append(friend)
        return result

    def get_friend_requests(self, user_id: str) -> list:
        """获取收到的好友请求"""
        result = []
        for fid, status in self.friends.get(user_id, {}).items():
            if status == "pending":
                friend = self.get_user(fid)
                if friend:
                    result.append(friend)
        return result

    def are_friends(self, user_a: str, user_b: str) -> bool:
        return self.friends.get(user_a, {}).get(user_b) == "accepted"


# 全局单例
db = Database()
