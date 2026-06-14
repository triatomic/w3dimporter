$ErrorActionPreference = "Stop"
# Verifies the frozen v21.4 baseline has not drifted. Pins to the baseline's own
# known hash/size — it must NOT be compared against the live w3dimporter.ms, which
# is a generated build artifact (banner + 99-register) that legitimately differs.
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$EXPECTED_SHA  = "791B8883DB6B0EDE3A0DA1FE333ADDAF1AFAC743BCE61DDDE3FFFB37C5DEB83D"
$EXPECTED_SIZE = 250263
$h    = (Get-FileHash -Algorithm SHA256 $legacy).Hash
$size = (Get-Item $legacy).Length
if ($h    -ne $EXPECTED_SHA)  { Write-Error "legacy drift: $h != $EXPECTED_SHA"; exit 1 }
if ($size -ne $EXPECTED_SIZE) { Write-Error "legacy size=$size expected $EXPECTED_SIZE"; exit 1 }
Write-Host "LEGACY FROZEN OK ($h, $size bytes)"
exit 0
