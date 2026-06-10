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
         "$INC/etc/motd" "$ABOUT_HTML" "$CREDITS" "$ABOUT_TSX" "$WEBSITE" \
         "$REPO_ROOT/vitos-v1/branding/build-branding.sh" \
         "$REPO_ROOT/vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script" \
         "$TOOLS/usr/bin/vitos-theme" \
         "$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"; do
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
# Component B — Look & Feel ---------------------------------------------------
BRANDING="$REPO_ROOT/vitos-v1/branding/build-branding.sh"
PLY_SCRIPT="$REPO_ROOT/vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script"
PLY_THEME="$REPO_ROOT/vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.plymouth"
THEME="$TOOLS/usr/bin/vitos-theme"
SKEL="$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
PKGLIST="$REPO_ROOT/vitos-v1/live-build/config/package-lists/vitos.list.chroot"

say "T7: build-branding.sh generates the variants + lock bg + Plymouth assets, with punchline"
bash -n "$BRANDING" && pass "T7 build-branding.sh syntax OK" || fail "T7 build-branding.sh syntax error"
for out in wallpaper.png wallpaper-matrix.png wallpaper-stealth.png lock-background.png; do
    grep -q "/$out\"" "$BRANDING" && pass "T7 emits $out" || fail "T7 build-branding.sh missing $out"
done
for out in progress-box.png progress-bar.png scanline.png; do
    grep -q "/$out\"" "$BRANDING" && pass "T7 emits $out" || fail "T7 build-branding.sh missing $out"
done
PC=$(grep -c 'Designed at VIT Bhopal for VITians' "$BRANDING")
[ "$PC" -ge 4 ] && pass "T7 punchline stamped $PC times" || fail "T7 punchline only $PC (<4) in build-branding.sh"

say "T8: Plymouth theme is animated and references its assets"
grep -q 'ScriptFile=.*/vitos.script' "$PLY_THEME" && pass "T8 .plymouth references vitos.script" || fail "T8 .plymouth missing ScriptFile"
grep -q 'SetBootProgressFunction' "$PLY_SCRIPT" && pass "T8 boot-progress animation present" || fail "T8 no SetBootProgressFunction"
for img in splash.png progress-box.png progress-bar.png scanline.png; do
    grep -q "\"$img\"" "$PLY_SCRIPT" && pass "T8 script uses $img" || fail "T8 script missing $img"
done

say "T9: vitos-theme resolves all three presets"
sh -n "$THEME" && pass "T9 vitos-theme syntax OK" || fail "T9 vitos-theme syntax error"
for p in neon matrix stealth; do
    OUT=$(VITOS_THEME_TEST=1 sh "$THEME" "$p")
    echo "$OUT" | grep -q "PRESET=$p " && echo "$OUT" | grep -q "/usr/share/vitos/branding/wallpaper" \
        && pass "T9 $p -> $OUT" || fail "T9 $p resolve wrong: $OUT"
done

say "T10: theme launchers valid + menu references the Themes category"
for p in neon matrix stealth; do
    f="$APPS/vitos-theme-$p.desktop"
    if desktop-file-validate "$f" >/tmp/dfv.out 2>&1; then pass "T10 valid: $(basename "$f")";
    else fail "T10 INVALID: $(basename "$f")"; cat /tmp/dfv.out; fi
    grep -q 'Categories=.*X-VITOS-Theme' "$f" && pass "T10 $(basename "$f") in Theme category" || fail "T10 $(basename "$f") lacks X-VITOS-Theme"
done
grep -q 'vitos-themes.directory' "$MENU" && pass "T10 menu references vitos-themes.directory" || fail "T10 menu missing vitos-themes.directory"
[ -f "$DIRS/vitos-themes.directory" ] && pass "T10 vitos-themes.directory present" || fail "T10 vitos-themes.directory missing"

say "T11: /etc/skel desktop defaults are well-formed + screensaver packaged"
for x in xsettings xfwm4 xfce4-screensaver; do
    if xmllint --noout "$SKEL/$x.xml" 2>/tmp/xml.out; then pass "T11 $x.xml well-formed"; else fail "T11 $x.xml malformed"; cat /tmp/xml.out; fi
done
grep -q 'Arc-Dark' "$SKEL/xsettings.xml" && pass "T11 default GTK theme set" || fail "T11 default GTK theme missing"
grep -q 'use_compositing' "$SKEL/xfwm4.xml" && pass "T11 compositor enabled" || fail "T11 compositor not enabled"
for p in arc-theme papirus-icon-theme xfce4-screensaver; do
    grep -qx "$p" "$PKGLIST" && pass "T11 package listed: $p" || fail "T11 package missing: $p"
done

# ---------------------------------------------------------------------------
say "SUMMARY"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32mALL CASES PASSED — identity + credits verified.\033[0m\n'
    exit 0
else
    printf '\033[1;31m%d CASE(S) FAILED.\033[0m\n' "$FAILED"
    exit 1
fi
