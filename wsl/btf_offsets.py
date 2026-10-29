#!/usr/bin/env python3
"""Pull the offsets we need for the CVE-2026-98260 exploit out of a bpftool BTF dump."""
import re

RAW = "/root/dijun/btf.raw"
lines = open(RAW, encoding="utf-8", errors="replace").read().splitlines()

# bpftool raw format:  [N] STRUCT 'name' size=NNN vlen=K
#                        'member' type_id=.. bits_offset=B ...
struct_start = {}
for idx, ln in enumerate(lines):
    m = re.match(r"\[\d+\] STRUCT '([^']+)' size=(\d+)", ln)
    if m:
        struct_start.setdefault(m.group(1), (idx, int(m.group(2))))

def struct_info(name, members):
    if name not in struct_start:
        print(f"[!] struct {name} not found")
        return
    idx, size = struct_start[name]
    print(f"=== struct {name}  size={size} (0x{size:x}) ===")
    found = {}
    for ln in lines[idx + 1:]:
        if ln.startswith("["):
            break
        mm = re.match(r"\s+'([^']+)' type_id=\d+ bits_offset=(\d+)", ln)
        if mm:
            found[mm.group(1)] = int(mm.group(2)) // 8
    for want in members:
        if want in found:
            print(f"  {want:<24} +0x{found[want]:x}")
        else:
            print(f"  {want:<24} MISSING")

struct_info("task_struct", ["cred", "real_cred", "posix_cputimers", "signal", "sighand", "pid", "tgid"])
struct_info("cred", ["usage", "uid", "gid", "suid", "sgid", "euid", "egid", "fsuid", "fsgid",
                     "securebits", "cap_inheritable", "cap_permitted", "cap_effective",
                     "cap_bset", "cap_ambient", "security", "user_ns", "group_info", "ucounts"])
struct_info("k_itimer", ["it", "it_clock", "it_id", "it_pid", "it_sigev_notify", "it_interval", "it_overrun"])
struct_info("posix_cputimers", ["cputimers", "expiries_active", "bases"])
struct_info("posix_cputimer_base", ["nextevt", "tqhead"])
struct_info("cpu_timer", ["node", "incr", "running"])
struct_info("timerqueue_node", ["node", "expires"])
struct_info("group_info", ["usage", "ngroups", "gid"])
struct_info("ucounts", ["node", "ns", "uid", "count", "rlimit"])
struct_info("selinux_state", ["enforcing", "initialized", "policycap", "policy"])
