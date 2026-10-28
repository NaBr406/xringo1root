#!/system/bin/sh
# Careful kprobe lifecycle test: create -> enable -> verify -> disable -> verify -> delete.
# No fetchargs, so even a stuck probe cannot fault; tracing_on stays 0 outside the
# measurement window.
TR=/sys/kernel/tracing
T=$TR/events/kmem/rss_stat/trigger
G=zz
E=g1

echo "[1] add probe"
printf "r:%s/%s __arm64_sys_getpid\n" "$G" "$E" >> $TR/kprobe_events 2>/data/local/tmp/lc.err
grep -q "$G/$E" $TR/kprobe_events && echo "    added" || { echo "    FAILED:"; cat /data/local/tmp/lc.err; exit 1; }

echo "[2] enable via trigger"
echo "enable_event:$G:$E" > $T
echo "    trigger rc=$?"

echo "[3] measure (tracing_on=1, trigger getpid, off)"
: > $TR/trace
echo 1 > $TR/tracing_on
/system/bin/true; /system/bin/true
echo 0 > $TR/tracing_on
H1=$(grep -c " $E: (" $TR/trace)
echo "    hits_before_disable=$H1"

echo "[4] disable via trigger (!enable_event)"
echo "!enable_event:$G:$E" > $T
echo "    rc=$?"

echo "[5] measure again"
: > $TR/trace
echo 1 > $TR/tracing_on
/system/bin/true; /system/bin/true
echo 0 > $TR/tracing_on
H2=$(grep -c " $E: (" $TR/trace)
echo "    hits_after_disable=$H2"

echo "[6] delete"
printf -- "-:%s/%s\n" "$G" "$E" >> $TR/kprobe_events 2>/data/local/tmp/lc2.err
if grep -q "$G/$E" $TR/kprobe_events; then
    echo "    DELETE FAILED: $(cat /data/local/tmp/lc2.err 2>/dev/null)"
    echo "    RESULT: stuck probe (needs reboot)"
else
    echo "    delete ok"
fi
echo "[7] final probe list:"
cat $TR/kprobe_events
