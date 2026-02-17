#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# Скачивает Xray, генерирует X25519, UUID, Short ID, пароль Hysteria2
# Записывает всё в .env
# =============================================================================
set -euo pipefail

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

[[ ! -f "$ENV_FILE" ]] && err "Файл .env не найден. Выполни: cp .env.example .env"

echo ""
echo "=========================================="
echo "  Генерация криптографических ключей"
echo "=========================================="
echo ""

# =============================================
# 1. Скачивание Xray
# =============================================
info "Установка зависимостей..."
apt-get install -y curl unzip > /dev/null 2>&1 || true

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_ARCH="64" ;;
    aarch64) XRAY_ARCH="arm64-v8a" ;;
    armv7l)  XRAY_ARCH="arm32-v7a" ;;
    *)       err "Неподдерживаемая архитектура: $ARCH" ;;
esac

info "Скачивание Xray (архитектура: $ARCH)..."
curl -fSL --connect-timeout 30 -o /tmp/xray.zip \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" || \
    err "Не удалось скачать Xray. Проверь: curl -I https://github.com"

cd /tmp && unzip -o xray.zip xray > /dev/null 2>&1 && chmod +x xray
cd "$PROJECT_DIR"

/tmp/xray version > /dev/null 2>&1 || err "Xray не запускается"
log "Xray скачан"

# =============================================
# 2. Генерация ключей
# =============================================
info "Генерация ключей..."

KEYS=$(/tmp/xray x25519)
REALITY_PRIVATE_KEY=$(echo "$KEYS" | grep Private | awk '{print $NF}')
REALITY_PUBLIC_KEY=$(echo "$KEYS" | grep Public | awk '{print $NF}')
VLESS_UUID=$(/tmp/xray uuid)
REALITY_SHORT_ID=$(openssl rand -hex 4)
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

[[ -z "$REALITY_PRIVATE_KEY" ]] && err "Не удалось сгенерировать Private Key"

# =============================================
# 3. Запись в .env
# =============================================
info "Запись в .env..."

sed -i "s|^REALITY_PRIVATE_KEY=.*|REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}|" "$ENV_FILE"
sed -i "s|^REALITY_PUBLIC_KEY=.*|REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}|" "$ENV_FILE"
sed -i "s|^REALITY_SHORT_ID=.*|REALITY_SHORT_ID=${REALITY_SHORT_ID}|" "$ENV_FILE"
sed -i "s|^VLESS_UUID=.*|VLESS_UUID=${VLESS_UUID}|" "$ENV_FILE"
sed -i "s|^HYSTERIA_PASSWORD=.*|HYSTERIA_PASSWORD=${HYSTERIA_PASSWORD}|" "$ENV_FILE"

# Проверка что записалось
SAVED=$(grep "^REALITY_PRIVATE_KEY=" "$ENV_FILE" | cut -d= -f2)
[[ -z "$SAVED" ]] && err "Ключи НЕ записались в .env!"

# Очистка
rm -f /tmp/xray /tmp/xray.zip

log "Все ключи записаны в .env"

echo ""
echo "=========================================="
echo -e "  ${GREEN}Генерация завершена!${NC}"
echo "=========================================="
echo ""
echo "  REALITY Private Key: ${REALITY_PRIVATE_KEY}"
echo "  REALITY Public Key:  ${REALITY_PUBLIC_KEY}"
echo "  REALITY Short ID:    ${REALITY_SHORT_ID}"
echo "  VLESS UUID:          ${VLESS_UUID}"
echo "  Hysteria2 пароль:    ${HYSTERIA_PASSWORD}"
echo ""
echo "  ⚠️  Public Key нужен клиентам — сохрани его!"
echo ""
