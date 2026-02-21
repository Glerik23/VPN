#!/usr/bin/env bash
# ============ 00-pre-check.sh =============
# Скрипт для проверки конфигурации перед установкой
# ===========================================
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
log()  { echo -e "${GREEN}[✓]${NC} $1"; }

ENV_FILE=".env"

# 1. Проверка существования .env
if [[ ! -f "$ENV_FILE" ]]; then
    err "Файл .env не найден! Пожалуйста, скопируйте .env.example в .env и настройте его."
fi

source "$ENV_FILE"

# Список обязательных переменных и их дефолтных (запрещенных) значений
declare -A CHECKS=(
    # SERVER_IP теперь определяется автоматически, но пользователь может задать жестко
    ["ROOT_PASSWORD"]="CHANGE_ME_STRONG_PASSWORD"
    ["XUI_PASSWORD"]="CHANGE_ME_STRONG_PASSWORD"
    ["TG_BOT_TOKEN"]=""
    ["TG_CHAT_ID"]=""
)

# Дополнительные проверки на дефолтные логины/пароли
declare -A DEFAULTS=(
    ["USERNAME"]="admin"
    ["PASSWORD"]="admin"
    ["XUI_USERNAME"]="admin"
)

info "Запуск предварительной проверки конфигурации..."
FAILED=0

# Проверка критических полей
for VAR in "${!CHECKS[@]}"; do
    VAL="${!VAR:-}"
    DEFAULT_VAL="${CHECKS[$VAR]}"
    
    # Игнорируем проверку SERVER_IP, так как мы его определим сами
    if [[ "$VAR" == "SERVER_IP" ]]; then continue; fi

    if [[ -z "$VAL" ]]; then
        warn "Переменная $VAR не установлена в .env!"
        FAILED=1
    elif [[ "$VAL" == "$DEFAULT_VAL" ]]; then
        warn "Переменная $VAR содержит стандартное значение: $VAL"
        FAILED=1
    fi
done

# --- Автоопределение SERVER_IP ---
if [[ -z "${SERVER_IP:-}" ]] || [[ "$SERVER_IP" == "YOUR_SERVER_IP" ]]; then
    info "SERVER_IP не задан или задан по умолчанию. Попытка автоматического определения..."
    DETECTED_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 icanhazip.com || true)
    
    if [[ -n "$DETECTED_IP" ]]; then
        log "Успешно определен публичный IP сервера: $DETECTED_IP"
        # Записываем в .env чтобы другие скрипты могли его использовать
        sed -i "s/^SERVER_IP=.*/SERVER_IP=$DETECTED_IP/" "$ENV_FILE"
        export SERVER_IP="$DETECTED_IP"
    else
        err "Не удалось автоматически определить IP адрес сервера. Пожалуйста, укажите SERVER_IP в .env вручную."
    fi
fi

# Проверка занятости критических портов
info "Проверка сетевых портов..."
for PORT in 80 443; do
    if ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        # Проверяем, не Docker ли это уже
        if ! ss -lnpt | grep ":$PORT " | grep -q "docker"; then
            warn "Порт $PORT уже занят другим процессом! Это может помешать установке."
            FAILED=1
        fi
    fi
done

# Проверка версии ядра для BBR
info "Проверка совместимости BBR..."
KERNEL_VER=$(uname -r | cut -d. -f1,2)
if ! awk "BEGIN{exit !($KERNEL_VER >= 4.9)}"; then
    warn "Версия ядра ($KERNEL_VER) слишком старая для BBR. Оптимизация сети будет ограничена."
fi

# Проверка на слабые пароли (опционально, но важно)
for VAR in "${!DEFAULTS[@]}"; do
    VAL="${!VAR:-}"
    DEFAULT_VAL="${DEFAULTS[$VAR]}"
    if [[ "$VAL" == "$DEFAULT_VAL" ]]; then
        info "Переменная $VAR использует значение по умолчанию: $VAL (рекомендуется сменить после установки)"
    fi
done

if [[ $FAILED -eq 1 ]]; then
    echo -e "\n${RED}=====================================================${NC}"
    echo -e "${RED}   ОШИБКА: Конфигурация .env не завершена!${NC}"
    echo -e "${RED}=====================================================${NC}"
    info "Пожалуйста, исправьте указанные выше параметры в файле .env"
    info "Команда для редактирования: nano .env"
    exit 1
fi

log "Проверка конфигурации пройдена успешно."
exit 0
