#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# Генерирует: X25519 пару, UUID, пароль Hysteria2, REALITY short ID
# Использует запущенный контейнер 3x-ui или docker run как фоллбэк
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

command -v docker &> /dev/null || err "Docker не установлен. Запусти ./02-install-docker.sh"

echo ""
echo "=========================================="
echo "  Генерация криптографических ключей"
echo "=========================================="
echo ""

# Определяем, как запускать xray
# Приоритет: работающий контейнер > docker run
if docker ps --format '{{.Names}}' | grep -q '^3x-ui$'; then
    XRAY_CMD="docker exec 3x-ui xray"
    info "Используем запущенный контейнер 3x-ui"
else
    XRAY_CMD="docker run --rm --entrypoint xray ghcr.io/mhsanaei/3x-ui:latest"
    info "Контейнер не запущен, используем docker run"
fi

# =============================================
# 1. Генерация X25519 ключевой пары для REALITY
# =============================================
info "Генерация X25519 ключевой пары для REALITY..."

KEYPAIR=$($XRAY_CMD x25519 2>/dev/null) || err "Не удалось запустить xray x25519"
REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')

[[ -z "$REALITY_PRIVATE_KEY" ]] && err "Не удалось сгенерировать REALITY Private Key"
[[ -z "$REALITY_PUBLIC_KEY" ]] && err "Не удалось сгенерировать REALITY Public Key"

log "REALITY Private Key: ${REALITY_PRIVATE_KEY}"
log "REALITY Public Key:  ${REALITY_PUBLIC_KEY}"

# =============================================
# 2. Генерация REALITY Short ID (8 hex символов)
# =============================================
REALITY_SHORT_ID=$(openssl rand -hex 4)
log "REALITY Short ID:    ${REALITY_SHORT_ID}"

# =============================================
# 3. Генерация VLESS UUID
# =============================================
VLESS_UUID=$($XRAY_CMD uuid 2>/dev/null) || err "Не удалось сгенерировать UUID"
[[ -z "$VLESS_UUID" ]] && err "UUID пустой"
log "VLESS UUID:          ${VLESS_UUID}"

# =============================================
# 4. Генерация пароля Hysteria2
# =============================================
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
log "Пароль Hysteria2:    ${HYSTERIA_PASSWORD}"

# =============================================
# 5. Запись в .env
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

echo ""
echo "=========================================="
echo -e "  ${GREEN}Генерация ключей завершена!${NC}"
echo "=========================================="
echo ""
echo "  ⚠️  Сохрани REALITY Public Key — он нужен клиентам:"
echo "     ${REALITY_PUBLIC_KEY}"
echo ""
