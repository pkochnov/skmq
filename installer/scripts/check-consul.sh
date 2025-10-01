#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Consul
# =============================================================================
# Назначение: Проверка состояния и работоспособности Consul
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
# CONSUL_HTTP_PORT, CONSUL_HTTPS_PORT, CONSUL_CONTAINER_NAME и другие
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
    --dns-port PORT           DNS порт (по умолчанию: из config/monq.conf)
    --server-port PORT        Server порт (по умолчанию: из config/monq.conf)
    --serf-lan-port PORT      Serf LAN порт (по умолчанию: из config/monq.conf)
    --serf-wan-port PORT      Serf WAN порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --logs-dir PATH           Директория логов (по умолчанию: из config/monq.conf)
    --network NAME            Имя сети (по умолчанию: из config/monq.conf)
    --datacenter NAME         Имя датацентра (по умолчанию: из config/monq.conf)
    --node-name NAME          Имя узла (по умолчанию: из config/monq.conf)
    --format FORMAT           Формат вывода (text, json) (по умолчанию: text)
    --dry-run                 Режим симуляции (без выполнения команд)
    --help                    Показать эту справку

Примечание: Все настройки по умолчанию загружаются из файла config/monq.conf.
Для изменения настроек отредактируйте соответствующие переменные в monq.conf.

Примеры:
    $0 --format json
    $0 --http-port 8501 --container-name my-consul

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --http-port)
                CONSUL_HTTP_PORT="$2"
                shift 2
                ;;
            --https-port)
                CONSUL_HTTPS_PORT="$2"
                shift 2
                ;;
            --dns-port)
                CONSUL_DNS_PORT="$2"
                shift 2
                ;;
            --server-port)
                CONSUL_SERVER_PORT="$2"
                shift 2
                ;;
            --serf-lan-port)
                CONSUL_SERF_LAN_PORT="$2"
                shift 2
                ;;
            --serf-wan-port)
                CONSUL_SERF_WAN_PORT="$2"
                shift 2
                ;;
            --container-name)
                CONSUL_CONTAINER_NAME="$2"
                shift 2
                ;;
            --base-dir)
                CONSUL_BASE_DIR="$2"
                CONSUL_DATA_DIR="$2/data"
                CONSUL_CONFIG_DIR="$2/config"
                CONSUL_LOGS_DIR="$2/logs"
                shift 2
                ;;
            --data-dir)
                CONSUL_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                CONSUL_CONFIG_DIR="$2"
                shift 2
                ;;
            --logs-dir)
                CONSUL_LOGS_DIR="$2"
                shift 2
                ;;
            --network)
                CONSUL_NETWORK="$2"
                shift 2
                ;;
            --datacenter)
                CONSUL_DATACENTER="$2"
                shift 2
                ;;
            --node-name)
                CONSUL_NODE_NAME="$2"
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
    
    if [[ ! "$CONSUL_HTTP_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_HTTP_PORT -lt 1 ]] || [[ $CONSUL_HTTP_PORT -gt 65535 ]]; then
        log_error "Неверный HTTP порт: $CONSUL_HTTP_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CONSUL_HTTPS_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_HTTPS_PORT -lt 1 ]] || [[ $CONSUL_HTTPS_PORT -gt 65535 ]]; then
        log_error "Неверный HTTPS порт: $CONSUL_HTTPS_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CONSUL_DNS_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_DNS_PORT -lt 1 ]] || [[ $CONSUL_DNS_PORT -gt 65535 ]]; then
        log_error "Неверный DNS порт: $CONSUL_DNS_PORT"
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

# Проверка контейнера Consul
check_container() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка контейнера Consul"
        return 0
    fi
    
    if ! run_sudo docker ps --filter "name=$CONSUL_CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$CONSUL_CONTAINER_NAME"; then
        print_error "Контейнер Consul не запущен"
        return 1
    fi
    
    local container_status=$(run_sudo docker ps --filter "name=$CONSUL_CONTAINER_NAME" --format "{{.Status}}")
    if echo "$container_status" | grep -q "Up"; then
        print_success "Контейнер Consul запущен: $container_status"
    else
        print_error "Контейнер Consul не активен: $container_status"
        return 1
    fi
    
    return 0
}

# Проверка портов
check_ports() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка портов Consul"
        return 0
    fi
    
    local ports=(
        "$CONSUL_HTTP_PORT:HTTP"
        "$CONSUL_HTTPS_PORT:HTTPS"
        "$CONSUL_DNS_PORT:DNS"
        "$CONSUL_SERVER_PORT:Server"
        "$CONSUL_SERF_LAN_PORT:Serf LAN"
        "$CONSUL_SERF_WAN_PORT:Serf WAN"
    )
    
    local all_open=true
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port name <<< "$port_info"
        if run_sudo netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            print_success "$name порт $port открыт"
        else
            print_error "$name порт $port не открыт"
            all_open=false
        fi
    done
    
    if [[ "$all_open" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Проверка API Consul
check_api() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка API Consul"
        return 0
    fi
    
    # Проверка статуса лидера
    local leader_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" 2>/dev/null)
    if [[ -n "$leader_response" && "$leader_response" != "null" ]]; then
        print_success "API Consul доступен (лидер: $leader_response)"
    else
        print_error "API Consul недоступен (статус лидера)"
        return 1
    fi
    
    # Проверка health check
    local health_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/status/checks" 2>/dev/null)
    if [[ -n "$health_response" && "$health_response" != "null" ]]; then
        print_success "Health check API доступен"
    else
        print_warning "Health check API недоступен"
    fi
    
    # Проверка членов кластера
    local members_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/agent/members" 2>/dev/null)
    if [[ -n "$members_response" && "$members_response" != "null" ]]; then
        local member_count=$(echo "$members_response" | jq '. | length' 2>/dev/null || echo "0")
        print_success "Количество членов кластера: $member_count"
    else
        print_warning "Не удалось получить список членов кластера"
    fi
    
    # Проверка версии Consul
    local version_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        print_success "Consul API работает корректно"
    else
        print_warning "Не удалось проверить версию Consul"
    fi
    
    return 0
}

# Проверка директорий
check_directories() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка директорий Consul"
        return 0
    fi
    
    local directories=(
        "$CONSUL_BASE_DIR"
        "$CONSUL_DATA_DIR"
        "$CONSUL_CONFIG_DIR"
        "$CONSUL_LOGS_DIR"
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
    
    local compose_file="$CONSUL_BASE_DIR/docker-compose.yml"
    local env_file="$CONSUL_BASE_DIR/.env"
    
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
    
    # Проверяем, что конфигурация передается через переменные окружения
    if grep -q "CONSUL_DATACENTER" "$compose_file" 2>/dev/null; then
        print_success "Конфигурация передается через переменные окружения"
    else
        print_warning "Переменные окружения Consul не найдены в docker-compose.yml"
    fi
    
    return 0
}

# Проверка сервисов
check_services() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка сервисов Consul"
        return 0
    fi
    
    # Получение списка сервисов
    local services_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/catalog/services" 2>/dev/null)
    if [[ -n "$services_response" && "$services_response" != "null" ]]; then
        local service_count=$(echo "$services_response" | jq 'keys | length' 2>/dev/null || echo "0")
        print_success "Количество зарегистрированных сервисов: $service_count"
        
        if [[ $service_count -gt 0 ]]; then
            print_info "Зарегистрированные сервисы:"
            echo "$services_response" | jq -r 'keys[]' 2>/dev/null | while read -r service; do
                echo "  - $service"
            done
        fi
    else
        print_warning "Не удалось получить список сервисов"
    fi
    
    return 0
}

# Проверка узлов
check_nodes() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка узлов Consul"
        return 0
    fi
    
    # Получение списка узлов
    local nodes_response=$(curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/catalog/nodes" 2>/dev/null)
    if [[ -n "$nodes_response" && "$nodes_response" != "null" ]]; then
        local node_count=$(echo "$nodes_response" | jq '. | length' 2>/dev/null || echo "0")
        print_success "Количество узлов в кластере: $node_count"
        
        if [[ $node_count -gt 0 ]]; then
            print_info "Узлы кластера:"
            echo "$nodes_response" | jq -r '.[] | "  - \(.Node) (\(.Address))"' 2>/dev/null
        fi
    else
        print_warning "Не удалось получить список узлов"
    fi
    
    return 0
}

# Проверка ресурсов
check_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка ресурсов Consul"
        return 0
    fi
    
    # Проверка использования CPU и памяти
    local stats=$(run_sudo docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$CONSUL_CONTAINER_NAME" 2>/dev/null | tail -n +2)
    
    if [[ -n "$stats" ]]; then
        local cpu_usage=$(echo "$stats" | awk '{print $2}')
        local mem_usage=$(echo "$stats" | awk '{print $3}')
        print_success "Использование ресурсов - CPU: $cpu_usage, Память: $mem_usage"
    else
        print_warning "Не удалось получить статистику использования ресурсов"
    fi
    
    # Проверка места на диске
    local data_size=$(run_sudo du -sh "$CONSUL_DATA_DIR" 2>/dev/null | cut -f1)
    local logs_size=$(run_sudo du -sh "$CONSUL_LOGS_DIR" 2>/dev/null | cut -f1)
    
    if [[ -n "$data_size" ]]; then
        print_success "Размер данных: $data_size"
    fi
    
    if [[ -n "$logs_size" ]]; then
        print_success "Размер логов: $logs_size"
    fi
    
    return 0
}

# Проверка логов
check_logs() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка логов Consul"
        return 0
    fi
    
    local log_errors="0"
    local log_warnings="0"
    local last_log_entry="none"
    
    # Проверка логов на ошибки и предупреждения
    if run_sudo docker logs "$CONSUL_CONTAINER_NAME" 2>/dev/null | grep -i error >/dev/null; then
        log_errors=$(run_sudo docker logs "$CONSUL_CONTAINER_NAME" 2>/dev/null | grep -i error | wc -l)
    fi
    
    if run_sudo docker logs "$CONSUL_CONTAINER_NAME" 2>/dev/null | grep -i warning >/dev/null; then
        log_warnings=$(run_sudo docker logs "$CONSUL_CONTAINER_NAME" 2>/dev/null | grep -i warning | wc -l)
    fi
    
    # Последняя запись в логе
    last_log_entry=$(run_sudo docker logs --tail 1 "$CONSUL_CONTAINER_NAME" 2>/dev/null | head -1 || echo "none")
    
    print_success "Ошибки в логах: $log_errors"
    print_success "Предупреждения в логах: $log_warnings"
    print_success "Последняя запись: $last_log_entry"
    
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
        "services:$(check_services && echo "true" || echo "false")"
        "nodes:$(check_nodes && echo "true" || echo "false")"
    )
    
    echo "{"
    echo "  \"service\": \"consul\","
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
    print_header "=== Проверка состояния Consul ==="
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
    
    print_section "Проверка сервисов"
    check_services
    echo
    
    print_section "Проверка узлов"
    check_nodes
    echo
    
    print_section "Проверка ресурсов"
    check_resources
    echo
    
    print_section "Проверка логов"
    check_logs
    echo
    
    print_header "=================================================================="
    print_success "Проверка Consul завершена"
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
    local log_file="$LOG_DIR/check-consul-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки Consul"
    log_info "HTTP порт: $CONSUL_HTTP_PORT"
    log_info "HTTPS порт: $CONSUL_HTTPS_PORT"
    log_info "DNS порт: $CONSUL_DNS_PORT"
    log_info "Контейнер: $CONSUL_CONTAINER_NAME"
    log_info "Базовая директория: $CONSUL_BASE_DIR"
    log_info "Датацентр: $CONSUL_DATACENTER"
    log_info "Узел: $CONSUL_NODE_NAME"
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
    
    log_info "Проверка Consul завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
