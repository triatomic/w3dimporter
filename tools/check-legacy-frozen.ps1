$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$live   = Join-Path $root "w3dimporter.ms"
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$hLive   = (Get-FileHash -Algorithm SHA256 $live).Hash
$hLegacy = (Get-FileHash -Algorithm SHA256 $legacy).Hash
$size    = (Get-Item $legacy).Length
if ($hLive -ne $hLegacy) { Write-Error "legacy drift: live=$hLive legacy=$hLegacy"; exit 1 }
if ($size  -ne 250263)   { Write-Error "legacy size=$size expected 250263"; exit 1 }
Write-Host "LEGACY FROZEN OK ($hLegacy, $size bytes)"
exit 0
