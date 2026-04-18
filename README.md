# ECMP Hash Lab

Тестовый стенд для проверки работы ECMP (Equal-Cost Multi-Path) маршрутизации с хэшированием по source IP. Разворачивается в Docker на любой Linux-машине.

## Топология

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   ┌───────────┐                                     │
│   │ generator │  10.0.1.10                          │
│   │           │  + aliases 10.0.1.3–15              │
│   └─────┬─────┘                                     │
│         │ net_gen (10.0.1.0/24)                     │
│   ┌─────┴─────┐                                     │
│   │  router   │  ECMP: fib_multipath_hash_policy=0  │
│   │           │  hash по src IP → nexthop           │
│   └──┬─────┬──┘                                     │
│      │     │                                        │
│  path1     path2                                    │
│  10.0.2.x  10.0.3.x                                │
│      │     │                                        │
│   ┌──┴─────┴──┐                                     │
│   │ receiver  │  VIP: 10.99.0.1 (lo)               │
│   │           │  tcpdump на обоих интерфейсах       │
│   └───────────┘                                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

| Контейнер | Образ | IP адреса | Роль |
|---|---|---|---|
| generator | nicolaka/netshoot | 10.0.1.10, алиасы .3–.15 | Генератор трафика с разных src IP |
| router | nicolaka/netshoot | 10.0.1.11 / 10.0.2.11 / 10.0.3.11 | ECMP маршрутизатор |
| receiver | nicolaka/netshoot | 10.0.2.20 / 10.0.3.20, VIP 10.99.0.1 | Приёмник, анализ дампа |

---

## Требования

- Linux (Ubuntu 20.04 / 22.04 / 24.04)
- Docker Engine + Docker Compose v2
- ~300 MB места (образ nicolaka/netshoot)

---

## Установка Docker

```bash
# Добавить официальный GPG ключ Docker
sudo apt update
sudo apt install ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Добавить репозиторий
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Проверить установку
docker --version
docker compose version
```

Чтобы запускать Docker без `sudo`:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## Запуск стенда

```bash
# 1. Клонировать репозиторий
git clone https://github.com/EgorkaSav/Lab_ECMP.git
cd ecmp-lab

# 2. Поднять контейнеры
sudo docker compose up -d

# 3. Проверить что все три запущены
sudo docker compose ps
```

Ожидаемый вывод:
```
NAME        IMAGE               STATUS
generator   nicolaka/netshoot   Up
router      nicolaka/netshoot   Up
receiver    nicolaka/netshoot   Up
```

---

## Проверка ECMP без трафика

Команда `ip route get` показывает какой nexthop выберет ядро для каждого src IP — без отправки реального трафика:

```bash
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.3 iif eth2
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.4 iif eth2
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.5 iif eth2
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.6 iif eth2
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.7 iif eth2
sudo docker exec router ip route get 10.99.0.1 from 10.0.1.8 iif eth2
```

Пример вывода — разные src IP попадают в разные nexthop:
```
10.99.0.1 from 10.0.1.3 via 10.0.2.20 dev eth0   ← path1
10.99.0.1 from 10.0.1.4 via 10.0.2.20 dev eth0   ← path1
10.99.0.1 from 10.0.1.5 via 10.0.3.20 dev eth1   ← path2
10.99.0.1 from 10.0.1.6 via 10.0.3.20 dev eth1   ← path2
```

---

## Тест с реальным трафиком

**Шаг 1 — запустить tcpdump на ресивере** (уже запущен в setup.sh, но если нужно перезапустить):

```bash
sudo docker exec receiver bash -c "
    pkill tcpdump 2>/dev/null; sleep 1
    rm -f /tmp/path1.pcap /tmp/path2.pcap
    tcpdump -i eth1 -n -w /tmp/path1.pcap &
    tcpdump -i eth0 -n -w /tmp/path2.pcap &
"
```

**Шаг 2 — отправить трафик с разных src IP:**

```bash
sudo docker exec generator bash -c "
for i in 3 4 5 6 7 8 9 10 12 13 14 15; do
    ping -I 10.0.1.\$i -c 3 -W 1 10.99.0.1 > /dev/null 2>&1 &
done
wait
echo 'Traffic done'
"
```

**Шаг 3 — остановить дамп и проанализировать:**

```bash
sudo docker exec receiver pkill tcpdump

echo "=== PATH1 (eth1) ===" && \
sudo docker exec receiver tshark -r /tmp/path1.pcap \
    -T fields -e ip.src 2>/dev/null | sort | uniq -c | sort -rn

echo "=== PATH2 (eth0) ===" && \
sudo docker exec receiver tshark -r /tmp/path2.pcap \
    -T fields -e ip.src 2>/dev/null | sort | uniq -c | sort -rn
```

**Ожидаемый результат:**

```
=== PATH1 (eth1) ===
  3  10.0.1.5
  3  10.0.1.6
  3  10.0.1.7
  ...

=== PATH2 (eth0) ===
  3  10.0.1.3
  3  10.0.1.4
  3  10.0.1.10
  ...
```

Каждый src IP присутствует **только в одном** из файлов — это доказывает корректную работу ECMP hash. Один поток = один путь, пакеты не перемешиваются.

---

## Полезные команды

```bash
# Зайти внутрь контейнера
sudo docker exec -it router bash
sudo docker exec -it receiver bash
sudo docker exec -it generator bash

# Таблица маршрутов роутера
sudo docker exec router ip route show

# Текущий hash policy (0 = L3, 1 = L4)
sudo docker exec router sysctl net.ipv4.fib_multipath_hash_policy

# Переключить на L4 hash (src/dst port) и сравнить распределение
sudo docker exec router sysctl -w net.ipv4.fib_multipath_hash_policy=1

# Логи контейнера (вывод setup.sh при старте)
sudo docker compose logs router

# Снести стенд
sudo docker compose down
```

---

## Как работает ECMP hash

Параметр `net.ipv4.fib_multipath_hash_policy` определяет что входит в хэш-функцию:

| Значение | Поля для хэша | Применение |
|---|---|---|
| `0` (L3) | src IP + dst IP + протокол | Один src IP → всегда один путь |
| `1` (L4) | + src port + dst port | Более тонкое распределение |

При `policy=0` два пакета с одинаковым src IP **всегда** пойдут одним путём независимо от количества пакетов и времени. Это гарантирует что TCP-сессия не разрывается при ECMP.

---

## Структура репозитория

```
ecmp-lab/
├── docker-compose.yml     # описание сетей и контейнеров
├── generator/
│   └── setup.sh           # генератор ip трафика
├── router/
│   └── setup.sh           # виртуальный маршрутизатор
├── receiver/
│   └── setup.sh           # клиент на котором захватываем трафик, два интерфейса
└── README.md
```
