# Installing

## What has to be true first

1. **Bootloader unlocked** (Xiaomi Mi Unlock; `fastboot getvar unlocked` → `yes`).
2. **Android platform-tools** on the PC (`fastboot`), and Python 3.
3. The images from [02-building.md](02-building.md) in `dist/image/`:
   `uboot.img`, `esp.img`, `rootfs.img`, `SHA256SUMS`.

## Flashing a bare phone

Power the phone off, then hold **Volume-Down + Power** until fastboot shows.

```bash
python scripts/flash/flash.py                  # checks only, writes nothing
python scripts/flash/flash.py --flash --reboot
```

It checks the images against `SHA256SUMS`, that the phone is an unlocked
`davinci` and that every image fits, then:

| Partition | Image | What it is |
|---|---|---|
| `dtbo` | erased | the Android overlay must not be applied to U-Boot's tree |
| `boot` | `uboot.img` | U-Boot, started by the Xiaomi bootloader like a kernel |
| `cache` (`/dev/sda30`) | `esp.img` | the ESP: systemd-boot, the kernel, the device tree |
| `userdata` (`/dev/sda32`) | `rootfs.img` | Ubuntu |

**Flashing userdata replaces all Android user data.** The Xiaomi bootloader
itself is never written, so fastboot always stays reachable.

## First boot

* The root filesystem grows to the whole of userdata, the phone creates its
  own SSH host keys, and `mi9t-wlan-calibration.service` packs the phone's
  own Wi-Fi calibration from its modem partition. That last step takes
  effect after the **next** reboot (the board data is only sent when the
  Wi-Fi firmware starts).
* GDM logs your user in, GNOME on Wayland. The user and password are the
  ones you gave the image build; root is locked, and root can never log in
  over SSH.
* The USB cable is a serial console (`/dev/ttyGS0`, a COM port on the PC).
* Wi-Fi: from the GNOME menu.

## What the image adds for this phone

On top of the common base system ([`image/common/README.md`](../image/common/README.md)),
only what the hardware needs:

| | |
|---|---|
| the kernel modules of `7.1.0-sm7150fix` | built by `scripts/build/build-kernel.sh` |
| the davinci firmware tree | `sm7150-mainline/firmware-xiaomi-davinci` at the pinned commit, plus a newer `a630_sqe.fw` from linux-firmware |
| `rmtfs`, `tqftpserv`, `pd-mapper`, `qrtr-tools` | the helpers the modem and Wi-Fi firmware need (pd-mapper built from `linux-msm/pd-mapper` v1.1) |
| `mi9t-hardware-support` | the audio DSP and sensor package from `hardware-package/`: speaker, automatic rotation |
| `modules-load.d/sm7150.conf` | the modules that do not load on their own |
| `mi9t-wlan-calibration` + service | the phone's own Wi-Fi calibration, once |
| `serial-getty@ttyGS0` | the USB serial console |

The boot splash is optional: [`extras/boot-splash`](../extras/boot-splash/).

## Updating the kernel on a running phone

Build a new `kernel-fix.tar.gz` ([02-building.md](02-building.md)), copy it to
the phone and run one of the two install scripts as root.

### install-kernel-parallel.sh — the safe variant

```bash
sudo scripts/install/install-kernel-parallel.sh /tmp/kernel-fix.tar.gz
```

Installs the kernel **next to** the existing one, with its own boot entry and
device tree. Nothing existing is overwritten, and the old entry stays the
default. If the new kernel fails, one restart brings the old one back. Use
this one when you are changing something you are not sure about.

### install-kernel.sh — make it the system

```bash
sudo scripts/install/install-kernel.sh /tmp/kernel-fix.tar.gz
```

Makes `7.1.0-sm7150fix` **the** system: kernel and device tree onto the ESP,
one boot entry, no initramfs.

## Rescue

The Xiaomi bootloader is never reflashed by anything here, so fastboot
always works: power off, Volume-Down + Power, flash known-good images again.
The root filesystem survives a reflash of `boot` and `cache`.

### White screen with black stripes

U-Boot ignored the `devicetree` line and gave the kernel the wrong device
tree. Restart; the previous entry comes back on its own.

## Two rules that were learned the hard way

**Kernel first, then the device tree — never the other way round.** A pure DTB
patch (`power-role = "dual"` plus `sink-pdos` and `op-sink-microwatt`) on the
6.13.7 kernel hangs the boot: TCPM goes into dual-role mode, finds no charging
driver to talk to, and stops before USB comes up. White display, black
stripes, no USB enumeration.

**Never make an experiment the default.** Experiments get their own boot
entry; the working one stays `default`, so a plain restart is the way back.
`bootctl set-oneshot` does not help here: U-Boot's EFI variables are
volatile, so choose test entries in the boot menu.

## Back to Android

Flash a stock fastboot ROM for the Mi 9T with Xiaomi's tools. It restores
`boot`, `dtbo`, `cache` and `userdata` along with everything else.
