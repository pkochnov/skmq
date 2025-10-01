#!/bin/bash

# Универсальный скрипт для разделения файлов на части по 8KB
# Автор: MONQ Installer
# Дата: $(date)
# Использование: ./split-installer.sh <файл> [размер_части_в_KB]

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
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo -e "${PURPLE}${BOLD}=== $1 ===${NC}"
}

print_section() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

# Проверка аргументов
if [ $# -lt 1 ]; then
    print_error "Использование: $0 <файл> [размер_части_в_KB]"
    print_info "Пример: $0 monq-installer.tgz 8"
    exit 1
fi

INPUT_FILE="$1"
CHUNK_SIZE_KB="${2:-8}"  # По умолчанию 8KB
CHUNK_SIZE_BYTES=$((CHUNK_SIZE_KB * 1024))

# Проверка наличия исходного файла
if [ ! -f "$INPUT_FILE" ]; then
    print_error "Файл '$INPUT_FILE' не найден!"
    exit 1
fi

# Получение размера файла
FILE_SIZE=$(stat -c%s "$INPUT_FILE")
print_info "Размер файла: $FILE_SIZE байт ($(($FILE_SIZE / 1024)) KB)"
print_info "Размер части: $CHUNK_SIZE_KB KB ($CHUNK_SIZE_BYTES байт)"

# Получение базового имени файла
FILE_BASENAME=$(basename "$INPUT_FILE")

print_header "Разделение $INPUT_FILE на части по $CHUNK_SIZE_KB KB"

# Разделение файла на части с числовыми именами в текущем каталоге
split -b $CHUNK_SIZE_BYTES -d "$INPUT_FILE" "${FILE_BASENAME}-"

# Подсчет количества созданных частей
CHUNK_COUNT=$(ls -1 ${FILE_BASENAME}-* 2>/dev/null | grep -E "${FILE_BASENAME}-[0-9]+$" | wc -l)
print_success "Создано $CHUNK_COUNT частей файла"

# Показ информации о созданных частях
print_section "Информация о частях"
ls -lh ${FILE_BASENAME}-* | grep -E "${FILE_BASENAME}-[0-9]+$"

# Создание скрипта для сборки файла
print_section "Создание скрипта сборки"
cat > "assemble-${FILE_BASENAME}.sh" << EOF
#!/bin/bash

# Скрипт для сборки $FILE_BASENAME из частей
# Автор: MONQ Installer
# Использование: ./assemble-${FILE_BASENAME}.sh [выходной_файл]

# Цветовые коды
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "\${GREEN}✓\${NC} \$1"
}

print_error() {
    echo -e "\${RED}✗\${NC} \$1"
}

print_info() {
    echo -e "\${BLUE}ℹ\${NC} \$1"
}

# Определение выходного файла
OUTPUT_FILE="\${1:-$FILE_BASENAME}"

print_info "Сборка \$OUTPUT_FILE из частей..."

# Проверка наличия частей
if [ ! -f "${FILE_BASENAME}-00" ] && [ ! -f "${FILE_BASENAME}-01" ]; then
    print_error "Части файла ${FILE_BASENAME}-* не найдены!"
    exit 1
fi

# Сборка файла из частей (сортировка по числовому порядку)
ls ${FILE_BASENAME}-* | grep -E "${FILE_BASENAME}-[0-9]+$" | sort -V | xargs cat > "\$OUTPUT_FILE"

if [ \$? -eq 0 ]; then
    print_success "Файл \$OUTPUT_FILE успешно собран"
    
    # Проверка контрольной суммы
    if [ -f "$INPUT_FILE" ]; then
        ORIGINAL_MD5=\$(md5sum "$INPUT_FILE" | cut -d' ' -f1)
        ASSEMBLED_MD5=\$(md5sum "\$OUTPUT_FILE" | cut -d' ' -f1)
        
        if [ "\$ORIGINAL_MD5" = "\$ASSEMBLED_MD5" ]; then
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
EOF

chmod +x "assemble-${FILE_BASENAME}.sh"

print_success "Создан скрипт сборки: assemble-${FILE_BASENAME}.sh"

print_header "Завершение"
print_info "Исходный файл разделен на $CHUNK_COUNT частей по $CHUNK_SIZE_KB KB"
print_info "Части находятся в текущем каталоге: ${FILE_BASENAME}-*"
print_info "Для сборки используйте: ./assemble-${FILE_BASENAME}.sh"
print_info "Или с указанием выходного файла: ./assemble-${FILE_BASENAME}.sh новый-файл.tgz"
