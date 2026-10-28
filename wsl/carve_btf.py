#!/usr/bin/env python3
"""Locate and carve the .BTF blob out of a raw arm64 Image."""
import struct
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "/root/dijun/Image"
out = sys.argv[2] if len(sys.argv) > 2 else "/root/dijun/btf.bin"

data = open(src, "rb").read()
print(f"[*] image size = {len(data)}")

cands = []
needle = b"\x9f\xeb\x01\x00"
pos = 0
while True:
    i = data.find(needle, pos)
    if i < 0:
        break
    pos = i + 1
    if i + 24 > len(data):
        continue
    magic, version, flags, hdr_len = struct.unpack("<HBB I", data[i:i + 8])
    type_off, type_len, str_off, str_len = struct.unpack("<IIII", data[i + 8:i + 24])
    if magic != 0xEB9F or version != 1 or hdr_len != 24:
        continue
    total = hdr_len + type_off + type_len + str_off + str_len
    if total <= 24 or total > 64 * 1024 * 1024 or i + total > len(data):
        continue
    cands.append((i, total, type_len, str_len))

for i, total, tl, sl in cands:
    print(f"[+] candidate at 0x{i:x} total={total} types={tl} strings={sl}")

if not cands:
    print("[!] no BTF header found")
    sys.exit(1)

# Largest candidate is almost certainly the real .BTF.
i, total, _, _ = max(cands, key=lambda c: c[1])
open(out, "wb").write(data[i:i + total])
print(f"[+] wrote {out} ({total} bytes)")
