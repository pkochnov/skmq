#!/bin/bash
# =============================================================================
# Скрипт установки Docker Engine
# =============================================================================
# Назначение: Установка и настройка Docker Engine на RedOS 8
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source /etc/os-release

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию
DOCKER_VERSION="${DOCKER_VERSION:-latest}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-/etc/docker}"
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR:-}"
DOCKER_REPO_RELEASEVER="${DOCKER_REPO_RELEASEVER:-}"
DRY_RUN=false
FORCE=false

# Функции цветного вывода загружаются из common.sh

# =============================================================================
# Функции скрипта
# =============================================================================

# Поиск конфигурационного файла хостов
find_hosts_config() {
    local config_file=""
    
    # Список возможных путей для поиска
    local possible_paths=(
        "$SCRIPT_DIR/../config/hosts.conf"
        "/root/sibkor-monq/config/hosts.conf"
        "$(pwd)/config/hosts.conf"
        "$(dirname "$(pwd)")/config/hosts.conf"
        "$(dirname "$(dirname "$(pwd)")")/config/hosts.conf"
    )
    
    # Ищем первый существующий файл
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            config_file="$path"
            break
        fi
    done
    
    echo "$config_file"
}

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --version VERSION      Версия Docker (по умолчанию: latest)
    --data-root PATH       Путь к данным Docker (по умолчанию: /var/lib/docker)
    --config-dir PATH      Путь к конфигурации Docker (по умолчанию: /etc/docker)
    --registry-mirror URL  URL Docker Registry для зеркалирования (по умолчанию: из конфигурации)
    --dry-run             Режим симуляции (без выполнения команд)
    --force               Принудительное выполнение (без подтверждений)
    --help                Показать эту справку

Примеры:
    $0 --version 24.0.7 --registry-mirror http://registry.example.com:5000
    $0 --data-root /opt/docker --dry-run

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                DOCKER_VERSION="$2"
                shift 2
                ;;
            --data-root)
                DOCKER_DATA_ROOT="$2"
                shift 2
                ;;
            --config-dir)
                DOCKER_CONFIG_DIR="$2"
                shift 2
                ;;
            --registry-mirror)
                DOCKER_REGISTRY_MIRROR="$2"
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
    
    if [[ ! -d "$(dirname "$DOCKER_DATA_ROOT")" ]]; then
        log_error "Родительская директория для --data-root не существует: $(dirname "$DOCKER_DATA_ROOT")"
        errors=$((errors + 1))
    fi
    
    if [[ ! -d "$(dirname "$DOCKER_CONFIG_DIR")" ]]; then
        log_error "Родительская директория для --config-dir не существует: $(dirname "$DOCKER_CONFIG_DIR")"
        errors=$((errors + 1))
    fi
    
    # Проверка URL registry mirror
    if [[ -n "$DOCKER_REGISTRY_MIRROR" ]]; then
        if [[ ! "$DOCKER_REGISTRY_MIRROR" =~ ^https?:// ]]; then
            log_error "URL registry mirror должен начинаться с http:// или https://: $DOCKER_REGISTRY_MIRROR"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Удаление старых версий Docker и podman
remove_old_docker() {
    print_section "Удаление старых версий Docker и podman"
    
    local packages_to_remove=(
        "podman"
        "buildah"
        "docker"
        "docker-client"
        "docker-client-latest"
        "docker-common"
        "docker-latest"
        "docker-latest-logrotate"
        "docker-logrotate"
        "docker-engine"
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "runc"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление пакетов: ${packages_to_remove[*]}"
        return 0
    fi
    
    # Удаление пакетов
    for package in "${packages_to_remove[@]}"; do
        if run_sudo dnf remove -y "$package" 2>/dev/null; then
            log_debug "Пакет удален: $package"
        fi
    done
    
    # Удаление директорий
    local dirs_to_remove=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/etc/docker"
        "/etc/containerd"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            if run_sudo rm -rf "$dir"; then
                log_debug "Директория удалена: $dir"
            fi
        fi
    done
    
    print_success "Старые версии Docker и podman удалены"
    return 0
}

# Установка зависимостей
install_dependencies() {
    print_section "Установка зависимостей для Docker"
    
    local packages=(
        "dnf-utils"
        "zip"
        "unzip"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка пакетов: ${packages[*]}"
        return 0
    fi
    
    if run_sudo dnf $DOCKER_REPO_RELEASEVER install -y "${packages[@]}"; then
        print_success "Зависимости установлены"
        return 0
    else
        print_error "Ошибка при установке зависимостей"
        return 1
    fi
}

# Добавление Docker репозитория
add_docker_repository() {
    print_section "Добавление Docker репозитория"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Добавление Docker репозитория"
        return 0
    fi
    
    # Добавление репозитория
    if run_sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo; then
        print_success "Docker репозиторий добавлен"
    else
        print_error "Ошибка при добавлении Docker репозитория"
        return 1
    fi
    
    # Обновление кэша пакетов
    if run_sudo dnf $DOCKER_REPO_RELEASEVER makecache; then
        print_success "Кэш пакетов обновлен"
        return 0
    else
        print_error "Ошибка при обновлении кэша пакетов"
        return 1
    fi
}

# Установка Docker Engine
install_docker_engine() {
    print_section "Установка Docker Engine версии: $DOCKER_VERSION"
    
    # Если ОС RedOS и версия начинается с 8
    if [[ "$ID" == "redos" && "$VERSION_ID" =~ ^8 ]]; then
        local packages=(
            "docker-ce"
            "docker-compose"
        )
    else
        local packages=(
            "docker-ce"
            "docker-ce-cli"
            "containerd.io"
            "docker-buildx-plugin"
            "docker-compose-plugin"
        )
    fi

    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка пакетов: ${packages[*]}"
        return 0
    fi
    
    # Установка Docker Engine (упрощенный алгоритм для RHEL9)
    if run_sudo dnf $DOCKER_REPO_RELEASEVER install -y "${packages[@]}"; then
        if [[ "$DOCKER_VERSION" == "latest" ]]; then
            print_success "Docker Engine установлен (последняя версия)"
        else
            print_success "Docker Engine установлен"
        fi
        return 0
    else
        print_error "Ошибка при установке Docker Engine"
        return 1
    fi
}

# Определение registry mirror из конфигурации
get_registry_mirror() {
    # Если registry mirror уже задан, используем его
    if [[ -n "$DOCKER_REGISTRY_MIRROR" ]]; then
        echo "$DOCKER_REGISTRY_MIRROR"
        return 0
    fi
    
    # Загружаем конфигурацию хостов
    local hosts_config_file=$(find_hosts_config)
    if [[ -f "$hosts_config_file" ]]; then
        source "$hosts_config_file"
        
        # Ищем хост registry
        if [[ -n "$HOST_REGISTRY_HOSTNAME" && -n "$HOST_REGISTRY_IP" ]]; then
            local registry_hostname="$HOST_REGISTRY_HOSTNAME"
            local registry_ip="$HOST_REGISTRY_IP"
            
            # Определяем, какой адрес использовать
            # Если мы на том же хосте, что и registry, используем localhost
            local current_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
            if [[ "$current_ip" == "$registry_ip" ]]; then
                echo "localhost:5000"
            else
                # Иначе используем имя хоста registry
                echo "registry:5000"
            fi
        else
            print_warning "Конфигурация registry не найдена, registry mirror не будет настроен"
            echo ""
        fi
    else
        print_warning "Конфигурационный файл хостов не найден: $hosts_config_file"
        echo ""
    fi
}

# Настройка Docker daemon
configure_docker_daemon() {
    print_section "Настройка Docker daemon"
    
    # Определяем registry mirror
    local registry_mirror=$(get_registry_mirror)
    if [[ -n "$registry_mirror" ]]; then
        print_info "Registry mirror: $registry_mirror"
    else
        print_info "Registry mirror не настроен"
    fi
    
    # Создание директории конфигурации
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директории: $DOCKER_CONFIG_DIR"
        print_info "[DRY-RUN] Создание конфигурации daemon.json"
        if [[ -n "$registry_mirror" ]]; then
            print_info "[DRY-RUN] Registry mirror: $registry_mirror"
        fi
        return 0
    fi
    
    if run_sudo mkdir -p "$DOCKER_CONFIG_DIR"; then
        log_debug "Директория конфигурации создана: $DOCKER_CONFIG_DIR"
    else
        print_error "Ошибка при создании директории конфигурации"
        return 1
    fi
    
    # Создание конфигурации daemon.json
    local daemon_config="$DOCKER_CONFIG_DIR/daemon.json"
    local temp_config="/tmp/docker-daemon.json"
    
    # Создаем временный файл с конфигурацией
    if [[ -n "$registry_mirror" ]]; then
        cat << EOF > "$temp_config"
{
    "data-root": "$DOCKER_DATA_ROOT",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "metrics-addr": "127.0.0.1:9323",
    "registry-mirrors": [ "http://$registry_mirror" ],
    "insecure-registries": [ "$registry_mirror" ],
    "default-address-pools": [
        {
            "base": "172.17.0.0/12",
            "size": 24
        }
    ]
}
EOF
    else
        cat << EOF > "$temp_config"
{
    "data-root": "$DOCKER_DATA_ROOT",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "metrics-addr": "127.0.0.1:9323",
    "default-address-pools": [
        {
            "base": "172.17.0.0/12",
            "size": 24
        }
    ]
}
EOF
    fi
    
    # Копируем файл с sudo правами
    if run_sudo cp "$temp_config" "$daemon_config"; then
        run_sudo chmod 644 "$daemon_config"
        rm -f "$temp_config"
        print_success "Конфигурация Docker daemon создана"
    else
        rm -f "$temp_config"
        print_error "Ошибка при создании конфигурации Docker daemon"
        return 1
    fi
    
    return 0
}

# Создание директорий для данных Docker
create_docker_directories() {
    print_section "Создание директорий для данных Docker"
    
    local directories=(
        "$DOCKER_DATA_ROOT"
        "$DOCKER_DATA_ROOT/containers"
        "$DOCKER_DATA_ROOT/image"
        "$DOCKER_DATA_ROOT/overlay2"
        "$DOCKER_DATA_ROOT/volumes"
        "$DOCKER_DATA_ROOT/network"
        "/etc/docker/certs.d"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание директорий Docker"
        for dir in "${directories[@]}"; do
            print_info "[DRY-RUN] mkdir -p $dir"
        done
        return 0
    fi
    
    for dir in "${directories[@]}"; do
        if run_sudo mkdir -p "$dir"; then
            log_debug "Директория создана: $dir"
        else
            print_warning "Не удалось создать директорию: $dir"
        fi
    done
    
    # Установка прав доступа
    if run_sudo chown -R root:root "$DOCKER_DATA_ROOT"; then
        print_success "Права доступа установлены для $DOCKER_DATA_ROOT"
    else
        print_warning "Не удалось установить права доступа для $DOCKER_DATA_ROOT"
    fi
    
    return 0
}

# Добавление пользователя в группу docker
add_user_to_docker_group() {
    print_section "Добавление пользователя $MONQ_USER в группу docker"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Добавление пользователя $MONQ_USER в группу docker"
        return 0
    fi
    
    if run_sudo usermod -aG docker "$MONQ_USER"; then
        print_success "Пользователь $MONQ_USER добавлен в группу docker"
    else
        print_error "Ошибка при добавлении пользователя в группу docker"
        return 1
    fi
    
    return 0
}

# Настройка автозапуска Docker
enable_docker_services() {
    print_section "Настройка автозапуска Docker сервисов"
    
    local services=(
        "docker"
        "containerd"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Включение автозапуска сервисов: ${services[*]}"
        return 0
    fi
    
    for service in "${services[@]}"; do
        if run_sudo systemctl enable "$service"; then
            log_debug "Автозапуск включен для сервиса: $service"
        else
            print_warning "Не удалось включить автозапуск для сервиса: $service"
        fi
    done
    
    return 0
}

# Запуск Docker сервисов
start_docker_services() {
    print_section "Запуск Docker сервисов"
    
    local services=(
        "containerd"
        "docker"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Запуск сервисов: ${services[*]}"
        return 0
    fi
    
    for service in "${services[@]}"; do
        if run_sudo systemctl start "$service"; then
            log_debug "Сервис запущен: $service"
        else
            print_error "Ошибка при запуске сервиса: $service"
            return 1
        fi
    done
    
    # Ожидание готовности Docker
    print_info "Ожидание готовности Docker..."
    local retry_count=0
    local max_retries=30
    
    while [[ $retry_count -lt $max_retries ]]; do
        if run_sudo docker info &>/dev/null; then
            print_success "Docker готов к работе"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_debug "Ожидание готовности Docker... ($retry_count/$max_retries)"
        sleep 2
    done
    
    print_error "Docker не готов к работе после $max_retries попыток"
    return 1
}

# Проверка установки Docker
verify_docker_installation() {
    print_section "Проверка установки Docker"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки Docker"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка версии Docker
    if docker --version &>/dev/null; then
        log_debug "Проверка пройдена: docker --version"
    else
        print_warning "Проверка не пройдена: docker --version"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка Docker info (с sudo)
    if run_sudo docker info &>/dev/null; then
        log_debug "Проверка пройдена: docker info"
    else
        print_warning "Проверка не пройдена: docker info"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка статуса сервисов
    if systemctl is-active docker &>/dev/null; then
        log_debug "Проверка пройдена: systemctl is-active docker"
    else
        print_warning "Проверка не пройдена: systemctl is-active docker"
        failed_checks=$((failed_checks + 1))
    fi
    
    if systemctl is-active containerd &>/dev/null; then
        log_debug "Проверка пройдена: systemctl is-active containerd"
    else
        print_warning "Проверка не пройдена: systemctl is-active containerd"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка версии Docker
    local docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$docker_version" ]]; then
        print_success "Установленная версия Docker: $docker_version"
    else
        print_warning "Не удалось определить версию Docker"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности Docker для пользователя
    if run_sudo -u "$MONQ_USER" docker info &>/dev/null; then
        print_success "Docker доступен для пользователя $MONQ_USER"
    else
        print_warning "Docker недоступен для пользователя $MONQ_USER (требуется перелогин)"
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки Docker пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок Docker"
        return 1
    fi
}

# Тестирование Docker
test_docker() {
    print_section "Тестирование Docker"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Тестирование Docker"
        return 0
    fi
    
    # Проверяем, что Docker daemon доступен
    if ! run_sudo docker info &>/dev/null; then
        print_error "Docker daemon недоступен для тестирования"
        return 1
    fi
    
    # Запуск тестового контейнера
    print_info "Запуск тестового контейнера hello-world..."
    if run_sudo docker run --rm hello-world &>/dev/null; then
        print_success "Тестовый контейнер запущен успешно"
    else
        print_error "Ошибка при запуске тестового контейнера"
        print_info "Попробуйте запустить вручную: sudo docker run --rm hello-world"
        return 1
    fi
    
    # Очистка тестовых образов
    if run_sudo docker rmi hello-world &>/dev/null; then
        log_debug "Тестовый образ удален"
    fi
    
    print_success "Тестирование Docker завершено успешно"
    return 0
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Docker Engine для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-docker-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Docker"
    log_info "Версия Docker: $DOCKER_VERSION"
    log_info "Директория данных: $DOCKER_DATA_ROOT"
    log_info "Директория конфигурации: $DOCKER_CONFIG_DIR"
    if [[ -n "$DOCKER_REGISTRY_MIRROR" ]]; then
        log_info "Registry mirror (заданный): $DOCKER_REGISTRY_MIRROR"
    else
        log_info "Registry mirror: будет определен из конфигурации"
    fi
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "remove_old_docker"
        "install_dependencies"
        # "add_docker_repository"
        "install_docker_engine"
        "create_docker_directories"
        "configure_docker_daemon"
        "add_user_to_docker_group"
        "enable_docker_services"
        "start_docker_services"
        "verify_docker_installation"
        "test_docker"
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
    
    log_info "Установка Docker завершена успешно"
    
    # Информация для пользователя
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Docker Engine успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    local final_registry_mirror=$(get_registry_mirror)
    if [[ -n "$final_registry_mirror" ]]; then
        echo -e "${BLUE}Registry Mirror:${NC} $final_registry_mirror"
    else
        echo -e "${BLUE}Registry Mirror:${NC} не настроен"
    fi
    echo -e "${BLUE}Конфигурация:${NC} $DOCKER_CONFIG_DIR/daemon.json"
    echo -e "${BLUE}Директория данных:${NC} $DOCKER_DATA_ROOT"
    echo
    echo -e "${YELLOW}Для использования Docker без sudo пользователю $MONQ_USER необходимо перелогиниться${NC}"
    echo -e "${YELLOW}Или выполнить команду: newgrp docker${NC}"
    echo
    echo -e "${BLUE}Лог файл:${NC} $log_file"
    
    log_info "Для использования Docker без sudo пользователю $MONQ_USER необходимо перелогиниться"
    log_info "Или выполнить команду: newgrp docker"
    if [[ -n "$final_registry_mirror" ]]; then
        log_info "Registry Mirror настроен: $final_registry_mirror"
    else
        log_info "Registry Mirror не настроен"
    fi
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
