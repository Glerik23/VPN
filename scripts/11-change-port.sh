#!/usr/bin/env bash
# =============================================================================
# 11-change-port.sh — Смена порта Hysteria 2 и обновление фаервола
# Использование: ./11-change-port.sh <новый_порт>
# =============================================================================
set -euo pipefail

NEW_PORT=$1

if [[ -z "$NEW_PORT" ]]; then
    echo "Ошибка: не указан новый порт"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOTENV="$PROJECT_DIR/.env"

if [[ ! -f "$DOTENV" ]]; then
    echo "Ошибка: файл .env не найден"
    exit 1
fi

# Загружаем текущие настройки
source "$DOTENV"
OLD_PORT="${HYSTERIA_PORT:-443}"

echo "--- Смена порта Hysteria 2 ---"
echo "Старый порт: $OLD_PORT"
echo "Новый порт: $NEW_PORT"

# 1. Обновляем .env (используем sed для замены значения)
# Ищем строку HYSTERIA_PORT=... и заменяем её полностью
if grep -q "HYSTERIA_PORT=" "$DOTENV"; then
    sed -i "s/^HYSTERIA_PORT=.*/HYSTERIA_PORT=$NEW_PORT/" "$DOTENV"
else
    echo "HYSTERIA_PORT=$NEW_PORT" >> "$DOTENV"
fi

# 2. Обновляем фаервол (UFW)
if command -v ufw > /dev/null; then
    echo "Обновление правил UFW..."
    # Удаляем старое правило (если оно было)
    ufw delete allow "$OLD_PORT/udp" || true
    # Добавляем новое правило
    ufw allow "$NEW_PORT/udp" comment 'Hysteria2 (Auto)'
    echo "UFW обновлен."
fi

# 3. Синхронизация Reality (на случай, если SNI тоже меняли)
if [[ -f "$SCRIPT_DIR/08-setup-inbound.sh" ]]; then
    echo "Синхронизация настроек VLESS Reality..."
    bash "$SCRIPT_DIR/08-setup-inbound.sh"
fi

# 4. Перегенерация конфига Hysteria2
echo "Обновление конфигурации Hysteria2..."
HYSTERIA_CONFIG="$PROJECT_DIR/hysteria2/config.yaml"
if [[ -f "${HYSTERIA_CONFIG}.template" ]]; then
    # Перезагружаем переменные из .env чтобы получить свежие данные, включая новый порт
    source "$DOTENV"
    cp "${HYSTERIA_CONFIG}.template" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_PASSWORD__|${HYSTERIA_PASSWORD}|g" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_UP__|${HYSTERIA_UP_MBPS:-100} mbps|g" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_DOWN__|${HYSTERIA_DOWN_MBPS:-100} mbps|g" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_MASQUERADE__|${REALITY_SNI:-www.microsoft.com}|g" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_OBFS_PASSWORD__|${HYSTERIA_OBFS_PASSWORD:-}|g" "${HYSTERIA_CONFIG}.tmp"
    sed -i "s|__HYSTERIA_PORT__|${NEW_PORT}|g" "${HYSTERIA_CONFIG}.tmp"
    mv "${HYSTERIA_CONFIG}.tmp" "$HYSTERIA_CONFIG"
else
    echo "⚠️ Шаблон ${HYSTERIA_CONFIG}.template не найден, обновляю порт в текущем конфиге..."
    sed -i "s/listen: :$OLD_PORT/listen: :$NEW_PORT/g" "$HYSTERIA_CONFIG"
fi

# 5. Перезапускаем контейнер
echo "Перезапуск контейнера Hysteria2..."
cd "$PROJECT_DIR"
docker compose --env-file .env restart hysteria2

echo "✅ Порт успешно изменен на $NEW_PORT"
echo "⚠️  ВАЖНО: Теперь вам нужно обновить ссылку в вашем VPN-клиенте!"
