#!/bin/sh -e

if [ "$(uname -m)" != aarch64 ]; then
    echo 'This builder requires a native ARM64 host (use ubuntu-22.04-arm in Actions).' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y \
    android-sdk-libsparse-utils \
    build-essential \
    ca-certificates \
    debian-archive-keyring \
    debootstrap \
    device-tree-compiler \
    e2fsprogs \
    fdisk \
    gcc-arm-none-eabi \
    python3-cryptography \
    python3-pyasn1-modules \
    python3-pycryptodome \
    unzip \
    wget \
    xz-utils

# Ubuntu 22.04 ships a keyring predating Debian 13 (the current stable).
# Keep debootstrap signature verification enabled by updating the trusted keys.
if dpkg --compare-versions "$(dpkg-query -W -f='${Version}' debian-archive-keyring)" lt 2025.1; then
    keyring_tmp=$(mktemp -d)
    trap 'rm -rf "$keyring_tmp"' EXIT
    wget --https-only --tries=3 --timeout=30 \
        -O "$keyring_tmp/keyring.deb" \
        https://deb.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb
    # SHA-256 published at https://packages.debian.org/trixie/all/debian-archive-keyring/download
    printf '%s  %s\n' \
        9ea7778e443144ca490668737a8ab22dd3e748bb99e805e22ec055abeb3c7fac \
        "$keyring_tmp/keyring.deb" | sha256sum --check -
    dpkg -i "$keyring_tmp/keyring.deb"
fi
