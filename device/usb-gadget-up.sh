#!/bin/sh
# Restores the USB serial console on a kernel without the legacy g_serial.
#
# Why: the 6.13 kernel (and this project's 7.1.0-sm7150fix) has
# CONFIG_USB_G_SERIAL=y, a built-in legacy gadget, so /dev/ttyGS0 appears by
# itself. postmarketOS' 7.1 package has "# CONFIG_USB_G_SERIAL is not set";
# there the gadget has to be assembled through configfs, which this script
# does. On a kernel with g_serial it does nothing.
#
# VID/PID are deliberately the legacy gadget's (0525:a4a7), so Windows reuses
# the same usbser.sys binding and the COM port comes back without installing
# a driver.

set -e

# With g_serial, ttyGS0 already exists. Then there is nothing to do - and a
# second gadget on the same UDC would only disturb the working one.
[ -e /dev/ttyGS0 ] && exit 0

modprobe libcomposite 2>/dev/null || true
modprobe usb_f_acm    2>/dev/null || true

CFG=/sys/kernel/config
mountpoint -q "$CFG" || mount -t configfs none "$CFG" 2>/dev/null || true
[ -d "$CFG/usb_gadget" ] || exit 0

G="$CFG/usb_gadget/g1"
[ -d "$G" ] || mkdir -p "$G"
cd "$G"

echo 0x0525 > idVendor
echo 0xa4a7 > idProduct
echo 0x0200 > bcdUSB
echo 0x0100 > bcdDevice

mkdir -p strings/0x409
echo "0123456789"        > strings/0x409/serialnumber
echo "Linux"             > strings/0x409/manufacturer
echo "Gadget Serial"     > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "ACM"   > configs/c.1/strings/0x409/configuration
echo 250     > configs/c.1/MaxPower

mkdir -p functions/acm.GS0
[ -e configs/c.1/acm.GS0 ] || ln -s functions/acm.GS0 configs/c.1/

# Bind to the first USB device controller
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
[ -n "$UDC" ] || exit 0
if [ -z "$(cat UDC 2>/dev/null)" ]; then
    echo "$UDC" > UDC
fi
exit 0
