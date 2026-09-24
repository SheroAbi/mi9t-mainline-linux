"""Read and extend an ath10k board-2.bin container.

    python ath10k-board.py list board-2.bin
    python ath10k-board.py add board-2.bin bdwlan.bin "<board name>" out.bin

Why this exists: the Mi 9T's device tree asks the WCN3990 driver for the
calibration variant `xiaomi_davinci`, and linux-firmware's board-2.bin has no
such entry. ath10k then falls back to `bus=snoc,qmi-board-id=ff`, a reference
board's data -- other antennas, other front end, other power tables. The
phone's own calibration is `bdwlan.bin` in the stock modem image (QMI reports
board_id 0xff, which is the file Android loads). `add` packs it into a copy of
board-2.bin under the name the driver looks for first.

Format (drivers/net/wireless/ath/ath10k/hw.h): the magic "QCA-ATH10K-BOARD"
plus NUL, padded to 4 bytes; then IEs of (le32 id, le32 len, data padded to 4).
IE 0 is a board, holding sub-IEs 0 (name, no NUL) and 1 (data).
"""
import hashlib
import struct
import sys

MAGIC = b'QCA-ATH10K-BOARD\0'
IE_BOARD, IE_NAME, IE_DATA = 0, 0, 1


def pad(data):
    return data + b'\0'*(-len(data) % 4)


def ies(blob, offset=0):
    while offset+8 <= len(blob):
        kind, length = struct.unpack_from('<II', blob, offset)
        yield kind, blob[offset+8:offset+8+length]
        offset += 8+length+(-length % 4)


def boards(blob):
    if not blob.startswith(MAGIC):
        raise SystemExit('not a board-2.bin')
    for kind, body in ies(blob, len(pad(MAGIC))):
        if kind != IE_BOARD:
            continue
        names, data = [], None
        for sub, value in ies(body):
            if sub == IE_NAME:
                names.append(value.decode('ascii', 'replace'))
            elif sub == IE_DATA:
                data = value
        yield names, data


def board_ie(name, data):
    body = (struct.pack('<II', IE_NAME, len(name)) + pad(name.encode('ascii'))
            + struct.pack('<II', IE_DATA, len(data)) + pad(data))
    return struct.pack('<II', IE_BOARD, len(body)) + body


def main():
    action, path = sys.argv[1], sys.argv[2]
    blob = open(path, 'rb').read()
    if action == 'list':
        for names, data in boards(blob):
            digest = hashlib.sha256(data or b'').hexdigest()[:12]
            print(f'{len(data or b""):6d} {digest}  ' + ' | '.join(names))
        return
    if action == 'add':
        data = open(sys.argv[3], 'rb').read()
        name, out = sys.argv[4], sys.argv[5]
        if any(name in names for names, _ in boards(blob)):
            raise SystemExit(f'{name} is already in {path}')
        result = blob + board_ie(name, data)
        found = [d for names, d in boards(result) if name in names]
        assert found == [data], 'round trip failed'
        open(out, 'wb').write(result)
        print(f'{out}: {len(result)} bytes, {name} -> {len(data)} bytes')
        return
    raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
