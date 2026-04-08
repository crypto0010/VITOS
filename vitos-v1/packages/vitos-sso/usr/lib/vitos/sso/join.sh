#!/usr/bin/env bash
# /usr/lib/vitos/sso/join.sh — joins a VITOS workstation to a FreeIPA realm
# and rewires PAM/SSSD. Reads /etc/vitos/sso.toml for configuration. The
# admin password is expected at /etc/vitos/sso.password (mode 0600); the
# file is wiped on success.
set -euo pipefail

CFG=/etc/vitos/sso.toml
PWFILE=/etc/vitos/sso.password
[ -f "$CFG" ] || { echo "no $CFG — refusing join"; exit 0; }

# Tiny TOML reader (handles flat key = "value" lines under [ipa])
toml_get() {
  awk -v section="$1" -v key="$2" '
    /^\[/ { in_sec = ($0 == "["section"]") }
    in_sec && $1 == key { gsub(/"/,"",$3); print $3; exit }
  ' "$CFG"
}

REALM=$(toml_get ipa realm)
DOMAIN=$(toml_get ipa domain)
SERVER=$(toml_get ipa server)
ADMIN=$(toml_get ipa admin)
PURGE=$(awk '/^\[purge_defaults\]/{p=1} p && $1=="enabled"{print $3; exit}' "$CFG" \
        | tr -d '"')

[ -n "$REALM" ] && [ -n "$DOMAIN" ] && [ -n "$SERVER" ] && [ -n "$ADMIN" ] || {
  echo "vitos-sso: $CFG missing required ipa.* fields"; exit 2; }
[ -f "$PWFILE" ] || { echo "vitos-sso: $PWFILE not found"; exit 3; }

logger -t vitos-sso "joining IPA realm $REALM via $SERVER"

ipa-client-install --unattended \
  --realm="$REALM" --domain="$DOMAIN" --server="$SERVER" \
  --principal="$ADMIN" --password="$(cat "$PWFILE")" \
  --mkhomedir --no-ntp --force-join

# Wipe the password file on success
shred -u "$PWFILE" 2>/dev/null || rm -f "$PWFILE"

# pam_sss is automatically inserted by ipa-client-install on Debian, but
# we make sure pam_faillock from vitos-base still runs first.
if ! grep -q 'pam_sss.so' /etc/pam.d/common-auth; then
  echo "auth sufficient pam_sss.so forward_pass" >> /etc/pam.d/common-auth
fi

systemctl restart sssd

# Optionally purge the v1 hardcoded accounts
if [ "${PURGE:-true}" = "true" ]; then
  /usr/lib/vitos/sso/purge-defaults.sh || true
fi

# Restart the dashboard so it picks up the new auth backend
systemctl restart vitos-dashboard 2>/dev/null || true

logger -t vitos-sso "join complete"
