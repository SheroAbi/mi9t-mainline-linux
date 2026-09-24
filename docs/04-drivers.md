# The two driver patches

Both live in `kernel/modules/` as complete sources — that is what the running
modules were compiled from — and in `kernel/patches/` as unified diffs against
the pristine upstream copies in `kernel/upstream-reference/`.

`scripts/build/make-patches.sh` regenerates the diffs and then applies each
one to the pristine copy to prove it reconstructs the shipped source byte for
byte.

Every register value below is justified by a vendor source that is checked in
next to the patch: `davinci-vendor-smb5.c` and `davinci-vendor-reg.h` from
Xiaomi's `davinci-p-oss` kernel, `qcom-qg-vendor.c` and `qg-reg.h` from
Qualcomm's. Their URLs and SHA-256 sums are in
`kernel/upstream-reference/sources.json`.

---

## qcom_qg — the fuel gauge

### What was wrong

The upstream driver admits it in a source comment: the percentage is
calculated from the present voltage, and that is meant to be rewritten. Under
load the terminal voltage sags, so the displayed percentage sags with it and
jumps back when the load goes away. It is not a measurement of charge at all.

A second consequence: an `ocv-capacity-table` in the device tree is **not**
evaluated by the upstream driver, so adding one changes nothing.

### What it does now

A coulomb counter, anchored twice.

**Anchor 1 — startup.** On the first reading the driver establishes an open
circuit voltage from the averaged cell voltage minus `I × R` with the
validated SDAM `Rbat` of 118 mΩ. Within the first 120 s of a boot it prefers
the hardware's own power-on measurement registers (`0x70`/`0x72`) when they
are plausible, because those were taken before any load existed. That OCV goes
through `power_supply_batinfo_ocv2cap()` against the device tree's Sunwoda
profile at the measured cell temperature, with a built-in 18-point curve as
the fallback for the recovery device tree that has no profile.

Full capacity comes from the SDAM's learned value when it is between 50 % and
105 % of the design capacity, otherwise from the design capacity.

    SOC initialized from OCV 3918000uV at 31C: 61%, 3987000uAh

**Between readings** the driver integrates `current × elapsed` into
`charge_uams`, clamped to `[0, full]`. Readings are rate-limited to one per
second, and an elapsed interval is capped at 24 h so a long suspend cannot
overflow the arithmetic.

**Anchor 2 — charge termination.** `STATUS_FULL` together with at least
4.3 V pins the counter to full; while charging it is held at or below 99 %, so
the display cannot reach 100 % before the charger says so.

**The safety net.** Three consecutive samples below 3.3 V while discharging
force the counter to zero. A drifting software estimate must never hide a
cell that is actually empty.

**Plausibility windows.** Voltage outside 2.5–4.6 V falls back to the last-ADC
register and then gives up with `-EAGAIN`; a current reading above 10 A is
discarded.

---

## qcom_smbx — the charger

Three defects, all of them SMB5-specific. The driver supports SMB2 and SMB5
and the SMB5 paths had been extrapolated from SMB2.

**The wrong register.** Charge status was read from
`BATTERY_CHARGER_STATUS_7`. On SMB5 the state lives in
`BATTERY_CHARGER_STATUS_2` — `smb5-reg.h` in the vendor tree.

**The wrong state encoding.** SMB5 numbers its states differently from SMB2.
`INHIBIT_CHARGE` (0) and `TERMINATE_CHARGE` (5) both mean *full*, and without
the SMB5 branch they were reported as something else.

**A masked variable that was never read.** `return !!(reg & mask)` tested the
register address instead of the value that had just been read into `val`.

**The prescaler applied twice.** `POWER_SUPPLY_PROP_VOLTAGE_NOW` multiplied
the IIO reading by 16 to undo the board's 1:16 divider — but ADC5 has already
applied the device tree's `qcom,pre-scaling`. The multiplication is gone.

**Online check.** `smb_get_iio_chan()` now gates on `smb_get_prop_usb_online()`
rather than on `smb_is_charging()`, so the input voltage is readable while a
charger is attached but not yet charging.

---

## The device tree

`scripts/build/build-battery-dt.py` adds two things the driver needs and the
mainline tree does not have.

**The battery ID ADC channel**, so the pack can be identified at all:

    /soc@0/spmi@c440000/pmic@0/adc@3100/bat-id@4b
        reg = <0x4b>
        label = "bat_id"
        qcom,pre-scaling = <1 1>

**Xiaomi's measured discharge profile**, translated from the vendor's
`qcom,pc-temp-v2-lut` into the standard Linux battery bindings: six
temperature columns, 56 OCV points each, written as `ocv-capacity-celsius`
plus `ocv-capacity-table-0..5`. The script asserts that the vendor table is
monotonic in both axes before it writes anything.

See `kernel/devicetree/README.md` for how the four device-tree stages relate,
and [01-hardware.md](01-hardware.md) for why the Sunwoda profile is the right
one for this device.
