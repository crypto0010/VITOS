#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Generate branding artifacts from the source logo
/build/vitos-v1/branding/build-branding.sh

# Stage the pre-baked model into includes.chroot
mkdir -p config/includes.chroot/var/lib/ollama/models/blobs
if [ ! -f config/includes.chroot/var/lib/ollama/models/blobs/gemma3-4b-instruct-q4_K_M.gguf ]; then
  /build/vitos-v1/ollama-blob/fetch-model.sh
fi

lb clean --purge || true
./auto/config
lb build 2>&1 | tee /tmp/lb-build.log

ISO=$(ls -1 *.iso 2>/dev/null | head -1)
if [ -z "$ISO" ]; then
  echo "BUILD FAILED — no ISO produced"
  exit 1
fi
SIZE=$(du -h "$ISO" | cut -f1)
mv "$ISO" "/build/vitos-v1/vitos-v1-$(date +%Y%m%d)-amd64.iso"
echo "Built /build/vitos-v1/vitos-v1-$(date +%Y%m%d)-amd64.iso ($SIZE)"
