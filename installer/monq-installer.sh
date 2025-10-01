#!/bin/bash
# =============================================================================
# Главный интерактивный скрипт установщика инфраструктуры Monq
# =============================================================================
# Назначение: Интерактивное управление установкой и настройкой инфраструктуры
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/scripts/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию
SELECTED_HOST=""
SELECTED_ACTION=""
DRY_RUN=false
FORCE=false
LOG_LEVEL="INFO"

# Дополнительные параметры для Kubernetes Worker
MASTER_IP=""
JOIN_TOKEN=""
DISCOVERY_TOKEN_CA_CERT_HASH=""

# Массивы для меню
declare -a HOST_MENU_ITEMS=()
declare -a ACTION_MENU_ITEMS=()

# =============================================================================
# Цветовое оформление
# =============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Функции для цветного вывода
print_error() {
    echo -e "${RED}${BOLD}[ОШИБКА]${NC} ${RED}$1${NC}"
}

print_success() {
    echo -e "${GREEN}${BOLD}[УСПЕХ]${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}[ПРЕДУПРЕЖДЕНИЕ]${NC} ${YELLOW}$1${NC}"
}

print_info() {
    echo -e "${BLUE}${BOLD}[ИНФО]${NC} ${BLUE}$1${NC}"
}

print_header() {
    echo -e "${CYAN}${BOLD}$1${NC}"
}

print_menu_item() {
    echo -e "${WHITE}$1${NC}"
}

print_prompt() {
    echo -e -n "${PURPLE}$*${NC}"
}

# =============================================================================
# Обработка сигналов
# =============================================================================

# Функция обработки сигнала SIGINT (Ctrl+C)
handle_interrupt() {
    echo
    echo
    log_info "Получен сигнал прерывания (Ctrl+C)"
    log_info "Завершение работы установщика..."
    
    # Очистка ресурсов
    cleanup
    
    exit 130  # Стандартный код выхода для SIGINT
}

# Установка обработчика сигнала
trap handle_interrupt SIGINT

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --host HOST           Указать хост напрямую (пропустить интерактивный выбор)
    --action ACTION       Указать действие напрямую
    --config PATH         Путь к файлу конфигурации
    --log-level LEVEL     Уровень логирования (DEBUG, INFO, WARN, ERROR)
    --k8s-version VERSION Версия Kubernetes (по умолчанию: $K8S_VERSION)
    --dry-run             Режим симуляции (без выполнения команд)
    --force               Принудительное выполнение (без подтверждений)
    --help                Показать эту справку

Дополнительные опции для Kubernetes Worker:
    --master-ip IP        IP адрес контроллерного узла
    --join-token TOKEN    Токен для присоединения к кластеру
    --discovery-token-ca-cert-hash HASH  Хэш CA сертификата

Примеры:
    $0 --host k01 --action setup-os
    $0 --host k01 --action install-k8s-controller --k8s-version 1.31.4
    $0 --host k02 --action install-k8s-worker --master-ip 10.72.66.51 --join-token abc123.def456 --discovery-token-ca-cert-hash sha256:...
    $0 --dry-run
    $0 --log-level DEBUG

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                SELECTED_HOST="$2"
                shift 2
                ;;
            --action)
                SELECTED_ACTION="$2"
                shift 2
                ;;
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --k8s-version)
                K8S_VERSION="$2"
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
            --master-ip)
                MASTER_IP="$2"
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
    if [[ -n "$LOG_LEVEL" ]]; then
        case "$LOG_LEVEL" in
            DEBUG|INFO|WARN|ERROR)
                ;;
            *)
                log_error "Неверный уровень логирования: $LOG_LEVEL (допустимо: DEBUG, INFO, WARN, ERROR)"
                exit 1
                ;;
        esac
    fi
    
    # Валидация версии Kubernetes
    if [[ -n "$K8S_VERSION" ]]; then
        if [[ ! "$K8S_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            log_error "Неверный формат версии Kubernetes: $K8S_VERSION (ожидается: X.Y или X.Y.Z)"
            exit 1
        fi
    fi
}

# Загрузка информации о хостах
load_hosts_info() {
    log_info "Загрузка информации о хостах..."
    
    # Очистка массивов
    HOST_MENU_ITEMS=()
    
    # Загрузка хостов из конфигурации
    local host_index=1
    
    # Kubernetes хосты
    for host_var in "${HOSTS_K8S[@]}"; do
        local hostname_var="${host_var}_HOSTNAME"
        local ip_var="${host_var}_IP"
        local alias_var="${host_var}_ALIAS"
        local description_var="${host_var}_DESCRIPTION"
        
        local hostname="${!hostname_var}"
        local ip="${!ip_var}"
        local alias="${!alias_var}"
        local description="${!description_var}"
        
        HOST_MENU_ITEMS+=("$host_index|$hostname|$ip|$alias|$description|k8s")
        host_index=$((host_index + 1))
    done
    
    # Docker хосты
    for host_var in "${HOSTS_DOCKER[@]}"; do
        local hostname_var="${host_var}_HOSTNAME"
        local ip_var="${host_var}_IP"
        local alias_var="${host_var}_ALIAS"
        local description_var="${host_var}_DESCRIPTION"
        
        local hostname="${!hostname_var}"
        local ip="${!ip_var}"
        local alias="${!alias_var}"
        local description="${!description_var}"
        
        HOST_MENU_ITEMS+=("$host_index|$hostname|$ip|$alias|$description|docker")
        host_index=$((host_index + 1))
    done
    
    log_info "Загружено ${#HOST_MENU_ITEMS[@]} хостов"
}

# Получение информации о хосте по индексу
get_host_info() {
    local index="$1"
    local info_type="$2"  # hostname, ip, alias, description, type
    
    for item in "${HOST_MENU_ITEMS[@]}"; do
        IFS='|' read -r item_index hostname ip alias description type <<< "$item"
        if [[ "$item_index" == "$index" ]]; then
            case "$info_type" in
                hostname) echo "$hostname" ;;
                ip) echo "$ip" ;;
                alias) echo "$alias" ;;
                description) echo "$description" ;;
                type) echo "$type" ;;
                *) echo "" ;;
            esac
            return 0
        fi
    done
    return 1
}

# Получение токена присоединения с контроллерного узла
get_join_token_from_controller() {
    local controller_ip="$1"
    
    print_info "Получение токена присоединения с контроллерного узла $controller_ip..."
    
    # Получение команды присоединения
    local join_command=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 monq@$controller_ip "kubeadm token create --print-join-command" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$join_command" ]]; then
        print_success "Токен присоединения получен"
        echo "$join_command"
        return 0
    else
        print_error "Не удалось получить токен присоединения с контроллерного узла"
        return 1
    fi
}

# Извлечение параметров из команды присоединения
extract_join_parameters() {
    local join_command="$1"
    
    # Извлекаем IP адрес мастера
    local master_ip=$(echo "$join_command" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    # Извлекаем токен
    local join_token=$(echo "$join_command" | grep -oE -- '--token [a-z0-9]+\.[a-z0-9]+' | cut -d' ' -f2)
    
    # Извлекаем хэш CA сертификата
    local ca_cert_hash=$(echo "$join_command" | grep -oE -- '--discovery-token-ca-cert-hash sha256:[a-f0-9]+' | cut -d' ' -f2)
    
    echo "$master_ip|$join_token|$ca_cert_hash"
}


show_logo() {
    echo -e "${CYAN}${BOLD}"
    echo "   _____ __       ____           __        ____         "
    echo "  ╱ ___╱╱ ╱      ╱  _╱___  _____╱ ╱_____ _╱ ╱ ╱__  _____"
    echo "  ╲__ ╲╱ ╱       ╱ ╱╱ __ ╲╱ ___╱ __╱ __ \`╱ ╱ ╱ _ ╲╱ ___╱"
    echo " ___╱ ╱ ╱___   _╱ ╱╱ ╱ ╱ (__  ) ╱_╱ ╱_╱ ╱ ╱ ╱  __╱ ╱    "
    echo "╱____╱_____╱  ╱___╱_╱ ╱_╱____╱╲__╱╲__,_╱_╱_╱╲___╱_╱     "
    echo "                                                        "
    echo -e "${NC}"
}

# Отображение главного меню
show_main_menu() {
    clear
    show_logo
    print_header "=================================================================="
    print_header "=== Установщик инфраструктуры Monq ==="
    print_header "=================================================================="
    echo
    print_menu_item "1. Выбрать хост"
    print_menu_item "2. Общая проверка состояния"
    print_menu_item "3. Выход"
    echo
    print_prompt "Выберите действие [1-3]: "
}

# Отображение меню выбора хоста
show_host_menu() {
    clear
    show_logo
    print_header "=================================================================="
    print_header "=== Выбор хоста ==="
    print_header "=================================================================="
    echo
    
    # Kubernetes кластер
    print_info "Kubernetes кластер:"
    for item in "${HOST_MENU_ITEMS[@]}"; do
        IFS='|' read -r index hostname ip alias description type <<< "$item"
        if [[ "$type" == "k8s" ]]; then
            print_menu_item "  $index. $hostname ($alias) - $ip - $description"
        fi
    done
    echo
    
    # Docker сервисы
    print_info "Docker сервисы:"
    for item in "${HOST_MENU_ITEMS[@]}"; do
        IFS='|' read -r index hostname ip alias description type <<< "$item"
        if [[ "$type" == "docker" ]]; then
            print_menu_item "  $index. $hostname ($alias) - $ip - $description"
        fi
    done
    echo
    
    print_menu_item "0. Назад"
    echo
    print_prompt "Выберите хост [0-${#HOST_MENU_ITEMS[@]}]: "
}

# Отображение меню действий для хоста
show_action_menu() {
    local hostname="$1"
    local alias="$2"
    local host_type="$3"
    
    clear
    print_header "=================================================================="
    print_header "=== Действия для $hostname ($alias) ==="
    print_header "=================================================================="
    echo
    
    # Очистка массива действий
    ACTION_MENU_ITEMS=()
    local action_index=1
    
    # Общие действия
    print_info "Общие действия:"
    print_menu_item "  $action_index. Настройка базовой ОС"
    ACTION_MENU_ITEMS+=("$action_index|setup-os")
    action_index=$((action_index + 1))
    
    print_menu_item "  $action_index. Проверка состояния ОС"
    ACTION_MENU_ITEMS+=("$action_index|check-os")
    action_index=$((action_index + 1))
    
    # Действия в зависимости от типа хоста
    if [[ "$host_type" == "k8s" ]]; then
        echo
        print_info "Kubernetes действия:"
        if [[ "$alias" == "k01" ]]; then
            print_menu_item "  $action_index. Установка Kubernetes Controller"
            ACTION_MENU_ITEMS+=("$action_index|install-k8s-controller")
            action_index=$((action_index + 1))
            
            print_menu_item "  $action_index. Проверка состояния Kubernetes Controller"
            ACTION_MENU_ITEMS+=("$action_index|check-k8s-controller")
            action_index=$((action_index + 1))
            
            print_menu_item "  $action_index. Сброс кластера Kubernetes"
            ACTION_MENU_ITEMS+=("$action_index|reset-k8s-cluster")
            action_index=$((action_index + 1))
            
            print_menu_item "  $action_index. Установка MONQ на контроллерном узле"
            ACTION_MENU_ITEMS+=("$action_index|install-monq-controller")
            action_index=$((action_index + 1))
        else
            print_menu_item "  $action_index. Установка Kubernetes Worker"
            ACTION_MENU_ITEMS+=("$action_index|install-k8s-worker")
            action_index=$((action_index + 1))
            
            print_menu_item "  $action_index. Проверка состояния Kubernetes Worker"
            ACTION_MENU_ITEMS+=("$action_index|check-k8s-worker")
            action_index=$((action_index + 1))
        fi
    else
        echo
        print_info "Docker действия:"
        print_menu_item "  $action_index. Установка Docker"
        ACTION_MENU_ITEMS+=("$action_index|install-docker")
        action_index=$((action_index + 1))
        
        print_menu_item "  $action_index. Проверка состояния Docker"
        ACTION_MENU_ITEMS+=("$action_index|check-docker")
        action_index=$((action_index + 1))
        
        # Действия для конкретных сервисов
        case "$alias" in
            arangodb)
                print_menu_item "  $action_index. Установка ArangoDB"
                ACTION_MENU_ITEMS+=("$action_index|install-arangodb")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка ArangoDB"
                ACTION_MENU_ITEMS+=("$action_index|check-arangodb")
                action_index=$((action_index + 1))
                ;;
            clickhouse)
                print_menu_item "  $action_index. Установка ClickHouse"
                ACTION_MENU_ITEMS+=("$action_index|install-clickhouse")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка ClickHouse"
                ACTION_MENU_ITEMS+=("$action_index|check-clickhouse")
                action_index=$((action_index + 1))
                ;;
            postgres)
                print_menu_item "  $action_index. Установка PostgreSQL"
                ACTION_MENU_ITEMS+=("$action_index|install-postgresql")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка PostgreSQL"
                ACTION_MENU_ITEMS+=("$action_index|check-postgresql")
                action_index=$((action_index + 1))
                ;;
            rabbitmq)
                print_menu_item "  $action_index. Установка RabbitMQ"
                ACTION_MENU_ITEMS+=("$action_index|install-rabbitmq")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка RabbitMQ"
                ACTION_MENU_ITEMS+=("$action_index|check-rabbitmq")
                action_index=$((action_index + 1))
                ;;
            victoriametrics)
                print_menu_item "  $action_index. Установка VictoriaMetrics"
                ACTION_MENU_ITEMS+=("$action_index|install-victoriametrics")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка VictoriaMetrics"
                ACTION_MENU_ITEMS+=("$action_index|check-victoriametrics")
                action_index=$((action_index + 1))
                ;;
            redis)
                print_menu_item "  $action_index. Установка Redis"
                ACTION_MENU_ITEMS+=("$action_index|install-redis")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка Redis"
                ACTION_MENU_ITEMS+=("$action_index|check-redis")
                action_index=$((action_index + 1))
                ;;
            consul)
                print_menu_item "  $action_index. Установка Consul"
                ACTION_MENU_ITEMS+=("$action_index|install-consul")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка Consul"
                ACTION_MENU_ITEMS+=("$action_index|check-consul")
                action_index=$((action_index + 1))
                ;;
            registry)
                print_menu_item "  $action_index. Установка Docker Registry"
                ACTION_MENU_ITEMS+=("$action_index|install-registry")
                action_index=$((action_index + 1))
                
                print_menu_item "  $action_index. Проверка Docker Registry"
                ACTION_MENU_ITEMS+=("$action_index|check-registry")
                action_index=$((action_index + 1))
                ;;
            prometheus)
                print_menu_item "  $action_index. Установка Prometheus + Grafana"
                ACTION_MENU_ITEMS+=("$action_index|install-prometheus-grafana")
                action_index=$((action_index + 1))
                ;;
            elk)
                print_menu_item "  $action_index. Установка ELK Stack"
                ACTION_MENU_ITEMS+=("$action_index|install-elk")
                action_index=$((action_index + 1))
                ;;
        esac
        
        # Проверка состояния сервиса только для сервисов с реализованными скриптами проверки
        # Исключаем сервисы, у которых есть собственные скрипты проверки (arangodb, clickhouse, postgres, rabbitmq, registry)
        # и сервисы без скриптов проверки
        case "$alias" in
            prometheus|elk)
                # Эти сервисы не имеют скриптов проверки - пропускаем
                ;;
            *)
                # Для остальных сервисов (если есть общий скрипт check-services.sh)
                if [[ -f "$PROJECT_DIR/scripts/check-services.sh" ]]; then
                    print_menu_item "  $action_index. Проверка состояния сервиса"
                    ACTION_MENU_ITEMS+=("$action_index|check-service")
                    action_index=$((action_index + 1))
                fi
                ;;
        esac
    fi
    
    echo
    print_menu_item "0. Назад"
    echo
    print_prompt "Выберите действие [0-$((action_index-1))]: "
}

# Получение действия по индексу
get_action_by_index() {
    local index="$1"
    
    for item in "${ACTION_MENU_ITEMS[@]}"; do
        IFS='|' read -r item_index action <<< "$item"
        if [[ "$item_index" == "$index" ]]; then
            echo "$action"
            return 0
        fi
    done
    return 1
}

# Выполнение действия
execute_action() {
    local hostname="$1"
    local ip="$2"
    local alias="$3"
    local action="$4"
    
    log_info "Выполнение действия '$action' для хоста '$hostname' ($ip)"
    
    local script_path=""
    local script_args=()
    
    # Определение скрипта и аргументов
    case "$action" in
        setup-os)
            script_path="$PROJECT_DIR/scripts/setup-os.sh"
            script_args=("--hostname" "$hostname" "--ip" "$ip" "--role" "service")
            ;;
        install-docker)
            script_path="$PROJECT_DIR/scripts/install-docker.sh"
            script_args=()
            ;;
        check-os)
            script_path="$PROJECT_DIR/scripts/check-os.sh"
            script_args=("--format" "text")
            ;;
        check-docker)
            script_path="$PROJECT_DIR/scripts/check-docker.sh"
            script_args=("--format" "text")
            ;;
        install-k8s-controller)
            script_path="$PROJECT_DIR/scripts/install-k8s-controller.sh"
            script_args=("--k8s-version" "$K8S_VERSION" "--cni" "cilium" "--pause")
            ;;
        install-k8s-worker)
            script_path="$PROJECT_DIR/scripts/install-k8s-worker.sh"
            # Проверяем, переданы ли необходимые параметры
            if [[ -n "$MASTER_IP" && -n "$JOIN_TOKEN" && -n "$DISCOVERY_TOKEN_CA_CERT_HASH" ]]; then
                script_args=("--master-ip" "$MASTER_IP" "--join-token" "$JOIN_TOKEN" "--discovery-token-ca-cert-hash" "$DISCOVERY_TOKEN_CA_CERT_HASH" "--pause")
                print_info "Используются переданные параметры для Kubernetes Worker"
            else
                # Пытаемся автоматически получить токен с контроллерного узла
                local controller_ip="10.72.66.51"  # IP контроллерного узла k01
                print_info "Попытка автоматического получения токена присоединения..."
                
                local join_command=$(get_join_token_from_controller "$controller_ip")
                if [[ $? -eq 0 && -n "$join_command" ]]; then
                    # Извлекаем параметры из команды присоединения
                    local join_params=$(extract_join_parameters "$join_command")
                    IFS='|' read -r master_ip join_token ca_cert_hash <<< "$join_params"
                    
                    if [[ -n "$master_ip" && -n "$join_token" && -n "$ca_cert_hash" ]]; then
                        script_args=("--master-ip" "$master_ip" "--join-token" "$join_token" "--discovery-token-ca-cert-hash" "$ca_cert_hash" "--pause")
                        print_success "Параметры присоединения получены автоматически"
                    else
                        print_error "Не удалось извлечь параметры из команды присоединения"
                        return 1
                    fi
                else
                    # Для worker узлов нужны дополнительные параметры
                    print_warning "Для установки Kubernetes Worker требуются дополнительные параметры:"
                    print_info "  --master-ip IP - IP адрес контроллерного узла"
                    print_info "  --join-token TOKEN - токен для присоединения к кластеру"
                    print_info "  --discovery-token-ca-cert-hash HASH - хэш CA сертификата"
                    echo
                    print_info "Пример использования:"
                    print_info "  $0 --host $alias --action install-k8s-worker --master-ip 10.72.66.51 --join-token abc123.def456 --discovery-token-ca-cert-hash sha256:..."
                    echo
                    print_prompt "Продолжить с параметрами по умолчанию? (y/N): "
                    read -r continue_choice
                    if [[ "$continue_choice" =~ ^[Yy]$ ]]; then
                        script_args=("--master-ip" "10.72.66.51" "--join-token" "PLACEHOLDER" "--discovery-token-ca-cert-hash" "PLACEHOLDER" "--pause")
                        print_warning "ВНИМАНИЕ: Используются заглушки для токена и хэша. Установка может завершиться ошибкой."
                    else
                        print_info "Установка отменена. Используйте командную строку с правильными параметрами."
                        return 1
                    fi
                fi
            fi
            ;;
        check-k8s-controller)
            script_path="$PROJECT_DIR/scripts/check-k8s-controller.sh"
            script_args=("--format" "text")
            ;;
        check-k8s-worker)
            script_path="$PROJECT_DIR/scripts/check-k8s-worker.sh"
            script_args=("--format" "text")
            ;;
        reset-k8s-cluster)
            script_path="$PROJECT_DIR/scripts/reset-k8s-cluster.sh"
            script_args=("--interactive")
            ;;
        install-monq-controller)
            script_path="$PROJECT_DIR/scripts/install-monq-controller.sh"
            script_args=()
            ;;
        install-arangodb)
            script_path="$PROJECT_DIR/scripts/install-arangodb.sh"
            script_args=()
            ;;
        check-arangodb)
            script_path="$PROJECT_DIR/scripts/check-arangodb.sh"
            script_args=("--format" "text")
            ;;
        install-clickhouse)
            script_path="$PROJECT_DIR/scripts/install-clickhouse.sh"
            script_args=()
            ;;
        check-clickhouse)
            script_path="$PROJECT_DIR/scripts/check-clickhouse.sh"
            script_args=("--format" "text")
            ;;
        install-postgresql)
            script_path="$PROJECT_DIR/scripts/install-postgresql.sh"
            script_args=()
            ;;
        check-postgresql)
            script_path="$PROJECT_DIR/scripts/check-postgresql.sh"
            script_args=("--format" "text")
            ;;
        check-redis)
            script_path="$PROJECT_DIR/scripts/check-redis.sh"
            script_args=("--format" "text")
            ;;
        install-rabbitmq)
            script_path="$PROJECT_DIR/scripts/install-rabbitmq.sh"
            script_args=()
            ;;
        check-rabbitmq)
            script_path="$PROJECT_DIR/scripts/check-rabbitmq.sh"
            script_args=("--format" "text")
            ;;
        install-victoriametrics)
            script_path="$PROJECT_DIR/scripts/install-victoriametrics.sh"
            script_args=()
            ;;
        check-victoriametrics)
            script_path="$PROJECT_DIR/scripts/check-victoriametrics.sh"
            script_args=("--format" "text")
            ;;
        install-redis)
            script_path="$PROJECT_DIR/scripts/install-redis.sh"
            script_args=()
            ;;
        install-consul)
            script_path="$PROJECT_DIR/scripts/install-consul.sh"
            script_args=()
            ;;
        check-consul)
            script_path="$PROJECT_DIR/scripts/check-consul.sh"
            script_args=("--format" "text")
            ;;
        install-registry)
            script_path="$PROJECT_DIR/scripts/install-registry.sh"
            script_args=()
            ;;
        check-registry)
            script_path="$PROJECT_DIR/scripts/check-registry.sh"
            script_args=("--format" "text")
            ;;
        install-prometheus-grafana)
            script_path="$PROJECT_DIR/scripts/install-prometheus-grafana.sh"
            script_args=()
            ;;
        install-elk)
            script_path="$PROJECT_DIR/scripts/install-elk.sh"
            script_args=()
            ;;
        check-service)
            script_path="$PROJECT_DIR/scripts/check-services.sh"
            script_args=("--service" "$alias")
            ;;
        *)
            log_error "Неизвестное действие: $action"
            return 1
            ;;
    esac
    
    # Добавление общих аргументов
    if [[ "$DRY_RUN" == "true" ]]; then
        script_args+=("--dry-run")
    fi
    
    if [[ "$FORCE" == "true" ]]; then
        script_args+=("--force")
    fi
    
    # Выполнение скрипта
    log_info "Запуск скрипта: $script_path ${script_args[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Команда: $script_path ${script_args[*]}"
        return 0
    fi
    
    # Проверка существования скрипта
    if [[ ! -f "$script_path" ]]; then
        log_error "Скрипт не найден: $script_path"
        return 1
    fi
    
    # Выполнение через SSH если хост не локальный
    if [[ "$hostname" != "$(hostname)" ]]; then
        log_info "Выполнение на удаленном хосте: $hostname"
        
        # Проверка SSH соединения
        if ! check_ssh_connection "$ip"; then
            log_error "Не удалось установить SSH соединение с $hostname"
            return 1
        fi
        
        # Создание временной директории на удаленном хосте
        local remote_temp_dir="/tmp/monq-$(date +%s)"
        if ! run_ssh "$ip" "$MONQ_USER" "mkdir -p $remote_temp_dir"; then
            log_error "Не удалось создать временную директорию на удаленном хосте"
            return 1
        fi
        
            # Копирование скрипта на удаленный хост
    local remote_script_path="$remote_temp_dir/$(basename "$script_path")"
    if ! scp -o StrictHostKeyChecking=no "$script_path" "$MONQ_USER@$ip:$remote_script_path"; then
        log_error "Не удалось скопировать скрипт на удаленный хост"
        return 1
    fi
    
    # Копирование common.sh на удаленный хост
    local remote_common_path="$remote_temp_dir/common.sh"
    if ! scp -o StrictHostKeyChecking=no "$PROJECT_DIR/scripts/common.sh" "$MONQ_USER@$ip:$remote_common_path"; then
        log_error "Не удалось скопировать common.sh на удаленный хост"
        return 1
    fi
    
    # Копирование конфигурационных файлов на удаленный хост
    local remote_config_dir="$remote_temp_dir/config"
    if ! run_ssh "$ip" "$MONQ_USER" "mkdir -p $remote_config_dir"; then
        log_error "Не удалось создать директорию конфигурации на удаленном хосте"
        return 1
    fi
    
    if ! scp -o StrictHostKeyChecking=no "$PROJECT_DIR/config/monq.conf" "$MONQ_USER@$ip:$remote_config_dir/"; then
        log_error "Не удалось скопировать monq.conf на удаленный хост"
        return 1
    fi
    
    if ! scp -o StrictHostKeyChecking=no "$PROJECT_DIR/config/hosts.conf" "$MONQ_USER@$ip:$remote_config_dir/"; then
        log_error "Не удалось скопировать hosts.conf на удаленный хост"
        return 1
    fi
    
    # Копирование конфигурационных файлов сервисов на удаленный хост
    if [[ -d "$PROJECT_DIR/config" ]]; then
        for service_dir in "$PROJECT_DIR/config"/*; do
            if [[ -d "$service_dir" ]]; then
                local service_name=$(basename "$service_dir")
                local remote_service_dir="$remote_config_dir/$service_name"
                
                # Создание директории сервиса на удаленном хосте
                if ! run_ssh "$ip" "$MONQ_USER" "mkdir -p $remote_service_dir"; then
                    log_error "Не удалось создать директорию $service_name на удаленном хосте"
                    return 1
                fi
                
                # Копирование всех файлов сервиса
                for config_file in "$service_dir"/*; do
                    if [[ -f "$config_file" ]]; then
                        local config_name=$(basename "$config_file")
                        if ! scp -o StrictHostKeyChecking=no "$config_file" "$MONQ_USER@$ip:$remote_service_dir/"; then
                            log_error "Не удалось скопировать конфигурацию $config_name для сервиса $service_name на удаленный хост"
                            return 1
                        fi
                    fi
                done
            fi
        done
    fi
        
        # Выполнение скрипта на удаленном хосте
        local execution_command="cd $remote_temp_dir && chmod +x $(basename "$script_path") && ./$(basename "$script_path") ${script_args[*]}"
        
        # Для скрипта сброса кластера используем интерактивный SSH
        if [[ "$action" == "reset-k8s-cluster" ]]; then
            log_info "Выполнение интерактивного скрипта сброса кластера..."
            if ! ssh -t -o ConnectTimeout="$SSH_TIMEOUT" -o StrictHostKeyChecking=no "$MONQ_USER@$ip" "$execution_command"; then
                log_error "Ошибка при выполнении скрипта сброса кластера на удаленном хосте"
                # Очистка временных файлов даже при ошибке
                run_ssh "$ip" "$MONQ_USER" "rm -rf $remote_temp_dir"
                return 1
            fi
        else
            if ! run_ssh "$ip" "$MONQ_USER" "$execution_command"; then
                log_error "Ошибка при выполнении скрипта на удаленном хосте"
                # Очистка временных файлов даже при ошибке
                run_ssh "$ip" "$MONQ_USER" "rm -rf $remote_temp_dir"
                return 1
            fi
        fi
        
        # Удаление временных файлов с удаленного хоста
        run_ssh "$ip" "$MONQ_USER" "rm -rf $remote_temp_dir"
    else
        # Локальное выполнение
        log_info "Локальное выполнение скрипта"
        if ! bash "$script_path" "${script_args[@]}"; then
            log_error "Ошибка при выполнении скрипта"
            return 1
        fi
    fi
    
    log_info "Действие '$action' выполнено успешно"
    return 0
}

# Общая проверка состояния
check_overall_status() {
    log_info "Выполнение общей проверки состояния..."
    
    print_header "=================================================================="
    print_header "=== Общая проверка состояния инфраструктуры ==="
    print_header "=================================================================="
    echo
    
    # Проверка всех хостов
    for item in "${HOST_MENU_ITEMS[@]}"; do
        IFS='|' read -r index hostname ip alias description type <<< "$item"
        
        print_info "Проверка хоста: $hostname ($alias) - $ip"
        
        # Проверка доступности хоста
        if ping -c 1 -W 3 "$ip" &>/dev/null; then
            print_success "  ✓ Хост доступен"
            
            # Проверка SSH
            if check_ssh_connection "$ip"; then
                print_success "  ✓ SSH доступен"
                
                # Проверка состояния ОС
                if run_ssh "$ip" "$MONQ_USER" "systemctl is-active sshd" &>/dev/null; then
                    print_success "  ✓ SSH сервис активен"
                else
                    print_error "  ✗ SSH сервис неактивен"
                fi
                
                # Дополнительная проверка для Kubernetes узлов
                if [[ "$type" == "k8s" ]]; then
                    print_info "  Проверка состояния Kubernetes..."
                    
                    # Копируем скрипт проверки на хост
                    local check_script=""
                    if [[ "$alias" == "k01" ]]; then
                        check_script="check-k8s-controller.sh"
                    else
                        check_script="check-k8s-worker.sh"
                    fi
                    
                    # Выполняем проверку через SSH
                    if run_ssh "$ip" "$MONQ_USER" "test -f /tmp/$check_script" &>/dev/null; then
                        print_info "  Выполнение проверки Kubernetes..."
                        if run_ssh "$ip" "$MONQ_USER" "chmod +x /tmp/$check_script && /tmp/$check_script --format text" &>/dev/null; then
                            print_success "  ✓ Kubernetes работает корректно"
                        else
                            print_warning "  ⚠ Проблемы с Kubernetes"
                        fi
                    else
                        print_info "  Скрипт проверки Kubernetes не найден на хосте"
                    fi
                fi
            else
                print_error "  ✗ SSH недоступен"
            fi
        else
            print_error "  ✗ Хост недоступен"
        fi
        echo
    done
    
    print_success "Общая проверка завершена"
    echo
    print_prompt "Нажмите Enter для продолжения..."
    read -r
}

# Интерактивный режим
interactive_mode() {
    while true; do
        show_main_menu
        read -r choice
        
        case "$choice" in
            1)
                # Выбор хоста
                while true; do
                    show_host_menu
                    read -r host_choice
                    
                    if [[ "$host_choice" == "0" ]]; then
                        break
                    elif [[ "$host_choice" =~ ^[0-9]+$ ]] && [[ "$host_choice" -ge 1 ]] && [[ "$host_choice" -le ${#HOST_MENU_ITEMS[@]} ]]; then
                        # Получение информации о выбранном хосте
                        local selected_hostname=$(get_host_info "$host_choice" "hostname")
                        local selected_ip=$(get_host_info "$host_choice" "ip")
                        local selected_alias=$(get_host_info "$host_choice" "alias")
                        local selected_type=$(get_host_info "$host_choice" "type")
                        
                        # Меню действий для хоста
                        while true; do
                            show_action_menu "$selected_hostname" "$selected_alias" "$selected_type"
                            read -r action_choice
                            
                            if [[ "$action_choice" == "0" ]]; then
                                break
                            elif [[ "$action_choice" =~ ^[0-9]+$ ]] && [[ "$action_choice" -ge 1 ]]; then
                                local selected_action=$(get_action_by_index "$action_choice")
                                if [[ -n "$selected_action" ]]; then
                                    execute_action "$selected_hostname" "$selected_ip" "$selected_alias" "$selected_action"
                                    echo
                                    print_prompt "Нажмите Enter для продолжения..."
                                    read -r
                                else
                                    print_error "Неверный выбор действия"
                                    sleep 2
                                fi
                            else
                                print_error "Неверный выбор. Попробуйте снова."
                                sleep 2
                            fi
                        done
                    else
                        print_error "Неверный выбор. Попробуйте снова."
                        sleep 2
                    fi
                done
                ;;
            2)
                check_overall_status
                ;;
            3)
                log_info "Выход из программы"
                exit 0
                ;;
            *)
                print_error "Неверный выбор. Попробуйте снова."
                sleep 2
                ;;
        esac
    done
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    show_header "Установщик инфраструктуры Monq"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/monq-installer-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Запуск установщика инфраструктуры Monq"
    log_info "Режим симуляции: $DRY_RUN"
    log_info "Принудительный режим: $FORCE"
    log_info "Уровень логирования: $LOG_LEVEL"
    log_info "Версия Kubernetes: $K8S_VERSION"
    
    # Загрузка информации о хостах
    load_hosts_info
    
    # Проверка режима работы
    if [[ -n "$SELECTED_HOST" && -n "$SELECTED_ACTION" ]]; then
        # Прямое выполнение
        log_info "Прямое выполнение: хост=$SELECTED_HOST, действие=$SELECTED_ACTION"
        
        # Поиск хоста
        local found_host=""
        for item in "${HOST_MENU_ITEMS[@]}"; do
            IFS='|' read -r index hostname ip alias description type <<< "$item"
            if [[ "$alias" == "$SELECTED_HOST" || "$hostname" == "$SELECTED_HOST" ]]; then
                found_host="$item"
                break
            fi
        done
        
        if [[ -z "$found_host" ]]; then
            log_error "Хост не найден: $SELECTED_HOST"
            exit 1
        fi
        
        IFS='|' read -r index hostname ip alias description type <<< "$found_host"
        execute_action "$hostname" "$ip" "$alias" "$SELECTED_ACTION"
    else
        # Интерактивный режим
        interactive_mode
    fi
    
    log_info "Работа установщика завершена"
    log_info "Лог файл: $log_file"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
