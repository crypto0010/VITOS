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

# Try normal build — if debootstrap fails on a transient mirror issue
# (e.g. GCC package transition), fall back to mmdebstrap which uses
# APT's full resolver and can select older consistent packages.
if lb build 2>&1 | tee /tmp/lb-build.log; then
  echo "=== lb build succeeded ==="
else
  if grep -q "Couldn't download packages" /tmp/lb-build.log; then
    echo "=== Debootstrap mirror issue — retrying with mmdebstrap ==="
    rm -rf chroot .build/bootstrap*

    mmdebstrap \
      --variant=minbase \
      --include=apt,kali-archive-keyring \
      --aptopt='Acquire::Retries "3";' \
      kali-rolling chroot http://http.kali.org/kali

    mkdir -p .build
    touch .build/bootstrap

    lb build 2>&1 | tee /tmp/lb-build-retry.log
  else
    echo "=== Build failed (not a mirror issue) ==="
    tail -100 /tmp/lb-build.log
    exit 1
  fi
fi

ISO=""; for f in *.iso; do [ -f "$f" ] && ISO="$f" && break; done
if [ -z "$ISO" ]; then
  echo "BUILD FAILED — no ISO produced"
  exit 1
fi
SIZE=$(du -h "$ISO" | cut -f1)
STAMP="$(date +%Y%m%d)"
FINAL="/build/vitos-v1/vitos-v1-${STAMP}-amd64.iso"
mv "$ISO" "$FINAL"
echo "Built ${FINAL} ($SIZE)"
