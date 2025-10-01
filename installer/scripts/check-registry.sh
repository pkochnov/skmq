#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Docker Registry
# =============================================================================
# Назначение: Проверка состояния и работоспособности Docker Registry
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
# REGISTRY_PORT, REGISTRY_CONTAINER_NAME, REGISTRY_BASE_DIR и другие
# определены в config/monq.conf
FORMAT="text"
DRY_RUN=false

# Функции цветного вывода загружаются из common.sh

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --registry-port PORT       Порт Registry (по умолчанию: из monq.conf)
    --registry-container NAME  Имя контейнера Registry (по умолчанию: из monq.conf)
    --base-dir PATH            Базовая директория (по умолчанию: из monq.conf)
    --data-dir PATH            Директория данных (по умолчанию: из monq.conf)
    --config-dir PATH          Директория конфигурации (по умолчанию: из monq.conf)
    --network NAME             Имя сети (по умолчанию: из monq.conf)
    --format FORMAT            Формат вывода (text, json) (по умолчанию: text)
    --dry-run                  Режим симуляции (без выполнения команд)
    --help                     Показать эту справку

Примечание: Все настройки по умолчанию загружаются из файла config/monq.conf.
Для изменения настроек отредактируйте соответствующие переменные в monq.conf.

Примеры:
    $0 --format json
    $0 --registry-port 6000

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --registry-port)
                REGISTRY_PORT="$2"
                shift 2
                ;;
            --registry-container)
                REGISTRY_CONTAINER_NAME="$2"
                shift 2
                ;;
            --base-dir)
                REGISTRY_BASE_DIR="$2"
                REGISTRY_DATA_DIR="$2/data"
                REGISTRY_CONFIG_DIR="$2/config"
                shift 2
                ;;
            --data-dir)
                REGISTRY_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                REGISTRY_CONFIG_DIR="$2"
                shift 2
                ;;
            --network)
                REGISTRY_NETWORK="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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
    
    if [[ ! "$REGISTRY_PORT" =~ ^[0-9]+$ ]] || [[ $REGISTRY_PORT -lt 1 ]] || [[ $REGISTRY_PORT -gt 65535 ]]; then
        log_error "Неверный порт Registry: $REGISTRY_PORT"
        errors=$((errors + 1))
    fi
    

    
    case "$FORMAT" in
        text|json)
            ;;
        *)
            log_error "Неверный формат: $FORMAT (допустимо: text, json)"
            errors=$((errors + 1))
            ;;
    esac
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Проверка контейнера Docker Registry
check_container() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка контейнера Docker Registry"
        return 0
    fi
    
    if ! sudo docker ps --filter "name=$REGISTRY_CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$REGISTRY_CONTAINER_NAME"; then
        print_error "Контейнер $REGISTRY_CONTAINER_NAME не запущен"
        return 1
    else
        local container_status=$(sudo docker ps --filter "name=$REGISTRY_CONTAINER_NAME" --format "{{.Status}}")
        if echo "$container_status" | grep -q "Up"; then
            print_success "Контейнер $REGISTRY_CONTAINER_NAME запущен: $container_status"
            return 0
        else
            print_error "Контейнер $REGISTRY_CONTAINER_NAME не активен: $container_status"
            return 1
        fi
    fi
}

# Проверка портов
check_ports() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка портов Docker Registry"
        return 0
    fi
    
    # Проверка порта Registry
    if sudo netstat -tlnp 2>/dev/null | grep -q ":$REGISTRY_PORT "; then
        print_success "Порт Registry $REGISTRY_PORT открыт"
    else
        print_error "Порт Registry $REGISTRY_PORT не открыт"
        return 1
    fi
    
    return 0
}

# Проверка API Docker Registry
check_api() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка API Docker Registry"
        return 0
    fi
    
    # Проверка API v2
    local http_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$REGISTRY_PORT/v2/" 2>/dev/null)
    
    if [[ "$http_code" -lt 500 ]]; then
        print_success "API Docker Registry v2 доступен (HTTP код: $http_code)"
    else
        print_error "API Docker Registry v2 недоступен (HTTP код: $http_code)"
        return 1
    fi
    
    # Проверка каталога
    local catalog_response=$(curl -s "http://localhost:$REGISTRY_PORT/v2/_catalog" 2>/dev/null)
    if [[ -n "$catalog_response" ]]; then
        print_success "Каталог Docker Registry доступен"
    else
        print_warning "Каталог Docker Registry недоступен"
    fi
    
    rm -f /tmp/registry_api.txt
    return 0
}



# Проверка директорий
check_directories() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка директорий Docker Registry"
        return 0
    fi
    
    local directories=(
        "$REGISTRY_BASE_DIR"
        "$REGISTRY_DATA_DIR"
        "$REGISTRY_CONFIG_DIR"
    )
    
    local all_exist=true
    
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            local permissions=$(stat -c "%a" "$dir" 2>/dev/null)
            local owner=$(stat -c "%U:%G" "$dir" 2>/dev/null)
            print_success "Директория $dir существует (права: $permissions, владелец: $owner)"
        else
            print_error "Директория $dir не существует"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Проверка Docker Compose файла
check_docker_compose() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка Docker Compose файла"
        return 0
    fi
    
    local compose_file="$REGISTRY_BASE_DIR/docker-compose.yml"
    local env_file="$REGISTRY_BASE_DIR/.env"
    
    if [[ -f "$compose_file" ]]; then
        print_success "Docker Compose файл существует: $compose_file"
    else
        print_error "Docker Compose файл не найден: $compose_file"
        return 1
    fi
    
    if [[ -f "$env_file" ]]; then
        print_success ".env файл существует: $env_file"
    else
        print_warning ".env файл не найден: $env_file"
    fi
    
    return 0
}

# Проверка конфигурационных файлов
check_config_files() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка конфигурационных файлов Docker Registry"
        return 0
    fi
    
    local config_files=(
        "$REGISTRY_CONFIG_DIR/config.yml"
    )
    
    local all_exist=true
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            local permissions=$(stat -c "%a" "$config_file" 2>/dev/null)
            local owner=$(stat -c "%U:%G" "$config_file" 2>/dev/null)
            print_success "Конфигурационный файл существует: $config_file (права: $permissions, владелец: $owner)"
        else
            print_error "Конфигурационный файл не найден: $config_file"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Проверка ресурсов
check_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка ресурсов Docker Registry"
        return 0
    fi
    
    # Проверка использования CPU и памяти для Registry
    local registry_stats=$(sudo docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$REGISTRY_CONTAINER_NAME" 2>/dev/null | tail -n +2)
    
    if [[ -n "$registry_stats" ]]; then
        local cpu_usage=$(echo "$registry_stats" | awk '{print $2}')
        local mem_usage=$(echo "$registry_stats" | awk '{print $3}')
        print_success "Registry использование ресурсов - CPU: $cpu_usage, Память: $mem_usage"
    else
        print_warning "Не удалось получить статистику использования ресурсов для Registry"
    fi
    
    # Проверка места на диске
    local data_size=$(sudo du -sh "$REGISTRY_DATA_DIR" 2>/dev/null | cut -f1)
    local config_size=$(sudo du -sh "$REGISTRY_CONFIG_DIR" 2>/dev/null | cut -f1)
    
    if [[ -n "$data_size" ]]; then
        print_success "Размер данных: $data_size"
    fi
    
    if [[ -n "$config_size" ]]; then
        print_success "Размер конфигурации: $config_size"
    fi
    
    return 0
}

# Вывод результатов в JSON формате
output_json() {
    local results=()
    
    # Проверки
    local checks=(
        "docker:$(check_docker && echo "true" || echo "false")"
        "container:$(check_container && echo "true" || echo "false")"
        "ports:$(check_ports && echo "true" || echo "false")"
        "api:$(check_api && echo "true" || echo "false")"
        "directories:$(check_directories && echo "true" || echo "false")"
        "docker_compose:$(check_docker_compose && echo "true" || echo "false")"
        "config_files:$(check_config_files && echo "true" || echo "false")"
    )
    
    echo "{"
    echo "  \"service\": \"docker-registry\","
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"checks\": {"
    
    local first=true
    for check in "${checks[@]}"; do
        IFS=':' read -r name result <<< "$check"
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    \"$name\": $result"
    done
    
    echo ""
    echo "  }"
    echo "}"
}

# Вывод результатов в текстовом формате
output_text() {
    print_header "=================================================================="
    print_header "=== Проверка состояния Docker Registry ==="
    print_header "=================================================================="
    echo
    
    print_section "Проверка Docker"
    check_docker
    echo
    
    print_section "Проверка контейнера"
    check_container
    echo
    
    print_section "Проверка портов"
    check_ports
    echo
    
    print_section "Проверка API"
    check_api
    echo
    
    print_section "Проверка директорий"
    check_directories
    echo
    
    print_section "Проверка Docker Compose"
    check_docker_compose
    echo
    
    print_section "Проверка конфигурации"
    check_config_files
    echo
    
    print_section "Проверка ресурсов"
    check_resources
    echo
    
    print_header "=================================================================="
    print_success "Проверка Docker Registry завершена"
    print_header "=================================================================="
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-registry-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки Docker Registry"
    log_info "Registry порт: $REGISTRY_PORT"
    log_info "Registry контейнер: $REGISTRY_CONTAINER_NAME"
    log_info "Базовая директория: $REGISTRY_BASE_DIR"
    log_info "Формат вывода: $FORMAT"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Вывод результатов
    case "$FORMAT" in
        json)
            output_json
            ;;
        text)
            output_text
            ;;
    esac
    
    log_info "Проверка Docker Registry завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
