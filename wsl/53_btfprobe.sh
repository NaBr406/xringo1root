#!/bin/bash
echo "=== device btf probe ==="
bpftool btf dump file /root/device-btf.bin format raw 2>&1 | head -3
echo "count: $(bpftool btf dump file /root/device-btf.bin format raw 2>/dev/null | grep -c 'STRUCT')"
echo "module structs: $(bpftool btf dump file /root/device-btf.bin format raw 2>/dev/null | grep -c "STRUCT 'module'")"
echo
echo "=== our vmlinux btf probe ==="
bpftool btf dump file /root/kernel-6.18.21/vmlinux format raw 2>&1 | head -3
echo "module structs: $(bpftool btf dump file /root/kernel-6.18.21/vmlinux format raw 2>/dev/null | grep -c "STRUCT 'module'")"
