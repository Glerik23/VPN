#!/usr/bin/env bash
# =============================================================================
# 08-setup-inbound.sh — Автоматическая настройка 3x-ui через API
# Создает VLESS + Reality inbound на порту 443 используя данные из .env
# =============================================================================
set -euo pipefail

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOTENV="$PROJECT_DIR/.env"

[[ ! -f "$DOTENV" ]] && err "Файл .env не найден"
source "$DOTENV"

# Параметры API
PANEL_URL="http://localhost:${XUI_PORT:-2053}"
USERNAME="${XUI_USERNAME:-admin}"
PASSWORD="${XUI_PASSWORD}"
COOKIE_FILE="/tmp/3xui_cookie.txt"

info "Автоматическая настройка панели 3x-ui..."

# 1. Логин для получения куки
info "Авторизация в панели..."

attempt_login() {
    local user=$1
    local pass=$2
    curl -s -X POST "${PANEL_URL}/login" \
         -c "$COOKIE_FILE" \
         -d "username=${user}" \
         -d "password=${pass}"
}

LOGIN_RES=$(attempt_login "${USERNAME}" "${PASSWORD}")

if [[ "$LOGIN_RES" != *"true"* ]]; then
    warn "Не удалось войти с учетными данными из .env. Пробую стандартные (admin/admin)..."
    LOGIN_RES=$(attempt_login "admin" "admin")
    
    if [[ "$LOGIN_RES" == *"true"* ]]; then
        log "Вход со стандартными данными выполнен."
        info "Обновляю учетные данные панели на те, что указаны в .env..."
        
        # Обновляем логин и пароль через API или внутреннюю команду
        # В 3x-ui это делается через POST /panel/setting/updateUser
        UPDATE_RES=$(curl -s -X POST "${PANEL_URL}/panel/setting/updateUser" \
             -b "$COOKIE_FILE" \
             -d "oldUsername=admin" \
             -d "oldPassword=admin" \
             -d "newUsername=${USERNAME}" \
             -d "newPassword=${PASSWORD}")
        
        if [[ "$UPDATE_RES" == *"true"* ]]; then
            log "Данные успешно обновлены."
        else
            err "Не удалось обновить данные пользователя в панели: $UPDATE_RES"
        fi
    else
        err "Ошибка авторизации. Не подошли ни данные из .env, ни стандартные admin/admin."
    fi
fi
log "Успешная авторизация"

# 2. Проверка, существует ли уже такой Inbound (по порту 443)
info "Проверка существующих подключений..."
LIST_RES=$(curl -s -X POST "${PANEL_URL}/panel/api/inbounds/list" -b "$COOKIE_FILE")

# Извлекаем ID существующего инбаунда на порту 443
EXISTING_ID=$(echo "$LIST_RES" | grep -Po '"id":\s*\d+(?=,"up":.*,"port":443)' | head -n 1 | grep -Po '\d+') || EXISTING_ID=""

# 3. Подготовка JSON для VLESS + Reality
info "Подготовка параметров подключения (VLESS + Reality)..."

INBOUND_JSON=$(cat <<EOF
{
  "up": 0,
  "down": 0,
  "total": 0,
  "remark": "VLESS-REALITY-AUTO",
  "enable": true,
  "expiryTime": 0,
  "listen": "",
  "port": 443,
  "protocol": "vless",
  "settings": "{\"clients\": [{\"id\": \"${VLESS_UUID}\", \"flow\": \"xtls-rprx-vision\"}], \"decryption\": \"none\", \"fallbacks\": []}",
  "streamSettings": "{\"network\": \"tcp\", \"security\": \"reality\", \"realitySettings\": {\"show\": false, \"dest\": \"${REALITY_SNI}:443\", \"proxyProtocol\": 0, \"serverNames\": [\"${REALITY_SNI}\"], \"privateKey\": \"${REALITY_PRIVATE_KEY}\", \"minClient\": \"\", \"maxClient\": \"\", \"format\": \"\", \"shortIds\": [\"${REALITY_SHORT_ID}\"]}, \"tcpSettings\": {\"header\": {\"type\": \"none\"}}}",
  "sniffing": "{\"enabled\": true, \"destOverride\": [\"http\", \"tls\"]}"
}
EOF
)

# 4. Создание или обновление
if [[ -n "$EXISTING_ID" ]]; then
    info "Обновление существующего подключения (ID: $EXISTING_ID)..."
    ACTION_URL="${PANEL_URL}/panel/api/inbounds/update/${EXISTING_ID}"
else
    info "Создание нового подключения..."
    ACTION_URL="${PANEL_URL}/panel/api/inbounds/add"
fi

RES=$(curl -s -X POST "$ACTION_URL" \
     -b "$COOKIE_FILE" \
     -H "Content-Type: application/json" \
     -d "$INBOUND_JSON")

if [[ "$RES" == *"true"* ]]; then
    log "Настройки успешно применены!"
else
    echo "DEBUG: API Response: $RES"
    err "Не удалось применить настройки инбаунда."
fi

rm -f "$COOKIE_FILE"
