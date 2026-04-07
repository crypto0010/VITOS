#!/usr/bin/env bash
# Run at builder time, NOT at firstboot.
set -euo pipefail
DEST="${DEST:-/build/vitos-v1/live-build/config/includes.chroot/var/lib/ollama/models/blobs}"
mkdir -p "$DEST"
# Use the non-gated community mirror — google/gemma-3-* requires license
# acceptance and returns 401 to anonymous curl. bartowski's repo is the
# same Q4_K_M quantization of the same instruction-tuned weights.
URL="https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf"
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
