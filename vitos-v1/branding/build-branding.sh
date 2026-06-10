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
  -annotate +0+120 'VITOS — Developed by Dr. Hemraj, VIT Bhopal' \
  "$OUT_BASE/lightdm-background.png"

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

# 2. Plymouth boot splash — 1920x1080
convert -size 1920x1080 xc:"$BG" \
  \( "$SRC" -resize 480x -background none -gravity center -extent 480x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans -pointsize 28 \
  -annotate +0+200 'VITOS — Developed by Dr. Hemraj' \
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
