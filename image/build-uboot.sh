#!/bin/bash
# Build U-Boot for the Mi 9T, packed as an Android boot image for the boot
# partition. The Xiaomi bootloader starts it like a kernel; U-Boot then starts
# systemd-boot from the ESP.
#
#   image/build-uboot.sh            (image/build-image.sh calls it)
#
# Source, configuration and packaging are exactly those of the U-Boot the
# reference phone runs ("U-Boot 2025.04-g70c600c10f87"): the tree of the
# SM7150 mainline maintainer and his own build workflow, USB left in OTG mode.
#
# Host packages: gcc-aarch64-linux-gnu make gcc bison flex bc libssl-dev
# libgnutls28-dev python3 python3-setuptools python3-pyelftools swig git
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-/var/tmp/mi9t-uboot}
OUT=${OUT:-$REPO/dist/image}
CROSS=${CROSS_COMPILE:-aarch64-linux-gnu-}
UBOOT_REPO=https://github.com/Gelbpunkt/u-boot
UBOOT_COMMIT=70c600c10f8734b8636f7817bf0e1b4c0868c03a
MKBOOTIMG_REPO=https://github.com/osm0sis/mkbootimg
MKBOOTIMG_COMMIT=17cea80bd5af64e45cdf9e263cad7555030e0e86
DEVICE=sm7150-xiaomi-davinci

for t in git make gcc gzip bison flex bc "${CROSS}gcc"; do
	command -v "$t" >/dev/null || { echo "missing host tool: $t" >&2; exit 1; }
done

fetch_commit() {  # <repo> <commit> <dir>
	rm -rf "$3"
	git init -q "$3"
	git -C "$3" fetch -q --depth 1 "$1" "$2"
	git -C "$3" checkout -q FETCH_HEAD
}

mkdir -p "$WORK" "$OUT"
echo "=== sources ==="
fetch_commit "$UBOOT_REPO" "$UBOOT_COMMIT" "$WORK/u-boot"
fetch_commit "$MKBOOTIMG_REPO" "$MKBOOTIMG_COMMIT" "$WORK/mkbootimg"

echo "=== mkbootimg ==="
# Ubuntu's mkbootimg package does not produce a working image here; the
# workflow uses this C variant.
(cd "$WORK/mkbootimg" && CFLAGS=-Wstringop-overflow=0 make mkbootimg)

echo "=== U-Boot ==="
cd "$WORK/u-boot"
make CROSS_COMPILE="$CROSS" O=.output qcom_defconfig qcom-phone.config
make CROSS_COMPILE="$CROSS" O=.output -j"$(nproc)" CONFIG_DEFAULT_DEVICE_TREE="qcom/$DEVICE"
gzip -c .output/u-boot-nodtb.bin > .output/u-boot-nodtb.bin.gz
cat .output/u-boot-nodtb.bin.gz ".output/dts/upstream/src/arm64/qcom/$DEVICE.dtb" > .output/uboot-dtb
"$WORK/mkbootimg/mkbootimg" --base 0x0 --kernel_offset 0x00008000 --pagesize 4096 \
	--kernel .output/uboot-dtb -o "$OUT/uboot.img"
ls -l "$OUT/uboot.img"
