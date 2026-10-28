#!/usr/bin/env python3
"""Neutralise module sections by renaming them to the empty string.

usage: neutralize.py <in.ko> <out.ko> <prefix-or-name> [...]

Sections whose name matches any token (or starts with a token ending in '*')
are renamed to "", which makes the kernel's find_sec() miss them.
Used to drop __version* tables (CRC mismatch across GKI revisions) and
.init_array/.fini_array (unsupported by the module loader).
"""
import struct
import sys

src, dst = sys.argv[1], sys.argv[2]
patterns = sys.argv[3:]

d = bytearray(open(src, "rb").read())
shoff, = struct.unpack("<Q", d[40:48])
shentsize, shnum, shstrndx = struct.unpack("<HHH", d[58:64])
shstr = shoff + shstrndx * shentsize
str_off, = struct.unpack("<Q", d[shstr + 24:shstr + 32])

def match(name):
    for p in patterns:
        if p.endswith("*"):
            if name.startswith(p[:-1]):
                return True
        elif name == p:
            return True
    return False

renamed = []
for i in range(shnum):
    b = shoff + i * shentsize
    name_off, = struct.unpack("<I", d[b:b + 4])
    start = str_off + name_off
    end = d.find(b"\x00", start)
    name = d[start:end].decode("ascii", "replace")
    if match(name):
        renamed.append(name)
        struct.pack_into("<I", d, b, 0)

open(dst, "wb").write(d)
print(f"renamed {len(renamed)}: {renamed}")
