#!/bin/sh -e

CHROOT=${CHROOT:-$(pwd)/rootfs}
RELEASE=${RELEASE:-trixie}
HOST_NAME=${HOST_NAME=openstick-debian}

if [ "$(uname -m)" != aarch64 ]; then
    echo 'Rootfs creation requires a native ARM64 host.' >&2
    exit 1
fi

rm -rf ${CHROOT}

kernel_apk=
cleanup() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ] && [ -f "$CHROOT/debootstrap/debootstrap.log" ]; then
        tail -n 100 "$CHROOT/debootstrap/debootstrap.log"
    fi
    for a in dev/pts dev sys proc; do
        if mountpoint -q "$CHROOT/$a"; then
            umount "$CHROOT/$a" || status=1
        fi
    done
    if [ -n "$kernel_apk" ]; then
        rm -f "$kernel_apk"
    fi
    exit "$status"
}
trap cleanup EXIT

# Both bootstrap stages execute directly on the ARM64 runner.
debootstrap --arch arm64 --include=ca-certificates \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    "$RELEASE" "$CHROOT" https://deb.debian.org/debian

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb https://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb https://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb https://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/

# Do not start services inside the image while installing packages.
printf '#!/bin/sh\nexit 101\n' > "$CHROOT/usr/sbin/policy-rc.d"
chmod 0755 "$CHROOT/usr/sbin/policy-rc.d"

cp scripts/setup.sh ${CHROOT}
chroot "$CHROOT" /bin/sh -e /setup.sh

# cleanup
for a in dev/pts dev sys proc; do
    umount ${CHROOT}/${a}
done;

rm -f "$CHROOT/setup.sh" "$CHROOT/usr/sbin/policy-rc.d"
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup systemd services
cp -a configs/system/* ${CHROOT}/etc/systemd/system

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# enable autoconnect for usb0
cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# install kernel
kernel_apk=$(mktemp)
wget --https-only --tries=3 --timeout=30 -O "$kernel_apk" \
    https://mirror.postmarketos.org/postmarketos/v24.06/aarch64/linux-postmarketos-qcom-msm8916-6.6-r5.apk
tar xkzf "$kernel_apk" --ignore-zeros -C "$CHROOT" --exclude=.PKGINFO --exclude='.SIGN*'

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz -C "$CHROOT" .
