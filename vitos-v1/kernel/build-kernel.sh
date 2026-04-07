#!/usr/bin/env bash
# vitos-v1/kernel/build-kernel.sh
set -euo pipefail

KVER="${KVER:-6.6.52}"
WORK="${WORK:-/build/work/kernel}"
OUT="${OUT:-/build/vitos-v1/live-build/config/packages.chroot}"
FRAGMENT="$(dirname "$0")/vitos.config"

mkdir -p "$WORK" "$OUT"
cd "$WORK"

if [ ! -d "linux-${KVER}" ]; then
  curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz" \
    | tar -xJf -
fi
cd "linux-${KVER}"

# Force GCC 12. Kali ships GCC 14 which defaults to C23; Linux 6.6
# predates the kernel's C23 port and fails to compile with errors like
# "cannot use keyword 'false' as enumeration constant".
export CC=gcc-12
export HOSTCC=gcc-12
export KBUILD_BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

make CC=gcc-12 HOSTCC=gcc-12 defconfig
./scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
make CC=gcc-12 HOSTCC=gcc-12 olddefconfig

for opt in CONFIG_BPF_SYSCALL CONFIG_USER_NS CONFIG_AUDIT CONFIG_FANOTIFY CONFIG_CGROUP_BPF; do
  grep -q "^${opt}=y" .config || { echo "MISSING: $opt"; exit 1; }
done

echo "-vitos" > localversion-vitos

make -j"$(nproc)" CC=gcc-12 HOSTCC=gcc-12 bindeb-pkg \
     LOCALVERSION=-vitos KDEB_PKGVERSION="${KVER}-vitos1"

mv ../linux-image-*-vitos_*.deb ../linux-headers-*-vitos_*.deb "$OUT/"
echo "Built: $(ls "$OUT"/linux-image-*-vitos_*.deb)"
