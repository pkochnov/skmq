#!/bin/bash
# =============================================================================
# Скрипт установки ClickHouse
# =============================================================================
# Назначение: Установка и настройка ClickHouse в Docker контейнере
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
    --version VERSION         Версия ClickHouse (по умолчанию: из config/monq.conf)
    --password PASS           Пароль пользователя (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --logs-dir PATH           Директория логов (по умолчанию: из config/monq.conf)
    --http-port PORT          HTTP порт (по умолчанию: из config/monq.conf)
    --tcp-port PORT           TCP порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --database NAME           Имя базы данных (по умолчанию: из config/monq.conf)
    --username NAME           Имя пользователя (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 24.8.2.11 --password mypassword
    $0 --base-dir /opt/clickhouse --dry-run
    $0 --http-port 8124 --tcp-port 9001

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                CLICKHOUSE_VERSION="$2"
                shift 2
                ;;
            --password)
                CLICKHOUSE_PASSWORD="$2"
                shift 2
                ;;
            --base-dir)
                CLICKHOUSE_BASE_DIR="$2"
                CLICKHOUSE_DATA_DIR="$2/data"
                CLICKHOUSE_LOGS_DIR="$2/logs"
                shift 2
                ;;
            --data-dir)
                CLICKHOUSE_DATA_DIR="$2"
                shift 2
                ;;
            --logs-dir)
                CLICKHOUSE_LOGS_DIR="$2"
                shift 2
                ;;
            --http-port)
                CLICKHOUSE_HTTP_PORT="$2"
                shift 2
                ;;
            --tcp-port)
                CLICKHOUSE_TCP_PORT="$2"
                shift 2
                ;;
            --container-name)
                CLICKHOUSE_CONTAINER_NAME="$2"
                shift 2
                ;;
            --database)
                CLICKHOUSE_DB="$2"
                shift 2
                ;;
            --username)
                CLICKHOUSE_USER="$2"
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
    
    if [[ -z "$CLICKHOUSE_VERSION" ]]; then
        log_error "Версия ClickHouse не может быть пустой"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$CLICKHOUSE_PASSWORD" ]]; then
        log_error "Пароль пользователя не может быть пустым"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CLICKHOUSE_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $CLICKHOUSE_HTTP_PORT -lt 1 ]] || [[ $CLICKHOUSE_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $CLICKHOUSE_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CLICKHOUSE_TCP_PORT" =~ ^[0-9]+$ ]] || [[ $CLICKHOUSE_TCP_PORT -lt 1 ]] || [[ $CLICKHOUSE_TCP_PORT -gt 65535 ]]; then
        log_error "Неверный TCP порт: $CLICKHOUSE_TCP_PORT"
        errors=$((errors + 1))
    fi
    

    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}



# Настройка системных параметров для ClickHouse
configure_system_parameters() {
    print_section "Настройка системных параметров для ClickHouse"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка системных параметров"
        return 0
    fi
    
    # Увеличиваем лимит file descriptors
    print_info "Настройка fs.file-max..."
    if ! run_sudo sysctl -w "fs.file-max=2097152"; then
        print_warning "Не удалось установить fs.file-max через sysctl"
        print_info "Добавляем в /etc/sysctl.conf для постоянного применения"
        # Создаем временный файл с содержимым
        local temp_sysctl="/tmp/clickhouse-sysctl-fs.conf"
        echo "fs.file-max=2097152" > "$temp_sysctl"
        run_sudo "cat '$temp_sysctl' >> /etc/sysctl.conf"
        rm -f "$temp_sysctl"
    fi
    
    # Настройка vm.max_map_count
    print_info "Настройка vm.max_map_count..."
    if ! run_sudo sysctl -w "vm.max_map_count=262144"; then
        print_warning "Не удалось установить vm.max_map_count через sysctl"
        print_info "Добавляем в /etc/sysctl.conf для постоянного применения"
        # Создаем временный файл с содержимым
        local temp_sysctl="/tmp/clickhouse-sysctl-vm.conf"
        echo "vm.max_map_count=262144" > "$temp_sysctl"
        run_sudo "cat '$temp_sysctl' >> /etc/sysctl.conf"
        rm -f "$temp_sysctl"
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
    print_section "Создание директорий для ClickHouse"
    
    local directories=(
        "$CLICKHOUSE_BASE_DIR"
        "$CLICKHOUSE_DATA_DIR"
        "$CLICKHOUSE_LOGS_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий ClickHouse"
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
    if run_sudo chown -R 101:101 "$CLICKHOUSE_DATA_DIR" "$CLICKHOUSE_LOGS_DIR"; then
        print_success "Права доступа установлены для директорий ClickHouse"
    else
        print_warning "Не удалось установить права доступа для директорий ClickHouse"
    fi
    
    return 0
}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для ClickHouse"
    
    local env_file="$CLICKHOUSE_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/clickhouse.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# ClickHouse Configuration
TIMEZONE=${TIMEZONE}
CLICKHOUSE_VERSION=${CLICKHOUSE_VERSION}
CLICKHOUSE_CONTAINER_NAME=${CLICKHOUSE_CONTAINER_NAME}
CLICKHOUSE_HTTP_PORT=${CLICKHOUSE_HTTP_PORT}
CLICKHOUSE_TCP_PORT=${CLICKHOUSE_TCP_PORT}
CLICKHOUSE_DATA_DIR=${CLICKHOUSE_DATA_DIR}
CLICKHOUSE_LOGS_DIR=${CLICKHOUSE_LOGS_DIR}
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
CLICKHOUSE_NETWORK=${CLICKHOUSE_NETWORK}
CLICKHOUSE_DB=${CLICKHOUSE_DB}
CLICKHOUSE_USER=${CLICKHOUSE_USER}
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
    copy_docker_compose_file "ClickHouse" "clickhouse" "$CLICKHOUSE_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "ClickHouse" "$CLICKHOUSE_BASE_DIR"
}

# Запуск ClickHouse сервисов
start_clickhouse_services() {
    print_section "Запуск ClickHouse сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск ClickHouse сервисов"
        print_info "[DRY-RUN] Образ: clickhouse/clickhouse-server:$CLICKHOUSE_VERSION"
        print_info "[DRY-RUN] HTTP порт: $CLICKHOUSE_HTTP_PORT:8123"
        print_info "[DRY-RUN] TCP порт: $CLICKHOUSE_TCP_PORT:9000"
        print_info "[DRY-RUN] Данные: $CLICKHOUSE_DATA_DIR:/var/lib/clickhouse"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$CLICKHOUSE_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $CLICKHOUSE_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "ClickHouse сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске ClickHouse сервисов"
        return 1
    fi
}

# Ожидание готовности ClickHouse
wait_for_clickhouse() {
    print_section "Ожидание готовности ClickHouse"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности ClickHouse"
        return 0
    fi
    
    local retry_count=0
    local max_retries=60
    local wait_time=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        local ping_response=$(curl -fsS "http://localhost:$CLICKHOUSE_HTTP_PORT/ping" 2>/dev/null)
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -eq 0 ]] && echo "$ping_response" | grep -q 'Ok'; then
            print_success "ClickHouse готов к работе"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности ClickHouse... ($retry_count/$max_retries) - curl exit code: $curl_exit_code"
        sleep $wait_time
    done
    
    print_error "ClickHouse не готов к работе после $max_retries попыток"
    return 1
}

# Создание пользователя и базы данных
setup_clickhouse_database() {
    print_section "Настройка базы данных ClickHouse"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка базы данных ClickHouse"
        return 0
    fi
    
    # Ожидание готовности
    if ! wait_for_clickhouse; then
        print_error "ClickHouse не готов для настройки базы данных"
        return 1
    fi
    
    # Проверка существования базы данных (с аутентификацией)
    print_info "Проверка существования базы данных '$CLICKHOUSE_DB'"
    local check_db_query="SHOW DATABASES LIKE '$CLICKHOUSE_DB'"
    local check_db_response=$(curl -s -X POST \
        "http://localhost:$CLICKHOUSE_HTTP_PORT/" \
        -d "$check_db_query" \
        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" 2>&1)
    local check_curl_exit_code=$?
    
    log_debug "Проверка БД - ответ: '$check_db_response'"
    log_debug "Проверка БД - код возврата: $check_curl_exit_code"
    
    # Создание базы данных (с аутентификацией)
    local create_db_query="CREATE DATABASE IF NOT EXISTS $CLICKHOUSE_DB"
    print_info "Выполнение запроса: $create_db_query"
    
    local create_db_response=$(curl -s -X POST \
        "http://localhost:$CLICKHOUSE_HTTP_PORT/" \
        -d "$create_db_query" \
        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" 2>&1)
    local curl_exit_code=$?
    
    log_debug "Ответ ClickHouse: '$create_db_response'"
    log_debug "Код возврата curl: $curl_exit_code"
    
    # Анализ результата проверки существования
    if [[ $check_curl_exit_code -eq 0 ]] && echo "$check_db_response" | grep -q "$CLICKHOUSE_DB"; then
        print_info "База данных '$CLICKHOUSE_DB' уже существует"
    else
        # База данных не существует, пытаемся создать
        if [[ $curl_exit_code -eq 0 ]]; then
            # curl выполнился успешно, проверяем ответ
            if [[ -z "$create_db_response" ]]; then
                # Пустой ответ обычно означает успех для CREATE DATABASE IF NOT EXISTS
                print_success "База данных '$CLICKHOUSE_DB' создана успешно (пустой ответ = успех)"
            elif echo "$create_db_response" | grep -q "Ok"; then
                print_success "База данных '$CLICKHOUSE_DB' создана успешно"
            elif echo "$create_db_response" | grep -q "already exists"; then
                print_info "База данных '$CLICKHOUSE_DB' уже существует (обнаружено при создании)"
            else
                print_warning "Неожиданный ответ при создании БД: '$create_db_response'"
                print_info "Предполагаем успех, так как curl завершился с кодом 0"
            fi
        else
            print_error "Ошибка создания базы данных '$CLICKHOUSE_DB'"
            print_error "Ответ сервера: $create_db_response"
            print_error "Код возврата curl: $curl_exit_code"
            return 1
        fi
    fi
    
    # Дополнительная проверка - попытка выполнить запрос к базе данных
    print_info "Проверка доступности базы данных '$CLICKHOUSE_DB'"
    local test_query="USE $CLICKHOUSE_DB; SELECT 1"
    local test_response=$(curl -s -X POST \
        "http://localhost:$CLICKHOUSE_HTTP_PORT/" \
        -d "$test_query" \
        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" 2>&1)
    local test_curl_exit_code=$?
    
    log_debug "Тест БД - ответ: '$test_response'"
    log_debug "Тест БД - код возврата: $test_curl_exit_code"
    
    if [[ $test_curl_exit_code -eq 0 ]] && echo "$test_response" | grep -q "1"; then
        print_success "База данных '$CLICKHOUSE_DB' доступна и работает"
    else
        print_warning "Не удалось подтвердить доступность базы данных '$CLICKHOUSE_DB'"
        print_warning "Ответ теста: '$test_response'"
    fi
    
    return 0
}

# Проверка установки ClickHouse
verify_clickhouse_installation() {
    print_section "Проверка установки ClickHouse"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки ClickHouse"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса контейнера
    if run_docker_compose -f "$CLICKHOUSE_BASE_DIR/docker-compose.yml" ps | grep -q Up; then
        log_debug "Проверка пройдена: контейнер ClickHouse запущен"
    else
        print_warning "Проверка не пройдена: контейнер ClickHouse не запущен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка ping ClickHouse
    local ping_response=$(curl -fsS "http://localhost:$CLICKHOUSE_HTTP_PORT/ping" 2>/dev/null)
    local curl_exit_code=$?
    if [[ $curl_exit_code -eq 0 ]] && echo "$ping_response" | grep -q 'Ok'; then
        log_debug "Проверка пройдена: ClickHouse ping успешен"
    else
        print_warning "Проверка не пройдена: ClickHouse ping неуспешен (curl exit code: $curl_exit_code)"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка Docker сервиса
    if systemctl is-active docker &>/dev/null; then
        log_debug "Проверка пройдена: Docker сервис активен"
    else
        print_warning "Проверка не пройдена: Docker сервис не активен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка версии ClickHouse
    local version_response=$(curl -s "http://localhost:$CLICKHOUSE_HTTP_PORT/" \
        -d "SELECT version()" \
        --user "$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        print_success "Установленная версия ClickHouse: $version_response"
    else
        print_warning "Не удалось определить версию ClickHouse"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности веб-интерфейса
    if curl -s -f "http://localhost:$CLICKHOUSE_HTTP_PORT" &>/dev/null; then
        print_success "Веб-интерфейс ClickHouse доступен"
    else
        print_warning "Веб-интерфейс ClickHouse недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки ClickHouse пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок ClickHouse"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к ClickHouse"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== ClickHouse успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}HTTP интерфейс:${NC} http://$(hostname -I | awk '{print $1}'):$CLICKHOUSE_HTTP_PORT"
    echo -e "${BLUE}TCP интерфейс:${NC} $(hostname -I | awk '{print $1}'):$CLICKHOUSE_TCP_PORT"
    echo -e "${BLUE}Пользователь по умолчанию:${NC} default (без пароля)"
    echo
    echo -e "${BLUE}База данных:${NC} $CLICKHOUSE_DB"
    echo -e "${BLUE}Пользователь БД:${NC} $CLICKHOUSE_USER"
    echo -e "${BLUE}Пароль БД:${NC} $CLICKHOUSE_PASSWORD"
    echo
    echo -e "${BLUE}Контейнер:${NC} $CLICKHOUSE_CONTAINER_NAME"
    echo -e "${BLUE}Сеть:${NC} $CLICKHOUSE_NETWORK"
    echo -e "${BLUE}Базовая директория:${NC} $CLICKHOUSE_BASE_DIR"
    echo -e "${BLUE}База данных:${NC} $CLICKHOUSE_DATA_DIR"

    echo -e "${BLUE}Логи:${NC} $CLICKHOUSE_LOGS_DIR"
    echo
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    echo -e "${PURPLE}${BOLD}Команды управления:${NC}"
    echo -e "  ${GREEN}Остановка:${NC} cd $CLICKHOUSE_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Запуск:${NC} cd $CLICKHOUSE_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Логи:${NC} cd $CLICKHOUSE_BASE_DIR && $compose_cmd logs"
    echo -e "  ${GREEN}Перезапуск:${NC} cd $CLICKHOUSE_BASE_DIR && $compose_cmd restart"
    echo -e "  ${GREEN}Статус:${NC} cd $CLICKHOUSE_BASE_DIR && $compose_cmd ps"
    echo
    echo -e "${PURPLE}${BOLD}Примеры подключения:${NC}"
    echo -e "  ${GREEN}HTTP:${NC} curl 'http://localhost:$CLICKHOUSE_HTTP_PORT/?query=SELECT%201' --user '$CLICKHOUSE_USER:$CLICKHOUSE_PASSWORD'"
    echo -e "  ${GREEN}TCP:${NC} clickhouse-client --host localhost --port $CLICKHOUSE_TCP_PORT --user $CLICKHOUSE_USER --password $CLICKHOUSE_PASSWORD"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка ClickHouse для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-clickhouse-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки ClickHouse"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $CLICKHOUSE_VERSION"
    log_info "HTTP порт: $CLICKHOUSE_HTTP_PORT"
    log_info "TCP порт: $CLICKHOUSE_TCP_PORT"
    log_info "Базовая директория: $CLICKHOUSE_BASE_DIR"
    log_info "Директория данных: $CLICKHOUSE_DATA_DIR"
    log_info "Директория логов: $CLICKHOUSE_LOGS_DIR"
    log_info "База данных: $CLICKHOUSE_DB"
    log_info "Пользователь: $CLICKHOUSE_USER"
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
        "start_clickhouse_services"
        "wait_for_clickhouse"
        "setup_clickhouse_database"
        "verify_clickhouse_installation"
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
    
    log_info "Установка ClickHouse завершена успешно"
    
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
