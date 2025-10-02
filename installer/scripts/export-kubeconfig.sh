#!/bin/bash

# Скрипт экспорта kubeconfig файла с контроллера
# Создает доступную копию kubeconfig файла для передачи на worker узлы

set -euo pipefail

# Загрузка общих функций
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/common.sh"

# Функция показа справки
show_help() {
    echo "Скрипт экспорта kubeconfig файла с контроллера"
    echo ""
    echo "Использование:"
    echo "  $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  --output-dir DIR     Директория для сохранения kubeconfig (по умолчанию: /tmp)"
    echo "  --filename NAME      Имя файла kubeconfig (по умолчанию: kubeconfig-export)"
    echo "  --permissions PERM   Права доступа к файлу (по умолчанию: 644)"
    echo "  --help, -h           Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0"
    echo "  $0 --output-dir /home/user --filename my-kubeconfig"
    echo "  $0 --permissions 600"
}

# Параметры по умолчанию
OUTPUT_DIR="/tmp"
FILENAME="kubeconfig-export"
PERMISSIONS="644"

# Обработка аргументов командной строки
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --filename)
            FILENAME="$2"
            shift 2
            ;;
        --permissions)
            PERMISSIONS="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Неизвестный параметр: $1"
            show_help
            exit 1
            ;;
    esac
done

# Функция проверки, что скрипт запущен на контроллере
check_controller() {
    print_section "Проверка контроллера"
    
    # Проверяем, что мы на контроллере
    if [[ ! -f "/etc/kubernetes/admin.conf" ]]; then
        print_error "Файл /etc/kubernetes/admin.conf не найден"
        print_info "Этот скрипт должен выполняться на контроллере Kubernetes"
        exit 1
    fi
    
    # Проверяем, что kubelet работает
    if ! systemctl is-active --quiet kubelet; then
        print_warning "Сервис kubelet не активен"
    fi
    
    print_success "Контроллер Kubernetes обнаружен"
}

# Функция создания доступной копии kubeconfig
export_kubeconfig() {
    print_section "Экспорт kubeconfig"
    
    local source_file="/etc/kubernetes/admin.conf"
    
    # Создаем директорию, если она не существует
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        print_info "Создание директории: $OUTPUT_DIR"
        run_sudo mkdir -p "$OUTPUT_DIR"
    fi
    
    # Копируем kubeconfig файл
    print_info "Копирование kubeconfig из $source_file в $OUTPUT_DIR/$FILENAME"
    if run_sudo cp "$source_file" "$OUTPUT_DIR/$FILENAME"; then
        print_success "Kubeconfig файл скопирован"
    else
        print_error "Не удалось скопировать kubeconfig файл"
        return 1
    fi
    
    # Устанавливаем права доступа
    print_info "Установка прав доступа: $PERMISSIONS"
    if run_sudo chmod "$PERMISSIONS" "$OUTPUT_DIR/$FILENAME"; then
        print_success "Права доступа установлены"
    else
        print_warning "Не удалось установить права доступа"
    fi
    
    # Устанавливаем владельца (если не root)
    if [[ $EUID -ne 0 ]]; then
        print_info "Установка владельца файла: $(whoami)"
        if run_sudo chown "$(whoami):$(whoami)" "$OUTPUT_DIR/$FILENAME"; then
            print_success "Владелец файла установлен"
        else
            print_warning "Не удалось установить владельца файла"
        fi
    fi
    
    # Проверяем размер файла
    local file_size=$(run_sudo wc -c < "$OUTPUT_DIR/$FILENAME")
    if [[ $file_size -gt 0 ]]; then
        print_success "Размер файла: $file_size байт"
    else
        print_error "Файл пустой или не существует"
        return 1
    fi
}

# Функция проверки экспортированного файла
verify_export() {
    print_section "Проверка экспортированного файла"
    
    # Проверяем, что файл существует и не пустой
    if [[ ! -f "$OUTPUT_DIR/$FILENAME" ]]; then
        print_error "Экспортированный файл не найден: $OUTPUT_DIR/$FILENAME"
        return 1
    fi
    
    if [[ ! -s "$OUTPUT_DIR/$FILENAME" ]]; then
        print_error "Экспортированный файл пустой: $OUTPUT_DIR/$FILENAME"
        return 1
    fi
    
    print_success "Файл готов к использованию"
    return 0
}

# Функция показа информации о файле
show_file_info() {
    print_section "Информация о файле"
    
    print_info "Путь к файлу: $OUTPUT_DIR/$FILENAME"
    print_info "Размер: $(run_sudo wc -c < "$OUTPUT_DIR/$FILENAME") байт"
    print_info "Права доступа: $(run_sudo ls -l "$OUTPUT_DIR/$FILENAME" | awk '{print $1}')"
    print_info "Владелец: $(run_sudo ls -l "$OUTPUT_DIR/$FILENAME" | awk '{print $3":"$4}')"
    
    # Показываем первые несколько строк для проверки
    print_info "Содержимое (первые 5 строк):"
    run_sudo head -5 "$OUTPUT_DIR/$FILENAME" | sed 's/^/  /'
    
    if [[ $(run_sudo wc -l < "$OUTPUT_DIR/$FILENAME") -gt 5 ]]; then
        print_info "  ... (файл содержит больше строк)"
    fi
}

# Функция показа инструкций по использованию
show_usage_instructions() {
    print_section "Инструкции по использованию"
    
    print_info "Для копирования файла на локальную машину используйте:"
    print_info "  scp $MONQ_USER@$(hostname):$OUTPUT_DIR/$FILENAME ./kubeconfig"
    print_info ""
    print_info "Для копирования файла на worker узел используйте:"
    print_info "  scp $OUTPUT_DIR/$FILENAME $MONQ_USER@<worker-ip>:/tmp/kubeconfig"
    print_info ""
    print_info "Для использования kubeconfig на worker узле:"
    print_info "  kubectl --kubeconfig=/tmp/kubeconfig get nodes"
    print_info "  export KUBECONFIG=/tmp/kubeconfig"
    print_info "  kubectl get nodes"
}

# Основная функция
main() {
    print_header "Экспорт kubeconfig с контроллера"
    
    # Инициализируем sudo сессию
    if ! init_sudo_session; then
        print_error "Не удалось инициализировать sudo сессию"
        exit 1
    fi
    
    # Проверяем, что скрипт запущен на контроллере
    check_controller
    
    # Экспортируем kubeconfig
    if export_kubeconfig; then
        print_success "Kubeconfig успешно экспортирован в $OUTPUT_DIR/$FILENAME"
    else
        print_error "Не удалось экспортировать kubeconfig"
        exit 1
    fi
    
    # Проверяем экспортированный файл
    if verify_export; then
        print_success "Экспортированный файл проверен"
    else
        print_error "Проблемы с экспортированным файлом"
        exit 1
    fi
    
    # Показываем информацию о файле
    show_file_info
    
    # Показываем инструкции по использованию
    show_usage_instructions
    
    print_success "Экспорт kubeconfig завершен успешно"
    print_info "Файл сохранен: $OUTPUT_DIR/$FILENAME"
}

# Запуск основной функции
main "$@"
