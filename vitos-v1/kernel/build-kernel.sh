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

# Start from defconfig, apply our fragment
make defconfig
./scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
make olddefconfig

# Verify forced options stuck
for opt in CONFIG_BPF_SYSCALL CONFIG_USER_NS CONFIG_AUDIT CONFIG_FANOTIFY CONFIG_CGROUP_BPF; do
  grep -q "^${opt}=y" .config || { echo "MISSING: $opt"; exit 1; }
done

echo "-vitos" > localversion-vitos

# Build .deb packages
make -j"$(nproc)" bindeb-pkg LOCALVERSION=-vitos KDEB_PKGVERSION="${KVER}-vitos1"

mv ../linux-image-*-vitos_*.deb ../linux-headers-*-vitos_*.deb "$OUT/"
echo "Built: $(ls "$OUT"/linux-image-*-vitos_*.deb)"
