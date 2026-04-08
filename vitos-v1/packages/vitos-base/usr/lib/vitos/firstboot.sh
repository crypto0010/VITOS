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

    # SP6 Track 6A — Ghost Mode assertions
    getent group vitos-ghost-approvers >/dev/null \
      && say "ghost_approver_group=PASS" || say "ghost_approver_group=FAIL"
    [ -d /var/lib/vitos/ghost/pending ] && [ -d /var/lib/vitos/ghost/active ] \
      && say "ghost_state_dirs=PASS" || say "ghost_state_dirs=FAIL"
    [ -x /usr/lib/vitos/ghost/launch.sh ] && [ -x /usr/lib/vitos/ghost/killswitch-watchdog.sh ] \
      && say "ghost_scripts=PASS" || say "ghost_scripts=FAIL"
    [ -f /etc/nftables.d/vitos-ghost.nft ] \
      && say "ghost_killswitch_ruleset=PASS" || say "ghost_killswitch_ruleset=FAIL"
    # default state must be: no active ghost netns
    ip netns list 2>/dev/null | grep -q '^ghost-' && say "ghost_off_by_default=FAIL" || say "ghost_off_by_default=PASS"
    # vitosctl ghost subcommand exists
    vitosctl ghost --help >/dev/null 2>&1 && say "ghost_cli=PASS" || say "ghost_cli=FAIL"

    # SP6 Track 6B — FreeIPA SSO (fail-soft: package present, join optional)
    [ -x /usr/lib/vitos/sso/join.sh ] && say "sso_join_script=PASS" || say "sso_join_script=FAIL"
    [ -x /usr/lib/vitos/sso/purge-defaults.sh ] && say "sso_purge_script=PASS" || say "sso_purge_script=FAIL"
    [ -f /etc/vitos/sso.toml.example ] && say "sso_example_config=PASS" || say "sso_example_config=FAIL"

    # SP6 Track 6C — Hardening
    [ -f /etc/lynis/profiles/vitos.prf ] && say "hardening_lynis_profile=PASS" || say "hardening_lynis_profile=FAIL"
    [ -f /etc/cron.d/vitos-hardening ] && say "hardening_cron=PASS" || say "hardening_cron=FAIL"
    [ -x /usr/lib/vitos/hardening/run-audit.sh ] && say "hardening_runner=PASS" || say "hardening_runner=FAIL"

    # SP6 Track 6D — VIT pilot
    [ -f /etc/cron.d/vitos-retention ] && say "pilot_retention_cron=PASS" || say "pilot_retention_cron=FAIL"
    [ -f /etc/vitos/retention.toml ] && say "pilot_retention_config=PASS" || say "pilot_retention_config=FAIL"
    nscopes=$(ls /etc/vitos/lab-scopes/*.yaml 2>/dev/null | wc -l)
    [ "$nscopes" -ge 8 ] && say "pilot_lab_scopes=PASS" || say "pilot_lab_scopes=FAIL"
    grep -q 'vitos-bhopal-lab3' /etc/hostname 2>/dev/null && say "pilot_hostname=PASS" || say "pilot_hostname=FAIL"

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
