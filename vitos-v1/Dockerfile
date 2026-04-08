FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# Builder image is Kali so live-build defaults to kali mode and the
# kali-archive-keyring is already trusted — no manual key fetching.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev \
    libncurses-dev rsync cpio kmod \
    gcc-12 g++-12 \
    debhelper devscripts dpkg-dev fakeroot lintian \
    live-build live-boot live-config-doc \
    debootstrap squashfs-tools xorriso isolinux syslinux-common \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
    git curl ca-certificates jq xz-utils \
    clang llvm libbpf-dev linux-headers-amd64 \
    python3 python3-venv python3-pip \
    qemu-system-x86 qemu-utils ovmf \
    imagemagick fonts-dejavu-core \
    golang \
    kali-archive-keyring \
    nodejs npm \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
ENTRYPOINT ["/bin/bash"]
