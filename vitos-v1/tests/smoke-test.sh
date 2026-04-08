#!/usr/bin/env bash
set -euo pipefail

ISO="${1:-$(ls -1t /build/vitos-v1/vitos-v1-*.iso | head -1)}"
[ -f "$ISO" ] || { echo "ISO not found"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -f "$WORK/qemu.pid" ] && kill "$(cat "$WORK/qemu.pid")" 2>/dev/null || true' EXIT
qcow="$WORK/disk.qcow2"
qemu-img create -f qcow2 "$qcow" 20G

LOG="$WORK/serial.log"

# Extract kernel + initrd from the ISO so we can pass a custom -append.
# QEMU rejects -append unless -kernel is set, and -cdrom alone uses the
# ISO's bootloader cmdline which doesn't include vitos.selftest=1.
mkdir -p "$WORK/extract"
xorriso -osirrox on -indev "$ISO" \
  -extract /live/vmlinuz "$WORK/extract/vmlinuz" \
  -extract /live/initrd.img "$WORK/extract/initrd.img" 2>/dev/null || {
    # Fallback path for some live-build versions
    xorriso -osirrox on -indev "$ISO" \
      -extract /live/vmlinuz-vitos "$WORK/extract/vmlinuz" \
      -extract /live/initrd.img-vitos "$WORK/extract/initrd.img"
  }

KVM_FLAG=""
[ -e /dev/kvm ] && KVM_FLAG="-enable-kvm"

qemu-system-x86_64 $KVM_FLAG -m 6144 -smp 4 \
  -kernel "$WORK/extract/vmlinuz" \
  -initrd "$WORK/extract/initrd.img" \
  -append "boot=live components quiet vitos.consent=preaccepted vitos.selftest=1 console=ttyS0 findiso=/$(basename "$ISO")" \
  -cdrom "$ISO" \
  -drive file="$qcow",if=virtio,format=qcow2 \
  -nographic -serial file:"$LOG" \
  -net none \
  -daemonize -pidfile "$WORK/qemu.pid"

echo "Waiting for boot to settle (300s)…"
sleep 300

fail=0

# Build-time assertion: ISO size present and not catastrophically small
size_gb=$(stat -c%s "$ISO" | awk '{printf "%.2f", $1/1073741824}')
echo "ISO size: ${size_gb} GB"
awk -v s="$size_gb" 'BEGIN{exit !(s>=1.0)}' \
  && echo "  PASS: iso_size_nonzero (${size_gb} GB)" \
  || { echo "  FAIL: iso suspiciously small"; fail=$((fail+1)); }

# In-guest selftest assertions appear as VITOS-SELFTEST: <name>=PASS|FAIL
for marker in uname bpf group_students group_admins student_no_sudo \
              auditd idle_ram vitos-busd vitos-bpf-exec vitos-bpf-net \
              vitos-shell-tap vitos-udev-tap vitos-fanotify-tap \
              ollama vitos-ai vitos-dashboard ollama_model alert_pipeline \
              dashboard_health dashboard_index dashboard_auth_required \
              dashboard_sse_gated; do
  if grep -q "VITOS-SELFTEST: ${marker}=PASS" "$LOG"; then
    echo "  PASS: ${marker}"
  else
    echo "  FAIL: ${marker}"
    fail=$((fail+1))
  fi
done

# Banner check
grep -q "VIT Bhopal" "$LOG" && echo "  PASS: banner" \
  || { echo "  FAIL: banner"; fail=$((fail+1)); }

kill "$(cat "$WORK/qemu.pid")" 2>/dev/null || true

if [ "$fail" -gt 0 ]; then
  echo "SMOKE TEST FAILED ($fail assertions)"
  exit 1
fi
echo "SMOKE TEST PASSED"
