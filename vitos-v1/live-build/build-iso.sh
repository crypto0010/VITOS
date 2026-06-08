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

# Stage vendored .debs (packages that have left kali-rolling / Debian-testing —
# see vendor-debs/README.md) into the live-build local repo. Verified against
# SHA256SUMS; a checksum mismatch is fatal (we will not bake an unverified .deb).
if ls vendor-debs/*.deb >/dev/null 2>&1; then
  mkdir -p config/packages.chroot
  ( cd vendor-debs && sha256sum -c SHA256SUMS )
  cp vendor-debs/*.deb config/packages.chroot/
  echo "Staged vendored .debs: $(ls vendor-debs/*.deb | xargs -n1 basename | tr '\n' ' ')"
fi

lb clean --purge || true
./auto/config

MAX_RETRIES=6
for attempt in $(seq 1 $MAX_RETRIES); do
  echo "=== Build attempt $attempt of $MAX_RETRIES ==="

  if lb build 2>&1 | tee /tmp/lb-build.log; then
    echo "=== lb build succeeded on attempt $attempt ==="
    break
  fi

  if grep -qE "Couldn't download packages|404.*Not Found.*(gcc|libgcc|libstdc)" /tmp/lb-build.log; then
    echo "=== Kali mirror has broken GCC packages — bootstrapping from Debian testing ==="
    rm -rf chroot .build/bootstrap* .build/chroot*

    if ! mmdebstrap \
      --variant=minbase \
      --include=apt,gnupg \
      --aptopt='Acquire::Retries "5";' \
      --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
      testing chroot http://deb.debian.org/debian; then
      echo "=== mmdebstrap from Debian testing also failed — retrying in 60s ==="
      sleep 60
      continue
    fi

    # Prepare chroot for lb's Kali chroot stage
    mkdir -p chroot/etc/apt/preferences.d chroot/etc/apt/trusted.gpg.d chroot/etc/apt/apt.conf.d

    # Block Kali's broken gcc-16 .debs — Debian testing versions already installed
    printf 'Package: gcc-16-base\nPin: version *\nPin-Priority: -1\n\nPackage: libgcc-s1 libstdc++6\nPin: version 16*\nPin-Priority: -1\n' \
      > chroot/etc/apt/preferences.d/gcc-pin

    cp /usr/share/keyrings/kali-archive-keyring.gpg \
       chroot/etc/apt/trusted.gpg.d/kali-archive-keyring.gpg
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' \
       > chroot/etc/apt/apt.conf.d/99retries

    # Replace Debian sources with Kali — lb will overwrite anyway
    echo "deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" \
      > chroot/etc/apt/sources.list

    # Mark bootstrap complete
    mkdir -p .build
    touch .build/bootstrap

    continue

  elif grep -qE "Mirror sync in progress|unexpected size|Hash Sum mismatch|index files failed" /tmp/lb-build.log; then
    echo "=== Mirror sync in progress — waiting 180s before retry (keeping chroot intact) ==="
    sleep 180
    # Do NOT clean the chroot — it's fine, only the mirror is flaky.
    # Just remove chroot stage markers so lb retries the chroot config.
    rm -f .build/chroot_archives .build/chroot_apt
    continue

  else
    echo "=== Non-transient failure on attempt $attempt ==="
    tail -80 /tmp/lb-build.log
    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
      exit 1
    fi
    sleep 30
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
