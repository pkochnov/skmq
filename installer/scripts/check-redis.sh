#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Redis
# =============================================================================
# Назначение: Проверка состояния и работоспособности Redis
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
# REDIS_PORT, REDIS_CONTAINER_NAME, REDIS_BASE_DIR и другие
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
    --port PORT                Порт Redis (по умолчанию: из config/monq.conf)
    --container-name NAME      Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH            Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH            Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH          Директория конфигурации (по умолчанию: из config/monq.conf)
    --network NAME             Имя сети (по умолчанию: из config/monq.conf)
    --password PASS            Пароль Redis (по умолчанию: из config/monq.conf)
    --format FORMAT            Формат вывода (text, json) (по умолчанию: text)
    --dry-run                  Режим симуляции (без выполнения команд)
    --help                     Показать эту справку

Примеры:
    $0 --format json
    $0 --port 6380 --container-name my-redis

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                REDIS_PORT="$2"
                shift 2
                ;;
            --container-name)
                REDIS_CONTAINER_NAME="$2"
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
            --network)
                REDIS_NETWORK="$2"
                shift 2
                ;;
            --password)
                REDIS_PASSWORD="$2"
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
    
    if [[ ! "$REDIS_PORT" =~ ^[0-9]+$ ]] || [[ $REDIS_PORT -lt 1 ]] || [[ $REDIS_PORT -gt 65535 ]]; then
        log_error "Неверный порт Redis: $REDIS_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
        log_error "Неверный формат вывода: $FORMAT (допустимо: text, json)"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Проверка контейнера Redis
check_container() {
    local container_status="unknown"
    local container_running=false
    local container_health="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка контейнера Redis"
        container_status="running"
        container_running=true
        container_health="healthy"
    else
        # Проверка существования контейнера
        if run_sudo docker ps -a --filter name=^${REDIS_CONTAINER_NAME}$ --format '{{.Status}}' | grep -q "Up"; then
            container_status="running"
            container_running=true
        elif run_sudo docker ps -a --filter name=^${REDIS_CONTAINER_NAME}$ --format '{{.Status}}' | grep -q "Exited"; then
            container_status="stopped"
            container_running=false
        else
            container_status="not_found"
            container_running=false
        fi
        
        # Проверка health check
        if [[ "$container_running" == "true" ]]; then
            local health_status=$(run_sudo docker inspect --format='{{.State.Health.Status}}' "$REDIS_CONTAINER_NAME" 2>/dev/null || echo "no_healthcheck")
            if [[ "$health_status" == "healthy" ]]; then
                container_health="healthy"
            elif [[ "$health_status" == "unhealthy" ]]; then
                container_health="unhealthy"
            elif [[ "$health_status" == "starting" ]]; then
                container_health="starting"
            else
                container_health="no_healthcheck"
            fi
        fi
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "container": {
    "name": "$REDIS_CONTAINER_NAME",
    "status": "$container_status",
    "running": $container_running,
    "health": "$container_health"
  }
}
EOF
    else
        print_section "Состояние контейнера Redis"
        echo -e "  ${GREEN}Имя контейнера:${NC} $REDIS_CONTAINER_NAME"
        echo -e "  ${GREEN}Статус:${NC} $container_status"
        echo -e "  ${GREEN}Запущен:${NC} $container_running"
        echo -e "  ${GREEN}Здоровье:${NC} $container_health"
    fi
    
    # Возврат кода ошибки если контейнер не запущен
    if [[ "$container_running" != "true" ]]; then
        return 1
    fi
    
    return 0
}

# Проверка порта Redis
check_port() {
    local port_open=false
    local port_listening=false
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка порта Redis"
        port_open=true
        port_listening=true
    else
        # Проверка доступности порта
        if check_port_common "localhost" "$REDIS_PORT"; then
            port_open=true
        fi
        
        # Проверка прослушивания порта
        if run_sudo netstat -tlnp 2>/dev/null | grep -q ":$REDIS_PORT "; then
            port_listening=true
        elif run_sudo ss -tlnp 2>/dev/null | grep -q ":$REDIS_PORT "; then
            port_listening=true
        fi
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "port": {
    "number": $REDIS_PORT,
    "open": $port_open,
    "listening": $port_listening
  }
}
EOF
    else
        print_section "Состояние порта Redis"
        echo -e "  ${GREEN}Порт:${NC} $REDIS_PORT"
        echo -e "  ${GREEN}Открыт:${NC} $port_open"
        echo -e "  ${GREEN}Прослушивается:${NC} $port_listening"
    fi
    
    # Возврат кода ошибки если порт недоступен
    if [[ "$port_open" != "true" ]]; then
        return 1
    fi
    
    return 0
}

# Проверка подключения к Redis
check_connection() {
    local connection_ok=false
    local redis_version="unknown"
    local redis_uptime="unknown"
    local redis_memory="unknown"
    local redis_connected_clients="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка подключения к Redis"
        connection_ok=true
        redis_version="7.2.5"
        redis_uptime="12345"
        redis_memory="1.2M"
        redis_connected_clients="1"
    else
        # Проверка подключения через redis-cli
        if run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD ping" | grep -q "PONG"; then
            connection_ok=true
            
            # Получение информации о Redis
            redis_version=$(run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD info server" | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
            redis_uptime=$(run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD info server" | grep "uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
            redis_memory=$(run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD info memory" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
            redis_connected_clients=$(run_docker_exec "$REDIS_CONTAINER_NAME" "redis-cli -a $REDIS_PASSWORD info clients" | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
        fi
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "connection": {
    "status": "$connection_ok",
    "version": "$redis_version",
    "uptime_seconds": "$redis_uptime",
    "memory_used": "$redis_memory",
    "connected_clients": "$redis_connected_clients"
  }
}
EOF
    else
        print_section "Подключение к Redis"
        echo -e "  ${GREEN}Статус подключения:${NC} $connection_ok"
        echo -e "  ${GREEN}Версия Redis:${NC} $redis_version"
        echo -e "  ${GREEN}Время работы (сек):${NC} $redis_uptime"
        echo -e "  ${GREEN}Использование памяти:${NC} $redis_memory"
        echo -e "  ${GREEN}Подключенные клиенты:${NC} $redis_connected_clients"
    fi
    
    # Возврат кода ошибки если подключение не удалось
    if [[ "$connection_ok" != "true" ]]; then
        return 1
    fi
    
    return 0
}

# Проверка директорий
check_directories() {
    local base_dir_exists=false
    local data_dir_exists=false
    local config_dir_exists=false
    local base_dir_size="unknown"
    local data_dir_size="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка директорий Redis"
        base_dir_exists=true
        data_dir_exists=true
        config_dir_exists=true
        base_dir_size="1.2G"
        data_dir_size="800M"
    else
        # Проверка существования директорий
        if run_sudo test -d "$REDIS_BASE_DIR"; then
            base_dir_exists=true
            base_dir_size=$(run_sudo du -sh "$REDIS_BASE_DIR" 2>/dev/null | cut -f1)
        fi
        
        if run_sudo test -d "$REDIS_DATA_DIR"; then
            data_dir_exists=true
            data_dir_size=$(run_sudo du -sh "$REDIS_DATA_DIR" 2>/dev/null | cut -f1)
        fi
        
        if run_sudo test -d "$REDIS_CONFIG_DIR"; then
            config_dir_exists=true
        fi
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "directories": {
    "base_dir": {
      "path": "$REDIS_BASE_DIR",
      "exists": $base_dir_exists,
      "size": "$base_dir_size"
    },
    "data_dir": {
      "path": "$REDIS_DATA_DIR",
      "exists": $data_dir_exists,
      "size": "$data_dir_size"
    },
    "config_dir": {
      "path": "$REDIS_CONFIG_DIR",
      "exists": $config_dir_exists
    }
  }
}
EOF
    else
        print_section "Директории Redis"
        echo -e "  ${GREEN}Базовая директория:${NC} $REDIS_BASE_DIR ($base_dir_exists, $base_dir_size)"
        echo -e "  ${GREEN}Директория данных:${NC} $REDIS_DATA_DIR ($data_dir_exists, $data_dir_size)"
        echo -e "  ${GREEN}Директория конфигурации:${NC} $REDIS_CONFIG_DIR ($config_dir_exists)"
    fi
    
    # Возврат кода ошибки если базовые директории не существуют
    if [[ "$base_dir_exists" != "true" ]]; then
        return 1
    fi
    
    return 0
}

# Проверка Docker Compose файла
check_docker_compose() {
    local compose_file_exists=false
    local compose_file_valid=false
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка Docker Compose файла"
        compose_file_exists=true
        compose_file_valid=true
    else
        local compose_file="$REDIS_BASE_DIR/docker-compose.yml"
        
        # Проверка существования файла
        if run_sudo test -f "$compose_file"; then
            compose_file_exists=true
            
            # Проверка валидности файла
            if run_sudo docker compose -f "$compose_file" config >/dev/null 2>&1; then
                compose_file_valid=true
            fi
        fi
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "docker_compose": {
    "file_exists": $compose_file_exists,
    "file_valid": $compose_file_valid
  }
}
EOF
    else
        print_section "Docker Compose файл"
        echo -e "  ${GREEN}Файл существует:${NC} $compose_file_exists"
        echo -e "  ${GREEN}Файл валиден:${NC} $compose_file_valid"
    fi
    
    # Возврат кода ошибки если файл не существует или невалиден
    if [[ "$compose_file_exists" != "true" || "$compose_file_valid" != "true" ]]; then
        return 1
    fi
    
    return 0
}



# Общая проверка состояния
check_overall_status() {
    local overall_status="unknown"
    local issues_count=0
    
    # Подсчет проблем
    if ! check_container >/dev/null 2>&1; then
        issues_count=$((issues_count + 1))
    fi
    
    if ! check_port >/dev/null 2>&1; then
        issues_count=$((issues_count + 1))
    fi
    
    if ! check_connection >/dev/null 2>&1; then
        issues_count=$((issues_count + 1))
    fi
    
    if ! check_directories >/dev/null 2>&1; then
        issues_count=$((issues_count + 1))
    fi
    
    if ! check_docker_compose >/dev/null 2>&1; then
        issues_count=$((issues_count + 1))
    fi
    
    # Определение общего статуса
    if [[ $issues_count -eq 0 ]]; then
        overall_status="healthy"
    elif [[ $issues_count -le 2 ]]; then
        overall_status="warning"
    else
        overall_status="critical"
    fi
    
    # Вывод результата
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "overall_status": {
    "status": "$overall_status",
    "issues_count": $issues_count,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF
    else
        print_section "Общее состояние Redis"
        echo -e "  ${GREEN}Статус:${NC} $overall_status"
        echo -e "  ${GREEN}Количество проблем:${NC} $issues_count"
        echo -e "  ${GREEN}Время проверки:${NC} $(date)"
    fi
    
    # Возврат кода ошибки в зависимости от статуса
    case "$overall_status" in
        "healthy") return 0 ;;
        "warning") return 1 ;;
        "critical") return 2 ;;
        *) return 3 ;;
    esac
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Проверка состояния Redis"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-redis-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки состояния Redis"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Порт: $REDIS_PORT"
    log_info "Контейнер: $REDIS_CONTAINER_NAME"
    log_info "Базовая директория: $REDIS_BASE_DIR"
    log_info "Формат вывода: $FORMAT"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение проверок
    local checks=(
        "check_container"
        "check_port"
        "check_connection"
        "check_directories"
        "check_docker_compose"
        "check_overall_status"
    )
    
    local total_checks=${#checks[@]}
    local current_check=0
    local exit_code=0
    
    for check in "${checks[@]}"; do
        current_check=$((current_check + 1))
        show_progress $current_check $total_checks "Выполнение: $check"
        
        if ! $check; then
            local check_exit_code=$?
            if [[ $check_exit_code -gt $exit_code ]]; then
                exit_code=$check_exit_code
            fi
        fi
    done
    
    log_info "Проверка состояния Redis завершена"
    log_info "Лог файл: $log_file"
    
    exit $exit_code
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
