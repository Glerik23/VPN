#!/usr/bin/env bash
# =============================================================================
# 12-update-geodata.sh — Автоматическое обновление GeoIP/GeoSite для Xray (3x-ui)
# =============================================================================
set -euo pipefail

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/root/xui-geodata-backup"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
XUI_DIR="/etc/x-ui/bin"

if [[ ! -d "$XUI_DIR" ]]; then
    # Если запущены через Docker, файлы могут храниться в volume
    # Пробуем найти пути внутри контейнера
    log "Попытка обновления баз внутри Docker контейнера 3x-ui..."
    if docker ps --format '{{.Names}}' | grep -q "^3x-ui$"; then
        docker exec 3x-ui bash -c "wget -O /usr/local/x-ui/bin/geoip.dat $GEOIP_URL && wget -O /usr/local/x-ui/bin/geosite.dat $GEOSITE_URL && wget -O /usr/local/x-ui/bin/v2ray-rules-dat/geoip.dat $GEOIP_URL && wget -O /usr/local/x-ui/bin/v2ray-rules-dat/geosite.dat $GEOSITE_URL"
        docker restart 3x-ui
        log "GeoData для 3x-ui успешно обновлена!"
        exit 0
    else
        err "Контейнер 3x-ui не найден и папка $XUI_DIR не существует."
    fi
fi

# Скачивание напрямую в систему (если установка Panel локальная)
mkdir -p "$BACKUP_DIR"
log "Скачивание актуальных баз данных GeoData..."

wget -q -O "/tmp/geoip.dat" "$GEOIP_URL" || err "Не удалось скачать geoip.dat"
wget -q -O "/tmp/geosite.dat" "$GEOSITE_URL" || err "Не удалось скачать geosite.dat"

# Замена с бэкапом
[[ -f "$XUI_DIR/geoip.dat" ]] && cp "$XUI_DIR/geoip.dat" "$BACKUP_DIR/geoip.dat.bak"
[[ -f "$XUI_DIR/geosite.dat" ]] && cp "$XUI_DIR/geosite.dat" "$BACKUP_DIR/geosite.dat.bak"

mv "/tmp/geoip.dat" "$XUI_DIR/"
mv "/tmp/geosite.dat" "$XUI_DIR/"

# Перезапуск службы Xray
if systemctl is-active --quiet x-ui; then
    systemctl restart x-ui
    log "GeoData успешно загружена, сервис x-ui перезапущен."
else
    warn "Не удалось найти службу x-ui. Возможно, Xray запущен иначе."
fi
