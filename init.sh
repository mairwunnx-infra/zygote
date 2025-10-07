#!/usr/bin/env bash
set -euo pipefail

IFACE=${IFACE:-ens3}
V6_PREFIX=${V6_PREFIX:-"2a09:7c47:0:2e::/64"}
V6_HOST=${V6_HOST:-"2a09:7c47:0:2e::1/64"}
V6_DOCKER_SUBNET=${V6_DOCKER_SUBNET:-"2a09:7c47:0:2e:1000::/80"}

echo "🐧 Обновление системы..."
sudo apt update && sudo apt -y upgrade

echo "🐧 Установка базовых пакетов..."
sudo apt -y install curl ca-certificates gnupg lsb-release git jq unzip htop chrony

echo "🐧 Установка часового пояса Europe/Moscow..."
sudo timedatectl set-timezone Europe/Moscow

echo "🐧 Создание swap-файла (4G)..."
if ! swapon --summary | grep -q '/swapfile'; then
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  sudo swapon -a
  echo "✅ Swap-файл создан."
else
  echo "ℹ️  Swap-файл уже существует, пропускаем."
fi

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
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "✅ Docker установлен."

echo "👥 Добавляем пользователя в группу Docker..."
sudo groupadd docker || true
sudo usermod -aG docker $USER || true
newgrp docker || true

echo "✅ Пользователь добавлен в группу Docker."

echo "🐳 Настройка Docker daemon.json (логи + IPv6 fixed-cidr-v6=${V6_DOCKER_SUBNET})..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<JSON
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "ipv6": true,
  "fixed-cidr-v6": "${V6_DOCKER_SUBNET}"
}
JSON
sudo systemctl restart docker

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

echo "✅ Готово. Если это первый запуск, выйдите из системы и войдите снова, чтобы использовать docker без sudo."