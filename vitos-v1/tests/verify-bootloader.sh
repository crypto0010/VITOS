#!/bin/sh
# VITOS bootloader-install verification (comprehensive).
#
# Reproduces, in a real Kali environment, the exact grub-install call Calamares
# makes inside the target chroot and proves the VITOS wrapper turns the failing
# / unbootable result into a bootable one. Also exercises the live-build hook's
# divert logic, idempotency, BIOS passthrough, and the post-install script.
#
# Run inside kalilinux/kali-rolling with --privileged. Runs every case, prints
# a summary, and exits non-zero if ANY case fails so CI fails loudly.

set -u

REPO_ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
INC="$REPO_ROOT/vitos-v1/live-build/config/includes.chroot"
WRAPPER_SRC="$INC/usr/local/share/vitos/grub-install"
POSTINSTALL_SRC="$INC/usr/local/bin/vitos-postinstall"

FAILED=0
say()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=$((FAILED+1)); }

say "Environment"
. /etc/os-release 2>/dev/null || true
echo "Distro: ${PRETTY_NAME:-unknown}"
[ -f "$WRAPPER_SRC" ]     || { echo "wrapper source missing: $WRAPPER_SRC"; exit 2; }
[ -f "$POSTINSTALL_SRC" ] || { echo "postinstall source missing: $POSTINSTALL_SRC"; exit 2; }

say "Install grub-efi + grub-pc + tooling"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    grub-efi-amd64-bin grub-pc-bin grub-common grub2-common efibootmgr \
    dosfstools gdisk fdisk util-linux mount dpkg debconf >/dev/null
echo "installed."

# ---------------------------------------------------------------------------
# T1: the modules grub-install needs in the target are actually present
# ---------------------------------------------------------------------------
say "T1: x86_64-efi modules present (rules out 'missing modules' root cause)"
if [ -d /usr/lib/grub/x86_64-efi ] && ls /usr/lib/grub/x86_64-efi/*.mod >/dev/null 2>&1; then
    pass "T1 /usr/lib/grub/x86_64-efi has $(ls /usr/lib/grub/x86_64-efi/*.mod | wc -l) modules"
else
    fail "T1 x86_64-efi modules missing"
fi

# ---------------------------------------------------------------------------
# T2: the live-build hook's divert logic installs the wrapper correctly
#     (mirrors hooks/normal/9200-calamares.hook.chroot verbatim)
# ---------------------------------------------------------------------------
say "T2: live-build hook divert logic installs wrapper + creates .distrib"
mkdir -p /usr/local/share/vitos /usr/local/bin
cp "$WRAPPER_SRC"     /usr/local/share/vitos/grub-install
cp "$POSTINSTALL_SRC" /usr/local/bin/vitos-postinstall
chmod +x /usr/local/bin/vitos-postinstall
WRAPPER_SRC_RUNTIME=/usr/local/share/vitos/grub-install
if [ -f "$WRAPPER_SRC_RUNTIME" ]; then
    dpkg-divert --local --rename --add /usr/sbin/grub-install >/dev/null 2>&1 || true
    cp "$WRAPPER_SRC_RUNTIME" /usr/sbin/grub-install
    chmod +x /usr/sbin/grub-install
fi
if [ -x /usr/sbin/grub-install.distrib ] && grep -q "VITOS grub-install wrapper" /usr/sbin/grub-install; then
    pass "T2 wrapper at /usr/sbin/grub-install, real binary at .distrib"
else
    fail "T2 divert/copy did not install wrapper correctly"
fi

# --- loopback FAT32 ESP helpers --------------------------------------------
LOOP=""
setup_esp() {
    rm -f /tmp/esp.img
    truncate -s 256M /tmp/esp.img
    mkfs.vfat -F32 /tmp/esp.img >/dev/null 2>&1
    modprobe loop 2>/dev/null || true
    i=0; while [ $i -lt 8 ]; do [ -e /dev/loop$i ] || mknod -m660 /dev/loop$i b 7 $i 2>/dev/null || true; i=$((i+1)); done
    mkdir -p "$1"
    LOOP=$(losetup --find --show /tmp/esp.img)
    mount "$LOOP" "$1"
    mkdir -p "$1/EFI" /boot/grub
}
teardown_esp() {
    umount "$1" 2>/dev/null || true
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
    LOOP=""
}

EFI_ARGS="--target=x86_64-efi --efi-directory=/mnt/esp --bootloader-id=VITOS --force"

# ---------------------------------------------------------------------------
# T3: baseline reproduces the bug — real grub-install returns exit 1 and
#     leaves nothing bootable (no NVRAM available in the container)
# ---------------------------------------------------------------------------
say "T3: baseline — REAL grub-install with Calamares' exact args (the bug)"
setup_esp /mnt/esp
/usr/sbin/grub-install.distrib $EFI_ARGS >/tmp/baseline.log 2>&1
BASE_RC=$?
echo "real grub-install exit code: $BASE_RC"; tail -n 8 /tmp/baseline.log 2>/dev/null || true
if [ ! -f /mnt/esp/EFI/BOOT/BOOTX64.EFI ]; then
    pass "T3 baseline left NO \\EFI\\BOOT\\BOOTX64.EFI -> unbootable (bug reproduced, rc=$BASE_RC)"
else
    fail "T3 baseline unexpectedly produced BOOTX64.EFI"
fi
teardown_esp /mnt/esp

# ---------------------------------------------------------------------------
# T4: the fix — unqualified grub-install (PATH -> wrapper, like Calamares'
#     check_target_env_call) exits 0 and produces a bootable artifact
# ---------------------------------------------------------------------------
say "T4: fix — 'grub-install' (PATH -> wrapper) exits 0 + bootable artifact"
setup_esp /mnt/esp
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install $EFI_ARGS
WRAP_RC=$?
echo "wrapper exit code: $WRAP_RC"
[ "$WRAP_RC" -eq 0 ] && pass "T4a wrapper returned 0 (Calamares would NOT abort)" || fail "T4a wrapper returned $WRAP_RC"
[ -f /mnt/esp/EFI/BOOT/BOOTX64.EFI ] && pass "T4b \\EFI\\BOOT\\BOOTX64.EFI exists ($(stat -c%s /mnt/esp/EFI/BOOT/BOOTX64.EFI 2>/dev/null) bytes)" || fail "T4b BOOTX64.EFI missing"
[ -f /mnt/esp/EFI/VITOS/grubx64.efi ] && pass "T4c \\EFI\\VITOS\\grubx64.efi exists" || echo "note: VITOS/grubx64.efi absent (pass-1 NVRAM install skipped); removable path still boots"

# ---------------------------------------------------------------------------
# T5: idempotency — running the wrapper again still succeeds (re-install safe)
# ---------------------------------------------------------------------------
say "T5: idempotency — second wrapper run also succeeds"
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install $EFI_ARGS
WRAP_RC2=$?
{ [ "$WRAP_RC2" -eq 0 ] && [ -f /mnt/esp/EFI/BOOT/BOOTX64.EFI ]; } \
    && pass "T5 second run rc=0 and BOOTX64.EFI present" || fail "T5 second run rc=$WRAP_RC2"
echo "--- wrapper log ---"; cat /var/log/vitos-grub-install.log 2>/dev/null || true
teardown_esp /mnt/esp

# ---------------------------------------------------------------------------
# T6: BIOS passthrough — i386-pc target must reach the real binary untouched
# ---------------------------------------------------------------------------
say "T6: BIOS passthrough — i386-pc install routes to real grub-install"
rm -f /tmp/bios.img; truncate -s 64M /tmp/bios.img
i=8; while [ $i -lt 12 ]; do [ -e /dev/loop$i ] || mknod -m660 /dev/loop$i b 7 $i 2>/dev/null || true; i=$((i+1)); done
BLOOP=$(losetup --find --show /tmp/bios.img)
echo -e "o\nn\np\n1\n\n\nw\n" | fdisk "$BLOOP" >/dev/null 2>&1 || true
mkdir -p /tmp/biosboot/boot/grub
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install --target=i386-pc \
    --boot-directory=/tmp/biosboot/boot --force --modules=part_msdos "$BLOOP" >/tmp/bios.log 2>&1
BIOS_RC=$?
echo "i386-pc install exit code: $BIOS_RC"; tail -n 6 /tmp/bios.log 2>/dev/null || true
if [ -d /tmp/biosboot/boot/grub/i386-pc ] && ls /tmp/biosboot/boot/grub/i386-pc/*.mod >/dev/null 2>&1; then
    pass "T6 BIOS install reached real binary (i386-pc modules written)"
else
    fail "T6 BIOS passthrough did not produce i386-pc grub"
fi
losetup -d "$BLOOP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T7: post-install script runs cleanly and writes the stub grub.cfg that
#     Debian's EFI stub needs (else it drops to a grub shell)
# ---------------------------------------------------------------------------
say "T7: vitos-postinstall runs, exits 0, writes stub grub.cfg"
setup_esp /boot/efi
mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/VITOS
# put a dummy binary so IS_EFI is detected and the removable path is satisfied
: > /boot/efi/EFI/BOOT/BOOTX64.EFI
/usr/local/bin/vitos-postinstall
POST_RC=$?
echo "postinstall exit code: $POST_RC"; echo "--- postinstall log ---"; cat /var/log/vitos-postinstall.log 2>/dev/null || true
[ "$POST_RC" -eq 0 ] && pass "T7a vitos-postinstall exited 0" || fail "T7a vitos-postinstall rc=$POST_RC"
{ [ -f /boot/efi/EFI/BOOT/grub.cfg ] || [ -f /boot/efi/EFI/VITOS/grub.cfg ]; } \
    && pass "T7b stub grub.cfg written" || fail "T7b stub grub.cfg missing"
teardown_esp /boot/efi

# ---------------------------------------------------------------------------
say "SUMMARY"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32mALL CASES PASSED — bootloader fix verified end to end.\033[0m\n'
    exit 0
else
    printf '\033[1;31m%d CASE(S) FAILED.\033[0m\n' "$FAILED"
    exit 1
fi
