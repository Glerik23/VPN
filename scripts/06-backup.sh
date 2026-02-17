#!/usr/bin/env bash
# =============================================================================
# 06-backup.sh — Бэкап конфигурации VPN-сервера
# Архивирует .env, docker volumes и конфиги
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

[[ $EUID -ne 0 ]] && err "Этот скрипт нужно запускать от root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-/root/vpn-backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="vpn-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo ""
echo "=========================================="
echo "  VPN-сервер — Бэкап"
echo "=========================================="
echo ""

mkdir -p "$BACKUP_PATH"

# =============================================
# 1. Бэкап .env
# =============================================
info "Бэкап .env..."
cp "$PROJECT_DIR/.env" "$BACKUP_PATH/.env"
log ".env сохранён"

# =============================================
# 2. Бэкап конфигов Hysteria2
# =============================================
info "Бэкап конфигов Hysteria2..."
mkdir -p "$BACKUP_PATH/hysteria2"
cp -r "$PROJECT_DIR/hysteria2/" "$BACKUP_PATH/hysteria2/"
log "Конфиги Hysteria2 сохранены"

# =============================================
# 3. Бэкап базы данных 3x-ui (Docker volume)
# =============================================
info "Бэкап базы данных 3x-ui..."
if docker volume inspect 3xui-db > /dev/null 2>&1; then
    docker run --rm \
        -v 3xui-db:/source:ro \
        -v "$BACKUP_PATH/3xui-db":/backup \
        alpine sh -c "cp -a /source/* /backup/"
    log "База данных 3x-ui сохранена"
else
    warn "Docker volume 3xui-db не найден, пропускаем"
fi

# =============================================
# 4. Бэкап клиентских ссылок
# =============================================
if [[ -f "$PROJECT_DIR/client-links.txt" ]]; then
    cp "$PROJECT_DIR/client-links.txt" "$BACKUP_PATH/"
    log "Клиентские ссылки сохранены"
fi

# =============================================
# 5. Бэкап конфигов fail2ban
# =============================================
info "Бэкап правил fail2ban..."
mkdir -p "$BACKUP_PATH/fail2ban"
cp -r "$PROJECT_DIR/configs/fail2ban/" "$BACKUP_PATH/fail2ban/"
log "Конфиги fail2ban сохранены"

# =============================================
# 6. Создание архива
# =============================================
info "Создание архива..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

ARCHIVE_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)

echo ""
echo "=========================================="
echo -e "  ${GREEN}Бэкап завершён!${NC}"
echo "=========================================="
echo ""
echo "  📦 Архив: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo "  📏 Размер: ${ARCHIVE_SIZE}"
echo ""
echo "  Для восстановления:"
echo "    tar -xzf ${BACKUP_NAME}.tar.gz"
echo "    cp .env /path/to/vpn-project/"
echo "    docker compose up -d"
echo ""

# =============================================
# 7. Очистка старых бэкапов (хранить последние 5)
# =============================================
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
if [[ "$BACKUP_COUNT" -gt 5 ]]; then
    info "Очистка старых бэкапов (хранятся последние 5)..."
    ls -1t "$BACKUP_DIR"/*.tar.gz | tail -n +6 | xargs rm -f
    log "Старые бэкапы удалены"
fi
