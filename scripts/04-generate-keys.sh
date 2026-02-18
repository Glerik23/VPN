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

# 2. Скачивание Xray
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    *)       err "Неподдерживаемая архитектура: $ARCH" ;;
esac

if [ ! -f /tmp/xray ]; then
    info "Скачивание Xray ($ARCH)..."
    curl -fSL --connect-timeout 30 -o /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" || err "Не удалось скачать Xray"
    
    cd /tmp && unzip -o xray.zip xray > /dev/null 2>&1 && chmod +x xray
fi
/tmp/xray version > /dev/null 2>&1 || err "Xray не запускается"
log "Xray готов"

# 3. Генерация ключей
info "=== Генерация ключей ==="

# Шаг 3.1: Генерация ключей (используем openssl для надежности)
if command -v openssl >/dev/null 2>&1; then
    # Проверяем поддержку X25519 в OpenSSL
    if openssl list -public-key-algorithms 2>/dev/null | grep -iq "X25519"; then
        info "Генерация ключей через OpenSSL..."
        REALITY_PRIVATE_KEY=$(openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\r\n ')
        if [ -n "$REALITY_PRIVATE_KEY" ]; then
            REALITY_PUBLIC_KEY=$(echo "$REALITY_PRIVATE_KEY" | base64 -d | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\r\n ')
        fi
    else
        warn "OpenSSL на сервере не поддерживает X25519, используем Xray..."
    fi
fi

# Если OpenSSL не сработал или отсутствует, пробуем Xray
if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    RAW_KEYS=$(/tmp/xray x25519 2>&1)
    
    # Ищем любой ряд, похожий на ключ (Base64 или URL-safe Base64), исключая мусор
    # Reality ключи обычно 43-44 символа
    KEYS_FOUND=$(echo "$RAW_KEYS" | grep -Ei "Private|Public|[a-zA-Z0-9+/=_-]{43,44}" | head -n 5)
    
    # Пробуем извлечь Private Key по метке или паттерну
    REALITY_PRIVATE_KEY=$(echo "$KEYS_FOUND" | grep -i "Private" | awk -F': ' '{print $NF}' | tr -d '\r\n ')
    [ -z "$REALITY_PRIVATE_KEY" ] && REALITY_PRIVATE_KEY=$(echo "$KEYS_FOUND" | grep -E "[a-zA-Z0-9+/=_-]{43,44}" | head -n 1 | tr -d '\r\n ')
    
    # Пробуем извлечь Public Key
    REALITY_PUBLIC_KEY=$(echo "$KEYS_FOUND" | grep -i "Public" | awk -F': ' '{print $NF}' | tr -d '\r\n ')
    
    # Если Public Key не найден, пробуем сгенерировать его из Private через Xray
    if [ -n "$REALITY_PRIVATE_KEY" ] && [ -z "$REALITY_PUBLIC_KEY" ]; then
        info "Попытка генерации Public Key из Private Key..."
        PUB_RAW=$(/tmp/xray x25519 -i "$REALITY_PRIVATE_KEY" 2>&1)
        REALITY_PUBLIC_KEY=$(echo "$PUB_RAW" | grep -Ei "Public|[a-zA-Z0-9+/=_-]{43,44}" | grep -v "$REALITY_PRIVATE_KEY" | head -n 1 | awk -F': ' '{print $NF}' | tr -d '\r\n ')
        # Если awk не сработал (нет двоеточия), берем просто строку
        [[ "$REALITY_PUBLIC_KEY" == *" "* ]] && REALITY_PUBLIC_KEY=$(echo "$REALITY_PUBLIC_KEY" | awk '{print $NF}')
    fi
fi

if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    echo "--- ОТЛАДКА ---"
    echo "Вывод Xray:"
    echo "$RAW_KEYS"
    err "Не удалось сгенерировать ключи. Проверьте вывод выше."
fi

echo "Private Key: [$REALITY_PRIVATE_KEY]"
echo "Public Key:  [$REALITY_PUBLIC_KEY]"

# UUID, ShortID, Password
VLESS_UUID=$(/tmp/xray uuid 2>&1 | tr -d '\r\n ')
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
