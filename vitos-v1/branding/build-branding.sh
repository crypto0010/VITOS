#!/usr/bin/env bash
# Generates VITOS branding imagery from the source VIT Bhopal logo.
# Bootloader splash is left to Kali's stock live-build templates.
set -euo pipefail

SRC="$(dirname "$0")/vit-bhopal-logo.png"
OUT_BASE="$(dirname "$0")/../packages/vitos-base/usr/share/vitos/branding"
OUT_PLY="$(dirname "$0")/../packages/vitos-base/usr/share/plymouth/themes/vitos"

mkdir -p "$OUT_BASE" "$OUT_PLY"

BG="#0a0e2a"
FG="#ffffff"

# 1. LightDM greeter background — 1920x1080
convert -size 1920x1080 \
  gradient:"$BG"-"#1a1f4a" \
  \( "$SRC" -resize 720x -background none -gravity center -extent 720x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 36 \
  -annotate +0+120 'VITOS — VIT Cybersecurity Lab' \
  "$OUT_BASE/lightdm-background.png"

# 2. Plymouth boot splash — 1920x1080
convert -size 1920x1080 xc:"$BG" \
  \( "$SRC" -resize 480x -background none -gravity center -extent 480x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans -pointsize 28 \
  -annotate +0+200 'Booting VITOS…' \
  "$OUT_PLY/splash.png"

# 3. ASCII header
cat > "$OUT_BASE/banner-ascii.txt" <<'ASCII'
   __     __  ___   _____   ___    ____
   \ \   / / |_ _| |_   _| / _ \  / ___|
    \ \ / /   | |    | |  | | | | \___ \
     \ V /    | |    | |  | |_| |  ___) |
      \_/    |___|   |_|   \___/  |____/

         VIT Bhopal — Cybersecurity Lab OS
ASCII

echo "Branding artifacts written:"
ls -1 "$OUT_BASE" "$OUT_PLY"
