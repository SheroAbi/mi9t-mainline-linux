#!/bin/bash
# Install kernel 7.1.0-sm7150fix as THE system - without an initramfs.
#
#   scripts/install/install-kernel.sh [/tmp/kernel-fix.tar.gz]
#
# Why no initramfs: the UFS controller, SCSI disk and ext4 are built into the
# kernel (CONFIG_SCSI_UFS_QCOM=y, CONFIG_BLK_DEV_SD=y, CONFIG_EXT4_FS=y), so
# the kernel mounts root by itself. That removes the 20 MB artefact that had
# to be rebuilt on every install - and that was the flakiest link in the chain.
#
# Three file operations remain: copy the kernel, copy the DTB, write the boot
# entry. There is no intermediate state in which anything is half done.
set -e

KREL=7.1.0-sm7150fix
TGZ=${1:-/tmp/kernel-fix.tar.gz}
BOOTDEV=/dev/sda30
ROOTDEV=/dev/sda32
BM=/mnt/bootfix
X=/tmp/kfix

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

[ "$(id -u)" = 0 ] || die "run as root"

step "unpack the package"
[ -f "$TGZ" ] || die "$TGZ not found"
rm -rf "$X"; mkdir -p "$X"
tar xzf "$TGZ" -C "$X"
[ -f "$X/boot/vmlinuz-$KREL" ] || die "vmlinuz missing from the package"
[ -f "$X/dtb/davinci-fix.dtb" ] || die "DTB missing from the package"

step "install modules"
if [ -d "/lib/modules/$KREL" ]; then
    echo "already present: $(find /lib/modules/$KREL -name '*.ko*' | wc -l) modules"
else
    cp -a "$X/lib/modules/$KREL" /lib/modules/
    depmod -a "$KREL"
    echo "installed: $(find /lib/modules/$KREL -name '*.ko*' | wc -l) modules"
fi

step "firmware path for 7.1"
# The 7.1 kernel looks under qcom/sm7150/xiaomi/davinci/, the firmware is
# installed under qcom/sm7150/davinci/. Without this link the modem
# coprocessor does not start, and without it there is no Wi-Fi.
mkdir -p /lib/firmware/qcom/sm7150/xiaomi
ln -sfn ../davinci /lib/firmware/qcom/sm7150/xiaomi/davinci
if [ -r /lib/firmware/qcom/sm7150/xiaomi/davinci/ipa_fws.mbn ]; then
    echo "firmware reachable through the new path"
else
    echo "WARNING: firmware not readable under the new path - Wi-Fi will be missing"
fi

step "mount the boot partition"
mkdir -p "$BM"
mountpoint -q "$BM" || mount -t vfat "$BOOTDEV" "$BM" || die "mounting $BOOTDEV failed"
trap 'umount "$BM" 2>/dev/null || true' EXIT

step "copy kernel and DTB"
cp "$X/boot/vmlinuz-$KREL" "$BM/vmlinuz-fix"
mkdir -p "$BM/dtbs/qcom"
cp "$X/dtb/davinci-fix.dtb" "$BM/dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb"
ls -la "$BM/vmlinuz-fix" "$BM/dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb"

step "write the boot entry"
# root as a device node: without an initramfs the kernel cannot resolve
# root=UUID=, but it can resolve /dev/sda32. There is only one UFS unit with
# partitions, so the naming is stable.
cat > "$BM/loader/entries/ubuntu.conf" <<EOF
title Ubuntu
sort-key aaa
linux vmlinuz-fix
devicetree dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb
options root=$ROOTDEV rw rootwait console=tty0 console=ttyGS0,115200 loglevel=4 arm_smmu.disable_bypass=0 quiet splash
EOF
cat "$BM/loader/entries/ubuntu.conf"

# The older 7.1 entry with an initramfs is no longer needed
rm -f "$BM/loader/entries/ubuntu-fix.conf" "$BM/initramfs-fix"

step "keep the rescue entry"
if [ -f "$BM/loader/entries/pmos.conf" ]; then
    sed -i 's/^title.*/title Rescue (old kernel 6.13)/' "$BM/loader/entries/pmos.conf"
    grep -q '^sort-key' "$BM/loader/entries/pmos.conf" \
        && sed -i 's/^sort-key.*/sort-key zzz/' "$BM/loader/entries/pmos.conf" \
        || echo "sort-key zzz" >> "$BM/loader/entries/pmos.conf"
    echo "6.13 stays as the rescue entry at the bottom of the menu"
fi

step "boot menu"
printf 'timeout 3\ndefault ubuntu.conf\n' > "$BM/loader/loader.conf"
cat "$BM/loader/loader.conf"
echo "--- entries ---"
ls -1 "$BM/loader/entries/"
echo "--- usage ---"
df -h "$BM" | tail -1

sync
umount "$BM"
trap - EXIT

echo
echo "DONE. One system, one entry, no initramfs."
echo "After the reboot: uname -r  ->  $KREL"
