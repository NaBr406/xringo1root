#!/bin/bash
set -uo pipefail
cd /root/dijun
SS=ffffffc082958630

echo "=== symbols in [ss-0x200, ss+0x100] ==="
nm -n vmlinux.elf | awk -v lo="ffffffc082958430" -v hi="ffffffc082958730" '$1 >= lo && $1 <= hi'
echo
echo "=== notif_update / avc symbols ==="
nm vmlinux.elf | grep -iE "notif_update|^.* avc_" | head -10
echo
echo "=== raw bytes around selinux_state in the image (file offset mapping) ==="
python3 - <<'PY'
import subprocess, struct
ss = 0xffffffc082958630
# find section containing the address
out = subprocess.check_output(["readelf","-S","-W","vmlinux.elf"], text=True)
for line in out.splitlines():
    if "]" not in line or "PROGBITS" not in line and "NOBITS" not in line:
        continue
    parts = line.split()
    try:
        name = parts[1]
        addr = int(parts[3], 16)
        off = int(parts[4], 16)
        size = int(parts[5], 16)
    except (IndexError, ValueError):
        continue
    if addr <= ss < addr + size:
        print(f"section {name} addr=0x{addr:x} off=0x{off:x} size=0x{size:x}")
        break
data = open("Image","rb").read()
load = 0xffffffc080000000
file_off = ss - load
print("computed file offset (Image) = 0x%x" % file_off)
print("bytes [ss-16, ss+16):", data[file_off-16:file_off+16].hex())
PY
