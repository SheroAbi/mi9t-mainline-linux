#!/bin/sh
# Reflash the Ubuntu boot image and root filesystem of the base image from
# fastboot (Linux host). U-Boot must already be on the boot partition.
# boot.img and root.img are the base image files (not in this repository),
# next to this script. Everything on userdata is replaced.
sudo fastboot erase cache
sudo fastboot erase userdata

sudo fastboot flash cache ./boot.img
sudo fastboot flash userdata ./root.img

sudo fastboot reboot
