#!/usr/bin/env bash
# Generates VITOS branding imagery from the source VIT Bhopal logo.
set -euo pipefail

SRC="$(dirname "$0")/vit-bhopal-logo.png"
OUT_BASE="$(dirname "$0")/../packages/vitos-base/usr/share/vitos/branding"
OUT_PLY="$(dirname "$0")/../packages/vitos-base/usr/share/plymouth/themes/vitos"
OUT_CAL="$(dirname "$0")/../live-build/config/includes.chroot/usr/share/vitos/branding"

mkdir -p "$OUT_BASE" "$OUT_PLY" "$OUT_CAL"

BG="#0a0e2a"
FG="#ffffff"

# 1. LightDM greeter background — 1920x1080
convert -size 1920x1080 \
  gradient:"$BG"-"#1a1f4a" \
  \( "$SRC" -resize 720x -background none -gravity center -extent 720x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 36 \
  -annotate +0+150 'VITOS — Developed by Dr. Hemraj, VIT Bhopal' \
  -gravity south -fill '#9aa4d6' -font DejaVu-Sans -pointsize 24 \
  -annotate +0+100 'Designed at VIT Bhopal for VITians' \
  "$OUT_BASE/lightdm-background.png"

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

# 2. Plymouth boot splash — 1920x1080
convert -size 1920x1080 xc:"$BG" \
  \( "$SRC" -resize 480x -background none -gravity center -extent 480x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans -pointsize 28 \
  -annotate +0+240 'VITOS — Developed by Dr. Hemraj' \
  -gravity south -fill '#9aa4d6' -font DejaVu-Sans -pointsize 20 \
  -annotate +0+200 'Designed at VIT Bhopal for VITians' \
  "$OUT_PLY/splash.png"

# 3. Calamares product logo — VIT logo on dark background, sized for sidebar
convert -size 320x120 xc:"#0d1117" \
  \( "$SRC" -resize 280x -background none -gravity center -extent 280x \) \
  -gravity center -composite \
  "$OUT_CAL/calamares-logo.png"

# 4. Calamares product icon — 64x64 "V" monogram
convert -size 64x64 xc:none \
  -fill '#4CB5F5' -draw 'roundrectangle 0,0 63,63 12,12' \
  -fill white -font DejaVu-Sans-Bold -pointsize 36 \
  -gravity center -annotate +0+0 'V' \
  "$OUT_CAL/calamares-icon.png"

# 5. ASCII header
cat > "$OUT_BASE/banner-ascii.txt" <<'ASCII'
   __     __  ___   _____   ___    ____
   \ \   / / |_ _| |_   _| / _ \  / ___|
    \ \ / /   | |    | |  | | | | \___ \
     \ V /    | |    | |  | |_| |  ___) |
      \_/    |___|   |_|   \___/  |____/

    Developed by Dr. Hemraj — VIT Bhopal University
ASCII

echo "Branding artifacts written:"
ls -1 "$OUT_BASE" "$OUT_PLY" "$OUT_CAL"
