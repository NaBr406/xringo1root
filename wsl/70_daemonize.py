from pathlib import Path
#!/usr/bin/env python3
import io, sys

p = Path(__file__).resolve().parents[1] / "o3root-port" / "o3p.c"
s = io.open(p, encoding="utf-8").read()

old = (
    "static void rootd_start(void){\n"
    " pid_t c=fork();\n"
    " if(c==0){execl(g_self,\"o1p\",\"--rootd\",(char*)0);_exit(127);}"
)

new = (
    "static void rootd_start(void){\n"
    " pid_t c=fork();\n"
    " if(c==0){\n"
    "   /* detach from the caller's session (adb shell / app) so the daemon\n"
    "      keeps running after the shell channel closes */\n"
    "   setsid();\n"
    "   int nfd=open(\"/dev/null\",O_RDWR);\n"
    "   if(nfd>=0){dup2(nfd,0);dup2(nfd,1);dup2(nfd,2);if(nfd>2)close(nfd);}\n"
    "   execl(g_self,\"o1p\",\"--rootd\",(char*)0);_exit(127);}"
)

if old not in s:
    print("PATTERN NOT FOUND")
    sys.exit(1)

s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("daemonize patched")
