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

echo "🛡 Настройка защиты от UDP-флуда через iptables/ip6tables (c логами)..."

export DEBIAN_FRONTEND=noninteractive

echo "📦 Устанавливаю iptables-persistent (для автосохранения правил)..."
sudo apt-get update -y
sudo apt-get install -y iptables-persistent || {
  echo "⚠️  Не удалось установить iptables-persistent. Правила всё равно применю, но автозагрузка может не сохраниться."
}

echo "🔩 Проверяю модуль xt_hashlimit..."
if lsmod | grep -q '^xt_hashlimit'; then
  echo "✅ xt_hashlimit уже загружен."
else
  if sudo modprobe xt_hashlimit 2>/dev/null; then
    echo "✅ Модуль xt_hashlimit успешно загружен."
  else
    echo "⚠️  Модуль xt_hashlimit не загрузился. Попробую всё равно применить правила; если будет ошибка — дам знать."
  fi
fi

add_rule() { # add_rule <iptables|ip6tables> <args...>
  local bin="$1"; shift
  echo "+ $bin $*"
  if sudo $bin -C "$@" 2>/dev/null; then
    echo "  ↳ уже есть (OK)"
  else
    if sudo $bin -A "$@" 2>/dev/null; then
      echo "  ↳ добавлено (OK)"
    else
      echo "  ↳ ❌ ошибка при добавлении (проверьте поддержку модуля/синтаксис)" >&2
      return 1
    fi
  fi
}

echo "🔍 Версия iptables: $(iptables -V || true)"
echo "🔍 Версия ip6tables: $(ip6tables -V || true)"

echo "🔐 Применяю правила IPv4..."

# Разрешаем ответы
add_rule iptables OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Системные UDP-службы
add_rule iptables OUTPUT -p udp --dport 53  -j ACCEPT   # DNS
add_rule iptables OUTPUT -p udp --dport 123 -j ACCEPT   # NTP
add_rule iptables OUTPUT -p udp --dport 67:68 -j ACCEPT # DHCP (клиент)

# Лимит исходящего UDP для остального трафика (per dst ip/port)
add_rule iptables OUTPUT -p udp -m hashlimit \
  --hashlimit-name udp_out_v4 --hashlimit 50/second --hashlimit-burst 100 \
  --hashlimit-mode dstip,dstport --hashlimit-htable-expire 60000 -j ACCEPT

# логирование того, что режем (чтобы видеть всплески)
add_rule iptables OUTPUT -p udp -m limit --limit 5/second -j LOG --log-prefix "[UDP_DROP_v4] "

# Остальной UDP — DROP
add_rule iptables OUTPUT -p udp -j DROP

echo "🔐 Применяю правила IPv6..."

add_rule ip6tables OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
add_rule ip6tables OUTPUT -p udp --dport 53  -j ACCEPT   # DNS
add_rule ip6tables OUTPUT -p udp --dport 123 -j ACCEPT   # NTP
add_rule ip6tables OUTPUT -p udp --dport 67:68 -j ACCEPT # DHCPv6 (если используется)

add_rule ip6tables OUTPUT -p udp -m hashlimit \
  --hashlimit-name udp_out_v6 --hashlimit 50/second --hashlimit-burst 100 \
  --hashlimit-mode dstip,dstport --hashlimit-htable-expire 60000 -j ACCEPT

add_rule ip6tables OUTPUT -p udp -m limit --limit 5/second -j LOG --log-prefix "[UDP_DROP_v6] "
add_rule ip6tables OUTPUT -p udp -j DROP

echo "💾 Сохраняю правила для автозагрузки..."
if sudo sh -c 'iptables-save  > /etc/iptables/rules.v4' && \
   sudo sh -c 'ip6tables-save > /etc/iptables/rules.v6'; then
  echo "✅ Правила сохранены в /etc/iptables/rules.v4 и /etc/iptables/rules.v6"
else
  echo "⚠️  Не удалось сохранить правила. Они активны сейчас, но могут не примениться после перезагрузки."
fi

echo "🧪 Краткая проверка применённых правил (вывод OUTPUT-цепочек):"
echo "--- IPv4 ---"
sudo iptables -S OUTPUT || true
echo "--- IPv6 ---"
sudo ip6tables -S OUTPUT || true

echo "ℹ️  Логи отбрасываемого UDP смотри в: journalctl -k | grep UDP_DROP"
echo "✅ Защита от исходящего UDP-флуда активна."

echo "✅ Готово. Если это первый запуск, выйдите из системы и войдите снова, чтобы использовать docker без sudo."