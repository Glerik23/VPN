#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    err "Файл .env не найден"
fi

echo ""
echo "=========================================="
echo "  Генерация криптографических ключей"
echo "=========================================="
echo ""

# 1. Зависимости
info "Установка зависимостей..."
apt-get install -y curl unzip > /dev/null 2>&1 || true
log "Зависимости готовы"

# 2. Скачивание Xray
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    *)       err "Неподдерживаемая архитектура: $ARCH" ;;
esac

info "Скачивание Xray ($ARCH)..."
curl -fSL --connect-timeout 30 -o /tmp/xray.zip \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"

if [ ! -f /tmp/xray.zip ]; then
    err "Файл не скачался"
fi
log "Скачан: $(ls -lh /tmp/xray.zip | awk '{print $5}')"

info "Распаковка..."
cd /tmp
unzip -o xray.zip xray 2>&1
chmod +x /tmp/xray

if [ ! -f /tmp/xray ]; then
    err "Файл xray не найден после распаковки"
fi
log "Распаковано"

info "Проверка xray..."
/tmp/xray version
log "Xray работает"

# 3. Генерация ключей
info "=== Генерация X25519 ==="
echo "Запускаю: /tmp/xray x25519"
/tmp/xray x25519 > /tmp/xray_keys.txt 2>&1
XRAY_EXIT=$?
echo "Код выхода: $XRAY_EXIT"
echo "Результат:"
cat /tmp/xray_keys.txt
echo ""
echo "Hex-дамп (для отладки):"
cat /tmp/xray_keys.txt | xxd | head -5
echo "---"

if [ $XRAY_EXIT -ne 0 ]; then
    err "xray x25519 завершился с ошибкой $XRAY_EXIT"
fi

# Берём приватный ключ — последнее слово первой строки
REALITY_PRIVATE_KEY=$(head -1 /tmp/xray_keys.txt | awk '{print $NF}')
echo "Private (из 1-й строки): [$REALITY_PRIVATE_KEY]"

if [ -z "$REALITY_PRIVATE_KEY" ]; then
    err "Private Key пустой!"
fi

# Получаем публичный ключ из приватного (надёжный метод)
info "Генерация Public Key из Private Key..."
PUB_RAW=$(/tmp/xray x25519 -i "$REALITY_PRIVATE_KEY" 2>/dev/null)
echo "Raw output: [$PUB_RAW]"
REALITY_PUBLIC_KEY=$(echo "$PUB_RAW" | head -1 | awk '{print $NF}' | tr -d '\r\n')
echo "Public (очищенный): [$REALITY_PUBLIC_KEY]"

if [ -z "$REALITY_PUBLIC_KEY" ]; then
    err "Public Key пустой!"
fi

info "=== Генерация UUID ==="
VLESS_UUID=$(/tmp/xray uuid 2>&1)
echo "UUID: [$VLESS_UUID]"

info "=== Генерация Short ID ==="
REALITY_SHORT_ID=$(openssl rand -hex 4)
echo "Short ID: [$REALITY_SHORT_ID]"

info "=== Генерация пароля Hysteria2 ==="
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
echo "Password: [$HYSTERIA_PASSWORD]"

# 4. Запись в .env
info "Запись в .env..."
cd "$PROJECT_DIR"

# Функция: заменяет значение или добавляет строку если её нет
set_env() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
    echo "  ${key}=${val}"
}

set_env "REALITY_PRIVATE_KEY" "$REALITY_PRIVATE_KEY"
set_env "REALITY_PUBLIC_KEY" "$REALITY_PUBLIC_KEY"
set_env "REALITY_SHORT_ID" "$REALITY_SHORT_ID"
set_env "VLESS_UUID" "$VLESS_UUID"
set_env "HYSTERIA_PASSWORD" "$HYSTERIA_PASSWORD"

# Проверка
echo ""
echo "=== Проверка .env ==="
grep -E "REALITY_PRIVATE|REALITY_PUBLIC|REALITY_SHORT|VLESS_UUID|HYSTERIA_PASSWORD" "$ENV_FILE"

SAVED=$(grep "^REALITY_PRIVATE_KEY=" "$ENV_FILE" | cut -d= -f2)
if [ -z "$SAVED" ]; then
    err "Ключи НЕ записались!"
fi

# Очистка
rm -f /tmp/xray /tmp/xray.zip /tmp/xray_keys.txt

echo ""
echo "=========================================="
echo -e "  ${GREEN}Готово! Ключи записаны в .env${NC}"
echo "=========================================="
echo ""
