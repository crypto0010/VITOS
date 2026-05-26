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

  if grep -qE "Couldn't download packages|404.*Not Found.*(gcc|libgcc|libstdc)" /tmp/lb-build.log; then
    echo "=== Kali mirror has broken GCC 16 packages — using mmdebstrap with Debian testing fallback ==="
    rm -rf chroot .build/bootstrap* .build/chroot*

    # Bootstrap from Kali, but add Debian testing as a supplementary
    # source for GCC packages. Pin GCC 16 to -1 so APT picks GCC 14
    # from Debian testing instead of the broken Kali packages.
    GCC_PIN='Package: gcc-16-base\nPin: version *\nPin-Priority: -1\n\nPackage: gcc-14-base libgcc-s1 libstdc++6\nPin: release a=testing\nPin-Priority: 999'

    mmdebstrap \
      --variant=minbase \
      --include=apt,gnupg,kali-archive-keyring \
      --aptopt='Acquire::Retries "5";' \
      --keyring=/usr/share/keyrings/kali-archive-keyring.gpg \
      --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
      --setup-hook='echo "deb http://deb.debian.org/debian testing main" > "$1/etc/apt/sources.list.d/debian-testing.list"' \
      --setup-hook="mkdir -p \"\$1/etc/apt/preferences.d\" && printf '$GCC_PIN\n' > \"\$1/etc/apt/preferences.d/gcc-pin\"" \
      kali-rolling chroot http://http.kali.org/kali

    # Mark bootstrap complete — lb build will skip straight to chroot stage
    mkdir -p .build
    touch .build/bootstrap

    # Ensure the GCC pin and Kali keyring persist into the chroot for lb
    mkdir -p chroot/etc/apt/preferences.d chroot/etc/apt/trusted.gpg.d
    cp /usr/share/keyrings/kali-archive-keyring.gpg \
       chroot/etc/apt/trusted.gpg.d/kali-archive-keyring.gpg
    printf "$GCC_PIN\n" > chroot/etc/apt/preferences.d/gcc-pin

    # Remove the Debian testing source — lb will set up Kali sources
    rm -f chroot/etc/apt/sources.list.d/debian-testing.list

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
