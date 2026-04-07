FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Enable bookworm-backports for golang-1.22
RUN echo "deb http://deb.debian.org/debian bookworm-backports main" \
      > /etc/apt/sources.list.d/backports.list

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
 && apt-get install -y --no-install-recommends -t bookworm-backports golang-1.22 \
 && rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/lib/go-1.22/bin:$PATH
WORKDIR /build
ENTRYPOINT ["/bin/bash"]
