# The device and its boot chain

Xiaomi Mi 9T, sold as Redmi K20 in some markets. Xiaomi codename **davinci**,
SoC **SM7150** (Snapdragon 730). The Mi 9T **Pro** is a different SoC
(SM8150) and none of this applies to it.

## Partitions

| Partition | Block device | Filesystem | Holds |
|---|---|---|---|
| `boot` | | | U-Boot |
| `cache` (the ESP) | `/dev/sda30` | vfat | systemd-boot, the kernel, the device tree |
| `userdata` (root) | `/dev/sda32` | ext4 | Ubuntu 24.04 |

## Boot chain

    Xiaomi bootloader
      -> U-Boot            (flashed to the boot partition)
        -> systemd-boot    (on the ESP, /dev/sda30)
          -> vmlinuz-fix + sm7150-xiaomi-davinci-battery-final.dtb

The image build writes one entry, `loader/entries/ubuntu.conf`, with a
3-second menu. Boot to a usable desktop takes about
33 seconds, firmware and services included.

There is **no initramfs**. The UFS controller, SCSI disk and ext4 are built
into the kernel (`CONFIG_SCSI_UFS_QCOM=y`, `CONFIG_BLK_DEV_SD=y`,
`CONFIG_EXT4_FS=y`), so the kernel mounts its own root. That removed the
20 MB artefact that had to be rebuilt on every install, and it was the
flakiest link in the chain.

### Two boot-chain facts that each cost a failed attempt

**U-Boot honours the `devicetree` line in a systemd-boot entry.** Two kernels
can therefore live side by side, each with its own device tree. Leave the line
out and U-Boot loads `dtbs/qcom/sm7150-xiaomi-davinci.dtb` — swap that file
and the other kernel stops booting, with a white screen and black stripes.

**`bootctl set-oneshot` does not work on this device.** U-Boot's EFI variables
are volatile: `LoaderEntryOneShot` is gone after the restart and the default
entry boots. Test runs only work through the menu (with a timeout) or by
changing `default` in `loader.conf`.

## Firmware

The image build installs the
[pinned davinci firmware tree](https://github.com/sm7150-mainline/firmware-xiaomi-davinci/tree/7c25d3fe5883f25f8f068e89c6442b4c608835f0)
(485 files; the reference phone matches it file for file), under
`qcom/sm7150/xiaomi/davinci/`, where the 7.1 kernel looks.

On an older install that has the firmware under `qcom/sm7150/davinci/`, one
symlink fixes Wi-Fi, adsp, cdsp and the modem all at once
(`install-kernel.sh` sets it):

    ln -sfn ../davinci /lib/firmware/qcom/sm7150/xiaomi/davinci

## Memory

About 5.4 GiB is visible to Linux. The rest of the physical memory is reserved
for firmware and hardware and must not be handed back wholesale. On top of
that there is 2 GiB of ZRAM with LZ4 (`/etc/systemd/zram-generator.conf`,
`vm.swappiness=100`); swapping to flash is not enabled in this kernel.

## The battery

The physical battery ID measured 750908..752335 uV, which is about
66.8..67.0 kohm with Xiaomi's 100 kohm / 1.875 V identification circuit. That
identifies the **68 kohm Sunwoda** pack, not the 100 kohm Coslight one — which
is why `scripts/build/build-battery-dt.py` translates Xiaomi's Sunwoda
discharge profile, and not the other, into the device tree.

Values that end up in the `/battery` node:

| Property | Value |
|---|---|
| `device-chemistry` | `lithium-ion` |
| `bti-resistance-ohm` | 68000 (±10 %) |
| `factory-internal-resistance-micro-ohms` | 118000 |
| `ocv-capacity-celsius` + `ocv-capacity-table-N` | 6 temperatures, 56 OCV points each, from `batterydata-F10-sunwoda-4000mah.dtsi` |
