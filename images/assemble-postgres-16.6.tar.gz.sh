#!/bin/bash

# Скрипт для сборки postgres-16.6.tar.gz из частей
# Автор: MONQ Installer
# Использование: ./assemble-postgres-16.6.tar.gz.sh [выходной_файл]

# Цветовые коды
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Определение выходного файла
OUTPUT_FILE="${1:-postgres-16.6.tar.gz}"

print_info "Сборка $OUTPUT_FILE из частей..."

# Проверка наличия частей
if [ ! -f "postgres-16.6.tar.gz-00" ] && [ ! -f "postgres-16.6.tar.gz-01" ]; then
    print_error "Части файла postgres-16.6.tar.gz-* не найдены!"
    exit 1
fi

# Сборка файла из частей (сортировка по числовому порядку)
ls postgres-16.6.tar.gz-* | grep -E "postgres-16.6.tar.gz-[0-9]+$" | sort -V | xargs cat > "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
    print_success "Файл $OUTPUT_FILE успешно собран"
    
    # Проверка контрольной суммы
    if [ -f "postgres-16.6.tar.gz" ]; then
        ORIGINAL_MD5=$(md5sum "postgres-16.6.tar.gz" | cut -d' ' -f1)
        ASSEMBLED_MD5=$(md5sum "$OUTPUT_FILE" | cut -d' ' -f1)
        
        if [ "$ORIGINAL_MD5" = "$ASSEMBLED_MD5" ]; then
            print_success "Контрольная сумма совпадает - файл собран корректно"
        else
            print_error "Контрольная сумма не совпадает!"
            exit 1
        fi
    fi
else
    print_error "Ошибка при сборке файла"
    exit 1
fi
