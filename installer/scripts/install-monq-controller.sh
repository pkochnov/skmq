#!/bin/bash
# =============================================================================
# Скрипт установки MONQ на контроллерном узле Kubernetes
# =============================================================================
# Назначение: Установка и настройка MONQ на контроллерном узле k01
# Автор: Система автоматизации Monq
# Версия: 1.0.0
# =============================================================================

# Загрузка общих функций
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# Переменные скрипта
# =============================================================================

# Параметры по умолчанию (из monq.conf)
# MONQCTL_VERSION и MONQ_TOKEN загружаются из config/monq.conf
MONQCTL_ARCH="linux-x64"
MONQCTL_URL="https://downloads.monq.ru/tools/monqctl/v${MONQCTL_VERSION}/${MONQCTL_ARCH}/monqctl.zip"
MONQCTL_BIN="/usr/local/bin/monqctl"

# Настройки конфигурации MONQ
MONQ_INSTANCE_NAME="temp"
MONQ_SERVER="http://registry.api.monq.local"
MONQ_REGISTRY_TOKEN="000"
MONQ_RELEASEHUB_NAME="monq-release-hub"
MONQ_CONTEXT_NAME="temp"

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

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
    --monqctl-version VERSION    Версия monqctl (по умолчанию: из monq.conf)
    --token TOKEN               Токен обновления MONQ (по умолчанию: из monq.conf)
    --server URL                URL сервера MONQ (по умолчанию: ${MONQ_SERVER})
    --registry-token TOKEN      Токен registry (по умолчанию: ${MONQ_REGISTRY_TOKEN})
    --dry-run                   Режим симуляции (без выполнения команд)
    --force                     Принудительное выполнение (без подтверждений)
    --verbose                   Подробный вывод
    --help                      Показать эту справку

Примеры:
    # Установка MONQ (использует токен из monq.conf)
    $0

    # Установка с токеном (переопределяет monq.conf)
    $0 --token "your_monq_token_here"

    # Установка с кастомной версией monqctl (переопределяет monq.conf)
    $0 --token "your_token" --monqctl-version "1.17.3"

    # Режим симуляции
    $0 --dry-run

Требования:
    - Токен обновления MONQ (в monq.conf или через --token)
    - Доступ к интернету для загрузки monqctl
    - Права sudo для установки в /usr/local/bin

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --monqctl-version)
                MONQCTL_VERSION="$2"
                shift 2
                ;;
            --token)
                MONQ_TOKEN="$2"
                shift 2
                ;;
            --server)
                MONQ_SERVER="$2"
                shift 2
                ;;
            --registry-token)
                MONQ_REGISTRY_TOKEN="$2"
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
            --verbose)
                VERBOSE=true
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
    
    # Если токен не передан через параметр, используем из monq.conf
    if [[ -z "$MONQ_TOKEN" ]]; then
        if [[ -n "${MONQ_TOKEN:-}" ]]; then
            MONQ_TOKEN="${MONQ_TOKEN}"
        else
            log_error "Токен MONQ не указан. Используйте --token или настройте MONQ_TOKEN в monq.conf"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ ! "$MONQCTL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Неверный формат версии monqctl: $MONQCTL_VERSION"
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
    
    # Проверяем, что мы на контроллерном узле
    if ! kubectl get nodes --no-headers | grep -q "control-plane\|master"; then
        print_warning "Предупреждение: узел не является контроллерным"
    fi
    
    # Проверяем доступность kubectl
    if ! command -v kubectl &>/dev/null; then
        print_error "kubectl не установлен"
        return 1
    fi
    
    # Проверяем подключение к кластеру
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Не удается подключиться к кластеру Kubernetes"
        return 1
    fi
    
    print_success "Системные требования выполнены"
    return 0
}

# Проверка существующей установки monqctl
check_existing_installation() {
    print_section "Проверка существующей установки monqctl"
    
    if [[ -f "$MONQCTL_BIN" ]]; then
        local current_version=$($MONQCTL_BIN version 2>/dev/null | head -n1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "неизвестно")
        print_info "monqctl уже установлен: $current_version"
        
        if [[ "$current_version" == "v$MONQCTL_VERSION" ]]; then
            print_success "Требуемая версия уже установлена"
            return 0
        else
            print_warning "Версия отличается от требуемой (v$MONQCTL_VERSION)"
            if [[ "$FORCE" != "true" ]]; then
                print_info "Используйте --force для принудительной переустановки"
                return 1
            fi
        fi
    else
        print_info "monqctl не установлен"
    fi
    
    return 0
}

# Загрузка и установка monqctl
install_monqctl() {
    print_section "Установка monqctl версии $MONQCTL_VERSION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Загрузка monqctl с $MONQCTL_URL"
        print_info "[DRY-RUN] Установка в $MONQCTL_BIN"
        return 0
    fi
    
    # Создаем временную директорию
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return 1
    
    # Загружаем monqctl
    print_info "Загрузка monqctl..."
    if ! wget -q "$MONQCTL_URL" -O monqctl.zip; then
        print_error "Ошибка при загрузке monqctl"
        return 1
    fi
    
    # Распаковываем архив
    print_info "Распаковка архива..."
    if ! unzip -q monqctl.zip; then
        print_error "Ошибка при распаковке архива"
        return 1
    fi
    
    # Устанавливаем в систему
    print_info "Установка monqctl в $MONQCTL_BIN..."
    if ! run_sudo mv monqctl "$MONQCTL_BIN"; then
        print_error "Ошибка при установке monqctl"
        return 1
    fi
    
    # Устанавливаем права выполнения
    run_sudo chmod +x "$MONQCTL_BIN"
    
    # Очищаем временные файлы
    cd /tmp
    rm -rf "$temp_dir"
    
    # Проверяем установку
    if ! $MONQCTL_BIN version &>/dev/null; then
        print_error "monqctl установлен, но не работает"
        return 1
    fi
    
    print_success "monqctl успешно установлен"
    return 0
}

# Настройка конфигурации monqctl
configure_monqctl() {
    print_section "Настройка конфигурации monqctl"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Настройка конфигурации monqctl"
        print_info "[DRY-RUN] Instance: $MONQ_INSTANCE_NAME"
        print_info "[DRY-RUN] Server: $MONQ_SERVER"
        print_info "[DRY-RUN] Registry Token: $MONQ_REGISTRY_TOKEN"
        print_info "[DRY-RUN] Release Hub: $MONQ_RELEASEHUB_NAME"
        print_info "[DRY-RUN] Context: $MONQ_CONTEXT_NAME"
        return 0
    fi
    
    # Настройка instance
    print_info "Настройка instance..."
    if ! $MONQCTL_BIN config set instance "$MONQ_INSTANCE_NAME" --server="$MONQ_SERVER"; then
        print_error "Ошибка при настройке instance"
        return 1
    fi
    
    # Настройка credential
    print_info "Настройка credential..."
    if ! $MONQCTL_BIN config set credential "$MONQ_INSTANCE_NAME" --registry-token="$MONQ_REGISTRY_TOKEN"; then
        print_error "Ошибка при настройке credential"
        return 1
    fi
    
    # Настройка releasehub
    print_info "Настройка releasehub..."
    if ! $MONQCTL_BIN config set releasehub "$MONQ_RELEASEHUB_NAME" --token="$MONQ_TOKEN"; then
        print_error "Ошибка при настройке releasehub"
        return 1
    fi
    
    # Настройка context
    print_info "Настройка context..."
    if ! $MONQCTL_BIN config set context "$MONQ_CONTEXT_NAME" --instance="$MONQ_INSTANCE_NAME" --credential="$MONQ_INSTANCE_NAME" --releasehub="$MONQ_RELEASEHUB_NAME"; then
        print_error "Ошибка при настройке context"
        return 1
    fi
    
    # Активация context
    print_info "Активация context..."
    if ! $MONQCTL_BIN config use-context "$MONQ_CONTEXT_NAME"; then
        print_error "Ошибка при активации context"
        return 1
    fi
    
    print_success "Конфигурация monqctl настроена"
    return 0
}

# Проверка конфигурации
verify_configuration() {
    print_section "Проверка конфигурации monqctl"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Проверка конфигурации"
        return 0
    fi
    
    # Проверяем текущий context
    local current_context=$($MONQCTL_BIN config current-context 2>/dev/null)
    if [[ "$current_context" != "$MONQ_CONTEXT_NAME" ]]; then
        print_error "Текущий context ($current_context) не соответствует ожидаемому ($MONQ_CONTEXT_NAME)"
        return 1
    fi
    
    # Проверяем версию
    local version=$($MONQCTL_BIN version 2>/dev/null | head -n1)
    if [[ -n "$version" ]]; then
        print_success "monqctl версии: $version"
    fi
    
    # Проверяем конфигурацию
    print_info "Текущая конфигурация:"
    $MONQCTL_BIN config view 2>/dev/null || print_warning "Не удалось получить конфигурацию"
    
    print_success "Конфигурация monqctl проверена"
    return 0
}

# Отображение информации об установке
show_installation_info() {
    print_section "Информация об установке MONQ"
    
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}=== Установка MONQ на контроллерном узле ===${NC}"
    echo -e "${CYAN}${BOLD}==================================================================${NC}"
    echo
    
    echo -e "${BLUE}Версия monqctl:${NC} $MONQCTL_VERSION (из monq.conf)"
    echo -e "${BLUE}Архитектура:${NC} $MONQCTL_ARCH"
    echo -e "${BLUE}URL загрузки:${NC} $MONQCTL_URL"
    echo -e "${BLUE}Путь установки:${NC} $MONQCTL_BIN"
    echo
    echo -e "${BLUE}Настройки конфигурации:${NC}"
    echo -e "  ${GREEN}Instance:${NC} $MONQ_INSTANCE_NAME"
    echo -e "  ${GREEN}Server:${NC} $MONQ_SERVER"
    echo -e "  ${GREEN}Registry Token:${NC} $MONQ_REGISTRY_TOKEN"
    echo -e "  ${GREEN}Release Hub:${NC} $MONQ_RELEASEHUB_NAME"
    echo -e "  ${GREEN}Context:${NC} $MONQ_CONTEXT_NAME"
    echo -e "  ${GREEN}MONQ Token:${NC} ${MONQ_TOKEN:0:8}... (из monq.conf)"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    print_header "Установка MONQ на контроллерном узле Kubernetes"
    
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Валидация параметров
    validate_parameters
    
    # Инициализация логирования
    local log_file="$LOG_DIR/install-monq-controller-$(date +%Y%m%d_%H%M%S).log"
    init_logging "$log_file" "$LOG_LEVEL"
    
    log_info "Начало установки MONQ на контроллерном узле"
    log_info "Версия monqctl: $MONQCTL_VERSION"
    log_info "MONQ Token: ${MONQ_TOKEN:0:8}..."
    log_info "Режим симуляции: $DRY_RUN"
    
    # Запрос sudo пароля
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! init_sudo_session; then
            log_error "Не удалось получить sudo привилегии"
            exit 1
        fi
    fi
    
    # Выполнение этапов установки
    local steps=(
        "check_system_requirements"
        "check_existing_installation"
        "install_monqctl"
        "configure_monqctl"
        "verify_configuration"
    )
    
    local total_steps=${#steps[@]}
    local current_step=0
    
    for step in "${steps[@]}"; do
        current_step=$((current_step + 1))
        show_progress $current_step $total_steps "Выполнение: $step"
        
        if ! eval "$step"; then
            log_error "Ошибка на этапе: $step"
            if [[ "$FORCE" != "true" ]]; then
                log_error "Прерывание выполнения"
                exit 1
            else
                log_warn "Продолжение выполнения в принудительном режиме"
            fi
        fi
    done
    
    show_installation_info
    
    log_info "Установка MONQ на контроллерном узле завершена"
    log_info "Лог файл: $log_file"
    
    print_success "MONQ успешно установлен и настроен на контроллерном узле"
    print_info "Используйте 'monqctl --help' для получения справки"
}

# =============================================================================
# Запуск скрипта
# =============================================================================

# Проверка, что скрипт запущен напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
