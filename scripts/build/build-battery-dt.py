#!/usr/bin/env python3
"""Translate Xiaomi's measured Sunwoda discharge profile to Linux battery bindings.

    python3 scripts/build/build-battery-dt.py

Reads kernel/devicetree/boot-maintenance.dtb and writes
kernel/devicetree/boot-battery-final.dtb. Needs `fdtput` from
device-tree-compiler; on Windows it is run through WSL (WSL_DISTRO, default
Ubuntu-24.04).

The physical battery ID was measured at 750908..752335 uV, approximately
66.8..67.0 kohm with the vendor's 100 kohm / 1.875 V identification circuit.
This identifies the 68 kohm Sunwoda profile, not the 100 kohm Coslight pack.
Check yours before using this tree on another phone.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
BASE = Path(__file__).resolve().parents[2]          # repository root
OUT = BASE / "kernel/devicetree/boot-battery-final.dtb"
shutil.copyfile(BASE / "kernel/devicetree/boot-maintenance.dtb", OUT)
if os.name == "nt":
    # fdtput runs inside WSL and needs the WSL view of the Windows path.
    dt = "/mnt/" + str(OUT)[0].lower() + str(OUT)[2:].replace(chr(92), "/")
    FDTPUT = ["wsl", "-d", os.environ.get("WSL_DISTRO", "Ubuntu-24.04"), "--", "fdtput"]
else:
    dt = str(OUT)
    FDTPUT = ["fdtput"]


def fdt(*args):
    subprocess.run([*FDTPUT, *args], check=True)

def prop(node, name, values, typ="i"):
    fdt("-t", typ, "--", dt, node, name, *map(str, values))

adc = "/soc@0/spmi@c440000/pmic@0/adc@3100/bat-id@4b"
fdt("-c", dt, adc)
prop(adc, "reg", [0x4b])
prop(adc, "label", ["bat_id"], "s")
prop(adc, "qcom,pre-scaling", [1, 1])

s = (BASE / "kernel/upstream-reference/batterydata-F10-sunwoda-4000mah.dtsi").read_text()
block = re.search(r"qcom,pc-temp-v2-lut\s*\{(.*?)\};", s, re.S)[1]
def nums(name):
    return list(map(int, re.findall(r"-?\d+", re.search(name + r"\s*=\s*(.*?);", block, re.S)[1])))
temps, soc, data = (nums(n) for n in ["qcom,lut-col-legend", "qcom,lut-row-legend", "qcom,lut-data"])
assert len(data) == len(temps) * len(soc)
assert all(a > b for a, b in zip(soc, soc[1:]))
prop("/battery", "ocv-capacity-celsius", temps)
for j, temp in enumerate(temps):
    table = [(data[i * len(temps) + j] * 100, s // 100) for i, s in enumerate(soc)]
    assert all(a[0] > b[0] for a, b in zip(table, table[1:]))
    prop("/battery", f"ocv-capacity-table-{j}", [n for pair in table for n in pair])
prop("/battery", "device-chemistry", ["lithium-ion"], "s")
prop("/battery", "bti-resistance-ohm", [68000])
prop("/battery", "bti-resistance-tolerance", [10])
prop("/battery", "factory-internal-resistance-micro-ohms", [118000])
print(f"Generated {OUT.name}: {len(temps)} temperatures, {len(soc)} OCV points each.")
