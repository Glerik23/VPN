#!/usr/bin/env bash
# =============================================================================
# 01-init-server.sh — Защита сервера
# Настройка SSH, UFW, fail2ban, unattended-upgrades
# Запускать от root на чистом Ubuntu 22.04+ / Debian 12+
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

# --- Предварительные проверки ---
[[ $EUID -ne 0 ]] && err "Этот скрипт нужно запускать от root"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Загрузка .env
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
else
    err "Файл .env не найден. Скопируй .env.example в .env и заполни значения."
fi

SSH_PORT="${SSH_PORT:-2222}"
F2B_MAXRETRY="${F2B_MAXRETRY:-3}"
F2B_BANTIME="${F2B_BANTIME:-3600}"
XUI_PORT="${XUI_PORT:-2053}"
ADGUARD_PORT="${ADGUARD_PORT:-3000}"

echo ""
echo "=========================================="
echo "  VPN-сервер — Защита сервера"
echo "=========================================="
echo ""

# =============================================
# 1. Настройка DNS и обновление системы
# =============================================
info "Настройка DNS..."
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    # Если файл не является симлинком на systemd-resolved, меняем его
    if [[ ! -L /etc/resolv.conf ]]; then
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        log "Google DNS установлен"
    else
        warn "Конфигурация DNS управляется системой (симлинк). Пропускаю ручную правку /etc/resolv.conf"
    fi
else
    log "DNS уже настроен"
fi

info "Обновление системных пакетов..."
apt update && apt upgrade -y
log "Система обновлена"

# =============================================
# 2. Установка необходимых пакетов
# =============================================
info "Установка необходимых пакетов..."
apt install -y \
    curl wget git nano \
    ufw fail2ban \
    unattended-upgrades apt-listchanges \
    qrencode jq \
    htop net-tools apache2-utils
log "Пакеты установлены"

# =============================================
# 3. Настройка пароля root
# =============================================
if [[ -n "$ROOT_PASSWORD" ]]; then
    info "Установка пароля для root..."
    printf "root:%s\n" "$ROOT_PASSWORD" | chpasswd
    log "Пароль root изменён"
else
    warn "ROOT_PASSWORD не задан в .env — вход по паролю может не работать!"
fi

info "Настройка SSH на порту ${SSH_PORT}..."

# Бэкап оригинального конфига
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Перевірка наявності SSH-ключів перед відключенням паролів
if [[ ! -f /root/.ssh/authorized_keys ]] || [[ ! -s /root/.ssh/authorized_keys ]]; then
    warn "⚠️  Файл /root/.ssh/authorized_keys порожній або відсутній!"
    warn "⚠️  Відключення паролів ЗАБОРОНЕНО, щоб ви не втратили доступ."
    SSH_PASSWORD_AUTH="yes"
else
    log "SSH-ключі виявлені. Парольна автентифікація буде вимкнена."
    SSH_PASSWORD_AUTH="no"
fi

# Применение защищённого SSH-конфига
cat > /etc/ssh/sshd_config.d/99-hardened.conf << EOF
# --- Защищённая конфигурация SSH ---
Port ${SSH_PORT}
PermitRootLogin yes
PasswordAuthentication ${SSH_PASSWORD_AUTH}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers root
X11Forwarding no
AllowTcpForwarding no
EOF

# Проверка, что основной конфиг включает директорию .d
if ! grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
fi

# Перезапуск SSH
systemctl restart sshd
log "SSH настроен на порту ${SSH_PORT} (PasswordAuth: ${SSH_PASSWORD_AUTH})"

warn "⚠️  ВАЖНО: Убедись, что SSH-ключи настроены, прежде чем отключаться!"
warn "⚠️  Проверь в НОВОМ терминале: ssh -p ${SSH_PORT} root@${SERVER_IP}"

# =============================================
# 4. Фаервол UFW
# =============================================
info "Настройка фаервола UFW..."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow "${SSH_PORT}/tcp" comment 'SSH'

# Панель 3x-ui
ufw allow "${XUI_PORT}/tcp" comment '3x-ui Panel'

# VLESS + REALITY (TCP)
ufw allow "${VLESS_PORT:-443}/tcp" comment 'VLESS REALITY'

# Hysteria 2 (UDP)
ufw allow "${HYSTERIA_PORT:-443}/udp" comment 'Hysteria 2'

# AdGuard Home
ufw allow "${ADGUARD_PORT}/tcp" comment 'AdGuard Home'

ufw --force enable
log "UFW настроен и включён"
ufw status verbose

# =============================================
# 5. Fail2Ban
# =============================================
info "Настройка fail2ban..."

# Копирование пользовательских конфигов
cp "$PROJECT_DIR/configs/fail2ban/jail.local" /etc/fail2ban/jail.local

# Создание фильтра для 3x-ui
if [[ -f "$PROJECT_DIR/configs/fail2ban/filter.d/3x-ui.conf" ]]; then
    cp "$PROJECT_DIR/configs/fail2ban/filter.d/3x-ui.conf" /etc/fail2ban/filter.d/3x-ui.conf
fi

# Обновление портов в конфиге jail
sed -i "s/port     = 2222/port     = ${SSH_PORT}/" /etc/fail2ban/jail.local
sed -i "s/port     = 2053/port     = ${XUI_PORT}/" /etc/fail2ban/jail.local
sed -i "s/maxretry = 3/maxretry = ${F2B_MAXRETRY}/" /etc/fail2ban/jail.local
sed -i "s/bantime  = 3600/bantime  = ${F2B_BANTIME}/" /etc/fail2ban/jail.local

systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban настроен и запущен"

# =============================================
# 6. Автоматические обновления безопасности
# =============================================
info "Настройка автоматических обновлений безопасности..."

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
log "Автоматические обновления безопасности включены"

# =============================================
# 7. Оптимизация сети
# =============================================
info "Применение сетевых оптимизаций..."

cat >> /etc/sysctl.conf << 'EOF'

# --- Сетевые оптимизации VPN-сервера ---
# BBR — управление перегрузкой (лучшая скорость для прокси)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Увеличение буферов
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Включение IP-форвардинга (для прокси)
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

# Отслеживание соединений
net.netfilter.nf_conntrack_max=131072
EOF

sysctl -p > /dev/null 2>&1
log "Сетевые оптимизации применены (BBR включён)"

echo ""
echo "=========================================="
echo -e "  ${GREEN}Защита сервера завершена!${NC}"
echo "=========================================="
echo ""
echo "  SSH-порт:        ${SSH_PORT}"
echo "  Фаервол:         UFW включён"
echo "  Защита от брута: fail2ban активен"
echo "  Автообновления:  включены"
echo "  TCP congestion:  BBR"
echo ""
warn "Следующий шаг: ./02-install-docker.sh"
echo ""
