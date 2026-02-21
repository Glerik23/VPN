#!/usr/bin/env bash
# =============================================================================
# 05-show-clients.sh — Генерация клиентских ссылок и QR-кодов
# Выводит VLESS и Hysteria2 share-ссылки для клиентских приложений
# =============================================================================
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[[ ! -f "$PROJECT_DIR/.env" ]] && err "Файл .env не найден"
source "$PROJECT_DIR/.env"

# Проверка наличия ключей
[[ -z "${REALITY_PUBLIC_KEY:-}" ]] && err "REALITY_PUBLIC_KEY не задан. Запусти 04-generate-keys.sh"
[[ -z "${VLESS_UUID:-}" ]] && err "VLESS_UUID не задан. Запусти 04-generate-keys.sh"
[[ -z "${HYSTERIA_PASSWORD:-}" ]] && err "HYSTERIA_PASSWORD не задан. Запусти 04-generate-keys.sh"
[[ -z "${HYSTERIA_OBFS_PASSWORD:-}" ]] && err "HYSTERIA_OBFS_PASSWORD не задан. Запусти 04-generate-keys.sh"

# Обработка аргументов
LINKS_ONLY=false
if [[ "${1:-}" == "--links-only" ]]; then
    LINKS_ONLY=true
fi

if [[ "$LINKS_ONLY" == "false" ]]; then
    echo ""
    echo "=========================================="
    echo "  Ссылки для подключения клиентов"
    echo "=========================================="
fi

# =============================================
# 1. Ссылка VLESS + REALITY
# =============================================
# Поддержка IPv6 (заключение в квадратные скобки)
if [[ "$SERVER_IP" == *":"* ]]; then
    URI_IP="[$SERVER_IP]"
else
    URI_IP="$SERVER_IP"
fi

VLESS_LINK="vless://${VLESS_UUID}@${URI_IP}:${VLESS_PORT:-443}?type=tcp&security=reality&pbk=${REALITY_PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI:-www.microsoft.com}&sid=${REALITY_SHORT_ID}&spx=%2F&flow=xtls-rprx-vision#VPN-VLESS-REALITY"

if [[ "$LINKS_ONLY" == "true" ]]; then
    echo "$VLESS_LINK"
else
    echo ""
    echo -e "${BOLD}━━━ VLESS + REALITY (основной) ━━━${NC}"
    echo ""
    echo -e "${CYAN}${VLESS_LINK}${NC}"
    echo ""

    # QR-код
    if command -v qrencode &> /dev/null; then
        echo "QR-код:"
        qrencode -t ansiutf8 "$VLESS_LINK"
        echo ""
    else
        warn "Установи qrencode для QR-кодов: apt install qrencode"
    fi
fi

# =============================================
# 2. Ссылка Hysteria2
# =============================================
HYSTERIA_LINK="hysteria2://${HYSTERIA_PASSWORD}@${URI_IP}:${HYSTERIA_PORT:-443}?insecure=1&sni=${REALITY_SNI:-www.microsoft.com}&obfs=salamander&obfs-password=${HYSTERIA_OBFS_PASSWORD}#VPN-Hysteria2"

if [[ "$LINKS_ONLY" == "true" ]]; then
    echo "$HYSTERIA_LINK"
else
    echo -e "${BOLD}━━━ Hysteria 2 (резервный) ━━━${NC}"
    echo ""
    echo -e "${CYAN}${HYSTERIA_LINK}${NC}"
    echo ""

    # QR-код
    if command -v qrencode &> /dev/null; then
        echo "QR-код:"
        qrencode -t ansiutf8 "$HYSTERIA_LINK"
        echo ""
    fi
fi

# =============================================
# 3. Рекомендуемые клиентские приложения
# =============================================
if [[ "$LINKS_ONLY" == "false" ]]; then
    echo ""
    echo "=========================================="
    echo "  Рекомендуемые приложения"
    echo "=========================================="
    echo ""
    echo "  📱 iOS:"
    echo "     • Streisand (App Store) — VLESS + Hysteria2"
    echo "     • Shadowrocket (App Store, платный) — все протоколы"
    echo ""
    echo "  🤖 Android:"
    echo "     • v2rayNG (Google Play / GitHub) — VLESS"
    echo "     • NekoBox (GitHub) — VLESS + Hysteria2"
    echo "     • Hiddify (Google Play / GitHub) — все протоколы"
    echo ""
    echo "  🖥️  Windows:"
    echo "     • Hiddify Next (GitHub) — все протоколы"
    echo "     • Nekoray (GitHub) — VLESS + Hysteria2"
    echo "     • v2rayN (GitHub) — VLESS"
    echo ""
    echo "  🍎 macOS:"
    echo "     • Hiddify Next (GitHub) — все протоколы"
    echo "     • Streisand (App Store)"
    echo "     • FoXray (App Store)"
    echo ""
    echo "  🐧 Linux:"
    echo "     • Hiddify Next (GitHub)"
    echo "     • Nekoray (GitHub)"
    echo ""
    echo "  💡 Как подключиться:"
    echo "     1. Установи приложение"
    echo "     2. Скопируй ссылку выше или отсканируй QR-код"
    echo "     3. Добавь как новый профиль/сервер"
    echo "     4. Подключись!"
    echo ""

    # Сохранение ссылок в файл
    LINKS_FILE="$PROJECT_DIR/client-links.txt"
    cat > "$LINKS_FILE" << EOF
# Ссылки для VPN-клиентов
# Сгенерировано: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ⚠️  НЕ публикуй этот файл!

## VLESS + REALITY (основной)
${VLESS_LINK}

## Hysteria 2 (резервный)
${HYSTERIA_LINK}
EOF

    log "Ссылки сохранены в client-links.txt"
    warn "⚠️  Добавь client-links.txt в .gitignore!"
    echo ""
fi
