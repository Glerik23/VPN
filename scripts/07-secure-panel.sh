#!/usr/bin/env bash
# =============================================================================
# 07-secure-panel.sh — Смена порта панели 3x-ui на нестандартный
# Автоматически меняет порт, обновляет фаервол, перезапускает контейнер
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

[[ ! -f "$PROJECT_DIR/.env" ]] && err "Файл .env не найден"
source "$PROJECT_DIR/.env"

OLD_PORT="${XUI_PORT:-2053}"

echo ""
echo "=========================================="
echo "  Защита панели 3x-ui"
echo "=========================================="
echo ""
echo "  Текущий порт панели: ${OLD_PORT}"
echo ""

# =============================================
# 1. Ввод нового порта
# =============================================
if [[ -n "${1:-}" ]]; then
    NEW_PORT="$1"
else
    read -rp "  Введи новый порт (рекомендуется 10000-65535): " NEW_PORT
fi

# Проверка порта
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [[ "$NEW_PORT" -lt 1024 ]] || [[ "$NEW_PORT" -gt 65535 ]]; then
    err "Некорректный порт. Используй число от 1024 до 65535"
fi

if [[ "$NEW_PORT" == "$OLD_PORT" ]]; then
    warn "Новый порт совпадает с текущим. Ничего не изменено."
    exit 0
fi

echo ""
info "Меняем порт панели: ${OLD_PORT} → ${NEW_PORT}"

# =============================================
# 2. Смена порта в 3x-ui
# =============================================
info "Обновление порта в контейнере 3x-ui..."

docker exec -i 3x-ui /app/x-ui setting -port "$NEW_PORT" 2>/dev/null || \
    err "Не удалось изменить порт. Проверь, запущен ли контейнер: docker compose ps"

log "Порт в 3x-ui изменён на ${NEW_PORT}"

# =============================================
# 3. Обновление фаервола
# =============================================
info "Обновление правил фаервола..."

ufw allow "${NEW_PORT}/tcp" comment '3x-ui Panel (new)' 2>/dev/null
ufw delete allow "${OLD_PORT}/tcp" 2>/dev/null || true

log "Фаервол обновлён: ${OLD_PORT} закрыт, ${NEW_PORT} открыт"

# =============================================
# 4. Обновление .env
# =============================================
info "Обновление .env..."

if grep -q "^XUI_PORT=" "$PROJECT_DIR/.env"; then
    sed -i "s|^XUI_PORT=.*|XUI_PORT=${NEW_PORT}|" "$PROJECT_DIR/.env"
else
    echo "XUI_PORT=${NEW_PORT}" >> "$PROJECT_DIR/.env"
fi

log ".env обновлён"

# =============================================
# 5. Обновление fail2ban
# =============================================
if [[ -f /etc/fail2ban/jail.local ]]; then
    info "Обновление fail2ban..."
    sed -i "s/port     = ${OLD_PORT}/port     = ${NEW_PORT}/" /etc/fail2ban/jail.local
    systemctl restart fail2ban 2>/dev/null || true
    log "fail2ban обновлён"
fi

# =============================================
# 6. Перезапуск контейнера
# =============================================
info "Перезапуск 3x-ui..."
docker restart 3x-ui
sleep 3
log "3x-ui перезапущен"

echo ""
echo "=========================================="
echo -e "  ${GREEN}Порт панели изменён!${NC}"
echo "=========================================="
echo ""
echo "  Старый URL: http://${SERVER_IP}:${OLD_PORT}"
echo "  Новый URL:  http://${SERVER_IP}:${NEW_PORT}"
echo ""
warn "Запомни новый порт! Старый порт больше недоступен."
echo ""
