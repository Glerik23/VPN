#!/usr/bin/env bash
# ============= 09-setup-bot.sh =============
set -euo pipefail

info() { echo -e "\033[0;36m[i]\033[0m $1"; }
log()  { echo -e "\033[0;32m[✓]\033[0m $1"; }

info "Налаштування оточення для бота..."
apt-get update && apt-get install -y python3-pip python3-venv
python3 -m venv /root/vpn/scripts/bot/venv
/root/vpn/scripts/bot/venv/bin/pip install psutil requests python-dotenv

# Створення systemd сервісу для бота
cat > /etc/systemd/system/vpn-bot.service <<EOF
[Unit]
Description=VPN Monitoring Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vpn/scripts/bot
ExecStart=/root/vpn/scripts/bot/venv/bin/python /root/vpn/scripts/bot/monitoring_bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-bot
log "Сервіс бота створено та додано в автозавантаження."
