@echo off
rem Bare-device bootstrap from fastboot (Windows): U-Boot to boot, the Ubuntu
rem boot image to cache, the root filesystem to userdata. uboot.img, boot.img
rem and root.img are the base image files (not in this repository), next to
rem this script. dtbo, boot, cache and userdata are erased first.

fastboot erase dtbo
fastboot erase boot
fastboot erase cache
fastboot erase userdata

fastboot flash boot ./uboot.img
fastboot flash cache ./boot.img
fastboot flash userdata ./root.img

fastboot reboot
pause
