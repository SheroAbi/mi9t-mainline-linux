#!/bin/sh
# Device integration for a Mi 9T that already runs 7.1.0-sm7150fix.
# Run as root on the phone from a checkout of this repository.
#
#   scripts/install/install-maintenance.sh
#
# What it does:
#   * boot splash (setup-splash.sh)
#   * disables the services of the KlipperOS base image that fail on a
#     desktop system, and leaves exactly one owner for the USB serial login
#   * installs the device tree (default: kernel/devicetree/boot-battery-final.dtb)
#     as its own systemd-boot entry, next to the existing one
#
# Optional inputs, from the environment:
#   DTB=<file>             another device tree to install
#   MODULES=<dir>          qcom_qg.ko and qcom_smbx.ko built from kernel/modules/
#                          for a kernel that was built before the patches
#   A630_SQE=<file>        a newer Adreno 630 SQE microcode (linux-firmware
#                          qcom/a630_sqe.fw, see kernel/upstream-reference/sources.json)
#
# The new entry is NOT made the default. Pick it in the boot menu, check the
# phone, and only then change `default` in loader.conf (bootctl set-oneshot
# does not work on this device: U-Boot's EFI variables are volatile).
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/../.." && pwd)
K=7.1.0-sm7150fix
ESP_DEV=/dev/sda30
M=/run/mi9t-boot-install
DTB=${DTB:-$REPO/kernel/devicetree/boot-battery-final.dtb}
[ "$(uname -r)" = "$K" ] || { echo "running kernel is not $K" >&2; exit 1; }
[ -s "$DTB" ] || { echo "missing $DTB" >&2; exit 1; }
ROOT_PARTUUID=$(findmnt -no PARTUUID /)
[ -n "$ROOT_PARTUUID" ] || { echo "cannot read the PARTUUID of /" >&2; exit 1; }

if [ -n "${MODULES:-}" ]; then
    install -d "/lib/modules/$K/updates/mi9t"
    install -m 644 "$MODULES/qcom_qg.ko" "$MODULES/qcom_smbx.ko" "/lib/modules/$K/updates/mi9t/"
    depmod -a "$K"
    case "$(modinfo -n qcom_qg)" in */updates/mi9t/*) ;; *) exit 1;; esac
    case "$(modinfo -n qcom_smbx)" in */updates/mi9t/*) ;; *) exit 1;; esac
fi
if [ -n "${A630_SQE:-}" ]; then
    install -m 644 "$A630_SQE" /lib/firmware/qcom/a630_sqe.fw.mi9t-new
    mv /lib/firmware/qcom/a630_sqe.fw.mi9t-new /lib/firmware/qcom/a630_sqe.fw
fi

"$REPO/scripts/install/setup-splash.sh"

# Helpers of the KlipperOS base image that fail on a desktop system.
for unit in crowsnest.service auto_rmi4_reload.service autoresize.service; do
    systemctl disable --now "$unit" 2>/dev/null || true
    systemctl reset-failed "$unit" 2>/dev/null || true
done
# There must be exactly one owner for the USB login terminal.
systemctl disable --now autottyGS0.service 2>/dev/null || true
systemctl enable serial-getty@ttyGS0.service

mkdir -p "$M"
mount -t vfat "$ESP_DEV" "$M"
trap 'umount "$M"' EXIT
install -m 644 "$DTB" "$M/dtbs/qcom/sm7150-xiaomi-davinci-battery-final.dtb"
cat > "$M/loader/entries/ubuntu-battery-final.conf" <<EOF
title Ubuntu (battery-final device tree)
sort-key aab
linux vmlinuz-fix
devicetree dtbs/qcom/sm7150-xiaomi-davinci-battery-final.dtb
options root=PARTUUID=$ROOT_PARTUUID rw rootwait console=ttyGS0,115200 loglevel=3 arm_smmu.disable_bypass=0 vt.global_cursor_default=0 quiet splash plymouth.ignore-serial-consoles systemd.show_status=auto
EOF
sync
bootctl --esp-path="$M" list --no-pager
sha256sum "$M/dtbs/qcom/sm7150-xiaomi-davinci-battery-final.dtb"
sync
echo 'Installed. The previous boot entry remains the default; choose the new one in the boot menu.'
