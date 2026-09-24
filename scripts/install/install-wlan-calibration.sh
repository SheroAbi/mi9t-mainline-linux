#!/bin/sh
# Give the WCN3990 Wi-Fi of the Mi 9T its own calibration.  Run as root on the
# phone, next to ath10k-board.py, then reboot.
#
# The device tree asks ath10k for the variant `xiaomi_davinci`; linux-firmware
# has no such entry, so the driver falls back to `bus=snoc,qmi-board-id=ff`, a
# reference board's data. Measured on 2026-09-23 with that fallback: 1.4 MB/s
# to the phone, 1.8 MB/s from it, 5 GHz practically unusable (-81 dBm). With
# the phone's own bdwlan.bin from the stock modem image: 3.0-3.7 / 3.5-4.0
# MB/s, and the phone holds 5 GHz at 80 MHz (292-325 MBit/s).
#
# Three things that each cost a failed attempt:
#  * The name uses the chip id in HEX: qmi-chip-id=140, not 320. The driver
#    prints the names it tries with ath10k_core.debug_mask=0x20.
#  * The board data is sent only when the Wi-Fi firmware starts. Rebinding
#    ath10k_snoc does not resend it, and restarting the modem remoteproc
#    leaves ath10k dead ("failed to push frame: -108"). Only a reboot applies it.
#  * QMI reports board_id 0xff, and 0xff means bdwlan.bin -- the same mapping
#    qcom-fw-setup uses. The bdwlan.bXX files are other boards.
#
# The result goes to /lib/firmware/updates, which the firmware loader searches
# first and no package ever writes: a linux-firmware update cannot undo it,
# and deleting that one file undoes it.
set -eu
here=$(dirname "$0")
work=$(mktemp -d)
trap 'umount "$work/modem" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir "$work/modem"
mount -o ro /dev/disk/by-partlabel/modem "$work/modem"
cp "$work/modem/image/bdwlan.bin" "$work/bdwlan.bin"
umount "$work/modem"
python3 "$here/ath10k-board.py" add /lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin \
    "$work/bdwlan.bin" 'bus=snoc,qmi-board-id=ff,qmi-chip-id=140,variant=xiaomi_davinci' \
    "$work/board-2.bin"
install -d /lib/firmware/updates/ath10k/WCN3990/hw1.0
install -m 0644 "$work/board-2.bin" /lib/firmware/updates/ath10k/WCN3990/hw1.0/board-2.bin
echo 'Installed. Reboot; afterwards `dmesg | grep ath10k` shows no fallback and'
echo '`iw dev wlan0 link` should be able to hold 5 GHz.'
