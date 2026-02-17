#!/usr/bin/env bash
# =============================================================================
# 04-generate-keys.sh — Генерация криптографических ключей
# Генерирует: X25519 пару, UUID, пароль Hysteria2, REALITY short ID
# Автоматически запускает контейнер 3x-ui для генерации, если он не запущен
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

# =============================================
# 0. Убедимся, что контейнер 3x-ui запущен
# =============================================
NEED_STOP=false

if ! docker ps --format '{{.Names}}' | grep -q '^3x-ui$'; then
    info "Контейнер 3x-ui не запущен, запускаем..."

    # Проверяем, есть ли образ
    XRAY_IMAGE="ghcr.io/mhsanaei/3x-ui:latest"
    if ! docker image inspect "$XRAY_IMAGE" &> /dev/null; then
        info "Загрузка образа 3x-ui (это займёт 1-2 минуты)..."
        docker pull "$XRAY_IMAGE"
        log "Образ загружен"
    fi

    # Запускаем только 3x-ui (без hysteria2)
    docker run -d --name 3x-ui-keygen --rm "$XRAY_IMAGE" sleep 120 &> /dev/null
    CONTAINER="3x-ui-keygen"
    NEED_STOP=true

    # Ждём запуска
    sleep 2
    log "Временный контейнер запущен"
else
    CONTAINER="3x-ui"
    log "Используем запущенный контейнер 3x-ui"
fi

# Находим путь к xray внутри контейнера
XRAY_PATH=""
for path in "/app/xray" "/usr/local/bin/xray" "/app/bin/xray-linux-amd64"; do
    if docker exec "$CONTAINER" test -f "$path" 2>/dev/null; then
        XRAY_PATH="$path"
        break
    fi
done

# Фоллбэк: ищем через find
if [[ -z "$XRAY_PATH" ]]; then
    XRAY_PATH=$(docker exec "$CONTAINER" find / -name "xray" -type f 2>/dev/null | head -1)
fi

[[ -z "$XRAY_PATH" ]] && { $NEED_STOP && docker stop "$CONTAINER" &>/dev/null; err "Не удалось найти xray внутри контейнера"; }

info "Xray найден: $XRAY_PATH"

# =============================================
# 1. Генерация X25519 ключевой пары для REALITY
# =============================================
info "Генерация X25519 ключевой пары для REALITY..."

KEYPAIR=$(docker exec "$CONTAINER" "$XRAY_PATH" x25519 2>/dev/null) || \
    { $NEED_STOP && docker stop "$CONTAINER" &>/dev/null; err "Не удалось выполнить xray x25519"; }

REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $NF}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $NF}')

[[ -z "$REALITY_PRIVATE_KEY" ]] && { $NEED_STOP && docker stop "$CONTAINER" &>/dev/null; err "Private Key пустой"; }

log "REALITY Private Key: ${REALITY_PRIVATE_KEY}"
log "REALITY Public Key:  ${REALITY_PUBLIC_KEY}"

# =============================================
# 2. Генерация REALITY Short ID
# =============================================
REALITY_SHORT_ID=$(openssl rand -hex 4)
log "REALITY Short ID:    ${REALITY_SHORT_ID}"

# =============================================
# 3. Генерация VLESS UUID
# =============================================
VLESS_UUID=$(docker exec "$CONTAINER" "$XRAY_PATH" uuid 2>/dev/null) || \
    VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null) || \
    VLESS_UUID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null) || \
    err "Не удалось сгенерировать UUID"

log "VLESS UUID:          ${VLESS_UUID}"

# =============================================
# 4. Генерация пароля Hysteria2
# =============================================
HYSTERIA_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
log "Пароль Hysteria2:    ${HYSTERIA_PASSWORD}"

# =============================================
# Остановка временного контейнера
# =============================================
if $NEED_STOP; then
    docker stop "$CONTAINER" &>/dev/null || true
    log "Временный контейнер остановлен"
fi

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
