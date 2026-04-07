FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev \
    libncurses-dev rsync cpio kmod \
    debhelper devscripts dpkg-dev fakeroot lintian \
    live-build live-boot live-config \
    debootstrap squashfs-tools xorriso isolinux syslinux-common \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
    git curl ca-certificates jq xz-utils \
    clang llvm libbpf-dev linux-headers-amd64 \
    python3 python3-venv python3-pip \
    qemu-system-x86 qemu-utils ovmf \
    imagemagick fonts-dejavu-core \
    golang \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
ENTRYPOINT ["/bin/bash"]
