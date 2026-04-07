#!/usr/bin/env bash
# Run at builder time, NOT at firstboot.
set -euo pipefail
DEST="${DEST:-/build/vitos-v1/live-build/config/includes.chroot/var/lib/ollama/models/blobs}"
mkdir -p "$DEST"
URL="https://huggingface.co/google/gemma-3-4b-it-qat-q4_0-gguf/resolve/main/gemma-3-4b-it-q4_0.gguf"
SUM_FILE="$(dirname "$0")/SHA256SUMS"
TARGET="$DEST/gemma3-4b-instruct-q4_K_M.gguf"

if [ ! -f "$TARGET" ]; then
  curl -fL --retry 3 -o "$TARGET" "$URL"
fi
if [ -f "$SUM_FILE" ]; then
  ( cd "$DEST" && sha256sum -c "$SUM_FILE" ) || {
    echo "Model checksum mismatch"; rm -f "$TARGET"; exit 1; }
else
  ( cd "$DEST" && sha256sum gemma3-4b-instruct-q4_K_M.gguf > "$SUM_FILE" )
  echo "Wrote initial $SUM_FILE — review and commit it."
fi
echo "Model staged at $TARGET ($(du -h "$TARGET" | cut -f1))"
