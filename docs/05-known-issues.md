# Known issues

## USB-C power role

`qcom_smbx` sets `EN_TRY_SNK` in hardware, but TCPM follows the device tree
and wins.

* With `power-role = "source"` the port reports `usb_type=[Unknown]`,
  `voltage_now=0`, `online=0` — it never sees input voltage.
* With `power-role = "sink"` (plus `try-power-role`, `sink-pdos`,
  `op-sink-microwatt`) the boot hangs, even with the charging driver bound.
  The log says why: `usb@a600000: Fixed dependency cycle(s) with
  typec@1500/connector` — the USB controller and the connector wait for each
  other.

Charging works in the current configuration, but dual-role negotiation is
unresolved. Two untried ideas: disable `typec@1500` entirely and let the SMB
hardware do it alone, or test on a real charger rather than a PC port —
everything so far was measured on PC USB, which is an SDP port.

## Wi-Fi ran on another board's calibration

The device tree asks ath10k for the calibration variant `xiaomi_davinci`, and
linux-firmware has no such entry, so the WCN3990 ran on the reference data
`bus=snoc,qmi-board-id=ff`: one stream at 20 MHz on 2.4 GHz, 1.4 MB/s to the
phone, 5 GHz at -81 dBm and practically unusable, where a Galaxy S9+ on the
same desk carried 7 MB/s. The phone's own calibration is `bdwlan.bin` in the
stock modem partition. `scripts/install/install-wlan-calibration.sh` packs it
into a copy of board-2.bin under `/lib/firmware/updates` (reboot required;
the board data is sent only when the Wi-Fi firmware starts). Measured after:
3.0-3.7 MB/s to the phone, 3.5-4.0 MB/s from it, 5 GHz at 80 MHz. Note the
board name uses the chip id in hex (`qmi-chip-id=140`).

## ocv-capacity-table in the device tree is ignored by the upstream driver

Upstream `qcom_qg` does not read it. Putting the table in the device tree
alone changes nothing; the patched driver in `kernel/modules/` is what
evaluates it, through `power_supply_batinfo_ocv2cap()`. Worth knowing before
spending a session on the DTB.

## bootctl set-oneshot has no effect

U-Boot's EFI variables are volatile. See [01-hardware.md](01-hardware.md).

## The battery display looked jumpy, and the hardware was fine

The jumping was load noise: the upstream gauge computed the percentage from
the instantaneous terminal voltage. That is fixed — see
[04-drivers.md](04-drivers.md) — and the replacement has no runtime knobs. If
the reading ever looks wrong again, start from the line the gauge logs once at
startup:

    SOC initialized from OCV <uV> at <C>: <n>%, <uAh>

and compare that OCV against the measured cell voltage before assuming a
hardware fault.

## Long-cycle gauge accuracy is untested

The coulomb counter is anchored on charge termination and on the OCV estimate
taken at startup. Over many cycles without a full charge the integrated value
will drift, and how far has not been measured.

## Things deliberately left alone

* The Android bootloader is not reflashed by anything in this project.
* No overclocking, and no thermal limits disabled.
* About 300 Ubuntu package updates were held back rather than applied
  wholesale. GNOME Shell, Mutter, PipeWire, WirePlumber, systemd and Mesa are
  at their available candidates; Mesa comes from the Kisak PPA of the base
  image.
