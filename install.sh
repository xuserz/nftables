#!/bin/bash

# ============================================================
# Скрипт установки nftables с GitHub
# ============================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    print_error "Запусти с sudo: sudo $0"
    exit 1
fi

# GitHub репозиторий
GIT_REPO="https://raw.githubusercontent.com/xuserz/nftables/main"

echo "============================================================"
echo "    Установка nftables с блокировкой Сервисов"
echo "============================================================"
echo ""

# Запрос TCP портов
print_info "Какие TCP порты разрешить? (через пробел, например: 80 443 8080)"
print_warning "SSH (22) уже добавлен автоматически"
echo ""
read -p "TCP порты: " TCP_PORTS_INPUT

# Проверка что ввели
if [ -z "$TCP_PORTS_INPUT" ]; then
    print_error "Ты не ввёл ни одного TCP порта"
    exit 1
fi

echo ""

# Запрос UDP портов
print_info "Какие UDP порты разрешить? (через пробел, например: 53 51820 42603)"
echo ""
read -p "UDP порты: " UDP_PORTS_INPUT

echo ""

# Преобразуем строку в массив
TCP_PORTS=($TCP_PORTS_INPUT)
UDP_PORTS=($UDP_PORTS_INPUT)

# Установка nftables
print_info "Устанавливаем nftables..."
apt update -qq
apt install -y nftables curl

# Создание структуры
print_info "Создаём структуру каталогов..."
mkdir -p /etc/nftables/{blocklists,rules}

# Скачивание файлов с GitHub
print_info "Скачиваем конфиги с GitHub..."

curl -s -o /etc/nftables/main.conf "$GIT_REPO/main.conf"
curl -s -o /etc/nftables/blocklists/ipv4.nft "$GIT_REPO/blocklists/ipv4.nft"
curl -s -o /etc/nftables/blocklists/ipv6.nft "$GIT_REPO/blocklists/ipv6.nft"
curl -s -o /etc/nftables/rules/input.nft "$GIT_REPO/rules/input.nft"
curl -s -o /etc/nftables/rules/output.nft "$GIT_REPO/rules/output.nft"

# Создаём variables.conf
print_info "Создаём variables.conf с твоими портами..."

cat > /etc/nftables/variables.conf << EOF
# ============================================================
# ПЕРЕМЕННЫЕ
# ============================================================

# Разрешённые TCP порты для входящих подключений (SSH не нужен, он уже отдельно)
define ALLOWED_TCP_PORTS = {
$(for port in "${TCP_PORTS[@]}"; do
    echo "    $port,"
done)
}

# Разрешённые UDP порты для входящих подключений
define ALLOWED_UDP_PORTS = {
$(for port in "${UDP_PORTS[@]}"; do
    echo "    $port,"
done)
}
EOF

# Проверка конфига
print_info "Проверяем синтаксис..."
if nft -c -f /etc/nftables/main.conf; then
    print_success "Синтаксис корректен"
else
    print_error "Ошибка в синтаксисе"
    exit 1
fi

# Применение
print_info "Применяем правила..."
nft -f /etc/nftables/main.conf

# Включаем автозагрузку
systemctl enable nftables
systemctl restart nftables

# Итог
echo ""
echo "============================================================"
print_success "УСТАНОВКА ЗАВЕРШЕНА!"
echo "============================================================"
echo ""
echo -e "${BLUE}Разрешённые TCP порты:${NC}"
for port in "${TCP_PORTS[@]}"; do
    echo "  ✅ tcp/$port"
done
echo ""
echo -e "${BLUE}Разрешённые UDP порты:${NC}"
for port in "${UDP_PORTS[@]}"; do
    echo "  ✅ udp/$port"
done
echo ""
echo -e "${GREEN}🔒 SSH (порт 22) всегда открыт${NC}"
echo ""
echo "============================================================"
echo -e "${BLUE}Полезные команды:${NC}"
echo "  sudo nft list ruleset                      # просмотр правил"
echo "  sudo nft -f /etc/nftables/main.conf        # применить изменения"
echo "  sudo systemctl status nftables             # статус сервиса"
echo "============================================================"
echo ""

# Предложение перезагрузить
read -p "Перезагрузить сервер? (y/n): " REBOOT_ANSWER
if [[ "$REBOOT_ANSWER" =~ ^[Yy]$ ]]; then
    print_info "Перезагрузка..."
    reboot
else
    print_info "Перезагрузка отменена"
fi