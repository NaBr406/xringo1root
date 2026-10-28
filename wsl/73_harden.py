#!/usr/bin/env python3
"""Make the daemon harder to reap: lowest possible OOM score so neither the
kernel OOM killer nor framework cleanups pick it, and ignore the usual
termination signals."""
import io, sys

p = "/mnt/e/code/CVE/cve-2026-98260-xring/o3root-port/o3p.c"
s = io.open(p, encoding="utf-8").read()

anchor = (
    ' printf("ROOTD start pid=%d uid=%d euid=%d sock=@%s\\n",'
    '(int)getpid(),(int)getuid(),(int)geteuid(),ROOTD_SOCK);fflush(stdout);\n'
)

hardening = (
    ' /* stay alive across framework restarts and low-memory cleanups */\n'
    ' {int of=open("/proc/self/oom_score_adj",O_WRONLY);\n'
    '  if(of>=0){if(write(of,"-1000",5)<0){}close(of);}}\n'
    ' signal(SIGHUP,SIG_IGN);signal(SIGPIPE,SIG_IGN);signal(SIGTERM,SIG_IGN);\n'
)

if anchor not in s:
    print("ANCHOR NOT FOUND")
    sys.exit(1)

s = s.replace(anchor, anchor + hardening, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("rootd hardened: oom_score_adj=-1000, ignores HUP/TERM")
