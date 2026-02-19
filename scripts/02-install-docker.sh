#!/usr/bin/env bash
# =============================================================================
# 02-install-docker.sh — Установка Docker CE + Docker Compose Plugin
# Для Ubuntu 22.04+ / Debian 12+
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

# Обработка ошибок
error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    echo -e "${RED}[✗] Ошибка в строке $line_number: команда '$command' завершилась с кодом $exit_code${NC}"
    exit $exit_code
}
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

[[ $EUID -ne 0 ]] && err "Этот скрипт нужно запускать от root"

echo ""
echo "=========================================="
echo "  Установка Docker CE"
echo "=========================================="
echo ""

# Проверка, установлен ли Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    warn "Docker уже установлен: ${DOCKER_VERSION}"
    
    if command -v docker compose &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        warn "Docker Compose уже установлен: ${COMPOSE_VERSION}"
        log "Пропускаем установку. Docker готов."
        exit 0
    fi
fi

# =============================================
# 1. Удаление старых версий
# =============================================
info "Удаление старых версий Docker (если есть)..."
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
log "Старые версии удалены"

# =============================================
# 2. Установка зависимостей
# =============================================
info "Установка зависимостей..."
apt update
apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
log "Зависимости установлены"

# =============================================
# 3. Добавление GPG-ключа Docker
# =============================================
info "Добавление GPG-ключа Docker..."
install -m 0755 -d /etc/apt/keyrings

# Определение дистрибутива
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="${ID}"
else
    err "Не удалось определить дистрибутив Linux"
fi

curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
log "GPG-ключ добавлен"

# =============================================
# 4. Добавление репозитория Docker
# =============================================
info "Добавление репозитория Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/${DISTRO} \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
log "Репозиторий добавлен"

# =============================================
# 5. Установка Docker
# =============================================
info "Установка Docker CE..."
apt update
apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
log "Docker CE установлен"

# =============================================
# 6. Включение и запуск Docker
# =============================================
info "Включение сервиса Docker..."
systemctl enable docker
systemctl start docker
log "Сервис Docker запущен"

# =============================================
# 7. Проверка
# =============================================
echo ""
docker --version
docker compose version
echo ""

log "Установка Docker завершена!"
echo ""
warn "Следующий шаг: ./03-deploy.sh"
echo ""
