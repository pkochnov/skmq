#!/bin/bash
# =============================================================================
# Скрипт установки VictoriaMetrics
# =============================================================================
# Назначение: Установка и настройка VictoriaMetrics в Docker контейнере
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
    --version VERSION         Версия VictoriaMetrics (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --http-port PORT          HTTP порт (по умолчанию: из config/monq.conf)
    --ingest-port PORT        Ingest порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --retention PERIOD        Время хранения метрик (по умолчанию: из config/monq.conf)
    --memory MB               Память для VictoriaMetrics в MB (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 1.95.1 --retention 2y
    $0 --base-dir /opt/victoriametrics --dry-run
    $0 --http-port 8429 --ingest-port 2004

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VICTORIAMETRICS_VERSION="$2"
                shift 2
                ;;
            --base-dir)
                VICTORIAMETRICS_BASE_DIR="$2"
                VICTORIAMETRICS_DATA_DIR="$2/data"
                VICTORIAMETRICS_CONFIG_DIR="$2/config"
                shift 2
                ;;
            --data-dir)
                VICTORIAMETRICS_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                VICTORIAMETRICS_CONFIG_DIR="$2"
                shift 2
                ;;
            --http-port)
                VICTORIAMETRICS_HTTP_PORT="$2"
                shift 2
                ;;
            --ingest-port)
                VICTORIAMETRICS_INGEST_PORT="$2"
                shift 2
                ;;
            --container-name)
                VICTORIAMETRICS_CONTAINER_NAME="$2"
                shift 2
                ;;
            --retention)
                VICTORIAMETRICS_RETENTION="$2"
                shift 2
                ;;
            --memory)
                VICTORIAMETRICS_MEMORY="$2"
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
    
    if [[ -z "$VICTORIAMETRICS_VERSION" ]]; then
        log_error "Версия VictoriaMetrics не может быть пустой"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$VICTORIAMETRICS_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $VICTORIAMETRICS_HTTP_PORT -lt 1 ]] || [[ $VICTORIAMETRICS_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $VICTORIAMETRICS_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$VICTORIAMETRICS_INGEST_PORT" =~ ^[0-9]+$ ]] || [[ $VICTORIAMETRICS_INGEST_PORT -lt 1 ]] || [[ $VICTORIAMETRICS_INGEST_PORT -gt 65535 ]]; then
        log_error "Неверный Ingest порт: $VICTORIAMETRICS_INGEST_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$VICTORIAMETRICS_MEMORY" =~ ^[0-9]+$ ]] || [[ $VICTORIAMETRICS_MEMORY -lt 128 ]]; then
        log_error "Неверное значение памяти: $VICTORIAMETRICS_MEMORY (минимум 128 MB)"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Настройка системных параметров для VictoriaMetrics
configure_system_parameters() {
    print_section "Настройка системных параметров для VictoriaMetrics"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка системных параметров"
        return 0
    fi
    
    # Увеличиваем лимит file descriptors
    print_info "Настройка fs.file-max..."
    if ! run_sudo sysctl -w "fs.file-max=2097152"; then
        print_warning "Не удалось установить fs.file-max через sysctl"
        print_info "Добавляем в /etc/sysctl.conf для постоянного применения"
        local temp_sysctl="/tmp/victoriametrics-sysctl-fs.conf"
        echo "fs.file-max=2097152" > "$temp_sysctl"
        run_sudo "cat '$temp_sysctl' >> /etc/sysctl.conf"
        rm -f "$temp_sysctl"
    fi
    
    # Настройка vm.max_map_count
    print_info "Настройка vm.max_map_count..."
    if ! run_sudo sysctl -w "vm.max_map_count=262144"; then
        print_warning "Не удалось установить vm.max_map_count через sysctl"
        print_info "Добавляем в /etc/sysctl.conf для постоянного применения"
        local temp_sysctl="/tmp/victoriametrics-sysctl-vm.conf"
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
    print_section "Создание директорий для VictoriaMetrics"
    
    local directories=(
        "$VICTORIAMETRICS_BASE_DIR"
        "$VICTORIAMETRICS_DATA_DIR"
        "$VICTORIAMETRICS_CONFIG_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий VictoriaMetrics"
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
    if run_sudo chown -R 1000:1000 "$VICTORIAMETRICS_DATA_DIR" "$VICTORIAMETRICS_CONFIG_DIR"; then
        print_success "Права доступа установлены для директорий VictoriaMetrics"
    else
        print_warning "Не удалось установить права доступа для директорий VictoriaMetrics"
    fi
    
    return 0
}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для VictoriaMetrics"
    
    local env_file="$VICTORIAMETRICS_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/victoriametrics.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# VictoriaMetrics Configuration
TIMEZONE=${TIMEZONE}
VICTORIAMETRICS_VERSION=${VICTORIAMETRICS_VERSION}
VICTORIAMETRICS_CONTAINER_NAME=${VICTORIAMETRICS_CONTAINER_NAME}
VICTORIAMETRICS_HTTP_PORT=${VICTORIAMETRICS_HTTP_PORT}
VICTORIAMETRICS_INGEST_PORT=${VICTORIAMETRICS_INGEST_PORT}
VICTORIAMETRICS_DATA_DIR=${VICTORIAMETRICS_DATA_DIR}
VICTORIAMETRICS_CONFIG_DIR=${VICTORIAMETRICS_CONFIG_DIR}
VICTORIAMETRICS_RETENTION=${VICTORIAMETRICS_RETENTION}
VICTORIAMETRICS_MEMORY=${VICTORIAMETRICS_MEMORY}
VICTORIAMETRICS_NETWORK=${VICTORIAMETRICS_NETWORK}
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
    copy_docker_compose_file "VictoriaMetrics" "victoriametrics" "$VICTORIAMETRICS_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "VictoriaMetrics" "$VICTORIAMETRICS_BASE_DIR"
}

# Запуск VictoriaMetrics сервисов
start_victoriametrics_services() {
    print_section "Запуск VictoriaMetrics сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск VictoriaMetrics сервисов"
        print_info "[DRY-RUN] Образ: victoriametrics/victoria-metrics:$VICTORIAMETRICS_VERSION"
        print_info "[DRY-RUN] HTTP порт: $VICTORIAMETRICS_HTTP_PORT:8428"
        print_info "[DRY-RUN] Ingest порт: $VICTORIAMETRICS_INGEST_PORT:2003"
        print_info "[DRY-RUN] Данные: $VICTORIAMETRICS_DATA_DIR:/victoria-metrics-data"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$VICTORIAMETRICS_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $VICTORIAMETRICS_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "VictoriaMetrics сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске VictoriaMetrics сервисов"
        return 1
    fi
}

# Ожидание готовности VictoriaMetrics
wait_for_victoriametrics() {
    print_section "Ожидание готовности VictoriaMetrics"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности VictoriaMetrics"
        return 0
    fi
    
    local retry_count=0
    local max_retries=60
    local wait_time=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        local health_response=$(curl -fsS "http://localhost:$VICTORIAMETRICS_HTTP_PORT/health" 2>/dev/null)
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -eq 0 ]] && echo "$health_response" | grep -q 'OK'; then
            print_success "VictoriaMetrics готов к работе"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности VictoriaMetrics... ($retry_count/$max_retries) - curl exit code: $curl_exit_code"
        sleep $wait_time
    done
    
    print_error "VictoriaMetrics не готов к работе после $max_retries попыток"
    return 1
}

# Проверка установки VictoriaMetrics
verify_victoriametrics_installation() {
    print_section "Проверка установки VictoriaMetrics"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки VictoriaMetrics"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса контейнера
    if run_docker_compose -f "$VICTORIAMETRICS_BASE_DIR/docker-compose.yml" ps | grep -q Up; then
        log_debug "Проверка пройдена: контейнер VictoriaMetrics запущен"
    else
        print_warning "Проверка не пройдена: контейнер VictoriaMetrics не запущен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка health endpoint
    local health_response=$(curl -fsS "http://localhost:$VICTORIAMETRICS_HTTP_PORT/health" 2>/dev/null)
    local curl_exit_code=$?
    if [[ $curl_exit_code -eq 0 ]] && echo "$health_response" | grep -q 'OK'; then
        log_debug "Проверка пройдена: VictoriaMetrics health check успешен"
    else
        print_warning "Проверка не пройдена: VictoriaMetrics health check неуспешен (curl exit code: $curl_exit_code)"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка Docker сервиса
    if systemctl is-active docker &>/dev/null; then
        log_debug "Проверка пройдена: Docker сервис активен"
    else
        print_warning "Проверка не пройдена: Docker сервис не активен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка версии VictoriaMetrics
    local version_response=$(curl -s "http://localhost:$VICTORIAMETRICS_HTTP_PORT/version" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        print_success "Установленная версия VictoriaMetrics: $version_response"
    else
        print_warning "Не удалось определить версию VictoriaMetrics"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности веб-интерфейса
    if curl -s -f "http://localhost:$VICTORIAMETRICS_HTTP_PORT" &>/dev/null; then
        print_success "Веб-интерфейс VictoriaMetrics доступен"
    else
        print_warning "Веб-интерфейс VictoriaMetrics недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки VictoriaMetrics пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок VictoriaMetrics"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к VictoriaMetrics"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== VictoriaMetrics успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}HTTP интерфейс:${NC} http://$(hostname -I | awk '{print $1}'):$VICTORIAMETRICS_HTTP_PORT"
    echo -e "${BLUE}Ingest интерфейс:${NC} $(hostname -I | awk '{print $1}'):$VICTORIAMETRICS_INGEST_PORT"
    echo -e "${BLUE}Время хранения:${NC} $VICTORIAMETRICS_RETENTION"
    echo -e "${BLUE}Память:${NC} $VICTORIAMETRICS_MEMORY MB"
    echo
    echo -e "${BLUE}Контейнер:${NC} $VICTORIAMETRICS_CONTAINER_NAME"
    echo -e "${BLUE}Сеть:${NC} $VICTORIAMETRICS_NETWORK"
    echo -e "${BLUE}Базовая директория:${NC} $VICTORIAMETRICS_BASE_DIR"
    echo -e "${BLUE}Данные:${NC} $VICTORIAMETRICS_DATA_DIR"
    echo -e "${BLUE}Конфигурация:${NC} $VICTORIAMETRICS_CONFIG_DIR"
    echo
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    echo -e "${PURPLE}${BOLD}Команды управления:${NC}"
    echo -e "  ${GREEN}Остановка:${NC} cd $VICTORIAMETRICS_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Запуск:${NC} cd $VICTORIAMETRICS_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Логи:${NC} cd $VICTORIAMETRICS_BASE_DIR && $compose_cmd logs"
    echo -e "  ${GREEN}Перезапуск:${NC} cd $VICTORIAMETRICS_BASE_DIR && $compose_cmd restart"
    echo -e "  ${GREEN}Статус:${NC} cd $VICTORIAMETRICS_BASE_DIR && $compose_cmd ps"
    echo
    echo -e "${PURPLE}${BOLD}Примеры использования:${NC}"
    echo -e "  ${GREEN}Health check:${NC} curl http://localhost:$VICTORIAMETRICS_HTTP_PORT/health"
    echo -e "  ${GREEN}Версия:${NC} curl http://localhost:$VICTORIAMETRICS_HTTP_PORT/version"
    echo -e "  ${GREEN}Метрики:${NC} curl http://localhost:$VICTORIAMETRICS_HTTP_PORT/metrics"
    echo -e "  ${GREEN}Отправка метрики:${NC} echo 'test_metric 123' | nc localhost $VICTORIAMETRICS_INGEST_PORT"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка VictoriaMetrics для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-victoriametrics-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки VictoriaMetrics"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $VICTORIAMETRICS_VERSION"
    log_info "HTTP порт: $VICTORIAMETRICS_HTTP_PORT"
    log_info "Ingest порт: $VICTORIAMETRICS_INGEST_PORT"
    log_info "Базовая директория: $VICTORIAMETRICS_BASE_DIR"
    log_info "Директория данных: $VICTORIAMETRICS_DATA_DIR"
    log_info "Директория конфигурации: $VICTORIAMETRICS_CONFIG_DIR"
    log_info "Время хранения: $VICTORIAMETRICS_RETENTION"
    log_info "Память: $VICTORIAMETRICS_MEMORY MB"
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
        "start_victoriametrics_services"
        "wait_for_victoriametrics"
        "verify_victoriametrics_installation"
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
    
    log_info "Установка VictoriaMetrics завершена успешно"
    
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
