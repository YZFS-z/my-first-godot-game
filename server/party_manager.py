"""
组队管理器
邀请、接受、离开组队
组队可以一起加入房间
"""
import uuid
import time
from typing import Optional


class Party:
    def __init__(self, party_id: str, leader_id: str, leader_name: str):
        self.party_id = party_id
        self.leader_id = leader_id
        self.members = {leader_id: {"username": leader_name, "ready": False}}
        self.created_at = time.time()
        self.invites = {}  # invitee_id -> inviter_id (待处理的邀请)

    def add_member(self, user_id: str, username: str) -> bool:
        if user_id in self.members:
            return False
        self.members[user_id] = {"username": username, "ready": False}
        return True

    def remove_member(self, user_id: str):
        if user_id in self.members:
            del self.members[user_id]

    def is_empty(self) -> bool:
        return len(self.members) == 0

    def is_leader(self, user_id: str) -> bool:
        return self.leader_id == user_id

    def to_info(self) -> dict:
        return {
            "party_id": self.party_id,
            "leader_id": self.leader_id,
            "members": [
                {"user_id": uid, **info}
                for uid, info in self.members.items()
            ]
        }


class PartyManager:
    def __init__(self):
        self.parties = {}  # party_id -> Party
        self.user_party = {}  # user_id -> party_id
        self.pending_invites = {}  # invitee_id -> {party_id, inviter_id, inviter_name}

    def create_party(self, leader_id: str, leader_name: str) -> Party:
        """创建组队（如果已有组队则返回现有组队）"""
        existing = self.get_user_party(leader_id)
        if existing:
            return existing
        party_id = str(uuid.uuid4())[:8]
        party = Party(party_id, leader_id, leader_name)
        self.parties[party_id] = party
        self.user_party[leader_id] = party_id
        return party

    def invite(self, inviter_id: str, invitee_id: str, inviter_name: str) -> tuple:
        """邀请玩家加入组队"""
        party = self.get_user_party(inviter_id)
        if not party:
            # 邀请者没有组队，自动创建
            party = self.create_party(inviter_id, inviter_name)
        if not party.is_leader(inviter_id):
            return False, "只有队长可以邀请", None
        if invitee_id in party.members:
            return False, "玩家已在组队中", None
        if invitee_id in self.user_party:
            return False, "玩家已在其他组队中", None

        self.pending_invites[invitee_id] = {
            "party_id": party.party_id,
            "inviter_id": inviter_id,
            "inviter_name": inviter_name
        }
        return True, "邀请已发送", party

    def accept_invite(self, user_id: str, username: str, party_id: str) -> tuple:
        """接受组队邀请"""
        invite = self.pending_invites.get(user_id)
        if not invite or invite["party_id"] != party_id:
            return False, "邀请不存在或已过期", None
        if user_id in self.user_party:
            return False, "你已在组队中，请先离开", None

        party = self.parties.get(party_id)
        if not party:
            return False, "组队不存在", None

        party.add_member(user_id, username)
        self.user_party[user_id] = party_id
        del self.pending_invites[user_id]
        return True, "已加入组队", party

    def decline_invite(self, user_id: str, party_id: str) -> bool:
        """拒绝组队邀请"""
        invite = self.pending_invites.get(user_id)
        if invite and invite["party_id"] == party_id:
            del self.pending_invites[user_id]
            return True
        return False

    def leave_party(self, user_id: str) -> Optional[Party]:
        """离开组队"""
        party_id = self.user_party.get(user_id)
        if not party_id:
            return None
        party = self.parties.get(party_id)
        if party:
            party.remove_member(user_id)
            # 如果队长离开，转移队长或解散
            if party.is_leader(user_id):
                if party.members:
                    party.leader_id = next(iter(party.members.keys()))
                else:
                    del self.parties[party_id]
        if user_id in self.user_party:
            del self.user_party[user_id]
        return party

    def promote_leader(self, current_leader: str, new_leader: str) -> tuple:
        """提升新队长"""
        party = self.get_user_party(current_leader)
        if not party:
            return False, "不在组队中"
        if not party.is_leader(current_leader):
            return False, "只有队长可以提升"
        if new_leader not in party.members:
            return False, "玩家不在组队中"
        party.leader_id = new_leader
        return True, "已提升队长"

    def get_user_party(self, user_id: str) -> Optional[Party]:
        party_id = self.user_party.get(user_id)
        if party_id:
            return self.parties.get(party_id)
        return None

    def get_pending_invite(self, user_id: str) -> Optional[dict]:
        return self.pending_invites.get(user_id)

    def set_member_ready(self, user_id: str, ready: bool):
        party = self.get_user_party(user_id)
        if party and user_id in party.members:
            party.members[user_id]["ready"] = ready

    def cleanup_empty_parties(self):
        """清理空组队"""
        to_remove = [pid for pid, p in self.parties.items() if p.is_empty()]
        for pid in to_remove:
            del self.parties[pid]


# 全局单例
party_manager = PartyManager()
