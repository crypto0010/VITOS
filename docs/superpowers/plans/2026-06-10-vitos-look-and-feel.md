# VITOS Look & Feel (PR B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give VITOS a switchable cyber look (3 themes), an animated Plymouth boot, a compositor-enabled desktop, and a branded sleep/lock screen — all carrying the punchline.

**Architecture:** `build-branding.sh` generates three wallpaper variants (+ a lock background + Plymouth animation assets), all stamped with the punchline. A `vitos-theme` switcher applies a named preset (GTK + icon + xfwm4 theme + wallpaper) via `xfconf-query`; three launchers sit under a **VITOS · Themes** menu category. `/etc/skel` XFCE config sets the default theme, enables the compositor, and configures `xfce4-screensaver` (lock on idle/suspend). The existing scripted Plymouth theme gains a progress bar, sweeping scanline, and animated tagline. A new section of `verify-branding.sh` validates it all in the Kali CI container; no ISO build.

**Tech Stack:** POSIX sh, ImageMagick (`convert`), Plymouth `script` module, XFCE `xfconf` XML, freedesktop `.desktop`/`.directory`, Debian packaging, GitHub Actions (Kali container).

**Branch:** `feat/vitos-look-and-feel` (create off `feat/vitos-identity-credits`). PR B base = `feat/vitos-identity-credits` (stacked on PR #9).

**Reference spec:** `docs/superpowers/specs/2026-06-10-vitos-branding-identity-ai-design.md` (Component B).

**TDD adaptation:** Static-asset/packaging/theming feature with no runnable unit on the dev host (Windows; visual rendering only on Linux/hardware). Each task carries the strongest *locally runnable* check (`bash -n`, `sh -n`, XML parse, `grep`). The authoritative gate is `verify-branding.sh` (Task 7) green in the Kali CI container (Task 8); final visual confirmation is on hardware after a (user-prompted) ISO build.

**Graceful-degradation note (firejail lesson):** the theme/icon packages are added to the package list, and `vitos-theme` only *sets xfconf string values* — if a theme package is ever absent, XFCE silently falls back to a default theme rather than breaking. Nothing in this plan can abort the desktop.

---

## File Structure

Branding assets:
- Modify `vitos-v1/branding/build-branding.sh` — wallpaper variants, lock bg, Plymouth assets, punchline.

Plymouth:
- Modify `vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script` — animation.

Themes (package `vitos-tools`):
- Create `vitos-v1/packages/vitos-tools/usr/bin/vitos-theme`
- Create `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-neon.desktop`
- Create `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-matrix.desktop`
- Create `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-stealth.desktop`
- Create `vitos-v1/packages/vitos-tools/usr/share/desktop-directories/vitos-themes.directory`
- Modify `vitos-v1/packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu`
- Modify `vitos-v1/packages/vitos-tools/debian/install`

Desktop defaults (`includes.chroot` /etc/skel):
- Create `…/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`
- Create `…/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`
- Create `…/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml`

Packages:
- Modify `vitos-v1/live-build/config/package-lists/vitos.list.chroot`

Verification:
- Modify `vitos-v1/tests/verify-branding.sh` (append Component-B section)
- Modify `.github/workflows/verify-branding.yml` (add B paths)

---

### Task 1: Branding assets — wallpaper variants, lock bg, Plymouth assets, punchline

**Files:**
- Modify: `vitos-v1/branding/build-branding.sh`

- [ ] **Step 1: Add the punchline to the LightDM greeter background**

Replace this block (lines 20-22):

```bash
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 36 \
  -annotate +0+120 'VITOS — Developed by Dr. Hemraj, VIT Bhopal' \
  "$OUT_BASE/lightdm-background.png"
```

with:

```bash
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 36 \
  -annotate +0+150 'VITOS — Developed by Dr. Hemraj, VIT Bhopal' \
  -gravity south -fill '#9aa4d6' -font DejaVu-Sans -pointsize 24 \
  -annotate +0+100 'Designed at VIT Bhopal for VITians' \
  "$OUT_BASE/lightdm-background.png"
```

- [ ] **Step 2: Replace the single wallpaper with three punchline variants**

Replace the entire block 1b (lines 24-33):

```bash
# 1b. XFCE desktop wallpaper — 1920x1080 (VIT logo on the VITOS gradient).
#     Installed via vitos-base to /usr/share/vitos/branding/wallpaper.png and
#     referenced by the /etc/skel XFCE backdrop config + vitos-set-wallpaper.
convert -size 1920x1080 \
  gradient:"$BG"-"#1a1f4a" \
  \( "$SRC" -resize 560x -background none -gravity center -extent 560x \) \
  -gravity center -composite \
  -gravity south -fill "#9aa4d6" -font DejaVu-Sans -pointsize 26 \
  -annotate +0+90 'VITOS — VIT Bhopal University' \
  "$OUT_BASE/wallpaper.png"
```

with:

```bash
# 1b. XFCE desktop wallpapers — 3 VITOS theme variants (Neon / Matrix / Stealth),
#     each stamped with the punchline. Installed via vitos-base to
#     /usr/share/vitos/branding/ and applied by vitos-theme + the /etc/skel
#     backdrop config. wallpaper.png is the default (Neon) variant.
gen_wallpaper() {  # $1=outfile  $2=gradient-top  $3=gradient-bottom  $4=accent
  convert -size 1920x1080 \
    gradient:"$2"-"$3" \
    \( "$SRC" -resize 560x -background none -gravity center -extent 560x \) \
    -gravity center -composite \
    -gravity south -fill "$4" -font DejaVu-Sans-Bold -pointsize 30 \
    -annotate +0+140 'VITOS — VIT Bhopal' \
    -gravity south -fill "$4" -font DejaVu-Sans -pointsize 22 \
    -annotate +0+95 'Designed at VIT Bhopal for VITians' \
    "$1"
}
gen_wallpaper "$OUT_BASE/wallpaper.png"         "#0a0e2a" "#1a1f4a" "#00f5ff"
gen_wallpaper "$OUT_BASE/wallpaper-matrix.png"  "#001a00" "#003300" "#16ff8e"
gen_wallpaper "$OUT_BASE/wallpaper-stealth.png" "#05060a" "#0b0d14" "#9aa4d6"

# 1c. Lock screen background (used by xfce4-screensaver) — logo + punchline.
convert -size 1920x1080 \
  gradient:"#0a0e2a"-"#05060a" \
  \( "$SRC" -resize 440x -background none -gravity center -extent 440x \) \
  -gravity center -composite \
  -gravity south -fill "#00f5ff" -font DejaVu-Sans-Bold -pointsize 26 \
  -annotate +0+130 'VITOS — locked' \
  -gravity south -fill "#9aa4d6" -font DejaVu-Sans -pointsize 20 \
  -annotate +0+90 'Designed at VIT Bhopal for VITians' \
  "$OUT_BASE/lock-background.png"

# 1d. Plymouth animation assets — progress bar (box + fill) and a scanline.
convert -size 420x6  xc:"#11163a" "$OUT_PLY/progress-box.png"
convert -size 420x6  xc:"#00f5ff" "$OUT_PLY/progress-bar.png"
convert -size 1920x2 xc:"rgba(0,245,255,0.18)" "$OUT_PLY/scanline.png"
```

- [ ] **Step 3: Add the punchline to the Plymouth splash**

Replace this block (lines 39-41):

```bash
  -gravity south -fill "$FG" -font DejaVu-Sans -pointsize 28 \
  -annotate +0+200 'VITOS — Developed by Dr. Hemraj' \
  "$OUT_PLY/splash.png"
```

with:

```bash
  -gravity south -fill "$FG" -font DejaVu-Sans -pointsize 28 \
  -annotate +0+240 'VITOS — Developed by Dr. Hemraj' \
  -gravity south -fill '#9aa4d6' -font DejaVu-Sans -pointsize 20 \
  -annotate +0+200 'Designed at VIT Bhopal for VITians' \
  "$OUT_PLY/splash.png"
```

- [ ] **Step 4: Syntax-check + assert the new outputs/punchline are present**

```bash
cd /c/Users/HP/Documents/VITOS
B=vitos-v1/branding/build-branding.sh
bash -n "$B" && echo "BRANDING SYNTAX OK"
grep -c 'Designed at VIT Bhopal for VITians' "$B"   # expect 4 (greeter, wallpaper fn, lock, splash)
for out in wallpaper.png wallpaper-matrix.png wallpaper-stealth.png lock-background.png; do
  grep -q "\$OUT_BASE/$out" "$B" && echo "emits $out" || echo "MISSING emit: $out"
done
for out in progress-box.png progress-bar.png scanline.png; do
  grep -q "\$OUT_PLY/$out" "$B" && echo "emits $out" || echo "MISSING emit: $out"
done
```
Expected: `BRANDING SYNTAX OK`, `4`, and `emits …` for all seven assets.

- [ ] **Step 5: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/branding/build-branding.sh
git commit -m "feat(branding): 3 wallpaper variants, lock bg, Plymouth assets, punchline

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Animate the Plymouth boot script

**Files:**
- Modify: `vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script` (full rewrite)

- [ ] **Step 1: Replace `vitos.script` with the animated version**

Overwrite the file with EXACTLY:

```
Window.SetBackgroundTopColor(0.039, 0.055, 0.165);
Window.SetBackgroundBottomColor(0.020, 0.024, 0.055);

logo.image  = Image("splash.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth()/2  - logo.image.GetWidth()/2);
logo.sprite.SetY(Window.GetHeight()/2 - logo.image.GetHeight()/2);

# Boot progress bar (static box + scaled fill), centered near the bottom.
box.image = Image("progress-box.png");
bar.image = Image("progress-bar.png");
box.sprite = Sprite(box.image);
bar.sprite = Sprite(bar.image);
bar_x = Window.GetWidth()/2 - box.image.GetWidth()/2;
bar_y = Window.GetHeight() * 0.80;
box.sprite.SetX(bar_x); box.sprite.SetY(bar_y);
bar.sprite.SetX(bar_x); bar.sprite.SetY(bar_y);
bar.sprite.SetOpacity(1);

# Sweeping cyber scanline.
scan.image  = Image("scanline.png");
scan.sprite = Sprite(scan.image);
scan.sprite.SetX(0);

# Pulsing tagline.
tag.image  = Image.Text("Designed at VIT Bhopal for VITians", 0.60, 0.95, 1.0);
tag.sprite = Sprite(tag.image);
tag.sprite.SetX(Window.GetWidth()/2 - tag.image.GetWidth()/2);
tag.sprite.SetY(Window.GetHeight() * 0.86);

tick = 0;
fun refresh_callback() {
  tick++;
  logo.sprite.SetOpacity(0.7 + 0.3 * Math.Sin(tick / 12));
  tag.sprite.SetOpacity(0.5 + 0.5 * Math.Sin(tick / 18));
  scan.sprite.SetY((tick * 6) % Window.GetHeight());
}
Plymouth.SetRefreshFunction(refresh_callback);

fun progress_callback(duration, progress) {
  w = box.image.GetWidth() * progress;
  if (w < 1) w = 1;
  bar.sprite.SetImage(bar.image.Scale(w, bar.image.GetHeight()));
}
Plymouth.SetBootProgressFunction(progress_callback);
```

- [ ] **Step 2: Verify the theme references + assets line up**

```bash
cd /c/Users/HP/Documents/VITOS
S=vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script
P=vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.plymouth
grep -q 'ScriptFile=.*/vitos.script' "$P" && echo "plymouth references script OK"
for img in splash.png progress-box.png progress-bar.png scanline.png; do
  grep -q "\"$img\"" "$S" && echo "script uses $img" || echo "MISSING use: $img"
done
grep -q 'SetBootProgressFunction' "$S" && echo "progress fn OK"
grep -q 'Designed at VIT Bhopal for VITians' "$S" && echo "tagline OK"
```
Expected: `plymouth references script OK`, `script uses …` for all four images, `progress fn OK`, `tagline OK`.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script
git commit -m "feat(plymouth): animated boot — progress bar, scanline, tagline

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `vitos-theme` switcher + launchers + category + menu

**Files:**
- Create: `vitos-v1/packages/vitos-tools/usr/bin/vitos-theme`
- Create: `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-neon.desktop`
- Create: `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-matrix.desktop`
- Create: `vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-stealth.desktop`
- Create: `vitos-v1/packages/vitos-tools/usr/share/desktop-directories/vitos-themes.directory`
- Modify: `vitos-v1/packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu`

- [ ] **Step 1: Write `vitos-theme`**

Create the file with EXACTLY:

```sh
#!/bin/sh
# vitos-theme <neon|matrix|stealth> — apply a VITOS look:
#   GTK theme + icon theme + xfwm4 theme + matching wallpaper, via xfconf-query.
# Shipped in vitos-tools; invoked by the VITOS · Themes launchers and runnable
# directly. If a named theme isn't installed, XFCE falls back to a default —
# this never breaks the desktop.
#
# Set VITOS_THEME_TEST=1 to print the resolved preset and exit 0 (CI hook).
set -u

PRESET="${1:-}"
case "$PRESET" in
  neon)    GTK="Arc-Dark";     ICONS="Papirus-Dark"; WM="Arc-Dark";     WP="wallpaper.png" ;;
  matrix)  GTK="Materia-dark"; ICONS="Papirus-Dark"; WM="Materia-dark"; WP="wallpaper-matrix.png" ;;
  stealth) GTK="Adwaita-dark"; ICONS="Papirus-Dark"; WM="Adwaita-dark"; WP="wallpaper-stealth.png" ;;
  ""|-h|--help) echo "usage: vitos-theme <neon|matrix|stealth>" >&2; exit 2 ;;
  *) echo "vitos-theme: unknown preset '$PRESET'" >&2; exit 2 ;;
esac
WPP="/usr/share/vitos/branding/$WP"

if [ "${VITOS_THEME_TEST:-0}" = "1" ]; then
    echo "PRESET=$PRESET GTK=$GTK ICONS=$ICONS WM=$WM WP=$WPP"
    exit 0
fi

command -v xfconf-query >/dev/null 2>&1 || { echo "xfconf-query not found" >&2; exit 1; }

set_str() {  # channel prop value
    xfconf-query -c "$1" -p "$2" -s "$3" 2>/dev/null \
      || xfconf-query -c "$1" -p "$2" -n -t string -s "$3" 2>/dev/null || true
}
set_str xsettings /Net/ThemeName     "$GTK"
set_str xsettings /Net/IconThemeName "$ICONS"
set_str xfwm4     /general/theme     "$WM"

# Apply the matching wallpaper to every existing backdrop.
xfconf-query -c xfce4-desktop -l 2>/dev/null \
  | grep -E '/backdrop/.*/last-image$' \
  | while read -r p; do xfconf-query -c xfce4-desktop -p "$p" -s "$WPP" 2>/dev/null || true; done

echo "Applied VITOS · $PRESET ($GTK / $ICONS)"
```

- [ ] **Step 2: chmod + syntax + the three test-hook resolutions**

```bash
cd /c/Users/HP/Documents/VITOS
F=vitos-v1/packages/vitos-tools/usr/bin/vitos-theme
chmod +x "$F"
sh -n "$F" && echo "SYNTAX OK"
VITOS_THEME_TEST=1 sh "$F" neon
VITOS_THEME_TEST=1 sh "$F" matrix
VITOS_THEME_TEST=1 sh "$F" stealth
```
Expected: `SYNTAX OK`, then:
```
PRESET=neon GTK=Arc-Dark ICONS=Papirus-Dark WM=Arc-Dark WP=/usr/share/vitos/branding/wallpaper.png
PRESET=matrix GTK=Materia-dark ICONS=Papirus-Dark WM=Materia-dark WP=/usr/share/vitos/branding/wallpaper-matrix.png
PRESET=stealth GTK=Adwaita-dark ICONS=Papirus-Dark WM=Adwaita-dark WP=/usr/share/vitos/branding/wallpaper-stealth.png
```

- [ ] **Step 3: Create the three launchers + the category directory**

```bash
cd /c/Users/HP/Documents/VITOS
APPS=vitos-v1/packages/vitos-tools/usr/share/applications
DIRS=vitos-v1/packages/vitos-tools/usr/share/desktop-directories
for p in neon matrix stealth; do
  case $p in neon) disp="Neon (cyan)";; matrix) disp="Matrix (green)";; stealth) disp="Stealth (dark)";; esac
  cat > "$APPS/vitos-theme-$p.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=VITOS Theme — $disp
Comment=Apply the VITOS $p look (theme, icons, wallpaper)
Exec=vitos-theme $p
Icon=preferences-desktop-theme
Terminal=false
Categories=X-VITOS-Theme;
Keywords=theme;appearance;vitos;$p;
EOF
done
cat > "$DIRS/vitos-themes.directory" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Directory
Name=VITOS · Themes
Comment=Switch the VITOS desktop look
Icon=preferences-desktop-theme
EOF
ls -1 "$APPS"/vitos-theme-*.desktop | wc -l   # expect 3
```
Expected: `3`

- [ ] **Step 4: Add the Themes submenu to `vitos.menu`**

Replace this closing fragment of `vitos-v1/packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu`:

```xml
  <!-- VITOS · About -->
  <Menu>
    <Name>VITOS About</Name>
    <Directory>vitos-about.directory</Directory>
    <Include>
      <And>
        <Category>X-VITOS-About</Category>
      </And>
    </Include>
  </Menu>
</Menu>
```

with:

```xml
  <!-- VITOS · About -->
  <Menu>
    <Name>VITOS About</Name>
    <Directory>vitos-about.directory</Directory>
    <Include>
      <And>
        <Category>X-VITOS-About</Category>
      </And>
    </Include>
  </Menu>

  <!-- VITOS · Themes -->
  <Menu>
    <Name>VITOS Themes</Name>
    <Directory>vitos-themes.directory</Directory>
    <Include>
      <And>
        <Category>X-VITOS-Theme</Category>
      </And>
    </Include>
  </Menu>
</Menu>
```

- [ ] **Step 5: Verify locally**

```bash
cd /c/Users/HP/Documents/VITOS
M=vitos-v1/packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu
python -c "import xml.dom.minidom; xml.dom.minidom.parse('$M'); print('MENU XML OK')" 2>/dev/null \
  || py -c "import xml.dom.minidom; xml.dom.minidom.parse('$M'); print('MENU XML OK')"
grep -q 'vitos-themes.directory' "$M" && echo "menu references themes dir OK"
grep -q 'Exec=vitos-theme matrix$' vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-matrix.desktop && echo "matrix exec OK"
```
Expected: `MENU XML OK`, `menu references themes dir OK`, `matrix exec OK`.

- [ ] **Step 6: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-tools/usr/bin/vitos-theme \
        vitos-v1/packages/vitos-tools/usr/share/applications/vitos-theme-*.desktop \
        vitos-v1/packages/vitos-tools/usr/share/desktop-directories/vitos-themes.directory \
        vitos-v1/packages/vitos-tools/etc/xdg/menus/applications-merged/vitos.menu
git commit -m "feat(themes): vitos-theme switcher + Neon/Matrix/Stealth launchers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Desktop defaults — theme, compositor, screensaver (/etc/skel)

**Files:**
- Create: `vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml`
- Create: `vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml`
- Create: `vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml`

- [ ] **Step 1: Create the three XML files**

```bash
cd /c/Users/HP/Documents/VITOS
SKEL=vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
mkdir -p "$SKEL"
cat > "$SKEL/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
</channel>
EOF
cat > "$SKEL/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="95"/>
    <property name="show_frame_shadow" type="bool" value="true"/>
  </property>
</channel>
EOF
cat > "$SKEL/xfce4-screensaver.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="true"/>
    <property name="idle-activation" type="empty">
      <property name="enabled" type="bool" value="true"/>
    </property>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="true"/>
    <property name="saver-activation" type="empty">
      <property name="enabled" type="bool" value="true"/>
    </property>
    <property name="sleep-activation" type="empty">
      <property name="enabled" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
echo "skel xml written"
```

- [ ] **Step 2: Verify all three are well-formed + reference the default theme**

```bash
cd /c/Users/HP/Documents/VITOS
SKEL=vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
for x in xsettings xfwm4 xfce4-screensaver; do
  python -c "import xml.dom.minidom; xml.dom.minidom.parse('$SKEL/$x.xml'); print('$x XML OK')" 2>/dev/null \
    || py -c "import xml.dom.minidom; xml.dom.minidom.parse('$SKEL/$x.xml'); print('$x XML OK')"
done
grep -q 'Arc-Dark' "$SKEL/xsettings.xml" && echo "default theme OK"
grep -q 'use_compositing' "$SKEL/xfwm4.xml" && echo "compositor OK"
```
Expected: `xsettings XML OK`, `xfwm4 XML OK`, `xfce4-screensaver XML OK`, `default theme OK`, `compositor OK`.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml \
        vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml \
        vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml
git commit -m "feat(desktop): default Arc-Dark theme, compositor, screensaver lock

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Install theme/icon/screensaver packages

**Files:**
- Modify: `vitos-v1/live-build/config/package-lists/vitos.list.chroot`

- [ ] **Step 1: Append the desktop-look packages**

Append to the end of `vitos-v1/live-build/config/package-lists/vitos.list.chroot`:

```
# Desktop look & feel (VITOS themes + screensaver lock). All standard
# Debian/Kali packages; vitos-theme degrades gracefully if any is absent.
arc-theme
materia-gtk-theme
papirus-icon-theme
xfce4-screensaver
xscreensaver-data-extra
```

- [ ] **Step 2: Verify the entries are present**

```bash
cd /c/Users/HP/Documents/VITOS
L=vitos-v1/live-build/config/package-lists/vitos.list.chroot
for p in arc-theme materia-gtk-theme papirus-icon-theme xfce4-screensaver xscreensaver-data-extra; do
  grep -qx "$p" "$L" && echo "listed: $p" || echo "MISSING: $p"
done
```
Expected: `listed:` for all five.

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/live-build/config/package-lists/vitos.list.chroot
git commit -m "build: add VITOS theme/icon packages + xfce4-screensaver

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Wire `vitos-theme` payload into the package

**Files:**
- Modify: `vitos-v1/packages/vitos-tools/debian/install`

- [ ] **Step 1: Append the install lines**

Append to `vitos-v1/packages/vitos-tools/debian/install`:

```
usr/bin/vitos-theme                                    usr/bin
usr/share/applications/vitos-theme-neon.desktop        usr/share/applications
usr/share/applications/vitos-theme-matrix.desktop      usr/share/applications
usr/share/applications/vitos-theme-stealth.desktop     usr/share/applications
usr/share/desktop-directories/vitos-themes.directory   usr/share/desktop-directories
```

- [ ] **Step 2: Sanity-check every install source exists**

```bash
cd /c/Users/HP/Documents/VITOS/vitos-v1/packages/vitos-tools
missing=0
while read -r src dest; do
    [ -n "$src" ] || continue
    case "$src" in \#*) continue;; esac
    if [ ! -e "$src" ]; then echo "MISSING: $src"; missing=$((missing+1)); fi
done < debian/install
echo "missing=$missing"
cd /c/Users/HP/Documents/VITOS
```
Expected: `missing=0`

- [ ] **Step 3: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/packages/vitos-tools/debian/install
git commit -m "build(tools): install vitos-theme switcher + theme launchers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Extend `verify-branding.sh` with the Look & Feel section

**Files:**
- Modify: `vitos-v1/tests/verify-branding.sh` (insert a new section before the `say "SUMMARY"` block)
- Modify: `.github/workflows/verify-branding.yml` (add B paths to the triggers)

- [ ] **Step 1: Insert the Component-B checks**

In `vitos-v1/tests/verify-branding.sh`, find this line:

```sh
# ---------------------------------------------------------------------------
say "SUMMARY"
```

and insert the following block IMMEDIATELY BEFORE it:

```sh
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

```

- [ ] **Step 2: Add the new required-file preflight entries**

In `verify-branding.sh`, find the preflight loop:

```sh
for f in "$INC/usr/lib/os-release" "$INC/etc/lsb-release" "$INC/etc/issue" \
         "$INC/etc/motd" "$ABOUT_HTML" "$CREDITS" "$ABOUT_TSX" "$WEBSITE"; do
    [ -f "$f" ] || { echo "required file missing: $f"; exit 2; }
done
```

and replace it with:

```sh
for f in "$INC/usr/lib/os-release" "$INC/etc/lsb-release" "$INC/etc/issue" \
         "$INC/etc/motd" "$ABOUT_HTML" "$CREDITS" "$ABOUT_TSX" "$WEBSITE" \
         "$REPO_ROOT/vitos-v1/branding/build-branding.sh" \
         "$REPO_ROOT/vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/vitos.script" \
         "$TOOLS/usr/bin/vitos-theme" \
         "$INC/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"; do
    [ -f "$f" ] || { echo "required file missing: $f"; exit 2; }
done
```

- [ ] **Step 3: Add B paths to the workflow triggers**

In `.github/workflows/verify-branding.yml`, find:

```yaml
      - "website/index.html"
      - "vitos-v1/tests/verify-branding.sh"
      - ".github/workflows/verify-branding.yml"
```

and replace with:

```yaml
      - "website/index.html"
      - "vitos-v1/branding/build-branding.sh"
      - "vitos-v1/packages/vitos-base/usr/share/plymouth/themes/vitos/**"
      - "vitos-v1/packages/vitos-tools/usr/bin/vitos-theme"
      - "vitos-v1/packages/vitos-tools/usr/share/desktop-directories/**"
      - "vitos-v1/live-build/config/includes.chroot/etc/skel/.config/xfce4/**"
      - "vitos-v1/live-build/config/package-lists/vitos.list.chroot"
      - "vitos-v1/tests/verify-branding.sh"
      - ".github/workflows/verify-branding.yml"
```

- [ ] **Step 4: Syntax-check + run host-runnable parts**

```bash
cd /c/Users/HP/Documents/VITOS
sh -n vitos-v1/tests/verify-branding.sh && echo "TEST SYNTAX OK"
bash -n vitos-v1/branding/build-branding.sh && echo "BRANDING SYNTAX OK"
VITOS_THEME_TEST=1 sh vitos-v1/packages/vitos-tools/usr/bin/vitos-theme neon
python -c "import yaml; yaml.safe_load(open('.github/workflows/verify-branding.yml')); print('YAML OK')" 2>/dev/null \
  || py -c "import yaml; yaml.safe_load(open('.github/workflows/verify-branding.yml')); print('YAML OK')" 2>/dev/null \
  || echo "(pyyaml unavailable)"
```
Expected: `TEST SYNTAX OK`, `BRANDING SYNTAX OK`, the neon resolution line, `YAML OK`.

- [ ] **Step 5: Commit**

```bash
cd /c/Users/HP/Documents/VITOS
git add vitos-v1/tests/verify-branding.sh .github/workflows/verify-branding.yml
git commit -m "test(branding): add Look & Feel checks (themes, Plymouth, lock)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Push, open PR B, confirm CI green (no ISO build)

- [ ] **Step 1: Push the branch**

```bash
cd /c/Users/HP/Documents/VITOS
git push -u origin feat/vitos-look-and-feel
```

- [ ] **Step 2: Open the PR (base = PR A branch — stacked)**

```bash
cd /c/Users/HP/Documents/VITOS
gh pr create --base feat/vitos-identity-credits --head feat/vitos-look-and-feel \
  --title "feat: VITOS look & feel — themes, animated boot, branded lock" \
  --body "Component B of docs/superpowers/specs/2026-06-10-vitos-branding-identity-ai-design.md. Adds 3 switchable VITOS themes (Neon/Matrix/Stealth) with a vitos-theme switcher + menu, an animated Plymouth boot (progress bar + scanline + tagline), the xfwm4 compositor, and a branded xfce4-screensaver lock — all carrying the punchline. Verified by verify-branding CI; no ISO build. Stacked on #9.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 3: Confirm verify-branding is green**

```bash
cd /c/Users/HP/Documents/VITOS
sleep 12
gh run list --workflow=verify-branding.yml --branch=feat/vitos-look-and-feel --limit 1 \
  --json databaseId,status,conclusion,headSha
gh run view <id> --log | grep -E "PASS|FAIL|ALL CASES PASSED|CASE\(S\) FAILED" | tail -80
```
Expected: every line `PASS`, final `ALL CASES PASSED — identity + credits verified.`, run `conclusion: success`.

- [ ] **Step 4: Report to the user.** Do NOT merge or build the ISO. Note PR B is stacked on #9. Then proceed to write Plan C (AI ask bar). Visual confirmation of themes/boot/lock is on hardware after the next build.

---

## Self-Review

**1. Spec coverage (Component B):**
- #5 switchable themes (3 presets + switcher + menu) → Tasks 3, 6; enforced by T9/T10. ✅
- #5 default cohesive look → Task 4 (xsettings/xfwm4). ✅
- #5 animations: animated boot → Task 2 (Plymouth); compositor → Task 4; enforced by T8/T11. ✅
- #2 sleep/lock UI: xfce4-screensaver config + lock background + packages → Tasks 1 (lock bg), 4 (config), 5 (package); enforced by T11. ✅
- #3 punchline on image surfaces (wallpaper/greeter/Plymouth/lock) → Task 1; enforced by T7. ✅
- Theme/icon packages installed → Task 5. ✅
- Package wiring → Task 6. ✅
- CI, no ISO build → Tasks 7, 8. ✅

**2. Placeholder scan:** No TBD/TODO; all file contents complete; `<id>` in Task 8 is a runtime value substituted from the JSON output (same pattern as the other verify workflows), not a plan placeholder. ✅

**3. Type/name consistency:**
- Category `X-VITOS-Theme` identical across the 3 launchers (Task 3), the `.directory`, `vitos.menu`, and test T10. ✅
- `VITOS_THEME_TEST` hook + `PRESET=… GTK=… ICONS=… WM=… WP=…` output identical between Task 3 and test T9. ✅
- Wallpaper variant filenames `wallpaper.png` / `wallpaper-matrix.png` / `wallpaper-stealth.png` identical in Task 1 (generator), Task 3 (`vitos-theme` `WP=`), and test T7/T9. ✅
- Plymouth asset names `progress-box.png` / `progress-bar.png` / `scanline.png` identical in Task 1 (generator), Task 2 (`vitos.script`), and test T7/T8. ✅
- Default theme `Arc-Dark` identical in Task 3 (neon preset), Task 4 (xsettings/xfwm4), and test T9/T11. ✅
- `vitos-theme` name identical in Task 3 (file), launchers' `Exec=`, Task 6 (install), test T9. ✅

**Note on T7 grep pattern:** the generator writes assets via `"$OUT_BASE/wallpaper.png"` and `"$OUT_PLY/progress-box.png"`; the test greps `"/$out\""` (e.g. `/wallpaper.png"`), which matches both `$OUT_BASE/…"` and `$OUT_PLY/…"` paths. ✅

No issues found.
