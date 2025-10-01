#!/bin/bash
# =============================================================================
# Скрипт проверки состояния VictoriaMetrics
# =============================================================================
# Назначение: Проверка состояния и работоспособности VictoriaMetrics
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
# VICTORIAMETRICS_HTTP_PORT, VICTORIAMETRICS_INGEST_PORT, VICTORIAMETRICS_CONTAINER_NAME и другие
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
    --ingest-port PORT        Ingest порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --network NAME            Имя сети (по умолчанию: из config/monq.conf)
    --format FORMAT           Формат вывода (text, json) (по умолчанию: text)
    --dry-run                 Режим симуляции (без выполнения команд)
    --help                    Показать эту справку

Примечание: Все настройки по умолчанию загружаются из файла config/monq.conf.
Для изменения настроек отредактируйте соответствующие переменные в monq.conf.

Примеры:
    $0 --format json
    $0 --http-port 9428 --container-name my-victoriametrics

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --network)
                VICTORIAMETRICS_NETWORK="$2"
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
    
    if [[ ! "$VICTORIAMETRICS_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $VICTORIAMETRICS_HTTP_PORT -lt 1 ]] || [[ $VICTORIAMETRICS_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $VICTORIAMETRICS_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$VICTORIAMETRICS_INGEST_PORT" =~ ^[0-9]+$ ]] || [[ $VICTORIAMETRICS_INGEST_PORT -lt 1 ]] || [[ $VICTORIAMETRICS_INGEST_PORT -gt 65535 ]]; then
        log_error "Неверный Ingest порт: $VICTORIAMETRICS_INGEST_PORT"
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

# Проверка контейнера VictoriaMetrics
check_container() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка контейнера VictoriaMetrics"
        return 0
    fi
    
    if ! sudo docker ps --filter "name=$VICTORIAMETRICS_CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$VICTORIAMETRICS_CONTAINER_NAME"; then
        print_error "Контейнер VictoriaMetrics не запущен"
        return 1
    fi
    
    local container_status=$(sudo docker ps --filter "name=$VICTORIAMETRICS_CONTAINER_NAME" --format "{{.Status}}")
    if echo "$container_status" | grep -q "Up"; then
        print_success "Контейнер VictoriaMetrics запущен: $container_status"
    else
        print_error "Контейнер VictoriaMetrics не активен: $container_status"
        return 1
    fi
    
    return 0
}

# Проверка портов
check_ports() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка портов VictoriaMetrics"
        return 0
    fi
    
    # Проверка HTTP порта
    if sudo netstat -tlnp 2>/dev/null | grep -q ":$VICTORIAMETRICS_HTTP_PORT "; then
        print_success "HTTP порт $VICTORIAMETRICS_HTTP_PORT открыт"
    else
        print_error "HTTP порт $VICTORIAMETRICS_HTTP_PORT не открыт"
        return 1
    fi
    
    # Проверка Ingest порта
    if sudo netstat -tlnp 2>/dev/null | grep -q ":$VICTORIAMETRICS_INGEST_PORT "; then
        print_success "Ingest порт $VICTORIAMETRICS_INGEST_PORT открыт"
    else
        print_error "Ingest порт $VICTORIAMETRICS_INGEST_PORT не открыт"
        return 1
    fi
    
    return 0
}

# Проверка API VictoriaMetrics
check_api() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка API VictoriaMetrics"
        return 0
    fi
    
    # Проверка health endpoint
    if curl -fsS "http://localhost:$VICTORIAMETRICS_HTTP_PORT/health" | grep -q 'OK'; then
        print_success "API VictoriaMetrics доступен (health)"
    else
        print_error "API VictoriaMetrics недоступен (health)"
        return 1
    fi
    
    # Проверка версии
    local version_response=$(curl -s "http://localhost:$VICTORIAMETRICS_HTTP_PORT/version" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        print_success "Версия VictoriaMetrics: $version_response"
    else
        print_warning "Не удалось получить версию VictoriaMetrics"
    fi
    
    # Проверка статуса
    local status_response=$(curl -s "http://localhost:$VICTORIAMETRICS_HTTP_PORT/status" 2>/dev/null)
    if [[ -n "$status_response" ]]; then
        print_success "Статус VictoriaMetrics получен"
    else
        print_warning "Не удалось получить статус VictoriaMetrics"
    fi
    
    return 0
}

# Проверка директорий
check_directories() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка директорий VictoriaMetrics"
        return 0
    fi
    
    local directories=(
        "$VICTORIAMETRICS_BASE_DIR"
        "$VICTORIAMETRICS_DATA_DIR"
        "$VICTORIAMETRICS_CONFIG_DIR"
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
    
    local compose_file="$VICTORIAMETRICS_BASE_DIR/docker-compose.yml"
    local env_file="$VICTORIAMETRICS_BASE_DIR/.env"
    
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
        print_info "[DRY-RUN] Проверка конфигурационных файлов VictoriaMetrics"
        return 0
    fi
    
    # VictoriaMetrics не требует специальных конфигурационных файлов
    # Конфигурация передается через переменные окружения в docker-compose.yml
    print_success "Конфигурация VictoriaMetrics передается через переменные окружения"
    
    return 0
}

# Проверка ресурсов
check_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка ресурсов VictoriaMetrics"
        return 0
    fi
    
    # Проверка использования CPU и памяти
    local stats=$(sudo docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$VICTORIAMETRICS_CONTAINER_NAME" 2>/dev/null | tail -n +2)
    
    if [[ -n "$stats" ]]; then
        local cpu_usage=$(echo "$stats" | awk '{print $2}')
        local mem_usage=$(echo "$stats" | awk '{print $3}')
        print_success "Использование ресурсов - CPU: $cpu_usage, Память: $mem_usage"
    else
        print_warning "Не удалось получить статистику использования ресурсов"
    fi
    
    # Проверка места на диске
    local data_size=$(sudo du -sh "$VICTORIAMETRICS_DATA_DIR" 2>/dev/null | cut -f1)
    
    if [[ -n "$data_size" ]]; then
        print_success "Размер данных: $data_size"
    fi
    
    return 0
}

# Проверка метрик
check_metrics() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка метрик VictoriaMetrics"
        return 0
    fi
    
    # Проверка доступности метрик
    local metrics_response=$(curl -s "http://localhost:$VICTORIAMETRICS_HTTP_PORT/metrics" 2>/dev/null)
    if [[ -n "$metrics_response" ]]; then
        print_success "Метрики VictoriaMetrics доступны"
        
        # Подсчет количества метрик
        local metrics_count=$(echo "$metrics_response" | grep -c "^[^#]" || echo "0")
        print_success "Количество метрик: $metrics_count"
    else
        print_warning "Метрики VictoriaMetrics недоступны"
    fi
    
    return 0
}

# Проверка ingest порта
check_ingest() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка ingest порта VictoriaMetrics"
        return 0
    fi
    
    # Попытка отправить тестовую метрику
    local test_metric="test_metric_check $(date +%s) $(date +%s)"
    if echo "$test_metric" | nc -w 1 localhost "$VICTORIAMETRICS_INGEST_PORT" >/dev/null 2>&1; then
        print_success "Ingest порт $VICTORIAMETRICS_INGEST_PORT работает"
    else
        print_warning "Не удалось отправить тестовую метрику через ingest порт"
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
        "metrics:$(check_metrics && echo "true" || echo "false")"
        "ingest:$(check_ingest && echo "true" || echo "false")"
    )
    
    echo "{"
    echo "  \"service\": \"victoriametrics\","
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
    print_header "=== Проверка состояния VictoriaMetrics ==="
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
    
    print_section "Проверка метрик"
    check_metrics
    echo
    
    print_section "Проверка ingest"
    check_ingest
    echo
    
    print_section "Проверка ресурсов"
    check_resources
    echo
    
    print_header "=================================================================="
    print_success "Проверка VictoriaMetrics завершена"
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
    local log_file="$LOG_DIR/check-victoriametrics-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки VictoriaMetrics"
    log_info "HTTP порт: $VICTORIAMETRICS_HTTP_PORT"
    log_info "Ingest порт: $VICTORIAMETRICS_INGEST_PORT"
    log_info "Контейнер: $VICTORIAMETRICS_CONTAINER_NAME"
    log_info "Базовая директория: $VICTORIAMETRICS_BASE_DIR"
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
    
    log_info "Проверка VictoriaMetrics завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
