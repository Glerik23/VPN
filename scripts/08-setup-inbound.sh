#!/usr/bin/env bash
# =============================================================================
# 08-setup-inbound.sh — Автоматическая настройка 3x-ui через API
# Синхронизирует VLESS + Reality inbound из .env в панель
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

PANEL_URL="http://localhost:${XUI_PORT:-2053}"
# Публичный URL для инструкций (из .env)
PUBLIC_URL="http://${SERVER_IP:-ваш_ip}:${XUI_PORT:-2053}"
USERNAME="${XUI_USERNAME:-admin}"
PASSWORD="${XUI_PASSWORD}"
COOKIE_FILE="/tmp/3xui_cookie.txt"

info "Синхронизация настроек Reality с панелью 3x-ui..."

# 1. Авторизация
info "Авторизация..."
attempt_login() {
    curl -s -X POST "${PANEL_URL}/login" -c "$COOKIE_FILE" -d "username=$1" -d "password=$2"
}

LOGIN_RES=$(attempt_login "${USERNAME}" "${PASSWORD}")
if [[ "$LOGIN_RES" != *"true"* ]]; then
    warn "Данные из .env не подошли, пробую admin/admin..."
    LOGIN_RES=$(attempt_login "admin" "admin")
    if [[ "$LOGIN_RES" == *"true"* ]]; then
        log "Вход со стандартными данными. Обновляю пользователя на данные из .env..."
        curl -s -X POST "${PANEL_URL}/panel/setting/updateUser" -b "$COOKIE_FILE" \
             -d "oldUsername=admin" -d "oldPassword=admin" \
             -d "newUsername=${USERNAME}" -d "newPassword=${PASSWORD}" > /dev/null
    else
        err "Ошибка авторизации в панели."
    fi
fi
log "Успешная авторизация"

# 2. Поиск инбаунда
info "Поиск существующего инбаунда на порту 443..."
LIST_RES=$(curl -s -X POST "${PANEL_URL}/panel/api/inbounds/list" -b "$COOKIE_FILE")

if [[ -z "$LIST_RES" || "$LIST_RES" == "null" ]]; then
    warn "POST запрос списка инбаундов вернул пустоту. Пробую GET..."
    LIST_RES=$(curl -s -X GET "${PANEL_URL}/panel/api/inbounds/list" -b "$COOKIE_FILE")
fi

if [[ -z "$LIST_RES" || "$LIST_RES" == "null" ]]; then
    warn "Не удалось получить список инбаундов (пустой ответ)."
    EXISTING_ID=""
else
    # Извлекаем ID с помощью Python
    EXISTING_ID=$(echo "$LIST_RES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if not data or not isinstance(data, dict):
        sys.exit(0)
    # 3x-ui обычно возвращает список в data['obj']
    inbounds = data.get('obj', [])
    if inbounds is None: inbounds = []
    for obj in inbounds:
        if obj.get('port') == 443:
            print(obj.get('id'))
            break
except Exception as e:
    sys.stderr.write(f'JSON Parsing Error: {e}\n')
" 2>/dev/null || echo "")
fi

if [[ -n "$EXISTING_ID" ]]; then
    log "Найден существующий инбаунд с ID: $EXISTING_ID"
else
    info "Существующий инбаунд на порту 443 не найден в списке API."
fi

# 3. Формирование JSON
info "Подготовка конфигурации (VLESS + Reality)..."
INBOUND_JSON=$(cat <<EOF
{
  "up": 0, "down": 0, "total": 0,
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

# 4. Применение
if [[ -n "$EXISTING_ID" ]]; then
    info "Обновление существующего инбаунда (ID: $EXISTING_ID)..."
    ACTION_URL="${PANEL_URL}/panel/api/inbounds/update/${EXISTING_ID}"
else
    info "Создание нового инбаунда..."
    ACTION_URL="${PANEL_URL}/panel/api/inbounds/add"
fi

RES=$(curl -s -X POST "$ACTION_URL" -b "$COOKIE_FILE" -H "Content-Type: application/json" -d "$INBOUND_JSON")

if [[ "$RES" == *"true"* ]]; then
    log "Настройки Reality успешно синхронизированы!"
else
    echo "DEBUG: API Response: $RES"
    err "Не удалось применить настройки."
fi

# 5. Настройка Outbound для Warp (если нужен)
info "Проверка конфигурации Outbound (Warp)..."

# Для получения списка аутбаундов в MHSanaei используем getConfigJson
CONFIG_JSON=$(curl -s -X GET "${PANEL_URL}/panel/api/server/getConfigJson" -b "$COOKIE_FILE")

WARP_EXISTS=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    # В ответе getConfigJson приходит объект с полем 'obj' (строка JSON или объект)
    if isinstance(data.get('obj'), str):
        config = json.loads(data['obj'])
    else:
        config = data.get('obj', {})
    
    outbounds = config.get('outbounds', [])
    for obj in outbounds:
        if obj.get('tag') == 'warp':
            print('true')
            sys.exit(0)
except Exception as e:
    pass
print('false')
" 2>/dev/null || echo "false")

if [[ "$WARP_EXISTS" == "true" ]]; then
    log "Outbound 'warp' найден в конфигурации Xray."
else
    warn "Outbound 'warp' НЕ найден. Добавляем Warp и маршрутизацию автоматически..."
    
    VOLUME_NAME=$(docker volume ls -q | grep "3xui-db" | head -n 1)
    if [[ -n "$VOLUME_NAME" ]]; then
        docker run --rm -v "${VOLUME_NAME}:/etc/x-ui/" -v "${PROJECT_DIR}/scripts:/scripts" python:3-slim bash -c "pip install sqlite3 2>/dev/null; python3 -c \"
import sqlite3, json

db_path = '/etc/x-ui/x-ui.db'
try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute(\\\"SELECT value FROM settings WHERE key='xrayTemplateConfig'\\\")
    row = c.fetchone()
    if row:
        config = json.loads(row[0])
        
        # Add warp outbound
        outbounds = config.setdefault('outbounds', [])
        if not any(o.get('tag') == 'warp' for o in outbounds):
            outbounds.append({
                'protocol': 'socks',
                'tag': 'warp',
                'settings': {
                    'servers': [{'address': '127.0.0.1', 'port': 1080}]
                }
            })
            
        # Add routing rules
        routing = config.setdefault('routing', {})
        rules = routing.setdefault('rules', [])
        
        if not any(r.get('outboundTag') == 'warp' for r in rules):
            rules.insert(0, {
                'type': 'field',
                'outboundTag': 'warp',
                'domain': [
                    'geosite:openai',
                    'geosite:netflix',
                    'geosite:disney',
                    'geosite:primevideo',
                    'geosite:twitter',
                    'geosite:instagram',
                    'geosite:meta',
                    'domain:chatgpt.com',
                    'domain:antigravity.com'
                ]
            })
            
        c.execute(\\\"UPDATE settings SET value=? WHERE key='xrayTemplateConfig'\\\", (json.dumps(config, indent=2),))
        conn.commit()
        print('Warp маршрутизация успешно добавлена в шаблон Xray!')
except Exception as e:
    print(f'Ошибка автоматической настройки: {e}')
finally:
    if 'conn' in locals():
        conn.close()
\""
        
        # Перезапуск 3x-ui для применения шаблона
        docker restart 3x-ui >/dev/null 2>&1
        log "Панель 3x-ui перезапущена для применения новых правил маршрутизации."
    else
        err "Не удалось найти Volume 3xui-db для автоматической настройки."
    fi
    echo ""
fi

rm -f "$COOKIE_FILE"
