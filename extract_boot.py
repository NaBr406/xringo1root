#!/usr/bin/env python3
"""Reconstruct the `boot` partition from the payload using per-operation
data_offset/data_length, decoding REPLACE/REPLACE_XZ/REPLACE_BZ/ZERO ops."""
import bz2
import json
import lzma
import struct
import sys
import urllib.request

URL = ("https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/"
       "OS4.0.0.19.XODCNXM/dijun-ota_full-OS4.0.0.19.XODCNXM-user-17.0-aa6a58e947.zip")
TOTAL = 7_821_662_782
PAYLOAD_START = 5238          # payload.bin data offset inside the zip
MANIFEST_SIZE = 282_940
SIG_SIZE = 267
BLOCK = 4096
UA = {"User-Agent": "Mozilla/5.0"}


def rng(a, b):
    h = dict(UA)
    h["Range"] = f"bytes={a}-{b}"
    req = urllib.request.Request(URL, headers=h)
    with urllib.request.urlopen(req, timeout=120) as r:
        d = r.read()
    if len(d) != b - a + 1:
        raise RuntimeError(f"short read {len(d)}")
    return d


def varint(buf, i):
    shift = 0
    val = 0
    while True:
        b = buf[i]; i += 1
        val |= (b & 0x7F) << shift
        if not b & 0x80:
            return val, i
        shift += 7


def pbfields(buf):
    i, out, n = 0, [], len(buf)
    while i < n:
        key, i = varint(buf, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(buf, i)
        elif wt == 2:
            ln, i = varint(buf, i); v = buf[i:i + ln]; i += ln
        elif wt == 5:
            v = buf[i:i + 4]; i += 4
        elif wt == 1:
            v = buf[i:i + 8]; i += 8
        else:
            raise RuntimeError(f"wt {wt}")
        out.append((fn, v))
    return out


def get_boot_ops():
    manifest = rng(PAYLOAD_START + 24, PAYLOAD_START + 24 + MANIFEST_SIZE - 1)
    data_base = PAYLOAD_START + 24 + MANIFEST_SIZE + SIG_SIZE
    for fn, part in pbfields(manifest):
        if fn != 13:
            continue
        pf = pbfields(part)
        name = next((v.decode() for f, v in pf if f == 1), "")
        if name != "boot":
            continue
        ops = []
        for f, op in pf:
            if f != 8:
                continue
            otype, doff, dlen = 0, None, None
            extents = []
            for of, ov in pbfields(op):
                if of == 1:
                    otype = ov
                elif of == 2:
                    doff = ov
                elif of == 3:
                    dlen = ov
                elif of == 6:
                    sb = nb = 0
                    for ef, ev in pbfields(ov):
                        if ef == 1:
                            sb = ev
                        elif ef == 2:
                            nb = ev
                    extents.append((sb, nb))
            ops.append({"type": otype, "data_offset": doff, "data_length": dlen,
                        "extents": extents})
        return ops, data_base
    raise RuntimeError("boot not found")


def main():
    ops, base = get_boot_ops()
    print(f"[*] boot ops={len(ops)} data_base={base}")
    for o in ops[:6]:
        print(f"    type={o['type']} off={o['data_offset']} len={o['data_length']} "
              f"ext={o['extents']}")

    total_blocks = max(sb + nb for o in ops for sb, nb in o["extents"])
    print(f"[*] partition blocks={total_blocks} size={total_blocks*BLOCK/1048576:.2f} MB")
    img = bytearray(total_blocks * BLOCK)

    for idx, o in enumerate(ops):
        t = o["type"]
        dst = [(sb * BLOCK, nb * BLOCK) for sb, nb in o["extents"]]
        if t in (6, 7):
            for off, ln in dst:
                img[off:off + ln] = b"\x00" * ln
            continue
        if o["data_offset"] is None:
            raise RuntimeError(f"op {idx} missing data_offset")
        raw = rng(base + o["data_offset"],
                  base + o["data_offset"] + o["data_length"] - 1)
        if t == 0:
            blob = raw
        elif t == 8:
            blob = lzma.decompress(raw)
        elif t == 1:
            blob = bz2.decompress(raw)
        else:
            raise RuntimeError(f"unsupported op type {t}")
        pos = 0
        for off, ln in dst:
            chunk = blob[pos:pos + ln]
            img[off:off + len(chunk)] = chunk
            pos += len(chunk)
        if (idx + 1) % 10 == 0 or idx + 1 == len(ops):
            print(f"    decoded {idx+1}/{len(ops)}", flush=True)

    open("boot.img", "wb").write(img)
    print("[+] wrote boot.img", len(img))

    if img[:8] != b"ANDROID!":
        print("[!] bad magic:", bytes(img[:8]))
        return 1
    ksize, rsize, osver, hsize = struct.unpack("<IIII", img[8:24])
    hver = struct.unpack("<I", img[40:44])[0]
    print(f"[*] kernel={ksize/1048576:.2f}MB ramdisk={rsize/1048576:.2f}MB "
          f"hdr_size={hsize} v{hver}")
    k_off = (hsize + BLOCK - 1) & ~(BLOCK - 1)
    kern = bytes(img[k_off:k_off + ksize])
    print(f"[*] kernel magic={kern[:4].hex()} at +{k_off}")
    open("kernel_image.bin", "wb").write(kern)
    json.dump({"kernel_size": ksize, "kernel_offset": k_off,
               "header_version": hver, "boot_size": len(img)},
              open("extract.json", "w"), indent=2)
    print("[+] wrote kernel_image.bin")
    return 0


if __name__ == "__main__":
    sys.exit(main())
