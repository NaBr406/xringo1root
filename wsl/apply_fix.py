#!/usr/bin/env python3
"""Apply the upstream CVE-2026-98260 fix to fs/exec.c.

Fix (upstream series "[patch 2/8] exec: Cleanup POSIX timers right after
de_thread()"): move the POSIX timer cleanup out of the late part of
begin_new_exec() into a helper called immediately after de_thread(), so a
failure later in exec cannot free a k_itimer whose timerqueue node is still
queued on the task.
"""
import re
import sys

path = sys.argv[1]
src = open(path).read()

if "posixtimer_exec" in src:
    print("already patched")
    sys.exit(0)

helper = """static void posixtimer_exec(struct task_struct *me)
{
#ifdef CONFIG_POSIX_TIMERS
	spin_lock_irq(&me->sighand->siglock);
	posix_cpu_timers_exit(me);
	spin_unlock_irq(&me->sighand->siglock);
	exit_itimers(me);
	flush_itimer_signals();
#endif
}

"""

marker = "int begin_new_exec(struct linux_binprm * bprm)"
idx = src.find(marker)
if idx < 0:
    print("begin_new_exec not found")
    sys.exit(1)

# Insert the helper just before the comment block that precedes begin_new_exec.
com = src.rfind("/*\n", 0, idx)
insert_at = com if com > 0 else idx
src = src[:insert_at] + helper + src[insert_at:]

# Call it right after de_thread() succeeds.
m = re.search(r"(retval = de_thread\(me\);\s*\n\s*if \(retval\)\s*\n\s*goto out;\n)", src)
if not m:
    print("de_thread anchor not found")
    sys.exit(1)
src = src[:m.end(1)] + "\n\tposixtimer_exec(me);\n" + src[m.end(1):]

# Remove the now-duplicated late cleanup block.
old_block = re.compile(
    r"[ \t]*#ifdef CONFIG_POSIX_TIMERS\n"
    r"[ \t]*spin_lock_irq\(&me->sighand->siglock\);\n"
    r"[ \t]*posix_cpu_timers_exit\(me\);\n"
    r"[ \t]*spin_unlock_irq\(&me->sighand->siglock\);\n"
    r"[ \t]*exit_itimers\(me\);\n"
    r"[ \t]*flush_itimer_signals\(\);\n"
    r"[ \t]*#endif\n[ \t]*\n")
src, n = old_block.subn("", src)
if n != 1:
    print(f"warning: late cleanup block replaced {n} times")
    sys.exit(1)

open(path, "w").write(src)
print("patched ok")
