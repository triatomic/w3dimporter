$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
& pwsh -NoProfile -File (Join-Path $root "build-w3dimporter.ps1");        if ($LASTEXITCODE) { exit 1 }
& pwsh -NoProfile -File (Join-Path $root "tools\check-build.ps1");        if ($LASTEXITCODE) { exit 1 }

$dist = Join-Path $root "dist"; New-Item -ItemType Directory -Force -Path $dist | Out-Null
$stage = Join-Path $root "dist\_stage"; if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $root "w3dimporter.ms")        (Join-Path $stage "w3dimporter.ms") -Force
Copy-Item (Join-Path $root "packaging\mzp.run")     (Join-Path $stage "mzp.run") -Force

$zip = Join-Path $dist "w3dimporter.zip"
$mzp = Join-Path $dist "w3dimporter.mzp"
if (Test-Path $zip) { Remove-Item -Force $zip }
if (Test-Path $mzp) { Remove-Item -Force $mzp }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
Move-Item $zip $mzp -Force
Remove-Item -Recurse -Force $stage

Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($mzp)
$names = $z.Entries.FullName; $z.Dispose()
$expected = @("mzp.run","w3dimporter.ms")
if ((($names | Sort-Object) -join ",") -ne (($expected | Sort-Object) -join ",")) {
    Write-Error "mzp root entries = $($names -join ',')  expected $($expected -join ',')"; exit 1
}
Write-Host "MZP OK -> dist/w3dimporter.mzp  (entries: $($names -join ', '))"
