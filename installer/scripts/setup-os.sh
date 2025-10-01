#!/bin/bash
# =============================================================================
# Скрипт базовой настройки операционной системы
# =============================================================================
# Назначение: Установка и настройка базовых компонентов ОС RedOS 8
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
HOSTNAME=""
IP_ADDRESS=""
ROLE=""
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
    --hostname HOSTNAME    Имя хоста (обязательно)
    --ip IP_ADDRESS        IP адрес (обязательно)
    --role ROLE           Роль хоста (controller|worker|database|service)
    --dry-run             Режим симуляции (без выполнения команд)
    --force               Принудительное выполнение (без подтверждений)
    --help                Показать эту справку

Примеры:
    $0 --hostname msk-monq-k01 --ip 10.72.66.51 --role controller
    $0 --hostname msk-monq-arangodb --ip 10.72.66.54 --role database --dry-run

Примечание: Sudo пароль берется из переменной HOST_USER_PASSWORD в config/hosts.conf

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --ip)
                IP_ADDRESS="$2"
                shift 2
                ;;
            --role)
                ROLE="$2"
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
    
    if [[ -z "$HOSTNAME" ]]; then
        log_error "Параметр --hostname обязателен"
        errors=$((errors + 1))
    elif ! validate_hostname "$HOSTNAME"; then
        log_error "Неверный формат hostname: $HOSTNAME"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$IP_ADDRESS" ]]; then
        log_error "Параметр --ip обязателен"
        errors=$((errors + 1))
    elif ! validate_ip "$IP_ADDRESS"; then
        log_error "Неверный формат IP адреса: $IP_ADDRESS"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$ROLE" ]]; then
        log_warn "Роль хоста не указана, будет использована роль по умолчанию"
        ROLE="service"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Обновление системы
update_system() {
    log_info "Обновление системы..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Выполнение: dnf update -y"
        return 0
    fi
    
    if run_sudo dnf update -y; then
        log_info "Система успешно обновлена"
        return 0
    else
        log_error "Ошибка при обновлении системы"
        return 1
    fi
}

# Установка необходимых пакетов
install_packages() {
    print_section "Установка необходимых пакетов"
    
    local packages=(
        "curl"
        "wget"
        "vim"
        "net-tools"
        "bind-utils"
        "telnet"
        "nc"
        "tcpdump"
        "rsync"
        "unzip"
        "tar"
        "gzip"
        "openssh-clients"
        "openssh-server"
        "firewalld"
        "chrony"
        "jq"
        "bc"
        "yum-utils"
        "device-mapper-persistent-data"
        "lvm2"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Выполнение: dnf install -y ${packages[*]}"
        return 0
    fi
    
    if run_sudo dnf install -y "${packages[@]}"; then
        print_success "Пакеты успешно установлены"
        return 0
    else
        print_error "Ошибка при установке пакетов"
        return 1
    fi
}

# Настройка hostname
configure_hostname() {
    print_section "Настройка hostname: $HOSTNAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Выполнение: hostnamectl set-hostname $HOSTNAME"
        return 0
    fi
    
    if run_sudo hostnamectl set-hostname "$HOSTNAME"; then
        print_success "Hostname успешно настроен"
        return 0
    else
        print_error "Ошибка при настройке hostname"
        return 1
    fi
}


# Настройка DNS
configure_dns() {
    print_section "Настройка /etc/hosts"
    
    # Проверяем sudo сессию
    if [[ "$DRY_RUN" != "true" && "$SUDO_SESSION_ACTIVE" != "true" ]]; then
        print_warning "Sudo сессия не активна, пропускаем настройку /etc/hosts"
        return 0
    fi
    
    # Загружаем конфигурацию хостов
    local hosts_config_file=$(find_hosts_config)
    if [[ -f "$hosts_config_file" ]]; then
        source "$hosts_config_file"
        print_info "Загружена конфигурация хостов из: $hosts_config_file"
    else
        print_error "Конфигурационный файл хостов не найден: $hosts_config_file"
        return 1
    fi
    
    # Генерируем записи hosts из конфигурации
    local hosts_entries=()
    
    # Проходим по всем хостам из конфигурации
    for host_var in "${HOSTS_ALL[@]}"; do
        # Получаем значения для каждого хоста
        local hostname_var="${host_var}_HOSTNAME"
        local ip_var="${host_var}_IP"
        local alias_var="${host_var}_ALIAS"
        
        # Проверяем, что все переменные определены
        if [[ -n "${!hostname_var}" && -n "${!ip_var}" && -n "${!alias_var}" ]]; then
            local hostname="${!hostname_var}"
            local ip="${!ip_var}"
            local alias="${!alias_var}"
            
            # Формируем запись для /etc/hosts
            local hosts_entry="$ip $hostname $alias"
            hosts_entries+=("$hosts_entry")
            
            print_info "Добавлена запись: $hosts_entry"
        else
            print_warning "Неполная конфигурация для хоста: $host_var"
        fi
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Добавление записей в /etc/hosts"
        for entry in "${hosts_entries[@]}"; do
            print_info "[DRY-RUN] $entry"
        done
        return 0
    fi
    
    # Создание резервной копии /etc/hosts
    if run_sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S); then
        print_success "Создана резервная копия /etc/hosts"
    else
        print_warning "Не удалось создать резервную копию /etc/hosts"
    fi
    
    # Добавление записи для текущего хоста, если она не существует
    local current_host_entry="$IP_ADDRESS $HOSTNAME"
    if ! run_sudo grep -q "$current_host_entry" /etc/hosts; then
        # Создаем временный файл с записью
        local temp_entry="/tmp/hosts_entry_$$"
        echo "$current_host_entry" > "$temp_entry"
        # Добавляем запись в /etc/hosts
        run_sudo sh -c "cat $temp_entry >> /etc/hosts"
        rm -f "$temp_entry"
        print_success "Добавлена запись для текущего хоста: $current_host_entry"
    else
        print_info "Запись для текущего хоста уже существует: $current_host_entry"
    fi
    
    # Добавление записей для других хостов
    local added_count=0
    for entry in "${hosts_entries[@]}"; do
        # Пропускаем запись для текущего хоста
        if [[ "$entry" == "$current_host_entry" ]]; then
            continue
        fi
        
        if ! run_sudo grep -q "$entry" /etc/hosts; then
            # Создаем временный файл с записью
            local temp_entry="/tmp/hosts_entry_$$_$added_count"
            echo "$entry" > "$temp_entry"
            # Добавляем запись в /etc/hosts
            run_sudo sh -c "cat $temp_entry >> /etc/hosts"
            rm -f "$temp_entry"
            added_count=$((added_count + 1))
        fi
    done
    
    if [[ $added_count -gt 0 ]]; then
        print_success "Добавлено $added_count записей в /etc/hosts"
    else
        print_info "Все записи уже существуют в /etc/hosts"
    fi
    
    return 0
}

# Отключение файрвола
configure_firewall() {
    print_section "Отключение файрвола"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Отключение файрвола"
        return 0
    fi
    
    # Остановка и отключение firewalld
    if run_sudo systemctl stop firewalld; then
        print_success "Firewalld остановлен"
    else
        print_warning "Не удалось остановить firewalld (возможно, уже остановлен)"
    fi
    
    if run_sudo systemctl disable firewalld; then
        print_success "Firewalld отключен"
    else
        print_warning "Не удалось отключить firewalld"
    fi
    
    # Проверка статуса
    if ! systemctl is-active firewalld &>/dev/null; then
        print_success "Файрвол успешно отключен"
        return 0
    else
        print_warning "Файрвол все еще активен"
        return 1
    fi
}

# Настройка SELinux
configure_selinux() {
    if [[ "$DISABLE_SELINUX" != "true" ]]; then
        print_info "SELinux остается включенным"
        return 0
    fi
    
    print_section "Отключение SELinux"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Отключение SELinux"
        return 0
    fi
    
    # Проверка текущего статуса SELinux
    if [[ "$(getenforce)" == "Disabled" ]]; then
        print_success "SELinux уже отключен"
        return 0
    fi
    
    # Отключение SELinux
    if run_sudo setenforce 0; then
        print_success "SELinux временно отключен"
    else
        print_error "Ошибка при временном отключении SELinux"
        return 1
    fi
    
    # Постоянное отключение SELinux
    if run_sudo sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config; then
        print_success "SELinux настроен для постоянного отключения"
        print_warning "Требуется перезагрузка системы для полного отключения SELinux"
        return 0
    else
        print_error "Ошибка при настройке постоянного отключения SELinux"
        return 1
    fi
}

# Настройка временных зон
configure_timezone() {
    print_section "Настройка временной зоны: $TIMEZONE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка временной зоны: $TIMEZONE"
        return 0
    fi
    
    if run_sudo timedatectl set-timezone "$TIMEZONE"; then
        print_success "Временная зона настроена на $TIMEZONE"
    else
        print_warning "Не удалось настроить временную зону $TIMEZONE"
    fi
    
    # Настройка NTP
    if run_sudo systemctl enable --now chronyd; then
        print_success "Chronyd запущен и включен"
    else
        print_warning "Не удалось запустить chronyd"
    fi
    
    # Функция завершается успешно
    return 0
}

# Создание пользователей и групп
create_users_groups() {
    log_info "Создание пользователей и групп..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Создание пользователя $MONQ_USER"
        return 0
    fi
    
    # Создание пользователя monq если не существует
    if ! id "$MONQ_USER" &>/dev/null; then
        if run_sudo useradd -m -s /bin/bash "$MONQ_USER"; then
            log_info "Пользователь $MONQ_USER создан"
        else
            log_error "Ошибка при создании пользователя $MONQ_USER"
            return 1
        fi
    else
        log_info "Пользователь $MONQ_USER уже существует"
    fi
    
    # Добавление пользователя в группу wheel (для sudo)
    if run_sudo usermod -aG wheel "$MONQ_USER"; then
        log_info "Пользователь $MONQ_USER добавлен в группу wheel"
    else
        log_warn "Не удалось добавить пользователя $MONQ_USER в группу wheel"
    fi
}

# Настройка SSH
configure_ssh() {
    print_section "Настройка SSH"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка SSH"
        return 0
    fi
    
    # Запуск и включение SSH
    if run_sudo systemctl enable --now sshd; then
        print_success "SSH запущен и включен"
    else
        print_error "Ошибка при запуске SSH"
        return 1
    fi
    
    # Базовая настройка SSH
    local ssh_config="/etc/ssh/sshd_config"
    
    # Создание резервной копии
    run_sudo cp "$ssh_config" "$ssh_config.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Настройка SSH
    run_sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' "$ssh_config"
    run_sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' "$ssh_config"
    run_sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$ssh_config"
    
    # Перезапуск SSH
    if run_sudo systemctl restart sshd; then
        print_success "SSH настроен и перезапущен"
        return 0
    else
        print_error "Ошибка при перезапуске SSH"
        return 1
    fi
}



# Проверка результатов настройки
verify_setup() {
    print_section "Проверка результатов настройки"
    
    local checks=(
        "hostname"
        "ip addr show"
        "systemctl is-active sshd"
        "systemctl is-active chronyd"
        "run_sudo grep -q $HOSTNAME /etc/hosts"
    )
    
    local failed_checks=0
    
    for check in "${checks[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY-RUN] Проверка: $check"
            continue
        fi
        
        if eval "$check" &>/dev/null; then
            print_success "Проверка пройдена: $check"
        else
            print_warning "Проверка не пройдена: $check"
            failed_checks=$((failed_checks + 1))
        fi
    done
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Настройка базовой ОС для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/setup-os-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало настройки ОС для хоста: $HOSTNAME ($IP_ADDRESS)"
    log_info "Роль хоста: $ROLE"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов настройки
    local steps=(
        "update_system"
        "install_packages"
        "configure_hostname"
        "configure_dns"  # Настройка /etc/hosts
        "configure_firewall"
        "configure_selinux"
        "configure_timezone"
        # "create_users_groups"  # Отключено создание групп пользователей
        "configure_ssh"
        "verify_setup"
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
    
    log_info "Настройка ОС завершена успешно"
    
    if [[ "$DISABLE_SELINUX" == "true" ]]; then
        log_warn "ВНИМАНИЕ: Требуется перезагрузка системы для полного отключения SELinux"
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
