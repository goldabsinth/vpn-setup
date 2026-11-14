#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Скрипт нужно запускать от root или через sudo"
fi

# ==========================================
# ВВОД ПУБЛИЧНОГО КЛЮЧА
# ==========================================
read -p "Введите имя пользователя: " USERNAME

if [ -z "$USERNAME" ]; then
    error "Имя пользователя не может быть пустым"
fi

info "Будет создан пользователь: $USERNAME"

echo ""
warn "Вставьте ваш публичный SSH-ключ (одной строкой) и нажмите Enter:"
echo "Пример: ssh-ed25519 AAAA... ваш_комментарий"
read -r PUBLIC_KEY

if [ -z "$PUBLIC_KEY" ]; then
    error "Ключ не был введён"
fi

if ! echo "$PUBLIC_KEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/=]+'; then
    error "Невалидный SSH-ключ"
fi

info "Получен ключ: ${PUBLIC_KEY:0:30}..."

echo ""
read -p "Скрипт внесёт изменения в систему. Продолжить? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    exit 0
fi

# ==========================================
# 1. АПДЕЙТ СИСТЕМЫ
# ==========================================
info "Обновление системы..."
apt update && apt upgrade -y && apt autoremove -y && apt clean

# ==========================================
# 2. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
# ==========================================
info "Создание пользователя $USERNAME..."
if id "$USERNAME" &>/dev/null; then
    warn "Пользователь $USERNAME уже существует"
else
    adduser --disabled-password --gecos "" "$USERNAME"
fi
usermod -aG sudo "$USERNAME"

# ==========================================
# 4. НАСТРОЙКА SSH
# ==========================================
info "Настройка SSH для $USERNAME..."
USER_HOME="/home/$USERNAME"

mkdir -p "$USER_HOME/.ssh"
echo "$PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# Харднинг sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
info "SSH настроен"

# ==========================================
# 5. FAIL2BAN
# ==========================================
info "Установка fail2ban..."
apt install fail2ban -y

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

systemctl enable --now fail2ban

# ==========================================
# 6. FIREWALL (UFW)
# ==========================================
info "Настройка UFW..."
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing

ufw allow ssh
ufw allow http
ufw allow https

ufw --force enable

# ==========================================
# 7. ПОЛЕЗНЫЕ ДОПОЛНЕНИЯ
# ==========================================
info "Установка утилит..."
apt install -y curl wget git htop net-tools unzip jq tcpdump

info "Настройка часового пояса..."
timedatectl set-timezone Europe/Moscow

info "Автоматические обновления..."
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
apt install unattended-upgrades -y
dpkg-reconfigure -plow unattended-upgrades

echo ""
echo "=================================================="
echo -e "${GREEN}✅ VPS подготовлен!${NC}"
echo "=================================================="
echo ""
info "Проверьте вход в НОВОМ окне терминала:"
echo "  ssh $USERNAME@<IP_VPS>"
echo ""
warn "НЕ ЗАКРЫВАЙТЕ текущую сессию!"
echo ""
