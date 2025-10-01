#!/bin/bash
# =============================================================================
# Скрипт установки PostgreSQL
# =============================================================================
# Назначение: Установка и настройка PostgreSQL в Docker контейнере
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию (загружаются из config/monq.conf)
# POSTGRESQL_VERSION, POSTGRESQL_PASSWORD, POSTGRESQL_BASE_DIR и другие
# определены в config/monq.conf
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
    --version VERSION         Версия PostgreSQL (по умолчанию: из config/monq.conf)
    --password PASS           Пароль для PostgreSQL (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --init-dir PATH           Директория инициализации (по умолчанию: из config/monq.conf)
    --port PORT               Порт PostgreSQL (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --database DB             Имя базы данных (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 16.1 --password mypassword
    $0 --base-dir /docker/postgresql --dry-run

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                POSTGRESQL_VERSION="$2"
                shift 2
                ;;
            --password)
                POSTGRESQL_PASSWORD="$2"
                shift 2
                ;;
            --base-dir)
                POSTGRESQL_BASE_DIR="$2"
                POSTGRESQL_DATA_DIR="$2/data"
                POSTGRESQL_CONFIG_DIR="$2/config"
                POSTGRESQL_INIT_DIR="$2/init"
                shift 2
                ;;
            --data-dir)
                POSTGRESQL_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                POSTGRESQL_CONFIG_DIR="$2"
                shift 2
                ;;
            --init-dir)
                POSTGRESQL_INIT_DIR="$2"
                shift 2
                ;;
            --port)
                POSTGRESQL_PORT="$2"
                shift 2
                ;;
            --container-name)
                POSTGRESQL_CONTAINER_NAME="$2"
                shift 2
                ;;
            --database)
                POSTGRESQL_DB="$2"
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
                log_error "Неизвестный параметр: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Валидация параметров
validate_parameters() {
    local errors=0
    
    if [[ -z "$POSTGRESQL_VERSION" ]]; then
        log_error "Версия PostgreSQL не может быть пустой"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$POSTGRESQL_PASSWORD" ]]; then
        log_error "Пароль PostgreSQL не может быть пустым"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$POSTGRESQL_PORT" =~ ^[0-9]+$ ]] || [[ $POSTGRESQL_PORT -lt 1 ]] || [[ $POSTGRESQL_PORT -gt 65535 ]]; then
        log_error "Неверный порт PostgreSQL: $POSTGRESQL_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}



# Создание структуры директорий
create_directories() {
    log_info "Создание структуры директорий..."
    
    local dirs=(
        "$POSTGRESQL_BASE_DIR"
        "$POSTGRESQL_DATA_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий PostgreSQL"
        for dir in "${dirs[@]}"; do
            print_info "[DRY-RUN] mkdir -p $dir"
        done
        return 0
    fi
    
    for dir in "${dirs[@]}"; do
        if run_sudo mkdir -p "$dir"; then
            log_debug "Директория создана: $dir"
        else
            log_error "Не удалось создать директорию: $dir"
            exit 1
        fi
    done
    
    # Установка правильных прав доступа
    if [[ "$DRY_RUN" != "true" ]]; then
        if run_sudo chown -R 999:999 "$POSTGRESQL_DATA_DIR"; then
            log_debug "Установлены права доступа для директории данных"
        else
            log_error "Не удалось установить права доступа для директории данных"
            exit 1
        fi
    fi
}

# Создание конфигурационных файлов
create_config_files() {
    log_info "Создание конфигурационных файлов..."
    

    

}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для PostgreSQL"
    
    local env_file="$POSTGRESQL_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/postgresql.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# PostgreSQL Configuration
TIMEZONE=${TIMEZONE}
POSTGRESQL_VERSION=${POSTGRESQL_VERSION}
POSTGRESQL_DB=${POSTGRESQL_DB}
POSTGRESQL_PASSWORD=${POSTGRESQL_PASSWORD}
POSTGRESQL_BASE_DIR=${POSTGRESQL_BASE_DIR}
POSTGRESQL_DATA_DIR=${POSTGRESQL_DATA_DIR}
POSTGRESQL_PORT=${POSTGRESQL_PORT}
POSTGRESQL_CONTAINER_NAME=${POSTGRESQL_CONTAINER_NAME}
POSTGRESQL_NETWORK=${POSTGRESQL_NETWORK}
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

# Копирование Docker Compose файла (используется универсальная функция из common.sh)
copy_docker_compose() {
    copy_docker_compose_file "PostgreSQL" "postgres" "$POSTGRESQL_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "PostgreSQL" "$POSTGRESQL_BASE_DIR"
}

# Настройка файрвола
configure_firewall() {
    if [[ "$CONFIGURE_FIREWALL" != "true" ]]; then
        log_info "Настройка файрвола отключена"
        return 0
    fi
    
    log_info "Настройка файрвола для PostgreSQL..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Открытие порта $POSTGRESQL_PORT в файрволе"
        return 0
    fi
    
    # Проверка статуса firewalld
    if ! run_sudo systemctl is-active firewalld &> /dev/null; then
        log_warn "Firewalld не активен, пропускаем настройку файрвола"
        return 0
    fi
    
    # Открытие порта PostgreSQL
    if run_sudo firewall-cmd --permanent --add-port=${POSTGRESQL_PORT}/tcp; then
        print_success "Добавлен порт $POSTGRESQL_PORT в постоянные правила файрвола"
    else
        log_warn "Не удалось добавить порт $POSTGRESQL_PORT в файрвол"
    fi
    
    # Перезагрузка правил файрвола
    if run_sudo firewall-cmd --reload; then
        print_success "Перезагружены правила файрвола"
    else
        log_warn "Не удалось перезагрузить правила файрвола"
    fi
}

# Запуск PostgreSQL
start_postgresql() {
    log_info "Запуск PostgreSQL..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Запуск PostgreSQL контейнера"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$POSTGRESQL_BASE_DIR" || {
        log_error "Не удалось перейти в директорию: $POSTGRESQL_BASE_DIR"
        exit 1
    }
    
    # Запуск контейнера
    if run_docker_compose up -d; then
        print_success "PostgreSQL контейнер запущен"
    else
        log_error "Не удалось запустить PostgreSQL контейнер"
        exit 1
    fi
    
    # Ожидание готовности
    log_info "Ожидание готовности PostgreSQL..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if run_docker_compose exec -T postgresql pg_isready -U postgres -d ${POSTGRESQL_DB} &> /dev/null; then
            print_success "PostgreSQL готов к работе"
            break
        fi
        
        log_info "Попытка $attempt/$max_attempts: PostgreSQL еще не готов..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "PostgreSQL не готов после $max_attempts попыток"
        log_error "Проверьте логи: run_docker_compose logs postgresql"
        exit 1
    fi
}

# Проверка установки
verify_installation() {
    log_info "Проверка установки PostgreSQL..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка установки PostgreSQL"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса контейнера
    if run_docker_compose ps | grep -q "Up"; then
        log_debug "Проверка пройдена: контейнер PostgreSQL запущен"
    else
        print_warning "Проверка не пройдена: контейнер PostgreSQL не запущен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка подключения к базе данных
    if run_docker_compose exec -T postgresql psql -U postgres -d ${POSTGRESQL_DB} -c 'SELECT version();' &> /dev/null; then
        log_debug "Проверка пройдена: подключение к базе данных работает"
    else
        print_warning "Проверка не пройдена: не удалось подключиться к базе данных"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки установки PostgreSQL пройдены успешно"
        return 0
    else
        print_warning "Обнаружено $failed_checks проблем при проверке установки"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к PostgreSQL"
    
    echo
    echo -e "${PURPLE}${BOLD}Основная информация:${NC}"
    echo -e "  ${GREEN}Хост:${NC} $(hostname)"
    echo -e "  ${GREEN}Порт:${NC} $POSTGRESQL_PORT"
    echo -e "  ${GREEN}База данных:${NC} $POSTGRESQL_DB"

    echo
    echo -e "${PURPLE}${BOLD}Строка подключения:${NC}"
    echo -e "  ${GREEN}Администратор:${NC} postgresql://postgres:${POSTGRESQL_PASSWORD}@$(hostname):${POSTGRESQL_PORT}/${POSTGRESQL_DB}"
    echo
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    echo -e "${PURPLE}${BOLD}Управление контейнером:${NC}"
    echo -e "  ${GREEN}Запуск:${NC} cd $POSTGRESQL_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Остановка:${NC} cd $POSTGRESQL_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Логи:${NC} cd $POSTGRESQL_BASE_DIR && $compose_cmd logs -f"
    echo -e "  ${GREEN}Подключение:${NC} $compose_cmd exec postgresql psql -U postgres -d $POSTGRESQL_DB"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка PostgreSQL для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-postgresql-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки PostgreSQL"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $POSTGRESQL_VERSION"
    log_info "Порт: $POSTGRESQL_PORT"
    log_info "Базовая директория: $POSTGRESQL_BASE_DIR"
    log_info "Директория данных: $POSTGRESQL_DATA_DIR"
    log_info "База данных: $POSTGRESQL_DB"

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
        "create_config_files"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "configure_firewall"
        "start_postgresql"
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
    
    log_info "Установка PostgreSQL завершена успешно"
    
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
