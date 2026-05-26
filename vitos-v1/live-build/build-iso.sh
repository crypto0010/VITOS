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

MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
  echo "=== Build attempt $attempt of $MAX_RETRIES ==="

  if lb build 2>&1 | tee /tmp/lb-build.log; then
    echo "=== lb build succeeded on attempt $attempt ==="
    break
  fi

  if grep -qE "Couldn't download packages|404.*Not Found.*gcc|404.*Not Found.*libgcc" /tmp/lb-build.log; then
    echo "=== Kali mirror has broken packages (404) — bootstrapping from Debian sid ==="
    rm -rf chroot .build/bootstrap*

    # Bootstrap from Debian sid which has consistent packages
    mmdebstrap \
      --variant=minbase \
      --include=apt,gnupg \
      --aptopt='Acquire::Retries "5";' \
      sid chroot http://deb.debian.org/debian

    # Switch the chroot to Kali repos
    cat > chroot/etc/apt/sources.list <<'SOURCES'
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
SOURCES

    # Trust Kali archive key
    cp /usr/share/keyrings/kali-archive-keyring.gpg \
       chroot/etc/apt/trusted.gpg.d/kali-archive-keyring.gpg

    # Upgrade chroot to Kali packages
    mount --bind /proc chroot/proc
    mount --bind /sys  chroot/sys
    mount --bind /dev  chroot/dev
    chroot chroot apt-get update -y
    chroot chroot apt-get dist-upgrade -y --allow-downgrades || true
    umount chroot/dev chroot/sys chroot/proc

    # Mark bootstrap complete for live-build
    mkdir -p .build
    touch .build/bootstrap

    # Retry — lb build will skip bootstrap and proceed to chroot + binary
    continue

  elif grep -qE "Mirror sync in progress|unexpected size|Hash Sum mismatch|index files failed" /tmp/lb-build.log; then
    echo "=== Mirror sync in progress — waiting 90s before retry ==="
    sleep 90
    lb clean --chroot || true
    rm -rf .build/chroot*
    continue

  else
    echo "=== Non-transient failure on attempt $attempt ==="
    tail -80 /tmp/lb-build.log
    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
      exit 1
    fi
    sleep 30
    lb clean --chroot || true
    rm -rf .build/chroot*
  fi
done

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
