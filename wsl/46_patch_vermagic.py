#!/usr/bin/env python3
"""Rewrite the vermagic= entry inside .modinfo, padding with NULs."""
import struct
import sys

src, dst, newmagic = sys.argv[1], sys.argv[2], sys.argv[3]
d = bytearray(open(src, "rb").read())
key = b"vermagic="
i = d.find(key)
if i < 0:
    print("no vermagic found")
    sys.exit(1)
end = d.find(b"\x00", i)
old = bytes(d[i:end])
entry = key + newmagic.encode()
if len(entry) > len(old):
    print(f"new entry too long: {len(entry)} > {len(old)}")
    sys.exit(2)
d[i:i + len(old)] = entry + b"\x00" * (len(old) - len(entry))
open(dst, "wb").write(d)
print(f"vermagic: {old.decode()}  ->  {entry.decode()}")
