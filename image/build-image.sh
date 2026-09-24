#!/bin/bash
# Build the complete Ubuntu 24.04 system for the Mi 9T from scratch.
#
#   scripts/build/build-kernel.sh          # first: the kernel package
#   sudo image/build-image.sh              # then: this
#
# Output in dist/image/ (flash with scripts/flash/flash.py):
#   uboot.img    U-Boot as an Android boot image     -> boot
#   esp.img      FAT32: systemd-boot, kernel, DTB    -> cache (/dev/sda30)
#   rootfs.img   ext4 root filesystem, sparse        -> userdata (/dev/sda32)
#   SHA256SUMS
#
# Inputs, from the environment:
#   KERNEL_TGZ  the package from build-kernel.sh (default ~/mi9t-build/kernel-fix.tar.gz,
#               of the user who called sudo)
#   DTB         the device tree to boot (default kernel/devicetree/boot-battery-final.dtb,
#               Samsung panel; see kernel/devicetree/README.md)
#   WORK        scratch space on a Linux filesystem (default /var/tmp/mi9t-image)
# plus the user/password/locale settings described in image/common/lib.sh.
# Optional features are not installed: see extras/.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$REPO/image/common/lib.sh"
CALLER_HOME=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
KERNEL_TGZ=${KERNEL_TGZ:-$CALLER_HOME/mi9t-build/kernel-fix.tar.gz}
DTB=${DTB:-$REPO/kernel/devicetree/boot-battery-final.dtb}
WORK=${WORK:-/var/tmp/mi9t-image}
OUT=${OUT:-$REPO/dist/image}
KREL=7.1.0-sm7150fix

# Public sources, pinned.
FIRMWARE_REPO=https://github.com/sm7150-mainline/firmware-xiaomi-davinci
FIRMWARE_COMMIT=7c25d3fe5883f25f8f068e89c6442b4c608835f0
PDMAPPER_REPO=https://github.com/linux-msm/pd-mapper
PDMAPPER_COMMIT=5ecd2fe926aca7abfe40724177f63b942cff3947          # v1.1
A630_SQE_URL='https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware/+/refs/heads/main/qcom/a630_sqe.fw?format=TEXT'
A630_SQE_SHA256=1c21b527d9183487cc550dabbb3f43e555df5a977a461934fc61f0635a9aa90c

require_host git curl base64 dpkg-deb mkfs.vfat mcopy mmd tar python3
[ -f "$KERNEL_TGZ" ] || die "no kernel package at $KERNEL_TGZ - run scripts/build/build-kernel.sh first (or set KERNEL_TGZ)"
[ -f "$DTB" ] || die "no device tree at $DTB"
image_settings mi9t
R=$WORK/rootfs
K=$WORK/kernel
trap chroot_umount EXIT

fetch_commit() {  # <repo> <commit> <dir>
	rm -rf "$3"
	git init -q "$3"
	git -C "$3" fetch -q --depth 1 "$1" "$2"
	git -C "$3" checkout -q FETCH_HEAD
}

log "kernel package"
rm -rf "$K"; mkdir -p "$K"
tar -xzf "$KERNEL_TGZ" -C "$K"
[ -f "$K/boot/vmlinuz-$KREL" ] && [ -d "$K/lib/modules/$KREL" ] || die "$KERNEL_TGZ is not a $KREL package"

rootfs_bootstrap "$R"
chroot_mount "$R"
rootfs_install "$R" "$REPO/device/packages.txt"
rootfs_configure "$R"

log "firmware"
fetch_commit "$FIRMWARE_REPO" "$FIRMWARE_COMMIT" "$WORK/firmware"
copy_tree "$WORK/firmware/usr" "$R/usr"
curl -fsSL "$A630_SQE_URL" | base64 -d > "$WORK/a630_sqe.fw"
echo "$A630_SQE_SHA256  $WORK/a630_sqe.fw" | sha256sum -c - >/dev/null || die "a630_sqe.fw checksum mismatch"
install -D -m 644 "$WORK/a630_sqe.fw" "$R/usr/lib/firmware/qcom/a630_sqe.fw"

log "kernel modules"
rm -rf "$R/usr/lib/modules/$KREL"
mkdir -p "$R/usr/lib/modules"
cp -a "$K/lib/modules/$KREL" "$R/usr/lib/modules/"
chown -R 0:0 "$R/usr/lib/modules/$KREL"
in_chroot "$R" depmod -a "$KREL"

log "sources for the device layer"
fetch_commit "$PDMAPPER_REPO" "$PDMAPPER_COMMIT" "$R/tmp/pd-mapper"
rm -rf "$WORK/hwpkg"; mkdir -p "$WORK/hwpkg"
copy_tree "$REPO/hardware-package" "$WORK/hwpkg"
rm -rf "$WORK/hwpkg/patches"
dpkg-deb --root-owner-group --build "$WORK/hwpkg" "$R/tmp/mi9t-hardware-support.deb" >/dev/null
rootfs_device "$R" "$REPO/device/base" "$REPO/device/configure.sh"
rootfs_finish "$R"
chroot_umount

mkdir -p "$OUT"
rm -f "$OUT/uboot.img" "$OUT/esp.img" "$OUT/rootfs.img" "$OUT/SHA256SUMS"

log "ESP: systemd-boot, kernel, device tree"
ESP=$WORK/esp.img
rm -f "$ESP"
truncate -s 256M "$ESP"
mkfs.vfat -F 32 -n ESP "$ESP" >/dev/null
export MTOOLS_SKIP_CHECK=1
mmd -i "$ESP" ::/EFI ::/EFI/BOOT ::/loader ::/loader/entries ::/dtbs ::/dtbs/qcom
mcopy -i "$ESP" "$R/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$ESP" "$K/boot/vmlinuz-$KREL" ::/vmlinuz-fix
mcopy -i "$ESP" "$DTB" ::/dtbs/qcom/sm7150-xiaomi-davinci-battery-final.dtb
printf 'timeout 3\ndefault ubuntu.conf\n' > "$WORK/loader.conf"
cat > "$WORK/ubuntu.conf" <<EOF
title Ubuntu
sort-key aaa
linux /vmlinuz-fix
devicetree /dtbs/qcom/sm7150-xiaomi-davinci-battery-final.dtb
options root=/dev/sda32 rw rootwait console=tty0 console=ttyGS0,115200 loglevel=4 arm_smmu.disable_bypass=0 quiet
EOF
mcopy -i "$ESP" "$WORK/loader.conf" ::/loader/loader.conf
mcopy -i "$ESP" "$WORK/ubuntu.conf" ::/loader/entries/ubuntu.conf
cp "$ESP" "$OUT/esp.img"

make_ext4 "$R" "$WORK/rootfs.raw" mi9t-root
sparse_image "$WORK/rootfs.raw" "$OUT/rootfs.img"
rm -f "$WORK/rootfs.raw"

WORK="$WORK/uboot" OUT="$OUT" "$REPO/image/build-uboot.sh"
checksums "$OUT"
log "done: flash with scripts/flash/flash.py (docs/03-installing.md)"
