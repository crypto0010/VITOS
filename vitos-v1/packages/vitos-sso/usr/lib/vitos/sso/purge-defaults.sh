#!/usr/bin/env bash
# /usr/lib/vitos/sso/purge-defaults.sh — delete the v1 'admin' and 'student'
# hardcoded accounts after a successful FreeIPA join. Home directories are
# moved to /var/lib/vitos/legacy-homes/<user>-<timestamp>/ rather than
# destroyed, so a faculty member can recover any work done before the join.
set -euo pipefail

ARCHIVE_BASE=/var/lib/vitos/legacy-homes
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$ARCHIVE_BASE"
chmod 0700 "$ARCHIVE_BASE"

for u in admin student; do
  if id "$u" &>/dev/null; then
    HOME_DIR=$(getent passwd "$u" | cut -d: -f6)
    if [ -d "$HOME_DIR" ]; then
      mv "$HOME_DIR" "$ARCHIVE_BASE/${u}-${TS}"
      logger -t vitos-sso "archived $u home -> $ARCHIVE_BASE/${u}-${TS}"
    fi
    pkill -KILL -u "$u" 2>/dev/null || true
    userdel "$u" || true
    logger -t vitos-sso "purged default account $u"
  fi
done
