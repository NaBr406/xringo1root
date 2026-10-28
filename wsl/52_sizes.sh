#!/bin/bash
dump() {
    local btf="$1" label="$2"
    printf '%-12s ' "$label"
    bpftool btf dump file "$btf" format raw 2>/dev/null \
        | grep "STRUCT 'module'" | head -1
}
dump /root/device-btf.bin device
dump /root/kernel-6.18.21/vmlinux k621
dump /root/kernel-gki/vmlinux k633
