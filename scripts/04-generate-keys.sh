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
info "=== Генерация ключей (VLESS + Reality + Hysteria) ==="

# Функция для локальной генерации (без Docker)
generate_locally() {
    warn "Использую локальную генерацию (Docker недоступен или тормозит)..."
    
    # Создаем временные файлы
    local PRIV_PEM="/tmp/reality_priv.pem"
    local PUB_PEM="/tmp/reality_pub.pem"
    
    # Генерируем приватный ключ в формате PEM
    if openssl genpkey -algorithm x25519 -out "$PRIV_PEM" 2>/dev/null; then
        # Генерируем публичный ключ в формате PEM
        openssl pkey -in "$PRIV_PEM" -pubout -out "$PUB_PEM" 2>/dev/null
        
        # Извлекаем сырые байты (raw bytes) и кодируем в base64
        # В DER-формате x25519 ключи всегда в конце: 32 байта для приватного и 32 для публичного
        REALITY_PRIVATE_KEY=$(openssl pkey -in "$PRIV_PEM" -outform DER | tail -c 32 | base64 | tr -d '\r\n')
        REALITY_PUBLIC_KEY=$(openssl pkey -in "$PUB_PEM" -pubin -outform DER | tail -c 32 | base64 | tr -d '\r\n')
        
        rm -f "$PRIV_PEM" "$PUB_PEM"
    else
        err "Ваша система не поддерживает генерацию X25519. Попробуйте обновить openssl (apt update && apt install openssl)."
    fi
    
    VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
    HYSTERIA_OBFS_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
}

# Пробуем через Docker с таймаутом
info "Проверка Docker и образа..."
CAN_USE_DOCKER=false

# Используем специализированный легковесный образ Xray, так как в 3x-ui бинарник скачивается при первом старте
KEY_IMAGE="teddysun/xray:latest"

# Проверяем, что docker вообще жив и может выполнить простую команду
if command -v docker &> /dev/null && timeout 5s docker ps &>/dev/null; then
    # Пробуем pull с таймаутом 30 секунд (только если образа нет)
    if [[ "$(docker images -q "$KEY_IMAGE" 2> /dev/null)" == "" ]]; then
        info "Загрузка вспомогательного образа Docker (teddysun/xray)..."
        if timeout 60s docker pull "$KEY_IMAGE" &>/dev/null; then
            CAN_USE_DOCKER=true
        fi
    else
        CAN_USE_DOCKER=true
    fi
fi

if [ "$CAN_USE_DOCKER" = true ]; then
    info "Генерация через Docker..."
    # Добавляем таймаут 15сек на сам запуск контейнера.
    if RAW_KEYS=$(timeout 15s docker run --rm "$KEY_IMAGE" x25519 2>/dev/null); then
        REALITY_PRIVATE_KEY=$(echo "$RAW_KEYS" | grep -i "Private" | awk -F': ' '{print $NF}' | tr -d '\r\n ' || echo "")
        REALITY_PUBLIC_KEY=$(echo "$RAW_KEYS" | grep -i "Public" | awk -F': ' '{print $NF}' | tr -d '\r\n ' || echo "")
        
        # Улучшенная отказоустойчивость
        if [[ -z "$REALITY_PRIVATE_KEY" ]]; then
            warn "Не удалось извлечь ключи из ответа Docker. Использую локальную генерацию..."
            generate_locally
        else
            VLESS_UUID=$(timeout 15s docker run --rm "$KEY_IMAGE" uuid 2>/dev/null | tr -d '\r\n ' || echo "")
        
        # Если UUID не сгенерировался через докер, генерируем локально
        if [ -z "$VLESS_UUID" ]; then
            VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
        fi
        
        REALITY_SHORT_ID=$(openssl rand -hex 4)
        HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
        HYSTERIA_OBFS_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
        fi
    else
        warn "Docker завис при запуске контейнера. Использую локальную генерацию..."
        generate_locally
    fi
else
    generate_locally
fi

if [ -z "$REALITY_PRIVATE_KEY" ]; then
    err "Не удалось сгенерировать ключи ни одним из способов."
fi

echo "Private Key: [СКРЫТО]"
echo "Public Key:  [$REALITY_PUBLIC_KEY]"

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
set_env "HYSTERIA_OBFS_PASSWORD" "$HYSTERIA_OBFS_PASSWORD"

# Очистка
rm -f /tmp/xray /tmp/xray.zip

echo ""
echo "=========================================="
echo -e "  ${GREEN}Готово! Ключи записаны в .env${NC}"
echo "=========================================="
echo "  REALITY Public Key: $REALITY_PUBLIC_KEY"
echo ""
