"""
公网联机大厅服务器
Python 3.10+，仅使用标准库
启动: python main.py
通过内网穿透映射 game.thefeishu.top -> 本机:8765
"""
import asyncio
import signal
import time
import threading
import sys
import getpass
import socket
import urllib.request
import json
import importlib

import config
import protocol
import email_sender
from database import db
from room_manager import room_manager
from party_manager import party_manager
from client_handler import ClientHandler
from game_server import GameServer
from email_sender import EmailSender


# ============================================================
#  工具函数
# ============================================================

def detect_public_ip(timeout: float = 3.0) -> str:
    """
    探测本机公网 IP 地址。
    依次尝试多个公共服务，全部失败则返回空字符串。
    """
    services = [
        ("https://api.ipify.org", "text"),
        ("https://ifconfig.me/ip", "text"),
        ("https://icanhazip.com", "text"),
        ("https://api.ipify.org?format=json", "json"),
    ]
    for url, fmt in services:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "curl/7.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8").strip()
                if fmt == "json":
                    data = json.loads(raw)
                    ip = data.get("ip", "")
                else:
                    ip = raw
                # 简单校验
                if ip and ":" not in ip and ip.count(".") == 3:
                    return ip
        except Exception:
            continue
    return ""


def detect_local_ips() -> list:
    """获取本机所有非回环 IPv4 地址"""
    ips = []
    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            ip = info[4][0]
            if "." in ip and not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    # 备用方法：连接外部地址获取出口 IP（不实际发送数据）
    if not ips:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ips.append(s.getsockname()[0])
            s.close()
        except Exception:
            pass
    return ips


def prompt_choice(prompt: str, choices: list, default: str = "") -> str:
    """
    带编号的选择输入。choices 为 [(key, label), ...]，返回选中的 key。
    直接回车返回 default。
    """
    while True:
        print(prompt)
        for i, (key, label) in enumerate(choices, 1):
            marker = " (默认)" if key == default else ""
            print(f"    {i}. {label}{marker}")
        raw = input("  选择: ").strip()
        if raw == "" and default:
            return default
        try:
            idx = int(raw) - 1
            if 0 <= idx < len(choices):
                return choices[idx][0]
        except ValueError:
            pass
        # 也支持直接输入 key
        for key, _ in choices:
            if raw.lower() == key.lower():
                return key
        print("  × 无效选择，请重新输入")


# ============================================================
#  管理控制台
# ============================================================

# 命令帮助文本（分类）
CMD_HELP = """
  服务器管理命令（输入 help 或 ? 再次显示此帮助）:

  [状态]
    status            显示服务器运行状态（运行时长/在线/房间/注册数）
    list              列出所有注册用户
    online            列出当前在线用户
    rooms             列出当前房间

  [用户管理]
    kick <用户名>     踢下线指定用户
    delete <用户名>   删除指定账号（管理员操作，无需密码）

  [热重载]
    reload data       重新读取 users.json / friends.json
    reload config     重载 config 模块并重建邮件发送器
    reload email      重建邮件发送器
    reload module <名> 重载指定代码模块（实验性）
    reload all        重载 data + config + email
    reload help       显示热重载详细用法

  [系统]
    clear             清屏
    help / ?          显示此帮助
    quit / exit       关闭服务器
"""

PROMPT = "server> "


def _print_prompt():
    """打印输入提示符（不换行，立即刷新）"""
    print(PROMPT, end="", flush=True)


def admin_console(loop, server, stop_event):
    """后台线程：服务器命令行管理控制台"""
    start_time = time.time()
    time.sleep(1.5)  # 等服务器启动输出完成
    print("\n[管理控制台] 服务器已就绪，输入 help 查看可用命令")
    _print_prompt()

    while not stop_event.is_set():
        try:
            line = sys.stdin.readline()
            if not line:
                break
            cmd = line.strip()
            if not cmd:
                _print_prompt()
                continue

            parts = cmd.split(maxsplit=1)
            action = parts[0].lower()
            arg = parts[1] if len(parts) > 1 else ""

            if action in ("help", "?"):
                print(CMD_HELP)

            elif action == "status":
                uptime_secs = int(time.time() - start_time)
                hours, remainder = divmod(uptime_secs, 3600)
                minutes, seconds = divmod(remainder, 60)
                uptime_str = f"{hours}时{minutes}分{seconds}秒" if hours > 0 else f"{minutes}分{seconds}秒"
                rooms = room_manager.get_all_rooms()
                total_players_in_rooms = sum(len(r.players) for r in rooms)
                print()
                print("  ┌─ 服务器状态 ─────────────────────────────")
                print(f"  │ 运行时长:   {uptime_str}")
                print(f"  │ 监听端口:   {config.PORT} (TCP大厅 + UDP游戏)")
                print(f"  │ 注册用户:   {len(db.users)}")
                print(f"  │ 在线用户:   {len(server.clients)}")
                print(f"  │ 活跃房间:   {len(rooms)} (共 {total_players_in_rooms} 名玩家在房间中)")
                print(f"  │ 邮箱验证:   {'已启用' if email_sender.email_sender else '已禁用'}")
                print("  └──────────────────────────────────────────")
                print()

            elif action == "list":
                users = db.get_all_users()
                if not users:
                    print("  (无注册用户)")
                else:
                    print(f"\n  共 {len(users)} 个注册用户:")
                    for u in users:
                        email = u.get("email", "") or "(未绑定邮箱)"
                        online = " [在线]" if server.get_client_by_user(u.get("user_id", "")) else ""
                        print(f"    - {u['username']} (ID: {u['user_id']}, 邮箱: {email}){online}")
                    print()

            elif action == "delete":
                if not arg:
                    print("  用法: delete <用户名>")
                    _print_prompt()
                    continue
                username = arg.strip()
                user = db.find_user_by_name(username)
                if not user:
                    print(f"  × 用户 '{username}' 不存在")
                    _print_prompt()
                    continue
                user_id = user["user_id"]
                if user_id in db.users:
                    del db.users[user_id]
                if username in db.username_index:
                    del db.username_index[username]
                if user_id in db.friends:
                    del db.friends[user_id]
                for uid in db.friends:
                    if username in db.friends[uid]:
                        del db.friends[uid][username]
                db._save_users()
                db._save_friends()
                client = server.get_client_by_user(user_id)
                if client:
                    loop.call_soon_threadsafe(client.close)
                    server.remove_client(client)
                    print(f"  ✓ 已删除用户 '{username}' 并踢下线")
                else:
                    print(f"  ✓ 已删除用户 '{username}'")

            elif action == "online":
                if not server.clients:
                    print("  (无在线用户)")
                else:
                    print(f"\n  在线用户 ({len(server.clients)}):")
                    for uid, c in server.clients.items():
                        # 显示用户所在房间
                        in_room = ""
                        for r in room_manager.get_all_rooms():
                            if uid in r.players:
                                in_room = f" | 房间: {r.name or r.room_id}"
                                break
                        print(f"    - {c.username} (ID: {uid}){in_room}")
                    print()

            elif action == "kick":
                if not arg:
                    print("  用法: kick <用户名>")
                    _print_prompt()
                    continue
                username = arg.strip()
                kicked = False
                for uid, c in list(server.clients.items()):
                    if c.username == username:
                        loop.call_soon_threadsafe(c.close)
                        server.remove_client(c)
                        print(f"  ✓ 已踢下线 '{username}'")
                        kicked = True
                        break
                if not kicked:
                    print(f"  × 用户 '{username}' 不在线")

            elif action == "rooms":
                rooms = room_manager.get_all_rooms()
                if not rooms:
                    print("  (无房间)")
                else:
                    print(f"\n  房间列表 ({len(rooms)}):")
                    for r in rooms:
                        players = r.players
                        player_names = ", ".join(
                            server.get_client_by_user(uid).username if server.get_client_by_user(uid) else uid
                            for uid in players.keys()
                        ) or "(空)"
                        print(f"    - {r.room_id} | {r.name} | {len(players)}人 | 地图: {r.map_id} | {'游戏中' if r.in_game else '等待中'}")
                        print(f"        玩家: {player_names}")
                    print()

            elif action == "reload":
                sub = arg.strip().lower()
                if not sub or sub == "help":
                    print("\n  热重载命令:")
                    print("    reload data          重新读取 users.json / friends.json")
                    print("    reload config        重载 config 模块并重建邮件发送器")
                    print("    reload email         重建邮件发送器（使用当前配置）")
                    print("    reload module <名>   重载指定代码模块（仅新连接生效，实验性）")
                    print("    reload all           重载 data + config + email")
                    print()

                elif sub == "data":
                    result = db.reload()
                    print(f"  ✓ 数据已重载: 用户 {result['users_before']}→{result['users_after']}, "
                          f"好友 {result['friends_before']}→{result['friends_after']}")

                elif sub == "config":
                    try:
                        importlib.reload(config)
                        print(f"  ✓ config 已重载 (端口={config.PORT}, 邮件={config.EMAIL_USERNAME})")
                        # 重建邮件发送器
                        if email_sender.email_sender:
                            old_pw = email_sender.email_sender.password
                            email_sender.email_sender = EmailSender(
                                config.EMAIL_USERNAME, old_pw,
                                smtp_host=config.SMTP_HOST,
                                smtp_port=config.SMTP_PORT,
                                encryption=config.SMTP_ENCRYPTION
                            )
                            print("  ✓ 邮件发送器已重建（沿用原密码）")
                    except Exception as e:
                        print(f"  × 重载 config 失败: {e}")

                elif sub == "email":
                    if email_sender.email_sender:
                        old_pw = email_sender.email_sender.password
                        email_sender.email_sender = EmailSender(
                            config.EMAIL_USERNAME, old_pw,
                            smtp_host=config.SMTP_HOST,
                            smtp_port=config.SMTP_PORT,
                            encryption=config.SMTP_ENCRYPTION
                        )
                        print("  ✓ 邮件发送器已重建")
                    else:
                        print("  - 邮件验证未启用，无需重建")

                elif sub.startswith("module "):
                    mod_name = sub[7:].strip()
                    if mod_name not in sys.modules:
                        print(f"  × 模块 '{mod_name}' 未加载")
                    else:
                        try:
                            importlib.reload(sys.modules[mod_name])
                            print(f"  ✓ 模块 '{mod_name}' 已重载（新连接生效，已有连接保持旧代码）")
                        except Exception as e:
                            print(f"  × 重载模块 '{mod_name}' 失败: {e}")

                elif sub == "all":
                    # data
                    r = db.reload()
                    print(f"  ✓ 数据重载: 用户 {r['users_before']}→{r['users_after']}")
                    # config
                    try:
                        importlib.reload(config)
                        print(f"  ✓ config 重载")
                    except Exception as e:
                        print(f"  × config 重载失败: {e}")
                    # email
                    if email_sender.email_sender:
                        old_pw = email_sender.email_sender.password
                        email_sender.email_sender = EmailSender(
                            config.EMAIL_USERNAME, old_pw,
                            smtp_host=config.SMTP_HOST,
                            smtp_port=config.SMTP_PORT,
                            encryption=config.SMTP_ENCRYPTION
                        )
                        print("  ✓ 邮件发送器重建")
                    print("  ✓ 全部重载完成")

                else:
                    print(f"  × 未知重载目标: '{sub}'，输入 reload help 查看用法")

            elif action == "clear":
                print("\033[2J\033[H", end="")

            elif action in ("quit", "exit", "stop"):
                print("  正在关闭服务器...")
                loop.call_soon_threadsafe(stop_event.set)
                break

            else:
                print(f"  × 未知命令: '{action}'，输入 help 查看可用命令")

            _print_prompt()

        except Exception as e:
            print(f"  [管理控制台错误] {e}")
            _print_prompt()


# ============================================================
#  大厅服务器
# ============================================================

class LobbyServer:
    def __init__(self):
        self.clients = {}  # user_id -> ClientHandler
        self.server = None
        self._cleanup_task = None
        self.game_server = None
        self._game_server_thread = None

    def add_client(self, client: ClientHandler):
        self.clients[client.user_id] = client

    def remove_client(self, client: ClientHandler):
        # 按对象身份判断，防止旧连接断开时删掉新登录的同账号客户端
        if self.clients.get(client.user_id) is client:
            del self.clients[client.user_id]

    def get_client_by_user(self, user_id: str):
        return self.clients.get(user_id)

    async def broadcast_room(self, room, msg_type: str, data: dict):
        """向房间内所有玩家广播"""
        for uid in list(room.players.keys()):
            client = self.get_client_by_user(uid)
            if client:
                await client.send(protocol.make_message(msg_type, data))

    async def broadcast_room_info(self, room):
        """广播房间最新信息"""
        if room:
            await self.broadcast_room(room, protocol.ROOM_INFO, room.to_full_info())

    async def broadcast_room_event(self, room, msg_type: str, data: dict):
        """广播房间事件（玩家加入/离开等）"""
        await self.broadcast_room(room, msg_type, data)

    async def broadcast_party(self, party, msg_type: str, data: dict):
        """向组队内所有成员广播"""
        for uid in list(party.members.keys()):
            client = self.get_client_by_user(uid)
            if client:
                await client.send(protocol.make_message(msg_type, data))

    async def broadcast_party_info(self, party):
        if party:
            await self.broadcast_party(party, protocol.PARTY_INFO_RESULT, party.to_info())

    async def broadcast_party_event(self, party, msg_type: str, data: dict):
        await self.broadcast_party(party, msg_type, data)

    async def notify_friends_status(self, user_id: str, online: bool):
        """通知该用户的所有好友上下线"""
        friends = db.get_friends(user_id)
        msg_type = protocol.FRIEND_ONLINE if online else protocol.FRIEND_OFFLINE
        for f in friends:
            client = self.get_client_by_user(f["user_id"])
            if client:
                await client.send(protocol.make_message(msg_type, {"user_id": user_id}))

    async def _cleanup_loop(self):
        """定期清理空房间、空组队、超时连接"""
        while True:
            await asyncio.sleep(60)
            room_manager.cleanup_empty_rooms()
            party_manager.cleanup_empty_parties()
            # 检查心跳超时
            now = time.time()
            to_remove = []
            for uid, client in self.clients.items():
                if now - client.last_heartbeat > config.HEARTBEAT_TIMEOUT:
                    print(f"[Server] 心跳超时: {client.username}")
                    to_remove.append(client)
            for client in to_remove:
                client.writer.close()

    async def handle_connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        handler = ClientHandler(reader, writer, self)
        await handler.handle()

    async def start(self, public_ip: str = "", local_ips: list = None):
        # 启动UDP游戏服务器（独立线程）
        self.game_server = GameServer(config.HOST, config.GAME_PORT)
        self._game_server_thread = threading.Thread(target=self.game_server.start, daemon=True)
        self._game_server_thread.start()

        self.server = await asyncio.start_server(
            self.handle_connection,
            config.HOST,
            config.LOBBY_PORT
        )
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())

        local_ips = local_ips or []
        print("=" * 55)
        print("  公网联机服务器 已启动")
        print(f"  监听地址: {config.HOST}:{config.PORT}")
        print(f"  TCP大厅:  {config.HOST}:{config.PORT}")
        print(f"  UDP游戏:  {config.HOST}:{config.PORT}")
        if public_ip:
            print(f"  公网IP:   {public_ip}:{config.PORT}")
        if local_ips:
            for ip in local_ips:
                print(f"  内网IP:   {ip}:{config.PORT}")
        print(f"  公网域名: {config.PUBLIC_HOST}:{config.PORT}")
        print(f"  已注册用户: {len(db.users)}")
        email_status = "已启用" if email_sender.email_sender else "已禁用"
        print(f"  邮箱验证: {email_status}")
        print("=" * 55)
        print("  按 Ctrl+C 停止服务器")
        print("=" * 55)

        async with self.server:
            await self.server.serve_forever()

    async def stop(self):
        print("\n[Server] 正在停止...")
        if self._cleanup_task:
            self._cleanup_task.cancel()
        # 关闭所有客户端连接
        for client in list(self.clients.values()):
            client.writer.close()
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        if self.game_server:
            self.game_server.stop()
        print("[Server] 已停止")


# ============================================================
#  启动配置
# ============================================================

async def main():
    print("=" * 55)
    print("  公网联机大厅服务器 - 启动配置")
    print("=" * 55)

    # ── 预探测网络信息 ──
    print("  正在探测网络信息...", end="", flush=True)
    public_ip = detect_public_ip()
    local_ips = detect_local_ips()
    print(" 完成")
    if public_ip:
        print(f"  检测到公网IP: {public_ip}")
    else:
        print("  未能自动检测公网IP（可能在NAT后或无外网）")
    if local_ips:
        print(f"  检测到内网IP: {', '.join(local_ips)}")
    print("-" * 55)

    # ── 1. 端口配置 ──
    default_port = config.PORT
    print()
    print("  [1/3] 监听端口配置")
    print("    · TCP 大厅与 UDP 游戏数据共用同一个端口")
    print("    · 云服务器需在安全组/防火墙中放行该端口（TCP + UDP）")
    print("    · 端口范围 1-65535，直接回车使用默认值")
    print()
    while True:
        port_input = input(f"    端口号 (默认 {default_port}, 回车使用默认): ").strip()
        if port_input == "":
            port = default_port
            break
        try:
            port = int(port_input)
            if 1 <= port <= 65535:
                break
            else:
                print("    × 端口号必须在 1-65535 之间")
        except ValueError:
            print("    × 请输入有效的数字端口号")

    config.PORT = port
    config.LOBBY_PORT = port
    config.GAME_PORT = port
    print(f"  ✓ 使用端口: {port}")

    # ── 2. 邮件服务器配置 ──
    print()
    print("  [2/3] 邮件服务器配置")
    print(f"    · 默认使用配置文件中的邮件服务器: {config.SMTP_HOST}:{config.SMTP_PORT} ({config.SMTP_ENCRYPTION.upper()})")
    print("    · 如需使用其他邮箱（QQ/163/Gmail等），输入 y 自定义 SMTP 地址、端口和加密方式")
    print("    · 直接回车或输入 n 使用默认配置")
    print()
    customize_email = input(f"    是否自定义邮件服务器？(y/N): ").strip().lower()
    if customize_email in ("y", "yes"):
        # SMTP 主机
        smtp_host = input(f"    SMTP服务器地址 (默认 {config.SMTP_HOST}): ").strip()
        if smtp_host:
            config.SMTP_HOST = smtp_host

        # 加密方式
        enc = prompt_choice(
            "    加密方式:",
            [("ssl", "SSL (端口465)"), ("starttls", "STARTTLS (端口587)"), ("none", "无加密 (端口25)")],
            default=config.SMTP_ENCRYPTION
        )
        config.SMTP_ENCRYPTION = enc
        default_smtp_port = {"ssl": 465, "starttls": 587, "none": 25}.get(enc, config.SMTP_PORT)

        # SMTP 端口
        port_input = input(f"    SMTP端口 (默认 {default_smtp_port}): ").strip()
        if port_input:
            try:
                config.SMTP_PORT = int(port_input)
            except ValueError:
                print(f"    × 无效端口，使用默认 {default_smtp_port}")
                config.SMTP_PORT = default_smtp_port
        else:
            config.SMTP_PORT = default_smtp_port

        # 邮箱用户名
        email_user = input(f"    发件邮箱 (默认 {config.EMAIL_USERNAME}): ").strip()
        if email_user:
            config.EMAIL_USERNAME = email_user

        print(f"    ✓ 邮件服务器: {config.SMTP_HOST}:{config.SMTP_PORT} ({config.SMTP_ENCRYPTION.upper()})")
        print(f"    ✓ 发件邮箱: {config.EMAIL_USERNAME}")
    else:
        print(f"    使用配置文件: {config.SMTP_HOST}:{config.SMTP_PORT} ({config.SMTP_ENCRYPTION.upper()})")
        print(f"    发件邮箱: {config.EMAIL_USERNAME}")

    # ── 3. 邮箱密码（getpass 隐藏输入）──
    print()
    print("  [3/3] 邮箱密码配置")
    print("    · 请输入邮箱的 SMTP 密码或授权码（部分邮箱需在设置中开启 SMTP 并生成授权码）")
    print("    · 输入时屏幕不会显示字符，以保护密码安全")
    print("    · 直接按回车可跳过，跳过则注册/重置密码无需邮箱验证码")
    print()
    email_password = getpass.getpass(
        f"    邮箱 {config.EMAIL_USERNAME} 的 SMTP 密码/授权码 (回车跳过): "
    )
    if email_password:
        email_sender.email_sender = EmailSender(
            config.EMAIL_USERNAME, email_password,
            smtp_host=config.SMTP_HOST,
            smtp_port=config.SMTP_PORT,
            encryption=config.SMTP_ENCRYPTION
        )
        print("  ✓ 邮箱验证已启用")
    else:
        email_sender.email_sender = None
        print("  - 邮箱验证已禁用（注册/重置无需验证码）")

    print("=" * 55)
    print("  服务器启动中...")
    print("=" * 55)

    server = LobbyServer()

    # 处理退出信号
    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    # 启动命令行管理控制台（后台线程）
    admin_thread = threading.Thread(target=admin_console, args=(loop, server, stop_event), daemon=True)
    admin_thread.start()

    def signal_handler():
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, signal_handler)
        except NotImplementedError:
            # Windows 不支持 add_signal_handler
            pass

    try:
        await server.start(public_ip=public_ip, local_ips=local_ips)
    except KeyboardInterrupt:
        pass
    finally:
        await server.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
