#!/usr/bin/env bash
# Verifies vitos firstboot.sh creates the admin/student accounts with WORKING,
# NON-EXPIRED passwords. This is the regression guard for the lockout bug where
# `chage -d 0` force-expired the shipped defaults: the LightDM gtk-greeter cannot
# complete the PAM password-change flow, so the (correct) password was rejected
# at the greeter and pam_faillock (deny=5) then locked the account.
#
# Run in a Debian/Kali container (see .github/workflows/verify-firstboot.yml).
set -uo pipefail

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sqlite3 passwd login pamtester libpam-modules >/dev/null

SCRIPT="$(dirname "$0")/../packages/vitos-base/usr/lib/vitos/firstboot.sh"
echo "Running: $SCRIPT init"
bash "$SCRIPT" init

# 1. Accounts exist
id admin   >/dev/null 2>&1 && pass "admin account created"   || fail "admin account missing"
id student >/dev/null 2>&1 && pass "student account created" || fail "student account missing"

# 2. Group membership (admin = sudo, student = no sudo)
id -nG admin   | grep -qw sudo           && pass "admin in sudo group"          || fail "admin not in sudo group"
id -nG admin   | grep -qw vitos-admins   && pass "admin in vitos-admins"        || fail "admin not in vitos-admins"
id -nG student | grep -qw vitos-students && pass "student in vitos-students"    || fail "student not in vitos-students"
if id -nG student | grep -qw sudo; then fail "student must NOT have sudo"; else pass "student correctly has no sudo"; fi

# 3. Passwords are USABLE (passwd -S status field == P), not locked/empty
[ "$(passwd -S admin   | awk '{print $2}')" = "P" ] && pass "admin password is usable"   || fail "admin password not usable (locked/empty)"
[ "$(passwd -S student | awk '{print $2}')" = "P" ] && pass "student password is usable" || fail "student password not usable (locked/empty)"

# 4. THE REGRESSION: passwords must NOT be force-expired (no `chage -d 0`).
for u in admin student; do
  lc="$(chage -l "$u" | sed -n 's/^Last password change[[:space:]]*:[[:space:]]*//p')"
  if echo "$lc" | grep -qiE '1970|password must be changed'; then
    fail "$u is force-expired ($lc) — this is the LightDM lockout bug"
  else
    pass "$u not force-expired (last change: $lc)"
  fi
done

# 5. Passwords actually AUTHENTICATE through PAM, and the OLD default is gone.
auth() { echo "$2" | pamtester login "$1" authenticate >/dev/null 2>&1; }
auth admin   'VitosAdmin@2026'   && pass "admin authenticates with VitosAdmin@2026"     || fail "admin failed to authenticate"
auth student 'VitosStudent@2026' && pass "student authenticates with VitosStudent@2026" || fail "student failed to authenticate"
if auth admin 'changeme'; then fail "old 'changeme' password still works"; else pass "old 'changeme' password rejected"; fi

echo "----"
if [ "$FAIL" = "0" ]; then
  echo "ALL FIRSTBOOT USER CHECKS PASSED"; exit 0
else
  echo "FIRSTBOOT USER CHECKS FAILED"; exit 1
fi
