#!/bin/bash
# =============================================================================
# Скрипт проверки состояния операционной системы
# =============================================================================
# Назначение: Проверка состояния ОС, пакетов, сети и сервисов
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

# Проверка версии ОС
check_os_version() {
    local os_info=""
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_info="$NAME $VERSION"
    else
        os_info="Неизвестная ОС"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"os_version\": \"$os_info\","
    else
        print_section "Версия ОС:"
        print_info "$os_info"
    fi
}

# Проверка установленных пакетов
check_installed_packages() {
    local required_packages=(
        "curl"
        "wget"
        "net-tools"
        "bind-utils"
        "telnet"
        "tcpdump"
        "rsync"
        "unzip"
        "tar"
        "gzip"
        "openssh-clients"
        "openssh-server"
        "chrony"
        "jq"
        "bc"
        "yum-utils"
        "device-mapper-persistent-data"
        "lvm2"
    )
    
    local missing_packages=()
    local installed_packages=()
    
    for package in "${required_packages[@]}"; do
        if rpm -q "$package" &>/dev/null; then
            installed_packages+=("$package")
        else
            missing_packages+=("$package")
        fi
    done
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"packages\": {"
        echo "        \"installed\": ["
        for package in "${installed_packages[@]}"; do
            echo "            \"$package\","
        done
        echo "        ],"
        echo "        \"missing\": ["
        for package in "${missing_packages[@]}"; do
            echo "            \"$package\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Установленные пакеты:"
        print_info "${#installed_packages[@]}/${#required_packages[@]} пакетов установлено"
        
        if [[ ${#missing_packages[@]} -gt 0 ]]; then
            print_warning "Отсутствующие пакеты: ${missing_packages[*]}"
        else
            print_success "Все необходимые пакеты установлены"
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo
            print_info "Список установленных пакетов:"
            for package in "${installed_packages[@]}"; do
                print_success "  $package"
            done
        fi
    fi
}

# Проверка настроек сети
check_network_settings() {
    local hostname=$(hostname)
    local ip_address=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || echo "Не определен")
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"network\": {"
        echo "        \"hostname\": \"$hostname\","
        echo "        \"ip_address\": \"$ip_address\","
        echo "        \"gateway\": \"$gateway\","
        echo "        \"dns_servers\": \"$dns_servers\""
        echo "    },"
    else
        print_section "Настройки сети:"
        print_info "Hostname: $hostname"
        print_info "IP адрес: $ip_address"
        print_info "Шлюз: $gateway"
        print_info "DNS серверы: $dns_servers"
    fi
}

# Проверка статуса сервисов
check_services_status() {
    local services=(
        "sshd"
        "chronyd"
        "NetworkManager"
    )
    
    local active_services=()
    local inactive_services=()
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            active_services+=("$service")
        else
            inactive_services+=("$service")
        fi
    done
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"services\": {"
        echo "        \"active\": ["
        for service in "${active_services[@]}"; do
            echo "            \"$service\","
        done
        echo "        ],"
        echo "        \"inactive\": ["
        for service in "${inactive_services[@]}"; do
            echo "            \"$service\","
        done
        echo "        ]"
        echo "    },"
    else
        print_section "Статус сервисов:"
        print_info "${#active_services[@]}/${#services[@]} сервисов активны"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo
            print_info "Активные сервисы:"
            for service in "${active_services[@]}"; do
                print_success "  $service"
            done
        fi
        
        if [[ ${#inactive_services[@]} -gt 0 ]]; then
            print_warning "Неактивные сервисы: ${inactive_services[*]}"
        else
            print_success "Все необходимые сервисы активны"
        fi
    fi
}

# Проверка дискового пространства
check_disk_space() {
    local disk_info=$(df -h / | tail -1)
    local total=$(echo "$disk_info" | awk '{print $2}')
    local used=$(echo "$disk_info" | awk '{print $3}')
    local available=$(echo "$disk_info" | awk '{print $4}')
    local usage_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"disk_space\": {"
        echo "        \"total\": \"$total\","
        echo "        \"used\": \"$used\","
        echo "        \"available\": \"$available\","
        echo "        \"usage_percent\": $usage_percent"
        echo "    },"
    else
        print_section "Дисковое пространство:"
        print_info "Всего: $total"
        print_info "Использовано: $used"
        print_info "Доступно: $available"
        print_info "Использование: $usage_percent%"
        
        if [[ $usage_percent -gt 90 ]]; then
            print_error "ВНИМАНИЕ: Диск заполнен более чем на 90%"
        elif [[ $usage_percent -gt 80 ]]; then
            print_warning "Предупреждение: Диск заполнен более чем на 80%"
        else
            print_success "Дисковое пространство в норме"
        fi
    fi
}

# Проверка памяти
check_memory() {
    local mem_info=$(free -h)
    local total_mem=$(echo "$mem_info" | grep Mem | awk '{print $2}')
    local used_mem=$(echo "$mem_info" | grep Mem | awk '{print $3}')
    local available_mem=$(echo "$mem_info" | grep Mem | awk '{print $7}')
    
    # Получение процента использования памяти
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"memory\": {"
        echo "        \"total\": \"$total_mem\","
        echo "        \"used\": \"$used_mem\","
        echo "        \"available\": \"$available_mem\","
        echo "        \"usage_percent\": $mem_usage"
        echo "    },"
    else
        print_section "Память:"
        print_info "Всего: $total_mem"
        print_info "Использовано: $used_mem"
        print_info "Доступно: $available_mem"
        print_info "Использование: ${mem_usage}%"
        
        # Проверка использования памяти без bc
        local mem_usage_int=$(echo "$mem_usage" | cut -d. -f1)
        if [[ $mem_usage_int -gt 90 ]]; then
            print_error "ВНИМАНИЕ: Память используется более чем на 90%"
        elif [[ $mem_usage_int -gt 80 ]]; then
            print_warning "Предупреждение: Память используется более чем на 80%"
        else
            print_success "Использование памяти в норме"
        fi
    fi
}

# Проверка CPU
check_cpu() {
    local cpu_info=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"cpu\": {"
        echo "        \"model\": \"$cpu_info\","
        echo "        \"cores\": $cpu_cores,"
        echo "        \"load_average\": \"$load_avg\""
        echo "    },"
    else
        print_section "CPU:"
        print_info "Модель: $cpu_info"
        print_info "Ядра: $cpu_cores"
        print_info "Средняя загрузка: $load_avg"
    fi
}

# Проверка файрвола
check_firewall() {
    local firewall_status=""
    local firewall_rules=""
    
    if systemctl is-active firewalld &>/dev/null; then
        firewall_status="active"
        if command -v firewall-cmd &>/dev/null; then
            firewall_rules=$(firewall-cmd --list-all 2>/dev/null | head -10)
        fi
    else
        firewall_status="inactive"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"firewall\": {"
        echo "        \"status\": \"$firewall_status\","
        echo "        \"expected\": \"inactive\""
        echo "    },"
    else
        print_section "Файрвол:"
        if [[ "$firewall_status" == "inactive" ]]; then
            print_success "Статус: $firewall_status (ожидается отключен)"
        else
            print_warning "Статус: $firewall_status (ожидается отключен)"
        fi
    fi
}

# Проверка SELinux
check_selinux() {
    local selinux_status=""
    local selinux_mode=""
    
    if command -v getenforce &>/dev/null; then
        selinux_status=$(getenforce 2>/dev/null || echo "unknown")
        selinux_mode=$(cat /etc/selinux/config 2>/dev/null | grep "^SELINUX=" | cut -d= -f2 || echo "unknown")
    else
        selinux_status="not_installed"
        selinux_mode="not_installed"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"selinux\": {"
        echo "        \"current_status\": \"$selinux_status\","
        echo "        \"configured_mode\": \"$selinux_mode\","
        echo "        \"expected\": \"disabled\""
        echo "    },"
    else
        print_section "SELinux:"
        print_info "Текущий статус: $selinux_status"
        print_info "Настроенный режим: $selinux_mode"
        
        if [[ "$selinux_status" == "Disabled" && "$selinux_mode" == "disabled" ]]; then
            print_success "SELinux отключен (ожидается отключен)"
        else
            print_warning "SELinux не отключен (ожидается отключен)"
        fi
    fi
}

# Проверка временной зоны
check_timezone() {
    local timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    local ntp_sync=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "unknown")
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"timezone\": {"
        echo "        \"timezone\": \"$timezone\","
        echo "        \"ntp_synchronized\": \"$ntp_sync\""
        echo "    },"
    else
        print_section "Временная зона:"
        print_info "Зона: $timezone"
        if [[ "$ntp_sync" == "yes" ]]; then
            print_success "NTP синхронизация: $ntp_sync"
        else
            print_warning "NTP синхронизация: $ntp_sync"
        fi
    fi
}

# Проверка пользователей
check_users() {
    local monq_user_exists=""
    local monq_user_groups=""
    
    if id "$MONQ_USER" &>/dev/null; then
        monq_user_exists="true"
        monq_user_groups=$(groups "$MONQ_USER" 2>/dev/null | cut -d: -f2 | xargs)
    else
        monq_user_exists="false"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "    \"users\": {"
        echo "        \"monq_user_exists\": $monq_user_exists,"
        echo "        \"monq_user_groups\": \"$monq_user_groups\""
        echo "    },"
    else
        print_section "Пользователи:"
        if [[ "$monq_user_exists" == "true" ]]; then
            print_success "Пользователь $MONQ_USER: существует"
            print_info "Группы пользователя $MONQ_USER: $monq_user_groups"
        else
            print_warning "Пользователь $MONQ_USER: не существует"
        fi
    fi
}



# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Проверка состояния ОС"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-os-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки состояния ОС"
    log_info "Формат вывода: $OUTPUT_FORMAT"
    log_info "Подробный режим: $VERBOSE"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{"
        echo "    \"timestamp\": \"$(date -Iseconds)\","
        echo "    \"hostname\": \"$(hostname)\","
    fi
    
    # Выполнение проверок
    local checks=(
        "check_os_version"
        "check_installed_packages"
        "check_network_settings"
        "check_services_status"
        "check_disk_space"
        "check_memory"
        "check_cpu"
        "check_firewall"
        "check_selinux"
        "check_timezone"
#        "check_users"
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
    
    log_info "Проверка состояния ОС завершена"
    log_info "Лог файл: $log_file"
    
    # Успешное завершение
    exit 0
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
