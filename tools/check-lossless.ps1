$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$mods   = Join-Path $root "modules"

$bytes = [System.IO.File]::ReadAllBytes($legacy)
$nl = 0; $cut = -1
for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) { $nl++; if ($nl -eq 6485) { $cut = $i + 2; break } }
}
if ($cut -lt 0) { Write-Error "could not locate line-6485 boundary"; exit 1 }
$legacyBody = New-Object byte[] $cut
[System.Array]::Copy($bytes, 0, $legacyBody, 0, $cut)

$files = Get-ChildItem $mods -Filter "0?-*.ms" | Sort-Object Name
$ms = New-Object System.IO.MemoryStream
foreach ($f in $files) { $b = [System.IO.File]::ReadAllBytes($f.FullName); $ms.Write($b, 0, $b.Length) }
$concat = $ms.ToArray()

$sha = [System.Security.Cryptography.SHA256]::Create()
$hBody   = [BitConverter]::ToString($sha.ComputeHash($legacyBody)).Replace("-","")
$hConcat = [BitConverter]::ToString($sha.ComputeHash($concat)).Replace("-","")
Write-Host "legacyBody bytes=$($legacyBody.Length) sha=$hBody"
Write-Host "concat     bytes=$($concat.Length) sha=$hConcat"
Write-Host "modules: $($files.Name -join ', ')"
if ($hBody -ne $hConcat) { Write-Error "LOSSLESS MISMATCH"; exit 1 }
Write-Host "LOSSLESS OK"
exit 0
