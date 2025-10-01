#!/bin/bash
# =============================================================================
# Скрипт сброса кластера Kubernetes
# =============================================================================
# Назначение: Полное удаление кластера Kubernetes для повторной инициализации
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

DRY_RUN=false
FORCE=false
INTERACTIVE=false

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --dry-run             Режим симуляции (без выполнения команд)
    --force               Принудительное выполнение (без подтверждений)
    --interactive         Принудительный интерактивный режим
    --help                Показать эту справку

Примеры:
    $0                    Сброс кластера с подтверждением
    $0 --dry-run          Симуляция сброса кластера
    $0 --force            Принудительный сброс без подтверждений
    $0 --interactive      Интерактивный режим (даже через SSH)

ВНИМАНИЕ: Этот скрипт полностью удалит кластер Kubernetes!

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --interactive)
                INTERACTIVE=true
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

# Подтверждение выполнения
confirm_reset() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    print_warning "ВНИМАНИЕ: Этот скрипт полностью удалит кластер Kubernetes!"
    print_warning "Все данные кластера будут потеряны!"
    echo
    
    # Проверяем, запущен ли скрипт в интерактивном режиме
    if [[ "$INTERACTIVE" == "true" ]] || [[ -t 0 ]]; then
        # Интерактивный режим - показываем запрос
        read -p "Вы уверены, что хотите продолжить? (yes/no): " -r
        echo
        
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            return 0
        else
            print_info "Операция отменена"
            exit 0
        fi
    else
        # Неинтерактивный режим (SSH) - показываем предупреждение и продолжаем
        print_warning "Неинтерактивный режим: автоматическое продолжение через 10 секунд..."
        print_warning "Для отмены нажмите Ctrl+C"
        print_warning "Для интерактивного режима используйте флаг --interactive"
        
        # Обратный отсчет
        for i in {10..1}; do
            printf "\rПродолжение через %d секунд... " "$i"
            sleep 1
        done
        echo
        print_info "Продолжение выполнения..."
        return 0
    fi
}

# Остановка и удаление контейнеров
stop_containers() {
    print_section "Остановка и удаление контейнеров"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Остановка контейнеров"
        return 0
    fi
    
    # Остановка всех контейнеров containerd
    if command -v crictl >/dev/null 2>&1; then
        print_info "Остановка контейнеров через crictl..."
        if run_sudo crictl ps -q | xargs -r run_sudo crictl stop; then
            print_success "Контейнеры остановлены"
        else
            print_warning "Не удалось остановить некоторые контейнеры"
        fi
        
        # Удаление всех контейнеров
        if run_sudo crictl ps -aq | xargs -r run_sudo crictl rm; then
            print_success "Контейнеры удалены"
        else
            print_warning "Не удалось удалить некоторые контейнеры"
        fi
    else
        print_info "crictl не найден, пропускаем остановку контейнеров"
    fi
}

# Сброс kubeadm
reset_kubeadm() {
    print_section "Сброс kubeadm"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Выполнение: kubeadm reset --force"
        return 0
    fi
    
    if run_sudo kubeadm reset --force; then
        print_success "kubeadm сброшен"
    else
        print_error "Ошибка при сбросе kubeadm"
        return 1
    fi
}

# Очистка iptables правил
cleanup_iptables() {
    print_section "Очистка iptables правил"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка iptables правил"
        return 0
    fi
    
    # Очистка iptables правил
    if run_sudo iptables -F; then
        print_success "iptables правила очищены"
    else
        print_warning "Не удалось очистить iptables правила"
    fi
    
    if run_sudo iptables -t nat -F; then
        print_success "iptables NAT правила очищены"
    else
        print_warning "Не удалось очистить iptables NAT правила"
    fi
    
    if run_sudo iptables -t mangle -F; then
        print_success "iptables mangle правила очищены"
    else
        print_warning "Не удалось очистить iptables mangle правила"
    fi
    
    if run_sudo iptables -X; then
        print_success "iptables цепочки удалены"
    else
        print_warning "Не удалось удалить iptables цепочки"
    fi
}

# Очистка IPVS правил
cleanup_ipvs() {
    print_section "Очистка IPVS правил"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка IPVS правил"
        return 0
    fi
    
    if command -v ipvsadm >/dev/null 2>&1; then
        if run_sudo ipvsadm -C; then
            print_success "IPVS правила очищены"
        else
            print_warning "Не удалось очистить IPVS правила"
        fi
    else
        print_info "ipvsadm не найден, пропускаем очистку IPVS"
    fi
}

# Остановка сервисов
stop_services() {
    print_section "Остановка сервисов Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Остановка сервисов"
        return 0
    fi
    
    local services=("kubelet" "containerd")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            if run_sudo systemctl stop "$service"; then
                print_success "$service остановлен"
            else
                print_warning "Не удалось остановить $service"
            fi
        else
            print_info "$service уже остановлен"
        fi
    done
}

# Удаление конфигурационных файлов
remove_config_files() {
    print_section "Удаление конфигурационных файлов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление конфигурационных файлов"
        return 0
    fi
    
    local config_dirs=(
        "/etc/kubernetes"
        "/var/lib/kubelet"
        "/var/lib/etcd"
        "/etc/cni/net.d"
        "/opt/cni/bin"
        "/var/lib/cni"
        "/var/lib/calico"
        "/var/lib/flannel"
        "/etc/systemd/system/kubelet.service.d"
        "/etc/systemd/system/containerd.service.d"
    )
    
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if run_sudo rm -rf "$dir"; then
                print_success "Удален: $dir"
            else
                print_warning "Не удалось удалить: $dir"
            fi
        else
            print_info "Директория не существует: $dir"
        fi
    done
}

# Очистка сетевых интерфейсов
cleanup_network_interfaces() {
    print_section "Очистка сетевых интерфейсов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка сетевых интерфейсов"
        return 0
    fi
    
    # Удаление CNI интерфейсов
    local interfaces=("cni0" "flannel.1" "cali0" "cilium_host" "cilium_net" "cilium_vxlan")
    
    for iface in "${interfaces[@]}"; do
        if ip link show "$iface" &>/dev/null; then
            if run_sudo ip link delete "$iface"; then
                print_success "Удален интерфейс: $iface"
            else
                print_warning "Не удалось удалить интерфейс: $iface"
            fi
        fi
    done
}

# Очистка модулей ядра
cleanup_kernel_modules() {
    print_section "Очистка модулей ядра"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка модулей ядра"
        return 0
    fi
    
    local modules=("ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh" "nf_conntrack")
    
    for module in "${modules[@]}"; do
        if lsmod | grep -q "$module"; then
            if run_sudo modprobe -r "$module"; then
                print_success "Выгружен модуль: $module"
            else
                print_warning "Не удалось выгрузить модуль: $module"
            fi
        fi
    done
}

# Очистка Docker (если установлен)
cleanup_docker() {
    print_section "Очистка Docker (если установлен)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка Docker"
        return 0
    fi
    
    if command -v docker >/dev/null 2>&1; then
        print_info "Docker найден, выполняется очистка..."
        
        # Остановка всех контейнеров
        if run_sudo docker stop $(run_sudo docker ps -aq) 2>/dev/null; then
            print_success "Docker контейнеры остановлены"
        fi
        
        # Удаление всех контейнеров
        if run_sudo docker rm $(run_sudo docker ps -aq) 2>/dev/null; then
            print_success "Docker контейнеры удалены"
        fi
        
        # Удаление всех образов
        if run_sudo docker rmi $(run_sudo docker images -q) 2>/dev/null; then
            print_success "Docker образы удалены"
        fi
        
        # Очистка системы Docker
        if run_sudo docker system prune -af; then
            print_success "Docker система очищена"
        fi
    else
        print_info "Docker не найден, пропускаем очистку"
    fi
}

# Перезапуск сервисов
restart_services() {
    print_section "Перезапуск сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Перезапуск сервисов"
        return 0
    fi
    
    # Перезапуск containerd
    if run_sudo systemctl restart containerd; then
        print_success "containerd перезапущен"
    else
        print_warning "Не удалось перезапустить containerd"
    fi
    
    # Перезапуск kubelet
    if run_sudo systemctl restart kubelet; then
        print_success "kubelet перезапущен"
    else
        print_warning "Не удалось перезапустить kubelet"
    fi
}

# Проверка очистки
verify_cleanup() {
    print_section "Проверка очистки"
    
    local checks=(
        "! systemctl is-active kubelet"
        "! systemctl is-active containerd"
        "! ls /etc/kubernetes"
        "! ls /var/lib/kubelet"
        "! ip link show cni0"
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
        print_success "Кластер успешно сброшен"
        return 0
    else
        print_warning "Некоторые компоненты не были полностью очищены"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Сброс кластера Kubernetes"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Подтверждение выполнения
    confirm_reset
    
    # Инициализация логирования
    local log_file="$LOG_DIR/reset-k8s-cluster-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало сброса кластера Kubernetes"
    log_info "Режим симуляции: $DRY_RUN"
    log_info "Принудительный режим: $FORCE"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов сброса
    local steps=(
        "stop_containers"
        "reset_kubeadm"
        "cleanup_iptables"
        "cleanup_ipvs"
        "stop_services"
        "remove_config_files"
        "cleanup_network_interfaces"
        "cleanup_kernel_modules"
        "cleanup_docker"
        "restart_services"
        "verify_cleanup"
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
    
    log_info "Сброс кластера завершен"
    log_info "Теперь можно заново инициализировать кластер"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
