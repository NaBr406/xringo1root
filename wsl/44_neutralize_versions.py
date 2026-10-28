#!/usr/bin/env python3
"""Neutralise a section by renaming it to the empty string.

The kernel locates the module version table by section name ("__versions").
Renaming it makes check_version() a no-op, which is what we need because our
LKM is built from a slightly different GKI revision and the module_layout CRC
therefore differs from the device kernel's.
"""
import struct
import sys

path = sys.argv[1]
drop = sys.argv[2] if len(sys.argv) > 2 else "__versions"
out = sys.argv[3] if len(sys.argv) > 3 else path + ".novers"

d = bytearray(open(path, "rb").read())
shoff, = struct.unpack("<Q", d[40:48])
shentsize, shnum, shstrndx = struct.unpack("<HHH", d[58:64])

shstr = shoff + shstrndx * shentsize
str_off, = struct.unpack("<Q", d[shstr + 24:shstr + 32])
str_size, = struct.unpack("<Q", d[shstr + 32:shstr + 40])

found = []
for i in range(shnum):
    b = shoff + i * shentsize
    name_off, = struct.unpack("<I", d[b:b + 4])
    start = str_off + name_off
    end = d.find(b"\x00", start)
    name = d[start:end].decode("ascii", "replace")
    if name == drop or (drop == "__version*" and name.startswith("__version")):
        found.append(i)
        struct.pack_into("<I", d, b, 0)  # sh_name = 0 (empty string)

open(out, "wb").write(d)
print(f"{path}: renamed {len(found)} section(s) named {drop!r} -> ''")
