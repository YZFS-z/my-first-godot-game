@echo off
chcp 65001 >nul
echo ========================================
echo   公网联机大厅服务器启动
echo   启动后将自动探测公网IP
echo   交互式配置端口和邮件服务器
echo ========================================
echo.
python main.py
pause
