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
MKCFG_WRAPPER_SRC="$INC/usr/local/share/vitos/grub-mkconfig"
POSTINSTALL_SRC="$INC/usr/local/bin/vitos-postinstall"

FAILED=0
say()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=$((FAILED+1)); }

say "Environment"
. /etc/os-release 2>/dev/null || true
echo "Distro: ${PRETTY_NAME:-unknown}"
[ -f "$WRAPPER_SRC" ]       || { echo "wrapper source missing: $WRAPPER_SRC"; exit 2; }
[ -f "$MKCFG_WRAPPER_SRC" ] || { echo "grub-mkconfig wrapper source missing: $MKCFG_WRAPPER_SRC"; exit 2; }
[ -f "$POSTINSTALL_SRC" ]   || { echo "postinstall source missing: $POSTINSTALL_SRC"; exit 2; }

say "Install grub-efi + grub-pc + tooling"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    grub-efi-amd64-bin grub-pc-bin grub-common grub2-common efibootmgr \
    dosfstools e2fsprogs gdisk fdisk util-linux mount dpkg debconf >/dev/null
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
# Put the boot-directory on a real ext4 loop device so grub-probe resolves a
# block device (the CI container's root is overlayfs, which grub-probe can't
# canonicalize). This isolates the wrapper-passthrough question from the host.
rm -f /tmp/bios.img; truncate -s 128M /tmp/bios.img
i=8; while [ $i -lt 12 ]; do [ -e /dev/loop$i ] || mknod -m660 /dev/loop$i b 7 $i 2>/dev/null || true; i=$((i+1)); done
mkfs.ext4 -F -q /tmp/bios.img
BLOOP=$(losetup --find --show /tmp/bios.img)
mkdir -p /mnt/bios; mount "$BLOOP" /mnt/bios; mkdir -p /mnt/bios/boot
: > /var/log/vitos-grub-install.log 2>/dev/null || true
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install --target=i386-pc \
    --boot-directory=/mnt/bios/boot --force --modules=part_msdos "$BLOOP" >/tmp/bios.log 2>&1
BIOS_RC=$?
echo "i386-pc install exit code: $BIOS_RC"; tail -n 6 /tmp/bios.log 2>/dev/null || true
# (a) the wrapper must NOT have taken the EFI branch for a BIOS target
if grep -q "EFI install requested" /var/log/vitos-grub-install.log 2>/dev/null; then
    fail "T6a wrapper wrongly treated i386-pc as EFI"
else
    pass "T6a wrapper did not divert BIOS target into EFI path"
fi
# (b) the real binary must have run and produced i386-pc modules
if [ -d /mnt/bios/boot/grub/i386-pc ] && ls /mnt/bios/boot/grub/i386-pc/*.mod >/dev/null 2>&1; then
    pass "T6b BIOS install reached real binary (i386-pc modules written, rc=$BIOS_RC)"
elif grep -q "Installing for i386-pc platform" /tmp/bios.log 2>/dev/null; then
    pass "T6b real grub-install ran the i386-pc install (passthrough confirmed, rc=$BIOS_RC)"
else
    fail "T6b BIOS passthrough did not reach the real grub-install"
fi
umount /mnt/bios 2>/dev/null || true
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
# T8: the EFI path NEVER returns non-zero, even when every install strategy
#     fails. This is the guarantee behind error2.jpeg: Calamares aborts the
#     whole install on a non-zero grub-install, and that abort happens BEFORE
#     grub-mkconfig runs — so /boot/grub/grub.cfg never gets written. As long as
#     the wrapper exits 0, Calamares proceeds to grub-mkconfig — which is ITSELF
#     wrapped so it can never abort either (see T9/T10) — and then to
#     vitos-postinstall (which repairs the ESP). We simulate
#     total failure with a READ-ONLY ESP so all three passes cannot write.
# ---------------------------------------------------------------------------
say "T8: wrapper exits 0 even when every EFI strategy fails (no Calamares abort)"
rm -f /tmp/roesp.img
truncate -s 64M /tmp/roesp.img
mkfs.vfat -F32 /tmp/roesp.img >/dev/null 2>&1
mkdir -p /mnt/roesp
RLOOP=$(losetup --find --show /tmp/roesp.img)
mount -o ro "$RLOOP" /mnt/roesp 2>/dev/null || mount "$RLOOP" /mnt/roesp
mount -o remount,ro "$RLOOP" /mnt/roesp 2>/dev/null || true
: > /var/log/vitos-grub-install.log 2>/dev/null || true
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-install \
    --target=x86_64-efi --efi-directory=/mnt/roesp --bootloader-id=VITOS --force \
    >/tmp/t8.log 2>&1
T8_RC=$?
echo "wrapper exit code on read-only ESP: $T8_RC"
tail -n 6 /var/log/vitos-grub-install.log 2>/dev/null || true
if [ "$T8_RC" -eq 0 ]; then
    pass "T8 wrapper returned 0 despite total failure -> Calamares cannot abort at the bootloader step"
else
    fail "T8 wrapper returned $T8_RC -> Calamares WOULD abort (error2.jpeg reproduced)"
fi
umount /mnt/roesp 2>/dev/null || true
losetup -d "$RLOOP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T9: the live-build hook's divert logic installs the grub-mkconfig wrapper too
#     (mirrors the grub-install divert in 9200-calamares.hook.chroot)
# ---------------------------------------------------------------------------
say "T9: divert installs grub-mkconfig wrapper + creates .distrib"
cp "$MKCFG_WRAPPER_SRC" /usr/local/share/vitos/grub-mkconfig
MKCFG_RUNTIME=/usr/local/share/vitos/grub-mkconfig
if [ -f "$MKCFG_RUNTIME" ]; then
    dpkg-divert --local --rename --add /usr/sbin/grub-mkconfig >/dev/null 2>&1 || true
    cp "$MKCFG_RUNTIME" /usr/sbin/grub-mkconfig
    chmod +x /usr/sbin/grub-mkconfig
fi
if [ -x /usr/sbin/grub-mkconfig.distrib ] && grep -q "VITOS grub-mkconfig wrapper" /usr/sbin/grub-mkconfig; then
    pass "T9 wrapper at /usr/sbin/grub-mkconfig, real binary at .distrib"
else
    fail "T9 divert/copy did not install the grub-mkconfig wrapper correctly"
fi

# ---------------------------------------------------------------------------
# T10: the bootloader module's SECOND command (grub-mkconfig -o
#      /boot/grub/grub.cfg) can NEVER abort the install. This is the exact
#      failure in VITOS Error.mp4: grub-install passes, then grub-mkconfig
#      returns error code 1 and Calamares shows "Installation Failed". The
#      wrapper must always exit 0 AND leave a grub.cfg with a real menuentry.
# ---------------------------------------------------------------------------
say "T10: grub-mkconfig wrapper exits 0 + writes a valid grub.cfg (no Calamares abort)"
# Stage a realistic boot dir on a REAL ext4 loop fs, so the fallback has a kernel
# to reference and findmnt/blkid yield a UUID.
rm -f /tmp/t10root.img; truncate -s 64M /tmp/t10root.img
i=12; while [ $i -lt 16 ]; do [ -e /dev/loop$i ] || mknod -m660 /dev/loop$i b 7 $i 2>/dev/null || true; i=$((i+1)); done
mkfs.ext4 -F -q /tmp/t10root.img
T10LOOP=$(losetup --find --show /tmp/t10root.img)
mkdir -p /mnt/t10root; mount "$T10LOOP" /mnt/t10root
mkdir -p /mnt/t10root/boot
: > /mnt/t10root/boot/vmlinuz-9.9.9-vitos
: > /mnt/t10root/boot/initrd.img-9.9.9-vitos
T10UUID=$(blkid -s UUID -o value "$T10LOOP" 2>/dev/null)
T10OUT=/mnt/t10root/boot/grub/grub.cfg

# T10a/b: real grub-mkconfig present. In this container it fails on the overlayfs
# root (grub-probe cannot canonicalize it) — exactly like it fails on lab
# hardware. The wrapper must still exit 0 with a valid grub.cfg.
: > /var/log/vitos-grub-mkconfig.log 2>/dev/null || true
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-mkconfig -o "$T10OUT" >/tmp/t10a.log 2>&1
T10A_RC=$?
echo "grub-mkconfig wrapper exit code: $T10A_RC"
[ "$T10A_RC" -eq 0 ] && pass "T10a wrapper returned 0 (Calamares would NOT abort)" || fail "T10a wrapper returned $T10A_RC"
{ [ -s "$T10OUT" ] && grep -q '^[[:space:]]*menuentry' "$T10OUT"; } \
    && pass "T10b grub.cfg written with a menuentry" || fail "T10b grub.cfg missing or has no menuentry"

# T10c/d/e: force the real binary unavailable — deterministically exercises the
# hand-written fallback and proves it is well-formed and pins the staged kernel.
rm -f "$T10OUT"
mv /usr/sbin/grub-mkconfig.distrib /usr/sbin/grub-mkconfig.distrib.hidden
: > /var/log/vitos-grub-mkconfig.log 2>/dev/null || true
PATH="/usr/sbin:/usr/bin:/sbin:/bin" grub-mkconfig -o "$T10OUT" >/tmp/t10c.log 2>&1
T10C_RC=$?
mv /usr/sbin/grub-mkconfig.distrib.hidden /usr/sbin/grub-mkconfig.distrib
[ "$T10C_RC" -eq 0 ] && pass "T10c fallback path returned 0" || fail "T10c fallback path returned $T10C_RC"
if grep -q 'vmlinuz-9.9.9-vitos' "$T10OUT" 2>/dev/null; then
    pass "T10d fallback grub.cfg references the staged kernel"
else
    fail "T10d fallback grub.cfg did not reference the staged kernel"
fi
if [ -n "$T10UUID" ] && grep -q "$T10UUID" "$T10OUT" 2>/dev/null; then
    pass "T10e fallback grub.cfg pins the root fs UUID ($T10UUID)"
else
    echo "note: T10e root UUID not embedded (findmnt/blkid unavailable here) — fallback used search --file"
fi
echo "--- grub-mkconfig wrapper log ---"; cat /var/log/vitos-grub-mkconfig.log 2>/dev/null || true
umount /mnt/t10root 2>/dev/null || true
losetup -d "$T10LOOP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# T11: the grub-mkconfig wrapper must reproduce the manually-proven fix —
#      assert GRUB_DISABLE_OS_PROBER=true in /etc/default/grub BEFORE generating.
#      In the field (grub_fix.pdf) os-prober scanning Windows + stale Kali made
#      the real grub-mkconfig misbehave; adding this single line to
#      /etc/default/grub and regenerating produced the clean 8-entry VITOS menu.
#      The wrapper now does that step itself (the /etc/default/grub.d drop-in was
#      NOT honoured in the field). Uses the VITOS_GRUB_DEFAULT_FILE test hook so
#      the assertion is hermetic and never touches the container's real config.
# ---------------------------------------------------------------------------
say "T11: grub-mkconfig wrapper forces GRUB_DISABLE_OS_PROBER=true (the proven fix)"
T11GRUB=/tmp/t11-default-grub
T11OUT=/tmp/t11-grub.cfg
# Simulate exactly the state grub_fix.pdf showed Calamares' grubcfg module leaves
# behind: os-prober commented out, plus an unrelated setting that must survive.
printf '%s\n' 'GRUB_TIMEOUT=10' '#GRUB_DISABLE_OS_PROBER=false' > "$T11GRUB"
VITOS_GRUB_DEFAULT_FILE="$T11GRUB" PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
    grub-mkconfig -o "$T11OUT" >/tmp/t11.log 2>&1 || true
if grep -q '^GRUB_DISABLE_OS_PROBER=true$' "$T11GRUB" 2>/dev/null; then
    pass "T11a wrapper asserted GRUB_DISABLE_OS_PROBER=true in the grub defaults file"
else
    fail "T11a wrapper did NOT set GRUB_DISABLE_OS_PROBER=true (os-prober would still run)"
fi
if grep -q 'GRUB_DISABLE_OS_PROBER=false' "$T11GRUB" 2>/dev/null \
   || grep -Eq '^[[:space:]]*#.*GRUB_DISABLE_OS_PROBER' "$T11GRUB" 2>/dev/null; then
    fail "T11b a stale/commented os-prober line survived — could re-enable os-prober"
else
    pass "T11b no stale 'false'/commented os-prober line remains"
fi
if grep -q '^GRUB_TIMEOUT=10$' "$T11GRUB" 2>/dev/null; then
    pass "T11c unrelated GRUB_* settings preserved"
else
    fail "T11c clobbered an unrelated GRUB_* setting"
fi
# Idempotency: a second run must not accumulate duplicate os-prober lines.
VITOS_GRUB_DEFAULT_FILE="$T11GRUB" PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
    grub-mkconfig -o "$T11OUT" >/tmp/t11b.log 2>&1 || true
T11N=$(grep -c 'GRUB_DISABLE_OS_PROBER' "$T11GRUB" 2>/dev/null || echo 0)
[ "$T11N" = "1" ] \
    && pass "T11d idempotent — exactly one GRUB_DISABLE_OS_PROBER line after re-run" \
    || fail "T11d expected exactly 1 os-prober line, found $T11N"
echo "--- /etc/default/grub (simulated) after wrapper ---"; cat "$T11GRUB" 2>/dev/null || true
rm -f "$T11GRUB" "$T11OUT" /tmp/t11.log /tmp/t11b.log

# ---------------------------------------------------------------------------
say "SUMMARY"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32mALL CASES PASSED — bootloader fix verified end to end.\033[0m\n'
    exit 0
else
    printf '\033[1;31m%d CASE(S) FAILED.\033[0m\n' "$FAILED"
    exit 1
fi
