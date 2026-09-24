# Building

## What gets built

A complete, flashable system in two commands:

```bash
scripts/build/build-kernel.sh      # the kernel package, as a normal user
sudo image/build-image.sh          # U-Boot, the ESP and the Ubuntu root filesystem
```

| | script | output |
|---|---|---|
| the kernel | `scripts/build/build-kernel.sh` | `~/mi9t-build/kernel-fix.tar.gz` |
| the images | `image/build-image.sh` | `dist/image/{uboot,esp,rootfs}.img`, `SHA256SUMS` |
| U-Boot alone | `image/build-uboot.sh` (called by the above) | `dist/image/uboot.img` |
| the device tree | `scripts/build/build-battery-dt.py` | `kernel/devicetree/boot-battery-final.dtb` (checked in) |
| the hardware package | `scripts/build/package-hardware.sh` | `mi9t-hardware-support_1.0.3_arm64.deb` (content checked in) |

## The kernel

```bash
scripts/build/build-kernel.sh
```

On a Windows host, through WSL:

```bash
wsl -d Ubuntu-24.04 -- bash '/mnt/c/<path>/mi9t-mainline-linux/scripts/build/build-kernel.sh'
```

Needs `aarch64-linux-gnu-gcc`, `make`, `bc`, `bison`, `flex` and `git`. The
work directory is `~/mi9t-build` by default (`WORK=` to change it) and is
reused, so a second run is incremental.

### The pinned upstream tree

    https://github.com/sm7150-mainline/linux
    fd78d17954a86ea6ceb0c535e618ea129e09f8dd     branch v7.2 == Linux 7.1.0 final

Pinned on purpose. The branch moves, and the two patches in `kernel/patches/`
apply to this revision.

### The config

`kernel/config-7.1.0-sm7150fix` is the exact config of the running kernel. It
started from postmarketOS's `7.1_rc3` config. The build re-checks the options
that matter after `olddefconfig` and stops if any of them was dropped:

| | |
|---|---|
| `CONFIG_LOCALVERSION="-sm7150fix"` | the kernel release string |
| `CONFIG_USB_G_SERIAL=y` | the serial rescue console; the pmOS package does not set it, which is why `/dev/ttyGS0` appeared on 6.13 and never on 7.1 |
| `CONFIG_EFI_ZBOOT=y` | the bootable artefact is `vmlinuz.efi`, **not** `Image` |
| `CONFIG_BATTERY_QCOM_QG=m`, `CONFIG_CHARGER_QCOM_SMB2=m`, `CONFIG_TYPEC_QCOM_PMIC=y` | charging |
| `CONFIG_SCSI_UFS_QCOM=y`, `CONFIG_BLK_DEV_SD=y`, `CONFIG_EXT4_FS=y` | root without an initramfs |

### The two driver patches

`kernel/modules/qcom_qg.c` and `qcom_smbx.c` are the **authoritative** copies:
the sources the running modules were compiled from. The build installs them
over the tree's own copies.

`kernel/patches/*.patch` are the same thing expressed as diffs against
`kernel/upstream-reference/*-before.c`. Regenerate and verify them with:

```bash
scripts/build/make-patches.sh
```

That script rebuilds each diff and then applies it to the pristine copy to
prove it reconstructs the shipped source byte for byte. It refuses to finish
if it does not.

### Output

`kernel-fix.tar.gz` unpacks to exactly what `scripts/install/install-kernel.sh`
expects:

```
boot/vmlinuz-7.1.0-sm7150fix          (vmlinuz.efi, PE32+ EFI application)
boot/System.map-7.1.0-sm7150fix
boot/config-7.1.0-sm7150fix
dtb/davinci-fix.dtb                   (sm7150-xiaomi-davinci-samsung.dtb)
dtb/davinci-fix-visionox.dtb
extra/modules-7150.conf
lib/modules/7.1.0-sm7150fix/          (~827 modules)
```

There are two panel variants of this phone; `davinci-fix.dtb` is the Samsung
panel, `-visionox` the other.

## The device tree

```bash
python scripts/build/build-battery-dt.py
```

Reads `kernel/devicetree/boot-maintenance.dtb`, adds the ADC battery-ID node
and the translated Sunwoda OCV tables, and writes
`kernel/devicetree/boot-battery-final.dtb` — the tree the installed system
boots. It needs `fdtput` from `device-tree-compiler`, which it reaches through
WSL on a Windows host.

The four stages and how they relate: `kernel/devicetree/README.md`.

## The hardware package

`scripts/build/package-hardware.sh` assembles `mi9t-hardware-support` from
meson builds of hexagonrpc 0.5.0, libssc 0.4.4 and iio-sensor-proxy 3.9, plus
the systemd units, the udev rule, the WirePlumber rule, the ALSA UCM profile
and the sensor configuration from `hardware-package/`.

It runs **on the phone**. `MI9T_STAGE` names a directory holding the three
source trees, each configured and built with meson in `<tree>/build`; the
script's header lists them. The prebuilt package content is checked in under
`hardware-package/`, so rebuilding is only necessary when one of the three is
updated. Our own change to iio-sensor-proxy is
`hardware-package/patches/iio-startup-race.patch`.

`image/build-image.sh` packs the checked-in content into the `.deb` and
installs it into the image.

## The images

```bash
sudo image/build-image.sh
```

Builds everything the phone needs from public sources, pinned:

| Piece | Source |
|---|---|
| Ubuntu 24.04 root filesystem | debootstrap + the common package set of all three phone projects ([`image/common/README.md`](../image/common/README.md)) |
| kernel modules | `kernel-fix.tar.gz` from `build-kernel.sh` (`KERNEL_TGZ=` to point elsewhere) |
| firmware | `sm7150-mainline/firmware-xiaomi-davinci` @ `7c25d3fe`, `a630_sqe.fw` from linux-firmware (SHA-256 checked) |
| pd-mapper | `linux-msm/pd-mapper` v1.1, compiled inside the image, compiler removed again |
| audio and sensors | `hardware-package/` as `mi9t-hardware-support` |
| ESP | FAT32 with Ubuntu's systemd-boot, `vmlinuz-fix` and `DTB=` (default `boot-battery-final.dtb`, Samsung panel) |
| U-Boot | `Gelbpunkt/u-boot` @ `70c600c1` (U-Boot 2025.04, the SM7150 maintainer's tree), `qcom_defconfig qcom-phone.config`, packed with `osm0sis/mkbootimg` @ `17cea80b` — the same build as the U-Boot on the reference phone |

It asks for the password of the user it creates; user name, time zone,
locale, keyboard and an SSH key are environment variables (see
`image/common/README.md`). Nothing optional is installed; see `extras/`.

Build host: Ubuntu 24.04 as root (WSL2 works), with

    sudo apt install debootstrap qemu-user-static binfmt-support e2fsprogs         dosfstools mtools openssl python3 curl git dpkg-dev         gcc-aarch64-linux-gnu make gcc bison flex bc libssl-dev         libgnutls28-dev python3-setuptools python3-pyelftools swig

The work directory (`WORK`, default `/var/tmp/mi9t-image`) must be on a Linux
filesystem.
