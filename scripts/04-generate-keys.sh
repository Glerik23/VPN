#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# Скачивает Xray binary напрямую, генерирует все ключи, сохраняет в .env
# =============================================================================
set -euo pipefail

# Цвета
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

[[ ! -f "$ENV_FILE" ]] && err "Файл .env не найден"

echo ""
echo "=========================================="
echo "  Генерация криптографических ключей"
echo "=========================================="
echo ""

# =============================================
# 0. Установка зависимостей
# =============================================
info "Проверка зависимостей..."
apt-get install -y curl unzip > /dev/null 2>&1 || true
command -v curl &> /dev/null || err "curl не установлен"
log "Зависимости готовы"

# =============================================
# 1. Скачивание Xray
# =============================================
XRAY_BIN="/tmp/xray"

if [[ -f "$XRAY_BIN" ]] && "$XRAY_BIN" version &>/dev/null; then
    log "Xray уже скачан"
else
    info "Скачивание Xray..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l)  XRAY_ARCH="arm32-v7a" ;;
        *)       err "Неподдерживаемая архитектура: $ARCH" ;;
    esac

    XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"

    info "Архитектура: $ARCH → Xray-linux-${XRAY_ARCH}.zip"
    info "URL: $XRAY_URL"

    # Скачиваем с подробным выводом
    curl -fSL --connect-timeout 30 --max-time 120 -o /tmp/xray.zip "$XRAY_URL" || \
        err "Не удалось скачать Xray. Проверь доступ к github.com: curl -I https://github.com"

    log "Архив скачан ($(du -h /tmp/xray.zip | cut -f1))"

    # Распаковка
    info "Распаковка..."
    cd /tmp
    unzip -o /tmp/xray.zip xray -d /tmp || err "Не удалось распаковать архив"
    chmod +x /tmp/xray
    rm -f /tmp/xray.zip

    # Проверка
    "$XRAY_BIN" version &>/dev/null || err "Xray скачан, но не запускается. Возможно, неверная архитектура."
    log "Xray готов ($(${XRAY_BIN} version 2>/dev/null | head -1))"
fi

# =============================================
# 2. Генерация X25519 ключевой пары для REALITY
# =============================================
info "Генерация X25519 ключевой пары..."

KEYPAIR=$("$XRAY_BIN" x25519 2>&1)
echo "  Результат: $KEYPAIR"

REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')

[[ -z "$REALITY_PRIVATE_KEY" ]] && err "Private Key пустой. Вывод xray: $KEYPAIR"
[[ -z "$REALITY_PUBLIC_KEY" ]] && err "Public Key пустой. Вывод xray: $KEYPAIR"

log "REALITY Private Key: ${REALITY_PRIVATE_KEY}"
log "REALITY Public Key:  ${REALITY_PUBLIC_KEY}"

# =============================================
# 3. Генерация REALITY Short ID
# =============================================
REALITY_SHORT_ID=$(openssl rand -hex 4)
log "REALITY Short ID:    ${REALITY_SHORT_ID}"

# =============================================
# 4. Генерация VLESS UUID
# =============================================
VLESS_UUID=$("$XRAY_BIN" uuid 2>/dev/null) || \
    VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null) || \
    err "Не удалось сгенерировать UUID"

log "VLESS UUID:          ${VLESS_UUID}"

# =============================================
# 5. Генерация пароля Hysteria2
# =============================================
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
log "Пароль Hysteria2:    ${HYSTERIA_PASSWORD}"

# =============================================
# 6. Запись в .env
# =============================================
info "Сохранение ключей в .env..."

update_env() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

update_env "REALITY_PRIVATE_KEY" "$REALITY_PRIVATE_KEY"
update_env "REALITY_PUBLIC_KEY" "$REALITY_PUBLIC_KEY"
update_env "REALITY_SHORT_ID" "$REALITY_SHORT_ID"
update_env "VLESS_UUID" "$VLESS_UUID"
update_env "HYSTERIA_PASSWORD" "$HYSTERIA_PASSWORD"

log "Ключи сохранены в .env"

# Очистка
rm -f "$XRAY_BIN"

echo ""
echo "=========================================="
echo -e "  ${GREEN}Генерация ключей завершена!${NC}"
echo "=========================================="
echo ""
echo "  ⚠️  Сохрани REALITY Public Key — он нужен клиентам:"
echo "     ${REALITY_PUBLIC_KEY}"
echo ""
