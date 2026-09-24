#!/bin/bash
# Mi 9T: hardware configuration, run inside the image during the build
# (image/build-image.sh). Only what this phone needs to work; the optional
# features are in extras/.
set -euo pipefail

# pd-mapper (protection-domain mapper, needed by the modem and Wi-Fi), from
# the source image/build-image.sh placed in /tmp/pd-mapper.
make -C /tmp/pd-mapper
make -C /tmp/pd-mapper install prefix=/usr/local
apt-get -y purge gcc make libc6-dev libqrtr-dev liblzma-dev
apt-get -y autoremove --purge

# The audio and sensor package (hexagonrpc, libssc, iio-sensor-proxy 3.9,
# the speaker profile, the sensor configuration).
apt-get -y --no-install-recommends install /tmp/mi9t-hardware-support.deb

systemctl enable pd-mapper.service rmtfs.service tqftpserv.service \
	serial-getty@ttyGS0.service mi9t-wlan-calibration.service

# The ESP (systemd-boot, kernel, device tree) for kernel updates later.
mkdir -p /boot/efi
cat > /etc/fstab <<'FSTAB'
# The kernel mounts /dev/sda32 (userdata) as root itself: no initramfs.
/dev/sda32  /          ext4  defaults,noatime              0 0
/dev/sda30  /boot/efi  vfat  defaults,noatime,umask=0077,nofail  0 0
FSTAB

dconf update
