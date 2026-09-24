# Device layer

What the Mi 9T's image carries on top of the common base system
([`../image/common/README.md`](../image/common/README.md)): only what this
phone's hardware needs. `image/build-image.sh` copies `base/` into the image,
installs `packages.txt` and runs `configure.sh` inside it.

| | |
|---|---|
| `packages.txt` | systemd-boot, `rmtfs`, `tqftpserv`, `qrtr-tools`, `linux-firmware`, the libraries of the audio/sensor package, and a compiler for pd-mapper that is removed again after the build |
| `configure.sh` | builds and enables pd-mapper, installs `mi9t-hardware-support` (from `../hardware-package/`), enables `rmtfs`, `tqftpserv`, the USB serial console and the Wi-Fi calibration, writes `/etc/fstab` |
| `base/etc/modules-load.d/sm7150.conf` | modules that do not reliably load on their own |
| `base/usr/local/sbin/mi9t-wlan-calibration` + service, `base/usr/local/lib/mi9t/ath10k-board.py` | packs the phone's own Wi-Fi calibration (`bdwlan.bin` from its modem partition) into `board-2.bin`, once, on the first boot |

The kernel modules and the davinci firmware tree are added by the image build
itself. Optional features live in [`../extras/`](../extras/).
