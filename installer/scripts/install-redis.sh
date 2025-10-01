#!/bin/bash
# =============================================================================
# Скрипт установки Redis
# =============================================================================
# Назначение: Установка и настройка Redis в Docker контейнере
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
    --version VERSION         Версия Redis (по умолчанию: из config/monq.conf)
    --password PASS           Пароль для Redis (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --port PORT               Порт Redis (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 7.2.5 --password mypassword
    $0 --base-dir /opt/redis --dry-run
    $0 --port 6380

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                REDIS_VERSION="$2"
                shift 2
                ;;
            --password)
                REDIS_PASSWORD="$2"
                shift 2
                ;;
            --base-dir)
                REDIS_BASE_DIR="$2"
                REDIS_DATA_DIR="$2/data"
                REDIS_CONFIG_DIR="$2/config"
                shift 2
                ;;
            --data-dir)
                REDIS_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                REDIS_CONFIG_DIR="$2"
                shift 2
                ;;
            --port)
                REDIS_PORT="$2"
                shift 2
                ;;
            --container-name)
                REDIS_CONTAINER_NAME="$2"
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
                print_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Валидация параметров
validate_parameters() {
    print_section "Валидация параметров"
    
    # Проверка обязательных параметров
    if [[ -z "$REDIS_VERSION" ]]; then
        print_error "Версия Redis не указана"
        return 1
    fi
    
    if [[ -z "$REDIS_PASSWORD" ]]; then
        print_error "Пароль Redis не указан"
        return 1
    fi
    
    if [[ -z "$REDIS_PORT" ]]; then
        print_error "Порт Redis не указан"
        return 1
    fi
    
    # Проверка корректности порта
    if ! [[ "$REDIS_PORT" =~ ^[0-9]+$ ]] || [[ "$REDIS_PORT" -lt 1 ]] || [[ "$REDIS_PORT" -gt 65535 ]]; then
        print_error "Некорректный порт: $REDIS_PORT"
        return 1
    fi
    
    # Проверка доступности порта
    if check_port "localhost" "$REDIS_PORT"; then
        print_warning "Порт $REDIS_PORT уже используется"
        if [[ "$FORCE" != "true" ]]; then
            print_error "Используйте --force для принудительного выполнения"
            return 1
        fi
    fi
    
    print_success "Параметры валидны"
    return 0
}

# Настройка системных параметров
configure_system_parameters() {
    print_section "Настройка системных параметров"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка системных параметров"
        return 0
    fi
    
    # Увеличение лимитов файловых дескрипторов
    print_info "Настройка лимитов файловых дескрипторов"
    
    local limits_conf="/etc/security/limits.d/redis.conf"
    if ! run_sudo test -f "$limits_conf" 2>/dev/null; then
        # Создаем временный файл с содержимым
        local temp_limits="/tmp/redis-limits.conf"
        cat > "$temp_limits" << EOF
# Лимиты для Redis
* soft nofile 65536
* hard nofile 65536
EOF
        
        # Копируем файл с sudo
        if run_sudo cp "$temp_limits" "$limits_conf" && run_sudo chmod 644 "$limits_conf"; then
            print_success "Создан файл лимитов: $limits_conf"
        else
            print_error "Не удалось создать файл лимитов: $limits_conf"
            rm -f "$temp_limits"
            return 1
        fi
        
        # Удаляем временный файл
        rm -f "$temp_limits"
    else
        print_info "Файл лимитов уже существует: $limits_conf"
    fi
    
    # Настройка параметров ядра
    print_info "Настройка параметров ядра"
    
    local sysctl_conf="/etc/sysctl.d/99-redis.conf"
    if ! run_sudo test -f "$sysctl_conf" 2>/dev/null; then
        # Создаем временный файл с содержимым
        local temp_sysctl="/tmp/redis-sysctl.conf"
        cat > "$temp_sysctl" << EOF
# Параметры ядра для Redis
vm.overcommit_memory = 1
net.core.somaxconn = 65535
EOF
        
        # Копируем файл с sudo
        if run_sudo cp "$temp_sysctl" "$sysctl_conf" && run_sudo chmod 644 "$sysctl_conf"; then
            print_success "Создан файл конфигурации ядра: $sysctl_conf"
        else
            print_error "Не удалось создать файл конфигурации ядра: $sysctl_conf"
            rm -f "$temp_sysctl"
            return 1
        fi
        
        # Удаляем временный файл
        rm -f "$temp_sysctl"
    else
        print_info "Файл конфигурации ядра уже существует: $sysctl_conf"
    fi
    
    # Применяем параметры ядра
    print_info "Применение параметров ядра"
    if run_sudo sysctl -p "$sysctl_conf" >/dev/null 2>&1; then
        print_success "Параметры ядра применены успешно"
    else
        print_warning "Не удалось применить параметры ядра (возможно, уже применены)"
    fi
    
    return 0
}

# Создание директорий
create_directories() {
    print_section "Создание директорий"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий"
        return 0
    fi
    
    local dirs=(
        "$REDIS_BASE_DIR"
        "$REDIS_DATA_DIR"
        "$REDIS_CONFIG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if ! run_sudo test -d "$dir"; then
            run_sudo mkdir -p "$dir"
            run_sudo chown -R 999:999 "$dir"  # Redis пользователь в контейнере
            run_sudo chmod 755 "$dir"
            print_success "Создана директория: $dir"
        else
            print_info "Директория уже существует: $dir"
        fi
    done
    
    return 0
}

# Создание .env файла
create_env_file() {
    print_section "Создание .env файла"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла"
        return 0
    fi
    
    local env_file="$REDIS_BASE_DIR/.env"
    local temp_env="/tmp/redis.env"
    
    # Создаем временный файл с содержимым
    cat > "$temp_env" << EOF
# Конфигурация Redis
TIMEZONE=$TIMEZONE
REDIS_VERSION=$REDIS_VERSION
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_BASE_DIR=$REDIS_BASE_DIR
REDIS_DATA_DIR=$REDIS_DATA_DIR
REDIS_CONFIG_DIR=$REDIS_CONFIG_DIR
REDIS_PORT=$REDIS_PORT
REDIS_CONTAINER_NAME=$REDIS_CONTAINER_NAME
REDIS_NETWORK=$REDIS_NETWORK
EOF
    
    # Копируем файл с sudo и устанавливаем права
    if run_sudo cp "$temp_env" "$env_file" && run_sudo chown root:root "$env_file" && run_sudo chmod 644 "$env_file"; then
        print_success "Создан .env файл: $env_file"
    else
        print_error "Не удалось создать .env файл: $env_file"
        rm -f "$temp_env"
        return 1
    fi
    
    # Удаляем временный файл
    rm -f "$temp_env"
    
    return 0
}

# Копирование docker-compose файла (используется универсальная функция из common.sh)
copy_docker_compose() {
    copy_docker_compose_file "Redis" "redis" "$REDIS_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "Redis" "$REDIS_BASE_DIR"
}

# Запуск сервисов Redis
start_redis_services() {
    print_section "Запуск сервисов Redis"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск сервисов Redis"
        return 0
    fi
    
    cd "$REDIS_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $REDIS_BASE_DIR"
        return 1
    }
    
    print_info "Запуск Redis контейнера"
    if run_docker_compose up -d; then
        print_success "Redis контейнер запущен"
    else
        print_error "Не удалось запустить Redis контейнер"
        return 1
    fi
    
    return 0
}

# Ожидание готовности Redis
wait_for_redis() {
    print_section "Ожидание готовности Redis"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности Redis"
        return 0
    fi
    
    local max_attempts=30
    local attempt=1
    
    print_info "Ожидание готовности Redis (максимум $max_attempts попыток)"
    
    while [[ $attempt -le $max_attempts ]]; do
        print_info "Попытка $attempt/$max_attempts"
        
        # Проверка через redis-cli
        if run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD ping" | grep -q "PONG"; then
            print_success "Redis готов к работе"
            return 0
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Redis не готов после $max_attempts попыток"
    return 1
}

# Проверка установки Redis
verify_redis_installation() {
    print_section "Проверка установки Redis"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки Redis"
        return 0
    fi
    
    # Проверка статуса контейнера
    if ! run_sudo docker ps -f name="$REDIS_CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "$REDIS_CONTAINER_NAME"; then
        print_error "Контейнер Redis не запущен"
        return 1
    fi
    
    print_success "Контейнер Redis запущен"
    
    # Проверка доступности порта
    if ! check_port "localhost" "$REDIS_PORT"; then
        print_error "Порт $REDIS_PORT недоступен"
        return 1
    fi
    
    print_success "Порт $REDIS_PORT доступен"
    
    # Проверка подключения к Redis
    if ! run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD ping" | grep -q "PONG"; then
        print_error "Не удалось подключиться к Redis"
        return 1
    fi
    
    print_success "Подключение к Redis успешно"
    
    # Проверка версии Redis
    local redis_version=$(run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD info server" | grep "redis_version" | cut -d: -f2 | tr -d '\r')
    print_info "Версия Redis: $redis_version"
    
    return 0
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении"
    
    echo
    echo -e "${PURPLE}${BOLD}Параметры подключения к Redis:${NC}"
    echo -e "  ${GREEN}Хост:${NC} localhost"
    echo -e "  ${GREEN}Порт:${NC} $REDIS_PORT"
    echo -e "  ${GREEN}Пароль:${NC} $REDIS_PASSWORD"
    echo -e "  ${GREEN}Контейнер:${NC} $REDIS_CONTAINER_NAME"
    echo -e "  ${GREEN}Директория данных:${NC} $REDIS_DATA_DIR"
    echo -e "  ${GREEN}Директория конфигурации:${NC} $REDIS_CONFIG_DIR"
    echo
    echo -e "${PURPLE}${BOLD}Примеры подключения:${NC}"
    echo -e "  ${GREEN}redis-cli:${NC} redis-cli -h localhost -p $REDIS_PORT -a $REDIS_PASSWORD"
    echo -e "  ${GREEN}Docker:${NC} docker exec -it $REDIS_CONTAINER_NAME redis-cli -a $REDIS_PASSWORD"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Redis для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-redis-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Redis"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $REDIS_VERSION"
    log_info "Порт: $REDIS_PORT"
    log_info "Базовая директория: $REDIS_BASE_DIR"
    log_info "Директория данных: $REDIS_DATA_DIR"
    log_info "Директория конфигурации: $REDIS_CONFIG_DIR"
    log_info "Контейнер: $REDIS_CONTAINER_NAME"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_docker"
        "configure_system_parameters"
        "create_directories"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "start_redis_services"
        "wait_for_redis"
        "verify_redis_installation"
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
    
    log_info "Установка Redis завершена успешно"
    
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
