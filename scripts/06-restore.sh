#!/usr/bin/env bash
# =============================================================================
# 06-restore.sh — Восстановление VPN из бэкапа
# =============================================================================
set -euo pipefail

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

BACKUP_DIR="/root/VPN-backups"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================="
echo "  VPN-сервер — Восстановление"
echo "=========================================="

# 1. Выбор архива
if [[ ! -d "$BACKUP_DIR" ]]; then
    err "Директория с бэкапами не найдена: $BACKUP_DIR"
fi

FILES=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
if [[ ${#FILES[@]} -eq 0 ]]; then
    err "Нет доступных архивов в $BACKUP_DIR"
fi

if [[ -n "${1:-}" ]]; then
    SELECTED_FILE="$1"
else
    echo "Выберите архив для восстановления:"
    for i in "${!FILES[@]}"; do
        echo "[$i] $(basename "${FILES[$i]}")"
    done
    read -p "Введите номер: " CHOICE
    SELECTED_FILE="${FILES[$CHOICE]}"
fi

[[ ! -f "$SELECTED_FILE" ]] && err "Файл не найден"

info "Восстановление из $(basename "$SELECTED_FILE")..."
TEMP_RESTORE="/tmp/VPN-restore-$(date +%s)"
mkdir -p "$TEMP_RESTORE"
tar -xzf "$SELECTED_FILE" -C "$TEMP_RESTORE"

# Определяем имя папки внутри архива (обычно VPN-backup-YYYYMMDD_HHMMSS)
INNER_DIR=$(ls -1 "$TEMP_RESTORE" | head -n 1)
RESTORE_SRC="$TEMP_RESTORE/$INNER_DIR"

# 2. Восстановление файлов
info "Восстановление файлов в $PROJECT_DIR..."

# .env
if [[ -f "$RESTORE_SRC/.env" ]]; then
    cp "$RESTORE_SRC/.env" "$PROJECT_DIR/.env"
    log ".env восстановлен"
fi

# Hysteria2 configs
if [[ -d "$RESTORE_SRC/hysteria2" ]]; then
    mkdir -p "$PROJECT_DIR/hysteria2"
    cp -r "$RESTORE_SRC/hysteria2/"* "$PROJECT_DIR/hysteria2/"
    log "Конфиги Hysteria2 восстановлены"
fi

# 3x-ui Database (Docker Volume)
if [[ -d "$RESTORE_SRC/3xui-db" ]]; then
    info "Восстановление базы данных 3x-ui..."
    docker volume create 3xui-db >/dev/null || true
    docker run --rm \
        -v 3xui-db:/dest \
        -v "$RESTORE_SRC/3xui-db":/source \
        alpine sh -c "cp -a /source/* /dest/"
    log "База данных 3x-ui восстановлена"
fi

# Fail2ban
if [[ -d "$RESTORE_SRC/fail2ban" ]]; then
    mkdir -p "$PROJECT_DIR/configs/fail2ban"
    cp -r "$RESTORE_SRC/fail2ban/"* "$PROJECT_DIR/configs/fail2ban/"
    log "Конфиги fail2ban восстановлены"
fi

# 3. Перезапуск
read -p "Перезапустить Docker-контейнеры сейчас? (y/n): " RESTART
if [[ "$RESTART" =~ ^[Yy]$ ]]; then
    cd "$PROJECT_DIR"
    docker compose up -d --remove-orphans
    log "Контейнеры запущены"
fi

rm -rf "$TEMP_RESTORE"
echo ""
log "Восстановление успешно завершено!"
