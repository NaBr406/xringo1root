from pathlib import Path
#!/usr/bin/env python3
"""Fix rootd losing root: unreachable via execve because the kernel resets
euid back to ruid for non-setuid binaries after a privilege drop."""
import io, sys

p = Path(__file__).resolve().parents[1] / "o3root-port" / "o3p.c"
s = io.open(p, encoding="utf-8").read()

old = (
    '   execl(g_self,"o1p","--rootd",(char*)0);_exit(127);}'
)

new = (
    '   /* do NOT exec a new binary here: after setuid(0) the kernel resets\n'
    '      euid back to ruid for non-setuid files (dumpable rule), which made\n'
    '      the daemon come back as shell. run the loop in this process. */\n'
    '   rootd_main();_exit(0);}'
)

if old not in s:
    print("PATTERN NOT FOUND")
    sys.exit(1)

s = s.replace(old, new, 1)

# rootd_main is defined before rootd_start (line 675 vs 721), so no forward decl needed
io.open(p, "w", encoding="utf-8").write(s)
print("rootd exec removed; runs in-process")
