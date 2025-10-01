#!/bin/bash
# =============================================================================
# Скрипт проверки состояния Kubernetes Controller
# =============================================================================
# Назначение: Проверка состояния контроллерного узла Kubernetes
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
CHECK_NODES=true
CHECK_PODS=true
CHECK_SERVICES=true
CHECK_DEPLOYMENTS=true
CHECK_EVENTS=true
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
    --check-nodes            Проверка узлов кластера
    --check-pods             Проверка подов
    --check-services         Проверка сервисов
    --check-deployments      Проверка deployments
    --check-events           Проверка событий кластера
    --check-logs             Проверка логов компонентов
    --all                    Проверка всех компонентов (по умолчанию)
    --help                   Показать эту справку

Примеры:
    $0 --format json --verbose
    $0 --check-nodes --check-pods
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
            --check-nodes)
                CHECK_ALL=false
                CHECK_NODES=true
                shift
                ;;
            --check-pods)
                CHECK_ALL=false
                CHECK_PODS=true
                shift
                ;;
            --check-services)
                CHECK_ALL=false
                CHECK_SERVICES=true
                shift
                ;;
            --check-deployments)
                CHECK_ALL=false
                CHECK_DEPLOYMENTS=true
                shift
                ;;
            --check-events)
                CHECK_ALL=false
                CHECK_EVENTS=true
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

# Проверка доступности kubectl
check_kubectl_availability() {
    if ! command -v kubectl &>/dev/null; then
        print_error "kubectl не установлен или недоступен"
        return 1
    fi
    
    # Проверка подключения к кластеру
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Не удалось подключиться к кластеру Kubernetes"
        print_info "Убедитесь, что:"
        print_info "  1. Кластер инициализирован"
        print_info "  2. kubeconfig настроен правильно"
        print_info "  3. API сервер доступен"
        return 1
    fi
    
    return 0
}

# Проверка узлов кластера
check_cluster_nodes() {
    print_section "Проверка узлов кластера"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local nodes_json=$(kubectl get nodes -o json 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$nodes_json" | jq '.'
        else
            echo '{"error": "Не удалось получить информацию об узлах"}'
        fi
        return 0
    fi
    
    # Текстовый вывод
    print_info "Список узлов кластера:"
    if kubectl get nodes -o wide; then
        print_success "Информация об узлах получена"
    else
        print_error "Не удалось получить информацию об узлах"
        return 1
    fi
    
    # Проверка готовности узлов
    print_info "Проверка готовности узлов:"
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    
    if [[ $ready_nodes -eq $total_nodes ]]; then
        print_success "Все узлы готовы ($ready_nodes/$total_nodes)"
    else
        print_warning "Не все узлы готовы ($ready_nodes/$total_nodes)"
    fi
    
    # Детальная информация об узлах
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Детальная информация об узлах:"
        kubectl describe nodes
    fi
    
    return 0
}

# Проверка подов
check_cluster_pods() {
    print_section "Проверка подов кластера"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local pods_json=$(kubectl get pods --all-namespaces -o json 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$pods_json" | jq '.'
        else
            echo '{"error": "Не удалось получить информацию о подах"}'
        fi
        return 0
    fi
    
    # Текстовый вывод
    print_info "Список подов по namespace:"
    if kubectl get pods --all-namespaces; then
        print_success "Информация о подах получена"
    else
        print_error "Не удалось получить информацию о подах"
        return 1
    fi
    
    # Проверка статуса подов
    print_info "Статистика подов:"
    local running_pods=$(kubectl get pods --all-namespaces --no-headers | grep -c "Running")
    local pending_pods=$(kubectl get pods --all-namespaces --no-headers | grep -c "Pending")
    local failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -c "Failed\|Error\|CrashLoopBackOff")
    local total_pods=$(kubectl get pods --all-namespaces --no-headers | wc -l)
    
    print_info "  Всего подов: $total_pods"
    print_info "  Запущенных: $running_pods"
    print_info "  Ожидающих: $pending_pods"
    print_info "  Ошибок: $failed_pods"
    
    if [[ $failed_pods -gt 0 ]]; then
        print_warning "Обнаружены поды с ошибками:"
        kubectl get pods --all-namespaces --no-headers | grep -E "Failed|Error|CrashLoopBackOff"
    fi
    
    # Проверка системных подов
    print_info "Проверка системных подов:"
    local system_pods=$(kubectl get pods -n kube-system --no-headers | wc -l)
    local system_running=$(kubectl get pods -n kube-system --no-headers | grep -c "Running")
    
    if [[ $system_running -eq $system_pods ]]; then
        print_success "Все системные поды запущены ($system_running/$system_pods)"
    else
        print_warning "Не все системные поды запущены ($system_running/$system_pods)"
        kubectl get pods -n kube-system
    fi
    
    # Детальная информация о проблемных подах
    if [[ "$VERBOSE" == "true" && $failed_pods -gt 0 ]]; then
        print_info "Детальная информация о проблемных подах:"
        kubectl get pods --all-namespaces --no-headers | grep -E "Failed|Error|CrashLoopBackOff" | while read namespace pod_name rest; do
            print_info "Проблемный под: $namespace/$pod_name"
            kubectl describe pod "$pod_name" -n "$namespace"
        done
    fi
    
    return 0
}

# Проверка сервисов
check_cluster_services() {
    print_section "Проверка сервисов кластера"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local services_json=$(kubectl get services --all-namespaces -o json 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$services_json" | jq '.'
        else
            echo '{"error": "Не удалось получить информацию о сервисах"}'
        fi
        return 0
    fi
    
    # Текстовый вывод
    print_info "Список сервисов по namespace:"
    if kubectl get services --all-namespaces; then
        print_success "Информация о сервисах получена"
    else
        print_error "Не удалось получить информацию о сервисах"
        return 1
    fi
    
    # Проверка системных сервисов
    print_info "Проверка системных сервисов:"
    local system_services=$(kubectl get services -n kube-system --no-headers | wc -l)
    print_info "  Системных сервисов: $system_services"
    
    # Проверка сервисов с внешними IP
    local external_services=$(kubectl get services --all-namespaces --no-headers | grep -c "<external>")
    if [[ $external_services -gt 0 ]]; then
        print_info "  Сервисов с внешними IP: $external_services"
    fi
    
    # Детальная информация о сервисах
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Детальная информация о сервисах:"
        kubectl describe services --all-namespaces
    fi
    
    return 0
}

# Проверка deployments
check_cluster_deployments() {
    print_section "Проверка deployments кластера"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local deployments_json=$(kubectl get deployments --all-namespaces -o json 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$deployments_json" | jq '.'
        else
            echo '{"error": "Не удалось получить информацию о deployments"}'
        fi
        return 0
    fi
    
    # Текстовый вывод
    print_info "Список deployments по namespace:"
    if kubectl get deployments --all-namespaces; then
        print_success "Информация о deployments получена"
    else
        print_error "Не удалось получить информацию о deployments"
        return 1
    fi
    
    # Проверка готовности deployments
    print_info "Проверка готовности deployments:"
    local ready_deployments=$(kubectl get deployments --all-namespaces --no-headers | awk '$2==$4 && $3==$5 {count++} END {print count+0}')
    local total_deployments=$(kubectl get deployments --all-namespaces --no-headers | wc -l)
    
    if [[ $ready_deployments -eq $total_deployments ]]; then
        print_success "Все deployments готовы ($ready_deployments/$total_deployments)"
    else
        print_warning "Не все deployments готовы ($ready_deployments/$total_deployments)"
    fi
    
    # Детальная информация о проблемных deployments
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Детальная информация о deployments:"
        kubectl describe deployments --all-namespaces
    fi
    
    return 0
}

# Проверка событий кластера
check_cluster_events() {
    print_section "Проверка событий кластера"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local events_json=$(kubectl get events --all-namespaces -o json 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "$events_json" | jq '.'
        else
            echo '{"error": "Не удалось получить информацию о событиях"}'
        fi
        return 0
    fi
    
    # Текстовый вывод
    print_info "Последние события кластера:"
    if kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20; then
        print_success "Информация о событиях получена"
    else
        print_error "Не удалось получить информацию о событиях"
        return 1
    fi
    
    # Проверка событий с ошибками
    print_info "События с ошибками:"
    local error_events=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers | wc -l)
    if [[ $error_events -gt 0 ]]; then
        print_warning "Обнаружено $error_events событий с предупреждениями:"
        kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10
    else
        print_success "Событий с ошибками не обнаружено"
    fi
    
    return 0
}

# Проверка логов компонентов
check_component_logs() {
    print_section "Проверка логов компонентов Kubernetes"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local logs_json="{}"
        echo "$logs_json" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    local components=(
        "kube-apiserver"
        "kube-controller-manager"
        "kube-scheduler"
        "etcd"
    )
    
    for component in "${components[@]}"; do
        print_info "Проверка логов $component:"
        
        # Поиск пода с компонентом
        local pod_name=$(kubectl get pods -n kube-system --no-headers | grep "$component" | head -1 | awk '{print $1}')
        
        if [[ -n "$pod_name" ]]; then
            print_info "  Под: $pod_name"
            
            # Проверка последних логов
            if kubectl logs "$pod_name" -n kube-system --tail=10 2>/dev/null | grep -i error; then
                print_warning "  Обнаружены ошибки в логах $component"
            else
                print_success "  Ошибок в логах $component не обнаружено"
            fi
            
            # Подробные логи в verbose режиме
            if [[ "$VERBOSE" == "true" ]]; then
                print_info "  Последние 20 строк логов $component:"
                kubectl logs "$pod_name" -n kube-system --tail=20
            fi
        else
            print_warning "  Под с компонентом $component не найден"
        fi
    done
    
    return 0
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
    "load": "$(uptime | awk -F'load average:' '{print $2}')"
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
    
    return 0
}

# Проверка сетевого подключения
check_network_connectivity() {
    print_section "Проверка сетевого подключения"
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local network_info=$(cat << EOF
{
    "api_server": {
        "port": 6443,
        "accessible": $(check_port_common localhost 6443 5 && echo "true" || echo "false")
    },
    "etcd": {
        "port": 2379,
        "accessible": $(check_port_common localhost 2379 5 && echo "true" || echo "false")
    }
}
EOF
        )
        echo "$network_info" | jq '.'
        return 0
    fi
    
    # Текстовый вывод
    print_info "Проверка доступности портов:"
    
    # Проверка API сервера
    if check_port_common localhost 6443 5; then
        print_success "  API сервер (6443): доступен"
    else
        print_error "  API сервер (6443): недоступен"
    fi
    
    # Проверка etcd
    if check_port_common localhost 2379 5; then
        print_success "  etcd (2379): доступен"
    else
        print_error "  etcd (2379): недоступен"
    fi
    
    # Проверка kubelet
    if check_port_common localhost 10250 5; then
        print_success "  kubelet (10250): доступен"
    else
        print_error "  kubelet (10250): недоступен"
    fi
    
    return 0
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Проверка состояния Kubernetes Controller"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/check-k8s-controller-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало проверки состояния Kubernetes Controller"
    log_info "Формат вывода: $OUTPUT_FORMAT"
    log_info "Подробный режим: $VERBOSE"
    log_info "Проверка всех компонентов: $CHECK_ALL"
    
    # Проверка доступности kubectl
    if ! check_kubectl_availability; then
        log_error "kubectl недоступен или кластер недоступен"
        exit 1
    fi
    
    # Выполнение проверок
    local checks=()
    
    if [[ "$CHECK_ALL" == "true" ]]; then
        checks=(
            "check_system_status"
            "check_network_connectivity"
            "check_cluster_nodes"
            "check_cluster_pods"
            "check_cluster_services"
            "check_cluster_deployments"
            "check_cluster_events"
        )
    else
        if [[ "$CHECK_NODES" == "true" ]]; then
            checks+=("check_cluster_nodes")
        fi
        if [[ "$CHECK_PODS" == "true" ]]; then
            checks+=("check_cluster_pods")
        fi
        if [[ "$CHECK_SERVICES" == "true" ]]; then
            checks+=("check_cluster_services")
        fi
        if [[ "$CHECK_DEPLOYMENTS" == "true" ]]; then
            checks+=("check_cluster_deployments")
        fi
        if [[ "$CHECK_EVENTS" == "true" ]]; then
            checks+=("check_cluster_events")
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
    
    log_info "Проверка состояния Kubernetes Controller завершена"
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
