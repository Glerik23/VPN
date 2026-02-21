#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — Полная деинсталляция VPN-сервера
# Удаляет контейнеры, образы, волюмы и очищает порты.
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
cd "$SCRIPT_DIR"

echo -e "${RED}"
echo "====================================================="
echo "   ⚠️  ВНИМАНИЕ: ПОЛНОЕ УДАЛЕНИЕ VPN-СЕРВЕРА ⚠️"
echo "====================================================="
echo -e "${NC}"

read -p "Вы уверены, что хотите удалить все контейнеры и данные? (y/n): " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# 1. Останавливаем проект через Docker Compose
info "Остановка Docker-контейнеров..."
if command -v docker-compose &> /dev/null; then
    docker-compose down --volumes --remove-orphans || true
elif docker compose version &> /dev/null; then
    docker compose down --volumes --remove-orphans || true
else
    warn "Docker Compose не найден, пробую остановить контейнеры вручную..."
    # Остановка контейнеров по именам из docker-compose
    docker stop 3x-ui hysteria2 VPN-Warp adguard monitoring-bot 2>/dev/null || true
    docker rm 3x-ui hysteria2 VPN-Warp adguard monitoring-bot 2>/dev/null || true
fi

# 2. Принудительная очистка портов
info "Очистка сетевых портов..."
# Собираем список портов для очистки
PORTS_TO_CLEAR=(80 443 2053 2222) # Дефолтные порты

# Если есть .env, добавляем порты оттуда
if [[ -f ".env" ]]; then
    source .env
    [[ -n "${XUI_PORT:-}" ]] && PORTS_TO_CLEAR+=("$XUI_PORT")
    [[ -n "${ADGUARD_PORT:-}" ]] && PORTS_TO_CLEAR+=("$ADGUARD_PORT")
    [[ -n "${HYSTERIA_PORT:-}" ]] && PORTS_TO_CLEAR+=("$HYSTERIA_PORT")
    [[ -n "${VLESS_PORT:-}" ]] && PORTS_TO_CLEAR+=("$VLESS_PORT")
    [[ -n "${SSH_PORT:-}" ]] && PORTS_TO_CLEAR+=("$SSH_PORT")
fi

# Убираем дубликаты
UNIQUE_PORTS=$(echo "${PORTS_TO_CLEAR[@]}" | tr ' ' '\n' | sort -u)

for PORT in $UNIQUE_PORTS; do
    # Пропускаем стандартный SSH (22) и текущий SSH_PORT, чтобы не выкинуло из системы
    [[ "$PORT" == "22" || "$PORT" == "${SSH_PORT:-22}" ]] && continue
    
    PIDS=$(ss -tulpn | grep ":$PORT " | awk '{print $NF}' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)
    if [[ -n "$PIDS" ]]; then
        warn "Порт $PORT занят процессом(ами): $PIDS. Убиваю..."
        for PID in $PIDS; do
            kill -9 "$PID" 2>/dev/null || true
        done
        log "Порт $PORT очищен."
    fi
done

# 3. Удаление Docker образов (опционально, но полезно для очистки места)
read -p "Удалить неиспользуемые Docker-образы? (y/n): " RM_IMAGES
if [[ "$RM_IMAGES" =~ ^[Yy]$ ]]; then
    info "Очистка Docker-образов..."
    docker image prune -a -f
fi

# 4. Очистка временных файлов и логов
info "Удаление логов и временных данных..."
rm -rf ./logs/*
rm -rf ./hysteria2/cert/*
rm -rf ./adguard/work/*
rm -rf ./adguard/conf/*
# Удаление куки API
rm -f /tmp/3xui_cookie.txt

# 5. Особый вопрос про .env
echo ""
warn "В файле .env хранятся ваши пароли и ключи."
read -p "Удалить файл .env? (y/n): " RM_ENV
if [[ "$RM_ENV" =~ ^[Yy]$ ]]; then
    rm -f .env
    log "Файл .env удален."
else
    info "Файл .env сохранен."
fi

echo ""
echo "====================================================="
echo -e "   ${GREEN}✨ ДЕИНСТАЛЛЯЦИЯ ЗАВЕРШЕНА ✨${NC}"
echo "====================================================="
echo "Теперь вы можете запустить master_setup.sh на чистой системе."
echo ""
