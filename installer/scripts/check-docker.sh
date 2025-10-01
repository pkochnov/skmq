#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Docker
# =============================================================================
# Назначение: Проверка состояния Docker Engine, контейнеров и образов
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию
OUTPUT_FORMAT="text"  # text, json
VERBOSE=false
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
    --format FORMAT       Формат вывода (text|json, по умолчанию: text)
    --verbose            Подробный вывод
    --dry-run            Режим симуляции
    --help               Показать эту справку

Примеры:
    $0 --format json
    $0 --verbose

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
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
    if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        log_error "Неверный формат вывода: $OUTPUT_FORMAT (допустимо: text, json)"
        exit 1
    fi
}

# Проверка версии Docker
check_docker_version() {
    local docker_version=""
    local docker_compose_version=""
    
    if command -v docker &>/dev/null; then
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Проверяем Docker Compose (плагин)
    if command -v docker &>/dev/null; then
        docker_compose_version=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    # Если плагин не найден, проверяем отдельную команду docker-compose
    if [[ -z "$docker_compose_version" ]] && command -v docker-compose &>/dev/null; then
        docker_compose_version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"docker_version\": \"$docker_version\","
        echo "    \"docker_compose_version\": \"$docker_compose_version\","
    else
        print_section "Версии Docker:"
        print_info "Docker: $docker_version"
        if [[ -n "$docker_compose_version" ]]; then
            print_info "Docker Compose: $docker_compose_version"
        else
            print_warning "Docker Compose: не установлен"
        fi
    fi
}

# Проверка статуса Docker daemon
check_docker_daemon() {
    local daemon_status=""
    local daemon_info=""
    
    if systemctl is-active docker &>/dev/null; then
        daemon_status="active"
        if command -v docker &>/dev/null; then
            daemon_info=$(docker info 2>/dev/null | head -20)
        fi
    else
        daemon_status="inactive"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"daemon_status\": \"$daemon_status\","
        echo "    \"daemon_info\": \"$daemon_info\","
    else
        print_section "Docker Daemon:"
        if [[ "$daemon_status" == "active" ]]; then
            print_success "Статус: $daemon_status"
        else
            print_error "Статус: $daemon_status"
        fi
        if [[ "$VERBOSE" == "true" && -n "$daemon_info" ]]; then
            print_info "Информация:"
            echo "$daemon_info" | sed 's/^/    /'
        fi
    fi
}

# Проверка запущенных контейнеров
check_running_containers() {
    local running_containers=()
    local stopped_containers=()
    
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        # Получение списка контейнеров
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local container_id=$(echo "$line" | awk '{print $1}')
                local container_name=$(echo "$line" | awk '{print $2}')
                local container_status=$(echo "$line" | awk '{print $7}')
                
                if [[ "$container_status" == "Up" ]]; then
                    running_containers+=("$container_name ($container_id)")
                else
                    stopped_containers+=("$container_name ($container_id)")
                fi
            fi
        done < <(docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | tail -n +2)
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"containers\": {"
        echo "        \"running\": ["
        for container in "${running_containers[@]}"; do
            echo "            \"$container\","
        done
        echo "        ],"
        echo "        \"stopped\": ["
        for container in "${stopped_containers[@]}"; do
            echo "            \"$container\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Контейнеры:"
        print_info "Запущенные: ${#running_containers[@]}"
        print_info "Остановленные: ${#stopped_containers[@]}"
        
        if [[ "$VERBOSE" == "true" ]]; then
            if [[ ${#running_containers[@]} -gt 0 ]]; then
                print_info "Запущенные контейнеры:"
                for container in "${running_containers[@]}"; do
                    print_success "  $container"
                done
            fi
            if [[ ${#stopped_containers[@]} -gt 0 ]]; then
                print_info "Остановленные контейнеры:"
                for container in "${stopped_containers[@]}"; do
                    print_error "  $container"
                done
            fi
        fi
    fi
}

# Проверка образов Docker
check_docker_images() {
    local images=()
    local total_size=""
    
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        # Получение списка образов
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local image_name=$(echo "$line" | awk '{print $1}')
                local image_tag=$(echo "$line" | awk '{print $2}')
                local image_size=$(echo "$line" | awk '{print $7}')
                images+=("$image_name:$image_tag ($image_size)")
            fi
        done < <(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" 2>/dev/null | tail -n +2)
        
        # Получение общего размера
        total_size=$(docker system df 2>/dev/null | grep "Images" | awk '{print $3}' || echo "unknown")
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"images\": {"
        echo "        \"count\": ${#images[@]},"
        echo "        \"total_size\": \"$total_size\","
        echo "        \"list\": ["
        for image in "${images[@]}"; do
            echo "            \"$image\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Образы Docker:"
        print_info "Количество: ${#images[@]}"
        print_info "Общий размер: $total_size"
        
        if [[ "$VERBOSE" == "true" && ${#images[@]} -gt 0 ]]; then
            print_info "Список образов:"
            for image in "${images[@]}"; do
                print_success "  📦 $image"
            done
        fi
    fi
}

# Проверка сетей Docker
check_docker_networks() {
    local networks=()
    
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        # Получение списка сетей
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local network_name=$(echo "$line" | awk '{print $2}')
                local network_driver=$(echo "$line" | awk '{print $3}')
                local network_scope=$(echo "$line" | awk '{print $4}')
                networks+=("$network_name ($network_driver, $network_scope)")
            fi
        done < <(docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null | tail -n +2)
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"networks\": {"
        echo "        \"count\": ${#networks[@]},"
        echo "        \"list\": ["
        for network in "${networks[@]}"; do
            echo "            \"$network\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Сети Docker:"
        print_info "Количество: ${#networks[@]}"
        
        if [[ "$VERBOSE" == "true" && ${#networks[@]} -gt 0 ]]; then
            print_info "Список сетей:"
            for network in "${networks[@]}"; do
                print_success "  🌐 $network"
            done
        fi
    fi
}

# Проверка томов Docker
check_docker_volumes() {
    local volumes=()
    local total_size=""
    
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        # Получение списка томов
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local volume_name=$(echo "$line" | awk '{print $2}')
                local volume_driver=$(echo "$line" | awk '{print $3}')
                volumes+=("$volume_name ($volume_driver)")
            fi
        done < <(docker volume ls --format "table {{.Driver}}\t{{.Name}}" 2>/dev/null | tail -n +2)
        
        # Получение общего размера томов
        total_size=$(docker system df 2>/dev/null | grep "Local Volumes" | awk '{print $4}' || echo "unknown")
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"volumes\": {"
        echo "        \"count\": ${#volumes[@]},"
        echo "        \"total_size\": \"$total_size\","
        echo "        \"list\": ["
        for volume in "${volumes[@]}"; do
            echo "            \"$volume\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Тома Docker:"
        print_info "Количество: ${#volumes[@]}"
        print_info "Общий размер: $total_size"
        
        if [[ "$VERBOSE" == "true" && ${#volumes[@]} -gt 0 ]]; then
            print_info "Список томов:"
            for volume in "${volumes[@]}"; do
                print_success "  💾 $volume"
            done
        fi
    fi
}

# Проверка использования ресурсов Docker
check_docker_resources() {
    local cpu_usage=""
    local memory_usage=""
    local disk_usage=""
    local running_containers=0
    
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        # Подсчет запущенных контейнеров
        running_containers=$(docker ps -q 2>/dev/null | wc -l)
        
        if [[ $running_containers -gt 0 ]]; then
            # Получение статистики использования ресурсов
            local stats=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null)
            
            if [[ -n "$stats" ]]; then
                # Убираем символ % и суммируем
                cpu_usage=$(echo "$stats" | awk '{gsub(/%/, "", $1); sum+=$1} END {printf "%.1f", sum}')
                memory_usage=$(echo "$stats" | awk '{gsub(/%/, "", $2); sum+=$2} END {printf "%.1f", sum}')
            fi
        else
            cpu_usage="0.0"
            memory_usage="0.0"
        fi
        
        # Получение использования диска
        local disk_info=$(docker system df 2>/dev/null)
        if [[ -n "$disk_info" ]]; then
            # Ищем строку с общим размером
            disk_usage=$(echo "$disk_info" | grep -E "Images|Local Volumes|Build Cache" | awk '{sum+=$3} END {print sum}' || echo "0B")
            if [[ -z "$disk_usage" || "$disk_usage" == "0" ]]; then
                disk_usage="0B"
            fi
        else
            disk_usage="unknown"
        fi
    else
        cpu_usage="N/A"
        memory_usage="N/A"
        disk_usage="N/A"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"resources\": {"
        echo "        \"running_containers\": $running_containers,"
        echo "        \"cpu_usage_percent\": \"$cpu_usage\","
        echo "        \"memory_usage_percent\": \"$memory_usage\","
        echo "        \"disk_usage\": \"$disk_usage\""
        echo "    },"
    else
        print_section "Использование ресурсов:"
        print_info "Запущенных контейнеров: $running_containers"
        if [[ "$cpu_usage" != "N/A" ]]; then
            print_info "CPU: ${cpu_usage}%"
            print_info "Память: ${memory_usage}%"
        else
            print_warning "CPU: $cpu_usage"
            print_warning "Память: $memory_usage"
        fi
        print_info "Диск: $disk_usage"
    fi
}

# Проверка конфигурации Docker
check_docker_config() {
    local config_file="/etc/docker/daemon.json"
    local config_exists="false"
    local config_content=""
    
    if [[ -f "$config_file" ]]; then
        config_exists="true"
        config_content=$(cat "$config_file" 2>/dev/null | head -10)
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"config\": {"
        echo "        \"config_file_exists\": $config_exists,"
        echo "        \"config_file\": \"$config_file\","
        echo "        \"config_content\": \"$config_content\""
        echo "    },"
    else
        print_section "Конфигурация Docker:"
        if [[ "$config_exists" == "true" ]]; then
            print_success "Файл конфигурации: $config_exists"
        else
            print_warning "Файл конфигурации: $config_exists"
        fi
        print_info "Путь: $config_file"
        
        if [[ "$VERBOSE" == "true" && -n "$config_content" ]]; then
            print_info "Содержимое:"
            echo "$config_content" | sed 's/^/    /'
        fi
    fi
}

# Проверка прав доступа пользователя
check_user_permissions() {
    local user_in_docker_group="false"
    local can_run_docker="false"
    
    if groups "$MONQ_USER" 2>/dev/null | grep -q docker; then
        user_in_docker_group="true"
    fi
    
    if sudo -u "$MONQ_USER" docker info &>/dev/null 2>&1; then
        can_run_docker="true"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"user_permissions\": {"
        echo "        \"user_in_docker_group\": $user_in_docker_group,"
        echo "        \"can_run_docker\": $can_run_docker"
        echo "    },"
    else
        print_section "Права доступа пользователя:"
        if [[ "$user_in_docker_group" == "true" ]]; then
            print_success "Пользователь $MONQ_USER в группе docker: $user_in_docker_group"
        else
            print_warning "Пользователь $MONQ_USER в группе docker: $user_in_docker_group"
        fi
        
        if [[ "$can_run_docker" == "true" ]]; then
            print_success "Может запускать Docker: $can_run_docker"
        else
            print_warning "Может запускать Docker: $can_run_docker"
        fi
        
        if [[ "$user_in_docker_group" == "false" ]]; then
            print_warning "  Пользователь не в группе docker"
        fi
        if [[ "$can_run_docker" == "false" ]]; then
            print_warning "  Пользователь не может запускать Docker команды"
        fi
    fi
}

# Проверка сервисов Docker
check_docker_services() {
    local docker_service=""
    local containerd_service=""
    
    if systemctl is-active docker &>/dev/null; then
        docker_service="active"
    else
        docker_service="inactive"
    fi
    
    if systemctl is-active containerd &>/dev/null; then
        containerd_service="active"
    else
        containerd_service="inactive"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"services\": {"
        echo "        \"docker\": \"$docker_service\","
        echo "        \"containerd\": \"$containerd_service\""
        echo "    }"
    else
        print_section "Сервисы Docker:"
        if [[ "$docker_service" == "active" ]]; then
            print_success "Docker: $docker_service"
        else
            print_error "Docker: $docker_service"
        fi
        
        if [[ "$containerd_service" == "active" ]]; then
            print_success "Containerd: $containerd_service"
        else
            print_error "Containerd: $containerd_service"
        fi
        
        if [[ "$docker_service" == "inactive" ]]; then
            print_warning "  Docker сервис не активен"
        fi
        if [[ "$containerd_service" == "inactive" ]]; then
            print_warning "  Containerd сервис не активен"
        fi
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Проверка состояния Docker"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-docker-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки состояния Docker"
    log_info "Формат вывода: $OUTPUT_FORMAT"
    log_info "Подробный режим: $VERBOSE"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{"
        echo "    \"timestamp\": \"$(date -Iseconds)\","
        echo "    \"hostname\": \"$(hostname)\","
    fi
    
    # Выполнение проверок
    local checks=(
        "check_docker_version"
        "check_docker_daemon"
        "check_running_containers"
        "check_docker_images"
        "check_docker_networks"
        "check_docker_volumes"
        "check_docker_resources"
        "check_docker_config"
        "check_user_permissions"
        "check_docker_services"
    )
    
    for check in "${checks[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Выполнение проверки: $check"
        else
            $check
        fi
    done
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "}"
    fi
    
    log_info "Проверка состояния Docker завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
