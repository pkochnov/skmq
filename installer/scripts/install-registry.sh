#!/bin/bash
# =============================================================================
# Скрипт установки Docker Registry
# =============================================================================
# Назначение: Установка и настройка Docker Registry с веб-интерфейсом
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
# REGISTRY_VERSION, REGISTRY_BASE_DIR, REGISTRY_DATA_DIR и другие
# определены в config/monq.conf
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
    --registry-version VERSION     Версия Docker Registry (по умолчанию: из monq.conf)
    --base-dir PATH                Базовая директория (по умолчанию: из monq.conf)
    --data-dir PATH                Директория данных (по умолчанию: из monq.conf)
    --config-dir PATH              Директория конфигурации (по умолчанию: из monq.conf)
    --registry-port PORT           Порт Registry (по умолчанию: из monq.conf)
    --registry-container NAME      Имя контейнера Registry (по умолчанию: из monq.conf)
    --dry-run                      Режим симуляции (без выполнения команд)
    --force                        Принудительное выполнение (без подтверждений)
    --help                         Показать эту справку

Примечание: Все настройки по умолчанию загружаются из файла config/monq.conf.
Для изменения настроек отредактируйте соответствующие переменные в monq.conf.

Примеры:
    $0 --registry-version 2.8.3
    $0 --base-dir /docker/registry --dry-run

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --registry-version)
                REGISTRY_VERSION="$2"
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
            --registry-port)
                REGISTRY_PORT="$2"
                shift 2
                ;;
            --registry-container)
                REGISTRY_CONTAINER_NAME="$2"
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
    
    if [[ -z "$REGISTRY_VERSION" ]]; then
        log_error "Версия Docker Registry не может быть пустой"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$REGISTRY_PORT" =~ ^[0-9]+$ ]] || [[ $REGISTRY_PORT -lt 1 ]] || [[ $REGISTRY_PORT -gt 65535 ]]; then
        log_error "Неверный порт Registry: $REGISTRY_PORT"
        errors=$((errors + 1))
    fi
    

    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Создание директорий
create_directories() {
    print_section "Создание директорий для Docker Registry"
    
    local directories=(
        "$REGISTRY_BASE_DIR"
        "$REGISTRY_DATA_DIR"
        "$REGISTRY_CONFIG_DIR"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий Docker Registry"
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
    if run_sudo chown -R 1000:1000 "$REGISTRY_DATA_DIR" "$REGISTRY_CONFIG_DIR"; then
        print_success "Права доступа установлены для директорий Docker Registry"
    else
        print_warning "Не удалось установить права доступа для директорий Docker Registry"
    fi
    
    return 0
}







# Копирование конфигурационных файлов
copy_registry_config() {
    print_section "Копирование конфигурационных файлов Docker Registry"
    
    local config_file="$REGISTRY_CONFIG_DIR/config.yml"
    local source_config=""
    
    # Определяем путь к исходному конфигурационному файлу
    if [[ -f "$SCRIPT_DIR/../config/registry/config.yml" ]]; then
        # Локальное выполнение
        source_config="$SCRIPT_DIR/../config/registry/config.yml"
    elif [[ -f "./config/registry/config.yml" ]]; then
        # Выполнение в временной директории на удаленном хосте
        source_config="./config/registry/config.yml"
    else
        print_error "Конфигурационный файл Docker Registry не найден"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Копирование конфигурационного файла: $source_config -> $config_file"
        return 0
    fi
    
    # Отладочная информация
    log_debug "Текущая директория: $(pwd)"
    log_debug "Ищем конфигурацию: $source_config"
    log_debug "Содержимое текущей директории:"
    log_debug "$(ls -la)"
    if [[ -d "./config" ]]; then
        log_debug "Содержимое директории config:"
        log_debug "$(ls -la ./config/)"
        if [[ -d "./config/registry" ]]; then
            log_debug "Содержимое директории config/registry:"
            log_debug "$(ls -la ./config/registry/)"
        fi
    fi
    
    # Проверяем существование исходного файла
    if [[ ! -f "$source_config" ]]; then
        print_error "Конфигурационный файл Docker Registry не найден: $source_config"
        return 1
    fi
    
    # Копируем конфигурационный файл
    if run_sudo cp "$source_config" "$config_file"; then
        run_sudo chown 1000:1000 "$config_file"
        run_sudo chmod 644 "$config_file"
        print_success "Конфигурационный файл Docker Registry скопирован"
        return 0
    else
        print_error "Ошибка при копировании конфигурационного файла Docker Registry"
        return 1
    fi
}

# Создание .env файла с переменными окружения
create_env_file() {
    print_section "Создание .env файла для Docker Registry"
    
    local env_file="$REGISTRY_BASE_DIR/.env"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание .env файла: $env_file"
        return 0
    fi
    
    local temp_env="/tmp/registry.env"
    
    # Создаем временный файл с переменными окружения
    cat << EOF > "$temp_env"
# Docker Registry Configuration
TIMEZONE=${TIMEZONE}
REGISTRY_VERSION=${REGISTRY_VERSION}
REGISTRY_CONTAINER_NAME=${REGISTRY_CONTAINER_NAME}
REGISTRY_PORT=${REGISTRY_PORT}
REGISTRY_DATA_DIR=${REGISTRY_DATA_DIR}
REGISTRY_CONFIG_DIR=${REGISTRY_CONFIG_DIR}
REGISTRY_NETWORK=${REGISTRY_NETWORK}
REGISTRY_LOG_LEVEL=${REGISTRY_LOG_LEVEL}
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
    copy_docker_compose_file "Docker Registry" "registry" "$REGISTRY_BASE_DIR"
}

# Остановка существующих сервисов (используется универсальная функция из common.sh)
stop_existing_services() {
    stop_existing_services_universal "Docker Registry" "$REGISTRY_BASE_DIR"
}

# Запуск Docker Registry сервисов
start_registry_services() {
    print_section "Запуск Docker Registry сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск Docker Registry сервисов"
        print_info "[DRY-RUN] Registry образ: registry:$REGISTRY_VERSION"
        print_info "[DRY-RUN] Registry порт: $REGISTRY_PORT:5000"
        print_info "[DRY-RUN] Данные: $REGISTRY_DATA_DIR:/var/lib/registry"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$REGISTRY_BASE_DIR" || {
        print_error "Не удалось перейти в директорию: $REGISTRY_BASE_DIR"
        return 1
    }
    
    # Запуск сервисов
    if run_docker_compose up -d; then
        print_success "Docker Registry сервисы запущены"
        return 0
    else
        print_error "Ошибка при запуске Docker Registry сервисов"
        return 1
    fi
}

# Ожидание готовности Docker Registry
wait_for_registry() {
    print_section "Ожидание готовности Docker Registry"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Ожидание готовности Docker Registry"
        return 0
    fi
    
    local retry_count=0
    local max_retries=20
    local wait_time=5
    
    print_info "Ожидание готовности Docker Registry (максимум $((max_retries * wait_time)) секунд)..."
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Проверяем доступность API с проверкой HTTP кода
        local http_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$REGISTRY_PORT/v2/" 2>/dev/null)
        if [[ "$http_code" -lt 500 ]]; then
            print_success "Docker Registry готов к работе (HTTP код: $http_code)"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности Docker Registry... ($retry_count/$max_retries, HTTP код: $http_code)"
        sleep $wait_time
    done
    
    print_error "Docker Registry не готов к работе после $max_retries попыток"
    return 1
}

# Проверка установки Docker Registry
verify_registry_installation() {
    print_section "Проверка установки Docker Registry"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки Docker Registry"
        return 0
    fi
    
    local checks=(
        "run_docker_compose -f $REGISTRY_BASE_DIR/docker-compose.yml ps | grep -q Up"
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:$REGISTRY_PORT/v2/ | grep -q '^[0-4][0-9][0-9]$'"
        "systemctl is-active docker"
    )
    
    local failed_checks=0
    
    for check in "${checks[@]}"; do
        if eval "$check" &>/dev/null; then
            log_debug "Проверка пройдена: $check"
        else
            print_warning "Проверка не пройдена: $check"
            failed_checks=$((failed_checks + 1))
        fi
    done
    
    # Проверка версии Docker Registry
    local api_http_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$REGISTRY_PORT/v2/" 2>/dev/null)
    if [[ "$api_http_code" -lt 500 ]]; then
        print_success "Docker Registry API доступен (HTTP код: $api_http_code)"
    else
        print_warning "Docker Registry API недоступен (HTTP код: $api_http_code)"
        failed_checks=$((failed_checks + 1))
    fi
    

    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки Docker Registry пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок Docker Registry"
        return 1
    fi
}

# Отображение информации о подключении
show_connection_info() {
    print_section "Информация о подключении к Docker Registry"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Docker Registry успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}Registry API:${NC} http://$(hostname -I | awk '{print $1}'):$REGISTRY_PORT"
    echo
    echo -e "${BLUE}Контейнер:${NC} $REGISTRY_CONTAINER_NAME"
    echo -e "${BLUE}Сеть:${NC} $REGISTRY_NETWORK"
    echo -e "${BLUE}Базовая директория:${NC} $REGISTRY_BASE_DIR"
    echo -e "${BLUE}Данные:${NC} $REGISTRY_DATA_DIR"
    echo -e "${BLUE}Конфигурация:${NC} $REGISTRY_CONFIG_DIR"
    echo
    local compose_cmd=$(get_docker_compose_cmd)
    echo -e "${PURPLE}${BOLD}Команды управления:${NC}"
    echo -e "  ${GREEN}Остановка:${NC} cd $REGISTRY_BASE_DIR && $compose_cmd down"
    echo -e "  ${GREEN}Запуск:${NC} cd $REGISTRY_BASE_DIR && $compose_cmd up -d"
    echo -e "  ${GREEN}Логи:${NC} cd $REGISTRY_BASE_DIR && $compose_cmd logs"
    echo -e "  ${GREEN}Перезапуск:${NC} cd $REGISTRY_BASE_DIR && $compose_cmd restart"
    echo -e "  ${GREEN}Статус:${NC} cd $REGISTRY_BASE_DIR && $compose_cmd ps"
    echo
    echo -e "${PURPLE}${BOLD}Примеры использования:${NC}"
    echo -e "  ${GREEN}Тег:${NC} docker tag myimage $(hostname -I | awk '{print $1}'):$REGISTRY_PORT/myimage:latest"
    echo -e "  ${GREEN}Пуш:${NC} docker push $(hostname -I | awk '{print $1}'):$REGISTRY_PORT/myimage:latest"
    echo -e "  ${GREEN}Пулл:${NC} docker pull $(hostname -I | awk '{print $1}'):$REGISTRY_PORT/myimage:latest"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Docker Registry для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-registry-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Docker Registry"
    log_info "Registry версия: $REGISTRY_VERSION"
    log_info "Registry порт: $REGISTRY_PORT"
    log_info "Базовая директория: $REGISTRY_BASE_DIR"
    log_info "Директория данных: $REGISTRY_DATA_DIR"
    log_info "Директория конфигурации: $REGISTRY_CONFIG_DIR"
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
        "copy_registry_config"
        "create_env_file"
        "copy_docker_compose"
        "stop_existing_services"
        "start_registry_services"
        "wait_for_registry"
        "verify_registry_installation"
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
    
    log_info "Установка Docker Registry завершена успешно"
    
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
