"""
游戏服务器 - UDP状态同步
自定义可靠UDP协议（零依赖，Python标准库）
- 不可靠通道：输入、状态同步（30Hz，丢包可接受）
- 可靠通道：开火、命中、击毁等事件（ACK重传）
"""
import socket
import json
import time
import threading
import struct
from collections import defaultdict

# 协议常量
FLAG_UNRELIABLE = 0
FLAG_RELIABLE = 1
FLAG_ACK = 2

RELIABLE_TIMEOUT = 1.0  # 可靠消息重传超时（秒）
MAX_RETRANSMITS = 5
STATE_TICK_RATE = 30  # 状态广播频率 Hz


class GameInstance:
    """一个游戏房间实例"""

    def __init__(self, room_id: str, map_id: str, max_players: int = 8):
        self.room_id = room_id
        self.map_id = map_id
        self.max_players = max_players
        self.players = {}  # player_id -> {addr, username, team, vehicle_id, state, last_seen}
        self.ai_states = {}  # ai_id -> {position, rotation, turret_yaw, gun_pitch, health, destroyed}
        self.reliable_buffer = {}  # player_id -> {seq: (payload, send_time, retries)}
        self.next_seq = defaultdict(int)
        self.created_at = time.time()
        self.lock = threading.Lock()

    def add_player(self, player_id: str, addr, username: str, team: int, vehicle_id: str):
        with self.lock:
            self.players[player_id] = {
                "addr": addr,
                "username": username,
                "team": team,
                "vehicle_id": vehicle_id,
                "state": None,
                "last_seen": time.time(),
                "ready": False,
            }
            print(f"[Game:{self.room_id}] 玩家加入: {username} ({player_id}) 队伍{team}")

    def remove_player(self, player_id: str):
        with self.lock:
            if player_id in self.players:
                p = self.players.pop(player_id)
                print(f"[Game:{self.room_id}] 玩家离开: {p['username']} ({player_id})")
            if player_id in self.reliable_buffer:
                del self.reliable_buffer[player_id]

    def update_player_state(self, player_id: str, state: dict):
        with self.lock:
            if player_id in self.players:
                self.players[player_id]["state"] = state
                self.players[player_id]["last_seen"] = time.time()

    def update_ai_state(self, ai_states: list):
        """更新AI状态（由房主发送）"""
        with self.lock:
            for ai in ai_states:
                ai_id = ai.get("ai_id", "")
                if ai_id:
                    self.ai_states[ai_id] = ai

    def get_player_addrs(self, exclude_id: str = None) -> list:
        with self.lock:
            return [p["addr"] for pid, p in self.players.items() if pid != exclude_id]

    def get_state_broadcast(self) -> dict:
        """构建状态广播消息（包含玩家和AI状态）"""
        with self.lock:
            players_data = []
            for pid, p in self.players.items():
                if p["state"]:
                    players_data.append({
                        "player_id": pid,
                        "username": p["username"],
                        "team": p["team"],
                        "vehicle_id": p["vehicle_id"],
                        **p["state"],
                    })
            ai_data = list(self.ai_states.values())
            return {
                "type": "game_state",
                "room_id": self.room_id,
                "map_id": self.map_id,
                "players": players_data,
                "ai_states": ai_data,
                "timestamp": time.time(),
            }

    def is_empty(self) -> bool:
        with self.lock:
            return len(self.players) == 0

    def timeout_players(self, timeout: float = 30.0):
        """移除超时未响应的玩家"""
        now = time.time()
        with self.lock:
            to_remove = [pid for pid, p in self.players.items() if now - p["last_seen"] > timeout]
        for pid in to_remove:
            self.remove_player(pid)


class GameServer:
    """UDP游戏服务器"""

    def __init__(self, host: str = "0.0.0.0", port: int = 8765):
        self.host = host
        self.port = port
        self.sock = None
        self.games = {}  # room_id -> GameInstance
        self.addr_to_player = {}  # addr -> (room_id, player_id)
        self.running = False
        self.lock = threading.Lock()
        self._recv_buffer = {}  # addr -> bytes (for fragmented packets)
        self.reliable_buffer = {}  # addr -> {seq: (packet, send_time, retries)}
        self.next_seq = defaultdict(int)

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.host, self.port))
        self.sock.settimeout(0.1)
        self.running = True
        print(f"[GameServer] UDP游戏服务器已启动: {self.host}:{self.port}")

        # 状态广播线程
        broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
        broadcast_thread.start()

        # 可靠消息重传线程
        retransmit_thread = threading.Thread(target=self._retransmit_loop, daemon=True)
        retransmit_thread.start()

        # 主接收循环
        self._recv_loop()

    def stop(self):
        self.running = False
        if self.sock:
            self.sock.close()

    def create_game(self, room_id: str, map_id: str, max_players: int = 8):
        with self.lock:
            if room_id not in self.games:
                self.games[room_id] = GameInstance(room_id, map_id, max_players)
                print(f"[GameServer] 创建游戏实例: {room_id} 地图:{map_id}")

    def remove_game(self, room_id: str):
        with self.lock:
            if room_id in self.games:
                del self.games[room_id]
                print(f"[GameServer] 移除游戏实例: {room_id}")

    def _recv_loop(self):
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65536)
                self._handle_packet(data, addr)
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"[GameServer] 接收错误: {e}")

    def _handle_packet(self, data: bytes, addr):
        if len(data) < 1:
            return
        flag = data[0]
        payload = data[1:]

        if flag == FLAG_ACK:
            self._handle_ack(payload, addr)
            return

        try:
            msg = json.loads(payload.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return

        msg_type = msg.get("type", "")

        if flag == FLAG_RELIABLE:
            seq = msg.get("seq", 0)
            # 发送ACK
            self._send_ack(addr, seq)
            # 去重：如果已处理过则跳过
            # 简化处理：直接处理，状态更新是幂等的

        if msg_type == "game_join":
            self._handle_join(msg, addr)
        elif msg_type == "game_leave":
            self._handle_leave(msg, addr)
        elif msg_type == "game_input":
            self._handle_input(msg, addr)
        elif msg_type == "game_fire":
            self._handle_fire(msg, addr)
        elif msg_type == "game_hit":
            self._handle_hit(msg, addr)
        elif msg_type == "game_destroy":
            self._handle_destroy(msg, addr)
        elif msg_type == "game_chat":
            self._handle_chat(msg, addr)
        elif msg_type == "game_skill":
            self._handle_skill(msg, addr)
        elif msg_type == "game_state":
            # 客户端上报自己的状态
            self._handle_client_state(msg, addr)
        elif msg_type == "game_ai_state":
            # 房主上报AI状态
            self._handle_ai_state(msg, addr)
        elif msg_type == "game_foliage_destroy":
            # 植被破坏同步
            self._handle_foliage_destroy(msg, addr)

    def _handle_join(self, msg: dict, addr):
        room_id = msg.get("room_id", "")
        player_id = msg.get("player_id", "")
        username = msg.get("username", "玩家")
        team = msg.get("team", 1)
        vehicle_id = msg.get("vehicle_id", "tank_abrams")

        with self.lock:
            game = self.games.get(room_id)

        if not game:
            # 自动创建游戏实例
            self.create_game(room_id, msg.get("map_id", "map_desert"))
            with self.lock:
                game = self.games.get(room_id)

        if game:
            game.add_player(player_id, addr, username, team, vehicle_id)
            self.addr_to_player[addr] = (room_id, player_id)
            # 通知其他玩家有人加入
            self._broadcast_to_room(room_id, {
                "type": "game_player_joined",
                "player_id": player_id,
                "username": username,
                "team": team,
                "vehicle_id": vehicle_id,
            }, reliable=True, exclude_addr=addr)

    def _handle_leave(self, msg: dict, addr):
        room_id = msg.get("room_id", "")
        player_id = msg.get("player_id", "")
        with self.lock:
            game = self.games.get(room_id)
        if game:
            game.remove_player(player_id)
        if addr in self.addr_to_player:
            del self.addr_to_player[addr]
        # 通知其他玩家
        self._broadcast_to_room(room_id, {
            "type": "game_player_left",
            "player_id": player_id,
        }, reliable=True)

    def _handle_input(self, msg: dict, addr):
        """客户端输入：转发给房间内其他玩家"""
        room_id = msg.get("room_id", "")
        player_id = msg.get("player_id", "")
        with self.lock:
            game = self.games.get(room_id)
        if not game:
            return
        # 更新最后活跃时间
        if player_id in game.players:
            game.players[player_id]["last_seen"] = time.time()
        # 转发输入给其他玩家
        forward_msg = {
            "type": "game_input",
            "player_id": player_id,
            "throttle": msg.get("throttle", 0),
            "steering": msg.get("steering", 0),
            "turret": msg.get("turret", 0),
            "gun": msg.get("gun", 0),
            "fire": msg.get("fire", False),
        }
        self._broadcast_to_room(room_id, forward_msg, reliable=False, exclude_addr=addr)

    def _handle_client_state(self, msg: dict, addr):
        """客户端上报自己的载具状态"""
        room_id = msg.get("room_id", "")
        player_id = msg.get("player_id", "")
        with self.lock:
            game = self.games.get(room_id)
        if not game:
            return
        state = {
            "position": msg.get("position", [0, 0, 0]),
            "rotation": msg.get("rotation", [0, 0, 0]),
            "turret_yaw": msg.get("turret_yaw", 0),
            "gun_pitch": msg.get("gun_pitch", 0),
            "health": msg.get("health", 100),
            "velocity": msg.get("velocity", [0, 0, 0]),
        }
        game.update_player_state(player_id, state)

    def _handle_ai_state(self, msg: dict, addr):
        """房主上报AI状态"""
        room_id = msg.get("room_id", "")
        ai_states = msg.get("ai_states", [])
        with self.lock:
            game = self.games.get(room_id)
        if not game:
            return
        game.update_ai_state(ai_states)

    def _handle_fire(self, msg: dict, addr):
        """开火事件：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _handle_hit(self, msg: dict, addr):
        """命中事件：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _handle_foliage_destroy(self, msg: dict, addr):
        """植被破坏同步：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _handle_destroy(self, msg: dict, addr):
        """击毁事件：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _handle_chat(self, msg: dict, addr):
        """局内聊天：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _handle_skill(self, msg: dict, addr):
        """技能释放（火炮/烟幕）：可靠广播"""
        room_id = msg.get("room_id", "")
        self._broadcast_to_room(room_id, msg, reliable=True, exclude_addr=addr)

    def _broadcast_to_room(self, room_id: str, msg: dict, reliable: bool = False, exclude_addr=None):
        with self.lock:
            game = self.games.get(room_id)
        if not game:
            return
        addrs = game.get_player_addrs()
        for addr in addrs:
            if exclude_addr and addr == exclude_addr:
                continue
            self._sendto(msg, addr, reliable)

    def _sendto(self, msg: dict, addr, reliable: bool = False):
        try:
            payload = json.dumps(msg, separators=(",", ":")).encode("utf-8")
            if reliable:
                seq = self._next_seq_for_addr(addr)
                msg_with_seq = dict(msg)
                msg_with_seq["seq"] = seq
                payload = json.dumps(msg_with_seq, separators=(",", ":")).encode("utf-8")
                packet = bytes([FLAG_RELIABLE]) + payload
                # 存入重传缓冲区
                with self.lock:
                    if addr not in self.reliable_buffer:
                        self.reliable_buffer[addr] = {}
                    self.reliable_buffer[addr][seq] = (packet, time.time(), 0)
            else:
                packet = bytes([FLAG_UNRELIABLE]) + payload
            self.sock.sendto(packet, addr)
        except Exception as e:
            print(f"[GameServer] 发送错误: {e}")

    def _next_seq_for_addr(self, addr) -> int:
        key = f"{addr[0]}:{addr[1]}"
        seq = self.next_seq[key]
        self.next_seq[key] += 1
        return seq

    def _send_ack(self, addr, seq: int):
        try:
            packet = bytes([FLAG_ACK]) + struct.pack("!I", seq)
            self.sock.sendto(packet, addr)
        except Exception:
            pass

    def _handle_ack(self, payload: bytes, addr):
        if len(payload) < 4:
            return
        seq = struct.unpack("!I", payload[:4])[0]
        with self.lock:
            if addr in self.reliable_buffer and seq in self.reliable_buffer[addr]:
                del self.reliable_buffer[addr][seq]

    def _broadcast_loop(self):
        """30Hz状态广播"""
        interval = 1.0 / STATE_TICK_RATE
        while self.running:
            start = time.time()
            with self.lock:
                games = list(self.games.values())
            for game in games:
                if game.is_empty():
                    continue
                state_msg = game.get_state_broadcast()
                addrs = game.get_player_addrs()
                for addr in addrs:
                    self._sendto(state_msg, addr, reliable=False)
            # 清理超时玩家和空房间
            for game in games:
                game.timeout_players()
                if game.is_empty() and time.time() - game.created_at > 60:
                    self.remove_game(game.room_id)
            # 控制频率
            elapsed = time.time() - start
            sleep_time = max(0, interval - elapsed)
            time.sleep(sleep_time)

    def _retransmit_loop(self):
        """可靠消息重传"""
        while self.running:
            time.sleep(0.2)
            now = time.time()
            with self.lock:
                to_retransmit = []
                for addr, msgs in self.reliable_buffer.items():
                    for seq, (packet, send_time, retries) in list(msgs.items()):
                        if now - send_time > RELIABLE_TIMEOUT:
                            if retries >= MAX_RETRANSMITS:
                                del msgs[seq]
                            else:
                                to_retransmit.append((addr, packet, seq, retries))
            for addr, packet, seq, retries in to_retransmit:
                try:
                    self.sock.sendto(packet, addr)
                    with self.lock:
                        if addr in self.reliable_buffer and seq in self.reliable_buffer[addr]:
                            self.reliable_buffer[addr][seq] = (packet, now, retries + 1)
                except Exception:
                    pass


# 单例
_game_server = None


def get_game_server(host: str = "0.0.0.0", port: int = 8765) -> GameServer:
    global _game_server
    if _game_server is None:
        _game_server = GameServer(host, port)
    return _game_server
