#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}

if [ "$(uname -m)" != aarch64 ]; then
    echo 'Gadget-tool compilation requires a native ARM64 host.' >&2
    exit 1
fi

# Compile against the target Debian libraries, rather than the Ubuntu host.
# rootfs.tgz was already created, so these build dependencies stay out of the image.
work="$CHROOT/tmp/openstick-build"
rm -rf "$work"
mkdir -p "$work"
cp -a src/libusbgx "$work/libusbgx"
cp -a src/gt "$work/gt"

chroot "$CHROOT" /bin/sh -ex <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    autoconf automake build-essential cmake libconfig-dev libtool pkg-config

cd /tmp/openstick-build/libusbgx
autoreconf -fi
./configure --prefix=/usr --libdir=/usr/lib --disable-examples --disable-static
make -j "$(nproc)"
make install
make DESTDIR=/tmp/openstick-build/dist install
ldconfig

cmake -S /tmp/openstick-build/gt/source -B /tmp/openstick-build/gt-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_SYSCONFDIR=/etc \
    -DENABLE_MANUAL_PAGE=OFF
cmake --build /tmp/openstick-build/gt-build --parallel "$(nproc)"
DESTDIR=/tmp/openstick-build/dist cmake --install /tmp/openstick-build/gt-build

# Stage only the runtime library, executable, and configuration.
rm -rf /tmp/openstick-build/dist/usr/include \
    /tmp/openstick-build/dist/usr/lib/cmake \
    /tmp/openstick-build/dist/usr/lib/pkgconfig \
    /tmp/openstick-build/dist/usr/share
rm -f /tmp/openstick-build/dist/usr/lib/*.la
EOF

test -x "$work/dist/usr/bin/gt"
# Fail here if the freshly built ARM64 executable has unresolved runtime libraries.
ldd_output=$(chroot "$CHROOT" /usr/bin/ldd /tmp/openstick-build/dist/usr/bin/gt)
printf '%s\n' "$ldd_output"
if printf '%s\n' "$ldd_output" | grep -q 'not found'; then
    exit 1
fi

rm -rf dist
cp -a "$work/dist" dist
mkdir -p dist/etc/gt
cp -a configs/templates dist/etc/gt
rm -rf "$work"
