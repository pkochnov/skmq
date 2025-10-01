#!/bin/bash
# =============================================================================
# Скрипт проверки состояния PostgreSQL
# =============================================================================
# Назначение: Проверка состояния и работоспособности PostgreSQL
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
# POSTGRESQL_PORT, POSTGRESQL_CONTAINER_NAME, POSTGRESQL_BASE_DIR и другие
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
    --port PORT                Порт PostgreSQL (по умолчанию: из config/monq.conf)
    --container-name NAME      Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH            Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH            Директория данных (по умолчанию: из config/monq.conf)

    --network NAME             Имя сети (по умолчанию: из config/monq.conf)
    --database DB              Имя базы данных (по умолчанию: из config/monq.conf)
    --format FORMAT            Формат вывода (text, json) (по умолчанию: text)
    --dry-run                  Режим симуляции (без выполнения команд)
    --help                     Показать эту справку

Примеры:
    $0 --format json
    $0 --port 5433 --container-name my-postgresql

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                POSTGRESQL_PORT="$2"
                shift 2
                ;;
            --container-name)
                POSTGRESQL_CONTAINER_NAME="$2"
                shift 2
                ;;
            --base-dir)
                POSTGRESQL_BASE_DIR="$2"
                POSTGRESQL_DATA_DIR="$2/data"
                shift 2
                ;;
            --data-dir)
                POSTGRESQL_DATA_DIR="$2"
                shift 2
                ;;
            --network)
                POSTGRESQL_NETWORK="$2"
                shift 2
                ;;
            --database)
                POSTGRESQL_DB="$2"
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
    
    if [[ ! "$POSTGRESQL_PORT" =~ ^[0-9]+$ ]] || [[ $POSTGRESQL_PORT -lt 1 ]] || [[ $POSTGRESQL_PORT -gt 65535 ]]; then
        log_error "Неверный порт PostgreSQL: $POSTGRESQL_PORT"
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

# Проверка контейнера PostgreSQL
check_container() {
    local container_status="unknown"
    local container_running=false
    local container_health="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка контейнера PostgreSQL"
        container_status="running"
        container_running=true
        container_health="healthy"
    else
        # Проверка существования контейнера
        if run_sudo docker ps -a --filter name=^${POSTGRESQL_CONTAINER_NAME}$ --format '{{.Status}}' | grep -q "Up"; then
            container_status="running"
            container_running=true
        elif run_sudo docker ps -a --filter name=^${POSTGRESQL_CONTAINER_NAME}$ --format '{{.Status}}' | grep -q "Exited"; then
            container_status="stopped"
            container_running=false
        else
            container_status="not_found"
            container_running=false
        fi
        
        # Проверка health check
        if [[ "$container_running" == "true" ]]; then
            local health_status=$(run_sudo docker inspect --format='{{.State.Health.Status}}' ${POSTGRESQL_CONTAINER_NAME} 2>/dev/null || echo "no_health_check")
            if [[ "$health_status" == "healthy" ]]; then
                container_health="healthy"
            elif [[ "$health_status" == "unhealthy" ]]; then
                container_health="unhealthy"
            else
                container_health="no_health_check"
            fi
        fi
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "container": {
    "name": "${POSTGRESQL_CONTAINER_NAME}",
    "status": "${container_status}",
    "running": ${container_running},
    "health": "${container_health}"
  }
}
EOF
    else
        print_header "=== Состояние контейнера PostgreSQL ==="
        print_info "Имя контейнера: $POSTGRESQL_CONTAINER_NAME"
        print_info "Статус: $container_status"
        print_info "Запущен: $container_running"
        print_info "Состояние здоровья: $container_health"
        echo
    fi
    
    return 0
}

# Проверка портов
check_ports() {
    local port_open=false
    local port_listening=false
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка портов PostgreSQL"
        port_open=true
        port_listening=true
    else
        # Проверка доступности порта
        if nc -z 127.0.0.1 "$POSTGRESQL_PORT" 2>/dev/null; then
            port_open=true
        fi
        
        # Проверка прослушивания порта
        if netstat -tlnp 2>/dev/null | grep -q ":$POSTGRESQL_PORT "; then
            port_listening=true
        fi
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "ports": {
    "postgresql": {
      "port": ${POSTGRESQL_PORT},
      "open": ${port_open},
      "listening": ${port_listening}
    }
  }
}
EOF
    else
        print_header "=== Проверка портов ==="
        print_info "PostgreSQL порт ($POSTGRESQL_PORT):"
        if [[ "$port_open" == "true" ]]; then
            print_success "  ✓ Порт открыт и доступен"
        else
            print_error "  ✗ Порт недоступен"
        fi
        
        if [[ "$port_listening" == "true" ]]; then
            print_success "  ✓ Порт прослушивается"
        else
            print_error "  ✗ Порт не прослушивается"
        fi
        echo
    fi
    
    return 0
}

# Проверка подключения к базе данных
check_database_connection() {
    local connection_ok=false
    local database_exists=false
    local user_exists=false
    local version="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка подключения к базе данных"
        connection_ok=true
        database_exists=true
        user_exists=true
        version="PostgreSQL 16.1"
    else
        # Проверка подключения к PostgreSQL
        if run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml exec -T postgresql pg_isready -U postgres -d ${POSTGRESQL_DB} &> /dev/null; then
            connection_ok=true
            
            # Получение версии PostgreSQL
            version=$(run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml exec -T postgresql psql -U postgres -d ${POSTGRESQL_DB} -t -c 'SELECT version();' 2>/dev/null | head -1 | xargs)
            
            # Проверка существования базы данных
            if run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml exec -T postgresql psql -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "${POSTGRESQL_DB}"; then
                database_exists=true
            fi
        fi
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
      "database": {
      "connection": ${connection_ok},
      "database_exists": ${database_exists},
      "version": "${version}",
      "database_name": "${POSTGRESQL_DB}"
    }
}
EOF
    else
        print_header "=== Проверка базы данных ==="
        print_info "Подключение к PostgreSQL:"
        if [[ "$connection_ok" == "true" ]]; then
            print_success "  ✓ Подключение успешно"
        else
            print_error "  ✗ Не удалось подключиться"
        fi
        
        print_info "Версия PostgreSQL: $version"
        print_info "База данных '$POSTGRESQL_DB':"
        if [[ "$database_exists" == "true" ]]; then
            print_success "  ✓ База данных существует"
        else
            print_error "  ✗ База данных не найдена"
        fi
        echo
    fi
    
    return 0
}

# Проверка файловой системы
check_filesystem() {
    local base_dir_exists=false
    local data_dir_exists=false
    local compose_file_exists=false
    local data_size="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка файловой системы"
        base_dir_exists=true
        data_dir_exists=true
        compose_file_exists=true
        data_size="1.2GB"
    else
        # Проверка директорий
        if [[ -d "$POSTGRESQL_BASE_DIR" ]]; then
            base_dir_exists=true
        fi
        
        if [[ -d "$POSTGRESQL_DATA_DIR" ]]; then
            data_dir_exists=true
            data_size=$(du -sh "$POSTGRESQL_DATA_DIR" 2>/dev/null | cut -f1)
        fi
        
        if [[ -f "$POSTGRESQL_BASE_DIR/docker-compose.yml" ]]; then
            compose_file_exists=true
        fi
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "filesystem": {
    "base_dir": "${POSTGRESQL_BASE_DIR}",
    "base_dir_exists": ${base_dir_exists},
    "data_dir": "${POSTGRESQL_DATA_DIR}",
    "data_dir_exists": ${data_dir_exists},
    "data_size": "${data_size}",
    "compose_file_exists": ${compose_file_exists}
  }
}
EOF
    else
        print_header "=== Проверка файловой системы ==="
        print_info "Базовая директория ($POSTGRESQL_BASE_DIR):"
        if [[ "$base_dir_exists" == "true" ]]; then
            print_success "  ✓ Директория существует"
        else
            print_error "  ✗ Директория не найдена"
        fi
        
        print_info "Директория данных ($POSTGRESQL_DATA_DIR):"
        if [[ "$data_dir_exists" == "true" ]]; then
            print_success "  ✓ Директория существует"
            print_info "  Размер данных: $data_size"
        else
            print_error "  ✗ Директория не найдена"
        fi
        

        
        print_info "Docker Compose файл:"
        if [[ "$compose_file_exists" == "true" ]]; then
            print_success "  ✓ Файл docker-compose.yml существует"
        else
            print_error "  ✗ Файл docker-compose.yml не найден"
        fi
        echo
    fi
    
    return 0
}

# Проверка логов
check_logs() {
    local log_entries=0
    local error_count=0
    local recent_errors=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Проверка логов PostgreSQL"
        log_entries=150
        error_count=0
    else
        # Получение количества записей в логах
        if run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml logs --tail=100 postgresql &> /dev/null; then
            log_entries=$(run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml logs --tail=100 postgresql 2>/dev/null | wc -l)
            error_count=$(run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml logs --tail=100 postgresql 2>/dev/null | grep -i "error\|fatal\|panic" | wc -l)
            recent_errors=$(run_docker_compose -f ${POSTGRESQL_BASE_DIR}/docker-compose.yml logs --tail=10 postgresql 2>/dev/null | grep -i "error\|fatal\|panic" | head -3)
        fi
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        cat << EOF
{
  "logs": {
    "entries_count": ${log_entries},
    "error_count": ${error_count},
    "recent_errors": "${recent_errors}"
  }
}
EOF
    else
        print_header "=== Проверка логов ==="
        print_info "Записей в логах (последние 100): $log_entries"
        print_info "Ошибок в логах: $error_count"
        
        if [[ $error_count -gt 0 ]]; then
            print_warning "Обнаружены ошибки в логах:"
            echo "$recent_errors" | while read -r line; do
                if [[ -n "$line" ]]; then
                    print_warning "  $line"
                fi
            done
        else
            print_success "  ✓ Критических ошибок не обнаружено"
        fi
        echo
    fi
    
    return 0
}



# Основная функция
main() {
    show_header "Проверка состояния PostgreSQL"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    log_info "Начало проверки состояния PostgreSQL"
    log_info "Порт: $POSTGRESQL_PORT"
    log_info "Контейнер: $POSTGRESQL_CONTAINER_NAME"
    log_info "База данных: $POSTGRESQL_DB"

    log_info "Формат вывода: $FORMAT"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Проверка Docker
    if ! check_docker; then
        log_error "Docker недоступен"
        exit 1
    fi
    
    # Выполнение проверок
    check_container
    check_ports
    check_database_connection
    check_filesystem
    check_logs
    
    print_success "Проверка состояния PostgreSQL завершена"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
