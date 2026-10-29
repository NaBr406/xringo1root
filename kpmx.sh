#!/system/bin/sh
# Determine whether an enabled kprobe can be disabled/deleted on this firmware.
# Benign probes only (no fetchargs).
TR=/sys/kernel/tracing
T=$TR/events/kmem/rss_stat/trigger
RES=""

one() {
    TYP=$1; G=$2; E=$3
    echo "===== $TYP:$G/$E ====="
    printf "%s:%s/%s __arm64_sys_getpid\n" "$TYP" "$G" "$E" >> $TR/kprobe_events 2>/dev/null
    grep -q "$G/$E" $TR/kprobe_events || { echo "  add FAILED"; return; }
    echo "  add ok"
    echo "enable_event:$G:$E" > $T
    : > $TR/trace; echo 1 > $TR/tracing_on; /system/bin/true; /system/bin/true; echo 0 > $TR/tracing_on
    H1=$(grep -c " $E: (" $TR/trace)
    echo "  hits(enabled)=$H1"
    echo "!enable_event:$G:$E" > $T
    : > $TR/trace; echo 1 > $TR/tracing_on; /system/bin/true; /system/bin/true; echo 0 > $TR/tracing_on
    H2=$(grep -c " $E: (" $TR/trace)
    echo "  hits(after !enable_event)=$H2"
    if [ "$H2" != "0" ]; then
        echo "disable_event:$G:$E" > $T
        : > $TR/trace; echo 1 > $TR/tracing_on; /system/bin/true; /system/bin/true; echo 0 > $TR/tracing_on
        H3=$(grep -c " $E: (" $TR/trace)
        echo "  hits(after disable_event)=$H3"
    fi
    printf -- "-:%s/%s\n" "$G" "$E" >> $TR/kprobe_events 2>/tmp/derr 2>/data/local/tmp/derr
    if grep -q "$G/$E" $TR/kprobe_events; then
        echo "  DELETE: STUCK ($(cat /data/local/tmp/derr 2>/dev/null))"
        RES="$RES $TYP$G=STUCK"
    else
        echo "  DELETE: ok"
        RES="$RES $TYP$G=ok"
    fi
}

one p pz p1
one r rz r1
echo
echo "RESULT:$RES"
echo "--- final ---"
cat $TR/kprobe_events
