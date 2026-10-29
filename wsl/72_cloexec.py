from pathlib import Path
#!/usr/bin/env python3
"""Stop the daemon's listen socket from leaking into every command child:
without CLOEXEC each spawned /system/bin/sh inherits it and keeps the abstract
name claimed even after the daemon dies (EADDRINUSE for the next rootd)."""
import io, sys

p = Path(__file__).resolve().parents[1] / "o3root-port" / "o3p.c"
s = io.open(p, encoding="utf-8").read()

old = (
    ' if(listen(fd,8)<0){close(fd);return -1;}\n'
    ' return fd;\n'
    '}'
)
new = (
    ' if(listen(fd,8)<0){close(fd);return -1;}\n'
    ' /* keep the listener out of execve\'d children */\n'
    ' fcntl(fd,F_SETFD,FD_CLOEXEC);\n'
    ' return fd;\n'
    '}'
)

if old not in s:
    print("PATTERN NOT FOUND")
    sys.exit(1)
s = s.replace(old, new, 1)

# child side: close the client fd after dup2 and never inherit the listener
old2 = ' if(c==0){dup2(fd,1);dup2(fd,2);execl("/system/bin/sh","sh","-c",cmd,(char*)0);_exit(127);}'
new2 = ' if(c==0){dup2(fd,1);dup2(fd,2);fcntl(fd,F_SETFD,FD_CLOEXEC);execl("/system/bin/sh","sh","-c",cmd,(char*)0);_exit(127);}'
if old2 in s:
    s = s.replace(old2, new2, 1)
    print("rootd_exec cloexec added")
else:
    print("rootd_exec pattern skipped")

io.open(p, "w", encoding="utf-8").write(s)
print("bind cloexec added")
