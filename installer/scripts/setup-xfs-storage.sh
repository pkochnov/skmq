# Настройка XFS файловой системы на /dev/sdb
DEVICE="/dev/sdb"
MOUNT_POINT="/mnt/storage"

# Создание XFS файловой системы
echo "🔧 Создание XFS файловой системы на $DEVICE"
sudo mkfs.xfs -f "$DEVICE"

# Создание точки монтирования
echo "📁 Создание точки монтирования $MOUNT_POINT"
sudo mkdir -p "$MOUNT_POINT"

# Добавление в /etc/fstab
echo "📝 Добавление записи в /etc/fstab"
if ! grep -q "^$DEVICE" /etc/fstab; then
    echo "$DEVICE $MOUNT_POINT xfs defaults 0 2" | sudo tee -a /etc/fstab
fi

# Монтирование
echo "🔗 Монтирование файловой системы"
sudo mount "$MOUNT_POINT"

# Создание папок
echo "📂 Создание необходимых папок"
sudo mkdir -p "$MOUNT_POINT/docker" "$MOUNT_POINT/var"
sudo chmod 755 "$MOUNT_POINT/docker" "$MOUNT_POINT/var"
sudo chown root:root "$MOUNT_POINT/docker" "$MOUNT_POINT/var"