#!/bin/bash
# =============================================================================
# Скрипт проверки состояния ArangoDB
# =============================================================================
# Назначение: Проверка состояния и работоспособности ArangoDB
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
# ARANGODB_HTTP_PORT, ARANGODB_HTTPS_PORT, ARANGODB_CONTAINER_NAME и другие
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
    --http-port PORT          HTTP порт (по умолчанию: из config/monq.conf)
    --https-port PORT         HTTPS порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --apps-dir PATH           Директория приложений (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --network NAME            Имя сети (по умолчанию: из config/monq.conf)
    --format FORMAT           Формат вывода (text, json) (по умолчанию: text)
    --dry-run                 Режим симуляции (без выполнения команд)
    --help                    Показать эту справку

Примеры:
    $0 --format json
    $0 --http-port 9529 --container-name my-arangodb

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --base-dir)
                ARANGODB_BASE_DIR="$2"
                ARANGODB_DATA_DIR="$2/data"
                ARANGODB_APPS_DIR="$2/apps"
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
            --network)
                ARANGODB_NETWORK="$2"
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
    
    if [[ ! "$ARANGODB_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $ARANGODB_HTTP_PORT -lt 1 ]] || [[ $ARANGODB_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $ARANGODB_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$ARANGODB_HTTPS_PORT" =~ ^[0-9]+$ ]] || [[ $ARANGODB_HTTPS_PORT -lt 1 ]] || [[ $ARANGODB_HTTPS_PORT -gt 65535 ]]; then
        log_error "Неверный HTTPS порт: $ARANGODB_HTTPS_PORT"
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

# Проверка контейнера ArangoDB
check_container() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка контейнера ArangoDB"
        return 0
    fi
    
    if ! sudo docker ps --filter "name=$ARANGODB_CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$ARANGODB_CONTAINER_NAME"; then
        print_error "Контейнер ArangoDB не запущен"
        return 1
    fi
    
    local container_status=$(sudo docker ps --filter "name=$ARANGODB_CONTAINER_NAME" --format "{{.Status}}")
    if echo "$container_status" | grep -q "Up"; then
        print_success "Контейнер ArangoDB запущен: $container_status"
    else
        print_error "Контейнер ArangoDB не активен: $container_status"
        return 1
    fi
    
    return 0
}

# Проверка портов
check_ports() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка портов ArangoDB"
        return 0
    fi
    
    # Проверка HTTP порта
    if sudo netstat -tlnp 2>/dev/null | grep -q ":$ARANGODB_HTTP_PORT "; then
        print_success "HTTP порт $ARANGODB_HTTP_PORT открыт"
    else
        print_error "HTTP порт $ARANGODB_HTTP_PORT не открыт"
        return 1
    fi
    
    # Проверка HTTPS порта (если используется)
    if [[ "$ARANGODB_HTTPS_PORT" != "8530" ]] || sudo netstat -tlnp 2>/dev/null | grep -q ":$ARANGODB_HTTPS_PORT "; then
        print_success "HTTPS порт $ARANGODB_HTTPS_PORT открыт"
    else
        print_warning "HTTPS порт $ARANGODB_HTTPS_PORT не используется"
    fi
    
    return 0
}

# Проверка API ArangoDB
check_api() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка API ArangoDB"
        return 0
    fi
    
    local api_url="http://localhost:$ARANGODB_HTTP_PORT/_api/version"
    local response=$(curl -s -w "%{http_code}" -o /tmp/arangodb_version.json "$api_url" 2>/dev/null)
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "200" ]]; then
        local version=$(cat /tmp/arangodb_version.json 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        print_success "API ArangoDB доступен, версия: $version"
        rm -f /tmp/arangodb_version.json
        return 0
    else
        print_error "API ArangoDB недоступен (HTTP код: $http_code)"
        rm -f /tmp/arangodb_version.json
        return 1
    fi
}

# Проверка директорий
check_directories() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка директорий ArangoDB"
        return 0
    fi
    
    local directories=(
        "$ARANGODB_BASE_DIR"
        "$ARANGODB_DATA_DIR"
        "$ARANGODB_APPS_DIR"
        "$ARANGODB_CONFIG_DIR"
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
    
    local compose_file="$ARANGODB_BASE_DIR/docker-compose.yml"
    local env_file="$ARANGODB_BASE_DIR/.env"
    
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

# Проверка конфигурационного файла
check_config_file() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка конфигурационного файла ArangoDB"
        return 0
    fi
    
    local config_file="$ARANGODB_CONFIG_DIR/arangod.conf"
    
    if [[ -f "$config_file" ]]; then
        local permissions=$(stat -c "%a" "$config_file" 2>/dev/null)
        local owner=$(stat -c "%U:%G" "$config_file" 2>/dev/null)
        print_success "Конфигурационный файл существует: $config_file (права: $permissions, владелец: $owner)"
        return 0
    else
        print_error "Конфигурационный файл не найден: $config_file"
        return 1
    fi
}



# Проверка ресурсов
check_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка ресурсов ArangoDB"
        return 0
    fi
    
    # Проверка использования CPU и памяти
    local stats=$(sudo docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$ARANGODB_CONTAINER_NAME" 2>/dev/null | tail -n +2)
    
    if [[ -n "$stats" ]]; then
        local cpu_usage=$(echo "$stats" | awk '{print $2}')
        local mem_usage=$(echo "$stats" | awk '{print $3}')
        print_success "Использование ресурсов - CPU: $cpu_usage, Память: $mem_usage"
    else
        print_warning "Не удалось получить статистику использования ресурсов"
    fi
    
    # Проверка места на диске
    local data_size=$(sudo du -sh "$ARANGODB_DATA_DIR" 2>/dev/null | cut -f1)
    local apps_size=$(sudo du -sh "$ARANGODB_APPS_DIR" 2>/dev/null | cut -f1)
    
    if [[ -n "$data_size" ]]; then
        print_success "Размер данных: $data_size"
    fi
    
    if [[ -n "$apps_size" ]]; then
        print_success "Размер приложений: $apps_size"
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
        "config_file:$(check_config_file && echo "true" || echo "false")"
    )
    
    echo "{"
    echo "  \"service\": \"arangodb\","
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
    print_header "=== Проверка состояния ArangoDB ==="
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
    check_config_file
    echo
    
    print_section "Проверка ресурсов"
    check_resources
    echo
    
    print_header "=================================================================="
    print_success "Проверка ArangoDB завершена"
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
    local log_file="$LOG_DIR/check-arangodb-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки ArangoDB"
    log_info "HTTP порт: $ARANGODB_HTTP_PORT"
    log_info "HTTPS порт: $ARANGODB_HTTPS_PORT"
    log_info "Контейнер: $ARANGODB_CONTAINER_NAME"
    log_info "Базовая директория: $ARANGODB_BASE_DIR"
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
    
    log_info "Проверка ArangoDB завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

