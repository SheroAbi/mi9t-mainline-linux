# Ubuntu on the Xiaomi Mi 9T

This is a Xiaomi Mi 9T (sold as Redmi K20 in some countries) that runs a
normal Ubuntu 24.04 with the GNOME desktop instead of Android. Not Android
with Linux in a box, and not a compatibility layer: the phone boots a current
mainline Linux kernel, and everything above it is the same Ubuntu you would
put on a laptop.

Why would you want that? Because an old phone in a drawer is a small, quiet
ARM64 computer with eight cores, 6 GB of RAM, fast storage, Wi-Fi and a
built-in battery that bridges power cuts. Many people rent a VPS to run a
self-hosted AI agent, a bot, a home automation hub or a small web service.
This phone can be that machine instead: it sits on your desk, it costs
nothing per month, it draws a few watts, and your data stays at home. You
reach it over SSH like any server, and it still has a touchscreen and a full
desktop when you want to look at it. This repository shows, step by step,
how to turn such a device into your own Linux machine, and the same way of
working carries over to other old phones.

The Mi 9T is a good phone for this. Its Snapdragon 730 is fast enough for a
real desktop, and the community around sm7150-mainline has done the hard
groundwork of bringing the chip into mainline Linux. What was missing were
the things you only notice when you actually live with the device: the
battery percentage jumped up and down with every tap on the screen, charging
was reported wrong, there was no serial rescue console, Wi-Fi ran on another
phone's calibration data, the speaker was not set up, and the screen did not
rotate. This project fixes those, one at a time, and writes down why each
fix is correct.

The result is a phone that boots straight into GNOME in about half a minute,
shows an honest battery level and a correct charging icon, plays sound
through its speaker, rotates the screen when you turn it, and carries a
rescue console on the USB cable that is always there. The GPU renders the
desktop at the panel's full resolution with the open-source freedreno
driver. Nothing is overclocked and no thermal limit is switched off.

You build the system yourself, from this repository and public sources
only: the kernel, the bootloader chain (U-Boot and systemd-boot), the
firmware and a clean, ordinary Ubuntu. It is the same base system as the two
sister projects for the Galaxy S9+ and the Redmi 8, plus only the few pieces
this phone's hardware needs. Nothing of ours is preinstalled; the boot
animation we made is kept separate as an extra you can add. The image has no
default password: you choose one when you build it, root is locked, and
every phone creates its own SSH keys on its first boot.

The most interesting part is the battery. The upstream driver computed the
percentage directly from the battery's voltage at that very moment, and
voltage drops whenever the phone works hard, so the number was more a load
meter than a fuel gauge. The driver here counts the charge that actually
flows in and out, anchored to a proper resting-voltage estimate at boot and
to the charger's own "full" signal. Every register value in the fixes is
traced back to Xiaomi's and Qualcomm's published kernel sources, which are
kept next to the patches so anyone can check them.

There are limits. USB-C role negotiation is unresolved: charging works, but
switching between charging and powering other devices is not solved. The
long-term accuracy of the new battery counter over many partial charges has
not been measured. Parts this project did not touch, such as the cameras or
the mobile network, are simply whatever the underlying kernel provides. The
Mi 9T **Pro** is a different phone with a different chip, and nothing here
applies to it.

This repository is for people who own a Mi 9T and want a working Linux on
it, and for people porting similar Snapdragon phones who want to see how the
charging and fuel-gauge problems were solved.

---

## Technical overview

```
SoC        Qualcomm SM7150 (Snapdragon 730)
CPU        6x Kryo 470 Silver @ 1.8048 GHz  +  2x Kryo 470 Gold @ 2.208 GHz
GPU        Adreno 618, freedreno, OpenGL ES 3.2, up to 610 MHz
Display    1080x2340 @ 60 Hz AMOLED
Memory     ~5.4 GiB visible to Linux, plus 2 GiB ZRAM (LZ4)
Kernel     7.1.0-sm7150fix (sm7150-mainline/linux @ fd78d179 + this port)
Userland   Ubuntu 24.04 LTS arm64, GNOME
```

### Boot chain

```
Xiaomi bootloader (never reflashed)
  -> U-Boot on the boot partition
    -> systemd-boot on the ESP (/dev/sda30)
      -> vmlinuz-fix + sm7150-xiaomi-davinci-battery-final.dtb
        -> Ubuntu on /dev/sda32, no initramfs
```

The kernel has UFS, SCSI disk and ext4 built in and mounts root itself.
Boot to a usable desktop takes about 33 seconds.

### What works

Everything in this table was confirmed on the device.

| Subsystem | State |
|---|---|
| Boot | U-Boot → systemd-boot → kernel, single entry, no initramfs, ~33 s to the desktop |
| CPU | all 8 cores, `schedutil`, no overclock, thermal limits intact |
| GPU | Adreno 618 with freedreno, hardware-accelerated GNOME at full native resolution |
| Display | 1080x2340 @ 60 Hz |
| Battery | percentage from coulomb counting, charging icon changes on plug and unplug |
| Charging | works, through the patched SMB5 driver |
| Audio | speaker at normal volume, including in a browser |
| Sensors | automatic rotation with touch following it |
| Wi-Fi | `ath10k_snoc`, 2.4 and 5 GHz, with the phone's own calibration |
| Serial console | `/dev/ttyGS0` over USB on every boot |
| Boot splash | optional extra: own Plymouth theme, handed over to GNOME cleanly |
| Firmware | all 485 device firmware files match the upstream davinci firmware tree |

### Hurdles that were overcome

| Symptom | Cause | Fix |
|---|---|---|
| Battery percentage jumps with every load change | upstream `qcom_qg` derives the percentage from the instantaneous terminal voltage (its own comment says so); an `ocv-capacity-table` in the DT is not even read | coulomb counter anchored to an OCV estimate at boot (I×R-compensated, Xiaomi's Sunwoda profile) and to charge termination, with a 3.3 V safety net |
| Charging state wrong | `qcom_smbx` read `BATTERY_CHARGER_STATUS_7`; on SMB5 the state is in `STATUS_2`, with a different state encoding | SMB5 register and encoding, taken from Xiaomi's `smb5-reg.h` |
| `voltage_now` 16x too high | the IIO reading was multiplied to undo the board's 1:16 divider, which ADC5 had already applied | the multiplication is gone |
| A charger status check was meaningless | `!!(reg & mask)` tested the register address, not the value just read | test the value |
| No serial rescue console on 7.1 | postmarketOS' 7.1 config drops `CONFIG_USB_G_SERIAL` | set it; `/dev/ttyGS0` exists on every boot |
| No Wi-Fi, no modem on 7.1 | 7.1 looks for firmware under `qcom/sm7150/xiaomi/davinci/`, it is installed under `qcom/sm7150/davinci/` | one symlink |
| Wi-Fi slow, 5 GHz unusable | linux-firmware has no `xiaomi_davinci` board data, ath10k fell back to a reference board's calibration | pack the phone's own `bdwlan.bin` into `board-2.bin` (the name needs the chip id in **hex**); about twice the throughput, 5 GHz at 80 MHz |
| White screen with black stripes after a kernel swap | without a `devicetree` line U-Boot loads a shared DTB path | every boot entry names its own device tree |
| Test boots always ended in the default entry | U-Boot's EFI variables are volatile, `bootctl set-oneshot` has no effect | test entries are chosen in the boot menu; experiments are never the default |
| Boot hangs after a DT-only change | TCPM dual-role mode without a charging driver stops before USB comes up | rule: kernel first, then the device tree |
| Rotation could stay off after boot | iio-sensor-proxy race: SSC discovery runs a nested main loop, clients claimed the sensor before it was open | `iio-startup-race.patch` |
| The flakiest part of every install was the initramfs | 20 MB rebuilt on every install | UFS/SCSI/ext4 built in, no initramfs at all |

### Build your own system

Everything is built from this repository and public sources; no image is
downloaded from us. You need the phone with an unlocked bootloader, a Linux
build host (Ubuntu 24.04, a VM or WSL2 works), `fastboot` and Python 3.

```bash
# 1. the kernel package (aarch64 cross toolchain)
scripts/build/build-kernel.sh

# 2. U-Boot, the ESP (systemd-boot + kernel + device tree) and the Ubuntu
#    root filesystem: asks for your password
sudo image/build-image.sh

# 3. phone in fastboot (Volume-Down + Power): checks first, then writes
python scripts/flash/flash.py
python scripts/flash/flash.py --flash --reboot
```

What the image contains: the common base system of all three phone projects
([`image/common/README.md`](image/common/README.md): Ubuntu 24.04, GNOME,
Firefox, SSH, no default password, root locked, SSH keys made on the phone),
plus this phone's hardware layer: the kernel modules, the pinned davinci
firmware, the Qualcomm helpers for modem and Wi-Fi, the audio and sensor
package, and the phone's own Wi-Fi calibration on the first boot (see
[`device/`](device/)). Details: [docs/02-building.md](docs/02-building.md),
[docs/03-installing.md](docs/03-installing.md).

### Extras (optional, never installed by the image build)

```bash
sudo extras/install.sh                    # list them
sudo extras/install.sh boot-splash        # install one; --remove takes it out again
```

| Extra | What it does |
|---|---|
| [boot-splash](extras/boot-splash/) | a Plymouth boot animation (spinning ring, progress in percent) handed over cleanly to GNOME |

### Repository layout

```
kernel/
  config-7.1.0-sm7150fix     the exact kernel config
  modules/                   qcom_qg.c, qcom_smbx.c -- the sources the running
                             modules were compiled from
  patches/                   the same two drivers as unified diffs
  upstream-reference/        the pristine upstream copies the diffs apply to,
                             plus the vendor sources that justify each value
  devicetree/                the four device-tree stages, see its README
hardware-package/            mi9t-hardware-support (audio DSP, sensors)
image/                       build U-Boot, the ESP and the root filesystem
                             (common/ is shared by all three phones)
device/                      the hardware layer of the image
extras/                      optional features, installed on request
scripts/
  build/                     kernel, device tree, hardware package, patches
  install/                   update the kernel on a running phone
  flash/                     flash the images onto a phone in fastboot
docs/                        everything above in detail
```

### Documentation

| | |
|---|---|
| [01-hardware.md](docs/01-hardware.md) | the device, the boot chain, the partitions, the battery |
| [02-building.md](docs/02-building.md) | the pinned upstream tree, the toolchain, the kernel and the images |
| [03-installing.md](docs/03-installing.md) | flashing, first boot, kernel updates, recovery |
| [04-drivers.md](docs/04-drivers.md) | the charging and gauge patches, in detail |
| [05-known-issues.md](docs/05-known-issues.md) | what still does not work |

### Acknowledgements

This port stands on the [sm7150-mainline](https://github.com/sm7150-mainline)
project: its kernel tree, its davinci firmware repository and its U-Boot
build, which this repository pins and reproduces.

### Related projects

The same idea, Ubuntu on mainline Linux, on two other phones:

* [Samsung Galaxy S9+ (Exynos 9810)](https://github.com/SheroAbi/galaxy-s9plus-mainline-linux)
* [Xiaomi Redmi 8 (Snapdragon 439)](https://github.com/SheroAbi/redmi8-mainline-linux)

### Licence

GPL-2.0-only for the kernel patches and device trees; see [LICENSE](LICENSE).
Third-party and vendor components are listed in
[THIRD-PARTY.md](THIRD-PARTY.md). The hardware package bundles software under
its own licences, listed in
`hardware-package/usr/share/doc/mi9t-hardware-support/copyright`.

This is a hobby project and comes without any warranty. Flashing a phone can
go wrong; you do it at your own risk.
