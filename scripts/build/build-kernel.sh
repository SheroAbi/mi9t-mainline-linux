#!/bin/bash
# Build the Mi 9T kernel 7.1.0-sm7150fix and package it for install-kernel.sh.
#
# Run it inside a Linux environment with an aarch64 cross toolchain. On a
# Windows host that means WSL:
#
#     wsl -d Ubuntu-24.04 -- bash '/mnt/c/.../mi9t-kernel/scripts/build/build-kernel.sh'
#
# Work directory defaults to ~/mi9t-build and is reused between runs, so a
# second run is incremental. Set WORK= to put it elsewhere.
set -euo pipefail

PROJ=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="${WORK:-$HOME/mi9t-build}"
KREL=7.1.0-sm7150fix

# The exact upstream tree this kernel is built from. Pinned on purpose: the
# sm7150-mainline branch moves, and the two driver patches in kernel/patches/
# apply to this revision.
REPO=https://github.com/sm7150-mainline/linux
COMMIT=fd78d17954a86ea6ceb0c535e618ea129e09f8dd     # Linux 7.1.0 final, branch v7.2

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LC_ALL=C
SRC="$WORK/linux"
OUT="$WORK/out"
PKG="$WORK/pkg"

step() { echo; echo "=== $* ==="; }

step "toolchain"
for t in aarch64-linux-gnu-gcc make bc bison flex; do
	command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }
done
aarch64-linux-gnu-gcc --version | head -1

step "source tree @ $COMMIT"
mkdir -p "$WORK"
if [ ! -d "$SRC/.git" ] && [ ! -f "$SRC/Makefile" ]; then
	git clone --filter=blob:none "$REPO" "$SRC"
fi
if [ -d "$SRC/.git" ]; then
	git -C "$SRC" fetch --depth 1 origin "$COMMIT" 2>/dev/null || git -C "$SRC" fetch origin
	git -C "$SRC" checkout --detach "$COMMIT"
fi
grep -q '^SUBLEVEL = 0' "$SRC/Makefile" && grep -q '^PATCHLEVEL = 1' "$SRC/Makefile" \
	|| { echo "unexpected kernel version in $SRC/Makefile" >&2; exit 1; }

step "config"
mkdir -p "$OUT"
cp "$PROJ/kernel/config-$KREL" "$OUT/.config"
make -C "$SRC" O="$OUT" olddefconfig >/dev/null
for opt in CONFIG_USB_G_SERIAL=y CONFIG_EFI_ZBOOT=y CONFIG_BATTERY_QCOM_QG=m CONFIG_CHARGER_QCOM_SMB2=m \
           CONFIG_TYPEC_QCOM_PMIC=y CONFIG_SCSI_UFS_QCOM=y CONFIG_BLK_DEV_SD=y CONFIG_EXT4_FS=y; do
	grep -qx "$opt" "$OUT/.config" || { echo "config lost $opt after olddefconfig" >&2; exit 1; }
done
grep -x 'CONFIG_LOCALVERSION="-sm7150fix"' "$OUT/.config" >/dev/null

step "in-tree patches"
# The two charging drivers ship as sources, not as patches against the tree:
# kernel/modules/ holds exactly what the running modules were compiled from.
install -m644 "$PROJ/kernel/modules/qcom_qg.c"   "$SRC/drivers/power/supply/qcom_qg.c"
install -m644 "$PROJ/kernel/modules/qcom_smbx.c" "$SRC/drivers/power/supply/qcom_smbx.c"

step "build"
make -C "$SRC" O="$OUT" -j"$(nproc)" Image dtbs modules

step "package"
rm -rf "$PKG"
mkdir -p "$PKG/boot" "$PKG/dtb" "$PKG/extra" "$PKG/lib/modules"
# CONFIG_EFI_ZBOOT=y: the bootable artefact is vmlinuz.efi, not Image
cp "$OUT/arch/arm64/boot/vmlinuz.efi" "$PKG/boot/vmlinuz-$KREL"
cp "$OUT/System.map"                "$PKG/boot/System.map-$KREL"
cp "$OUT/.config"                   "$PKG/boot/config-$KREL"
cp "$OUT/arch/arm64/boot/dts/qcom/sm7150-xiaomi-davinci-samsung.dtb"  "$PKG/dtb/davinci-fix.dtb"
cp "$OUT/arch/arm64/boot/dts/qcom/sm7150-xiaomi-davinci-visionox.dtb" "$PKG/dtb/davinci-fix-visionox.dtb"
cp "$PROJ/device/modules-7150.conf" "$PKG/extra/"
make -C "$SRC" O="$OUT" -s modules_install INSTALL_MOD_PATH="$PKG" INSTALL_MOD_STRIP=1
rm -f "$PKG/lib/modules/$KREL/build" "$PKG/lib/modules/$KREL/source"

tar czf "$WORK/kernel-fix.tar.gz" -C "$PKG" boot dtb extra lib
sync
echo
echo "modules: $(find "$PKG/lib/modules" -name '*.ko*' | wc -l)"
sha256sum "$WORK/kernel-fix.tar.gz"
echo "BUILD_OK $WORK/kernel-fix.tar.gz"
echo
echo "Next: copy it to the phone and run scripts/install/install-kernel.sh"
