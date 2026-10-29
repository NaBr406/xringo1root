$RepoRoot = Split-Path $PSScriptRoot -Parent
# Build a minimal APK with the SDK command line tools (no Gradle).
$ErrorActionPreference = "Stop"

$Sdk      = "F:\Android\Sdk"
$Bt       = Join-Path $Sdk "build-tools\35.0.0"
$Jar      = Join-Path $Sdk "platforms\android-35\android.jar"
$Proj     = "$RepoRoot\apk"
$Out      = Join-Path $Proj "build"
$JavaHome = "C:\Program Files\Java\jdk-24"

$Aapt2    = Join-Path $Bt "aapt2.exe"
$D8       = Join-Path $Bt "d8.bat"
$ZipAlign = Join-Path $Bt "zipalign.exe"
$ApkSign  = Join-Path $Bt "apksigner.bat"
$Javac    = Join-Path $JavaHome "bin\javac.exe"
$KeyTool  = Join-Path $JavaHome "bin\keytool.exe"

foreach ($f in @($Aapt2, $Jar, $Javac, $D8)) {
    if (-not (Test-Path $f)) { throw "missing: $f" }
}

Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Out\classes", "$Out\gen", "$Out\dex" | Out-Null

Write-Host "=== 1. link resources ==="
& $Aapt2 link -o "$Out\base.apk" -I $Jar --manifest "$Proj\AndroidManifest.xml" `
    --java "$Out\gen" --auto-add-overlay -A "$Proj\assets"
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

Write-Host "=== 2. compile java ==="
$srcs = @(Get-ChildItem "$Proj\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$srcs += @(Get-ChildItem "$Out\gen" -Recurse -Filter *.java -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$cp = "$Jar;$Proj\kout;$Proj\libs\kotlin-stdlib.jar"
& $Javac --release 11 -encoding UTF-8 -classpath $cp `
    -d "$Out\classes" $srcs 2>&1 | Where-Object { $_ -notmatch "bootstrap|deprecat|warning" }
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Write-Host "=== 3. dex ==="
$inputs = @()
$inputs += @(Get-ChildItem "$Out\classes" -Recurse -Filter *.class -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$inputs += @(Get-ChildItem "$Proj\kout" -Recurse -Filter *.class -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($lib in @("kotlin-stdlib.jar","bcprov.jar","bcpkix.jar","bcutil.jar")) {
    $lp = "$Proj\libs\$lib"
    if (Test-Path $lp) { $inputs += $lp }
}
Write-Host ("d8 inputs: {0} entries" -f $inputs.Count)
& $D8 --lib $Jar --min-api 26 --output "$Out\dex" $inputs
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Write-Host "=== 4. package ==="
Copy-Item "$Out\base.apk" "$Out\unsigned.apk" -Force
& $Aapt2 add "$Out\unsigned.apk" "$Out\dex\classes.dex" 2>$null
# aapt2 add cannot place files at the archive root; use zip via .NET instead
if (-not (Test-Path "$Out\ok")) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($Out + "\unsigned.apk", "Update")
    $existing = $zip.Entries | Where-Object { $_.FullName -eq "classes.dex" }
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$Out\dex\classes.dex", "classes.dex") | Out-Null
    # native libs (SPAKE2 pairing lives in libadb.so)
    $jni = "$Proj\jni"
    if (Test-Path $jni) {
        Get-ChildItem $jni -Recurse -Filter *.so | ForEach-Object {
            $entryName = "lib/" + $_.Directory.Name + "/" + $_.Name
            $old = $zip.Entries | Where-Object { $_.FullName -eq $entryName }
            if ($old) { $old.Delete() }
            # store uncompressed so the loader can mmap it straight from the APK
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $entryName,
                [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null
            Write-Host "  packed native: $entryName"
        }
    }
    $zip.Dispose()
    New-Item -ItemType File -Path "$Out\ok" | Out-Null
}

Write-Host "=== 5. align + sign ==="
& $ZipAlign -f -p 4 "$Out\unsigned.apk" "$Out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

$ks = "$Proj\debug.keystore"
if (-not (Test-Path $ks)) {
    & $KeyTool -genkeypair -keystore $ks -alias androiddebugkey -storepass android `
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=Android Debug,O=Android,C=US" 2>&1 | Out-Null
}
& $ApkSign sign --ks $ks --ks-pass pass:android --key-pass pass:android `
    --ks-key-alias androiddebugkey --out "$Out\o1p-root.apk" "$Out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

$apk = Get-Item "$Out\o1p-root.apk"
Write-Host ""
Write-Host ("APK: {0}  ({1} bytes)" -f $apk.FullName, $apk.Length)
& $ApkSign verify --print-certs "$Out\o1p-root.apk" 2>&1 | Select-Object -First 3
