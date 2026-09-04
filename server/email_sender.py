"""
邮箱验证码发送模块
使用 SMTP 发送6位数字验证码
支持 SSL / STARTTLS / 无加密 三种连接方式
HTML + 纯文本 双部分邮件，兼容所有邮件客户端
"""
import smtplib
import random
import time
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional, Dict

import config

# 品牌常量
BRAND_NAME = "War Tank"
BRAND_NAME_CN = "坦克对战"
SUPPORT_EMAIL = "yzfs@thefeishu.top"
OFFICIAL_SITE = "game.thefeishu.top"


class EmailSender:
    def __init__(self, username: str, password: str,
                 smtp_host: str = None, smtp_port: int = None,
                 encryption: str = "ssl"):
        """
        初始化邮件发送器。

        Args:
            username: 发件邮箱地址
            password: 邮箱密码或授权码
            smtp_host: SMTP 服务器地址，默认取 config.SMTP_HOST
            smtp_port: SMTP 端口，默认取 config.SMTP_PORT
            encryption: 加密方式 "ssl" / "starttls" / "none"
        """
        self.username = username
        self.password = password
        self.smtp_host = smtp_host or config.SMTP_HOST
        self.smtp_port = smtp_port or config.SMTP_PORT
        self.encryption = encryption.lower()
        # 待验证的验证码: email -> {code, expire_at, username, action}
        self.pending_codes: Dict[str, dict] = {}

    def generate_code(self) -> str:
        """生成6位数字验证码"""
        return str(random.randint(100000, 999999))

    def _connect(self) -> smtplib.SMTP:
        """根据加密方式建立 SMTP 连接并登录"""
        if self.encryption == "ssl":
            server = smtplib.SMTP_SSL(self.smtp_host, self.smtp_port, timeout=15)
        elif self.encryption == "starttls":
            server = smtplib.SMTP(self.smtp_host, self.smtp_port, timeout=15)
            server.starttls()
        else:  # none
            server = smtplib.SMTP(self.smtp_host, self.smtp_port, timeout=15)
        server.login(self.username, self.password)
        return server

    def _get_action_meta(self, action: str) -> dict:
        """根据操作类型返回邮件元数据"""
        if action == "register":
            return {
                "subject": f"【{BRAND_NAME}】注册验证码 - 请完成账号注册",
                "title": "欢迎加入 {brand}".format(brand=BRAND_NAME),
                "heading": "注册验证码",
                "description": "您正在创建新的 {brand} 账号，请在注册页面输入以下验证码完成验证。".format(brand=BRAND_NAME),
                "cta": "完成注册",
            }
        else:
            return {
                "subject": f"【{BRAND_NAME}】密码重置验证码",
                "title": "密码重置",
                "heading": "重置密码验证码",
                "description": "您正在重置 {brand} 账号的登录密码，请在重置页面输入以下验证码。".format(brand=BRAND_NAME),
                "cta": "重置密码",
            }

    def _build_html_body(self, code: str, username: str, action: str) -> str:
        """构建专业 HTML 邮件正文（表格布局，兼容所有邮件客户端）"""
        meta = self._get_action_meta(action)
        display_name = username if username else "指挥官"
        year = time.strftime("%Y")

        return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{meta['subject']}</title>
</head>
<body style="margin:0; padding:0; background-color:#f0f2f5; font-family:'Helvetica Neue',Arial,'PingFang SC','Microsoft YaHei',sans-serif; -webkit-font-smoothing:antialiased;">
<!-- 外层容器 -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f0f2f5; padding:30px 15px;">
<tr>
<td align="center">
<!-- 主卡片 600px -->
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px; width:100%; background-color:#ffffff; border-radius:10px; overflow:hidden; box-shadow:0 2px 12px rgba(0,0,0,0.08);">

<!-- 品牌头部 -->
<tr>
<td style="background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%); padding:32px 40px 28px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
<tr>
<td>
<div style="font-size:24px; font-weight:bold; color:#ffffff; letter-spacing:1px;">{BRAND_NAME}</div>
<div style="font-size:13px; color:#a0aec0; margin-top:4px; letter-spacing:3px;">{BRAND_NAME_CN} · 在线对战</div>
</td>
<td align="right" style="font-size:12px; color:#718096; white-space:nowrap;">
<div style="display:inline-block; padding:4px 12px; border:1px solid #4a5568; border-radius:4px; color:#a0aec0;">系统邮件</div>
</td>
</tr>
</table>
</td>
</tr>

<!-- 分隔条 -->
<tr>
<td style="height:4px; background:linear-gradient(90deg,#f39c12,#e67e22);"></td>
</tr>

<!-- 正文区域 -->
<tr>
<td style="padding:36px 40px 32px;">
<!-- 称呼 -->
<div style="font-size:17px; color:#2d3436; margin-bottom:8px;">
尊敬的 <strong style="color:#1a1a2e;">{display_name}</strong>，您好：
</div>
<div style="font-size:14px; color:#636e72; line-height:1.7; margin-bottom:28px;">
{meta['description']}
</div>

<!-- 验证码区域 -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f8f9fa; border-radius:8px; border:1px solid #e9ecef; margin-bottom:24px;">
<tr>
<td align="center" style="padding:28px 20px;">
<div style="font-size:13px; color:#868e96; letter-spacing:2px; margin-bottom:12px;">您的验证码</div>
<div style="font-size:40px; font-weight:bold; color:#1a1a2e; letter-spacing:12px; font-family:'Courier New',monospace; line-height:1;">{code}</div>
<div style="font-size:12px; color:#adb5bd; margin-top:12px;">验证码有效期 10 分钟</div>
</td>
</tr>
</table>

<!-- 操作提示 -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:24px;">
<tr>
<td style="background-color:#fff8e1; border-left:4px solid #f39c12; padding:14px 18px; border-radius:0 6px 6px 0;">
<div style="font-size:13px; color:#856404; line-height:1.6;">
<strong>安全提示：</strong>验证码是账号安全的重要凭证，请勿向任何人透露，包括自称 {BRAND_NAME} 客服的人员。官方不会通过邮件、电话或聊天索要您的验证码。
</div>
</td>
</tr>
</table>

<!-- 操作步骤 -->
<div style="font-size:14px; color:#495057; line-height:1.8; margin-bottom:28px;">
<div style="margin-bottom:6px;">操作步骤：</div>
<div style="padding-left:20px;">
<div>1. 返回 {BRAND_NAME} 注册/重置页面</div>
<div>2. 在验证码输入框中填入上方 6 位数字</div>
<div>3. 完成后续操作即可</div>
</div>
</div>

<!-- 非本人操作提示 -->
<div style="font-size:13px; color:#868e96; line-height:1.6; padding-top:16px; border-top:1px solid #e9ecef;">
如果您没有进行此操作，请忽略本邮件。您的账号仍然安全，有人可能误输了您的邮箱地址。
</div>
</td>
</tr>

<!-- 页脚 -->
<tr>
<td style="background-color:#f8f9fa; padding:24px 40px; border-top:1px solid #e9ecef;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
<tr>
<td style="font-size:12px; color:#868e96; line-height:1.7;">
<div style="color:#495057; font-weight:bold; margin-bottom:4px;">{BRAND_NAME} {BRAND_NAME_CN}</div>
<div>官方网站：<a href="http://{OFFICIAL_SITE}" style="color:#495057; text-decoration:underline;">{OFFICIAL_SITE}</a></div>
<div>联系邮箱：<a href="mailto:{SUPPORT_EMAIL}" style="color:#495057; text-decoration:underline;">{SUPPORT_EMAIL}</a></div>
<div style="margin-top:8px; color:#adb5bd;">此邮件由系统自动发送，请勿直接回复。</div>
<div style="margin-top:4px; color:#adb5bd;">&copy; {year} {BRAND_NAME}. All rights reserved.</div>
</td>
</tr>
</table>
</td>
</tr>

</table>
<!-- /主卡片 -->
</td>
</tr>
</table>
<!-- /外层容器 -->
</body>
</html>"""

    def _build_text_body(self, code: str, username: str, action: str) -> str:
        """构建纯文本邮件正文（不支持 HTML 的邮件客户端使用）"""
        meta = self._get_action_meta(action)
        display_name = username if username else "指挥官"
        year = time.strftime("%Y")
        action_text = "注册账号" if action == "register" else "重置密码"

        return f"""{BRAND_NAME} ({BRAND_NAME_CN}) - {meta['heading']}
{'=' * 50}

尊敬的 {display_name}，您好：

您正在进行【{action_text}】操作。

您的验证码是：{code}

验证码有效期为 10 分钟，请尽快使用。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
安全提示：
验证码是账号安全的重要凭证，请勿向任何人透露，
包括自称 {BRAND_NAME} 客服的人员。官方不会通过邮件、
电话或聊天索要您的验证码。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

操作步骤：
1. 返回 {BRAND_NAME} 注册/重置页面
2. 在验证码输入框中填入上方 6 位数字
3. 完成后续操作即可

如果您没有进行此操作，请忽略本邮件。

--
官方网站：{OFFICIAL_SITE}
联系邮箱：{SUPPORT_EMAIL}
此邮件由系统自动发送，请勿直接回复。
© {year} {BRAND_NAME}. All rights reserved.
"""

    def send_verification_code(self, email: str, username: str = "", action: str = "register") -> bool:
        """发送验证码邮件（HTML + 纯文本双部分），返回是否成功"""
        code = self.generate_code()
        meta = self._get_action_meta(action)

        try:
            msg = MIMEMultipart("alternative")
            msg["From"] = f"{BRAND_NAME} <{self.username}>"
            msg["To"] = email
            msg["Subject"] = meta["subject"]
            msg["Reply-To"] = SUPPORT_EMAIL
            msg["X-Mailer"] = f"{BRAND_NAME} Server"

            # 纯文本版本（优先备选）
            text_part = MIMEText(self._build_text_body(code, username, action), "plain", "utf-8")
            # HTML 版本（主要显示）
            html_part = MIMEText(self._build_html_body(code, username, action), "html", "utf-8")

            msg.attach(text_part)
            msg.attach(html_part)

            with self._connect() as server:
                server.sendmail(self.username, [email], msg.as_string())

            # 保存验证码，10分钟过期
            self.pending_codes[email] = {
                "code": code,
                "expire_at": time.time() + 600,
                "username": username,
                "action": action,
            }
            print(f"[Email] 验证码已发送至 {email} ({action})")
            return True
        except Exception as e:
            print(f"[Email] 发送失败: {e}")
            return False

    def verify_code(self, email: str, code: str) -> bool:
        """验证验证码是否正确，正确则删除并返回True"""
        record = self.pending_codes.get(email)
        if not record:
            return False
        if time.time() > record["expire_at"]:
            del self.pending_codes[email]
            return False
        if record["code"] == code:
            del self.pending_codes[email]
            return True
        return False

    def cleanup_expired(self):
        """清理过期验证码"""
        now = time.time()
        expired = [e for e, r in self.pending_codes.items() if now > r["expire_at"]]
        for e in expired:
            del self.pending_codes[e]


# 全局单例（在main.py中初始化）
email_sender: Optional[EmailSender] = None
