# Добавление переменных прокси в .bashrc
cat >> ~/.bashrc << 'EOF'

# Настройки прокси для Docker и системы
export HTTP_PROXY=http://msk-kwts01.corp.suek.ru:3128
export HTTPS_PROXY=http://msk-kwts01.corp.suek.ru:3128
export http_proxy=$HTTP_PROXY
export https_proxy=$HTTPS_PROXY
EOF
