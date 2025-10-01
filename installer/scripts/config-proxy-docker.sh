# Создание директории для конфигурации Docker
sudo mkdir -p /etc/systemd/system/docker.service.d

# Создание файла конфигурации прокси
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null << 'EOF'
[Service]
Environment="HTTP_PROXY=http://msk-kwts01.corp.suek.ru:3128"
Environment="HTTPS_PROXY=http://msk-kwts01.corp.suek.ru:3128"
Environment="NO_PROXY=localhost,127.0.0.0/8"
EOF

# Перезагрузка конфигурации systemd
sudo systemctl daemon-reload

# Перезапуск Docker сервиса
sudo systemctl restart docker

# Проверка статуса Docker
sudo systemctl status docker --no-pager

# Проверка переменных окружения Docker
sudo systemctl show docker --property=Environment
