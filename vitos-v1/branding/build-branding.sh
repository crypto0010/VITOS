#!/usr/bin/env bash
# Generates all VITOS imagery from the source VIT Bhopal logo using ImageMagick.
set -euo pipefail

SRC="$(dirname "$0")/vit-bhopal-logo.png"
OUT_BASE="$(dirname "$0")/../packages/vitos-base/usr/share/vitos/branding"
OUT_PLY="$(dirname "$0")/../packages/vitos-base/usr/share/plymouth/themes/vitos"
OUT_ISOLINUX="$(dirname "$0")/../live-build/config/bootloaders/isolinux"
OUT_GRUB="$(dirname "$0")/../live-build/config/bootloaders/grub-pc"
OUT_GRUB_EFI="$(dirname "$0")/../live-build/config/bootloaders/grub-efi"

mkdir -p "$OUT_BASE" "$OUT_PLY" "$OUT_ISOLINUX" "$OUT_GRUB" "$OUT_GRUB_EFI"

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

# 3. isolinux splash — 640x480 indexed PNG
convert -size 640x480 xc:"$BG" \
  \( "$SRC" -resize 360x -background none -gravity center -extent 360x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 22 \
  -annotate +0+30 'VITOS v1' \
  -colors 16 -depth 8 \
  "$OUT_ISOLINUX/splash.png"

# 4. GRUB BIOS + EFI splash — 1024x768 for broad compatibility
convert -size 1024x768 xc:"$BG" \
  \( "$SRC" -resize 320x -background none -gravity center -extent 320x \) \
  -gravity center -composite \
  -gravity south -fill "$FG" -font DejaVu-Sans-Bold -pointsize 24 \
  -annotate +0+80 'VITOS — VIT Bhopal Cybersecurity Lab' \
  "$OUT_GRUB/splash.png"
cp "$OUT_GRUB/splash.png" "$OUT_GRUB_EFI/splash.png"

# 5. ASCII header
cat > "$OUT_BASE/banner-ascii.txt" <<'ASCII'
   __     __  ___   _____   ___    ____
   \ \   / / |_ _| |_   _| / _ \  / ___|
    \ \ / /   | |    | |  | | | | \___ \
     \ V /    | |    | |  | |_| |  ___) |
      \_/    |___|   |_|   \___/  |____/

         VIT Bhopal — Cybersecurity Lab OS
ASCII

echo "Branding artifacts written:"
ls -1 "$OUT_BASE" "$OUT_PLY" "$OUT_ISOLINUX" "$OUT_GRUB" "$OUT_GRUB_EFI"
