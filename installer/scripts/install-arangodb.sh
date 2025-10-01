#!/bin/bash
# =============================================================================
# Скрипт установки ArangoDB
# =============================================================================
# Назначение: Установка и настройка ArangoDB в Docker контейнере
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию (загружаются из config/monq.conf)
# ARANGODB_VERSION, ARANGODB_ADMIN_PASSWORD, ARANGODB_BASE_DIR и другие
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
    --version VERSION         Версия ArangoDB (по умолчанию: из config/monq.conf)
    --admin-password PASS     Пароль администратора (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --apps-dir PATH           Директория приложений (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --http-port PORT          HTTP порт (по умолчанию: из config/monq.conf)
    --https-port PORT         HTTPS порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 3.11.0 --admin-password mypassword
    $0 --base-dir /docker/arangodb --dry-run

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                ARANGODB_VERSION="$2"
                shift 2
                ;;
            --admin-password)
                ARANGODB_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --base-dir)
                ARANGODB_BASE_DIR="$2"
                ARANGODB_DATA_DIR="$2/data"
                ARANGODB_CONFIG_DIR="$2/config"
                shift 2
                ;;
            --data-dir)
                ARANGODB_DATA_DIR="$2"
                shift 2
                ;;
            --apps-dir)
                ARANGODB_APPS_DIR="$2"
                shift 2
                ;;
            --config-dir)
                ARANGODB_CONFIG_DIR="$2"
                shift 2
                ;;
            --http-port)
                ARANGODB_HTTP_PORT="$2"
                shift 2
                ;;
            --https-port)
                ARANGODB_HTTPS_PORT="$2"
                shift 2
                ;;
            --container-name)
                ARANGODB_CONTAINER_NAME="$2"
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
    
    if [[ -z "$ARANGODB_VERSION" ]]; then
        log_error "Версия ArangoDB не может быть пустой"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$ARANGODB_ADMIN_PASSWORD" ]]; then
        log_error "Пароль администратора не может быть пустым"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$ARANGODB_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $ARANGODB_HTTP_PORT -lt 1 ]] || [[ $ARANGODB_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $ARANGODB_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$ARANGODB_HTTPS_PORT" =~ ^[0-9]+$ ]] || [[ $ARANGODB_HTTPS_PORT -lt 1 ]] || [[ $ARANGODB_HTTPS_PORT -gt 65535 ]]; then
        log_error "Неверный HTTPS порт: $ARANGODB_HTTPS_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Настройка системных параметров для ArangoDB
configure_system_parameters() {
    print_section "Настройка системных параметров для ArangoDB"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка системных параметров"
        return 0
    fi
    
    # Увеличиваем лимит memory mappings
    print_info "Настройка vm.max_map_count..."
    if ! run_sudo sysctl -w "vm.max_map_count=256000"; then
        print_warning "Не удалось установить vm.max_map_count через sysctl"
        print_info "Добавляем в /etc/sysctl.conf для постоянного применения"
        # Создаем временный файл с содержимым
        local temp_sysctl="/tmp/arangodb-sysctl.conf"
        echo "vm.max_map_count=256000" > "$temp_sysctl"
        run_sudo "cat '$temp_sysctl' >> /etc/sysctl.conf"
        rm -f "$temp_sysctl"
    fi
    
    # Настройка transparent huge pages
    print_info "Настройка transparent huge pages..."
    if run_sudo bash -c "echo madvise > /sys/kernel/mm/transparent_hugepage/enabled"; then
        print_success "Transparent huge pages настроены на madvise"
    else
        print_warning "Не удалось настроить transparent huge pages"
    fi
    
    # Применяем настройки sysctl
    print_info "Применение настроек sysctl..."
    if run_sudo sysctl -p; then
        print_success "Настройки sysctl применены"
    else
        print_warning "Не удалось применить настройки sysctl"
    fi
}

# Создание директорий
create_directories() {
    print_section "Создание директорий для ArangoDB"
    
    local directories=(
        "$ARANGODB_BASE_DIR"
        "$ARANGODB_DATA_DIR"
        "$ARANGODB_APPS_DIR"
        "$ARANGODB_CONFIG_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий ArangoDB"
        for dir in "${directories[@]}"; do
            print_info "[DRY-RUN] mkdir -p $dir"
        done
        return 0
    fi
    
    for dir in "${directories[@]}"; do
        if run_sudo mkdir -p "$dir"; then
            log_debug "Директория создана: $dir"
        else
            print_error "Ошибка при создании директории: $dir"
            return 1
        fi
    done
    
    # Установка прав доступа
    if run_sudo chown -R 999:999 "$ARANGODB_DATA_DIR" "$ARANGODB_APPS_DIR" "$ARANGODB_CONFIG_DIR"; then
        print_success "Права доступа установлены для директорий ArangoDB"
    else
        print_warning "Не удалось установить права доступа для директорий ArangoDB"
    fi
    
    return 0
}

# Копирование конфигурационного файла ArangoDB
copy_arangodb_config() {
    print_section "Копирование конфигурационного файла ArangoDB"
    
    local config_file="$ARANGODB_CONFIG_DIR/arangod.conf"
    local source_config=""
    
    # Определяем путь к исходному конфигурационному файлу
    if [[ -f "$SCRIPT_DIR/../config/arangodb/arangod.conf" ]]; then
        # Локальное выполнение
        source_config="$SCRIPT_DIR/../config/arangodb/arangod.conf"
    elif [[ -f "./config/arangodb/arangod.conf" ]]; then
        # Выполнение в временной директории на удаленном хосте
        source_config="./config/arangodb/arangod.conf"
    else
        print_error "Конфигурационный файл ArangoDB не найден ни в одном из ожидаемых мест"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Копирование конфигурационного файла: $source_config -> $config_file"
        return 0
    fi
    
    # Отладочная информация
    log_debug "Текущая директория: $(pwd)"
    log_debug "Ищем конфигурацию: $source_config"
    log_debug "Содержимое текущей директории:"
    log_debug "$(ls -la)"
    if [[ -d "./config" ]]; then
        log_debug "Содержимое директории config:"
        log_debug "$(ls -la ./config/)"
        if [[ -d "./config/arangodb" ]]; then
            log_debug "Содержимое директории config/arangodb:"
            log_debug "$(ls -la ./config/arangodb/)"
        fi
    fi
    
    # Проверяем существование исходного файла
    if [[ ! -f "$source_config" ]]; then
        print_error "Конфигурационный файл ArangoDB не найден: $source_config"
        return 1
    fi
    
    # Копируем конфигурационный файл
    if run_sudo cp "$source_config" "$config_file"; then
        run_sudo chown 999:999 "$config_file"
        run_sudo chmod 644 "$config_file"
        print_success "Конфигурационный файл ArangoDB скопирован"
        return 0
    else
        print_error "Ошибка при копировании конфигурационного файла ArangoDB"
        return 1
    fi
}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для ArangoDB"
    
    local env_file="$ARANGODB_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/arangodb.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# ArangoDB Configuration
TIMEZONE=${TIMEZONE}
ARANGODB_VERSION=${ARANGODB_VERSION}
ARANGODB_CONTAINER_NAME=${ARANGODB_CONTAINER_NAME}
ARANGODB_HTTP_PORT=${ARANGODB_HTTP_PORT}
ARANGODB_HTTPS_PORT=${ARANGODB_HTTPS_PORT}
ARANGODB_DATA_DIR=${ARANGODB_DATA_DIR}
ARANGODB_APPS_DIR=${ARANGODB_APPS_DIR}
ARANGODB_CONFIG_DIR=${ARANGODB_CONFIG_DIR}
ARANGODB_ADMIN_PASSWORD=${ARANGODB_ADMIN_PASSWORD}
ARANGODB_NETWORK=${ARANGODB_NETWORK}
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
    copy_docker_compose_file "ArangoDB" "arangodb" "$ARANGODB_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "ArangoDB" "$ARANGODB_BASE_DIR"
}

# Запуск ArangoDB сервисов
start_arangodb_services() {
    print_section "Запуск ArangoDB сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск ArangoDB сервисов"
        print_info "[DRY-RUN] Образ: arangodb:$ARANGODB_VERSION"
        print_info "[DRY-RUN] Порт: $ARANGODB_HTTP_PORT:8529"
        print_info "[DRY-RUN] Данные: $ARANGODB_DATA_DIR:/var/lib/arangodb3"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$ARANGODB_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $ARANGODB_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "ArangoDB сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске ArangoDB сервисов"
        return 1
    fi
}

# Ожидание готовности ArangoDB
wait_for_arangodb() {
    print_section "Ожидание готовности ArangoDB"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности ArangoDB"
        return 0
    fi
    
    local retry_count=0
    local max_retries=60
    local wait_time=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -s -f "http://localhost:$ARANGODB_HTTP_PORT/_api/version" &>/dev/null; then
            print_success "ArangoDB готов к работе"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности ArangoDB... ($retry_count/$max_retries)"
        sleep $wait_time
    done
    
    print_error "ArangoDB не готов к работе после $max_retries попыток"
    return 1
}

# Создание пользователя и базы данных
setup_arangodb_database() {
    print_section "Настройка базы данных ArangoDB"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка базы данных ArangoDB"
        return 0
    fi
    
    # Ожидание готовности
    if ! wait_for_arangodb; then
        print_error "ArangoDB не готов для настройки базы данных"
        return 1
    fi
    
    # Создание базы данных
    local db_name="monq"
    local db_user="monq_user"
    local db_password="monq_db_2024"
    
    # Создание базы данных через API
    local create_db_response=$(curl -s -X POST \
        "http://localhost:$ARANGODB_HTTP_PORT/_api/database" \
        -H "Content-Type: application/json" \
        -u "root:$ARANGODB_ADMIN_PASSWORD" \
        -d "{\"name\": \"$db_name\"}")
    
    if echo "$create_db_response" | grep -q '"error":false'; then
        print_success "База данных '$db_name' создана"
    else
        print_warning "База данных '$db_name' уже существует или ошибка создания"
    fi
    
    # Создание пользователя
    local create_user_response=$(curl -s -X POST \
        "http://localhost:$ARANGODB_HTTP_PORT/_api/user" \
        -H "Content-Type: application/json" \
        -u "root:$ARANGODB_ADMIN_PASSWORD" \
        -d "{\"user\": \"$db_user\", \"passwd\": \"$db_password\"}")
    
    if echo "$create_user_response" | grep -q '"error":false'; then
        print_success "Пользователь '$db_user' создан"
    else
        print_warning "Пользователь '$db_user' уже существует или ошибка создания"
    fi
    
    # Предоставление прав доступа к базе данных
    local grant_permissions_response=$(curl -s -X PUT \
        "http://localhost:$ARANGODB_HTTP_PORT/_api/user/$db_user/database/$db_name" \
        -H "Content-Type: application/json" \
        -u "root:$ARANGODB_ADMIN_PASSWORD" \
        -d "{\"grant\": \"rw\"}")
    
    if echo "$grant_permissions_response" | grep -q '"error":false'; then
        print_success "Права доступа предоставлены пользователю '$db_user' для базы '$db_name'"
    else
        print_warning "Ошибка при предоставлении прав доступа"
    fi
    
    return 0
}

# Проверка установки ArangoDB
verify_arangodb_installation() {
    print_section "Проверка установки ArangoDB"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки ArangoDB"
        return 0
    fi
    
    local checks=(
        "run_docker_compose -f $ARANGODB_BASE_DIR/docker-compose.yml ps | grep -q Up"
        "curl -s http://localhost:$ARANGODB_HTTP_PORT/_api/version"
        "systemctl is-active docker"
    )
    
    local failed_checks=0
    
    for check in "${checks[@]}"; do
        if eval "$check" &>/dev/null; then
            log_debug "Проверка пройдена: $check"
        else
            print_warning "Проверка не пройдена: $check"
            failed_checks=$((failed_checks + 1))
        fi
    done
    
    # Проверка версии ArangoDB
    local version_response=$(curl -s "http://localhost:$ARANGODB_HTTP_PORT/_api/version" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        local version=$(echo "$version_response" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        print_success "Установленная версия ArangoDB: $version"
    else
        print_warning "Не удалось определить версию ArangoDB"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности веб-интерфейса
    if curl -s -f "http://localhost:$ARANGODB_HTTP_PORT" &>/dev/null; then
        print_success "Веб-интерфейс ArangoDB доступен"
    else
        print_warning "Веб-интерфейс ArangoDB недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки ArangoDB пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок ArangoDB"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к ArangoDB"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== ArangoDB успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}Веб-интерфейс:${NC} http://$(hostname -I | awk '{print $1}'):$ARANGODB_HTTP_PORT"
    echo -e "${BLUE}Пользователь:${NC} root"
    echo -e "${BLUE}Пароль:${NC} $ARANGODB_ADMIN_PASSWORD"
    echo
    echo -e "${BLUE}База данных:${NC} monq"
    echo -e "${BLUE}Пользователь БД:${NC} monq_user"
    echo -e "${BLUE}Пароль БД:${NC} monq_db_2024"
    echo
    echo -e "${BLUE}Контейнер:${NC} $ARANGODB_CONTAINER_NAME"
    echo -e "${BLUE}Сеть:${NC} $ARANGODB_NETWORK"
    echo -e "${BLUE}Базовая директория:${NC} $ARANGODB_BASE_DIR"
    echo -e "${BLUE}База данных:${NC} $ARANGODB_DATA_DIR"
    echo -e "${BLUE}Приложения:${NC} $ARANGODB_APPS_DIR"
    echo -e "${BLUE}Конфигурация:${NC} $ARANGODB_CONFIG_DIR"
    echo
    local compose_cmd=$(get_docker_compose_cmd)
    echo -e "${PURPLE}${BOLD}Команды управления:${NC}"
    echo -e "  ${GREEN}Остановка:${NC} cd $ARANGODB_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Запуск:${NC} cd $ARANGODB_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Логи:${NC} cd $ARANGODB_BASE_DIR && $compose_cmd logs"
    echo -e "  ${GREEN}Перезапуск:${NC} cd $ARANGODB_BASE_DIR && $compose_cmd restart"
    echo -e "  ${GREEN}Статус:${NC} cd $ARANGODB_BASE_DIR && $compose_cmd ps"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка ArangoDB для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-arangodb-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки ArangoDB"
    log_info "Версия: $ARANGODB_VERSION"
    log_info "HTTP порт: $ARANGODB_HTTP_PORT"
    log_info "HTTPS порт: $ARANGODB_HTTPS_PORT"
    log_info "Базовая директория: $ARANGODB_BASE_DIR"
    log_info "Директория данных: $ARANGODB_DATA_DIR"
    log_info "Директория приложений: $ARANGODB_APPS_DIR"
    log_info "Директория конфигурации: $ARANGODB_CONFIG_DIR"
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
        "copy_arangodb_config"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "start_arangodb_services"
        "wait_for_arangodb"
        "setup_arangodb_database"
        "verify_arangodb_installation"
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
    
    log_info "Установка ArangoDB завершена успешно"
    
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
