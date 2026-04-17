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
GIT_REPO="https://github.com/xuserz/nftables.git"

# Временная папка
TEMP_DIR="/tmp/nftables-install"

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

# Установка пакетов
print_info "Устанавливаем пакеты..."
apt update -qq
apt install -y nftables curl git

# ============================================================
# БЭКАП СТАРОГО КОНФИГА
# ============================================================

if [ -f /etc/nftables.conf ] || [ -L /etc/nftables.conf ]; then
    BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="/etc/nftables.conf.bak_${BACKUP_DATE}"
    
    print_info "Создаём бэкап: $BACKUP_FILE"
    cp -a /etc/nftables.conf "$BACKUP_FILE"
    print_success "Бэкап создан: $BACKUP_FILE"
else
    print_info "Файл /etc/nftables.conf не существует, бэкап не требуется"
fi

# ============================================================
# УСТАНОВКА НОВОГО КОНФИГА
# ============================================================

# Клонируем репозиторий
print_info "Клонируем репозиторий с GitHub..."
rm -rf "$TEMP_DIR"
git clone --depth 1 "$GIT_REPO" "$TEMP_DIR"

# Удаляем старую папку /etc/nftables и копируем новую
print_info "Удаляем старую конфигурацию..."
rm -rf /etc/nftables

print_info "Копируем новую конфигурацию..."

# Проверяем структуру репозитория
if [ -d "$TEMP_DIR/nftables" ]; then
    cp -r "$TEMP_DIR/nftables" /etc/
else
    cp -r "$TEMP_DIR" /etc/nftables
fi

# Удаляем временную папку
rm -rf "$TEMP_DIR"

# Создаём variables.conf с портами от пользователя
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

print_success "variables.conf создан"

# Проверка конфига
print_info "Проверяем синтаксис..."
if nft -c -f /etc/nftables/main.conf; then
    print_success "Синтаксис корректен"
else
    print_error "Ошибка в синтаксисе"
    exit 1
fi

# ============================================================
# ПРИМЕНЕНИЕ ПРАВИЛ И НАСТРОЙКА АВТОЗАГРУЗКИ
# ============================================================

print_info "Применяем правила..."

# Создаём симлинк из основного файла, который ожидает systemd
ln -sf /etc/nftables/main.conf /etc/nftables.conf
print_success "Создан симлинк /etc/nftables.conf -> /etc/nftables/main.conf"

# Применяем правила через основной системный файл
nft -f /etc/nftables.conf

# Включаем автозагрузку и перезапускаем сервис
systemctl enable nftables
systemctl restart nftables

print_success "nftables добавлен в автозагрузку"

# ============================================================
# ВЫВОД ИТОГОВ
# ============================================================

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
echo -e "${YELLOW}📁 Основной конфиг:${NC} /etc/nftables/main.conf"
echo -e "${YELLOW}🔗 Симлинк:${NC} /etc/nftables.conf -> /etc/nftables/main.conf"
if [ -f "$BACKUP_FILE" ]; then
    echo -e "${YELLOW}💾 Бэкап:${NC} $BACKUP_FILE"
fi
echo ""
echo "============================================================"
echo -e "${BLUE}Полезные команды:${NC}"
echo "  sudo nft list ruleset                      # просмотр правил"
echo "  sudo nft -f /etc/nftables.conf             # применить изменения"
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