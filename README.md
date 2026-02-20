# Автоматическое резервное копирование 3x-ui

Скрипт для автоматического создания резервных копий 3x-ui с ротацией на 30 дней.

## Установка

Запустите одну команду на сервере с 3x-ui:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Andrey039/Bootstrap-VM/main/install.sh)
```

Скрипт автоматически:
- Создаст директории `/root/3xui-backup` и `/backups/3xui`
- Установит скрипт резервного копирования
- Настроит crontab для ежедневного бэкапа в 3:00
- Выполнит тестовый бэкап

## Что сохраняется

- ✅ База данных `x-ui.db` (все настройки и пользователи)
- ✅ SSL/TLS сертификаты
- ✅ Конфигурационные файлы

## Расписание

По умолчанию: **каждый день в 3:00 ночи**

## Ротация

Автоматически хранятся **последние 30 копий**, старые удаляются.

## Полезные команды

```bash
# Ручной запуск бэкапа
/root/3xui-backup/backup_3xui.sh

# Список бэкапов
ls -lh /backups/3xui/

# Просмотр логов
tail -f /var/log/3xui-backup.log

# Проверка crontab
crontab -l
```

## Восстановление

```bash
# 1. Остановите 3x-ui
systemctl stop x-ui

# 2. Распакуйте бэкап
cd /tmp
tar -xzf /backups/3xui/3xui_backup_*.tar.gz

# 3. Скопируйте данные
cp -r 3xui_backup_*/x-ui.db /etc/x-ui/
cp -r 3xui_backup_*/cert /etc/x-ui/ 2>/dev/null || true

# 4. Установите права
chown -R root:root /etc/x-ui
chmod 600 /etc/x-ui/x-ui.db

# 5. Запустите 3x-ui
systemctl start x-ui
```

## Требования

- Linux с systemd
- Права root
- Установленный 3x-ui
