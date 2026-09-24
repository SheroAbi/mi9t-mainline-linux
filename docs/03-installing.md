# Installing

## On a device that already runs this port

Copy `kernel-fix.tar.gz` to the phone and run one of the two install scripts
as root.

### install-kernel.sh — the production install

```bash
scripts/install/install-kernel.sh /tmp/kernel-fix.tar.gz
```

Makes `7.1.0-sm7150fix` **the** system: kernel and device tree onto the ESP,
one boot entry, no initramfs. Three file operations, no half-finished state.

### install-kernel-parallel.sh — the safe variant

```bash
scripts/install/install-kernel-parallel.sh /tmp/kernel-fix.tar.gz
```

Installs the same kernel **next to** the existing one and builds an initramfs
for it. Nothing existing is overwritten: the old `linux.efi`, its initramfs,
its device tree and its boot entry stay exactly as they are and stay the
default. If the new kernel fails, one restart brings the old one back.

Use this one when you are changing something you are not sure about.

### install-maintenance.sh — the device integration

Installs the boot splash, disables the services of the KlipperOS base image
that fail on a desktop system, leaves `serial-getty@ttyGS0` as the only owner
of the USB serial login, and registers `boot-battery-final.dtb` as its own
boot entry — not as the default. Optional inputs (`DTB=`, `MODULES=`,
`A630_SQE=`) are listed in the script's header.

The audio and sensor integration is the hardware package, see
[02-building.md](02-building.md#the-hardware-package).

### setup-splash.sh — the boot splash

Installs the Plymouth theme from `bootsplash/theme/` and the unit that hands
the splash over to GDM.

## From a bare device

The system underneath is the community **KlipperOS** image for the Mi 9T:
U-Boot for the `boot` partition, an Ubuntu boot image, and an Ubuntu root
filesystem. `scripts/flash/flash.bat` (Windows) and `flash.sh` (Linux) write
that image set over fastboot. The image files are **not** in this repository
— they are several gigabytes and not ours to redistribute.

## Rescue

The bootloader is never reflashed by anything here, so fastboot always works.

**Keep a known-good boot image.** The Ubuntu boot image lives on the
`cache` partition, so one command puts a working kernel back:

```bash
fastboot flash cache boot-fixed.img
```

On the reference phone `boot-fixed.img` is the base image's 6.13 boot image,
repaired: the correct root UUID, no `break=mount`, `loglevel=4`,
`arm_smmu.disable_bypass=0`. Afterwards run `install-kernel-parallel.sh`
again to restore the 7.1 state. **The root filesystem is never touched by
any of this.**

### White screen with black stripes

U-Boot ignored the `devicetree` line and gave the new kernel the old device
tree. Restart; the previous entry comes back on its own.

## Two rules that were learned the hard way

**Kernel first, then the device tree — never the other way round.** A pure DTB
patch (`power-role = "dual"` plus `sink-pdos` and `op-sink-microwatt`) on the
6.13.7 kernel hangs the boot: TCPM goes into dual-role mode, finds no charging
driver to talk to, and stops before USB comes up. White display, black
stripes, no USB enumeration.

**Never make an experiment the default.** Experiments get their own boot
entry; the working one stays `default`, so a plain restart is the way back.
