#!/bin/sh

set -eu

# ============================================================
# Backup прошивки Netis NX30 V2
# ============================================================

BACKUP_DIR="/tmp/nx30v2-backup-$(date +%Y%m%d-%H%M%S)"
ARCHIVE="/tmp/$(basename "$BACKUP_DIR").tar.gz"

echo "=============================================="
echo " Backup прошивки Netis NX30 V2"
echo "=============================================="
echo

# ------------------------------------------------------------
# Проверка root
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    echo "ОШИБКА: скрипт необходимо запускать от root."
    echo "Попробуйте:"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Создание каталога backup
# ------------------------------------------------------------

echo "[1/6] Создание каталога резервной копии..."

mkdir -p "$BACKUP_DIR"

echo "Каталог:"
echo "  $BACKUP_DIR"
echo

# ------------------------------------------------------------
# Сохранение информации о системе
# ------------------------------------------------------------

echo "[2/6] Сохранение информации о системе..."

cat /proc/mtd > "$BACKUP_DIR/proc_mtd.txt"
cat /proc/cmdline > "$BACKUP_DIR/cmdline.txt"
uname -a > "$BACKUP_DIR/uname.txt"

if [ -f /etc/openwrt_release ]; then
    cp /etc/openwrt_release "$BACKUP_DIR/openwrt_release.txt"
fi

if [ -f /tmp/sysinfo/model ]; then
    cp /tmp/sysinfo/model "$BACKUP_DIR/model.txt"
fi

if [ -f /tmp/sysinfo/board_name ]; then
    cp /tmp/sysinfo/board_name "$BACKUP_DIR/board_name.txt"
fi

echo "Информация сохранена."
echo

# ------------------------------------------------------------
# Резервное копирование MTD-разделов
# ------------------------------------------------------------

echo "[3/6] Резервное копирование MTD-разделов..."
echo

echo "Будут сохранены:"
echo "  BL2"
echo "  u-boot-env"
echo "  Factory"
echo "  FIP"
echo "  UBI"
echo

# Читаем таблицу /proc/mtd.
#
# mtd0 = весь SPI flash.
#
# Его отдельно не сохраняем, поскольку он содержит все остальные
# разделы целиком и существенно увеличивает размер backup.
#
# Сохраняем mtd1 и выше.

while IFS=' ' read -r DEV SIZE ERASE NAME; do

    case "$DEV" in

        mtd[1-9]*)

            MTD_NUMBER="${DEV#mtd}"

            # Убираем кавычки из имени раздела.
            MTD_NAME=$(echo "$NAME" | tr -d '"')

            OUTPUT="$BACKUP_DIR/${DEV}-${MTD_NAME}.bin"

            echo "----------------------------------------------"
            echo "Раздел: $DEV"
            echo "Имя:    $MTD_NAME"
            echo "Размер: $SIZE"
            echo "Файл:   $OUTPUT"
            echo

            echo "Копирование..."

            dd \
                if="/dev/$DEV" \
                of="$OUTPUT" \
                bs=64K \
                2>/dev/null

            sync

            ACTUAL_SIZE=$(wc -c < "$OUTPUT")

            echo "Готово."
            echo "Фактический размер: $ACTUAL_SIZE байт"
            echo

            ;;

    esac

done < /proc/mtd

# ------------------------------------------------------------
# Информация об UBI
# ------------------------------------------------------------

echo "[4/6] Сохранение информации об UBI..."

if command -v ubinfo >/dev/null 2>&1; then

    ubinfo -a \
        > "$BACKUP_DIR/ubinfo.txt" \
        2>&1 || true

    echo "Информация UBI сохранена."

else

    echo "Команда ubinfo не найдена."

    echo "Команда ubinfo не найдена." \
        > "$BACKUP_DIR/ubinfo.txt"

fi

# Сохраняем информацию о смонтированных UBI/overlay.

if [ -f /proc/mounts ]; then

    grep -E 'ubi|overlay' /proc/mounts \
        > "$BACKUP_DIR/ubi_mounts.txt" \
        || true

fi

echo

# ------------------------------------------------------------
# Сохранение переменных U-Boot
# ------------------------------------------------------------

echo "[5/6] Сохранение переменных U-Boot..."

if command -v fw_printenv >/dev/null 2>&1; then

    fw_printenv \
        > "$BACKUP_DIR/u-boot-env.txt" \
        2>&1 || true

    echo "Переменные U-Boot сохранены."

else

    echo "Команда fw_printenv не найдена."

    echo "fw_printenv не установлен." \
        > "$BACKUP_DIR/u-boot-env.txt"

fi

echo

# ------------------------------------------------------------
# SHA256 контрольные суммы
# ------------------------------------------------------------

echo "Создание контрольных сумм SHA256..."

(
    cd "$BACKUP_DIR"

    sha256sum *.bin > SHA256SUMS
)

echo "Контрольные суммы созданы."
echo

# ------------------------------------------------------------
# Создание архива
# ------------------------------------------------------------

echo "Создание архива..."

tar \
    -czf "$ARCHIVE" \
    -C "/tmp" \
    "$(basename "$BACKUP_DIR")"

echo

# ------------------------------------------------------------
# Итог
# ------------------------------------------------------------

echo "=============================================="
echo " BACKUP ЗАВЕРШЁН"
echo "=============================================="
echo

echo "Каталог резервной копии:"
echo
echo "  $BACKUP_DIR"
echo

echo "Архив:"
echo
echo "  $ARCHIVE"
echo

echo "SHA256 архива:"
sha256sum "$ARCHIVE"

echo
echo "Содержимое резервной копии:"
echo

ls -lh "$BACKUP_DIR"

echo
echo "Размер архива:"
ls -lh "$ARCHIVE"

echo
echo "=============================================="
echo " ВАЖНО"
echo "=============================================="
echo
echo "Скопируйте архив с роутера на компьютер."
echo
echo "Пример:"
echo
echo "scp useradmin@192.168.1.1:$ARCHIVE ."
echo
echo "Особенно сохраните файл:"
echo
echo "  mtd3-Factory.bin"
echo
echo "Он содержит заводские данные устройства."
echo