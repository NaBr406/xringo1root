#!/usr/bin/env python3
"""Keep the __version* section names but set their sizes to zero.

Effect on module load:
  * has_crcs stays true  -> vermagic is compared only from the first space,
    so the GKI release suffix does not need to match.
  * zero entries         -> every CRC comparison degenerates to
    "no symbol version for X" (warning only), so no CRC mismatch can fail.
"""
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, "rb").read())
shoff, = struct.unpack("<Q", d[40:48])
shentsize, shnum, shstrndx = struct.unpack("<HHH", d[58:64])
stroff, = struct.unpack("<Q", d[shoff + shstrndx * shentsize + 24:shoff + shstrndx * shentsize + 32])

def nm(off):
    e = d.find(b"\x00", stroff + off)
    return d[stroff + off:e].decode("ascii", "replace")

zeroed = []
for i in range(shnum):
    b = shoff + i * shentsize
    no, = struct.unpack("<I", d[b:b + 4])
    name = nm(no)
    if name.startswith("__version"):
        struct.pack_into("<Q", d, b + 32, 0)  # sh_size
        zeroed.append(name)

open(dst, "wb").write(d)
print(f"zero-sized: {zeroed}")
