#!/bin/bash
# =============================================================================
# Скрипт инициализации хранилища для Kubernetes Worker
# =============================================================================
# Назначение: Создание файловой системы, монтирование и настройка ссылок
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
STORAGE_DEVICE="${K8S_STORAGE:-}"
MOUNT_POINT="/mnt/k8s-storage"
DRY_RUN=false
FORCE=false

# =============================================================================
# Функции скрипта
# =============================================================================

# Отображение справки
show_help() {
    cat << EOF
Использование: $0 [ОПЦИИ]

Скрипт инициализации хранилища для Kubernetes Worker узла.

ОПЦИИ:
    -d, --device DEVICE     Устройство хранилища (например: /dev/sdb)
    -m, --mount MOUNT        Точка монтирования (по умолчанию: /mnt/k8s-storage)
    -f, --force             Принудительное выполнение (перезаписать существующие данные)
    --dry-run               Режим проверки без выполнения изменений
    -h, --help              Показать эту справку

ПРИМЕРЫ:
    $0 -d /dev/sdb
    $0 -d /dev/sdb -m /mnt/k8s-storage --dry-run
    $0 -d /dev/sdb -f

ОПИСАНИЕ:
    Скрипт выполняет следующие действия:
    1. Создает файловую систему XFS на указанном устройстве (без партиций)
    2. Добавляет запись в /etc/fstab для автоматического монтирования
    3. Монтирует устройство в указанную точку
    4. Создает директории containerd и kubelet в хранилище
    5. Создает символические ссылки для /var/lib/containerd и /var/lib/kubelet

EOF
}


# Проверка существования устройства
check_device() {
    local device="$1"
    
    if [[ -z "$device" ]]; then
        print_error "Устройство не указано"
        return 1
    fi
    
    if [[ ! -b "$device" ]]; then
        print_error "Устройство $device не существует или не является блочным устройством"
        return 1
    fi
    
    # Проверка, что устройство не смонтировано
    if mount | grep -q "^$device "; then
        print_error "Устройство $device уже смонтировано"
        return 1
    fi
    
    # Проверка, что устройство не используется в LVM
    if command -v pvs >/dev/null 2>&1 && pvs "$device" >/dev/null 2>&1; then
        print_error "Устройство $device используется в LVM"
        return 1
    fi
    
    return 0
}

# Проверка точки монтирования
check_mount_point() {
    local mount_point="$1"
    
    if [[ -z "$mount_point" ]]; then
        print_error "Точка монтирования не указана"
        return 1
    fi
    
    # Создание директории если не существует
    if ! run_sudo test -d "$mount_point"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY RUN: Создание директории $mount_point"
        else
            print_info "Создание директории $mount_point"
            if ! run_sudo mkdir -p "$mount_point"; then
                print_error "Не удалось создать директорию $mount_point"
                return 1
            fi
        fi
    fi
    
    # Проверка, что директория пуста
    if run_sudo test -d "$mount_point" && [[ -n "$(run_sudo ls -A "$mount_point" 2>/dev/null)" ]]; then
        if [[ "$FORCE" != "true" ]]; then
            print_error "Директория $mount_point не пуста. Используйте --force для принудительного выполнения"
            return 1
        else
            print_warning "Директория $mount_point не пуста, но используется принудительный режим"
        fi
    fi
    
    return 0
}

# Создание файловой системы
create_filesystem() {
    local device="$1"
    
    print_info "Создание файловой системы XFS на устройстве $device"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: mkfs.xfs -f $device"
        return 0
    fi
    
    # Создание файловой системы XFS без партиций
    if run_sudo mkfs.xfs -f "$device"; then
        print_success "Файловая система XFS создана на $device"
        return 0
    else
        print_error "Не удалось создать файловую систему на $device"
        return 1
    fi
}

# Добавление записи в fstab
add_to_fstab() {
    local device="$1"
    local mount_point="$2"
    
    print_info "Добавление записи в /etc/fstab"
    
    # Проверка, что запись еще не существует
    if run_sudo grep -q "^$device " /etc/fstab; then
        print_warning "Запись для $device уже существует в /etc/fstab"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Добавление записи в /etc/fstab"
        print_info "DRY RUN: $device $mount_point xfs defaults 0 2"
        return 0
    fi
    
    # Добавление записи в fstab
    local fstab_entry="$device $mount_point xfs defaults 0 2"
    if echo "$fstab_entry" | run_sudo tee -a /etc/fstab >/dev/null; then
        print_success "Запись добавлена в /etc/fstab"
        return 0
    else
        print_error "Не удалось добавить запись в /etc/fstab"
        return 1
    fi
}

# Монтирование устройства
mount_device() {
    local device="$1"
    local mount_point="$2"
    
    print_info "Монтирование устройства $device в $mount_point"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: mount $device $mount_point"
        return 0
    fi
    
    if run_sudo mount "$device" "$mount_point"; then
        print_success "Устройство смонтировано в $mount_point"
        return 0
    else
        print_error "Не удалось смонтировать устройство $device"
        return 1
    fi
}

# Создание директорий в хранилище
create_storage_directories() {
    local mount_point="$1"
    
    print_info "Создание директорий в хранилище"
    
    local directories=(
        "$mount_point/containerd"
        "$mount_point/kubelet"
    )
    
    for dir in "${directories[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY RUN: mkdir -p $dir"
        else
            if run_sudo mkdir -p "$dir"; then
                print_success "Создана директория $dir"
            else
                print_error "Не удалось создать директорию $dir"
                return 1
            fi
        fi
    done
    
    return 0
}

# Создание символических ссылок
create_symlinks() {
    local mount_point="$1"
    
    print_info "Создание символических ссылок"
    
    # Создание ссылки для containerd
    local containerd_link="/var/lib/containerd"
    local containerd_target="$mount_point/containerd"
    
    if run_sudo test -L "$containerd_link"; then
        print_warning "Символическая ссылка $containerd_link уже существует"
        if [[ "$FORCE" == "true" ]]; then
            print_info "Удаление существующей ссылки (принудительный режим)"
            if [[ "$DRY_RUN" != "true" ]]; then
                run_sudo rm -f "$containerd_link"
            fi
        else
            print_info "Пропуск создания ссылки для containerd"
        fi
    fi
    
    if ! run_sudo test -L "$containerd_link"; then
        if run_sudo test -d "$containerd_link"; then
            print_info "Перемещение существующей директории $containerd_link в $containerd_target"
            if [[ "$DRY_RUN" != "true" ]]; then
                run_sudo mv "$containerd_link" "$containerd_target"
            fi
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY RUN: ln -s $containerd_target $containerd_link"
        else
            if run_sudo ln -s "$containerd_target" "$containerd_link"; then
                print_success "Создана ссылка $containerd_link -> $containerd_target"
            else
                print_error "Не удалось создать ссылку $containerd_link"
                return 1
            fi
        fi
    fi
    
    # Создание ссылки для kubelet
    local kubelet_link="/var/lib/kubelet"
    local kubelet_target="$mount_point/kubelet"
    
    if run_sudo test -L "$kubelet_link"; then
        print_warning "Символическая ссылка $kubelet_link уже существует"
        if [[ "$FORCE" == "true" ]]; then
            print_info "Удаление существующей ссылки (принудительный режим)"
            if [[ "$DRY_RUN" != "true" ]]; then
                run_sudo rm -f "$kubelet_link"
            fi
        else
            print_info "Пропуск создания ссылки для kubelet"
        fi
    fi
    
    if ! run_sudo test -L "$kubelet_link"; then
        if run_sudo test -d "$kubelet_link"; then
            print_info "Перемещение существующей директории $kubelet_link в $kubelet_target"
            if [[ "$DRY_RUN" != "true" ]]; then
                run_sudo mv "$kubelet_link" "$kubelet_target"
            fi
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "DRY RUN: ln -s $kubelet_target $kubelet_link"
        else
            if run_sudo ln -s "$kubelet_target" "$kubelet_link"; then
                print_success "Создана ссылка $kubelet_link -> $kubelet_target"
            else
                print_error "Не удалось создать ссылку $kubelet_link"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Проверка результата
verify_installation() {
    local mount_point="$1"
    
    print_info "Проверка результата установки"
    
    # Проверка монтирования
    if run_sudo mount | grep -q "$mount_point"; then
        print_success "Устройство смонтировано в $mount_point"
    else
        print_error "Устройство не смонтировано в $mount_point"
        return 1
    fi
    
    # Проверка символических ссылок
    local containerd_link="/var/lib/containerd"
    local kubelet_link="/var/lib/kubelet"
    
    if run_sudo test -L "$containerd_link"; then
        print_success "Ссылка $containerd_link создана"
    else
        print_error "Ссылка $containerd_link не создана"
        return 1
    fi
    
    if run_sudo test -L "$kubelet_link"; then
        print_success "Ссылка $kubelet_link создана"
    else
        print_error "Ссылка $kubelet_link не создана"
        return 1
    fi
    
    # Проверка директорий в хранилище
    if run_sudo test -d "$mount_point/containerd"; then
        print_success "Директория $mount_point/containerd создана"
    else
        print_error "Директория $mount_point/containerd не создана"
        return 1
    fi
    
    if run_sudo test -d "$mount_point/kubelet"; then
        print_success "Директория $mount_point/kubelet создана"
    else
        print_error "Директория $mount_point/kubelet не создана"
        return 1
    fi
    
    return 0
}

# Основная функция
main() {
    print_header "Инициализация хранилища для Kubernetes Worker"
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device)
                STORAGE_DEVICE="$2"
                shift 2
                ;;
            -m|--mount)
                MOUNT_POINT="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Проверка обязательных параметров
    if [[ -z "$STORAGE_DEVICE" ]]; then
        print_error "Не указано устройство хранилища"
        print_info "Используйте: $0 -d /dev/sdb"
        exit 1
    fi
    
    # Инициализация логирования
    init_logging "/tmp/log/installer/init-k8s-worker-storage.log"
    
    # Инициализация sudo сессии
    if ! init_sudo_session; then
        log_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Установка обработчика сигналов для очистки
    setup_signal_handlers
    
    print_section "Проверка параметров"
    
    # Проверка устройства
    if ! check_device "$STORAGE_DEVICE"; then
        exit 1
    fi
    
    # Проверка точки монтирования
    if ! check_mount_point "$MOUNT_POINT"; then
        exit 1
    fi
    
    print_section "Создание файловой системы"
    
    # Создание файловой системы
    if ! create_filesystem "$STORAGE_DEVICE"; then
        exit 1
    fi
    
    print_section "Настройка монтирования"
    
    # Добавление в fstab
    if ! add_to_fstab "$STORAGE_DEVICE" "$MOUNT_POINT"; then
        exit 1
    fi
    
    # Монтирование устройства
    if ! mount_device "$STORAGE_DEVICE" "$MOUNT_POINT"; then
        exit 1
    fi
    
    print_section "Создание директорий и ссылок"
    
    # Создание директорий в хранилище
    if ! create_storage_directories "$MOUNT_POINT"; then
        exit 1
    fi
    
    # Создание символических ссылок
    if ! create_symlinks "$MOUNT_POINT"; then
        exit 1
    fi
    
    print_section "Проверка результата"
    
    # Проверка результата
    if ! verify_installation "$MOUNT_POINT"; then
        exit 1
    fi
    
    print_success "Инициализация хранилища завершена успешно"
    print_info "Устройство: $STORAGE_DEVICE"
    print_info "Точка монтирования: $MOUNT_POINT"
    print_info "Ссылки созданы:"
    print_info "  /var/lib/containerd -> $MOUNT_POINT/containerd"
    print_info "  /var/lib/kubelet -> $MOUNT_POINT/kubelet"
    
    # Очистка ресурсов
    cleanup
}

# Запуск основной функции
main "$@"
