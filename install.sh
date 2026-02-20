#!/bin/bash

set -e

# ============================================
# НАСТРОЙКИ (измените при необходимости)
# ============================================
INSTALL_DIR="/root/3xui-backup"           # Директория для скрипта
BACKUP_DIR="/backups/3xui"                # Директория для хранения бэкапов
KEEP_DAYS=30                              # Количество дней хранения бэкапов
BACKUP_TIME="3"                           # Час запуска бэкапа (0-23)
X_UI_DATA_DIR="/etc/x-ui"                 # Директория данных 3x-ui

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}  Установка резервного копирования 3x-ui${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo "Настройки:"
echo "  • Директория для бэкапов: $BACKUP_DIR"
echo "  • Хранение: последние $KEEP_DAYS копий"
echo "  • Время запуска: $BACKUP_TIME:00"
echo ""

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен с правами root${NC}"
    exit 1
fi

echo -e "${GREEN}[1/5]${NC} Создание директорий..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BACKUP_DIR"
echo "  ✓ $INSTALL_DIR"
echo "  ✓ $BACKUP_DIR"

echo ""
echo -e "${GREEN}[2/5]${NC} Создание скрипта резервного копирования..."

# Создаем скрипт бэкапа
cat > "$INSTALL_DIR/backup_3xui.sh" <<BACKUP_SCRIPT_EOF
#!/bin/bash
#
# Скрипт резервного копирования 3x-ui
# Автоматическая ротация - хранение последних $KEEP_DAYS копий
#

# Настройки
BACKUP_DIR="$BACKUP_DIR"
KEEP_DAYS=$KEEP_DAYS
X_UI_DATA_DIR="$X_UI_DATA_DIR"
X_UI_DB="\${X_UI_DATA_DIR}/x-ui.db"
HOSTNAME=\$(hostname)
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="3xui_backup_\${HOSTNAME}_\${DATE}"
LOG_FILE="/var/log/3xui-backup.log"

# Функции
log() {
    echo "[\$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

error_exit() {
    log "ОШИБКА: \$1"
    exit 1
}

# Проверка прав root
if [ "\$EUID" -ne 0 ]; then
    error_exit "Скрипт должен быть запущен с правами root"
fi

# Создание директории для бэкапов
if [ ! -d "\$BACKUP_DIR" ]; then
    mkdir -p "\$BACKUP_DIR" || error_exit "Не удалось создать директорию \$BACKUP_DIR"
fi

# Проверка наличия 3x-ui
if [ ! -d "\$X_UI_DATA_DIR" ]; then
    error_exit "Директория 3x-ui не найдена: \$X_UI_DATA_DIR"
fi

if [ ! -f "\$X_UI_DB" ]; then
    log "ВНИМАНИЕ: База данных не найдена: \$X_UI_DB"
fi

log "=========================================="
log "Начало резервного копирования 3x-ui"
log "=========================================="

# Создание временной директории
temp_dir="\${BACKUP_DIR}/\${BACKUP_NAME}"
archive="\${BACKUP_DIR}/\${BACKUP_NAME}.tar.gz"

mkdir -p "\$temp_dir" || error_exit "Не удалось создать временную директорию"

# Копирование базы данных
if [ -f "\$X_UI_DB" ]; then
    log "Копирование базы данных..."
    cp "\$X_UI_DB" "\$temp_dir/" || error_exit "Не удалось скопировать базу данных"
fi

# Копирование сертификатов
if [ -d "\$X_UI_DATA_DIR/cert" ]; then
    log "Копирование сертификатов..."
    cp -r "\$X_UI_DATA_DIR/cert" "\$temp_dir/" 2>/dev/null
fi

# Копирование конфигурационных файлов
for file in config.json x-ui.service; do
    if [ -f "\$X_UI_DATA_DIR/\$file" ]; then
        cp "\$X_UI_DATA_DIR/\$file" "\$temp_dir/" 2>/dev/null
    fi
done

# Сохранение информации о бэкапе
cat > "\$temp_dir/backup_info.txt" <<EOFINFO
Backup Date: \$(date)
Hostname: \$HOSTNAME
3x-ui Data Dir: \$X_UI_DATA_DIR
EOFINFO

# Создание архива
log "Создание архива..."
tar -czf "\$archive" -C "\$BACKUP_DIR" "\$BACKUP_NAME" || error_exit "Не удалось создать архив"

# Удаление временной директории
rm -rf "\$temp_dir"

# Размер архива
size=\$(du -h "\$archive" | cut -f1)
log "Бэкап создан: \$archive (размер: \$size)"

# Ротация бэкапов
log "Ротация бэкапов (хранение последних \$KEEP_DAYS копий)..."
backup_count=\$(find "\$BACKUP_DIR" -name "3xui_backup_*.tar.gz" | wc -l)

if [ "\$backup_count" -gt "\$KEEP_DAYS" ]; then
    log "Найдено \$backup_count бэкапов, удаляем старые..."
    find "\$BACKUP_DIR" -name "3xui_backup_*.tar.gz" -type f -mtime +\$KEEP_DAYS -delete
    deleted=\$((backup_count - KEEP_DAYS))
    log "Удалено старых бэкапов: \$deleted"
else
    log "Всего бэкапов: \$backup_count"
fi

log "=========================================="
log "Резервное копирование завершено успешно"
log "=========================================="
BACKUP_SCRIPT_EOF

chmod +x "$INSTALL_DIR/backup_3xui.sh"
echo "  ✓ $INSTALL_DIR/backup_3xui.sh"

echo ""
echo -e "${GREEN}[3/5]${NC} Настройка crontab..."

# Проверяем, не добавлена ли уже задача
if crontab -l 2>/dev/null | grep -q "backup_3xui.sh"; then
    echo -e "${YELLOW}  ! Задача уже существует в crontab${NC}"
    read -p "  Заменить существующую задачу? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        crontab -l 2>/dev/null | grep -v "backup_3xui.sh" | crontab -
        echo "  ✓ Старая задача удалена"
    else
        echo "  - Пропуск настройки crontab"
        SKIP_CRON=1
    fi
fi

if [ -z "$SKIP_CRON" ]; then
    # Добавляем задачу в crontab
    (crontab -l 2>/dev/null; echo "0 $BACKUP_TIME * * * $INSTALL_DIR/backup_3xui.sh >> /var/log/3xui-backup.log 2>&1") | crontab -
    echo "  ✓ Задача добавлена в crontab (каждый день в $BACKUP_TIME:00)"
fi

echo ""
echo -e "${GREEN}[4/5]${NC} Тестовый запуск бэкапа..."
read -p "Выполнить тестовый бэкап сейчас? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    "$INSTALL_DIR/backup_3xui.sh"
    echo ""
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Тестовый бэкап выполнен успешно!${NC}"
    else
        echo -e "${RED}  ✗ Ошибка при выполнении бэкапа${NC}"
    fi
else
    echo "  - Тестовый бэкап пропущен"
fi

echo ""
echo -e "${GREEN}[5/5]${NC} Установка завершена!"
echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${GREEN}Резервное копирование 3x-ui установлено!${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""
echo "Установлено:"
echo "  • Скрипт: $INSTALL_DIR/backup_3xui.sh"
echo "  • Бэкапы: $BACKUP_DIR"
echo "  • Хранение: последние $KEEP_DAYS копий"
echo "  • Расписание: каждый день в $BACKUP_TIME:00"
echo "  • Логи: /var/log/3xui-backup.log"
echo ""
echo "Полезные команды:"
echo "  • Ручной бэкап: $INSTALL_DIR/backup_3xui.sh"
echo "  • Список бэкапов: ls -lh $BACKUP_DIR/"
echo "  • Просмотр логов: tail -f /var/log/3xui-backup.log"
echo "  • Проверка crontab: crontab -l"
echo ""
