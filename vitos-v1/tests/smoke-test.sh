#!/usr/bin/env bash
set -euo pipefail

ISO="${1:-$(ls -1t /build/vitos-v1/vitos-v1-*.iso | head -1)}"
[ -f "$ISO" ] || { echo "ISO not found"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; pkill -P $$ qemu-system-x86_64 2>/dev/null || true' EXIT
qcow="$WORK/disk.qcow2"
qemu-img create -f qcow2 "$qcow" 20G

LOG="$WORK/serial.log"

qemu-system-x86_64 -enable-kvm -m 6144 -smp 4 \
  -cdrom "$ISO" -drive file="$qcow",if=virtio,format=qcow2 \
  -nographic -serial file:"$LOG" \
  -append "boot=live components quiet vitos.consent=preaccepted vitos.selftest=1 console=ttyS0" \
  -net none \
  -daemonize -pidfile "$WORK/qemu.pid"

echo "Waiting for boot to settle (180s)…"
sleep 180

fail=0

# Build-time assertion: ISO size 4.0–5.0 GB
size_gb=$(stat -c%s "$ISO" | awk '{printf "%.2f", $1/1073741824}')
echo "ISO size: ${size_gb} GB"
awk -v s="$size_gb" 'BEGIN{exit !(s>=4.0 && s<=5.0)}' \
  && echo "  PASS: iso_size in 4.0–5.0 GB" \
  || { echo "  FAIL: iso_size out of bounds"; fail=$((fail+1)); }

# In-guest selftest assertions appear as VITOS-SELFTEST: <name>=PASS|FAIL
for marker in uname bpf group_students group_admins student_no_sudo \
              auditd idle_ram vitos-busd vitos-bpf-exec vitos-bpf-net \
              vitos-shell-tap vitos-udev-tap vitos-fanotify-tap \
              ollama vitos-ai ollama_model alert_pipeline; do
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
