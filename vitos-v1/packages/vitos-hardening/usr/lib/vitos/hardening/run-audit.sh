#!/usr/bin/env bash
# /usr/lib/vitos/hardening/run-audit.sh — quarterly CVE + lynis audit.
# Outputs land under /var/log/vitos/hardening/<YYYY-MM-DD>/.
set -euo pipefail

OUT=/var/log/vitos/hardening/$(date +%Y-%m-%d)
mkdir -p "$OUT"

echo "== debsecan ==" | tee "$OUT/cve.txt"
debsecan --suite kali-rolling --format detail >> "$OUT/cve.txt" 2>&1 || true

echo "== lynis ==" | tee "$OUT/lynis.txt"
lynis audit system --quick --no-colors --profile /etc/lynis/profiles/vitos.prf \
    >> "$OUT/lynis.txt" 2>&1 || true

# Extract the hardening index — single number, easier to alert on
HI=$(awk '/Hardening index/ {print $4}' "$OUT/lynis.txt" | tail -1)
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"hardening_index\":${HI:-0}}" \
  > /var/log/vitos/hardening/latest.json

logger -t vitos-hardening "audit complete (hardening index ${HI:-?}, see $OUT)"
