# 📱 Ubuntu on the Xiaomi Mi 9T

**A normal Ubuntu 24.04 with GNOME on the Xiaomi Mi 9T / Redmi K20, on mainline Linux 7.1.**
Not Android with Linux in a box, not a compatibility layer: the phone boots a
current kernel, and everything above it is the same Ubuntu you would put on a laptop.

- 🔋 **An honest battery level:** a fuel gauge that counts the charge that really flows, instead of a percentage that jumps with every tap.
- ⚡ **Correct charging:** the right charger registers, a charging icon that changes on plug and unplug.
- 🖥️ **Fast desktop:** GNOME at the full 1080x2340, rendered by the Adreno 618 GPU (freedreno). Boots to the desktop in about 33 seconds.
- 🔊 **Sound and rotation:** speaker at normal volume, the screen turns when you turn the phone.
- 📶 **Proper Wi-Fi:** 2.4 and 5 GHz on the phone's own calibration, about twice the throughput.
- 🛟 **Always a way back:** a serial rescue console on the USB cable on every boot; the Xiaomi bootloader is never touched.
- 🔒 **Yours:** you build it yourself from public sources. No default password, root locked, SSH keys made on the phone.
- 💸 **A free home server:** 8 cores, 6 GB RAM, a few watts, a built-in UPS. Run your bot, AI agent or home automation on it instead of renting a VPS.

> Only for the **Mi 9T / Redmi K20** (davinci, Snapdragon 730). The Mi 9T
> **Pro** is a different phone with a different chip, and nothing here applies to it.
> *(Hobby project, not affiliated with Xiaomi.)*

---

## ✨ What works

Everything in this table was confirmed on the device.

| Subsystem | State |
|---|---|
| Boot | U-Boot → systemd-boot → kernel, no initramfs, ~33 s to the desktop |
| CPU | all 8 cores, `schedutil`, no overclock, thermal limits intact |
| GPU / display | Adreno 618 with freedreno, 1080x2340 @ 60 Hz, hardware-accelerated GNOME |
| Battery | percentage from coulomb counting, charging icon changes on plug and unplug |
| Charging | works, through the patched SMB5 driver |
| Audio | speaker at normal volume, including in a browser |
| Sensors | automatic rotation with touch following it |
| Wi-Fi | `ath10k_snoc`, 2.4 and 5 GHz, with the phone's own calibration |
| Serial console | `/dev/ttyGS0` over USB on every boot |
| Firmware | all 485 device firmware files match the upstream davinci firmware tree |

**Not solved (yet):** USB-C role switching (charging works, powering other
devices does not), long-term accuracy of the new battery counter over many
partial charges. Cameras and the mobile network are whatever the underlying
kernel provides. Details: [docs/05-known-issues.md](docs/05-known-issues.md).

---

## 🛠️ Build it yourself

Everything is built from this repository and public sources: kernel, U-Boot,
systemd-boot, firmware and a clean Ubuntu. No image is downloaded from us.

**You need:** a Mi 9T with an **unlocked bootloader** (Xiaomi Mi Unlock), a
**Linux** build host (Ubuntu 24.04 on a PC or in a VM; WSL2 works too),
`fastboot` and Python 3.

```bash
git clone https://github.com/SheroAbi/mi9t-mainline-linux.git
cd mi9t-mainline-linux

# 0. host packages (once)
sudo apt install build-essential gcc-aarch64-linux-gnu bc bison flex libssl-dev \
    libelf-dev git python3 debootstrap qemu-user-static binfmt-support \
    e2fsprogs dosfstools mtools openssl curl libgnutls28-dev \
    python3-setuptools python3-pyelftools swig

# 1. the kernel package (as your normal user)
scripts/build/build-kernel.sh

# 2. U-Boot, the ESP and the Ubuntu root filesystem (asks for your password)
sudo image/build-image.sh
```

Good to know:
- 📁 The kernel builds in `~/mi9t-build` (`WORK=` to move it); a second run is incremental.
- 📌 The upstream kernel tree, firmware and U-Boot are **pinned** to exact commits, so the build is reproducible.
- 🧩 The output lands in `dist/image/`: `uboot.img`, `esp.img`, `rootfs.img` and `SHA256SUMS`.

---

## 📲 Install

Power the phone off, then hold **Volume-Down + Power** until fastboot shows:

```bash
python3 scripts/flash/flash.py                   # checks only, writes nothing
python3 scripts/flash/flash.py --flash --reboot  # write and start
```

It checks the images against `SHA256SUMS`, that the phone is an unlocked
`davinci` and that every image fits, and never reboots after a failed write.

> ⚠️ **This erases all Android user data** (`userdata`). The Xiaomi
> bootloader itself is never written, so fastboot always stays reachable.
> Back to Android: flash a stock fastboot ROM.

**First boot:** the root filesystem grows to the whole partition, the phone
makes its own SSH keys and packs its own Wi-Fi calibration (active after the
next reboot), then GNOME logs your user in. Wi-Fi is set up from the GNOME menu.

**Kernel updates on a running phone:** `sudo scripts/install/install-kernel-parallel.sh kernel-fix.tar.gz`
installs a new kernel *next to* the old one (a restart brings the old one back).
Details: [docs/03-installing.md](docs/03-installing.md).

---

## 🧩 Extras (optional)

```bash
sudo extras/install.sh                    # list them
sudo extras/install.sh boot-splash        # install one; --remove takes it out again
```

| Extra | What it does |
|---|---|
| [boot-splash](extras/boot-splash/) | a Plymouth boot animation (spinning ring, progress in percent) handed over cleanly to GNOME |

---

## 🛟 Troubleshooting

| Problem | Fix |
|---|---|
| `no phone in fastboot mode` | Power off, then hold Volume-Down + Power. Check `fastboot devices`. |
| `bootloader is locked` | Unlock it with Xiaomi Mi Unlock first. |
| White screen with black stripes | U-Boot used the wrong device tree. Restart; the previous boot entry comes back on its own. |
| Boot hangs after a device-tree-only change | Kernel first, then the device tree, never the other way round ([docs/03-installing.md](docs/03-installing.md)). |
| Wi-Fi slow, 5 GHz unusable after the first boot | The phone's own calibration is packed on the first boot; reboot once more. |
| Battery percentage looks wrong | Compare the `SOC initialized from OCV ...` line in `dmesg` with the measured cell voltage ([docs/05-known-issues.md](docs/05-known-issues.md)). |

---

## 🔬 Under the hood

```
SoC        Qualcomm SM7150 (Snapdragon 730)
CPU        6x Kryo 470 Silver @ 1.8048 GHz  +  2x Kryo 470 Gold @ 2.208 GHz
GPU        Adreno 618, freedreno, OpenGL ES 3.2, up to 610 MHz
Display    1080x2340 @ 60 Hz AMOLED
Memory     ~5.4 GiB visible to Linux, plus 2 GiB ZRAM (LZ4)
Kernel     7.1.0-sm7150fix (sm7150-mainline/linux @ fd78d179 + this port)
Userland   Ubuntu 24.04 LTS arm64, GNOME
```

**Boot chain:** Xiaomi bootloader (never reflashed) → U-Boot on `boot` →
systemd-boot on the ESP (`/dev/sda30`) → `vmlinuz-fix` + device tree →
Ubuntu on `/dev/sda32`. The kernel has UFS, SCSI disk and ext4 built in and
mounts root itself, no initramfs.

**The battery fix:** the upstream driver took the percentage straight from
the battery's voltage at that moment, and voltage drops whenever the phone
works hard, so the number was more a load meter than a fuel gauge. The
driver here counts the charge that flows in and out, anchored to a resting
voltage estimate at boot and to the charger's own "full" signal. Every
register value is traced back to Xiaomi's and Qualcomm's published kernel
sources, kept next to the patches so anyone can check them.

### 🧗 Hurdles that were overcome

<details>
<summary>What was broken, why, and how it was fixed (click to open)</summary>

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

</details>

### 🗂️ Repository layout

```text
kernel/
  config-7.1.0-sm7150fix     the exact kernel config
  modules/                   qcom_qg.c, qcom_smbx.c: the sources the running modules were built from
  patches/                   the same two drivers as unified diffs
  upstream-reference/        pristine upstream copies + the vendor sources that justify each value
  devicetree/                the four device-tree stages, see its README
hardware-package/            mi9t-hardware-support (audio DSP, sensors)
image/                       build U-Boot, the ESP and the root filesystem (common/ is shared by all three phones)
device/                      the hardware layer of the image
extras/                      optional features, installed on request
scripts/build/               kernel, device tree, hardware package, patches
scripts/install/             update the kernel on a running phone
scripts/flash/               flash the images onto a phone in fastboot
docs/                        everything above in detail
```

### 📚 Documentation

| | |
|---|---|
| [01-hardware.md](docs/01-hardware.md) | the device, the boot chain, the partitions, the battery |
| [02-building.md](docs/02-building.md) | the pinned upstream tree, the toolchain, the kernel and the images |
| [03-installing.md](docs/03-installing.md) | flashing, first boot, kernel updates, recovery |
| [04-drivers.md](docs/04-drivers.md) | the charging and gauge patches, in detail |
| [05-known-issues.md](docs/05-known-issues.md) | what still does not work |

---

## 🙏 Acknowledgements

This port stands on the [sm7150-mainline](https://github.com/sm7150-mainline)
project: its kernel tree, its davinci firmware repository and its U-Boot
build, which this repository pins and reproduces.

**Same idea, other phones:**
[Samsung Galaxy S9+ (Exynos 9810)](https://github.com/SheroAbi/galaxy-s9plus-mainline-linux) ·
[Xiaomi Redmi 8 (Snapdragon 439)](https://github.com/SheroAbi/redmi8-mainline-linux)

---

## 🇩🇪 Kurz auf Deutsch

Dieses Projekt bringt ein **normales Ubuntu 24.04 mit GNOME** auf das Xiaomi
Mi 9T / Redmi K20 (nicht die Pro-Version): aktueller Mainline-Kernel 7.1,
kein Android darunter. Akkuanzeige und Laden wurden repariert, Ton, Drehung
und WLAN mit der eigenen Kalibrierung laufen. Ideal als stromsparender
Heimserver statt VPS. Gebaut wird alles selbst auf einem Linux-Rechner:
`scripts/build/build-kernel.sh` → `sudo image/build-image.sh` →
`python3 scripts/flash/flash.py --flash --reboot` im Fastboot-Modus.
**Achtung:** Die Android-Nutzerdaten werden gelöscht.

---

## 📄 License

GPL-2.0-only for the kernel patches and device trees; see [LICENSE](LICENSE).
Third-party and vendor components are listed in
[THIRD-PARTY.md](THIRD-PARTY.md). The hardware package bundles software under
its own licences, listed in
`hardware-package/usr/share/doc/mi9t-hardware-support/copyright`.

This is a hobby project and comes without any warranty. Flashing a phone can
go wrong; you do it at your own risk.
