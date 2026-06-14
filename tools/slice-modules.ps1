$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$outDir = Join-Path $root "modules"

$map = @(
  @{ name="00-header.ms";       a=1;    b=85   },
  @{ name="01-structs.ms";      a=86;   b=359  },
  @{ name="02-chunkreader.ms";  a=360;  b=1508 },
  @{ name="03-materials.ms";    a=1509; b=1721 },
  @{ name="04-import-core.ms";  a=1722; b=4920 },
  @{ name="05-ui-renegade.ms";  a=4921; b=5408 },
  @{ name="06-preferences.ms";  a=5409; b=5957 },
  @{ name="07-mix.ms";          a=5958; b=6206 },
  @{ name="08-ui-main.ms";      a=6207; b=6485 }
)

$bytes = [System.IO.File]::ReadAllBytes($legacy)
$starts = [System.Collections.Generic.List[int]]::new()
$starts.Add(0)
for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) { $starts.Add($i + 2) }
}
if ($starts.Count -ne 6487) { Write-Error "expected 6487 line starts, got $($starts.Count)"; exit 1 }

foreach ($m in $map) {
    $startByte = $starts[$m.a - 1]
    $endByte   = if ($m.b -lt $starts.Count) { $starts[$m.b] } else { $bytes.Length }
    $len       = $endByte - $startByte
    $slice     = New-Object byte[] $len
    [System.Array]::Copy($bytes, $startByte, $slice, 0, $len)
    [System.IO.File]::WriteAllBytes((Join-Path $outDir $m.name), $slice)
    Write-Host ("{0,-20} lines {1}-{2}  {3} bytes" -f $m.name, $m.a, $m.b, $len)
}
Write-Host "SLICE DONE"
