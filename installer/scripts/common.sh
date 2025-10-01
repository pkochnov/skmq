#!/bin/bash
# =============================================================================
# Общие функции для системы автоматизации Monq
# =============================================================================
# Назначение: Общие функции для SSH, sudo, логирования и валидации
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка конфигурации
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Определение пути к конфигурационным файлам
# Если мы в временной директории (/tmp/monq-*), используем локальные файлы
if [[ "$SCRIPT_DIR" =~ ^/tmp/monq- ]]; then
    CONFIG_DIR="$SCRIPT_DIR/config"
else
    CONFIG_DIR="$PROJECT_ROOT/config"
fi

# Загрузка конфигурационных файлов
if [[ -f "$CONFIG_DIR/monq.conf" ]]; then
    source "$CONFIG_DIR/monq.conf"
else
    echo "ОШИБКА: Файл конфигурации $CONFIG_DIR/monq.conf не найден"
    exit 1
fi

if [[ -f "$CONFIG_DIR/hosts.conf" ]]; then
    source "$CONFIG_DIR/hosts.conf"
else
    echo "ОШИБКА: Файл конфигурации $CONFIG_DIR/hosts.conf не найден"
    exit 1
fi

# =============================================================================
# Глобальные переменные
# =============================================================================

# Флаг для отслеживания sudo сессии
SUDO_SESSION_ACTIVE=false

# PID процесса продления sudo сессии
SUDO_RENEW_PID=""

# =============================================================================
# Функции логирования
# =============================================================================

# Инициализация логирования
init_logging() {
    local log_file="$1"
    local log_level="${2:-$LOG_LEVEL}"
    
    # Создание директории логов если не существует
    local log_dir="$(dirname "$log_file")"
    if [[ ! -d "$log_dir" ]]; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            # Если есть sudo права, создаем директорию с sudo
            sudo mkdir -p "$log_dir" 2>/dev/null || true
        else
            # Иначе создаем в домашней директории пользователя
            log_file="$HOME/.monq/logs/$(basename "$log_file")"
            mkdir -p "$(dirname "$log_file")"
        fi
    fi
    
    # Установка уровня логирования
    case "$log_level" in
        DEBUG) LOG_LEVEL_NUM=0 ;;
        INFO)  LOG_LEVEL_NUM=1 ;;
        WARN)  LOG_LEVEL_NUM=2 ;;
        ERROR) LOG_LEVEL_NUM=3 ;;
        *)     LOG_LEVEL_NUM=1 ;;
    esac
    
    # Экспорт переменных для использования в функциях
    export MONQ_LOG_FILE="$log_file"
    export MONQ_LOG_LEVEL_NUM="$LOG_LEVEL_NUM"
}

# Функция логирования
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date "+$LOG_TIMESTAMP_FORMAT")
    
    # Определение числового уровня
    local level_num
    case "$level" in
        DEBUG) level_num=0 ;;
        INFO)  level_num=1 ;;
        WARN)  level_num=2 ;;
        ERROR) level_num=3 ;;
        *)     level_num=1 ;;
    esac
    
    # Проверка уровня логирования
    if [[ $level_num -ge ${MONQ_LOG_LEVEL_NUM:-1} ]]; then
        echo "[$timestamp] [$level] $message" | tee -a "${MONQ_LOG_FILE:-/dev/null}"
    fi
}

# Функции для разных уровней логирования
log_debug() { log "DEBUG" "$@"; }
log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

# =============================================================================
# Функции управления sudo
# =============================================================================

# Запрос sudo пароля
request_sudo_password() {
    if [[ "$SUDO_SESSION_ACTIVE" == "true" ]]; then
        log_info "Sudo сессия уже активна"
        return 0
    fi
    
    log_info "Запрос sudo пароля..."
    
    # Проверка текущего sudo статуса
    if sudo -n true 2>/dev/null; then
        log_info "Sudo сессия уже активна (без пароля)"
        SUDO_SESSION_ACTIVE=true
        start_sudo_renewal
        return 0
    fi
    
    # Запрос пароля с выводом в stderr для корректной работы через SSH
    echo "Введите sudo пароль для пользователя $(whoami):" >&2
    # Используем read для более надежного ввода пароля
    if [[ -t 0 ]]; then
        # Интерактивный режим
        if sudo -v; then
            log_info "Sudo пароль принят"
            SUDO_SESSION_ACTIVE=true
            start_sudo_renewal
            return 0
        else
            log_error "Неверный sudo пароль"
            return 1
        fi
    else
        # Неинтерактивный режим (удаленное выполнение)
        if sudo -v 2>/dev/null; then
            log_info "Sudo пароль принят"
            SUDO_SESSION_ACTIVE=true
            start_sudo_renewal
            return 0
        else
            log_error "Не удалось получить sudo привилегии в неинтерактивном режиме"
            return 1
        fi
    fi
}

# Продление sudo сессии
renew_sudo_session() {
    if sudo -v 2>/dev/null; then
        log_debug "Sudo сессия продлена"
        return 0
    else
        log_warn "Не удалось продлить sudo сессию"
        SUDO_SESSION_ACTIVE=false
        return 1
    fi
}

# Запуск фонового процесса продления sudo сессии
start_sudo_renewal() {
    if [[ -n "$SUDO_RENEW_PID" ]] && kill -0 "$SUDO_RENEW_PID" 2>/dev/null; then
        log_debug "Процесс продления sudo уже запущен"
        return 0
    fi
    
    # Запуск фонового процесса
    (
        while [[ "$SUDO_SESSION_ACTIVE" == "true" ]]; do
            sleep 300  # 5 минут
            if ! renew_sudo_session; then
                break
            fi
        done
    ) &
    
    SUDO_RENEW_PID=$!
    log_debug "Запущен процесс продления sudo сессии (PID: $SUDO_RENEW_PID)"
}

# Остановка процесса продления sudo сессии
stop_sudo_renewal() {
    if [[ -n "$SUDO_RENEW_PID" ]] && kill -0 "$SUDO_RENEW_PID" 2>/dev/null; then
        kill "$SUDO_RENEW_PID" 2>/dev/null
        log_debug "Остановлен процесс продления sudo сессии"
    fi
    SUDO_RENEW_PID=""
    SUDO_SESSION_ACTIVE=false
}

# Продление sudo сессии
renew_sudo_session() {
    if [[ "$SUDO_SESSION_ACTIVE" == "true" ]]; then
        # Пробуем продлить сессию
        if sudo -n true 2>/dev/null; then
            log_debug "Sudo сессия продлена"
            return 0
        else
            log_debug "Sudo сессия истекла, пытаемся восстановить"
            SUDO_SESSION_ACTIVE=false
            
            # Пытаемся восстановить сессию
            if [[ -n "$HOST_USER_PASSWORD" ]]; then
                if echo "$HOST_USER_PASSWORD" | sudo -S -v 2>/dev/null; then
                    log_debug "Sudo сессия восстановлена"
                    SUDO_SESSION_ACTIVE=true
                    return 0
                fi
            fi
            
            log_error "Не удалось восстановить sudo сессию"
            return 1
        fi
    fi
    return 0
}

# Выполнение команды с sudo
run_sudo() {
    # Продлеваем sudo сессию перед выполнением команды
    if ! renew_sudo_session; then
        log_error "Не удалось продлить sudo сессию"
        return 1
    fi
    
    if [[ "$SUDO_SESSION_ACTIVE" != "true" ]]; then
        log_error "Sudo сессия не активна"
        return 1
    fi
    
    log_debug "Выполнение sudo команды: $@"
    sudo "$@"
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_debug "Sudo команда выполнена успешно"
    else
        log_error "Sudo команда завершилась с ошибкой (код: $exit_code)"
    fi
    
    return $exit_code
}

# =============================================================================
# Функции SSH
# =============================================================================

# Проверка SSH соединения
check_ssh_connection() {
    local host="$1"
    local user="${2:-$MONQ_USER}"
    local timeout="${3:-$SSH_TIMEOUT}"
    
    log_info "Проверка SSH соединения с $user@$host..."
    
    # Простая проверка SSH соединения без повторных попыток
    if ssh -o ConnectTimeout="$timeout" -o BatchMode=yes -o StrictHostKeyChecking=no "$user@$host" "echo 'SSH соединение успешно'" &>/dev/null; then
        log_info "SSH соединение с $host установлено"
        return 0
    else
        log_error "Не удалось установить SSH соединение с $host"
        return 1
    fi
}

# Выполнение команды через SSH
run_ssh() {
    local host="$1"
    local user="${2:-$MONQ_USER}"
    local command="$3"
    local timeout="${4:-$SSH_TIMEOUT}"
    
    log_debug "Выполнение SSH команды на $user@$host: $command"
    
    # Простое выполнение SSH команды без повторных попыток
    if ssh -o ConnectTimeout="$timeout" -o StrictHostKeyChecking=no "$user@$host" "$command"; then
        log_debug "SSH команда выполнена успешно"
        return 0
    else
        log_error "SSH команда завершилась с ошибкой"
        return 1
    fi
}

# Выполнение команды с sudo через SSH
run_ssh_sudo() {
    local host="$1"
    local user="${2:-$MONQ_USER}"
    local command="$3"
    local timeout="${4:-$SSH_TIMEOUT}"
    
    log_debug "Выполнение SSH sudo команды на $user@$host: $command"
    
    # Выполнение команды с sudo
    run_ssh "$host" "$user" "sudo $command" "$timeout"
}

# =============================================================================
# Функции валидации
# =============================================================================

# Проверка IP адреса
validate_ip() {
    local ip="$1"
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        for part in "${ip_parts[@]}"; do
            if [[ $part -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Проверка hostname
validate_hostname() {
    local hostname="$1"
    
    if [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Проверка доступности порта
check_port_common() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Функции работы с хостами
# =============================================================================

# Получение информации о хосте
get_host_info() {
    local host_alias="$1"
    local info_type="$2"  # HOSTNAME, IP, ALIAS, DESCRIPTION
    
    # Поиск хоста в массивах
    for host_var in "${HOSTS_ALL[@]}"; do
        if [[ "${host_var}_ALIAS" == "HOST_${host_alias^^}_ALIAS" ]]; then
            local base_var="${host_var}_${info_type}"
            echo "${!base_var}"
            return 0
        fi
    done
    
    return 1
}

# Получение всех хостов определенного типа
get_hosts_by_type() {
    local host_type="$1"  # K8S, DOCKER, DATABASE, MONITORING, SERVICES
    
    local array_name="HOSTS_${host_type^^}"
    if [[ -n "${!array_name}" ]]; then
        echo "${!array_name[@]}"
    else
        return 1
    fi
}

# =============================================================================
# Функции очистки
# =============================================================================

# Очистка при завершении скрипта
cleanup() {
    log_info "Выполнение очистки..."
    stop_sudo_renewal
    log_info "Очистка завершена"
}

# Установка обработчика сигналов
setup_signal_handlers() {
    trap cleanup EXIT INT TERM
}

# =============================================================================
# Функции отображения
# =============================================================================

# Цветовые коды для вывода
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
print_success() {
    echo -e "${GREEN}✓${NC} $*"
}

print_error() {
    echo -e "${RED}✗${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

print_header() {
    echo -e "${CYAN}${BOLD}$*${NC}"
}

print_section() {
    echo -e "${PURPLE}${BOLD}$*${NC}"
}

# Отображение заголовка
show_header() {
    local title="$1"
    local width=60
    
    echo
    echo "=================================================================="
    printf "%-${width}s\n" "$title"
    echo "=================================================================="
    echo
}

# Отображение прогресса
show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' ' '
    printf "] %d%% %s" $percent "$message"
    
    # Всегда добавляем перенос строки после прогресс-бара
    echo
}

# =============================================================================
# Функции управления sudo сессией
# =============================================================================

# Инициализация sudo сессии
init_sudo_session() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Инициализация sudo сессии пропущена"
        return 0
    fi
    
    # Проверяем, есть ли уже активная sudo сессия
    if sudo -n true 2>/dev/null; then
        log_info "Sudo сессия уже активна"
        SUDO_SESSION_ACTIVE=true
        return 0
    fi
    
    # Проверяем, есть ли пароль в конфигурации
    if [[ -n "$HOST_USER_PASSWORD" ]]; then
        log_info "Использование пароля из конфигурации"
        if echo "$HOST_USER_PASSWORD" | sudo -S -v 2>/dev/null; then
            log_info "Sudo пароль принят"
            SUDO_SESSION_ACTIVE=true
            return 0
        else
            log_error "Неверный sudo пароль из конфигурации"
            return 1
        fi
    fi
    
    # Проверяем, запущен ли скрипт локально или удаленно
    if [[ -t 0 && -t 1 ]]; then
        # Локальное выполнение - запрашиваем пароль
        log_info "Локальное выполнение: запрос sudo пароля"
        if ! request_sudo_password; then
            log_error "Не удалось получить sudo привилегии"
            return 1
        fi
    else
        # Удаленное выполнение - пытаемся запросить пароль
        log_info "Удаленное выполнение: попытка запроса sudo пароля"
        
        # Проверяем, есть ли переменная SSH_TTY (индикатор SSH сессии)
        if [[ -n "$SSH_TTY" ]]; then
            log_info "SSH сессия обнаружена: $SSH_TTY"
            # В SSH сессии пытаемся использовать sudo без пароля или с паролем из конфигурации
            if sudo -n true 2>/dev/null; then
                log_info "Sudo работает без пароля в SSH сессии"
                SUDO_SESSION_ACTIVE=true
                return 0
            elif [[ -n "$HOST_USER_PASSWORD" ]]; then
                log_info "Попытка использовать пароль из конфигурации в SSH сессии"
                if echo "$HOST_USER_PASSWORD" | sudo -S -v 2>/dev/null; then
                    log_info "Sudo пароль принят в SSH сессии"
                    SUDO_SESSION_ACTIVE=true
                    return 0
                fi
            fi
        fi
        
        # Последняя попытка - интерактивный запрос
        echo "Введите sudo пароль для пользователя $(whoami):" >&2
        if sudo -v 2>/dev/null; then
            log_info "Sudo пароль принят"
            SUDO_SESSION_ACTIVE=true
            return 0
        else
            log_error "Не удалось получить sudo привилегии"
            log_error "Убедитесь, что пользователь $(whoami) имеет sudo права"
            log_error "Или настройте переменную HOST_USER_PASSWORD в config/hosts.conf"
            return 1
        fi
    fi
}

# =============================================================================
# Функции проверки системы
# =============================================================================

# Проверка Docker
check_docker() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        print_info "[DRY-RUN] Проверка Docker"
        return 0
    fi
    
    print_section "Проверка Docker"
    
    if ! command -v docker &>/dev/null; then
        print_error "Docker не установлен"
        return 1
    fi
    
    # Проверяем Docker Compose (новая версия) или docker-compose (старая версия)
    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
        if ! command -v docker-compose &>/dev/null; then
            print_error "Docker Compose не установлен"
            return 1
        fi
    fi
    
    if ! run_sudo systemctl is-active docker &>/dev/null; then
        print_error "Docker сервис не активен"
        return 1
    fi
    
    if ! run_sudo docker info &>/dev/null; then
        print_error "Docker daemon недоступен"
        return 1
    fi
    
    print_success "Docker готов к работе"
    return 0
}

# =============================================================================
# Функции для работы с Docker Compose
# =============================================================================

# Определение команды Docker Compose
get_docker_compose_cmd() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        echo "docker-compose"  # fallback
    fi
}

# Выполнение команды Docker Compose
run_docker_compose() {
    local compose_cmd
    compose_cmd=$(get_docker_compose_cmd)
    
    if [[ $? -ne 0 ]]; then
        log_error "Docker Compose не найден"
        return 1
    fi
    
    log_debug "Выполнение команды: $compose_cmd $*"
    $compose_cmd "$@"
}

# Универсальная функция выполнения Docker exec команд с sudo привилегиями
run_docker_exec() {
    local container_name="$1"
    shift
    local command="$*"
    
    if [[ -z "$container_name" || -z "$command" ]]; then
        log_error "Не указаны обязательные параметры: container_name и command"
        return 1
    fi
    
    log_debug "Выполнение Docker exec: docker exec $container_name $command"
    
    # Пробуем сначала с run_sudo, если не работает - используем прямой sudo
    if run_sudo docker exec "$container_name" $command 2>/dev/null; then
        return 0
    elif sudo docker exec "$container_name" $command 2>/dev/null; then
        return 0
    else
        log_error "Не удалось выполнить команду в контейнере $container_name"
        return 1
    fi
}

# =============================================================================
# Функции управления Docker сервисами
# =============================================================================

# Универсальная функция остановки существующих сервисов
stop_existing_services_universal() {
    local service_name="$1"
    local base_dir="$2"
    
    if [[ -z "$service_name" || -z "$base_dir" ]]; then
        log_error "Не указаны обязательные параметры: service_name и base_dir"
        return 1
    fi
    
    print_section "Проверка существующих сервисов $service_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        print_info "[DRY-RUN] Проверка существующих сервисов $service_name"
        return 0
    fi
    
    # Переход в директорию с docker-compose.yml
    cd "$base_dir" || {
        print_error "Не удалось перейти в директорию: $base_dir"
        return 1
    }
    
    # Остановка и удаление существующих сервисов
    if run_docker_compose ps -q | grep -q .; then
        print_info "Остановка существующих сервисов $service_name"
        
        if run_docker_compose down; then
            print_success "Сервисы $service_name остановлены и удалены"
        else
            print_warning "Не удалось остановить сервисы $service_name"
        fi
    else
        print_info "Существующие сервисы $service_name не найдены"
    fi
    
    return 0
}

# Универсальная функция копирования Docker Compose файла
copy_docker_compose_file() {
    local service_name="$1"
    local service_dir="$2"
    local base_dir="$3"
    
    if [[ -z "$service_name" || -z "$service_dir" || -z "$base_dir" ]]; then
        log_error "Не указаны обязательные параметры: service_name, service_dir и base_dir"
        return 1
    fi
    
    print_section "Копирование Docker Compose файла для $service_name"
    
    local compose_file="$base_dir/docker-compose.yml"
    local compose_source=""
    
    # Определяем путь к исходному Docker Compose файлу
    # Сначала пробуем использовать CONFIG_DIR
    if [[ -n "$CONFIG_DIR" && -f "$CONFIG_DIR/$service_dir/docker-compose.yml" ]]; then
        compose_source="$CONFIG_DIR/$service_dir/docker-compose.yml"
    # Затем пробуем локальный путь (для SSH выполнения)
    elif [[ -f "./config/$service_dir/docker-compose.yml" ]]; then
        compose_source="./config/$service_dir/docker-compose.yml"
    # Затем пробуем путь относительно SCRIPT_DIR
    elif [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/../config/$service_dir/docker-compose.yml" ]]; then
        compose_source="$SCRIPT_DIR/../config/$service_dir/docker-compose.yml"
    else
        print_error "Docker Compose файл не найден ни в одном из ожидаемых мест:"
        print_error "  - $CONFIG_DIR/$service_dir/docker-compose.yml"
        print_error "  - ./config/$service_dir/docker-compose.yml"
        print_error "  - $SCRIPT_DIR/../config/$service_dir/docker-compose.yml"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Копирование: $compose_source -> $compose_file"
        return 0
    fi
    
    # Копируем Docker Compose файл
    # Пробуем сначала с run_sudo, если не работает - используем прямой sudo
    if run_sudo cp "$compose_source" "$compose_file" 2>/dev/null; then
        run_sudo chown root:root "$compose_file" 2>/dev/null
        run_sudo chmod 644 "$compose_file" 2>/dev/null
        print_success "Docker Compose файл скопирован: $compose_file"
        return 0
    elif sudo cp "$compose_source" "$compose_file" 2>/dev/null; then
        sudo chown root:root "$compose_file" 2>/dev/null
        sudo chmod 644 "$compose_file" 2>/dev/null
        print_success "Docker Compose файл скопирован: $compose_file"
        return 0
    else
        print_error "Ошибка при копировании Docker Compose файла"
        print_error "Проверьте права доступа и sudo конфигурацию"
        return 1
    fi
}

# =============================================================================
# Функции для работы с Kubernetes
# =============================================================================

# Проверка доступности kubectl
check_kubectl_availability() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl не установлен или недоступен"
        return 1
    fi
    
    # Проверка подключения к кластеру
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Не удалось подключиться к кластеру Kubernetes"
        return 1
    fi
    
    return 0
}

# Получение информации о кластере
get_cluster_info() {
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$cluster_info"
        return 0
    else
        log_error "Не удалось получить информацию о кластере"
        return 1
    fi
}

# Получение списка узлов
get_cluster_nodes() {
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local nodes=$(kubectl get nodes --no-headers 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$nodes"
        return 0
    else
        log_error "Не удалось получить список узлов"
        return 1
    fi
}

# Проверка готовности узла
check_node_ready() {
    local node_name="$1"
    
    if [[ -z "$node_name" ]]; then
        log_error "Не указано имя узла"
        return 1
    fi
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local node_status=$(kubectl get node "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$node_status" == "True" ]]; then
        return 0
    else
        return 1
    fi
}

# Получение списка подов
get_cluster_pods() {
    local namespace="${1:-all-namespaces}"
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local pods
    if [[ "$namespace" == "all-namespaces" ]]; then
        pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null)
    else
        pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null)
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "$pods"
        return 0
    else
        log_error "Не удалось получить список подов"
        return 1
    fi
}

# Проверка статуса подов
check_pods_status() {
    local namespace="${1:-all-namespaces}"
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local pods=$(get_cluster_pods "$namespace")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local running_pods=$(echo "$pods" | grep -c "Running")
    local pending_pods=$(echo "$pods" | grep -c "Pending")
    local failed_pods=$(echo "$pods" | grep -c "Failed\|Error\|CrashLoopBackOff")
    local total_pods=$(echo "$pods" | wc -l)
    
    echo "Total: $total_pods, Running: $running_pods, Pending: $pending_pods, Failed: $failed_pods"
    return 0
}

# Получение событий кластера
get_cluster_events() {
    local namespace="${1:-all-namespaces}"
    local limit="${2:-20}"
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local events
    if [[ "$namespace" == "all-namespaces" ]]; then
        events=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -"$limit")
    else
        events=$(kubectl get events -n "$namespace" --sort-by='.lastTimestamp' --no-headers 2>/dev/null | tail -"$limit")
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "$events"
        return 0
    else
        log_error "Не удалось получить события кластера"
        return 1
    fi
}

# Проверка событий с ошибками
check_error_events() {
    local namespace="${1:-all-namespaces}"
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local error_events
    if [[ "$namespace" == "all-namespaces" ]]; then
        error_events=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null)
    else
        error_events=$(kubectl get events -n "$namespace" --field-selector type=Warning --no-headers 2>/dev/null)
    fi
    
    if [[ $? -eq 0 ]]; then
        local error_count=$(echo "$error_events" | wc -l)
        if [[ $error_count -gt 0 ]]; then
            echo "$error_events"
            return 1
        else
            return 0
        fi
    else
        log_error "Не удалось получить события с ошибками"
        return 1
    fi
}

# Получение логов пода
get_pod_logs() {
    local pod_name="$1"
    local namespace="${2:-default}"
    local lines="${3:-50}"
    
    if [[ -z "$pod_name" ]]; then
        log_error "Не указано имя пода"
        return 1
    fi
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local logs=$(kubectl logs "$pod_name" -n "$namespace" --tail="$lines" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$logs"
        return 0
    else
        log_error "Не удалось получить логи пода $pod_name"
        return 1
    fi
}

# Проверка логов на ошибки
check_pod_logs_for_errors() {
    local pod_name="$1"
    local namespace="${2:-default}"
    local lines="${3:-50}"
    
    if [[ -z "$pod_name" ]]; then
        log_error "Не указано имя пода"
        return 1
    fi
    
    local logs=$(get_pod_logs "$pod_name" "$namespace" "$lines")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local error_count=$(echo "$logs" | grep -i error | wc -l)
    if [[ $error_count -gt 0 ]]; then
        echo "$logs" | grep -i error
        return 1
    else
        return 0
    fi
}

# Создание токена для присоединения к кластеру
create_join_token() {
    local ttl="${1:-24h0m0s}"
    
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local join_command=$(kubeadm token create --ttl="$ttl" --print-join-command 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$join_command"
        return 0
    else
        log_error "Не удалось создать токен для присоединения"
        return 1
    fi
}

# Получение хэша CA сертификата
get_ca_cert_hash() {
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local ca_cert_hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' 2>/dev/null)
    if [[ $? -eq 0 && -n "$ca_cert_hash" ]]; then
        echo "sha256:$ca_cert_hash"
        return 0
    else
        log_error "Не удалось получить хэш CA сертификата"
        return 1
    fi
}

# Проверка версии Kubernetes
get_kubernetes_version() {
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local version=$(kubectl version --short --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ $? -eq 0 && -n "$version" ]]; then
        echo "$version"
        return 0
    else
        log_error "Не удалось получить версию Kubernetes"
        return 1
    fi
}

# Проверка статуса CNI
check_cni_status() {
    if ! check_kubectl_availability; then
        return 1
    fi
    
    local cni_pods=$(kubectl get pods -n kube-system --no-headers | grep -E "(cilium|calico|flannel|weave)" | wc -l)
    if [[ $cni_pods -gt 0 ]]; then
        local running_cni_pods=$(kubectl get pods -n kube-system --no-headers | grep -E "(cilium|calico|flannel|weave)" | grep -c "Running")
        if [[ $running_cni_pods -eq $cni_pods ]]; then
            return 0
        else
            return 1
        fi
    else
        log_error "CNI поды не найдены"
        return 1
    fi
}

# =============================================================================
# Инициализация общих функций
# =============================================================================

# Установка обработчиков сигналов
setup_signal_handlers

# Создание директории логов
mkdir -p "$LOG_DIR"

log_info "Общие функции загружены успешно"
