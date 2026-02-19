#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    cp "$PROJECT_DIR/.env.example" "$ENV_FILE" 2>/dev/null || err "Файл .env не найден"
fi

echo ""
echo "=========================================="
echo "  Генерация криптографических ключей"
echo "=========================================="
echo ""

# 1. Зависимости
info "Установка зависимостей..."
apt-get install -y curl unzip > /dev/null 2>&1 || true

# 2. Генерация ключей через Docker
info "Использование Docker для генерации ключей..."

# Проверяем наличие Docker
if ! command -v docker &> /dev/null; then
    err "Docker не установлен. Сначала запустите ./02-install-docker.sh"
fi

# Нам нужен образ 3x-ui, так как в нём есть xray-core
XRAY_IMAGE="ghcr.io/mhsanaei/3x-ui:v2.3.8"

# 3. Генерация ключей
info "=== Генерация ключей (X25519) ==="

# Генерация Private/Public Key через Docker (xray)
# Вывод xray x25519 выглядит так:
# Private key: ...
# Public key: ...
RAW_KEYS=$(docker run --rm "$XRAY_IMAGE" /app/xray x25519 2>/dev/null)

REALITY_PRIVATE_KEY=$(echo "$RAW_KEYS" | grep -i "Private" | awk -F': ' '{print $NF}' | tr -d '\r\n ')
REALITY_PUBLIC_KEY=$(echo "$RAW_KEYS" | grep -i "Public" | awk -F': ' '{print $NF}' | tr -d '\r\n ')

if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    err "Не удалось сгенерировать ключи через Docker. Убедитесь, что есть интернет для скачивания образа."
fi

echo "Private Key: [СКРЫТО]"
echo "Public Key:  [$REALITY_PUBLIC_KEY]"

# UUID, ShortID, Password
VLESS_UUID=$(docker run --rm "$XRAY_IMAGE" /app/xray uuid 2>/dev/null | tr -d '\r\n ')
REALITY_SHORT_ID=$(openssl rand -hex 4)
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# 4. Запись в .env
info "Запись в .env..."

# Функция для безопасной замены/добавления в .env
set_env() {
    local key="$1"
    local val="$2"
    # Экранируем слеши и спецсимволы для sed
    local esc_val=$(echo "$val" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${esc_val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
}

set_env "REALITY_PRIVATE_KEY" "$REALITY_PRIVATE_KEY"
set_env "REALITY_PUBLIC_KEY" "$REALITY_PUBLIC_KEY"
set_env "REALITY_SHORT_ID" "$REALITY_SHORT_ID"
set_env "VLESS_UUID" "$VLESS_UUID"
set_env "HYSTERIA_PASSWORD" "$HYSTERIA_PASSWORD"

# Очистка
rm -f /tmp/xray /tmp/xray.zip

echo ""
echo "=========================================="
echo -e "  ${GREEN}Готово! Ключи записаны в .env${NC}"
echo "=========================================="
echo "  REALITY Public Key: $REALITY_PUBLIC_KEY"
echo ""
