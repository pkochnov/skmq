#!/bin/bash
# =============================================================================
# Скрипт проверки состояния RabbitMQ
# =============================================================================
# Назначение: Проверка состояния и работоспособности RabbitMQ
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
# RABBITMQ_AMQP_PORT, RABBITMQ_MANAGEMENT_PORT, RABBITMQ_CONTAINER_NAME и другие
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
    --amqp-port PORT           AMQP порт (по умолчанию: из config/monq.conf)
    --management-port PORT     Management порт (по умолчанию: из config/monq.conf)
    --container-name NAME      Имя контейнера (по умолчанию: из config/monq.conf)
    --base-dir PATH            Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH            Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH          Директория конфигурации (по умолчанию: из config/monq.conf)
    --logs-dir PATH            Директория логов (по умолчанию: из config/monq.conf)
    --network NAME             Имя сети (по умолчанию: из config/monq.conf)
    --default-user USER        Пользователь по умолчанию (по умолчанию: из config/monq.conf)
    --default-vhost VHOST      Виртуальный хост по умолчанию (по умолчанию: из config/monq.conf)
    --format FORMAT            Формат вывода (text, json) (по умолчанию: text)
    --dry-run                  Режим симуляции (без выполнения команд)
    --help                     Показать эту справку

Примеры:
    $0 --format json
    $0 --amqp-port 5673 --management-port 15673
    $0 --container-name my-rabbitmq

Примечание: Все настройки по умолчанию загружаются из файла config/monq.conf.
Для изменения настроек отредактируйте соответствующие переменные в monq.conf.

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --amqp-port)
                RABBITMQ_AMQP_PORT="$2"
                shift 2
                ;;
            --management-port)
                RABBITMQ_MANAGEMENT_PORT="$2"
                shift 2
                ;;
            --container-name)
                RABBITMQ_CONTAINER_NAME="$2"
                shift 2
                ;;
            --base-dir)
                RABBITMQ_BASE_DIR="$2"
                RABBITMQ_DATA_DIR="$2/data"
                RABBITMQ_CONFIG_DIR="$2/config"
                RABBITMQ_LOGS_DIR="$2/logs"
                shift 2
                ;;
            --data-dir)
                RABBITMQ_DATA_DIR="$2"
                shift 2
                ;;
            --config-dir)
                RABBITMQ_CONFIG_DIR="$2"
                shift 2
                ;;
            --logs-dir)
                RABBITMQ_LOGS_DIR="$2"
                shift 2
                ;;
            --network)
                RABBITMQ_NETWORK="$2"
                shift 2
                ;;
            --default-user)
                RABBITMQ_DEFAULT_USER="$2"
                shift 2
                ;;
            --default-vhost)
                RABBITMQ_DEFAULT_VHOST="$2"
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
                log_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Валидация параметров
validate_parameters() {
    if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
        log_error "Некорректный формат вывода: $FORMAT. Используйте 'text' или 'json'"
        exit 1
    fi
}

# Проверка статуса контейнера
check_container_status() {
    local status="unknown"
    local health="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        status="running"
        health="healthy"
    else
        # Проверка существования контейнера
        if ! run_sudo docker ps -a --filter name="$RABBITMQ_CONTAINER_NAME" | grep -q "$RABBITMQ_CONTAINER_NAME"; then
            status="not_found"
            health="unknown"
        else
            # Проверка статуса запуска
            if run_sudo docker ps --filter name="$RABBITMQ_CONTAINER_NAME" --filter status=running | grep -q "$RABBITMQ_CONTAINER_NAME"; then
                status="running"
                
                # Проверка health check
                local health_status
                health_status=$(run_sudo docker inspect --format='{{.State.Health.Status}}' "$RABBITMQ_CONTAINER_NAME" 2>/dev/null || echo "unknown")
                if [[ "$health_status" == "healthy" ]]; then
                    health="healthy"
                elif [[ "$health_status" == "unhealthy" ]]; then
                    health="unhealthy"
                else
                    health="checking"
                fi
            else
                status="stopped"
                health="unknown"
            fi
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"container_status\": \"$status\", \"health_status\": \"$health\"}"
    else
        echo "Статус контейнера: $status"
        echo "Статус здоровья: $health"
    fi
}

# Проверка портов
check_ports() {
    local amqp_status="closed"
    local management_status="closed"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        amqp_status="open"
        management_status="open"
    else
        # Проверка AMQP порта
        if nc -z localhost "$RABBITMQ_AMQP_PORT" 2>/dev/null; then
            amqp_status="open"
        fi
        
        # Проверка management порта
        if nc -z localhost "$RABBITMQ_MANAGEMENT_PORT" 2>/dev/null; then
            management_status="open"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"amqp_port\": {\"port\": $RABBITMQ_AMQP_PORT, \"status\": \"$amqp_status\"}, \"management_port\": {\"port\": $RABBITMQ_MANAGEMENT_PORT, \"status\": \"$management_status\"}}"
    else
        echo "AMQP порт ($RABBITMQ_AMQP_PORT): $amqp_status"
        echo "Management порт ($RABBITMQ_MANAGEMENT_PORT): $management_status"
    fi
}

# Проверка RabbitMQ сервиса
check_rabbitmq_service() {
    local service_status="unknown"
    local version="unknown"
    local uptime="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        service_status="running"
        version="$RABBITMQ_VERSION"
        uptime="1d 2h 3m"
    else
        # Проверка через rabbitmq-diagnostics
        if run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-diagnostics ping >/dev/null 2>&1; then
            service_status="running"
            
            # Получение версии
            version=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-diagnostics server_version 2>/dev/null | head -1 || echo "unknown")
            
            # Получение uptime
            uptime=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-diagnostics uptime 2>/dev/null | head -1 || echo "unknown")
        else
            service_status="stopped"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"service_status\": \"$service_status\", \"version\": \"$version\", \"uptime\": \"$uptime\"}"
    else
        echo "Статус сервиса: $service_status"
        echo "Версия: $version"
        echo "Время работы: $uptime"
    fi
}

# Проверка плагинов
check_plugins() {
    local management_plugin="disabled"
    local management_agent_plugin="disabled"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        management_plugin="enabled"
        management_agent_plugin="enabled"
    else
        # Проверка management plugin
        if run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-plugins list 2>/dev/null | grep -q "rabbitmq_management.*E"; then
            management_plugin="enabled"
        fi
        
        # Проверка management agent plugin
        if run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-plugins list 2>/dev/null | grep -q "rabbitmq_management_agent.*E"; then
            management_agent_plugin="enabled"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"management_plugin\": \"$management_plugin\", \"management_agent_plugin\": \"$management_agent_plugin\"}"
    else
        echo "Management plugin: $management_plugin"
        echo "Management agent plugin: $management_agent_plugin"
    fi
}

# Проверка виртуальных хостов
check_vhosts() {
    local vhosts="[]"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        vhosts="[\"$RABBITMQ_DEFAULT_VHOST\"]"
    else
        # Получение списка виртуальных хостов
        local vhost_list
        vhost_list=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmqctl list_vhosts 2>/dev/null | grep -v "Listing vhosts" | grep -v "name" | grep -v "^$" | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$vhost_list" ]]; then
            vhosts="[$vhost_list]"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"vhosts\": $vhosts}"
    else
        echo "Виртуальные хосты:"
        if [[ "$vhosts" != "[]" ]]; then
            echo "$vhosts" | jq -r '.[]' 2>/dev/null || echo "Ошибка парсинга JSON"
        else
            echo "  Не найдены"
        fi
    fi
}

# Проверка пользователей
check_users() {
    local users="[]"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        users="[{\"name\": \"$RABBITMQ_DEFAULT_USER\", \"tags\": \"administrator\"}]"
    else
        # Получение списка пользователей
        local user_list
        user_list=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmqctl list_users 2>/dev/null | grep -v "Listing users" | grep -v "user" | grep -v "^$" | awk '{print "{\"name\": \"" $1 "\", \"tags\": \"" $2 "\"}"}' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$user_list" ]]; then
            users="[$user_list]"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"users\": $users}"
    else
        echo "Пользователи:"
        if [[ "$users" != "[]" ]]; then
            echo "$users" | jq -r '.[] | "  \(.name) (\(.tags))"' 2>/dev/null || echo "Ошибка парсинга JSON"
        else
            echo "  Не найдены"
        fi
    fi
}

# Проверка очередей
check_queues() {
    local queue_count="0"
    local queues="[]"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        queue_count="0"
        queues="[]"
    else
        # Получение количества очередей
        queue_count=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmqctl list_queues 2>/dev/null | grep -v "Listing queues" | grep -v "name" | grep -v "^$" | wc -l)
        
        # Получение списка очередей
        local queue_list
        queue_list=$(run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmqctl list_queues name messages 2>/dev/null | grep -v "Listing queues" | grep -v "name" | grep -v "^$" | awk '{print "{\"name\": \"" $1 "\", \"messages\": " $2 "}"}' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$queue_list" ]]; then
            queues="[$queue_list]"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"queue_count\": $queue_count, \"queues\": $queues}"
    else
        echo "Количество очередей: $queue_count"
        if [[ "$queues" != "[]" ]]; then
            echo "Очереди:"
            echo "$queues" | jq -r '.[] | "  \(.name): \(.messages) сообщений"' 2>/dev/null || echo "Ошибка парсинга JSON"
        fi
    fi
}

# Проверка использования ресурсов
check_resources() {
    local memory_usage="unknown"
    local disk_usage="unknown"
    local cpu_usage="unknown"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        memory_usage="512MB"
        disk_usage="1.2GB"
        cpu_usage="5%"
    else
        # Получение информации о ресурсах контейнера
        local stats
        stats=$(run_sudo docker stats --no-stream --format 'table {{.MemUsage}}\t{{.CPUPerc}}' "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | tail -1)
        if [[ -n "$stats" ]]; then
            memory_usage=$(echo "$stats" | awk '{print $1}')
            cpu_usage=$(echo "$stats" | awk '{print $2}')
        fi
        
        # Получение использования диска
        if [[ -d "$RABBITMQ_DATA_DIR" ]]; then
            disk_usage=$(run_sudo du -sh "$RABBITMQ_DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "unknown")
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"memory_usage\": \"$memory_usage\", \"disk_usage\": \"$disk_usage\", \"cpu_usage\": \"$cpu_usage\"}"
    else
        echo "Использование памяти: $memory_usage"
        echo "Использование диска: $disk_usage"
        echo "Использование CPU: $cpu_usage"
    fi
}

# Проверка логов
check_logs() {
    local log_errors="0"
    local log_warnings="0"
    local last_log_entry="none"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_errors="0"
        log_warnings="0"
        last_log_entry="2024-01-01 12:00:00 INFO: RabbitMQ started"
    else
        # Проверка логов на ошибки и предупреждения
        if run_sudo docker logs "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | grep -i error >/dev/null; then
            log_errors=$(run_sudo docker logs "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | grep -i error | wc -l)
        fi
        
        if run_sudo docker logs "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | grep -i warning >/dev/null; then
            log_warnings=$(run_sudo docker logs "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | grep -i warning | wc -l)
        fi
        
        # Последняя запись в логе
        last_log_entry=$(run_sudo docker logs --tail 1 "$RABBITMQ_CONTAINER_NAME" 2>/dev/null | head -1 || echo "none")
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"log_errors\": $log_errors, \"log_warnings\": $log_warnings, \"last_log_entry\": \"$last_log_entry\"}"
    else
        echo "Ошибки в логах: $log_errors"
        echo "Предупреждения в логах: $log_warnings"
        echo "Последняя запись: $last_log_entry"
    fi
}

# Общая проверка состояния
check_overall_status() {
    local overall_status="unknown"
    local issues="[]"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        overall_status="healthy"
        issues="[]"
    else
        local issue_count=0
        local issue_list=""
        
        # Проверка контейнера
        if ! run_sudo docker ps --filter name="$RABBITMQ_CONTAINER_NAME" --filter status=running | grep -q "$RABBITMQ_CONTAINER_NAME"; then
            issue_count=$((issue_count + 1))
            issue_list="${issue_list}\"Контейнер не запущен\","
        fi
        
        # Проверка AMQP порта
        if ! nc -z localhost "$RABBITMQ_AMQP_PORT" 2>/dev/null; then
            issue_count=$((issue_count + 1))
            issue_list="${issue_list}\"AMQP порт недоступен\","
        fi
        
        # Проверка management порта
        if ! nc -z localhost "$RABBITMQ_MANAGEMENT_PORT" 2>/dev/null; then
            issue_count=$((issue_count + 1))
            issue_list="${issue_list}\"Management порт недоступен\","
        fi
        
        # Проверка health check
        if ! run_sudo docker exec "$RABBITMQ_CONTAINER_NAME" rabbitmq-diagnostics ping >/dev/null 2>&1; then
            issue_count=$((issue_count + 1))
            issue_list="${issue_list}\"Health check не прошел\","
        fi
        
        # Определение общего статуса
        if [[ $issue_count -eq 0 ]]; then
            overall_status="healthy"
        elif [[ $issue_count -le 2 ]]; then
            overall_status="warning"
        else
            overall_status="error"
        fi
        
        # Формирование списка проблем
        if [[ -n "$issue_list" ]]; then
            issue_list=$(echo "$issue_list" | sed 's/,$//')
            issues="[$issue_list]"
        fi
    fi
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "{\"overall_status\": \"$overall_status\", \"issues\": $issues}"
    else
        echo "Общий статус: $overall_status"
        if [[ "$issues" != "[]" ]]; then
            echo "Проблемы:"
            echo "$issues" | jq -r '.[] | "  - \(.)"' 2>/dev/null || echo "Ошибка парсинга JSON"
        fi
    fi
}

# Вывод информации в текстовом формате
show_text_output() {
    print_header "Проверка состояния RabbitMQ"
    echo
    
    print_section "Общий статус"
    check_overall_status
    echo
    
    print_section "Контейнер"
    check_container_status
    echo
    
    print_section "Порты"
    check_ports
    echo
    
    print_section "Сервис"
    check_rabbitmq_service
    echo
    
    print_section "Плагины"
    check_plugins
    echo
    
    print_section "Виртуальные хосты"
    check_vhosts
    echo
    
    print_section "Пользователи"
    check_users
    echo
    
    print_section "Очереди"
    check_queues
    echo
    
    print_section "Ресурсы"
    check_resources
    echo
    
    print_section "Логи"
    check_logs
    echo
}

# Вывод информации в JSON формате
show_json_output() {
    local output="{"
    output+="\"timestamp\": \"$(date -Iseconds)\","
    output+="\"overall_status\": $(check_overall_status | jq -c .),"
    output+="\"container\": $(check_container_status | jq -c .),"
    output+="\"ports\": $(check_ports | jq -c .),"
    output+="\"service\": $(check_rabbitmq_service | jq -c .),"
    output+="\"plugins\": $(check_plugins | jq -c .),"
    output+="\"vhosts\": $(check_vhosts | jq -c .),"
    output+="\"users\": $(check_users | jq -c .),"
    output+="\"queues\": $(check_queues | jq -c .),"
    output+="\"resources\": $(check_resources | jq -c .),"
    output+="\"logs\": $(check_logs | jq -c .)"
    output+="}"
    
    echo "$output" | jq .
}

# =============================================================================
# Главная функция
# =============================================================================

main() {
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Вывод результатов
    if [[ "$FORMAT" == "json" ]]; then
        show_json_output
    else
        show_text_output
    fi
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
