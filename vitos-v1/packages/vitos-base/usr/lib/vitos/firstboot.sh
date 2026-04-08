#!/usr/bin/env bash
# /usr/lib/vitos/firstboot.sh
set -euo pipefail

ACTION="${1:-init}"
STATE_DIR="/var/lib/vitos"
DB="${STATE_DIR}/consent.db"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

ensure_db() {
  if [ ! -f "$DB" ]; then
    sqlite3 "$DB" "CREATE TABLE consent (user TEXT PRIMARY KEY, ts TEXT NOT NULL);"
    chmod 600 "$DB"
  fi
}

case "$ACTION" in
  init)
    ensure_db
    getent group vitos-admins   >/dev/null || groupadd --system vitos-admins
    getent group vitos-students >/dev/null || groupadd --system vitos-students
    if ! id admin &>/dev/null; then
      useradd -m -s /bin/bash -G vitos-admins,sudo admin
      echo 'admin:changeme' | chpasswd
      chage -d 0 admin
    fi
    if ! id student &>/dev/null; then
      useradd -m -s /bin/bash -G vitos-students student
      echo 'student:changeme' | chpasswd
      chage -d 0 student
    fi
    ;;
  consent)
    ensure_db
    user="${PAM_USER:-$(id -un)}"
    if [ "$(sqlite3 "$DB" "SELECT 1 FROM consent WHERE user='${user}';")" = "1" ]; then
      exit 0
    fi
    if [ "${VITOS_CONSENT_PREACCEPTED:-}" = "1" ] || grep -q 'vitos.consent=preaccepted' /proc/cmdline; then
      sqlite3 "$DB" "INSERT INTO consent VALUES('${user}', datetime('now'));"
      exit 0
    fi
    cat /usr/lib/vitos/login-banner
    read -r -p "> " reply
    if [ "$reply" = "I AGREE" ]; then
      sqlite3 "$DB" "INSERT INTO consent VALUES('${user}', datetime('now'));"
      exit 0
    fi
    echo "Consent not granted. Logging out."
    exit 1
    ;;
  selftest)
    say() { echo "VITOS-SELFTEST: $1"; }
    uname -a | grep -q 'vitos' && say "uname=PASS" || say "uname=FAIL"
    zgrep -q '^CONFIG_BPF_SYSCALL=y' /proc/config.gz && say "bpf=PASS" || say "bpf=FAIL"
    getent group vitos-students >/dev/null && say "group_students=PASS" || say "group_students=FAIL"
    getent group vitos-admins   >/dev/null && say "group_admins=PASS"   || say "group_admins=FAIL"
    sudo -l -U student 2>/dev/null | grep -q 'not allowed' && say "student_no_sudo=PASS" || say "student_no_sudo=FAIL"
    systemctl is-active --quiet auditd && say "auditd=PASS" || say "auditd=FAIL"
    awk '/Mem:/ {if ($3 < 2048) print "VITOS-SELFTEST: idle_ram=PASS"; else print "VITOS-SELFTEST: idle_ram=FAIL"}' < <(free -m)
    cat /usr/lib/vitos/login-banner | head -1
    for u in vitos-busd vitos-bpf-exec vitos-bpf-net vitos-shell-tap vitos-udev-tap vitos-fanotify-tap ollama vitos-ai vitos-dashboard; do
      systemctl is-active --quiet "$u" && say "$u=PASS" || say "$u=FAIL"
    done
    curl -sf http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q vitos-intent && say "ollama_model=PASS" || say "ollama_model=FAIL"
    [ -f /build/recon.jsonl ] && socat -u FILE:/build/recon.jsonl UNIX-CONNECT:/run/vitos/bus.sock 2>/dev/null || true
    sleep 6
    [ -s /var/log/vitos/alerts.jsonl ] && say "alert_pipeline=PASS" || say "alert_pipeline=FAIL"

    # SP5 dashboard assertions
    DASH_BASE=http://127.0.0.1:8443
    curl -sf "$DASH_BASE/api/health" 2>/dev/null | grep -q '"ok":true' \
      && say "dashboard_health=PASS" || say "dashboard_health=FAIL"
    curl -sf -o /dev/null -w '%{http_code}' "$DASH_BASE/" 2>/dev/null | grep -q '^200$' \
      && say "dashboard_index=PASS" || say "dashboard_index=FAIL"
    # /api/auth/me without cookie should return 401
    code=$(curl -s -o /dev/null -w '%{http_code}' "$DASH_BASE/api/auth/me" 2>/dev/null)
    [ "$code" = "401" ] && say "dashboard_auth_required=PASS" || say "dashboard_auth_required=FAIL"
    # SSE alerts heartbeat without cookie -> 401 (auth-gated)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$DASH_BASE/api/stream/alerts" 2>/dev/null)
    [ "$code" = "401" ] && say "dashboard_sse_gated=PASS" || say "dashboard_sse_gated=FAIL"

    say "DONE"
    ;;
esac
