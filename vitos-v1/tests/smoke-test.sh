#!/usr/bin/env bash
set -euo pipefail

ISO="${1:-$(ls -1t /build/vitos-v1/vitos-v1-*.iso | head -1)}"
[ -f "$ISO" ] || { echo "ISO not found"; exit 1; }

WORK=$(mktemp -d)
trap '[ -f "$WORK/qemu.pid" ] && kill "$(cat "$WORK/qemu.pid")" 2>/dev/null || true; rm -rf "$WORK"' EXIT
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

KVM_FLAG=()
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  KVM_FLAG=(-enable-kvm -cpu host)
  echo "KVM available -> hardware acceleration ON"
else
  echo "WARNING: /dev/kvm not usable -> falling back to slow TCG soft-emulation."
  echo "         The full live stack likely will NOT reach multi-user in time."
fi

MEM="${SMOKE_MEM:-6144}"          # guest RAM (MB); tune down for small runners
CPUS="${SMOKE_CPUS:-4}"
TIMEOUT="${SMOKE_TIMEOUT:-900}"   # max seconds to wait for the in-guest selftest

qemu-system-x86_64 "${KVM_FLAG[@]}" -m "$MEM" -smp "$CPUS" \
  -kernel "$WORK/extract/vmlinuz" \
  -initrd "$WORK/extract/initrd.img" \
  -append "boot=live components quiet vitos.consent=preaccepted vitos.selftest=1 console=ttyS0 findiso=/$(basename "$ISO")" \
  -cdrom "$ISO" \
  -drive file="$qcow",if=virtio,format=qcow2 \
  -display none -serial file:"$LOG" \
  -net none \
  -daemonize -pidfile "$WORK/qemu.pid"

# Wait until the in-guest selftest finishes (it prints "VITOS-SELFTEST: DONE"
# on ttyS0 once it has run every check) — or QEMU dies, or we hit the deadline.
echo "Waiting up to ${TIMEOUT}s for the in-guest selftest to finish…"
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if grep -q "VITOS-SELFTEST: DONE" "$LOG" 2>/dev/null; then
    echo "selftest completed after ~${waited}s"
    break
  fi
  if [ -f "$WORK/qemu.pid" ] && ! kill -0 "$(cat "$WORK/qemu.pid")" 2>/dev/null; then
    echo "QEMU exited after ~${waited}s before the selftest finished"
    break
  fi
  sleep 10
  waited=$((waited + 10))
done

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
              dashboard_sse_gated \
              ghost_approver_group ghost_state_dirs ghost_scripts \
              ghost_killswitch_ruleset ghost_off_by_default ghost_cli \
              sso_join_script sso_purge_script sso_example_config \
              hardening_lynis_profile hardening_cron hardening_runner \
              pilot_retention_cron pilot_retention_config pilot_lab_scopes \
              pilot_hostname; do
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
  echo "===== serial.log (first 80 lines) ====="
  head -n 80 "$LOG" 2>/dev/null || echo "(serial log empty — guest produced no output)"
  echo "===== serial.log (last 120 lines) ====="
  tail -n 120 "$LOG" 2>/dev/null || true
  echo "======================================="
  echo "SMOKE TEST FAILED ($fail assertions)"
  exit 1
fi
echo "SMOKE TEST PASSED"
