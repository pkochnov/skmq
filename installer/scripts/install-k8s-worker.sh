#!/bin/bash
# =============================================================================
# Скрипт установки Kubernetes Worker
# =============================================================================
# Назначение: Установка и настройка рабочего узла Kubernetes
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
K8S_VERSION="${K8S_VERSION:-1.31.4}"
MASTER_IP=""
MASTER_PORT="${K8S_API_PORT:-6443}"
JOIN_TOKEN=""
DISCOVERY_TOKEN_CA_CERT_HASH=""
DRY_RUN=false
FORCE=false
PAUSE_AFTER_STEP=false

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
    --k8s-version VERSION           Версия Kubernetes (по умолчанию: $K8S_VERSION)
    --master-ip IP                  IP адрес контроллерного узла (обязательно)
    --master-port PORT              Порт API сервера (по умолчанию: $MASTER_PORT)
    --join-token TOKEN              Токен для присоединения к кластеру (обязательно)
    --discovery-token-ca-cert-hash HASH  Хэш CA сертификата (обязательно)
    --dry-run                       Режим симуляции (без выполнения команд)
    --force                         Принудительное выполнение (без подтверждений)
    --pause                         Пауза после каждого этапа установки
    --help                          Показать эту справку

Примеры:
    $0 --master-ip 10.72.66.51 --join-token abc123.def456 --discovery-token-ca-cert-hash sha256:...
    $0 --master-ip 10.72.66.51 --join-token abc123.def456 --discovery-token-ca-cert-hash sha256:... --dry-run

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            --master-ip)
                MASTER_IP="$2"
                shift 2
                ;;
            --master-port)
                MASTER_PORT="$2"
                shift 2
                ;;
            --join-token)
                JOIN_TOKEN="$2"
                shift 2
                ;;
            --discovery-token-ca-cert-hash)
                DISCOVERY_TOKEN_CA_CERT_HASH="$2"
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
            --pause)
                PAUSE_AFTER_STEP=true
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
    
    # Проверка обязательных параметров
    if [[ -z "$MASTER_IP" ]]; then
        log_error "Не указан IP адрес контроллерного узла (--master-ip)"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$JOIN_TOKEN" ]]; then
        log_error "Не указан токен для присоединения (--join-token)"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$DISCOVERY_TOKEN_CA_CERT_HASH" ]]; then
        log_error "Не указан хэш CA сертификата (--discovery-token-ca-cert-hash)"
        errors=$((errors + 1))
    fi
    
    # Проверка версии Kubernetes
    if [[ ! "$K8S_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Неверный формат версии Kubernetes: $K8S_VERSION"
        errors=$((errors + 1))
    fi
    
    # Проверка IP адреса мастера
    if [[ -n "$MASTER_IP" ]] && ! validate_ip "$MASTER_IP"; then
        log_error "Неверный IP адрес контроллерного узла: $MASTER_IP"
        errors=$((errors + 1))
    fi
    
    # Проверка порта
    if [[ ! "$MASTER_PORT" =~ ^[0-9]+$ ]] || [[ $MASTER_PORT -lt 1 ]] || [[ $MASTER_PORT -gt 65535 ]]; then
        log_error "Неверный порт API сервера: $MASTER_PORT"
        errors=$((errors + 1))
    fi
    
    # Проверка токена
    if [[ -n "$JOIN_TOKEN" ]] && [[ ! "$JOIN_TOKEN" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ ]]; then
        log_error "Неверный формат токена: $JOIN_TOKEN"
        errors=$((errors + 1))
    fi
    
    # Проверка хэша CA сертификата
    if [[ -n "$DISCOVERY_TOKEN_CA_CERT_HASH" ]] && [[ ! "$DISCOVERY_TOKEN_CA_CERT_HASH" =~ ^sha256:[a-f0-9]{64}$ ]]; then
        log_error "Неверный формат хэша CA сертификата: $DISCOVERY_TOKEN_CA_CERT_HASH"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors ошибок в параметрах"
        exit 1
    fi
}

# Проверка системных требований
check_system_requirements() {
    print_section "Проверка системных требований"
    
    local errors=0
    
    # Проверка операционной системы
    if [[ ! -f /etc/redhat-release ]]; then
        print_error "Скрипт предназначен для Red Hat-based систем"
        errors=$((errors + 1))
    else
        local os_version=$(cat /etc/redhat-release)
        print_info "Операционная система: $os_version"
    fi
    
    # Проверка архитектуры
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        print_error "Неподдерживаемая архитектура: $arch (требуется x86_64)"
        errors=$((errors + 1))
    else
        print_info "Архитектура: $arch"
    fi
    
    # Проверка памяти
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 2048 ]]; then
        print_error "Недостаточно памяти: ${total_mem}MB (требуется минимум 2GB)"
        errors=$((errors + 1))
    else
        print_info "Общая память: ${total_mem}MB"
    fi
    
    # Проверка CPU
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        print_error "Недостаточно CPU ядер: $cpu_cores (требуется минимум 2)"
        errors=$((errors + 1))
    else
        print_info "CPU ядер: $cpu_cores"
    fi
    
    # Проверка дискового пространства
    local disk_space=$(df / | awk 'NR==2{print $4}')
    local disk_space_gb=$((disk_space / 1024 / 1024))
    if [[ $disk_space_gb -lt 10 ]]; then
        print_error "Недостаточно дискового пространства: ${disk_space_gb}GB (требуется минимум 10GB)"
        errors=$((errors + 1))
    else
        print_info "Доступное дисковое пространство: ${disk_space_gb}GB"
    fi
    
    # Docker не нужен на Kubernetes узлах - используется containerd
    
    if [[ $errors -gt 0 ]]; then
        print_error "Обнаружено $errors ошибок в системных требованиях"
        return 1
    else
        print_success "Все системные требования выполнены"
        return 0
    fi
}

# Проверка подключения к контроллерному узлу
check_master_connectivity() {
    print_section "Проверка подключения к контроллерному узлу"
    
    print_info "Проверка подключения к $MASTER_IP:$MASTER_PORT..."
    
    if check_port_common "$MASTER_IP" "$MASTER_PORT" 10; then
        print_success "Контроллерный узел доступен"
    else
        print_error "Контроллерный узел недоступен: $MASTER_IP:$MASTER_PORT"
        print_info "Убедитесь, что:"
        print_info "  1. Контроллерный узел запущен"
        print_info "  2. API сервер доступен"
        print_info "  3. Файрвол настроен правильно"
        print_info "  4. Сетевое подключение работает"
        return 1
    fi
    
    return 0
}

# Отключение swap
disable_swap() {
    print_section "Отключение swap"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Отключение swap"
        return 0
    fi
    
    # Отключаем zram swap (RHEL/Alma/Rocky 9+)
    print_info "Отключение zram swap..."
    
    # Проверяем и отключаем dev-zram0.swap
    if run_sudo systemctl list-unit-files | grep -q "dev-zram0.swap"; then
        if run_sudo systemctl stop dev-zram0.swap; then
            print_success "dev-zram0.swap остановлен"
        else
            print_warning "Не удалось остановить dev-zram0.swap"
        fi
        
        if run_sudo systemctl mask dev-zram0.swap; then
            print_success "dev-zram0.swap заблокирован (masked)"
        else
            print_warning "Не удалось заблокировать dev-zram0.swap"
        fi
    else
        log_debug "dev-zram0.swap не найден"
    fi
    
    # Проверяем, есть ли активный swap
    if swapon --show | grep -q .; then
        print_info "Отключение активного swap..."
        if run_sudo swapoff -a; then
            print_success "Swap отключен"
        else
            print_error "Ошибка при отключении swap"
            return 1
        fi
    else
        print_info "Swap уже отключен"
    fi
    
    # Комментируем строки swap в /etc/fstab
    if run_sudo sed -i '/swap/s/^/#/' /etc/fstab; then
        print_success "Swap закомментирован в /etc/fstab"
    else
        print_warning "Не удалось закомментировать swap в /etc/fstab"
    fi
    
    # Проверяем, что swap действительно отключен
    if swapon --show | grep -q .; then
        print_warning "Предупреждение: некоторые swap устройства все еще активны"
        run_sudo swapon --show
    else
        print_success "Все swap устройства отключены"
    fi
    
    # Очищаем swap подписи с блочных устройств
    print_info "Очистка swap подписей с блочных устройств..."
    local swap_devices_found=false
    
    # Ищем все блочные устройства с swap типом
    for device in $(run_sudo blkid -t TYPE=swap -o device); do
        if [[ -n "$device" ]]; then
            swap_devices_found=true
            print_info "Найдено swap устройство: $device"
            
            # Очищаем swap подпись
            if run_sudo wipefs -a "$device"; then
                print_success "Swap подпись очищена с $device"
            else
                print_warning "Не удалось очистить swap подпись с $device"
            fi
        fi
    done
    
    if [[ "$swap_devices_found" == "false" ]]; then
        log_debug "Swap блочные устройства не найдены"
    fi
    
    return 0
}

# Настройка ядра
configure_kernel() {
    print_section "Настройка параметров ядра"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка параметров ядра"
        return 0
    fi
    
    # Создание файла конфигурации sysctl
    local sysctl_config="/etc/sysctl.d/99-kubernetes-cri.conf"
    local temp_config="/tmp/kubernetes-sysctl.conf"
    
    cat << EOF > "$temp_config"
# Настройки для Kubernetes
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.ipv6.conf.all.forwarding        = 1
vm.swappiness                       = 0
vm.overcommit_memory                = 1
vm.panic_on_oom                     = 0
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 1048576
fs.file-max                         = 52706963
fs.nr_open                          = 52706963
net.netfilter.nf_conntrack_max      = 2310720
EOF
    
    # Копируем конфигурацию
    if run_sudo cp "$temp_config" "$sysctl_config"; then
        run_sudo chmod 644 "$sysctl_config"
        rm -f "$temp_config"
        print_success "Конфигурация sysctl создана"
    else
        rm -f "$temp_config"
        print_error "Ошибка при создании конфигурации sysctl"
        return 1
    fi
    
    # Применяем настройки
    if run_sudo sysctl --system; then
        print_success "Настройки ядра применены"
    else
        print_warning "Не удалось применить все настройки ядра"
    fi
    
    return 0
}

# Загрузка модулей ядра
load_kernel_modules() {
    print_section "Загрузка модулей ядра"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Загрузка модулей ядра"
        return 0
    fi
    
    local modules=(
        "br_netfilter"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
        "nf_conntrack"
    )
    
    # Создание файла конфигурации модулей
    local modules_config="/etc/modules-load.d/kubernetes.conf"
    local temp_config="/tmp/kubernetes-modules.conf"
    
    for module in "${modules[@]}"; do
        echo "$module" >> "$temp_config"
    done
    
    # Копируем конфигурацию
    if run_sudo cp "$temp_config" "$modules_config"; then
        run_sudo chmod 644 "$modules_config"
        rm -f "$temp_config"
        print_success "Конфигурация модулей создана"
    else
        rm -f "$temp_config"
        print_error "Ошибка при создании конфигурации модулей"
        return 1
    fi
    
    # Загружаем модули
    for module in "${modules[@]}"; do
        if run_sudo modprobe "$module"; then
            log_debug "Модуль загружен: $module"
        else
            print_warning "Не удалось загрузить модуль: $module"
        fi
    done
    
    print_success "Модули ядра загружены"
    return 0
}

# Установка toml-cli
install_toml_cli() {
    print_section "Установка toml-cli"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка toml-cli"
        return 0
    fi
    
    # Проверяем, установлен ли уже toml-cli
    if command -v toml >/dev/null 2>&1; then
        print_info "toml-cli уже установлен"
        return 0
    fi
    
    # Версия toml-cli
    local toml_version="0.2.3"
    local toml_url="https://github.com/gnprice/toml-cli/releases/download/v${toml_version}/toml-${toml_version}-x86_64-linux.tar.gz"
    local toml_tmp="/tmp/toml-${toml_version}-x86_64-linux.tar.gz"
    
    # Скачиваем toml-cli
    if wget -q "$toml_url" -O "$toml_tmp"; then
        print_success "toml-cli скачан"
    else
        print_error "Ошибка при скачивании toml-cli"
        return 1
    fi
    
    # Извлекаем и устанавливаем toml-cli
    if tar -xf "$toml_tmp" -C /tmp/ && run_sudo mv /tmp/toml /usr/local/bin/; then
        run_sudo chmod +x /usr/local/bin/toml
        print_success "toml-cli установлен"
        rm -f "$toml_tmp"
    else
        print_error "Ошибка при установке toml-cli"
        rm -f "$toml_tmp"
        return 1
    fi
    
    return 0
}

# Установка системных пакетов
install_system_packages() {
    print_section "Установка системных пакетов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка системных пакетов"
        return 0
    fi
    
    # Пакеты из документации MONQ (адаптированные для RedOS 8)
    local packages=(
        "gpg"
        "curl"
        "bind-utils"  # аналог dnsutils для RHEL
        "vim"
        "telnet"
        "unzip"
        "bash-completion"
        "ca-certificates"
        "jq"
        "nfs-utils"  # аналог nfs-common для RHEL
        "wget"
        "tar"
        "gzip"
        "openssl"  # для создания сертификатов
        "iproute-tc"
    )
    
    # Установка основных пакетов
    if run_sudo dnf install -y "${packages[@]}"; then
        print_success "Системные пакеты установлены"
    else
        print_error "Ошибка при установке системных пакетов"
        return 1
    fi
    
    # Установка dnf-command(versionlock) для фиксации версий
    if run_sudo dnf install -y 'dnf-command(versionlock)'; then
        print_success "dnf-command(versionlock) установлен"
    else
        print_warning "Не удалось установить dnf-command(versionlock)"
        print_warning "Фиксация версий пакетов будет выполнена через dnf.conf"
    fi
    
    return 0
}

# Установка runc (OCI runtime)
install_runc() {
    print_section "Установка runc (OCI runtime)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка runc"
        return 0
    fi
    
    # Проверяем, установлен ли уже runc
    if command -v runc >/dev/null 2>&1; then
        print_info "Runc уже установлен"
        return 0
    fi
    
    # Установка зависимостей
    local deps=("wget")
    if run_sudo dnf install -y "${deps[@]}"; then
        print_success "Зависимости установлены"
    else
        print_error "Ошибка при установке зависимостей"
        return 1
    fi
    
    # Используем версию runc из конфигурации
    local runc_version="$RUNC_VERSION"
    local arch="amd64"
    
    # Создаем временную директорию
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1
    
    # Скачиваем runc
    local download_url="https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.${arch}"
    
    if wget -q "$download_url" -O runc; then
        print_success "Runc скачан"
    else
        print_error "Ошибка при скачивании runc"
        cd - >/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Устанавливаем runc
    if run_sudo cp runc /usr/local/bin/ && run_sudo chmod +x /usr/local/bin/runc; then
        print_success "Runc установлен в /usr/local/bin"
    else
        print_error "Ошибка при установке runc"
        cd - >/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Очищаем временную директорию
    cd - >/dev/null || true
    rm -rf "$temp_dir"
    
    return 0
}

# Установка containerd
install_containerd() {
    print_section "Установка containerd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка containerd"
        return 0
    fi
    
    # Проверяем, установлен ли уже containerd
    if command -v containerd >/dev/null 2>&1; then
        print_info "Containerd уже установлен"
        return 0
    fi
    
    # Установка зависимостей
    local deps=("wget" "tar")
    if run_sudo dnf install -y "${deps[@]}"; then
        print_success "Зависимости установлены"
    else
        print_error "Ошибка при установке зависимостей"
        return 1
    fi
    
    # Используем версию containerd из конфигурации
    local containerd_version="$CONTAINERD_VERSION"
    local arch="amd64"
    
    # Создаем временную директорию
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1
    
    # Скачиваем containerd
    local download_url="https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-${arch}.tar.gz"
    
    if wget -q "$download_url"; then
        print_success "Containerd скачан"
    else
        print_error "Ошибка при скачивании containerd"
        cd - >/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Извлекаем и устанавливаем containerd
    if tar -xzf "containerd-${containerd_version}-linux-${arch}.tar.gz"; then
        print_success "Containerd извлечен"
    else
        print_error "Ошибка при извлечении containerd"
        cd - >/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Копируем бинарные файлы containerd
    if run_sudo cp bin/* /usr/local/bin/; then
        print_success "Containerd установлен в /usr/local/bin"
    else
        print_error "Ошибка при копировании бинарных файлов containerd"
        cd - >/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Создаем systemd unit файл
    cat <<EOF | run_sudo tee /etc/systemd/system/containerd.service >/dev/null
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
    
    # Очищаем временную директорию
    cd - >/dev/null || true
    rm -rf "$temp_dir"
    
    # Перезагружаем systemd и включаем containerd
    if run_sudo systemctl daemon-reload; then
        print_success "Systemd конфигурация перезагружена"
    else
        print_warning "Не удалось перезагрузить systemd конфигурацию"
    fi
    
    if run_sudo systemctl enable containerd; then
        print_success "Containerd включен для автозапуска"
    else
        print_warning "Не удалось включить автозапуск containerd"
    fi
    
    if run_sudo systemctl start containerd; then
        print_success "Containerd запущен"
    else
        print_warning "Не удалось запустить containerd"
    fi
    
    return 0
}

# Добавление Kubernetes репозитория
add_kubernetes_repository() {
    print_section "Добавление Kubernetes репозитория"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Добавление Kubernetes репозитория"
        return 0
    fi

    # Извлекаем только major.minor версию из K8S_VERSION
    # Например, из "1.31.4" получаем "1.31"
    local k8s_major_minor
    k8s_major_minor=$(echo "$K8S_VERSION" | awk -F. '{print $1"."$2}')
    
    log_debug "K8S_VERSION: $K8S_VERSION"
    log_debug "k8s_major_minor: $k8s_major_minor"

    # Создание файла репозитория
    local repo_config="/etc/yum.repos.d/kubernetes.repo"
    local temp_config="/tmp/kubernetes.repo"
    
    cat << EOF > "$temp_config"
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${k8s_major_minor}/rpm/repodata/repomd.xml.key
EOF
    
    # Копируем конфигурацию
    if run_sudo cp "$temp_config" "$repo_config"; then
        run_sudo chmod 644 "$repo_config"
        rm -f "$temp_config"
        print_success "Репозиторий Kubernetes добавлен"
    else
        rm -f "$temp_config"
        print_error "Ошибка при добавлении репозитория Kubernetes"
        return 1
    fi
    
    # Обновляем кэш пакетов
    if run_sudo dnf makecache; then
        print_success "Кэш пакетов обновлен"
        return 0
    else
        print_error "Ошибка при обновлении кэша пакетов"
        return 1
    fi
}

# Установка Kubernetes компонентов
install_kubernetes_components() {
    print_section "Установка Kubernetes компонентов версии: $K8S_VERSION"
    
    local packages=(
        "kubelet"
        "kubeadm"
        "kubectl"
        "cri-tools"
        "kubernetes-cni"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка пакетов: ${packages[*]}"
        return 0
    fi
    
    # Установка пакетов
    if run_sudo dnf install -y "${packages[@]}"; then
        print_success "Kubernetes компоненты установлены"
    else
        print_error "Ошибка при установке Kubernetes компонентов"
        return 1
    fi
    
    # Включаем kubelet
    if run_sudo systemctl enable kubelet; then
        print_success "Kubelet включен для автозапуска"
    else
        print_warning "Не удалось включить автозапуск kubelet"
    fi
    
    # Фиксируем версии Kubernetes пакетов (аналог apt-mark hold)
    local k8s_packages=("kubelet" "kubeadm" "kubectl")
    local versionlock_success=true
    
    # Проверяем, доступен ли dnf versionlock
    if command -v dnf >/dev/null 2>&1 && run_sudo dnf versionlock --help >/dev/null 2>&1; then
        print_info "Использование dnf versionlock для фиксации версий..."
        
        for package in "${k8s_packages[@]}"; do
            # Получаем текущую версию пакета
            local package_version=$(run_sudo dnf list installed "$package" --quiet 2>/dev/null | grep "$package" | awk '{print $2}')
            if [[ -n "$package_version" ]]; then
                if run_sudo dnf versionlock add "$package-$package_version"; then
                    log_debug "Версия пакета $package-$package_version зафиксирована"
                else
                    print_warning "Не удалось зафиксировать версию пакета $package через dnf versionlock"
                    versionlock_success=false
                fi
            else
                print_warning "Не удалось определить версию пакета $package"
                versionlock_success=false
            fi
        done
        
        if [[ "$versionlock_success" == "true" ]]; then
            print_success "Версии Kubernetes пакетов зафиксированы через dnf versionlock"
        fi
    else
        print_warning "dnf versionlock недоступен, используем альтернативный способ"
        versionlock_success=false
    fi
    
    # Альтернативный способ фиксации через исключение в dnf.conf
    if [[ "$versionlock_success" != "true" ]]; then
        print_info "Попытка альтернативной фиксации версий через dnf.conf..."
        local dnf_exclude_line="exclude=kubelet kubeadm kubectl"
        if run_sudo grep -q "exclude=" /etc/dnf/dnf.conf; then
            # Обновляем существующую строку exclude
            run_sudo sed -i "s/^exclude=.*/& kubelet kubeadm kubectl/" /etc/dnf/dnf.conf
        else
            # Добавляем новую строку exclude
            echo "$dnf_exclude_line" | run_sudo tee -a /etc/dnf/dnf.conf >/dev/null
        fi
        print_success "Версии Kubernetes пакетов зафиксированы через dnf.conf"
    fi
    
    return 0
}

# Создание конфигурации небезопасного реестра
configure_insecure_registry() {
    print_section "Настройка небезопасного реестра для containerd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка небезопасного реестра"
        return 0
    fi
    
    # Создание директории для конфигурации реестров
    local registry_config_dir="/etc/containerd/certs.d/registry:5000"
    if run_sudo mkdir -p "$registry_config_dir"; then
        log_debug "Директория конфигурации реестра создана: $registry_config_dir"
    else
        print_error "Ошибка при создании директории конфигурации реестра"
        return 1
    fi
    
    # Создание hosts.toml для небезопасного реестра
    local hosts_toml="$registry_config_dir/hosts.toml"
    cat << EOF > /tmp/hosts.toml
server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
  plain_http = true
EOF
    
    # Копируем конфигурацию
    if run_sudo cp /tmp/hosts.toml "$hosts_toml"; then
        run_sudo chmod 644 "$hosts_toml"
        rm -f /tmp/hosts.toml
        print_success "Конфигурация небезопасного реестра создана"
    else
        rm -f /tmp/hosts.toml
        print_error "Ошибка при создании конфигурации небезопасного реестра"
        return 1
    fi
    
    return 0
}

# Настройка containerd
configure_containerd() {
    print_section "Настройка containerd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка containerd"
        return 0
    fi
    
    # Создание директории конфигурации
    if run_sudo mkdir -p /etc/containerd; then
        log_debug "Директория конфигурации containerd создана: /etc/containerd"
    else
        print_error "Ошибка при создании директории конфигурации containerd"
        return 1
    fi
    
    # Генерация конфигурации containerd
    if run_sudo /usr/local/bin/containerd config default > /tmp/containerd-config.toml; then
        log_debug "Конфигурация containerd сгенерирована"
    else
        print_error "Ошибка при генерации конфигурации containerd"
        return 1
    fi
    
    # Настройка systemd cgroup driver
    if run_sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /tmp/containerd-config.toml; then
        log_debug "SystemdCgroup включен в конфигурации containerd"
    else
        print_warning "Не удалось включить SystemdCgroup в конфигурации containerd"
    fi
    
    # Настройка пути к конфигурации реестров с помощью toml-cli
    print_info "Настройка пути к конфигурации реестров с помощью toml-cli..."
    
    # Устанавливаем config_path в секции registry и сохраняем результат в файл
    local temp_output="/tmp/containerd-config-updated.toml"
    if run_sudo toml set /tmp/containerd-config.toml 'plugins."io.containerd.grpc.v1.cri".registry.config_path' '/etc/containerd/certs.d' > "$temp_output"; then
        if run_sudo mv "$temp_output" /tmp/containerd-config.toml; then
            log_debug "Путь к конфигурации реестров установлен: /etc/containerd/certs.d"
            print_success "Конфигурация реестров настроена"
        else
            print_error "Ошибка при сохранении обновленной конфигурации"
            rm -f "$temp_output"
            return 1
        fi
    else
        print_error "Не удалось настроить путь к конфигурации реестров через toml-cli"
        rm -f "$temp_output"
        return 1
    fi
    
    # Копируем конфигурацию
    if run_sudo cp /tmp/containerd-config.toml /etc/containerd/config.toml; then
        run_sudo chmod 644 /etc/containerd/config.toml
        rm -f /tmp/containerd-config.toml
        print_success "Конфигурация containerd создана"
    else
        rm -f /tmp/containerd-config.toml
        print_error "Ошибка при создании конфигурации containerd"
        return 1
    fi
    
    # Перезапуск containerd
    if run_sudo systemctl restart containerd; then
        print_success "Containerd перезапущен"
    else
        print_error "Ошибка при перезапуске containerd"
        return 1
    fi
    
    # Включение автозапуска
    if run_sudo systemctl enable containerd; then
        print_success "Containerd включен для автозапуска"
    else
        print_warning "Не удалось включить автозапуск containerd"
    fi
    
    return 0
}

# Предварительная загрузка образов Kubernetes
pull_k8s_images() {
    print_section "Предварительная загрузка образов Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Предварительная загрузка образов Kubernetes"
        return 0
    fi
    
    print_info "Загрузка образов Kubernetes с локального реестра registry:5000..."
    
    # Команда загрузки образов
    local pull_cmd="kubeadm config images pull --image-repository registry:5000"
    
    print_info "Выполнение команды загрузки образов..."
    log_info "Команда: $pull_cmd"
    
    if run_sudo $pull_cmd; then
        print_success "Образы Kubernetes загружены с локального реестра"
    else
        print_warning "Не удалось загрузить образы с локального реестра, будет использован стандартный репозиторий"
        log_warn "Возможно, локальный реестр недоступен или образы не загружены в него"
    fi
    
    return 0
}

# Присоединение к кластеру
join_cluster() {
    print_section "Присоединение к кластеру Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Присоединение к кластеру Kubernetes"
        print_info "[DRY-RUN] Команда: kubeadm join $MASTER_IP:$MASTER_PORT --token $JOIN_TOKEN --discovery-token-ca-cert-hash $DISCOVERY_TOKEN_CA_CERT_HASH --cri-socket=unix:///var/run/containerd/containerd.sock"
        return 0
    fi
    
    # Команда присоединения к кластеру
    local join_cmd="kubeadm join $MASTER_IP:$MASTER_PORT \
        --token $JOIN_TOKEN \
        --discovery-token-ca-cert-hash $DISCOVERY_TOKEN_CA_CERT_HASH \
        --cri-socket=unix:///var/run/containerd/containerd.sock"
    
    print_info "Выполнение команды присоединения к кластеру..."
    log_info "Команда: $join_cmd"
    
    if run_sudo $join_cmd; then
        print_success "Узел успешно присоединен к кластеру"
    else
        print_error "Ошибка при присоединении к кластеру"
        return 1
    fi
    
    return 0
}

# Настройка файрвола
configure_firewall() {
    print_section "Настройка файрвола для Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка файрвола для Kubernetes"
        return 0
    fi
    
    # Проверяем, активен ли firewalld
    if ! systemctl is-active firewalld &>/dev/null; then
        print_info "Firewalld не активен, пропускаем настройку файрвола"
        return 0
    fi
    
    # Порты для Kubernetes Worker
    local ports=(
        "10250/tcp"     # Kubelet API
        "10255/tcp"     # Read-only Kubelet API
        "179/tcp"       # Calico BGP
        "4789/udp"      # Calico VXLAN
    )
    
    # Открываем порты
    for port in "${ports[@]}"; do
        if run_sudo firewall-cmd --permanent --add-port="$port"; then
            log_debug "Порт открыт: $port"
        else
            print_warning "Не удалось открыть порт: $port"
        fi
    done
    
    # Перезагружаем файрвол
    if run_sudo firewall-cmd --reload; then
        print_success "Файрвол настроен для Kubernetes"
    else
        print_warning "Не удалось перезагрузить файрвол"
    fi
    
    return 0
}

# Проверка присоединения к кластеру
verify_cluster_join() {
    print_section "Проверка присоединения к кластеру"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка присоединения к кластеру"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса kubelet
    print_info "Проверка статуса kubelet..."
    if systemctl is-active kubelet &>/dev/null; then
        print_success "Kubelet активен"
    else
        print_error "Kubelet неактивен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка статуса containerd
    print_info "Проверка статуса containerd..."
    if systemctl is-active containerd &>/dev/null; then
        print_success "Containerd активен"
    else
        print_error "Containerd неактивен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка доступности портов
    print_info "Проверка доступности портов..."
    if check_port_common localhost 10250 5; then
        print_success "Порт kubelet (10250) доступен"
    else
        print_error "Порт kubelet (10250) недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка подключения к API серверу
    print_info "Проверка подключения к API серверу..."
    if check_port_common "$MASTER_IP" "$MASTER_PORT" 5; then
        print_success "API сервер доступен"
    else
        print_error "API сервер недоступен"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка логов kubelet
    print_info "Проверка логов kubelet..."
    if journalctl -u kubelet --no-pager -n 10 | grep -i error; then
        print_warning "Обнаружены ошибки в логах kubelet"
    else
        print_success "Ошибок в логах kubelet не обнаружено"
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки присоединения к кластеру пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок присоединения к кластеру"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Kubernetes Worker для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-k8s-worker-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Kubernetes Worker"
    log_info "Версия Kubernetes: $K8S_VERSION"
    log_info "IP контроллерного узла: $MASTER_IP"
    log_info "Порт API сервера: $MASTER_PORT"
    log_info "Токен присоединения: $JOIN_TOKEN"
    log_info "Хэш CA сертификата: $DISCOVERY_TOKEN_CA_CERT_HASH"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_system_requirements"
        "check_master_connectivity"
        "install_system_packages"
        "disable_swap"
        "configure_kernel"
        "load_kernel_modules"
        "add_kubernetes_repository"
        "install_runc"
        "install_containerd"
        "install_toml_cli"
        "configure_containerd"
        "configure_insecure_registry"
        "install_kubernetes_components"
        "pull_k8s_images"
        "join_cluster"
        "configure_firewall"
        "verify_cluster_join"
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
    
    log_info "Установка Kubernetes Worker завершена успешно"
    
    # Информация для пользователя
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Kubernetes Worker успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}Версия Kubernetes:${NC} $K8S_VERSION"
    echo -e "${BLUE}Контроллерный узел:${NC} $MASTER_IP:$MASTER_PORT"
    echo -e "${BLUE}Статус kubelet:${NC} $(systemctl is-active kubelet)"
    echo -e "${BLUE}Статус containerd:${NC} $(systemctl is-active containerd)"
    echo
    echo -e "${YELLOW}Для проверки статуса узла на контроллерном узле выполните:${NC}"
    echo -e "${GREEN}kubectl get nodes${NC}"
    echo
    echo -e "${BLUE}Лог файл:${NC} $log_file"
    
    log_info "Для проверки статуса узла на контроллерном узле выполните: kubectl get nodes"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
