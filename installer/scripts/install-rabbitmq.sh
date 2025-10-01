#!/bin/bash
# =============================================================================
# Скрипт установки RabbitMQ
# =============================================================================
# Назначение: Установка и настройка RabbitMQ в Docker контейнере с management plugin
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию (загружаются из monq.conf)
# Переменные уже загружены из common.sh
DRY_RUN=false
FORCE=false

# Функции цветного вывода загружаются из common.sh

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --version VERSION         Версия RabbitMQ (по умолчанию: из config/monq.conf)
    --admin-password PASS     Пароль администратора (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --logs-dir PATH           Директория логов (по умолчанию: из config/monq.conf)
    --amqp-port PORT          AMQP порт (по умолчанию: из config/monq.conf)
    --management-port PORT    Management порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --default-user USER       Пользователь по умолчанию (по умолчанию: из config/monq.conf)
    --default-vhost VHOST     Виртуальный хост по умолчанию (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 4.15.0 --admin-password mypassword
    $0 --base-dir /opt/rabbitmq --dry-run
    $0 --amqp-port 5673 --management-port 15673

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                RABBITMQ_VERSION="$2"
                shift 2
                ;;
            --admin-password)
                RABBITMQ_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --base-dir)
                RABBITMQ_BASE_DIR="$2"
                RABBITMQ_DATA_DIR="$2/data"
                RABBITMQ_LOGS_DIR="$2/logs"
                shift 2
                ;;
            --data-dir)
                RABBITMQ_DATA_DIR="$2"
                shift 2
                ;;
            --logs-dir)
                RABBITMQ_LOGS_DIR="$2"
                shift 2
                ;;
            --amqp-port)
                RABBITMQ_AMQP_PORT="$2"
                shift 2
                ;;
            --management-port)
                RABBITMQ_MANAGEMENT_PORT="$2"
                shift 2
                ;;
            --container-name)
                RABBITMQ_CONTAINER_NAME="$2"
                shift 2
                ;;
            --default-user)
                RABBITMQ_DEFAULT_USER="$2"
                shift 2
                ;;
            --default-vhost)
                RABBITMQ_DEFAULT_VHOST="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Валидация параметров
validate_parameters() {
    log_info "Валидация параметров..."
    
    # Проверка обязательных параметров
    if [[ -z "$RABBITMQ_VERSION" ]]; then
        log_error "Версия RabbitMQ не указана"
        exit 1
    fi
    
    if [[ -z "$RABBITMQ_ADMIN_PASSWORD" ]]; then
        log_error "Пароль администратора не указан"
        exit 1
    fi
    
    if [[ -z "$RABBITMQ_BASE_DIR" ]]; then
        log_error "Базовая директория не указана"
        exit 1
    fi
    
    # Проверка портов
    if ! [[ "$RABBITMQ_AMQP_PORT" =~ ^[0-9]+$ ]] || [[ "$RABBITMQ_AMQP_PORT" -lt 1 ]] || [[ "$RABBITMQ_AMQP_PORT" -gt 65535 ]]; then
        log_error "Некорректный AMQP порт: $RABBITMQ_AMQP_PORT"
        exit 1
    fi
    
    if ! [[ "$RABBITMQ_MANAGEMENT_PORT" =~ ^[0-9]+$ ]] || [[ "$RABBITMQ_MANAGEMENT_PORT" -lt 1 ]] || [[ "$RABBITMQ_MANAGEMENT_PORT" -gt 65535 ]]; then
        log_error "Некорректный management порт: $RABBITMQ_MANAGEMENT_PORT"
        exit 1
    fi
    
    print_success "Валидация параметров завершена успешно"
}

# Создание директорий
create_directories() {
    log_info "Создание директорий для RabbitMQ..."
    
    local dirs=(
        "$RABBITMQ_BASE_DIR"
        "$RABBITMQ_DATA_DIR"
        "$RABBITMQ_LOGS_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Создание директории $dir"
        else
            if ! run_sudo mkdir -p "$dir"; then
                log_error "Не удалось создать директорию: $dir"
                return 1
            fi
            
            # Установка прав доступа
            if ! run_sudo chown -R 999:999 "$dir"; then
                log_warn "Не удалось установить права доступа для директории: $dir"
            fi
            
            print_success "Директория создана: $dir"
        fi
    done
    
    print_success "Все директории созданы успешно"
}


# Создание .env файла
create_env_file() {
    log_info "Создание .env файла для RabbitMQ..."
    
    local env_file="$RABBITMQ_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/rabbitmq.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# RabbitMQ Configuration
TIMEZONE=${TIMEZONE}
RABBITMQ_VERSION=${RABBITMQ_VERSION}
RABBITMQ_ADMIN_PASSWORD=${RABBITMQ_ADMIN_PASSWORD}
RABBITMQ_BASE_DIR=${RABBITMQ_BASE_DIR}
RABBITMQ_DATA_DIR=${RABBITMQ_DATA_DIR}
RABBITMQ_LOGS_DIR=${RABBITMQ_LOGS_DIR}
RABBITMQ_AMQP_PORT=${RABBITMQ_AMQP_PORT}
RABBITMQ_MANAGEMENT_PORT=${RABBITMQ_MANAGEMENT_PORT}
RABBITMQ_CONTAINER_NAME=${RABBITMQ_CONTAINER_NAME}
RABBITMQ_NETWORK=${RABBITMQ_NETWORK}
RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
RABBITMQ_DEFAULT_VHOST=${RABBITMQ_DEFAULT_VHOST}
EOF
    
    # Копируем файл с sudo правами
    if run_sudo cp "$temp_env" "$env_file"; then
        run_sudo chown root:root "$env_file"
        run_sudo chmod 644 "$env_file"
        rm -f "$temp_env"
        print_success ".env файл создан"
        return 0
    else
        rm -f "$temp_env"
        print_error "Ошибка при создании .env файла"
        return 1
    fi
}

# Копирование docker-compose файла (используется универсальная функция из common.sh)
copy_docker_compose() {
    copy_docker_compose_file "RabbitMQ" "rabbitmq" "$RABBITMQ_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "RabbitMQ" "$RABBITMQ_BASE_DIR"
}

# Настройка файрвола
configure_firewall() {
    log_info "Настройка файрвола для RabbitMQ..."
    
    if [[ "$CONFIGURE_FIREWALL" != "true" ]]; then
        log_info "Настройка файрвола отключена"
        return 0
    fi
    
    local ports=("$RABBITMQ_AMQP_PORT" "$RABBITMQ_MANAGEMENT_PORT")
    
    for port in "${ports[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Открытие порта $port в файрволе"
        else
            if command -v firewall-cmd >/dev/null 2>&1; then
                if ! run_sudo firewall-cmd --permanent --add-port="$port/tcp"; then
                    log_warn "Не удалось открыть порт $port в файрволе"
                else
                    print_success "Порт $port открыт в файрволе"
                fi
            elif command -v ufw >/dev/null 2>&1; then
                if ! run_sudo ufw allow "$port/tcp"; then
                    log_warn "Не удалось открыть порт $port в файрволе"
                else
                    print_success "Порт $port открыт в файрволе"
                fi
            else
                log_warn "Файрвол не найден, пропускаем настройку портов"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" != "true" ]] && command -v firewall-cmd >/dev/null 2>&1; then
        if ! run_sudo firewall-cmd --reload; then
            log_warn "Не удалось перезагрузить правила файрвола"
        fi
    fi
    
    print_success "Настройка файрвола завершена"
}

# Запуск RabbitMQ
start_rabbitmq() {
    print_section "Запуск RabbitMQ сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск RabbitMQ сервисов"
        print_info "[DRY-RUN] Образ: rabbitmq:${RABBITMQ_VERSION}-management"
        print_info "[DRY-RUN] AMQP порт: $RABBITMQ_AMQP_PORT:5672"
        print_info "[DRY-RUN] Management порт: $RABBITMQ_MANAGEMENT_PORT:15672"
        print_info "[DRY-RUN] Данные: $RABBITMQ_DATA_DIR:/var/lib/rabbitmq"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$RABBITMQ_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $RABBITMQ_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "RabbitMQ сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске RabbitMQ сервисов"
        return 1
    fi
}

# Ожидание готовности RabbitMQ
wait_for_rabbitmq() {
    print_section "Ожидание готовности RabbitMQ"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности RabbitMQ"
        return 0
    fi
    
    local retry_count=0
    local max_retries=30
    local wait_time=10
    
    # Переход в директорию с docker-compose.yml
    cd "$RABBITMQ_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $RABBITMQ_BASE_DIR"
        return 1
    }
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Проверяем доступность web-интерфейса RabbitMQ через curl
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${RABBITMQ_MANAGEMENT_PORT:-15672}" | grep -q "200"; then
            print_success "RabbitMQ web-интерфейс доступен, сервис готов к работе"
            return 0
        fi

        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности RabbitMQ web-интерфейса... ($retry_count/$max_retries)"
        sleep $wait_time
    done
    
    print_error "RabbitMQ не готов к работе после $max_retries попыток"
    return 1
}

# Настройка RabbitMQ
setup_rabbitmq() {
    print_section "Настройка RabbitMQ"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка RabbitMQ"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$RABBITMQ_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $RABBITMQ_BASE_DIR"
        return 1
    }
    
    # Включение management plugin (уже включен в образе с management)
    log_info "Проверка включения management plugin..."
    if ! run_docker_compose exec -T rabbitmq rabbitmq-plugins list | grep -q "rabbitmq_management.*E"; then
        log_info "Включение management plugin..."
        if ! run_docker_compose exec -T rabbitmq rabbitmq-plugins enable rabbitmq_management; then
            log_warn "Не удалось включить management plugin"
        else
            print_success "Management plugin включен"
        fi
    else
        print_success "Management plugin уже включен"
    fi
    
    # Пользователи и виртуальные хосты настраиваются через переменные окружения
    # RABBITMQ_DEFAULT_USER, RABBITMQ_DEFAULT_PASS, RABBITMQ_DEFAULT_VHOST
    log_info "Пользователи и виртуальные хосты настраиваются через переменные окружения"
    
    print_success "Настройка RabbitMQ завершена"
}

# Проверка установки
verify_installation() {
    print_section "Проверка установки RabbitMQ"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки RabbitMQ"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$RABBITMQ_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $RABBITMQ_BASE_DIR"
        return 1
    }
    
    # Проверка статуса контейнера
    if ! run_docker_compose ps -q | grep -q .; then
        print_error "Контейнер RabbitMQ не запущен"
        return 1
    fi
    
    # Проверка доступности AMQP порта
    if ! nc -z localhost "$RABBITMQ_AMQP_PORT" 2>/dev/null; then
        print_error "AMQP порт $RABBITMQ_AMQP_PORT недоступен"
        return 1
    fi
    
    # Проверка доступности management порта
    if ! nc -z localhost "$RABBITMQ_MANAGEMENT_PORT" 2>/dev/null; then
        print_error "Management порт $RABBITMQ_MANAGEMENT_PORT недоступен"
        return 1
    fi
    
    # Проверка health check
    if ! run_docker_compose exec -T rabbitmq rabbitmq-diagnostics ping >/dev/null 2>&1; then
        print_error "Health check RabbitMQ не прошел"
        return 1
    fi
    
    print_success "Установка RabbitMQ проверена успешно"
}

# Отображение информации о подключении
show_connection_info() {
    log_info "Информация о подключении к RabbitMQ:"
    echo
    print_section "Подключение к RabbitMQ"
    echo "AMQP URL: amqp://$RABBITMQ_DEFAULT_USER:$RABBITMQ_ADMIN_PASSWORD@localhost:$RABBITMQ_AMQP_PORT/$RABBITMQ_DEFAULT_VHOST"
    echo "Management UI: http://localhost:$RABBITMQ_MANAGEMENT_PORT"
    echo "Пользователь: $RABBITMQ_DEFAULT_USER"
    echo "Пароль: $RABBITMQ_ADMIN_PASSWORD"
    echo "Виртуальный хост: $RABBITMQ_DEFAULT_VHOST"
    echo
    print_section "Docker команды"
    echo "Просмотр логов: docker logs $RABBITMQ_CONTAINER_NAME"
    echo "Подключение к контейнеру: docker exec -it $RABBITMQ_CONTAINER_NAME bash"
    echo "Остановка: docker stop $RABBITMQ_CONTAINER_NAME"
    echo "Запуск: docker start $RABBITMQ_CONTAINER_NAME"
    echo
    print_section "Конфигурация"
    echo "Конфигурация: только через docker-compose.yml и .env файлы"
    echo "Пользователи и виртуальные хосты: через переменные окружения"
    echo
}

# =============================================================================
# Главная функция
# =============================================================================

main() {
    print_header "Установка RabbitMQ для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-rabbitmq-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки RabbitMQ"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $RABBITMQ_VERSION"
    log_info "AMQP порт: $RABBITMQ_AMQP_PORT"
    log_info "Management порт: $RABBITMQ_MANAGEMENT_PORT"
    log_info "Базовая директория: $RABBITMQ_BASE_DIR"
    log_info "Директория данных: $RABBITMQ_DATA_DIR"
    log_info "Директория логов: $RABBITMQ_LOGS_DIR"
    log_info "Пользователь: $RABBITMQ_DEFAULT_USER"
    log_info "Виртуальный хост: $RABBITMQ_DEFAULT_VHOST"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_docker"
        "create_directories"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "configure_firewall"
        "start_rabbitmq"
        "wait_for_rabbitmq"
        "setup_rabbitmq"
        "verify_installation"
    )
    
    local total_steps=${#steps[@]}
    local current_step=0
    
    for step in "${steps[@]}"; do
        current_step=$((current_step + 1))
        show_progress $current_step $total_steps "Выполнение: $step"
        
        if ! $step; then
            log_error "Ошибка на этапе: $step"
            if [[ "$FORCE" != "true" ]]; then
                log_error "Прерывание выполнения"
                exit 1
            else
                log_warn "Продолжение выполнения в принудительном режиме"
            fi
        fi
    done
    
    log_info "Установка RabbitMQ завершена успешно"
    
    # Отображение информации о подключении
    show_connection_info
    
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
