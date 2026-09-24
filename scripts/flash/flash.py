#!/usr/bin/env python3
"""Flash the Ubuntu images built by image/build-image.sh onto a Mi 9T.

    python scripts/flash/flash.py                 # checks only, writes nothing
    python scripts/flash/flash.py --flash         # write
    python scripts/flash/flash.py --flash --reboot

The phone must be in fastboot mode (power off, then hold Volume-Down + Power)
with an unlocked bootloader. What gets written, from dist/image/:

    dtbo      erased (the Android overlay must not be applied to U-Boot's tree)
    boot      uboot.img    U-Boot
    cache     esp.img      systemd-boot, kernel, device tree
    userdata  rootfs.img   Ubuntu

!! userdata is the whole Android data partition: everything on it is gone.
   The Xiaomi bootloader itself is never written; to return to Android, flash
   a stock fastboot ROM.

Before anything is written the script checks the SHA256SUMS of the images,
that the device says product=davinci and unlocked=yes, and that every image
fits its partition. It never reboots after a failed write.
"""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
IMAGES = ROOT / 'dist' / 'image'
PLAN = (('boot', 'uboot.img'), ('cache', 'esp.img'), ('userdata', 'rootfs.img'))


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(8 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def expanded_size(path):
    """Size on the partition: sparse images expand, others are raw."""
    with path.open('rb') as f:
        head = f.read(28)
    if len(head) == 28 and struct.unpack_from('<I', head)[0] == 0xed26ff3a:
        _m, _a, _b, _fh, _ch, bs, blocks, _c, _crc = struct.unpack('<I4H4I', head)
        return blocks * bs
    return path.stat().st_size


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--images', type=Path, default=IMAGES, help='directory with the images (default dist/image)')
    p.add_argument('--fastboot', default=shutil.which('fastboot'), help='path to fastboot')
    p.add_argument('--serial', help='fastboot serial, if more than one device is attached')
    p.add_argument('--flash', action='store_true', help='actually write (default: checks only)')
    p.add_argument('--reboot', action='store_true', help='reboot after a successful flash')
    args = p.parse_args()
    if not args.fastboot:
        raise SystemExit('fastboot not found: install Android platform-tools or pass --fastboot')
    base = [args.fastboot] + (['-s', args.serial] if args.serial else [])

    sums = {}
    listing = args.images / 'SHA256SUMS'
    if not listing.is_file():
        raise SystemExit(f'{listing} missing - build the images first (image/build-image.sh)')
    for line in listing.read_text().splitlines():
        digest, name = line.split(None, 1)
        sums[name.lstrip('*')] = digest
    for _part, name in PLAN:
        path = args.images / name
        if not path.is_file():
            raise SystemExit(f'{path} missing')
        if sha256(path) != sums.get(name):
            raise SystemExit(f'{name}: checksum MISMATCH - build or copy it again')
        print(f'{name:11} ok, {expanded_size(path) / 2**20:.0f} MiB')

    def getvar(name):
        try:
            r = subprocess.run(base + ['getvar', name], capture_output=True, timeout=15)
        except subprocess.TimeoutExpired:
            raise SystemExit('no phone in fastboot mode (power off, then hold Volume-Down + Power)') from None
        text = (r.stdout + r.stderr).decode(errors='replace')
        m = re.search(r'^(?:\(bootloader\) )?' + re.escape(name) + r':\s*(.+)$', text, re.M)
        if not m:
            raise SystemExit(f'fastboot getvar {name} failed - is the phone in fastboot mode?\n{text.strip()}')
        return m.group(1).strip()

    product = getvar('product')
    unlocked = getvar('unlocked')
    print(f'device   product={product} unlocked={unlocked}')
    if product != 'davinci':
        raise SystemExit('this is not a Mi 9T / Redmi K20 (davinci) - nothing written')
    if unlocked != 'yes':
        raise SystemExit('bootloader is locked')
    for part, name in PLAN:
        size = int(getvar(f'partition-size:{part}'), 16)
        if expanded_size(args.images / name) > size:
            raise SystemExit(f'{name} does not fit {part} ({size} bytes)')
    print('checks   passed')
    if not args.flash:
        print('\nnothing written. Run again with --flash to install.')
        return 0

    steps = [['erase', 'dtbo']] + [['flash', part, str(args.images / name)] for part, name in PLAN]
    for step in steps:
        print('\n== fastboot ' + ' '.join(step[:2]), flush=True)
        if subprocess.call(base + step) != 0:
            raise SystemExit(f'fastboot {" ".join(step[:2])} FAILED - the phone stays in fastboot, '
                             'nothing was rebooted. Run the command again.')
    print('\nflash complete.')
    if args.reboot:
        subprocess.call(base + ['reboot'])
        print('rebooting: the first boot grows the root filesystem, then GNOME comes up.')
    else:
        print('reboot with:  fastboot reboot')
    return 0


if __name__ == '__main__':
    sys.exit(main())
