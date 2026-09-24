# Device trees — how the four files relate

The Mi 9T boots through U-Boot + systemd-boot. The boot entry names its own
`devicetree`, so every kernel can carry a different one. These four are the
stages that produced the tree the device runs today.

| File | Produced by | Contains |
|---|---|---|
| `davinci-fix.dtb` | `scripts/build/build-kernel.sh` (from the pinned upstream tree) | `sm7150-xiaomi-davinci.dtb` for the Samsung panel variant |
| `davinci-fix-visionox.dtb` | same build | the Visionox panel variant of the same board |
| `boot-maintenance.dtb` | hand-edited on the device during a repair session | `davinci-fix.dtb` plus the maintenance fixes; kept as the binary input for the next stage because no generator for it survived |
| `boot-battery-final.dtb` | `scripts/build/build-battery-dt.py` | `boot-maintenance.dtb` plus Xiaomi's measured Sunwoda discharge profile as standard `ocv-capacity-table-*` bindings — **this is the tree the installed system uses** |

`davinci-fix.dtb` is byte-identical to the tree that was read back off the
device after the first install, which is how the chain above was verified.

Inspect any of them with:

    dtc -I dtb -O dts boot-battery-final.dtb | less

Regenerate the last stage (needs `fdtput` from `device-tree-compiler`, reached
through WSL on a Windows host):

    python scripts/build/build-battery-dt.py
