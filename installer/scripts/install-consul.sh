#!/bin/bash
# =============================================================================
# Скрипт установки Consul
# =============================================================================
# Назначение: Установка и настройка Consul в Docker контейнере
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
    --version VERSION         Версия Consul (по умолчанию: из config/monq.conf)
    --base-dir PATH           Базовая директория (по умолчанию: из config/monq.conf)
    --data-dir PATH           Директория данных (по умолчанию: из config/monq.conf)
    --config-dir PATH         Директория конфигурации (по умолчанию: из config/monq.conf)
    --logs-dir PATH           Директория логов (по умолчанию: из config/monq.conf)
    --http-port PORT          HTTP порт (по умолчанию: из config/monq.conf)
    --https-port PORT         HTTPS порт (по умолчанию: из config/monq.conf)
    --dns-port PORT           DNS порт (по умолчанию: из config/monq.conf)
    --server-port PORT        Server порт (по умолчанию: из config/monq.conf)
    --serf-lan-port PORT      Serf LAN порт (по умолчанию: из config/monq.conf)
    --serf-wan-port PORT      Serf WAN порт (по умолчанию: из config/monq.conf)
    --container-name NAME     Имя контейнера (по умолчанию: из config/monq.conf)
    --datacenter NAME         Имя датацентра (по умолчанию: из config/monq.conf)
    --node-name NAME          Имя узла (по умолчанию: из config/monq.conf)
    --mode MODE               Режим работы (server/agent) (по умолчанию: из config/monq.conf)
    --bootstrap-expect NUM    Количество серверов для bootstrap (по умолчанию: из config/monq.conf)
    --acl-token TOKEN         ACL токен (по умолчанию: из config/monq.conf)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --help                    Показать эту справку

Примеры:
    $0 --version 1.18.1 --datacenter my-dc
    $0 --base-dir /opt/consul --dry-run
    $0 --http-port 8501 --https-port 8502

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                CONSUL_VERSION="$2"
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
            --datacenter)
                CONSUL_DATACENTER="$2"
                shift 2
                ;;
            --node-name)
                CONSUL_NODE_NAME="$2"
                shift 2
                ;;
            --mode)
                CONSUL_MODE="$2"
                shift 2
                ;;
            --bootstrap-expect)
                CONSUL_BOOTSTRAP_EXPECT="$2"
                shift 2
                ;;
            --acl-token)
                CONSUL_ACL_TOKEN="$2"
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
    
    if [[ -z "$CONSUL_VERSION" ]]; then
        log_error "Версия Consul не может быть пустой"
        errors=$((errors + 1))
    fi
    
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
    
    if [[ ! "$CONSUL_SERVER_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_SERVER_PORT -lt 1 ]] || [[ $CONSUL_SERVER_PORT -gt 65535 ]]; then
        log_error "Неверный Server порт: $CONSUL_SERVER_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CONSUL_SERF_LAN_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_SERF_LAN_PORT -lt 1 ]] || [[ $CONSUL_SERF_LAN_PORT -gt 65535 ]]; then
        log_error "Неверный Serf LAN порт: $CONSUL_SERF_LAN_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CONSUL_SERF_WAN_PORT" =~ ^[0-9]+$ ]] || [[ $CONSUL_SERF_WAN_PORT -lt 1 ]] || [[ $CONSUL_SERF_WAN_PORT -gt 65535 ]]; then
        log_error "Неверный Serf WAN порт: $CONSUL_SERF_WAN_PORT"
        errors=$((errors + 1))
    fi
    
    if [[ "$CONSUL_MODE" != "server" && "$CONSUL_MODE" != "agent" ]]; then
        log_error "Неверный режим работы: $CONSUL_MODE (допустимо: server, agent)"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$CONSUL_BOOTSTRAP_EXPECT" =~ ^[0-9]+$ ]] || [[ $CONSUL_BOOTSTRAP_EXPECT -lt 1 ]]; then
        log_error "Неверное количество серверов для bootstrap: $CONSUL_BOOTSTRAP_EXPECT"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Создание директорий
create_directories() {
    print_section "Создание директорий для Consul"
    
    local directories=(
        "$CONSUL_BASE_DIR"
        "$CONSUL_DATA_DIR"
        "$CONSUL_CONFIG_DIR"
        "$CONSUL_LOGS_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий Consul"
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
    if run_sudo chown -R 100:1000 "$CONSUL_DATA_DIR" "$CONSUL_LOGS_DIR"; then
        print_success "Права доступа установлены для директорий Consul"
    else
        print_warning "Не удалось установить права доступа для директорий Consul"
    fi
    
    return 0
}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для Consul"
    
    local env_file="$CONSUL_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/consul.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# Consul Configuration
TIMEZONE=${TIMEZONE}
CONSUL_VERSION=${CONSUL_VERSION}
CONSUL_BASE_DIR=${CONSUL_BASE_DIR}
CONSUL_DATA_DIR=${CONSUL_DATA_DIR}
CONSUL_CONFIG_DIR=${CONSUL_CONFIG_DIR}
CONSUL_LOGS_DIR=${CONSUL_LOGS_DIR}
CONSUL_HTTP_PORT=${CONSUL_HTTP_PORT}
CONSUL_HTTPS_PORT=${CONSUL_HTTPS_PORT}
CONSUL_DNS_PORT=${CONSUL_DNS_PORT}
CONSUL_SERVER_PORT=${CONSUL_SERVER_PORT}
CONSUL_SERF_LAN_PORT=${CONSUL_SERF_LAN_PORT}
CONSUL_SERF_WAN_PORT=${CONSUL_SERF_WAN_PORT}
CONSUL_CONTAINER_NAME=${CONSUL_CONTAINER_NAME}
CONSUL_NETWORK=${CONSUL_NETWORK}
CONSUL_DATACENTER=${CONSUL_DATACENTER}
CONSUL_NODE_NAME=${CONSUL_NODE_NAME}
CONSUL_MODE=${CONSUL_MODE}
CONSUL_BOOTSTRAP_EXPECT=${CONSUL_BOOTSTRAP_EXPECT}
CONSUL_ACL_TOKEN=${CONSUL_ACL_TOKEN}
CONSUL_ENCRYPT=${CONSUL_ENCRYPT}
CONSUL_AUTO_ENCRYPT=${CONSUL_AUTO_ENCRYPT}
CONSUL_VERIFY_OUTGOING=${CONSUL_VERIFY_OUTGOING}
CONSUL_VERIFY_INCOMING=${CONSUL_VERIFY_INCOMING}
CONSUL_VERIFY_SERVER_HOSTNAME=${CONSUL_VERIFY_SERVER_HOSTNAME}
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
    copy_docker_compose_file "Consul" "consul" "$CONSUL_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "Consul" "$CONSUL_BASE_DIR"
}

# Запуск Consul сервисов
start_consul_services() {
    print_section "Запуск Consul сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск Consul сервисов"
        print_info "[DRY-RUN] Образ: consul:$CONSUL_VERSION"
        print_info "[DRY-RUN] HTTP порт: $CONSUL_HTTP_PORT:8500"
        print_info "[DRY-RUN] HTTPS порт: $CONSUL_HTTPS_PORT:8501"
        print_info "[DRY-RUN] DNS порт: $CONSUL_DNS_PORT:8600"
        print_info "[DRY-RUN] Данные: $CONSUL_DATA_DIR:/consul/data"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$CONSUL_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $CONSUL_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "Consul сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске Consul сервисов"
        return 1
    fi
}

# Ожидание готовности Consul
wait_for_consul() {
    print_section "Ожидание готовности Consul"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности Consul"
        return 0
    fi
    
    local retry_count=0
    local max_retries=60
    local wait_time=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Проверяем доступность HTTP API
        if curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" >/dev/null 2>&1; then
            print_success "Consul готов к работе"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности Consul... ($retry_count/$max_retries)"
        sleep $wait_time
    done
    
    print_error "Consul не готов к работе после $max_retries попыток"
    return 1
}

# Настройка Consul
setup_consul() {
    print_section "Настройка Consul"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка Consul"
        return 0
    fi
    
    # Ожидание готовности
    if ! wait_for_consul; then
        print_error "Consul не готов для настройки"
        return 1
    fi
    
    # Проверка статуса кластера
    print_info "Проверка статуса кластера Consul"
    local leader_response=$(curl -s "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" 2>/dev/null)
    if [[ -n "$leader_response" && "$leader_response" != "null" ]]; then
        print_success "Кластер Consul активен, лидер: $leader_response"
    else
        print_warning "Не удалось определить лидера кластера"
    fi
    
    # Проверка членов кластера
    print_info "Проверка членов кластера"
    local members_response=$(curl -s "http://localhost:$CONSUL_HTTP_PORT/v1/agent/members" 2>/dev/null)
    if [[ -n "$members_response" && "$members_response" != "null" ]]; then
        local member_count=$(echo "$members_response" | jq '. | length' 2>/dev/null || echo "0")
        print_success "Количество членов кластера: $member_count"
    else
        print_warning "Не удалось получить список членов кластера"
    fi
    
    print_success "Настройка Consul завершена"
    return 0
}

# Проверка установки Consul
verify_consul_installation() {
    print_section "Проверка установки Consul"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки Consul"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса контейнера
    if run_docker_compose -f "$CONSUL_BASE_DIR/docker-compose.yml" ps | grep -q Up; then
        log_debug "Проверка пройдена: контейнер Consul запущен"
    else
        print_warning "Проверка не пройдена: контейнер Consul не запущен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка HTTP API
    if curl -fsS "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" >/dev/null 2>&1; then
        log_debug "Проверка пройдена: HTTP API Consul доступен"
    else
        print_warning "Проверка не пройдена: HTTP API Consul недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка Docker сервиса
    if systemctl is-active docker &>/dev/null; then
        log_debug "Проверка пройдена: Docker сервис активен"
    else
        print_warning "Проверка не пройдена: Docker сервис не активен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка версии Consul
    local version_response=$(curl -s "http://localhost:$CONSUL_HTTP_PORT/v1/status/leader" 2>/dev/null)
    if [[ -n "$version_response" ]]; then
        print_success "Consul API доступен"
    else
        print_warning "Не удалось проверить API Consul"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности веб-интерфейса
    if curl -s -f "http://localhost:$CONSUL_HTTP_PORT/ui" &>/dev/null; then
        print_success "Веб-интерфейс Consul доступен"
    else
        print_warning "Веб-интерфейс Consul недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки Consul пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок Consul"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к Consul"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Consul успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}HTTP интерфейс:${NC} http://$(hostname -I | awk '{print $1}'):$CONSUL_HTTP_PORT"
    echo -e "${BLUE}HTTPS интерфейс:${NC} https://$(hostname -I | awk '{print $1}'):$CONSUL_HTTPS_PORT"
    echo -e "${BLUE}DNS интерфейс:${NC} $(hostname -I | awk '{print $1}'):$CONSUL_DNS_PORT"
    echo -e "${BLUE}Веб-интерфейс:${NC} http://$(hostname -I | awk '{print $1}'):$CONSUL_HTTP_PORT/ui"
    echo
    echo -e "${BLUE}Датацентр:${NC} $CONSUL_DATACENTER"
    echo -e "${BLUE}Узел:${NC} $CONSUL_NODE_NAME"
    echo -e "${BLUE}Режим:${NC} $CONSUL_MODE"
    echo -e "${BLUE}Bootstrap ожидание:${NC} $CONSUL_BOOTSTRAP_EXPECT"
    echo
    echo -e "${BLUE}Контейнер:${NC} $CONSUL_CONTAINER_NAME"
    echo -e "${BLUE}Сеть:${NC} $CONSUL_NETWORK"
    echo -e "${BLUE}Базовая директория:${NC} $CONSUL_BASE_DIR"
    echo -e "${BLUE}Данные:${NC} $CONSUL_DATA_DIR"
    echo -e "${BLUE}Конфигурация:${NC} Переменные окружения в docker-compose.yml"
    echo -e "${BLUE}Логи:${NC} $CONSUL_LOGS_DIR"
    echo
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    echo -e "${PURPLE}${BOLD}Команды управления:${NC}"
    echo -e "  ${GREEN}Остановка:${NC} cd $CONSUL_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Запуск:${NC} cd $CONSUL_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Логи:${NC} cd $CONSUL_BASE_DIR && $compose_cmd logs"
    echo -e "  ${GREEN}Перезапуск:${NC} cd $CONSUL_BASE_DIR && $compose_cmd restart"
    echo -e "  ${GREEN}Статус:${NC} cd $CONSUL_BASE_DIR && $compose_cmd ps"
    echo
    echo -e "${PURPLE}${BOLD}Примеры использования:${NC}"
    echo -e "  ${GREEN}Статус кластера:${NC} curl http://localhost:$CONSUL_HTTP_PORT/v1/status/leader"
    echo -e "  ${GREEN}Список сервисов:${NC} curl http://localhost:$CONSUL_HTTP_PORT/v1/catalog/services"
    echo -e "  ${GREEN}Список узлов:${NC} curl http://localhost:$CONSUL_HTTP_PORT/v1/catalog/nodes"
    echo -e "  ${GREEN}Консоль:${NC} docker exec -it $CONSUL_CONTAINER_NAME consul members"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Consul для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-consul-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Consul"
    log_info "Конфигурация загружена из: config/monq.conf"
    log_info "Версия: $CONSUL_VERSION"
    log_info "HTTP порт: $CONSUL_HTTP_PORT"
    log_info "HTTPS порт: $CONSUL_HTTPS_PORT"
    log_info "DNS порт: $CONSUL_DNS_PORT"
    log_info "Базовая директория: $CONSUL_BASE_DIR"
    log_info "Директория данных: $CONSUL_DATA_DIR"
    log_info "Директория конфигурации: $CONSUL_CONFIG_DIR"
    log_info "Директория логов: $CONSUL_LOGS_DIR"
    log_info "Датацентр: $CONSUL_DATACENTER"
    log_info "Узел: $CONSUL_NODE_NAME"
    log_info "Режим: $CONSUL_MODE"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_docker"
        "create_directories"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "start_consul_services"
        "wait_for_consul"
        "setup_consul"
        "verify_consul_installation"
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
    
    log_info "Установка Consul завершена успешно"
    
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
