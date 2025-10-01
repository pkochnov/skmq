#!/bin/bash
# =============================================================================
# Скрипт установки Kubernetes Controller
# =============================================================================
# Назначение: Установка и настройка контроллерного узла Kubernetes
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
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
CNI_PLUGIN="${CNI_PLUGIN:-cilium}"
CILIUM_VERSION="${CILIUM_VERSION:-1.16.5}"
K8S_API_PORT="${K8S_API_PORT:-6443}"
K8S_CLUSTER_NAME="${K8S_CLUSTER_NAME:-monq-cluster}"
K8S_TOKEN_TTL="${K8S_TOKEN_TTL:-24h0m0s}"
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
    --k8s-version VERSION     Версия Kubernetes (по умолчанию: $K8S_VERSION)
    --pod-network-cidr CIDR   CIDR сети подов (по умолчанию: $POD_NETWORK_CIDR)
    --service-cidr CIDR       CIDR сети сервисов (по умолчанию: $SERVICE_CIDR)
    --cni PLUGIN              CNI плагин (cilium/calico/flannel) (по умолчанию: $CNI_PLUGIN)
    --cilium-version VERSION  Версия Cilium CNI (по умолчанию: $CILIUM_VERSION)
    --api-port PORT           Порт API сервера (по умолчанию: $K8S_API_PORT)
    --cluster-name NAME       Имя кластера (по умолчанию: $K8S_CLUSTER_NAME)
    --token-ttl TTL           Время жизни токена (по умолчанию: $K8S_TOKEN_TTL)
    --dry-run                 Режим симуляции (без выполнения команд)
    --force                   Принудительное выполнение (без подтверждений)
    --pause                   Пауза после каждого этапа установки
    --help                    Показать эту справку

Примеры:
    $0 --k8s-version 1.31.4 --cni cilium
    $0 --pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12 --dry-run
    $0 --cilium-version 1.16.5 --cni cilium

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
            --pod-network-cidr)
                POD_NETWORK_CIDR="$2"
                shift 2
                ;;
            --service-cidr)
                SERVICE_CIDR="$2"
                shift 2
                ;;
            --cni)
                CNI_PLUGIN="$2"
                shift 2
                ;;
            --cilium-version)
                CILIUM_VERSION="$2"
                shift 2
                ;;
            --api-port)
                K8S_API_PORT="$2"
                shift 2
                ;;
            --cluster-name)
                K8S_CLUSTER_NAME="$2"
                shift 2
                ;;
            --token-ttl)
                K8S_TOKEN_TTL="$2"
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
    
    # Проверка версии Kubernetes
    if [[ ! "$K8S_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Неверный формат версии Kubernetes: $K8S_VERSION"
        errors=$((errors + 1))
    fi
    
    # Проверка CIDR сетей
    if [[ ! "$POD_NETWORK_CIDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        log_error "Неверный формат CIDR сети подов: $POD_NETWORK_CIDR"
        errors=$((errors + 1))
    fi
    
    if [[ ! "$SERVICE_CIDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        log_error "Неверный формат CIDR сети сервисов: $SERVICE_CIDR"
        errors=$((errors + 1))
    fi
    
    # Проверка CNI плагина
    if [[ "$CNI_PLUGIN" != "cilium" && "$CNI_PLUGIN" != "calico" && "$CNI_PLUGIN" != "flannel" ]]; then
        log_error "Неподдерживаемый CNI плагин: $CNI_PLUGIN (поддерживаются: cilium, calico, flannel)"
        errors=$((errors + 1))
    fi
    
    # Проверка порта API
    if [[ ! "$K8S_API_PORT" =~ ^[0-9]+$ ]] || [[ $K8S_API_PORT -lt 1 ]] || [[ $K8S_API_PORT -gt 65535 ]]; then
        log_error "Неверный порт API сервера: $K8S_API_PORT"
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
    for device in $(run_sudo blkid -t TYPE=swap -o device 2>/dev/null); do
        if [[ -n "$device" ]]; then
            swap_devices_found=true
            print_info "Найдено swap устройство: $device"
            
            # Очищаем swap подпись
            if run_sudo wipefs -a "$device" 2>/dev/null; then
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
    
    # Проверяем содержимое созданного файла
    log_debug "Содержимое созданного repo файла:"
    log_debug "$(cat "$temp_config")"
    
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

# Создание CA сертификатов
create_ca_certificates() {
    print_section "Создание CA сертификатов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание CA сертификатов"
        return 0
    fi
    
    # Создаем директорию для сертификатов
    local certs_dir="/etc/kubernetes/certs"
    if run_sudo mkdir -p "$certs_dir"; then
        log_debug "Директория для сертификатов создана: $certs_dir"
    else
        print_error "Ошибка при создании директории для сертификатов"
        return 1
    fi
    
    # Создаем CA сертификат
    local ca_csr="$certs_dir/monq.ca.csr"
    local ca_key="$certs_dir/monq.ca.key"
    local ca_crt="$certs_dir/monq.ca.crt"
    
    # Генерируем приватный ключ CA
    if run_sudo openssl genrsa -out "$ca_key" 4096; then
        print_success "Приватный ключ CA создан"
    else
        print_error "Ошибка при создании приватного ключа CA"
        return 1
    fi
    
    # Создаем запрос на сертификат CA
    if run_sudo openssl req -new -key "$ca_key" -out "$ca_csr" -subj "/CN=monq"; then
        print_success "Запрос на сертификат CA создан"
    else
        print_error "Ошибка при создании запроса на сертификат CA"
        return 1
    fi
    
    # Создаем самоподписанный сертификат CA
    if run_sudo openssl x509 -req -in "$ca_csr" -signkey "$ca_key" -out "$ca_crt" -days 3650; then
        print_success "CA сертификат создан"
    else
        print_error "Ошибка при создании CA сертификата"
        return 1
    fi
    
    # Добавляем CA сертификат в список доверенных
    local ca_trust_dir="/usr/share/ca-certificates/monq"
    if run_sudo mkdir -p "$ca_trust_dir"; then
        if run_sudo cp "$ca_crt" "$ca_trust_dir/monq.ca.crt"; then
            print_success "CA сертификат скопирован в доверенные"
        else
            print_warning "Не удалось скопировать CA сертификат в доверенные"
        fi
    fi
    
    # Обновляем список доверенных сертификатов
    if run_sudo update-ca-trust; then
        print_success "Список доверенных сертификатов обновлен"
    else
        print_warning "Не удалось обновить список доверенных сертификатов"
    fi
    
    # Устанавливаем права доступа
    run_sudo chmod 644 "$ca_crt"
    run_sudo chmod 600 "$ca_key"
    
    return 0
}

# Установка Helm
install_helm() {
    print_section "Установка Helm"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка Helm"
        return 0
    fi
    
    # Проверяем, установлен ли уже Helm
    if command -v /usr/local/bin/helm >/dev/null 2>&1; then
        print_info "Helm уже установлен"
        return 0
    fi
    
    # Версия Helm из документации MONQ
    local arch="amd64"
    # local helm_url="https://get.helm.sh/helm-${HELM_VERSION}-linux-${arch}.tar.gz"
    local helm_url="https://github.com/pkochnov/skmq/raw/refs/heads/master/packages/helm-${HELM_VERSION}-linux-${arch}.tar.gz"
    local helm_tmp="/tmp/helm-${helm_version}-linux-${arch}.tar.gz"
    
    # Скачиваем Helm
    if wget -q "$helm_url" -O "$helm_tmp"; then
        print_success "Helm скачан"
    else
        print_error "Ошибка при скачивании Helm"
        return 1
    fi
    
    # Извлекаем и устанавливаем Helm
    if tar -xf "$helm_tmp" -C /tmp/ && run_sudo mv /tmp/linux-${arch}/helm /usr/local/bin/; then
        run_sudo chmod +x /usr/local/bin/helm
        print_success "Helm установлен"
        rm -f "$helm_tmp"
        rm -rf "/tmp/linux-${arch}"
    else
        print_error "Ошибка при установке Helm"
        rm -f "$helm_tmp"
        rm -rf "/tmp/linux-${arch}"
        return 1
    fi
    
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
    if tar -xf "$toml_tmp" -C /tmp/ && run_sudo mv /tmp/toml-${toml_version}-x86_64-linux/toml /usr/local/bin/; then
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

# Установка discli
install_discli() {
    print_section "Установка discli"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка discli"
        return 0
    fi
    
    # Проверяем, установлен ли уже discli
    if command -v discli >/dev/null 2>&1; then
        print_info "discli уже установлен"
        return 0
    fi
    
    # Версия discli из документации MONQ
    local discli_version="v0.2.0"
    local discli_url="https://github.com/shdubna/discli/releases/download/${discli_version}/discli_Linux_x86_64.tar.gz"
    local discli_tmp="/tmp/discli_Linux_x86_64.tar.gz"
    
    # Скачиваем discli
    if wget -q "$discli_url" -O "$discli_tmp"; then
        print_success "discli скачан"
    else
        print_error "Ошибка при скачивании discli"
        return 1
    fi
    
    # Извлекаем и устанавливаем discli
    if tar -xf "$discli_tmp" -C /tmp/ && run_sudo mv /tmp/discli /usr/local/bin/; then
        run_sudo chmod +x /usr/local/bin/discli
        print_success "discli установлен"
        rm -f "$discli_tmp"
    else
        print_error "Ошибка при установке discli"
        rm -f "$discli_tmp"
        return 1
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
    
    print_info "Скачиваем runc: $download_url"
    print_info "Proxy: $HTTPS_PROXY"
    
    if wget "$download_url" -O runc; then
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
    
    # Запуск containerd
    if run_sudo systemctl start containerd; then
        print_success "Containerd запущен"
    else
        print_warning "Не удалось запустить containerd"
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
    if run_sudo /usr/local/bin/toml set /tmp/containerd-config.toml 'plugins."io.containerd.grpc.v1.cri".registry.config_path' '/etc/containerd/certs.d' > "$temp_output"; then
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
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/kube-apiserver:${K8S_VERSION}" "registry.k8s.io/kube-apiserver:${K8S_VERSION}"
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/kube-controller-manager:${K8S_VERSION}" "registry.k8s.io/kube-controller-manager:${K8S_VERSION}"
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/kube-scheduler:${K8S_VERSION}" "registry.k8s.io/kube-scheduler:${K8S_VERSION}"
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/kube-proxy:${K8S_VERSION}" "registry.k8s.io/kube-proxy:${K8S_VERSION}"
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/etcd:3.5.15-0" "registry.k8s.io/etcd:3.5.15-0"
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/pause:3.10" "registry.k8s.io/pause:3.10"
   else
        print_warning "Не удалось загрузить образы с локального реестра, будет использован стандартный репозиторий"
        log_warn "Возможно, локальный реестр недоступен или образы не загружены в него"
    fi
    
    # Дополнительная загрузка образа pause:3.8
    print_info "Загрузка образа pause:3.8 с локального реестра..."
    if run_sudo crictl pull registry:5000/pause:3.8; then
        # Тегируем образ pause:3.8 для совместимости с Kubernetes
        run_sudo /usr/local/bin/ctr -n k8s.io images tag "registry:5000/pause:3.8" "registry.k8s.io/pause:3.8"
        print_success "Образ pause:3.8 загружен с локального реестра"
    else
        print_warning "Не удалось загрузить образ pause:3.8 с локального реестра"
        log_warn "Возможно, образ pause:3.8 не загружен в локальный реестр"
    fi
    
    return 0
}

# Инициализация кластера
initialize_cluster() {
    print_section "Инициализация кластера Kubernetes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Инициализация кластера Kubernetes"
        return 0
    fi
    
    # Получаем IP адрес текущего хоста
    local host_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    if [[ -z "$host_ip" ]]; then
        print_error "Не удалось определить IP адрес хоста"
        return 1
    fi
    
    print_info "IP адрес контроллера: $host_ip"
    
    # Команда инициализации кластера
    local init_cmd="kubeadm init \
        --v=2 \
        --pod-network-cidr=$POD_NETWORK_CIDR \
        --service-cidr=$SERVICE_CIDR \
        --apiserver-advertise-address=$host_ip \
        --apiserver-bind-port=$K8S_API_PORT \
        --token-ttl=$K8S_TOKEN_TTL \
        --image-repository=registry:5000 \
        --cri-socket=unix:///var/run/containerd/containerd.sock"
    
    print_info "Выполнение команды инициализации кластера..."
    log_info "Команда: $init_cmd"
    
    if run_sudo $init_cmd; then
        print_success "Кластер Kubernetes инициализирован"
    else
        print_error "Ошибка при инициализации кластера"
        return 1
    fi
    
    return 0
}

# Настройка kubeconfig для пользователя
setup_kubeconfig() {
    print_section "Настройка kubeconfig для пользователя $MONQ_USER"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка kubeconfig для пользователя $MONQ_USER"
        return 0
    fi
    
    # Создание директории .kube для пользователя
    if run_sudo mkdir -p /home/$MONQ_USER/.kube; then
        log_debug "Директория .kube создана для пользователя $MONQ_USER"
    else
        print_error "Ошибка при создании директории .kube"
        return 1
    fi
    
    # Копирование kubeconfig
    if run_sudo cp /etc/kubernetes/admin.conf /home/$MONQ_USER/.kube/config; then
        log_debug "kubeconfig скопирован для пользователя $MONQ_USER"
    else
        print_error "Ошибка при копировании kubeconfig"
        return 1
    fi
    
    # Установка прав доступа
    if run_sudo chown -R $MONQ_USER:$MONQ_USER /home/$MONQ_USER/.kube; then
        print_success "Права доступа установлены для kubeconfig"
    else
        print_error "Ошибка при установке прав доступа для kubeconfig"
        return 1
    fi
    
    # Копирование kubeconfig для root
    if run_sudo mkdir -p /root/.kube; then
        if run_sudo cp /etc/kubernetes/admin.conf /root/.kube/config; then
            print_success "kubeconfig настроен для root"
        else
            print_warning "Не удалось настроить kubeconfig для root"
        fi
    fi
    
    return 0
}

# Установка CNI плагина
install_cni_plugin() {
    print_section "Установка CNI плагина: $CNI_PLUGIN"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Установка CNI плагина: $CNI_PLUGIN"
        return 0
    fi
    
    case "$CNI_PLUGIN" in
        "cilium")
            install_cilium
            ;;
        "calico")
            install_calico
            ;;
        "flannel")
            install_flannel
            ;;
        *)
            print_error "Неподдерживаемый CNI плагин: $CNI_PLUGIN"
            return 1
            ;;
    esac
}

# Установка Cilium
install_cilium() {
    print_info "Установка Cilium CNI версии 1.16.5..."
    
    # Установка Cilium CLI
    local cilium_cli_url="https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz"
    local cilium_cli_tmp="/tmp/cilium-cli.tar.gz"
    
    if curl -s -L "$cilium_cli_url" -o "$cilium_cli_tmp"; then
        log_debug "Cilium CLI скачан"
    else
        print_error "Ошибка при скачивании Cilium CLI"
        return 1
    fi
    
    # Распаковка и установка CLI
    if tar -xzf "$cilium_cli_tmp" -C /tmp/ && run_sudo mv /tmp/cilium /usr/local/bin/; then
        print_success "Cilium CLI установлен"
        rm -f "$cilium_cli_tmp"
    else
        print_error "Ошибка при установке Cilium CLI"
        rm -f "$cilium_cli_tmp"
        return 1
    fi
    
    # Установка Cilium с помощью Helm
    print_info "Установка Cilium через Helm..."
    
    # Добавление репозитория Cilium
    if run_sudo /usr/local/bin/helm repo add cilium https://helm.cilium.io/; then
        log_debug "Репозиторий Cilium добавлен"
    else
        print_error "Ошибка при добавлении репозитория Cilium"
        return 1
    fi
    
    # Обновление репозиториев
    if run_sudo /usr/local/bin/helm repo update; then
        log_debug "Репозитории Helm обновлены"
    else
        print_warning "Не удалось обновить репозитории Helm"
    fi
    
    # Используем IP адрес контроллера из hosts.conf
    local host_ip="$HOST_CONTROLLER_IP"
    if [[ -z "$host_ip" ]]; then
        print_error "Не удалось получить IP адрес контроллера из hosts.conf"
        return 1
    fi
    
    # Установка Cilium с настройками
    local cilium_values="
cluster:
  name: $K8S_CLUSTER_NAME
  id: 1
ipam:
  mode: kubernetes
k8s:
  requireIPv4PodCIDR: true
  requireIPv6PodCIDR: false
ipv4:
  enabled: true
ipv6:
  enabled: false
kubeProxyReplacement: false
k8sServiceHost: $host_ip
k8sServicePort: 6443
# Дополнительные настройки для совместимости
cni:
  chainingMode: none
  customConf: false
  excludeMaster: false
  logFormat: json
  logSeverity: info
  uninstall: false
debug:
  enabled: false
  verbose: cilium
  verboseFlow: false
  verbosePolicy: false
hubble:
  enabled: true
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - port-distribution
      - icmp
      - http
  relay:
    enabled: true
  ui:
    enabled: true
    ingress:
      enabled: false
operator:
  enabled: true
  replicas: 1
  unmanagedPodWatcher:
    restart: false
"
    
    # Создание временного файла с настройками
    local cilium_config="/tmp/cilium-values.yaml"
    echo "$cilium_values" > "$cilium_config"
    
    # Установка Cilium
    if run_sudo /usr/local/bin/helm install cilium cilium/cilium --version "$CILIUM_VERSION" --namespace kube-system --values "$cilium_config"; then
        print_success "Cilium CNI установлен через Helm"
    else
        print_warning "Ошибка при установке Cilium через Helm, пробуем альтернативный способ..."
        
        # Альтернативный способ установки через манифест
        local cilium_manifest_url="https://raw.githubusercontent.com/cilium/cilium/v$CILIUM_VERSION/install/kubernetes/quick-install.yaml"
        local cilium_manifest="/tmp/cilium-manifest.yaml"
        
        if curl -s -L "$cilium_manifest_url" -o "$cilium_manifest"; then
            print_info "Cilium манифест скачан, применяем..."
            if run_sudo kubectl apply -f "$cilium_manifest"; then
                print_success "Cilium CNI установлен через манифест"
                rm -f "$cilium_manifest"
            else
                print_error "Ошибка при установке Cilium через манифест"
                rm -f "$cilium_config" "$cilium_manifest"
                return 1
            fi
        else
            print_error "Ошибка при скачивании Cilium манифеста"
            rm -f "$cilium_config"
            return 1
        fi
    fi
    
    # Очистка временных файлов
    rm -f "$cilium_config"
    
    # Ожидание готовности Cilium
    print_info "Ожидание готовности Cilium..."
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if run_sudo kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -q "Running"; then
            print_success "Cilium готов к работе"
            break
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        
        if [[ $elapsed -ge $timeout ]]; then
            print_warning "Таймаут ожидания готовности Cilium"
            break
        fi
    done
    
    return 0
}

# Установка Calico
install_calico() {
    print_info "Установка Calico CNI..."
    
    # Скачивание манифеста Calico
    local calico_url="https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/tigera-operator.yaml"
    local calico_manifest="/tmp/calico-operator.yaml"
    
    if curl -s -L "$calico_url" -o "$calico_manifest"; then
        log_debug "Манифест Calico скачан"
    else
        print_error "Ошибка при скачивании манифеста Calico"
        return 1
    fi
    
    # Применение манифеста
    if run_sudo kubectl apply -f "$calico_manifest"; then
        print_success "Calico operator установлен"
    else
        print_error "Ошибка при установке Calico operator"
        rm -f "$calico_manifest"
        return 1
    fi
    
    # Скачивание конфигурации Calico
    local calico_config_url="https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/custom-resources.yaml"
    local calico_config="/tmp/calico-config.yaml"
    
    if curl -s -L "$calico_config_url" -o "$calico_config"; then
        log_debug "Конфигурация Calico скачана"
    else
        print_error "Ошибка при скачивании конфигурации Calico"
        rm -f "$calico_manifest" "$calico_config"
        return 1
    fi
    
    # Настройка CIDR в конфигурации
    if sed -i "s|192.168.0.0/16|$POD_NETWORK_CIDR|g" "$calico_config"; then
        log_debug "CIDR настроен в конфигурации Calico"
    else
        print_warning "Не удалось настроить CIDR в конфигурации Calico"
    fi
    
    # Применение конфигурации
    if run_sudo kubectl apply -f "$calico_config"; then
        print_success "Calico CNI установлен и настроен"
    else
        print_error "Ошибка при установке Calico CNI"
        rm -f "$calico_manifest" "$calico_config"
        return 1
    fi
    
    # Очистка временных файлов
    rm -f "$calico_manifest" "$calico_config"
    
    return 0
}

# Установка Flannel
install_flannel() {
    print_info "Установка Flannel CNI..."
    
    # Скачивание манифеста Flannel
    local flannel_url="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    local flannel_manifest="/tmp/flannel.yaml"
    
    if curl -s -L "$flannel_url" -o "$flannel_manifest"; then
        log_debug "Манифест Flannel скачан"
    else
        print_error "Ошибка при скачивании манифеста Flannel"
        return 1
    fi
    
    # Настройка CIDR в манифесте
    if sed -i "s|10.244.0.0/16|$POD_NETWORK_CIDR|g" "$flannel_manifest"; then
        log_debug "CIDR настроен в манифесте Flannel"
    else
        print_warning "Не удалось настроить CIDR в манифесте Flannel"
    fi
    
    # Применение манифеста
    if run_sudo kubectl apply -f "$flannel_manifest"; then
        print_success "Flannel CNI установлен и настроен"
    else
        print_error "Ошибка при установке Flannel CNI"
        rm -f "$flannel_manifest"
        return 1
    fi
    
    # Очистка временных файлов
    rm -f "$flannel_manifest"
    
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
    
    # Порты для Kubernetes
    local ports=(
        "6443/tcp"      # Kubernetes API server
        "2379-2380/tcp" # etcd server client API
        "10250/tcp"     # Kubelet API
        "10251/tcp"     # kube-scheduler
        "10252/tcp"     # kube-controller-manager
        "10255/tcp"     # Read-only Kubelet API
        "179/tcp"       # Calico BGP
        "4789/udp"      # Calico VXLAN
        "5473/tcp"      # Calico Typha
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

# Создание токена для присоединения worker узлов
create_join_token() {
    print_section "Создание токена для присоединения worker узлов"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Создание токена для присоединения worker узлов"
        return 0
    fi
    
    # Создание токена
    local join_token=$(run_sudo kubeadm token create --ttl="$K8S_TOKEN_TTL" --print-join-command 2>/dev/null)
    if [[ -n "$join_token" ]]; then
        print_success "Токен для присоединения создан"
        echo
        echo -e "${CYAN}${BOLD}Команда для присоединения worker узлов:${NC}"
        echo -e "${GREEN}$join_token${NC}"
        echo
        
        # Сохранение токена в файл
        local token_file="/tmp/k8s-join-token.txt"
        echo "$join_token" > "$token_file"
        run_sudo chmod 644 "$token_file"
        print_info "Токен сохранен в файл: $token_file"
        
        log_info "Токен для присоединения: $join_token"
    else
        print_error "Ошибка при создании токена для присоединения"
        return 1
    fi
    
    return 0
}

# Проверка установки кластера
verify_cluster_installation() {
    print_section "Проверка установки кластера"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка установки кластера"
        return 0
    fi
    
    local failed_checks=0
    
    # Проверка статуса узлов
    print_info "Проверка статуса узлов кластера..."
    if run_sudo kubectl get nodes; then
        print_success "Узлы кластера доступны"
    else
        print_error "Не удалось получить информацию об узлах кластера"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка статуса подов
    print_info "Проверка статуса подов..."
    if run_sudo kubectl get pods --all-namespaces; then
        print_success "Поды доступны"
    else
        print_error "Не удалось получить информацию о подах"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка статуса сервисов
    print_info "Проверка статуса сервисов..."
    if run_sudo kubectl get services --all-namespaces; then
        print_success "Сервисы доступны"
    else
        print_error "Не удалось получить информацию о сервисах"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Проверка готовности узла
    print_info "Проверка готовности контроллерного узла..."
    local node_status=$(run_sudo kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$node_status" == "True" ]]; then
        print_success "Контроллерный узел готов"
    else
        print_warning "Контроллерный узел не готов (статус: $node_status)"
        failed_checks=$((failed_checks + 1))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "Все проверки кластера пройдены успешно"
        return 0
    else
        print_warning "Провалено $failed_checks проверок кластера"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка Kubernetes Controller для Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-k8s-controller-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки Kubernetes Controller"
    log_info "Версия Kubernetes: $K8S_VERSION"
    log_info "Сеть подов: $POD_NETWORK_CIDR"
    log_info "Сеть сервисов: $SERVICE_CIDR"
    log_info "CNI плагин: $CNI_PLUGIN"
    log_info "Порт API сервера: $K8S_API_PORT"
    log_info "Имя кластера: $K8S_CLUSTER_NAME"
    log_info "Время жизни токена: $K8S_TOKEN_TTL"
    log_info "Режим симуляции: $DRY_RUN"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_system_requirements"
        "install_system_packages"
        "create_ca_certificates"
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
        "install_helm"
        "install_discli"
        "initialize_cluster"
        "setup_kubeconfig"
        "install_cni_plugin"
        "configure_firewall"
        "create_join_token"
        "verify_cluster_installation"
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
    
    log_info "Установка Kubernetes Controller завершена успешно"
    
    # Информация для пользователя
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Kubernetes Controller успешно установлен ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    echo -e "${BLUE}Версия Kubernetes:${NC} $K8S_VERSION"
    echo -e "${BLUE}Сеть подов:${NC} $POD_NETWORK_CIDR"
    echo -e "${BLUE}Сеть сервисов:${NC} $SERVICE_CIDR"
    echo -e "${BLUE}CNI плагин:${NC} $CNI_PLUGIN"
    echo -e "${BLUE}Имя кластера:${NC} $K8S_CLUSTER_NAME"
    echo
    echo -e "${YELLOW}Для использования kubectl пользователю $MONQ_USER необходимо перелогиниться${NC}"
    echo -e "${YELLOW}Или выполнить команду: source /home/$MONQ_USER/.kube/config${NC}"
    echo
    echo -e "${BLUE}Лог файл:${NC} $log_file"
    
    log_info "Для использования kubectl пользователю $MONQ_USER необходимо перелогиниться"
    log_info "Или выполнить команду: source /home/$MONQ_USER/.kube/config"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
