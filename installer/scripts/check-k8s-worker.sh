#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Kubernetes Worker
# =============================================================================
# Назначение: Проверка состояния рабочего узла Kubernetes
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
OUTPUT_FORMAT="text"  # text или json
VERBOSE=false
CHECK_ALL=true
CHECK_SYSTEM=true
CHECK_SERVICES=true
CHECK_NETWORK=true
CHECK_LOGS=false

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --format FORMAT          Формат вывода (text/json) (по умолчанию: text)
    --verbose                Подробный вывод
    --check-system           Проверка состояния системы
    --check-services         Проверка сервисов Kubernetes
    --check-network          Проверка сетевого подключения
    --check-logs             Проверка логов компонентов
    --all                    Проверка всех компонентов (по умолчанию)
    --help                   Показать эту справку

Примеры:
    $0 --format json --verbose
    $0 --check-system --check-services
    $0 --all --check-logs

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
            --check-system)
                CHECK_ALL=false
                CHECK_SYSTEM=true
                shift
                ;;
            --check-services)
                CHECK_ALL=false
                CHECK_SERVICES=true
                shift
                ;;
            --check-network)
                CHECK_ALL=false
                CHECK_NETWORK=true
                shift
                ;;
            --check-logs)
                CHECK_ALL=false
                CHECK_LOGS=true
                shift
                ;;
            --all)
                CHECK_ALL=true
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
    
    # Проверка формата вывода
    if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        log_error "Неподдерживаемый формат вывода: $OUTPUT_FORMAT (поддерживаются: text, json)"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Проверка состояния системы
check_system_status() {
    print_section "Проверка состояния системы"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local system_info=$(cat << EOF
{
    "hostname": "$(hostname)",
    "uptime": "$(uptime -p)",
    "memory": {
        "total": "$(free -h | awk 'NR==2{print $2}')",
        "used": "$(free -h | awk 'NR==2{print $3}')",
        "available": "$(free -h | awk 'NR==2{print $7}')"
    },
    "disk": {
        "usage": "$(df -h / | awk 'NR==2{print $5}')"
    },
    "load": "$(uptime | awk -F'load average:' '{print $2}')",
    "swap": {
        "enabled": $(swapon --show | grep -q . && echo "true" || echo "false")
    }
}
EOF
        )
        echo "$system_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Информация о системе:"
    print_info "  Hostname: $(hostname)"
    print_info "  Uptime: $(uptime -p)"
    print_info "  Memory: $(free -h | awk 'NR==2{printf "Total: %s, Used: %s, Available: %s", $2, $3, $7}')"
    print_info "  Disk usage: $(df -h / | awk 'NR==2{print $5}')"
    print_info "  Load average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Проверка swap
    if swapon --show | grep -q .; then
        print_warning "  Swap: активен (рекомендуется отключить для Kubernetes)"
    else
        print_success "  Swap: отключен"
    fi
    
    # Проверка статуса сервисов
    print_info "Статус сервисов Kubernetes:"
    local services=("kubelet" "containerd")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            print_success "  $service: активен"
        else
            print_error "  $service: неактивен"
        fi
    done
    
    # Проверка автозапуска сервисов
    print_info "Автозапуск сервисов:"
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            print_success "  $service: включен"
        else
            print_warning "  $service: отключен"
        fi
    done
    
    return 0
}

# Проверка сервисов Kubernetes
check_kubernetes_services() {
    print_section "Проверка сервисов Kubernetes"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local services_info=$(cat << EOF
{
    "kubelet": {
        "active": $(systemctl is-active kubelet &>/dev/null && echo "true" || echo "false"),
        "enabled": $(systemctl is-enabled kubelet &>/dev/null && echo "true" || echo "false"),
        "port_10250": $(check_port_common localhost 10250 5 && echo "true" || echo "false"),
        "port_10255": $(check_port_common localhost 10255 5 && echo "true" || echo "false")
    },
    "containerd": {
        "active": $(systemctl is-active containerd &>/dev/null && echo "true" || echo "false"),
        "enabled": $(systemctl is-enabled containerd &>/dev/null && echo "true" || echo "false")
    }
}
EOF
        )
        echo "$services_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка kubelet:"
    if systemctl is-active kubelet &>/dev/null; then
        print_success "  Статус: активен"
    else
        print_error "  Статус: неактивен"
    fi
    
    if systemctl is-enabled kubelet &>/dev/null; then
        print_success "  Автозапуск: включен"
    else
        print_warning "  Автозапуск: отключен"
    fi
    
    # Проверка портов kubelet
    if check_port_common localhost 10250 5; then
        print_success "  Порт 10250 (API): доступен"
    else
        print_error "  Порт 10250 (API): недоступен"
    fi
    
    if check_port_common localhost 10255 5; then
        print_success "  Порт 10255 (Read-only): доступен"
    else
        print_warning "  Порт 10255 (Read-only): недоступен"
    fi
    
    print_info "Проверка containerd:"
    if systemctl is-active containerd &>/dev/null; then
        print_success "  Статус: активен"
    else
        print_error "  Статус: неактивен"
    fi
    
    if systemctl is-enabled containerd &>/dev/null; then
        print_success "  Автозапуск: включен"
    else
        print_warning "  Автозапуск: отключен"
    fi
    
    
    return 0
}

# Проверка сетевого подключения
check_network_connectivity() {
    print_section "Проверка сетевого подключения"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local network_info=$(cat << EOF
{
    "local_ports": {
        "kubelet_api": {
            "port": 10250,
            "accessible": $(check_port_common localhost 10250 5 && echo "true" || echo "false")
        },
        "kubelet_readonly": {
            "port": 10255,
            "accessible": $(check_port_common localhost 10255 5 && echo "true" || echo "false")
        }
    },
    "network_interfaces": $(ip -j addr show | jq 'map({name: .ifname, addresses: .addr_info})'),
    "routing": $(ip -j route show | jq '.')
}
EOF
        )
        echo "$network_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка локальных портов:"
    
    # Проверка портов kubelet
    if check_port_common localhost 10250 5; then
        print_success "  kubelet API (10250): доступен"
    else
        print_error "  kubelet API (10250): недоступен"
    fi
    
    if check_port_common localhost 10255 5; then
        print_success "  kubelet Read-only (10255): доступен"
    else
        print_warning "  kubelet Read-only (10255): недоступен"
    fi
    
    # Проверка сетевых интерфейсов
    print_info "Сетевые интерфейсы:"
    ip addr show | grep -E "^[0-9]+:|inet " | while read line; do
        if [[ "$line" =~ ^[0-9]+: ]]; then
            print_info "  $line"
        elif [[ "$line" =~ inet ]]; then
            print_info "    $line"
        fi
    done
    
    # Проверка маршрутизации
    print_info "Маршрутизация:"
    ip route show | head -5 | while read route; do
        print_info "  $route"
    done
    
    # Проверка DNS
    print_info "Проверка DNS:"
    if nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        print_success "  DNS кластера: работает"
    else
        print_warning "  DNS кластера: не работает (может быть нормально, если узел не присоединен к кластеру)"
    fi
    
    return 0
}

# Проверка логов компонентов
check_component_logs() {
    print_section "Проверка логов компонентов Kubernetes"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local logs_info=$(cat << EOF
{
    "kubelet": {
        "recent_errors": $(journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i error | wc -l),
        "recent_warnings": $(journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i warning | wc -l)
    },
    "containerd": {
        "recent_errors": $(journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i error | wc -l),
        "recent_warnings": $(journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i warning | wc -l)
    }
}
EOF
        )
        echo "$logs_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка логов kubelet:"
    
    # Проверка последних ошибок
    local kubelet_errors=$(journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i error | wc -l)
    if [[ $kubelet_errors -gt 0 ]]; then
        print_warning "  Обнаружено $kubelet_errors ошибок в последних 50 записях"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "  Последние ошибки kubelet:"
            journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i error | tail -5
        fi
    else
        print_success "  Ошибок в логах kubelet не обнаружено"
    fi
    
    # Проверка последних предупреждений
    local kubelet_warnings=$(journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i warning | wc -l)
    if [[ $kubelet_warnings -gt 0 ]]; then
        print_warning "  Обнаружено $kubelet_warnings предупреждений в последних 50 записях"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "  Последние предупреждения kubelet:"
            journalctl -u kubelet --no-pager -n 50 2>/dev/null | grep -i warning | tail -5
        fi
    else
        print_success "  Предупреждений в логах kubelet не обнаружено"
    fi
    
    print_info "Проверка логов containerd:"
    
    # Проверка последних ошибок
    local containerd_errors=$(journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i error | wc -l)
    if [[ $containerd_errors -gt 0 ]]; then
        print_warning "  Обнаружено $containerd_errors ошибок в последних 50 записях"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "  Последние ошибки containerd:"
            journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i error | tail -5
        fi
    else
        print_success "  Ошибок в логах containerd не обнаружено"
    fi
    
    # Проверка последних предупреждений
    local containerd_warnings=$(journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i warning | wc -l)
    if [[ $containerd_warnings -gt 0 ]]; then
        print_warning "  Обнаружено $containerd_warnings предупреждений в последних 50 записях"
        if [[ "$VERBOSE" == "true" ]]; then
            print_info "  Последние предупреждения containerd:"
            journalctl -u containerd --no-pager -n 50 2>/dev/null | grep -i warning | tail -5
        fi
    else
        print_success "  Предупреждений в логах containerd не обнаружено"
    fi
    
    # Подробные логи в verbose режиме
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Последние 20 строк логов kubelet:"
        journalctl -u kubelet --no-pager -n 20
        
        print_info "Последние 20 строк логов containerd:"
        journalctl -u containerd --no-pager -n 20
    fi
    
    return 0
}

# Проверка контейнеров
check_containers() {
    print_section "Проверка контейнеров"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local containers_info=$(cat << EOF
{
    "containerd_containers": $(run_sudo crictl ps -a -o json 2>/dev/null || echo "[]")
}
EOF
        )
        echo "$containers_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка контейнеров containerd:"
    if command -v crictl &>/dev/null; then
        local containerd_containers=$(run_sudo crictl ps -a --no-trunc 2>/dev/null | wc -l)
        if [[ $containerd_containers -gt 1 ]]; then  # -1 для заголовка
            print_info "  Всего контейнеров: $((containerd_containers - 1))"
            run_sudo crictl ps -a
        else
            print_info "  Контейнеры не найдены"
        fi
    else
        print_warning "  crictl не установлен"
    fi
    
    
    return 0
}

# Проверка модулей ядра
check_kernel_modules() {
    print_section "Проверка модулей ядра"
    
    local required_modules=(
        "br_netfilter"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
        "nf_conntrack"
    )
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local modules_info="{"
        for module in "${required_modules[@]}"; do
            local loaded=$(lsmod | grep -q "^$module " && echo "true" || echo "false")
            modules_info+="\"$module\": $loaded,"
        done
        modules_info="${modules_info%,}"
        modules_info+="}"
        echo "$modules_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка загруженных модулей ядра:"
    for module in "${required_modules[@]}"; do
        if lsmod | grep -q "^$module "; then
            print_success "  $module: загружен"
        else
            print_warning "  $module: не загружен"
        fi
    done
    
    return 0
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Проверка состояния Kubernetes Worker"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-k8s-worker-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки состояния Kubernetes Worker"
    log_info "Формат вывода: $OUTPUT_FORMAT"
    log_info "Подробный режим: $VERBOSE"
    log_info "Проверка всех компонентов: $CHECK_ALL"
    
    # Выполнение проверок
    local checks=()
    
    if [[ "$CHECK_ALL" == "true" ]]; then
        checks=(
            "check_system_status"
            "check_kubernetes_services"
            "check_network_connectivity"
            "check_containers"
            "check_kernel_modules"
            "check_component_logs"
        )
    else
        if [[ "$CHECK_SYSTEM" == "true" ]]; then
            checks+=("check_system_status")
        fi
        if [[ "$CHECK_SERVICES" == "true" ]]; then
            checks+=("check_kubernetes_services")
        fi
        if [[ "$CHECK_NETWORK" == "true" ]]; then
            checks+=("check_network_connectivity")
        fi
        if [[ "$CHECK_LOGS" == "true" ]]; then
            checks+=("check_component_logs")
        fi
    fi
    
    local total_checks=${#checks[@]}
    local current_check=0
    local failed_checks=0
    
    for check in "${checks[@]}"; do
        current_check=$((current_check + 1))
        show_progress $current_check $total_checks "Выполнение: $check"
        
        if ! $check; then
            log_error "Ошибка при выполнении проверки: $check"
            failed_checks=$((failed_checks + 1))
        fi
    done
    
    # Итоговый отчет
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local summary=$(cat << EOF
{
    "summary": {
        "total_checks": $total_checks,
        "failed_checks": $failed_checks,
        "success_rate": "$(( (total_checks - failed_checks) * 100 / total_checks ))%",
        "timestamp": "$(date -Iseconds)"
    }
}
EOF
        )
        echo "$summary" | jq '.'
    else
        echo
        print_section "Итоговый отчет"
        print_info "Всего проверок: $total_checks"
        print_info "Неудачных проверок: $failed_checks"
        
        if [[ $failed_checks -eq 0 ]]; then
            print_success "Все проверки пройдены успешно"
        else
            print_warning "Провалено $failed_checks проверок"
        fi
        
        echo
        echo -e "${BLUE}Лог файл:${NC} $log_file"
    fi
    
    log_info "Проверка состояния Kubernetes Worker завершена"
    log_info "Всего проверок: $total_checks"
    log_info "Неудачных проверок: $failed_checks"
    log_info "Лог файл: $log_file"
    
    exit $failed_checks
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
