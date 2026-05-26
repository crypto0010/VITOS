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

GCC_PIN='Package: gcc-16-base\nPin: version *\nPin-Priority: -1\n\nPackage: gcc-14-base libgcc-s1 libstdc++6\nPin: release a=testing\nPin-Priority: 999'

MAX_RETRIES=4
for attempt in $(seq 1 $MAX_RETRIES); do
  echo "=== Build attempt $attempt of $MAX_RETRIES ==="

  if lb build 2>&1 | tee /tmp/lb-build.log; then
    echo "=== lb build succeeded on attempt $attempt ==="
    break
  fi

  if grep -qE "Couldn't download packages|404.*Not Found.*(gcc|libgcc|libstdc)" /tmp/lb-build.log; then
    echo "=== Kali mirror has broken GCC 16 packages — using mmdebstrap with Debian testing fallback ==="
    rm -rf chroot .build/bootstrap* .build/chroot*

    mmdebstrap \
      --variant=minbase \
      --include=apt,gnupg,kali-archive-keyring \
      --aptopt='Acquire::Retries "5";' \
      --keyring=/usr/share/keyrings/kali-archive-keyring.gpg \
      --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
      --setup-hook='echo "deb http://deb.debian.org/debian testing main" > "$1/etc/apt/sources.list.d/debian-testing.list"' \
      --setup-hook="mkdir -p \"\$1/etc/apt/preferences.d\" && printf '$GCC_PIN\n' > \"\$1/etc/apt/preferences.d/gcc-pin\"" \
      kali-rolling chroot http://http.kali.org/kali

    # Persist GCC pin and Kali keyring into chroot for lb's chroot stage
    mkdir -p chroot/etc/apt/preferences.d chroot/etc/apt/trusted.gpg.d chroot/etc/apt/apt.conf.d
    printf "$GCC_PIN\n" > chroot/etc/apt/preferences.d/gcc-pin
    cp /usr/share/keyrings/kali-archive-keyring.gpg \
       chroot/etc/apt/trusted.gpg.d/kali-archive-keyring.gpg
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' \
       > chroot/etc/apt/apt.conf.d/99retries

    # Remove Debian testing source — lb will set up its own Kali sources
    rm -f chroot/etc/apt/sources.list.d/debian-testing.list

    # Mark bootstrap complete
    mkdir -p .build
    touch .build/bootstrap

    continue

  elif grep -qE "Mirror sync in progress|unexpected size|Hash Sum mismatch|index files failed" /tmp/lb-build.log; then
    echo "=== Mirror sync in progress — waiting 90s before retry (keeping chroot intact) ==="
    sleep 90
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
