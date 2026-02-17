#!/bin/bash
# fix-vpn.sh - One-click fix for VPN keys
# Run this on the server!

set -euo pipefail

echo ">>> Updating key generator..."
# Overwrite the generate script with the fixed version locally
cat > /root/vpn/scripts/04-generate-keys.sh << 'EOF'
#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей (FIXED)
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

cd /tmp
unzip -o xray.zip xray 2>&1
chmod +x /tmp/xray

# 3. Генерация ключей
info "=== Генерация X25519 ==="
/tmp/xray x25519 > /tmp/xray_keys.txt 2>&1

echo "Результат генерации:"
cat /tmp/xray_keys.txt

REALITY_PRIVATE_KEY=$(grep -i "Private" /tmp/xray_keys.txt | awk '{print $NF}')
REALITY_PUBLIC_KEY=$(grep -i "Public" /tmp/xray_keys.txt | awk '{print $NF}')

# Fallback format check
if [ -z "$REALITY_PRIVATE_KEY" ]; then
    REALITY_PRIVATE_KEY=$(grep -i "PrivateKey:" /tmp/xray_keys.txt | awk '{print $NF}')
fi

echo "Private Key: [$REALITY_PRIVATE_KEY]"
echo "Public Key:  [$REALITY_PUBLIC_KEY]"

if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    err "Ошибка получения ключей from xray output"
fi

info "=== Генерация UUID ==="
VLESS_UUID=$(/tmp/xray uuid 2>&1)
info "=== Генерация Short ID ==="
REALITY_SHORT_ID=$(openssl rand -hex 4)
info "=== Генерация пароля Hysteria2 ==="
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

# 4. Запись в .env
info "Запись в .env..."
cd "$PROJECT_DIR"
set_env() {
    local key="$1"
    local val="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
}

set_env "REALITY_PRIVATE_KEY" "$REALITY_PRIVATE_KEY"
set_env "REALITY_PUBLIC_KEY" "$REALITY_PUBLIC_KEY"
set_env "REALITY_SHORT_ID" "$REALITY_SHORT_ID"
set_env "VLESS_UUID" "$VLESS_UUID"
set_env "HYSTERIA_PASSWORD" "$HYSTERIA_PASSWORD"

rm -f /tmp/xray /tmp/xray.zip /tmp/xray_keys.txt

echo ""
echo "=========================================="
echo -e "  ${GREEN}КЛЮЧИ ОБНОВЛЕНЫ УСПЕШНО!${NC}"
echo "=========================================="
EOF

chmod +x /root/vpn/scripts/04-generate-keys.sh

echo ">>> Regenerating keys..."
/root/vpn/scripts/04-generate-keys.sh

echo ">>> Showing new links..."
/root/vpn/scripts/05-show-clients.sh

echo ""
echo "!!! ВАЖНО !!!"
echo "Скопируйте этот Private Key и вставьте в панель 3x-ui:"
grep "REALITY_PRIVATE_KEY" /root/vpn/.env
echo ""
