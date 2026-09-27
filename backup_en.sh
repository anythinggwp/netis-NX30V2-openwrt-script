#!/bin/sh

set -eu

BACKUP_DIR="/tmp/nx30v2-backup-$(date +%Y%m%d-%H%M%S)"
ARCHIVE="/tmp/$(basename "$BACKUP_DIR").tar.gz"

echo "=== Netis NX30 V2 firmware backup ==="
echo

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run as root"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[1/5] Collecting system information..."

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

echo "[2/5] Dumping MTD partitions..."

# Read the MTD table dynamically.
# We explicitly exclude the complete spi0.0 container (mtd0),
# because it contains the same flash and would duplicate the backup.

while IFS=' ' read -r dev size erase name; do
    case "$dev" in
        mtd[1-9]*)
            mtd_num="${dev#mtd}"

            # Remove quotes from name.
            name=$(echo "$name" | tr -d '"')

            output="$BACKUP_DIR/${dev}-${name}.bin"

            echo "  -> $dev ($name) -> $output"

            dd if="/dev/$dev" \
               of="$output" \
               bs=64K \
               2>/dev/null

            sync

            actual_size=$(wc -c < "$output")

            echo "     size: $actual_size bytes"
            ;;
    esac
done < /proc/mtd

echo "[3/5] Dumping UBI information..."

if command -v ubinfo >/dev/null 2>&1; then
    ubinfo -a > "$BACKUP_DIR/ubinfo.txt" 2>&1 || true
fi

if [ -f /proc/mounts ]; then
    grep -E 'ubi|overlay' /proc/mounts \
        > "$BACKUP_DIR/ubi_mounts.txt" || true
fi

echo "[4/5] Saving U-Boot environment..."

if command -v fw_printenv >/dev/null 2>&1; then
    fw_printenv > "$BACKUP_DIR/u-boot-env.txt" 2>&1 || true
else
    echo "fw_printenv not available" > "$BACKUP_DIR/u-boot-env.txt"
fi

echo "[5/5] Creating checksums..."

(
    cd "$BACKUP_DIR"
    sha256sum *.bin > SHA256SUMS
)

echo
echo "Creating archive..."

tar -czf "$ARCHIVE" -C "/tmp" "$(basename "$BACKUP_DIR")"

echo
echo "======================================"
echo "BACKUP COMPLETE"
echo "======================================"
echo
echo "Directory:"
echo "  $BACKUP_DIR"
echo
echo "Archive:"
echo "  $ARCHIVE"
echo
echo "SHA256:"
sha256sum "$ARCHIVE"
echo
echo "Files:"
ls -lh "$BACKUP_DIR"
echo
echo "Archive size:"
ls -lh "$ARCHIVE"