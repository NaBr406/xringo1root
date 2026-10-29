#!/usr/bin/env python3
"""Print the (crc, symbol) pairs from a module's __versions table."""
import struct
import sys

path = sys.argv[1]
d = open(path, "rb").read()
shoff, = struct.unpack("<Q", d[40:48])
shentsize, shnum, shstrndx = struct.unpack("<HHH", d[58:64])
stroff, = struct.unpack("<Q", d[shoff + shstrndx * shentsize + 24:shoff + shstrndx * shentsize + 32])

def nm(off):
    e = d.find(b"\x00", stroff + off)
    return d[stroff + off:e].decode("ascii", "replace")

for i in range(shnum):
    b = shoff + i * shentsize
    no, = struct.unpack("<I", d[b:b + 4])
    if nm(no) != "__versions":
        continue
    off, size = struct.unpack("<QQ", d[b + 24:b + 40])
    print(f"__versions: {size} bytes -> {size // 64} entries")
    for j in range(0, size, 64):
        crc, = struct.unpack("<Q", d[off + j:off + j + 8])
        name = d[off + j + 8:off + j + 64].split(b"\x00")[0].decode("ascii", "replace")
        print(f"  0x{crc:08x}  {name}")
