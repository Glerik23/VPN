#!/usr/bin/env bash
# ============= 10-setup-adguard.sh =============
set -euo pipefail

info() { echo -e "\033[0;36m[i]\033[0m $1"; }
log()  { echo -e "\033[0;32m[✓]\033[0m $1"; }
err()  { echo -e "\033[0;31m[✗]\033[0m $1"; exit 1; }

# Загрузка переменных
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
else
    err "Файл .env не найден!"
fi

ADGUARD_CONF_DIR="$PROJECT_DIR/adguard/conf"
mkdir -p "$ADGUARD_CONF_DIR"

info "Генерация конфигурации AdGuard Home..."

# Используем переменные из .env или значения по умолчанию
ADMIN_USER="${USERNAME:-admin}"
ADMIN_PASS="${PASSWORD:-admin}"
ADGUARD_PORT="${ADGUARD_PORT:-3000}"

# Генерация bcrypt хеша пароля через Python
# AdGuard Home требует именно bcrypt. Мы используем встроенный в Python модуль или passlib, если есть.
PASSWORD_HASH=$(python3 -c "
import base64
try:
    import bcrypt
    print(bcrypt.hashpw('$ADMIN_PASS'.encode(), bcrypt.gensalt()).decode())
except ImportError:
    try:
        from passlib.hash import bcrypt
        print(bcrypt.hash('$ADMIN_PASS'))
    except ImportError:
        import sys
        sys.exit(1)
" 2>/dev/null || {
    if command -v htpasswd >/dev/null; then
        htpasswd -bnBC 10 \"\" \"$ADMIN_PASS\" | tr -d ':\n'
    else
        echo \"$ADMIN_PASS\"
    fi
})

cat > "$ADGUARD_CONF_DIR/AdGuardHome.yaml" <<EOF
bind_host: 0.0.0.0
bind_port: $ADGUARD_PORT
users:
  - name: $ADMIN_USER
    password: $PASSWORD_HASH
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
filtering:
  enabled: true
  interval: 24
  filters:
    - enabled: true
      url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
      name: AdGuard DNS filter
      id: 1
    - enabled: true
      url: https://big.oisd.nl
      name: OISD Big
      id: 2
    - enabled: true
      url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
      name: AdAway Default Blocklist
      id: 3
filters:
  - enabled: true
    id: 1
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
  - enabled: true
    id: 2
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
EOF

log "Конфигурация создана в $ADGUARD_CONF_DIR/AdGuardHome.yaml"
info "Перезапуск AdGuard для применения настроек..."
cd "$PROJECT_DIR" && docker compose restart adguard
log "AdGuard теперь должен быть доступен по логину/паролю из .env!"
