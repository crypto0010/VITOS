#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(dirname "$0")/../usr/sbin/vitos-run"

out=$(STUDENT_ID=test123 VITOS_DRYRUN=1 "$SCRIPT" nmap -V)
echo "$out" | grep -q '"student_id":"test123"' || { echo "FAIL: missing student_id"; exit 1; }
echo "$out" | grep -q '"tool":"nmap"' || { echo "FAIL: missing tool"; exit 1; }
echo "$out" | grep -q '"argv":\["nmap","-V"\]' || { echo "FAIL: missing argv"; exit 1; }
echo "OK"
