#!/usr/bin/env bash
# ============= 09-setup-bot.sh =============
set -euo pipefail

info() { echo -e "\033[0;36m[i]\033[0m $1"; }
log()  { echo -e "\033[0;32m[✓]\033[0m $1"; }

info "Настройка окружения для бота..."
apt-get update && apt-get install -y python3-pip python3-venv
python3 -m venv /root/VPN/scripts/bot/venv
/root/VPN/scripts/bot/venv/bin/pip install psutil requests python-dotenv pyTelegramBotAPI

# Создание systemd сервиса для бота
cat > /etc/systemd/system/VPN-bot.service <<EOF
[Unit]
Description=VPN Monitoring Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/VPN/scripts/bot
ExecStart=/root/VPN/scripts/bot/venv/bin/python /root/VPN/scripts/bot/monitoring_bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable VPN-bot
systemctl restart VPN-bot
log "Сервис бота создан и добавлен в автозагрузку."
