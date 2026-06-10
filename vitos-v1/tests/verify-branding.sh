#!/bin/sh
# VITOS branding/identity/credits verification.
#
# Validates the committed identity files (os-release/lsb-release/issue/motd),
# the dashboard About rebrand, and the GUI/terminal credits — including a drift
# guard that every team name on the website appears in both credits surfaces.
# Run inside kalilinux/kali-rolling. Runs every case, prints a summary, exits
# non-zero if ANY case fails. Inspects the source tree; no package/ISO build.

set -u

REPO_ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
INC="$REPO_ROOT/vitos-v1/live-build/config/includes.chroot"
TOOLS="$REPO_ROOT/vitos-v1/packages/vitos-tools"
APPS="$TOOLS/usr/share/applications"
DIRS="$TOOLS/usr/share/desktop-directories"
MENU="$TOOLS/etc/xdg/menus/applications-merged/vitos.menu"
ABOUT_HTML="$TOOLS/usr/share/vitos/about/vitos-about.html"
CREDITS="$TOOLS/usr/bin/vitos-credits"
ABOUT_TSX="$REPO_ROOT/vitos-v1/packages/vitos-dashboard/web/src/pages/About.tsx"
WEBSITE="$REPO_ROOT/website/index.html"
PUNCHLINE="Designed at VIT Bhopal for VITians"
THANKS="Kadhambari S. Viswanathan"

FAILED=0
say()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=$((FAILED+1)); }

say "Environment"
. /etc/os-release 2>/dev/null || true
echo "Distro: ${PRETTY_NAME:-unknown}"
for f in "$INC/usr/lib/os-release" "$INC/etc/lsb-release" "$INC/etc/issue" \
         "$INC/etc/motd" "$ABOUT_HTML" "$CREDITS" "$ABOUT_TSX" "$WEBSITE"; do
    [ -f "$f" ] || { echo "required file missing: $f"; exit 2; }
done

say "Install validators"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq desktop-file-utils libxml2-utils >/dev/null
echo "installed."

# ---------------------------------------------------------------------------
say "T1: os-release parses, ID=vitos, identity present, no Kali"
( . "$INC/usr/lib/os-release"
  [ "$ID" = vitos ] && echo "ID=$ID" || { echo "BAD ID=$ID"; exit 1; }
  echo "$PRETTY_NAME" | grep -q VITOS || { echo "PRETTY_NAME missing VITOS"; exit 1; }
) && pass "T1 os-release ID=vitos + VITOS pretty name" || fail "T1 os-release parse/ID wrong"
diff "$INC/usr/lib/os-release" "$INC/etc/os-release" >/dev/null \
  && pass "T1 /etc and /usr/lib os-release identical" || fail "T1 os-release copies differ"

# ---------------------------------------------------------------------------
say "T2: no case-insensitive 'kali' in any identity/version surface"
for f in "$INC/usr/lib/os-release" "$INC/etc/os-release" "$INC/etc/lsb-release" \
         "$INC/etc/issue" "$INC/etc/issue.net" "$INC/etc/motd" "$ABOUT_TSX"; do
    if grep -qi kali "$f"; then fail "T2 'kali' found in $(basename "$f")"; grep -in kali "$f";
    else pass "T2 clean: $(basename "$f")"; fi
done

# ---------------------------------------------------------------------------
say "T3: identity line + punchline present where required"
LINE="Cybersecurity and Digital Forensics Lab"
for f in "$INC/etc/issue" "$INC/etc/issue.net" "$INC/etc/motd"; do
    grep -q "$LINE" "$f" && pass "T3 identity line in $(basename "$f")" || fail "T3 identity line missing in $(basename "$f")"
    grep -q "$PUNCHLINE" "$f" && pass "T3 punchline in $(basename "$f")" || fail "T3 punchline missing in $(basename "$f")"
done
for f in "$ABOUT_HTML" "$CREDITS" "$ABOUT_TSX"; do
    grep -q "$PUNCHLINE" "$f" && pass "T3 punchline in $(basename "$f")" || fail "T3 punchline missing in $(basename "$f")"
done

# ---------------------------------------------------------------------------
say "T4: Special Thanks present in both credits surfaces"
for f in "$ABOUT_HTML" "$CREDITS"; do
    grep -q "$THANKS" "$f" && pass "T4 thanks in $(basename "$f")" || fail "T4 thanks missing in $(basename "$f")"
done

# ---------------------------------------------------------------------------
say "T5: credits drift guard — every website team name in BOTH surfaces"
NAMES=$(grep -oE '<div class="(leader-name|team-member)">[^<]+</div>' "$WEBSITE" \
        | sed -E 's/<[^>]+>//g')
echo "$NAMES" | while IFS= read -r n; do
    [ -n "$n" ] || continue
    if grep -qF "$n" "$ABOUT_HTML" && grep -qF "$n" "$CREDITS"; then
        pass "T5 '$n' in both"
    else
        fail "T5 '$n' MISSING (html=$(grep -qF "$n" "$ABOUT_HTML" && echo y || echo n) credits=$(grep -qF "$n" "$CREDITS" && echo y || echo n))"
    fi
done
# Propagate failures out of the subshell pipe: re-count in-process.
MISS=0
for n in $(grep -oE '<div class="(leader-name|team-member)">[^<]+</div>' "$WEBSITE" | sed -E 's/<[^>]+>//g; s/ /\x01/g'); do
    name=$(printf '%s' "$n" | tr '\001' ' ')
    grep -qF "$name" "$ABOUT_HTML" && grep -qF "$name" "$CREDITS" || MISS=$((MISS+1))
done
[ "$MISS" -eq 0 ] && pass "T5 all website names present in both surfaces" || fail "T5 $MISS website name(s) missing"

# ---------------------------------------------------------------------------
say "T6: credits launchers valid + menu references the About category"
chmod +x "$CREDITS" 2>/dev/null || true
sh -n "$CREDITS" && pass "T6 vitos-credits syntax OK" || fail "T6 vitos-credits syntax error"
for f in "$APPS/vitos-about.desktop" "$APPS/vitos-credits.desktop"; do
    if desktop-file-validate "$f" >/tmp/dfv.out 2>&1; then pass "T6 valid: $(basename "$f")";
    else fail "T6 INVALID: $(basename "$f")"; cat /tmp/dfv.out; fi
    grep -q 'Categories=.*X-VITOS-About' "$f" && pass "T6 $(basename "$f") in About category" || fail "T6 $(basename "$f") lacks X-VITOS-About"
done
xmllint --noout "$MENU" 2>/tmp/xml.out && pass "T6 vitos.menu well-formed" || { fail "T6 vitos.menu malformed"; cat /tmp/xml.out; }
grep -q 'vitos-about.directory' "$MENU" && pass "T6 menu references vitos-about.directory" || fail "T6 menu missing vitos-about.directory"
[ -f "$DIRS/vitos-about.directory" ] && pass "T6 vitos-about.directory present" || fail "T6 vitos-about.directory missing"

# ---------------------------------------------------------------------------
say "SUMMARY"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32mALL CASES PASSED — identity + credits verified.\033[0m\n'
    exit 0
else
    printf '\033[1;31m%d CASE(S) FAILED.\033[0m\n' "$FAILED"
    exit 1
fi
