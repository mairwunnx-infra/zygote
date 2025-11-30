#!/usr/bin/env bash
set -euo pipefail

IFACE=${IFACE:-ens3}
V6_PREFIX=${V6_PREFIX:-"2a09:7c47:0:2e::/64"}
V6_HOST=${V6_HOST:-"2a09:7c47:0:2e::1/64"}
V6_DOCKER_SUBNET=${V6_DOCKER_SUBNET:-"2a09:7c47:0:2e:1000::/80"}

echo "🐧 Обновление системы..."
sudo apt update && sudo apt -y upgrade

echo "🐧 Установка базовых пакетов..."
sudo apt -y install curl ca-certificates gnupg lsb-release git jq unzip htop chrony zram-tools unattended-upgrades

echo "🐧 Установка часового пояса Europe/Moscow..."
sudo timedatectl set-timezone Europe/Moscow

# ============================================================
# SECURITY: Автоматические обновления безопасности
# ============================================================

echo "🔒 Настройка автоматических security-обновлений..."

sudo tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Автоматически удалять неиспользуемые зависимости
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Автоматически перезагружать если требуется (ночью)
Unattended-Upgrade::Automatic-Reboot "false";

// Логировать в syslog
Unattended-Upgrade::SyslogEnable "true";
EOF

sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

sudo systemctl enable unattended-upgrades
sudo systemctl start unattended-upgrades

echo "✅ Автоматические security-обновления настроены."

# ============================================================
# JOURNALD: Ограничение размера логов
# ============================================================

echo "📝 Настройка лимитов journald..."

sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/size.conf >/dev/null <<EOF
[Journal]
SystemMaxUse=256M
SystemMaxFileSize=32M
MaxRetentionSec=1month
EOF

sudo systemctl restart systemd-journald

echo "✅ Лимиты journald настроены (макс. 500M)."

# ============================================================
# SWAP: Файл подкачки
# ============================================================

echo "🐧 Создание swap-файла (4G)..."

if swapon --show | grep -q '/swapfile'; then
  echo "ℹ️  Swap-файл уже активен, пропускаем."
else
  sudo swapoff /swapfile 2>/dev/null || true
  
  sudo rm -f /swapfile
  
  sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
  
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
  
  sudo swapon /swapfile
  echo "✅ Swap-файл создан."
fi

# ============================================================
# ZRAM: Сжатый swap в RAM
# ============================================================

echo "🐧 Настройка zram..."

sudo tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

# Сбрасываем zram если уже существует, иначе restart упадёт
if [ -e /sys/block/zram0 ]; then
  sudo swapoff /dev/zram0 2>/dev/null || true
  echo 1 | sudo tee /sys/block/zram0/reset >/dev/null 2>&1 || true
fi

sudo systemctl restart zramswap
sudo systemctl enable zramswap

echo "✅ zramswap настроен и включен."

# ============================================================
# SYSCTL: Swappiness
# ============================================================

echo "🐧 Настройка swappiness..."

# Проверяем, есть ли уже настройка swappiness
if ! grep -q '^vm.swappiness' /etc/sysctl.conf; then
  echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf >/dev/null
else
  sudo sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
fi
sudo sysctl -p

echo "✅ Swappiness настроен."

# ============================================================
# IPv6: Настройка адреса и форвардинга
# ============================================================

echo "🌐 IPv6: добавление хост-адреса, если отсутствует..."
if ! ip -6 addr show dev "$IFACE" | grep -q "${V6_HOST%/*}"; then
  sudo ip -6 addr add "$V6_HOST" dev "$IFACE" || true
else
  echo "ℹ️  Адрес ${V6_HOST} уже присвоен интерфейсу $IFACE"
fi

echo "🌐 Включение форвардинга IPv6 (с сохранением RA)..."
sudo mkdir -p /etc/sysctl.d
sudo tee /etc/sysctl.d/99-ipv6-forward.conf >/dev/null <<EOF
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
# принимать Router Advertisements даже при включённом forwarding
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
EOF
sudo sysctl --system

# ============================================================
# DNS: Настройка через systemd-resolved
# ============================================================

echo "🌐 Настройка DNS серверов через systemd-resolved..."

sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns.conf >/dev/null <<EOF
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=8.8.4.4 1.0.0.1
EOF

sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

echo "✅ DNS сервера настроены."

# ============================================================
# DOCKER: Установка
# ============================================================

echo "🐳 Добавляем репозиторий Docker..."

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

echo "✅ Репозиторий Docker добавлен."

echo "🐳 Установка Docker..."
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "✅ Docker установлен."

echo "👥 Добавляем пользователя в группу Docker..."
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker "$USER" || true
# НЕ используем newgrp здесь — он открывает новый shell и блокирует скрипт

echo "✅ Пользователь добавлен в группу Docker."

# ============================================================
# DOCKER: Конфигурация daemon.json
# ============================================================

echo "🐳 Настройка Docker daemon.json..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<JSON
{
  "max-concurrent-downloads": 8,
  "live-restore": true,
  "registry-mirrors": [
    "https://mirror.gcr.io"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "ipv6": true,
  "fixed-cidr-v6": "${V6_DOCKER_SUBNET}",
  "dns": ["1.1.1.1", "8.8.8.8"],
  "dns-search": []
}
JSON

sudo systemctl restart docker

echo "✅ Docker daemon.json настроен."

# ============================================================
# DOCKER: Автоочистка (cron)
# ============================================================

echo "🧹 Настройка автоочистки Docker..."

sudo tee /etc/cron.d/docker-prune >/dev/null <<'EOF'
# Еженедельная очистка Docker (воскресенье, 03:00)
# Удаляет: остановленные контейнеры, неиспользуемые образы, сети, build cache
# Только объекты старше 7 дней (168 часов)
0 3 * * 0 root docker system prune -af --filter "until=168h" >/dev/null 2>&1
EOF

echo "✅ Автоочистка Docker настроена (каждое воскресенье в 03:00)."

# ============================================================
# DOCKER: Создание сети infra
# ============================================================

echo "🐳 Создание внешней сети 'infra' с IPv6 (${V6_DOCKER_SUBNET})..."
if docker network inspect infra >/dev/null 2>&1; then
  if docker network inspect infra | jq -e '.[0].EnableIPv6' | grep -q true; then
    echo "ℹ️  Сеть 'infra' с IPv6 уже существует"
  else
    echo "⚠️  Сеть 'infra' существует без IPv6. Удалите и пересоздайте:"
    echo "    docker network rm infra && docker network create --ipv6 --subnet ${V6_DOCKER_SUBNET} infra"
  fi
else
  docker network create --ipv6 --subnet "${V6_DOCKER_SUBNET}" infra
fi

# ============================================================
# ГОТОВО
# ============================================================

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ Готово! Перезайдите в систему (logout/login),"
echo "   чтобы использовать docker без sudo."
echo "════════════════════════════════════════════════════════"