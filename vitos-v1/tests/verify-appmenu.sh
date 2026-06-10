#!/bin/sh
# VITOS application-menu + wallpaper verification.
#
# Validates the committed launcher/menu/wallpaper artifacts against the
# vitos-tools wrapped-tool list. Run inside kalilinux/kali-rolling. Runs every
# case, prints a summary, exits non-zero if ANY case fails so CI fails loudly.
# Does NOT build a package or an ISO — it inspects the source tree.

set -u

REPO_ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
TOOLS="$REPO_ROOT/vitos-v1/packages/vitos-tools"
APPS="$TOOLS/usr/share/applications"
DIRS="$TOOLS/usr/share/desktop-directories"
MENU="$TOOLS/etc/xdg/menus/applications-merged/vitos.menu"
LAUNCH="$TOOLS/usr/bin/vitos-launch-tool"
POSTINST="$TOOLS/debian/postinst"
INC="$REPO_ROOT/vitos-v1/live-build/config/includes.chroot"
XFCEDESK="$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
SETWP="$INC/usr/local/bin/vitos-set-wallpaper"
AUTOSTART="$INC/etc/xdg/autostart/vitos-wallpaper.desktop"
WP_PATH="/usr/share/vitos/branding/wallpaper.png"

FAILED=0
say()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; FAILED=$((FAILED+1)); }

say "Environment"
. /etc/os-release 2>/dev/null || true
echo "Distro: ${PRETTY_NAME:-unknown}"
for f in "$LAUNCH" "$MENU" "$POSTINST" "$XFCEDESK" "$SETWP" "$AUTOSTART"; do
    [ -f "$f" ] || { echo "required file missing: $f"; exit 2; }
done

say "Install validators"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq desktop-file-utils libxml2-utils >/dev/null
echo "installed."

# Canonical wrapped-tool list, parsed from vitos-tools/debian/postinst (single
# source of truth — catches drift between the tool list and the launchers).
TOOL_LIST=$(awk '/^TOOLS="/{c=1} c{buf=buf" "$0} c&&/"[[:space:]]*$/{print buf; exit}' "$POSTINST" \
            | tr '\\' ' ' | sed 's/.*TOOLS="//; s/".*//' | tr -s ' ')
echo "tools: $TOOL_LIST"

# ---------------------------------------------------------------------------
say "T1: every .desktop passes desktop-file-validate"
# desktop-file-validate exits non-zero on errors (warnings are exit 0).
for f in "$APPS"/vitos-*.desktop "$AUTOSTART"; do
    if desktop-file-validate "$f" >/tmp/dfv.out 2>&1; then
        pass "T1 valid: $(basename "$f")"
    else
        fail "T1 INVALID: $(basename "$f")"; cat /tmp/dfv.out
    fi
done

# ---------------------------------------------------------------------------
say "T2: every wrapped tool has exactly one Security launcher routed via the sandbox"
for t in $TOOL_LIST; do
    f="$APPS/vitos-$t.desktop"
    if [ ! -f "$f" ]; then fail "T2 missing launcher for tool '$t' (vitos-$t.desktop)"; continue; fi
    grep -q 'Categories=.*X-VITOS-Security' "$f" || { fail "T2 $t launcher lacks X-VITOS-Security"; continue; }
    if grep -Eq "^Exec=(/usr/local/bin/$t|vitos-launch-tool $t)( |$)" "$f"; then
        pass "T2 $t -> sandboxed launcher OK"
    else
        fail "T2 $t Exec bypasses the sandbox: $(grep '^Exec=' "$f")"
    fi
done

# ---------------------------------------------------------------------------
say "T3: no Security launcher references an unknown tool (reverse drift guard)"
for f in "$APPS"/vitos-*.desktop; do
    base=$(basename "$f" .desktop); t=${base#vitos-}
    case "$t" in ai-chat|dashboard) continue;; esac   # AI launchers are exempt
    grep -q 'Categories=.*X-VITOS-Security' "$f" || continue
    if printf ' %s ' "$TOOL_LIST" | grep -q " $t "; then
        pass "T3 $t is a known wrapped tool"
    else
        fail "T3 launcher '$base' references unknown tool '$t'"
    fi
done

# ---------------------------------------------------------------------------
say "T4: AI launchers exist, valid, categorized (exempt from sandbox/completeness)"
for n in ai-chat dashboard; do
    f="$APPS/vitos-$n.desktop"
    [ -f "$f" ] || { fail "T4 missing vitos-$n.desktop"; continue; }
    grep -q 'Categories=.*X-VITOS-AI' "$f" && pass "T4 vitos-$n in VITOS · AI" || fail "T4 vitos-$n lacks X-VITOS-AI"
done
grep -q 'Exec=vitos-launch-tool ollama --repl' "$APPS/vitos-ai-chat.desktop" \
    && pass "T4 ai-chat runs the Gemma 3 chat" || fail "T4 ai-chat Exec wrong"
grep -q 'Exec=xdg-open http://127.0.0.1:8443' "$APPS/vitos-dashboard.desktop" \
    && pass "T4 dashboard opens the local dashboard URL" || fail "T4 dashboard Exec wrong"

# ---------------------------------------------------------------------------
say "T5: menu merge is well-formed and references both category dirs"
if xmllint --noout "$MENU" 2>/tmp/xml.out; then pass "T5 vitos.menu is well-formed XML"; else fail "T5 vitos.menu malformed"; cat /tmp/xml.out; fi
grep -q 'vitos-security.directory' "$MENU" && pass "T5 menu references vitos-security.directory" || fail "T5 menu missing vitos-security.directory"
grep -q 'vitos-ai.directory' "$MENU" && pass "T5 menu references vitos-ai.directory" || fail "T5 menu missing vitos-ai.directory"
for d in vitos-security vitos-ai; do
    [ -f "$DIRS/$d.directory" ] && pass "T5 $d.directory present" || fail "T5 $d.directory missing"
done

# ---------------------------------------------------------------------------
say "T6: XFCE backdrop config points at the VITOS wallpaper"
if xmllint --noout "$XFCEDESK" 2>/tmp/xml2.out; then pass "T6 xfce4-desktop.xml well-formed"; else fail "T6 xfce4-desktop.xml malformed"; cat /tmp/xml2.out; fi
grep -q "$WP_PATH" "$XFCEDESK" && pass "T6 backdrop references $WP_PATH" || fail "T6 backdrop does not reference $WP_PATH"
grep -q "$WP_PATH" "$SETWP" && pass "T6 vitos-set-wallpaper targets $WP_PATH" || fail "T6 vitos-set-wallpaper wrong target"
sh -n "$SETWP" && pass "T6 vitos-set-wallpaper syntax OK" || fail "T6 vitos-set-wallpaper syntax error"

# ---------------------------------------------------------------------------
say "T7: vitos-launch-tool resolves the sandboxed/AI commands correctly"
sh -n "$LAUNCH" && pass "T7 vitos-launch-tool syntax OK" || fail "T7 vitos-launch-tool syntax error"
OUT=$(VITOS_LAUNCH_TEST=1 sh "$LAUNCH" nmap)
echo "$OUT" | grep -q 'RUN=/usr/local/bin/nmap' && pass "T7 nmap -> /usr/local/bin/nmap" || fail "T7 nmap resolve wrong: $OUT"
OUT=$(VITOS_LAUNCH_TEST=1 sh "$LAUNCH" msfconsole --repl)
echo "$OUT" | grep -q 'MODE=repl RUN=/usr/local/bin/msfconsole' && pass "T7 msfconsole repl OK" || fail "T7 msfconsole resolve wrong: $OUT"
OUT=$(VITOS_LAUNCH_TEST=1 sh "$LAUNCH" ollama --repl)
echo "$OUT" | grep -q 'RUN=ollama run vitos-intent' && pass "T7 ollama -> gemma chat OK" || fail "T7 ollama resolve wrong: $OUT"

# ---------------------------------------------------------------------------
say "SUMMARY"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32mALL CASES PASSED — app menu + wallpaper verified.\033[0m\n'
    exit 0
else
    printf '\033[1;31m%d CASE(S) FAILED.\033[0m\n' "$FAILED"
    exit 1
fi
