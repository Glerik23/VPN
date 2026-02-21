#!/usr/bin/env bash
# =============================================================================
# 03-deploy.sh — Главный скрипт деплоя
# Генерирует ключи (если нужно), настраивает Hysteria2, запускает Docker
# =============================================================================
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# Обработка ошибок
error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    echo -e "${RED}[✗] Ошибка в строке $line_number: команда '$command' завершилась с кодом $exit_code${NC}"
    exit $exit_code
}
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

[[ $EUID -ne 0 ]] && err "Этот скрипт нужно запускать от root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo ""
echo "=========================================="
echo "  VPN-сервер — Деплой"
echo "=========================================="
echo ""

# =============================================
# 1. Проверка зависимостей
# =============================================
command -v docker &> /dev/null || err "Docker не установлен. Запусти ./02-install-docker.sh"
command -v docker compose &> /dev/null 2>&1 || err "Docker Compose плагин не найден."

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    err "Файл .env не найден. Выполни: cp .env.example .env && nano .env"
fi

source "$PROJECT_DIR/.env"

# Проверка обязательных переменных
[[ -z "${SERVER_IP:-}" || "$SERVER_IP" == "YOUR_SERVER_IP" ]] && \
    err "Укажи SERVER_IP в .env"
[[ -z "${XUI_PASSWORD:-}" || "$XUI_PASSWORD" == "CHANGE_ME_STRONG_PASSWORD" ]] && \
    err "Укажи XUI_PASSWORD в .env"

log "Проверка зависимостей пройдена"

# =============================================
# 2. Генерация ключей (если не заданы)
# =============================================
if [[ -z "${REALITY_PRIVATE_KEY:-}" || -z "${VLESS_UUID:-}" || -z "${HYSTERIA_PASSWORD:-}" || -z "${HYSTERIA_OBFS_PASSWORD:-}" ]]; then
    info "Ключи не найдены в .env, генерируем..."
    bash "$SCRIPT_DIR/04-generate-keys.sh"
    # Перезагрузка .env после генерации
    source "$PROJECT_DIR/.env"
    log "Ключи сгенерированы и сохранены в .env"
else
    log "Ключи уже присутствуют в .env"
fi

# =============================================
# 3. Подготовка конфига Hysteria2
# =============================================
info "Подготовка конфигурации Hysteria2..."

HYSTERIA_CONFIG="$PROJECT_DIR/hysteria2/config.yaml"

# Створення робочої копії з шаблону (якщо він існує) або використання поточного як основи
if [[ -f "${HYSTERIA_CONFIG}.template" ]]; then
    cp "${HYSTERIA_CONFIG}.template" "${HYSTERIA_CONFIG}.tmp"
else
    # Якщо шаблону немає, створюємо його з поточного конфігу (для першого разу)
    cp "$HYSTERIA_CONFIG" "${HYSTERIA_CONFIG}.tmp"
fi

# Замена плейсхолдеров
sed -i "s|__HYSTERIA_PASSWORD__|${HYSTERIA_PASSWORD}|g" "${HYSTERIA_CONFIG}.tmp"
sed -i "s|__HYSTERIA_UP__|${HYSTERIA_UP_MBPS:-100} mbps|g" "${HYSTERIA_CONFIG}.tmp"
sed -i "s|__HYSTERIA_DOWN__|${HYSTERIA_DOWN_MBPS:-100} mbps|g" "${HYSTERIA_CONFIG}.tmp"
sed -i "s|__HYSTERIA_MASQUERADE__|${REALITY_SNI:-www.microsoft.com}|g" "${HYSTERIA_CONFIG}.tmp"
sed -i "s|__HYSTERIA_OBFS_PASSWORD__|${HYSTERIA_OBFS_PASSWORD:-}|g" "${HYSTERIA_CONFIG}.tmp"
sed -i "s|__HYSTERIA_PORT__|${HYSTERIA_PORT:-443}|g" "${HYSTERIA_CONFIG}.tmp"

mv "${HYSTERIA_CONFIG}.tmp" "$HYSTERIA_CONFIG"
log "Конфиг Hysteria2 подготовлен"

# =============================================
# 4. Генерация TLS-сертификата для Hysteria2
# =============================================
CERT_DIR="$PROJECT_DIR/hysteria2/cert"
if [[ ! -f "$CERT_DIR/server.crt" ]]; then
    info "Генерация самоподписанного TLS-сертификата для Hysteria2..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/CN=${REALITY_SNI:-www.microsoft.com}" \
        -days 3650
    log "TLS-сертификат Hysteria2 сгенерирован"
else
    log "TLS-сертификат Hysteria2 уже существует"
fi

# Обновление docker-compose для монтирования локального каталога сертификатов
sed -i "s|hysteria2-cert:/etc/hysteria/cert/|./hysteria2/cert:/etc/hysteria/cert/:ro|g" \
    "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || true

# =============================================
# 5. Запуск Docker-контейнеров
# =============================================
info "Запуск Docker-контейнеров..."

cd "$PROJECT_DIR"
docker compose pull
docker compose up -d

# Ожидание готовности контейнеров
sleep 5
docker compose ps

log "Контейнеры запущены"

# =============================================
# 6. Информация о доступе
# =============================================
echo ""
echo "=========================================="
echo -e "  ${GREEN}Деплой завершён!${NC}"
echo "=========================================="
echo ""
echo "  📊 Панель 3x-ui:"
echo "     URL:      http://${SERVER_IP}:${XUI_PORT}"
echo "     Логин:    ${XUI_USERNAME:-admin}"
echo "     Пароль:   ${XUI_PASSWORD}"
echo ""
echo "  🔧 Следующие шаги в панели 3x-ui:"
echo "     1. Зайди в Panel Settings → измени порт/путь панели"
echo "     2. Зайди в Inbounds → Add New"
echo "     3. Выбери: VLESS + TCP + REALITY"
echo "     4. Укажи следующие значения REALITY:"
echo "        - Dest (SNI):    ${REALITY_SNI}"
echo "        - Server Names:  ${REALITY_SERVER_NAME}"
echo "        - Private Key:   ${REALITY_PRIVATE_KEY}"
echo "        - Short ID:      ${REALITY_SHORT_ID}"
echo "     5. Client UUID:     ${VLESS_UUID}"
echo ""
echo "  🔗 Hysteria2 работает на UDP :${HYSTERIA_PORT:-443}"
echo ""
echo "  Запусти ./05-show-clients.sh чтобы получить ссылки подключения"

# Обработка аргументов
SKIP_PROMPT=false
if [[ "${1:-}" == "--no-prompt" ]]; then
    SKIP_PROMPT=true
fi

# =============================================
# 7. Автоматическая настройка Inbound (через API)
# =============================================
echo ""
if [[ "$SKIP_PROMPT" == "true" ]]; then
    AUTO_XUI="y"
else
    read -p "Хотите настроить Inbound в панели автоматически? (y/n): " AUTO_XUI
fi

if [[ "$AUTO_XUI" =~ ^[Yy]$ ]]; then
    chmod +x "$SCRIPT_DIR/08-setup-inbound.sh"
    bash "$SCRIPT_DIR/08-setup-inbound.sh"
fi

echo ""
echo ""
