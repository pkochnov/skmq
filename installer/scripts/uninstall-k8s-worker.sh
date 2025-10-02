#!/bin/bash
# =============================================================================
# Скрипт удаления Kubernetes Worker
# =============================================================================
# Назначение: Удаление рабочего узла Kubernetes из кластера
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
DRY_RUN=false
FORCE=false
PAUSE_AFTER_STEP=false
CLEANUP_STORAGE=false
CLEANUP_CONFIG=false

# =============================================================================
# Функции скрипта
# =============================================================================

# Функция паузы после этапа
pause_after_step() {
    if [[ "$PAUSE_AFTER_STEP" == "true" ]]; then
        echo
        echo -e "${YELLOW}${BOLD}Нажмите Enter для продолжения или Ctrl+C для выхода...${NC}"
        read -r
    fi
}

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --dry-run               Режим симуляции (без выполнения команд)
    --force                 Принудительное выполнение (без подтверждений)
    --pause                 Пауза после каждого этапа удаления
    --cleanup-storage       Удалить данные хранилища (монтирование, файловые системы)
    --cleanup-config        Удалить конфигурационные файлы
    --help                  Показать эту справку

Примеры:
    $0                      Удаление узла с подтверждением
    $0 --dry-run            Симуляция удаления узла
    $0 --force              Принудительное удаление без подтверждений
    $0 --cleanup-storage    Удаление с очисткой хранилища
    $0 --cleanup-config     Удаление с очисткой конфигурации

ВНИМАНИЕ: Этот скрипт удалит узел из кластера Kubernetes!

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
            --pause)
                PAUSE_AFTER_STEP=true
                shift
                ;;
            --cleanup-storage)
                CLEANUP_STORAGE=true
                shift
                ;;
            --cleanup-config)
                CLEANUP_CONFIG=true
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
confirm_uninstall() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    print_warning "ВНИМАНИЕ: Этот скрипт удалит узел из кластера Kubernetes!"
    print_warning "Узел будет отключен от кластера и все локальные данные будут потеряны!"
    echo
    
    if [[ "$CLEANUP_STORAGE" == "true" ]]; then
        print_warning "Дополнительно будет выполнена очистка хранилища!"
    fi
    
    if [[ "$CLEANUP_CONFIG" == "true" ]]; then
        print_warning "Дополнительно будут удалены конфигурационные файлы!"
    fi
    
    echo
    read -p "Вы уверены, что хотите продолжить? (yes/no): " -r
    echo
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        print_info "Операция отменена"
        exit 0
    fi
}

# Проверка, что узел является частью кластера
check_cluster_membership() {
    print_section "Проверка принадлежности к кластеру"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка принадлежности к кластеру"
        return 0
    fi
    
    # Проверяем, запущен ли kubelet
    if systemctl is-active kubelet &>/dev/null; then
        print_info "Kubelet активен - узел является частью кластера"
        return 0
    else
        print_warning "Kubelet неактивен - узел может не быть частью кластера"
        return 1
    fi
}

# Остановка и отключение сервисов
stop_services() {
    print_section "Остановка и отключение сервисов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Остановка сервисов"
        return 0
    fi
    
    # Остановка kubelet
    print_info "Остановка kubelet..."
    if run_sudo systemctl stop kubelet; then
        print_success "Kubelet остановлен"
    else
        print_warning "Не удалось остановить kubelet"
    fi
    
    # Отключение автозапуска kubelet
    if run_sudo systemctl disable kubelet; then
        print_success "Автозапуск kubelet отключен"
    else
        print_warning "Не удалось отключить автозапуск kubelet"
    fi
    
    # Остановка containerd
    print_info "Остановка containerd..."
    if run_sudo systemctl stop containerd; then
        print_success "Containerd остановлен"
    else
        print_warning "Не удалось остановить containerd"
    fi
    
    # Отключение автозапуска containerd
    if run_sudo systemctl disable containerd; then
        print_success "Автозапуск containerd отключен"
    else
        print_warning "Не удалось отключить автозапуск containerd"
    fi
    
    return 0
}

# Очистка конфигурации Kubernetes
cleanup_kubernetes_config() {
    print_section "Очистка конфигурации Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка конфигурации Kubernetes"
        return 0
    fi
    
    # Удаление конфигурации kubelet
    print_info "Удаление конфигурации kubelet..."
    if run_sudo rm -rf /var/lib/kubelet; then
        print_success "Конфигурация kubelet удалена"
    else
        print_warning "Не удалось удалить конфигурацию kubelet"
    fi
    
    # Удаление конфигурации containerd
    print_info "Удаление конфигурации containerd..."
    if run_sudo rm -rf /var/lib/containerd; then
        print_success "Конфигурация containerd удалена"
    else
        print_warning "Не удалось удалить конфигурацию containerd"
    fi
    
    # Удаление конфигурации CNI
    print_info "Удаление конфигурации CNI..."
    if run_sudo rm -rf /etc/cni/net.d; then
        print_success "Конфигурация CNI удалена"
    else
        print_warning "Не удалось удалить конфигурацию CNI"
    fi
    
    # Удаление конфигурации kubectl
    print_info "Удаление конфигурации kubectl..."
    if run_sudo rm -rf /root/.kube; then
        print_success "Конфигурация kubectl удалена"
    else
        print_warning "Не удалось удалить конфигурацию kubectl"
    fi
    
    return 0
}

# Очистка сетевых интерфейсов
cleanup_network() {
    print_section "Очистка сетевых интерфейсов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка сетевых интерфейсов"
        return 0
    fi
    
    # Удаление интерфейсов CNI
    print_info "Удаление интерфейсов CNI..."
    
    # Удаление интерфейсов Calico
    for interface in $(ip link show | grep -E "cali|flannel" | cut -d: -f2 | tr -d ' '); do
        if run_sudo ip link delete "$interface" 2>/dev/null; then
            print_success "Интерфейс $interface удален"
        else
            log_debug "Интерфейс $interface не найден или уже удален"
        fi
    done
    
    # Очистка iptables правил
    print_info "Очистка iptables правил..."
    if run_sudo iptables -F; then
        print_success "Правила iptables очищены"
    else
        print_warning "Не удалось очистить правила iptables"
    fi
    
    # Очистка ip6tables правил
    if run_sudo ip6tables -F; then
        print_success "Правила ip6tables очищены"
    else
        print_warning "Не удалось очистить правила ip6tables"
    fi
    
    return 0
}

# Очистка хранилища
cleanup_storage() {
    if [[ "$CLEANUP_STORAGE" != "true" ]]; then
        return 0
    fi
    
    print_section "Очистка хранилища"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка хранилища"
        return 0
    fi
    
    # Поиск точек монтирования Kubernetes
    print_info "Поиск точек монтирования Kubernetes..."
    
    # Проверяем /var/lib/kubelet
    if mountpoint -q /var/lib/kubelet 2>/dev/null; then
        print_info "Размонтирование /var/lib/kubelet..."
        if run_sudo umount /var/lib/kubelet; then
            print_success "/var/lib/kubelet размонтирован"
        else
            print_warning "Не удалось размонтировать /var/lib/kubelet"
        fi
    fi
    
    # Проверяем /var/lib/containerd
    if mountpoint -q /var/lib/containerd 2>/dev/null; then
        print_info "Размонтирование /var/lib/containerd..."
        if run_sudo umount /var/lib/containerd; then
            print_success "/var/lib/containerd размонтирован"
        else
            print_warning "Не удалось размонтировать /var/lib/containerd"
        fi
    fi
    
    # Удаление записей из /etc/fstab
    print_info "Удаление записей Kubernetes из /etc/fstab..."
    if run_sudo sed -i '/kubelet\|containerd/d' /etc/fstab; then
        print_success "Записи Kubernetes удалены из /etc/fstab"
    else
        print_warning "Не удалось удалить записи из /etc/fstab"
    fi
    
    return 0
}

# Удаление пакетов Kubernetes
remove_kubernetes_packages() {
    print_section "Удаление пакетов Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление пакетов Kubernetes"
        return 0
    fi
    
    # Пакеты для удаления
    local packages=(
        "kubelet"
        "kubeadm"
        "kubectl"
        "cri-tools"
        "kubernetes-cni"
    )
    
    # Удаление пакетов
    print_info "Удаление пакетов Kubernetes..."
    if run_sudo dnf remove -y "${packages[@]}"; then
        print_success "Пакеты Kubernetes удалены"
    else
        print_warning "Не удалось удалить некоторые пакеты Kubernetes"
    fi
    
    # Удаление репозитория Kubernetes
    print_info "Удаление репозитория Kubernetes..."
    if run_sudo rm -f /etc/yum.repos.d/kubernetes.repo; then
        print_success "Репозиторий Kubernetes удален"
    else
        print_warning "Не удалось удалить репозиторий Kubernetes"
    fi
    
    return 0
}

# Удаление containerd
remove_containerd() {
    print_section "Удаление containerd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление containerd"
        return 0
    fi
    
    # Удаление systemd unit файла
    print_info "Удаление systemd unit файла containerd..."
    if run_sudo rm -f /etc/systemd/system/containerd.service; then
        print_success "Systemd unit файл containerd удален"
    else
        print_warning "Не удалось удалить systemd unit файл containerd"
    fi
    
    # Перезагрузка systemd
    if run_sudo systemctl daemon-reload; then
        print_success "Systemd конфигурация перезагружена"
    else
        print_warning "Не удалось перезагрузить systemd конфигурацию"
    fi
    
    # Удаление бинарных файлов containerd
    print_info "Удаление бинарных файлов containerd..."
    local containerd_binaries=(
        "/usr/local/bin/containerd"
        "/usr/local/bin/containerd-shim"
        "/usr/local/bin/containerd-shim-runc-v2"
        "/usr/local/bin/ctr"
        "/usr/local/bin/crictl"
    )
    
    for binary in "${containerd_binaries[@]}"; do
        if run_sudo rm -f "$binary"; then
            log_debug "Бинарный файл удален: $binary"
        else
            log_debug "Бинарный файл не найден: $binary"
        fi
    done
    
    print_success "Containerd удален"
    return 0
}

# Удаление runc
remove_runc() {
    print_section "Удаление runc"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление runc"
        return 0
    fi
    
    # Удаление бинарного файла runc
    if run_sudo rm -f /usr/local/bin/runc; then
        print_success "Runc удален"
    else
        print_warning "Не удалось удалить runc"
    fi
    
    return 0
}

# Удаление Helm
remove_helm() {
    print_section "Удаление Helm"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Удаление Helm"
        return 0
    fi
    
    # Удаление бинарного файла Helm
    if run_sudo rm -f /usr/local/bin/helm; then
        print_success "Helm удален"
    else
        print_warning "Не удалось удалить Helm"
    fi
    
    # Удаление конфигурации Helm
    if run_sudo rm -rf /root/.helm; then
        print_success "Конфигурация Helm удалена"
    else
        log_debug "Конфигурация Helm не найдена"
    fi
    
    return 0
}

# Очистка конфигурационных файлов
cleanup_config_files() {
    if [[ "$CLEANUP_CONFIG" != "true" ]]; then
        return 0
    fi
    
    print_section "Очистка конфигурационных файлов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Очистка конфигурационных файлов"
        return 0
    fi
    
    # Удаление конфигурации containerd
    print_info "Удаление конфигурации containerd..."
    if run_sudo rm -rf /etc/containerd; then
        print_success "Конфигурация containerd удалена"
    else
        print_warning "Не удалось удалить конфигурацию containerd"
    fi
    
    # Удаление конфигурации sysctl
    print_info "Удаление конфигурации sysctl..."
    if run_sudo rm -f /etc/sysctl.d/99-kubernetes-cri.conf; then
        print_success "Конфигурация sysctl удалена"
    else
        log_debug "Конфигурация sysctl не найдена"
    fi
    
    # Удаление конфигурации модулей
    print_info "Удаление конфигурации модулей..."
    if run_sudo rm -f /etc/modules-load.d/kubernetes.conf; then
        print_success "Конфигурация модулей удалена"
    else
        log_debug "Конфигурация модулей не найдена"
    fi
    
    return 0
}

# Восстановление swap
restore_swap() {
    print_section "Восстановление swap"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Восстановление swap"
        return 0
    fi
    
    # Раскомментируем строки swap в /etc/fstab
    print_info "Восстановление swap в /etc/fstab..."
    if run_sudo sed -i 's/^#\(.*swap.*\)/\1/' /etc/fstab; then
        print_success "Swap восстановлен в /etc/fstab"
    else
        print_warning "Не удалось восстановить swap в /etc/fstab"
    fi
    
    # Включаем zram swap обратно
    print_info "Включение zram swap..."
    if run_sudo systemctl unmask dev-zram0.swap; then
        print_success "dev-zram0.swap разблокирован"
    else
        log_debug "dev-zram0.swap не найден или уже разблокирован"
    fi
    
    return 0
}

# Проверка успешного удаления
verify_uninstall() {
    print_section "Проверка успешного удаления"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка успешного удаления"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса kubelet
    print_info "Проверка статуса kubelet..."
    if ! systemctl is-active kubelet &>/dev/null; then
        print_success "Kubelet неактивен"
    else
        print_error "Kubelet все еще активен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка статуса containerd
    print_info "Проверка статуса containerd..."
    if ! systemctl is-active containerd &>/dev/null; then
        print_success "Containerd неактивен"
    else
        print_error "Containerd все еще активен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка отсутствия конфигурации
    print_info "Проверка отсутствия конфигурации..."
    if [[ ! -d "/var/lib/kubelet" ]]; then
        print_success "Конфигурация kubelet удалена"
    else
        print_warning "Конфигурация kubelet все еще существует"
    fi
    
    if [[ ! -d "/var/lib/containerd" ]]; then
        print_success "Конфигурация containerd удалена"
    else
        print_warning "Конфигурация containerd все еще существует"
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Удаление Kubernetes Worker завершено успешно"
        return 0
    else
        print_warning "Обнаружено $failed_checks проблем при удалении"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Удаление Kubernetes Worker для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Инициализация логирования
    local log_file="$LOG_DIR/uninstall-k8s-worker-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало удаления Kubernetes Worker"
    log_info "Режим симуляции: $DRY_RUN"
    log_info "Очистка хранилища: $CLEANUP_STORAGE"
    log_info "Очистка конфигурации: $CLEANUP_CONFIG"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Подтверждение выполнения
    confirm_uninstall
    
    # Выполнение этапов удаления
    local steps=(
        "check_cluster_membership"
        "stop_services"
        "cleanup_kubernetes_config"
        "cleanup_network"
        "cleanup_storage"
        "remove_kubernetes_packages"
        "remove_containerd"
        "remove_runc"
        "remove_helm"
        "cleanup_config_files"
        "restore_swap"
        "verify_uninstall"
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
        
        # Пауза после каждого этапа, если включена
        pause_after_step
    done
    
    log_info "Удаление Kubernetes Worker завершено"
    
    # Информация для пользователя
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Kubernetes Worker успешно удален ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}Статус kubelet:${NC} $(systemctl is-active kubelet 2>/dev/null || echo 'неактивен')"
    echo -e "${BLUE}Статус containerd:${NC} $(systemctl is-active containerd 2>/dev/null || echo 'неактивен')"
    echo
    echo -e "${YELLOW}Для полной очистки системы рекомендуется перезагрузить узел${NC}"
    echo
    echo -e "${BLUE}Лог файл:${NC} $log_file"
    
    log_info "Для полной очистки системы рекомендуется перезагрузить узел"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
