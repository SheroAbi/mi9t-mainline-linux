#!/bin/bash
# Install the self-built kernel 7.1.0-sm7150fix NEXT TO the existing one.
#
#   scripts/install/install-kernel-parallel.sh [/tmp/kernel-fix.tar.gz]
#
# SAFETY PRINCIPLE: nothing existing is overwritten.
#   - linux.efi, its initramfs and the 6.13 DTB stay untouched
#   - pmos.conf (6.13) stays unchanged and stays the default
#   - the new kernel gets its own entry and its own DTB
# If the new kernel fails: restart once, and 6.13 runs again.
#
# What this kernel does differently from the 7.1-rc3 package:
#   - qcom_qg computes the state of charge from an open-circuit-voltage
#     curve instead of linearly from the terminal voltage
#   - qcom_smbx reads the right SMB5 status register
#   - CONFIG_USB_G_SERIAL=y: serial console as on 6.13
set -e

KREL=7.1.0-sm7150fix
TGZ=${1:-/tmp/kernel-fix.tar.gz}
BOOTDEV=/dev/sda30
BM=/mnt/bootfix
X=/tmp/kfix

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f "$TGZ" ]      || die "$TGZ not found"

step "unpack the package"
rm -rf "$X"; mkdir -p "$X"
tar xzf "$TGZ" -C "$X"
[ -f "$X/boot/vmlinuz-$KREL" ] || die "vmlinuz missing from the package"
[ -d "$X/lib/modules/$KREL" ]  || die "modules missing from the package"
[ -f "$X/dtb/davinci-fix.dtb" ] || die "DTB missing from the package"
echo "modules in the package: $(find "$X/lib/modules" -name '*.ko*' | wc -l)"

step "install modules"
rm -rf "/lib/modules/$KREL"
cp -a "$X/lib/modules/$KREL" /lib/modules/
depmod -a "$KREL"
for m in qcom_smbx qcom_qg ath10k_snoc pwrseq-qcom-wcn; do
    if find "/lib/modules/$KREL" -name "$m.ko*" | grep -q .; then
        echo "  OK       $m"
    else
        echo "  MISSING  $m"
    fi
done

step "kernel to /boot"
cp "$X/boot/vmlinuz-$KREL"    "/boot/vmlinuz-$KREL"
cp "$X/boot/System.map-$KREL" "/boot/System.map-$KREL"
cp "$X/boot/config-$KREL"     "/boot/config-$KREL"

step "build the initramfs"
update-initramfs -c -k "$KREL"
[ -f "/boot/initrd.img-$KREL" ] || die "initramfs was not created"
ls -la "/boot/initrd.img-$KREL"

step "mount the boot partition"
mkdir -p "$BM"
mountpoint -q "$BM" || mount -t vfat "$BOOTDEV" "$BM" || die "mounting $BOOTDEV failed"
trap 'umount "$BM" 2>/dev/null || true' EXIT

ROOTUUID=$(grep -oE 'root=UUID=[0-9a-fA-F-]+' "$BM/loader/entries/pmos.conf" | head -1 | cut -d= -f3)
[ -n "$ROOTUUID" ] || die "cannot read the root UUID from pmos.conf"
echo "root UUID taken over: $ROOTUUID"

step "files to the boot partition"
cp "$X/boot/vmlinuz-$KREL"   "$BM/vmlinuz-fix"
cp "/boot/initrd.img-$KREL"  "$BM/initramfs-fix"
mkdir -p "$BM/dtbs/qcom"
cp "$X/dtb/davinci-fix.dtb"  "$BM/dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb"
ls -la "$BM/vmlinuz-fix" "$BM/initramfs-fix" "$BM/dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb"

step "create the boot entry"
# Spaces rather than tabs on purpose: systemd-boot accepts both, and this
# way the file also survives a transfer over the serial line.
cat > "$BM/loader/entries/ubuntu-fix.conf" <<EOF
title Ubuntu 7.1 (charging + battery gauge fixed)
sort-key zubuntufix
linux vmlinuz-fix
initrd initramfs-fix
devicetree dtbs/qcom/sm7150-xiaomi-davinci-fix.dtb
options console=tty0 console=ttyGS0,115200 loglevel=4 arm_smmu.disable_bypass=0 root=UUID=$ROOTUUID rw rootdelay=10
EOF
cat "$BM/loader/entries/ubuntu-fix.conf"

step "6.13 stays the default"
printf 'timeout 10\ndefault pmos.conf\n' > "$BM/loader/loader.conf"
cat "$BM/loader/loader.conf"
echo "--- existing entries ---"
ls -1 "$BM/loader/entries/"

step "load modules at boot"
if [ -f "$X/extra/modules-7150.conf" ]; then
    cp "$X/extra/modules-7150.conf" /etc/modules-load.d/sm7150.conf
    echo "installed: /etc/modules-load.d/sm7150.conf"
    cat /etc/modules-load.d/sm7150.conf
fi

sync
umount "$BM"
trap - EXIT

cat <<'EOS'

DONE.

The new entry is called "Ubuntu 7.1 (charging + battery gauge fixed)".
6.13 stays the default and the fallback - nothing was replaced.

Test it by choosing the entry in the boot menu (10 s timeout). Note that
`bootctl set-oneshot` has no effect on this device: U-Boot's EFI variables
are volatile.

Then check:
    uname -r                                  -> 7.1.0-sm7150fix
    ls /sys/class/power_supply/               -> an additional charger
    cat /sys/class/power_supply/*/status      -> Charging
    iw dev                                    -> wlan0 present

If the display stays white with black stripes, U-Boot ignored the
"devicetree" line and gave the new kernel the old device tree. Just restart -
6.13 comes back on its own.
EOS
