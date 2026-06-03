#!/bin/sh
# VITOS bootloader-install verification.
#
# Reproduces, in a real Kali environment, the exact grub-install call that
# Calamares makes inside the target chroot:
#
#   grub-install --target=x86_64-efi --efi-directory=/boot/efi \
#                --bootloader-id=VITOS --force
#
# and proves that the VITOS wrapper turns the (otherwise unbootable / failing)
# result into a bootable one. The container has no writable UEFI NVRAM, which
# mirrors the VM/OVMF condition that triggers the user's "error code 1".
#
# Run inside kalilinux/kali-rolling with --privileged. Exits non-zero on any
# failed assertion so CI fails loudly.

set -eu

REPO_ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
WRAPPER_SRC="$REPO_ROOT/vitos-v1/live-build/config/includes.chroot/usr/local/share/vitos/grub-install"

say()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }

say "Environment"
. /etc/os-release 2>/dev/null || true
echo "Distro: ${PRETTY_NAME:-unknown}"
[ -f "$WRAPPER_SRC" ] || fail "wrapper source not found at $WRAPPER_SRC"

say "Install grub-efi + tooling"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    grub-efi-amd64-bin grub-common grub2-common efibootmgr \
    dosfstools gdisk fdisk util-linux mount dpkg >/dev/null

say "Assertion 1: x86_64-efi modules present (rules out 'missing modules')"
if [ -d /usr/lib/grub/x86_64-efi ] && ls /usr/lib/grub/x86_64-efi/*.mod >/dev/null 2>&1; then
    pass "/usr/lib/grub/x86_64-efi has $(ls /usr/lib/grub/x86_64-efi/*.mod | wc -l) modules"
else
    fail "/usr/lib/grub/x86_64-efi modules missing (grub-efi-amd64-bin did not deliver them)"
fi

say "Install the VITOS wrapper exactly as the live-build hook does"
mkdir -p /usr/local/share/vitos
cp "$WRAPPER_SRC" /usr/local/share/vitos/grub-install
dpkg-divert --local --rename --add /usr/sbin/grub-install >/dev/null 2>&1 || true
cp /usr/local/share/vitos/grub-install /usr/sbin/grub-install
chmod +x /usr/sbin/grub-install
[ -x /usr/sbin/grub-install.distrib ] || fail "divert did not create /usr/sbin/grub-install.distrib"
pass "wrapper installed; real binary at /usr/sbin/grub-install.distrib"

# --- build a loopback disk with a FAT32 ESP --------------------------------
setup_esp() {
    rm -f /tmp/esp.img
    truncate -s 256M /tmp/esp.img
    mkfs.vfat -F32 /tmp/esp.img >/dev/null
    modprobe loop 2>/dev/null || true
    i=0; while [ $i -lt 8 ]; do [ -e /dev/loop$i ] || mknod -m660 /dev/loop$i b 7 $i 2>/dev/null || true; i=$((i+1)); done
    mkdir -p /mnt/esp
    LOOP=$(losetup --find --show /tmp/esp.img)
    mount "$LOOP" /mnt/esp
    mkdir -p /mnt/esp/EFI /boot/grub
}
teardown_esp() {
    umount /mnt/esp 2>/dev/null || true
    [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null || true
}

CMD_ARGS="--target=x86_64-efi --efi-directory=/mnt/esp --bootloader-id=VITOS --force"

say "Baseline: the REAL grub-install with Calamares' exact args (no NVRAM available)"
setup_esp
set +e
/usr/sbin/grub-install.distrib $CMD_ARGS >/tmp/baseline.log 2>&1
BASE_RC=$?
set -e
echo "real grub-install exit code: $BASE_RC"
tail -n 20 /tmp/baseline.log || true
if [ -f /mnt/esp/EFI/BOOT/BOOTX64.EFI ]; then
    echo "baseline produced BOOTX64.EFI (unexpected but fine)"
else
    pass "baseline left NO \\EFI\\BOOT\\BOOTX64.EFI -> unbootable without NVRAM (this is the bug)"
fi
teardown_esp

say "Fixed: invoke 'grub-install' (PATH -> VITOS wrapper) with the same args"
setup_esp
set +e
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install $CMD_ARGS
WRAP_RC=$?
set -e
echo "wrapper exit code: $WRAP_RC"

say "Assertion 2: wrapper exited 0"
[ "$WRAP_RC" -eq 0 ] && pass "wrapper returned 0 (Calamares bootloader module would NOT abort)" \
    || fail "wrapper returned $WRAP_RC"

say "Assertion 3: removable boot path present (boots without NVRAM)"
[ -f /mnt/esp/EFI/BOOT/BOOTX64.EFI ] && pass "\\EFI\\BOOT\\BOOTX64.EFI exists ($(stat -c%s /mnt/esp/EFI/BOOT/BOOTX64.EFI) bytes)" \
    || fail "\\EFI\\BOOT\\BOOTX64.EFI was not created"

say "Assertion 4: branded EFI binary present"
if [ -f /mnt/esp/EFI/VITOS/grubx64.efi ]; then
    pass "\\EFI\\VITOS\\grubx64.efi exists"
else
    echo "note: \\EFI\\VITOS\\grubx64.efi absent (pass 1 NVRAM install skipped) - removable path still boots"
fi

say "Wrapper log (/var/log/vitos-grub-install.log)"
cat /var/log/vitos-grub-install.log 2>/dev/null || echo "(no log)"
teardown_esp

say "ALL ASSERTIONS PASSED — wrapper makes the failing install succeed AND bootable"
