# W3D Importer — Modular Source + Packaged `.mzp` Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 6,485-line single-file `w3dimporter.ms` into ~9 contiguous source modules that build-concatenate back to a byte-identical runtime, shipped as a drag-drop `.mzp` plugin that registers a **W3D Tools > W3D Importer** menu.

**Architecture:** Modules are byte-exact slices of the current file cut only at top-level `fn`/`struct`/`rollout` boundaries; a PowerShell build script concatenates them (with a generated banner) into the committed root `w3dimporter.ms`. The only intended behavior delta is the launch tail: the old `createDialog` auto-open is replaced by a `macroScript` + `menuMan` menu install, isolated in `99-register.ms`. A byte-for-byte regression guard proves the split altered no statement.

**Tech Stack:** MAXScript (3ds Max 2023), PowerShell 7 (build/slice/guard/pack scripts, no Max required), `.mzp` MAXScript Zip Package format.

**User decisions (already made):**
- "Split into multiple files **and** installable like a real 3ds Max plugin (menu entry, clean install)." — design spec, Goals.
- "Packaged MAXScript module (not compiled C++, not a bare file split)." — Resolved Decision 1.
- "Edit as modules, **build-concatenate to a single `w3dimporter.ms`**" so the runtime stays one file and cross-file scoping cannot fail. — Resolved Decision 2.
- "The plugin opens **only from the menu / macroScript**. The current auto-open tail is removed." — Resolved Decision 3.
- "All new artifacts live in the `w3dimporter` repo; built `w3dimporter.ms` stays at repo root." — Resolved Decision 4.
- "~9 modules is the cap, one concern per file, no finer subdivision." — Resolved Decision 5.
- "Keep the legacy single-script file (archived as `legacy/w3dimporter-v21.4.ms`), not retired." — Resolved Decision 6 + Legacy file.
- "Baseline is `main` at v21.4 (includes the `~NN` duplicate-object fix); build output must reproduce it." — Source-of-Truth note.
- "**Change no import/export behavior.**" — Goals / Non-Goals.

**Spec:** `docs/superpowers/specs/2026-06-14-w3dimporter-modular-plugin-design.md`

---

## Ground Facts (verified against the live file on branch `refactor/modular-plugin`)

- Baseline file: `w3dimporter.ms` at repo root, **6,487 lines, 250,263 bytes**, version global `W3DImporterVersion = "v21.4"` (line 12).
- Line endings: **uniformly CRLF** (6,486 CRLF pairs, zero bare LF). The **last line (6487) has NO trailing newline**.
- **Definition body = lines 1–6485** (line 6485 is CRLF-terminated → a clean cut).
- **Launch tail = lines 6486–6487**, verbatim:
  - 6486: `W3DImporterInit.init()`
  - 6487: `createDialog rltMain menu:rltMainMenu`  *(no trailing newline)*
  This 2-line tail is the ONLY part removed; it is replaced by `99-register.ms`.
- `cfW3DImporter` is declared with the `function` keyword (line 1722), not `fn`.
- `rcMenu rltMainMenu` (line 6207) is defined **before** `rollout rltMain` (line 6258); both belong to the main-UI module.

### Module boundary table (contiguous partition of lines 1–6485 — load-bearing)

| Module | Lines | Starts at (top-level def) |
|---|---|---|
| `00-header.ms` | 1–85 | banner, `global W3DImporterVersion` (12), `struct W3DImporterNamespace` (21), forward-decl globals (37–44), `global w3dMatlAvailable` (55), `fn w3dUniqueNodeName` (69) |
| `01-structs.ms` | 86–359 | `struct HierarchyHeader` (86) … `struct DependencyStack` (354) |
| `02-chunkreader.ms` | 360–1508 | `fn GetChunkSize` (360) … `fn ReadAABox` (1440), `rollout rltDepStackController` (1451), `struct RenegadeSelection` (1494) |
| `03-materials.ms` | 1509–1721 | materials comment banner (1509), `fn buildW3DMatl` (1520), `fn _w3dSetPassProp` (1596), `fn buildMultiPassW3DMatl` (1607) |
| `04-import-core.ms` | 1722–4920 | `function cfW3DImporter` (1722) |
| `05-ui-renegade.ms` | 4921–5408 | rltRenegade comment banner (4921), `rollout rltRenegade` (4926) |
| `06-preferences.ms` | 5409–5957 | preferences comment banner (5409), `struct W3D_Importer_Init` (5423), `global W3DImporterInit` (5647), `rollout W3DNewProfile` (5649), `rollout W3DPreferences` (5673) |
| `07-mix.ms` | 5958–6206 | MIX comment banner (5958), `struct Mix_File` (5969), `fn ExtractMixEntry` (6023), mix globals (6047–6049), `rollout SelectFromMixDlg` (6051), `fn DoSelectFromMix` (6111) |
| `08-ui-main.ms` | 6207–6485 | `rcMenu rltMainMenu` (6207), `rollout rltMain` (6258), `global rnPendingFile` (6485) |
| `99-register.ms` | NEW | replaces old tail 6486–6487: `W3DImporterInit.init()` + `macroScript W3D_Importer` + idempotent `menuMan` install |

Contiguity check: 85→86, 359→360, 1508→1509, 1721→1722, 4920→4921, 5408→5409, 5957→5958, 6206→6207, ends 6485. Full coverage of 1–6485, no gaps, no overlaps. **Because the partition is contiguous and complete, the raw concatenation of `00..08` is byte-identical to lines 1–6485 regardless of any single boundary's exact placement; boundaries were nonetheless chosen at top-level def/comment starts for human readability.**

### MZP format facts (verified: Autodesk MAXDEV 2026 docs + `maxsdk/.../mxsZipPackage.h` `DotRunParser`)

- The package control file MUST be named **`mzp.run`** at the zip root. A `.mzp` is a plain zip renamed.
- Directives (production functions in `DotRunParser`): `name`, `version`, `description`, `copy … to …`, `treeCopy … to …`, `move`, `extract to`, `run`, `drop`, `open`, `import`, `merge`, `xref`, `clear`, `keep`.
- **On drag-and-drop install, only `copy`/`move`/`extract` run and a single `drop` is sought; `run`/`open`/`import`/`merge`/`xref` are IGNORED.** → the installer MUST use `drop` (not `run`) to execute install logic on drop.
- `copy` syntax uses the `to` keyword and `$`-dir macros: `copy w3dimporter.ms to $userScripts`.
- macroScripts defined via `macroScript name category:"…"` are auto-persisted by Max to the user macros dir (survive restart); classic `menuMan` menu edits persist in the saved menu config on Max exit. Max 2023 uses classic `menuMan` (the new menu system arrived in 2025).

---

### Task 1: Freeze legacy baseline + scaffold directories

**Goal:** Archive the current `w3dimporter.ms` byte-for-byte as the immutable regression target and create the new directory skeleton.

**Files:**
- Create: `legacy/w3dimporter-v21.4.ms` (exact copy of current root `w3dimporter.ms`)
- Create: `modules/` (empty dir, via `.gitkeep` until Task 2)
- Create: `packaging/` (empty dir, via `.gitkeep` until Task 6)
- Create: `tools/` (empty dir, via `.gitkeep` until Task 2)

**Acceptance Criteria:**
- [ ] `legacy/w3dimporter-v21.4.ms` SHA-256 equals current `w3dimporter.ms` SHA-256.
- [ ] `legacy/w3dimporter-v21.4.ms` is 250,263 bytes.
- [ ] `modules/`, `packaging/`, `tools/` exist and are tracked.

**Verify:** `pwsh -NoProfile -File tools/check-legacy-frozen.ps1` → prints `LEGACY FROZEN OK` and exits 0.

**Steps:**

- [ ] **Step 1: Copy the baseline verbatim**

```powershell
$repo = "C:\Users\msi\Documents\W3dTools\_pr_workspace\w3dimporter"
New-Item -ItemType Directory -Force -Path "$repo\legacy","$repo\modules","$repo\packaging","$repo\tools" | Out-Null
Copy-Item -LiteralPath "$repo\w3dimporter.ms" -Destination "$repo\legacy\w3dimporter-v21.4.ms" -Force
foreach ($d in "modules","packaging","tools") {
    if (-not (Test-Path "$repo\$d\.gitkeep")) { New-Item -ItemType File -Path "$repo\$d\.gitkeep" | Out-Null }
}
```

- [ ] **Step 2: Write the freeze-check guard** `tools/check-legacy-frozen.ps1`

```powershell
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
```

- [ ] **Step 3: Run the guard**

Run: `pwsh -NoProfile -File tools/check-legacy-frozen.ps1`
Expected: `LEGACY FROZEN OK (<hash>, 250263 bytes)`

- [ ] **Step 4: Commit**

```bash
git add legacy/ modules/.gitkeep packaging/.gitkeep tools/.gitkeep tools/check-legacy-frozen.ps1
git commit -m "build: freeze v21.4 baseline as legacy/ + scaffold modules/packaging/tools"
```

---

### Task 2: Slice the baseline into byte-exact modules `00..08`

**Goal:** Deterministically cut `legacy/w3dimporter-v21.4.ms` into `modules/00-header.ms … 08-ui-main.ms` whose raw concatenation byte-equals lines 1–6485, and prove it.

**Files:**
- Create: `tools/slice-modules.ps1` (one-time generator; kept for audit/reproducibility)
- Create: `modules/00-header.ms`, `01-structs.ms`, `02-chunkreader.ms`, `03-materials.ms`, `04-import-core.ms`, `05-ui-renegade.ms`, `06-preferences.ms`, `07-mix.ms`, `08-ui-main.ms`
- Create: `tools/check-lossless.ps1` (asserts `concat(00..08) == legacyBody`)
- Delete: `modules/.gitkeep`

**Acceptance Criteria:**
- [ ] Nine module files exist, byte-exact slices of the boundary table.
- [ ] `concat(00..08)` raw bytes SHA-256 equals `legacy` bytes for lines 1–6485 (the body before line 6486).
- [ ] No module file is empty; line counts sum to 6485.

**Verify:** `pwsh -NoProfile -File tools/check-lossless.ps1` → prints `LOSSLESS OK` and exits 0.

**Steps:**

- [ ] **Step 1: Write the slicer** `tools/slice-modules.ps1` (operates on raw bytes; no encoding round-trip)

```powershell
$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$outDir = Join-Path $root "modules"

# 1-based inclusive line ranges (contiguous partition of lines 1..6485)
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
# line-start byte offsets: line 1 starts at 0; each subsequent line starts right after a CRLF
$starts = [System.Collections.Generic.List[int]]::new()
$starts.Add(0)
for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) { $starts.Add($i + 2) }
}
# $starts.Count must be 6487 (one entry per line)
if ($starts.Count -ne 6487) { Write-Error "expected 6487 line starts, got $($starts.Count)"; exit 1 }

foreach ($m in $map) {
    $startByte = $starts[$m.a - 1]
    $endByte   = if ($m.b -lt $starts.Count) { $starts[$m.b] } else { $bytes.Length }  # start of line b+1
    $len       = $endByte - $startByte
    $slice     = New-Object byte[] $len
    [System.Array]::Copy($bytes, $startByte, $slice, 0, $len)
    [System.IO.File]::WriteAllBytes((Join-Path $outDir $m.name), $slice)
    Write-Host ("{0,-20} lines {1}-{2}  {3} bytes" -f $m.name, $m.a, $m.b, $len)
}
Write-Host "SLICE DONE"
```

- [ ] **Step 2: Generate the modules**

Run: `pwsh -NoProfile -File tools/slice-modules.ps1`
Expected: nine `lines A-B  N bytes` lines then `SLICE DONE`. Remove the placeholder: `git rm modules/.gitkeep` (or `Remove-Item modules\.gitkeep`).

- [ ] **Step 3: Write the lossless guard** `tools/check-lossless.ps1`

```powershell
$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$mods   = Join-Path $root "modules"

# legacyBody = bytes of lines 1..6485 (everything before line 6486 "W3DImporterInit.init()")
$bytes = [System.IO.File]::ReadAllBytes($legacy)
$nl = 0; $cut = -1
for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
    if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10) { $nl++; if ($nl -eq 6485) { $cut = $i + 2; break } }
}
if ($cut -lt 0) { Write-Error "could not locate line-6485 boundary"; exit 1 }
$legacyBody = New-Object byte[] $cut
[System.Array]::Copy($bytes, 0, $legacyBody, 0, $cut)

# concat 00..08 in lexical order (exclude 99-register)
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
```

- [ ] **Step 4: Run the lossless guard**

Run: `pwsh -NoProfile -File tools/check-lossless.ps1`
Expected: equal byte counts + equal SHA on both lines, then `LOSSLESS OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/slice-modules.ps1 tools/check-lossless.ps1 modules/
git rm --cached modules/.gitkeep 2>/dev/null || true
git commit -m "build: slice w3dimporter into modules/00..08 (byte-exact, lossless-verified)"
```

---

### Task 3: Author `99-register.ms` — macroScript + menu install (the only behavior delta)

**Goal:** Replace the removed 2-line auto-open tail with a `W3D Tools > W3D Importer` macroScript and an idempotent `menuMan` installer, keeping `W3DImporterInit.init()`.

**Files:**
- Create: `modules/99-register.ms`

**Acceptance Criteria:**
- [ ] Calls `W3DImporterInit.init()` (preserved from old tail).
- [ ] Defines `macroScript W3D_Importer category:"W3D Tools"` whose `on execute` opens `rltMain` (destroy-then-create, same call the old tail made: `createDialog rltMain menu:rltMainMenu`).
- [ ] Defines `fn w3dInstallMenu` that adds a single **W3D Tools** main-menu with a **W3D Importer** item bound to the macro, **guarded against duplicates** via `menuMan.findMenu`, and calls it once at load.
- [ ] Does NOT auto-open any dialog on load (Resolved Decision 3).
- [ ] File is CRLF-terminated so it concatenates cleanly after `08-ui-main.ms` (which ends with a CRLF).

**Verify:** Static review against this section + the Task 5 build determinism guard (parse correctness is proven empirically in Task 7's Max smoke test).

**Steps:**

- [ ] **Step 1: Write `modules/99-register.ms`** (exact content)

```maxscript
-- ===========================================================================
-- 99-register.ms  --  plugin launch surface (replaces the legacy auto-open tail)
-- AUTO-GENERATED w3dimporter.ms is built from modules/; edit modules, not output.
--
-- Legacy tail (lines 6486-6487 of v21.4) was:
--     W3DImporterInit.init()
--     createDialog rltMain menu:rltMainMenu      -- auto-opened on every eval
-- The dialog now opens ONLY from the W3D Tools > W3D Importer menu / macroScript.
-- ===========================================================================

-- Preserve the one-time importer init the old tail performed (profiles, prefs).
W3DImporterInit.init()

macroScript W3D_Importer
    category:"W3D Tools"
    toolTip:"W3D Importer"
    buttonText:"W3D Importer"
(
    on execute do
    (
        try ( destroyDialog rltMain ) catch ()
        createDialog rltMain menu:rltMainMenu
    )
)

-- Idempotent menu install: add a single "W3D Tools" main menu with one
-- "W3D Importer" item bound to the macroScript above. menuMan edits persist in
-- Max's saved menu config on exit; the duplicate guard makes re-evaluation safe.
fn w3dInstallMenu =
(
    if menuMan == undefined do return false
    if (menuMan.findMenu "W3D Tools") != undefined do return false   -- already installed
    local mainBar = menuMan.getMainMenuBar()
    local w3dMenu = menuMan.createMenu "W3D Tools"
    local item    = menuMan.createActionItem "W3D_Importer" "W3D Tools" -- macroName, category
    w3dMenu.addItem item -1
    local sub = menuMan.createSubMenuItem "W3D Tools" w3dMenu
    mainBar.addItem sub -1
    menuMan.updateMenuBar()
    true
)

try ( w3dInstallMenu() ) catch ( format "*** w3dInstallMenu failed: %\n" (getCurrentException()) )
```

- [ ] **Step 2: Normalize line endings to CRLF**

```powershell
$root = Split-Path -Parent $PSScriptRoot   # run from tools/ context, or set $root to repo root
$p = Join-Path $root "modules\99-register.ms"
$t = [System.IO.File]::ReadAllText($p)
$t = $t -replace "`r`n","`n" -replace "`n","`r`n"   # force uniform CRLF
[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
```

- [ ] **Step 3: Commit**

```bash
git add modules/99-register.ms
git commit -m "feat: W3D Tools menu + macroScript launch surface (99-register.ms)"
```

---

### Task 4: Write `build-w3dimporter.ps1` — concatenate modules into the root artifact

**Goal:** Produce the committed root `w3dimporter.ms` = generated banner + raw concat of `modules/*.ms` in lexical order (`00..08`, then `99`), with no inserted separators.

**Files:**
- Create: `build-w3dimporter.ps1`
- Modify: `w3dimporter.ms` (now a build OUTPUT — regenerated, banner at top)

**Acceptance Criteria:**
- [ ] Output begins with the exact banner line: `-- AUTO-GENERATED by build-w3dimporter.ps1 — edit modules/, not this file --` + CRLF.
- [ ] Output body (banner stripped) = `concat(00..08)` + `concat(99)` with NO extra bytes between module files.
- [ ] Script requires no 3ds Max; runs under `pwsh`.
- [ ] Modules are concatenated in `Sort-Object Name` order (`00..08`, `99` last).

**Verify:** `pwsh -NoProfile -File build-w3dimporter.ps1` → prints `BUILD OK -> w3dimporter.ms (<n> bytes)`; followed by Task 5 guard.

**Steps:**

- [ ] **Step 1: Write `build-w3dimporter.ps1`**

```powershell
$ErrorActionPreference = "Stop"
$root   = $PSScriptRoot
$mods   = Join-Path $root "modules"
$out    = Join-Path $root "w3dimporter.ms"
$banner = "-- AUTO-GENERATED by build-w3dimporter.ps1 — edit modules/, not this file --`r`n"

$files = Get-ChildItem $mods -Filter "*.ms" | Sort-Object Name
if ($files.Count -lt 10) { Write-Error "expected >=10 module files, found $($files.Count)"; exit 1 }

$ms = New-Object System.IO.MemoryStream
$enc = New-Object System.Text.UTF8Encoding($false)
$bannerBytes = $enc.GetBytes($banner)
$ms.Write($bannerBytes, 0, $bannerBytes.Length)
foreach ($f in $files) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $ms.Write($b, 0, $b.Length)   # raw concat, no separator
}
[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Host ("BUILD OK -> w3dimporter.ms ({0} bytes) from: {1}" -f $ms.Length, ($files.Name -join ', '))
```

- [ ] **Step 2: Build**

Run: `pwsh -NoProfile -File build-w3dimporter.ps1`
Expected: `BUILD OK -> w3dimporter.ms (<n> bytes) from: 00-header.ms, 01-structs.ms, ..., 08-ui-main.ms, 99-register.ms`

- [ ] **Step 3: Commit**

```bash
git add build-w3dimporter.ps1 w3dimporter.ms
git commit -m "build: add build-w3dimporter.ps1; regenerate w3dimporter.ms from modules"
```

---

### Task 5: Regression guard — prove the build is lossless + deterministic

**Goal:** USER-ORDERED verification gate. Prove (a) the built `w3dimporter.ms` minus banner minus `99-register` body byte-equals the v21.4 definition body, and (b) the build inserted nothing beyond banner + modules.

**USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

**Files:**
- Create: `tools/check-build.ps1`

**Acceptance Criteria:**
- [ ] `built[after banner .. before 99-register marker]` byte-equals `legacy` lines 1–6485 (the **baseline** body).
- [ ] `built == bannerBytes + concat(00..08) + concat(99)` exactly (the **rebuilt** determinism check).
- [ ] Guard exits non-zero on any drift (negative control: temporarily flip one byte in a module → guard FAILS → revert).
- [ ] `tools/check-legacy-frozen.ps1` still passes (legacy untouched).

**Verify:** `pwsh -NoProfile -File tools/check-build.ps1` → prints `baseline:` and `rebuilt:` hash lines then `BUILD GUARD OK`, exit 0.

**Steps:**

- [ ] **Step 1: Write `tools/check-build.ps1`**

```powershell
$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\w3dimporter-v21.4.ms"
$built  = Join-Path $root "w3dimporter.ms"
$mods   = Join-Path $root "modules"
$banner = "-- AUTO-GENERATED by build-w3dimporter.ps1 — edit modules/, not this file --`r`n"
$enc    = New-Object System.Text.UTF8Encoding($false)

function Sha($bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-","")
}

# --- baseline body: legacy lines 1..6485 ---
$lb = [System.IO.File]::ReadAllBytes($legacy)
$nl = 0; $cut = -1
for ($i = 0; $i -lt $lb.Length - 1; $i++) {
    if ($lb[$i] -eq 13 -and $lb[$i+1] -eq 10) { $nl++; if ($nl -eq 6485) { $cut = $i + 2; break } }
}
$legacyBody = New-Object byte[] $cut; [System.Array]::Copy($lb, 0, $legacyBody, 0, $cut)

# --- rebuilt expectation: banner + concat(00..08) + concat(99) ---
$defFiles = Get-ChildItem $mods -Filter "0?-*.ms" | Sort-Object Name
$regFiles = Get-ChildItem $mods -Filter "99-*.ms" | Sort-Object Name
$bannerBytes = $enc.GetBytes($banner)
$concatDef = New-Object System.IO.MemoryStream
foreach ($f in $defFiles) { $b=[IO.File]::ReadAllBytes($f.FullName); $concatDef.Write($b,0,$b.Length) }
$defBytes = $concatDef.ToArray()
$concatReg = New-Object System.IO.MemoryStream
foreach ($f in $regFiles) { $b=[IO.File]::ReadAllBytes($f.FullName); $concatReg.Write($b,0,$b.Length) }
$regBytes = $concatReg.ToArray()

$expected = New-Object System.IO.MemoryStream
$expected.Write($bannerBytes,0,$bannerBytes.Length)
$expected.Write($defBytes,0,$defBytes.Length)
$expected.Write($regBytes,0,$regBytes.Length)
$expectedBytes = $expected.ToArray()
$builtBytes = [IO.File]::ReadAllBytes($built)

# (a) baseline body check: concat(00..08) must equal legacy body
Write-Host ("baseline: legacyBody={0}b sha={1}" -f $legacyBody.Length, (Sha $legacyBody))
Write-Host ("baseline: concatDef ={0}b sha={1}" -f $defBytes.Length,   (Sha $defBytes))
if ((Sha $legacyBody) -ne (Sha $defBytes)) { Write-Error "BASELINE BODY DRIFT"; exit 1 }

# (b) rebuilt determinism: built file == banner + def + reg
Write-Host ("rebuilt:  built   ={0}b sha={1}" -f $builtBytes.Length,    (Sha $builtBytes))
Write-Host ("rebuilt:  expected={0}b sha={1}" -f $expectedBytes.Length, (Sha $expectedBytes))
if ((Sha $builtBytes) -ne (Sha $expectedBytes)) { Write-Error "BUILD NONDETERMINISTIC / EXTRA BYTES"; exit 1 }

Write-Host "BUILD GUARD OK"
exit 0
```

- [ ] **Step 2: Run the guard (positive)**

Run: `pwsh -NoProfile -File tools/check-build.ps1`
Expected: `baseline:` + `rebuilt:` hash lines (matching pairs) then `BUILD GUARD OK`.

- [ ] **Step 3: Negative control (prove the guard can fail), then revert**

```powershell
# append a stray byte to a module, rebuild, expect FAILURE
Add-Content -Path "modules\01-structs.ms" -Value "X" -NoNewline
pwsh -NoProfile -File build-w3dimporter.ps1
pwsh -NoProfile -File tools/check-build.ps1   # MUST exit non-zero (BASELINE BODY DRIFT)
# revert
pwsh -NoProfile -File tools/slice-modules.ps1
pwsh -NoProfile -File build-w3dimporter.ps1
pwsh -NoProfile -File tools/check-build.ps1   # back to BUILD GUARD OK
```
Expected: middle run FAILS (`BASELINE BODY DRIFT`), final run prints `BUILD GUARD OK`.

- [ ] **Step 4: Commit**

```bash
git add tools/check-build.ps1
git commit -m "test: byte-for-byte regression guard for the modular build (baseline + determinism)"
```

```json:metadata
{"requireEvidenceTokens": [["baseline","legacyBody"], ["rebuilt","built"]]}
```

---

### Task 6: Package the `.mzp` drag-drop installer

**Goal:** Produce `dist/w3dimporter.mzp` (a zip renamed) containing the built `w3dimporter.ms` + an `mzp.run` that, on drag-drop, copies the script to `$userScripts` and `drop`-runs it (registering the macro + installing the menu).

**Files:**
- Create: `packaging/mzp.run`
- Create: `packaging/pack-mzp.ps1`
- Create: `dist/w3dimporter.mzp` (build output; consider `.gitignore` for `dist/`, but commit the first one so it is downloadable)
- Delete: `packaging/.gitkeep`

**Acceptance Criteria:**
- [ ] `mzp.run` uses only drag-drop-honored directives: `name`, `version`, `copy … to $userScripts`, `drop w3dimporter.ms` (NOT `run` — ignored on drop per MZP docs).
- [ ] `dist/w3dimporter.mzp` is a valid zip whose root entries are exactly `mzp.run` and `w3dimporter.ms`.
- [ ] `pack-mzp.ps1` rebuilds first (so the `.mzp` always carries the current build) and fails if `tools/check-build.ps1` fails.

**Verify:** `pwsh -NoProfile -File packaging/pack-mzp.ps1` → prints `MZP OK -> dist/w3dimporter.mzp`; `Expand-Archive` lists `mzp.run`, `w3dimporter.ms`.

**Steps:**

- [ ] **Step 1: Write `packaging/mzp.run`**

```
name "W3D Importer"
version 1
description "W3D Importer for 3ds Max - installs the W3D Tools menu and W3D Importer tool"
copy w3dimporter.ms to $userScripts
drop w3dimporter.ms
```

- [ ] **Step 2: Write `packaging/pack-mzp.ps1`**

```powershell
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
# always ship the current build, guarded
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

# verify the archive root entries
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($mzp)
$names = $z.Entries.FullName; $z.Dispose()
$expected = @("mzp.run","w3dimporter.ms")
if ((($names | Sort-Object) -join ",") -ne (($expected | Sort-Object) -join ",")) {
    Write-Error "mzp root entries = $($names -join ',')  expected $($expected -join ',')"; exit 1
}
Write-Host "MZP OK -> dist/w3dimporter.mzp  (entries: $($names -join ', '))"
```

- [ ] **Step 3: Pack**

Run: `pwsh -NoProfile -File packaging/pack-mzp.ps1`
Expected: `MZP OK -> dist/w3dimporter.mzp  (entries: mzp.run, w3dimporter.ms)`

- [ ] **Step 4: Commit**

```bash
git rm --cached packaging/.gitkeep 2>/dev/null || true
git add packaging/mzp.run packaging/pack-mzp.ps1 dist/w3dimporter.mzp
git commit -m "build: package drag-drop w3dimporter.mzp (copy to $userScripts + drop-run installer)"
```

---

### Task 7: Manual smoke test in 3ds Max 2023 (behavior-parity gate)

**Goal:** USER-ORDERED acceptance gate the agent cannot run. Prove the packaged plugin installs, the menu opens the importer, and a known `.w3d` (including a duplicate-object asset) imports identically to the pre-split v21.4 script.

**USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation. It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

**Files:**
- Test asset: any `.w3d` containing duplicate object names (e.g. a Renegade asset with `GDI SPAWNER~01`/`~02` instances — exercises the `~NN` fix from commit `470f0de`).

**Acceptance Criteria:**
- [ ] Drag-drop `dist/w3dimporter.mzp` onto a Max 2023 viewport → no errors; **W3D Tools > W3D Importer** menu item appears.
- [ ] Restart Max → the **W3D Tools** menu still present (persistence); menu item still bound (opens the dialog).
- [ ] Evaluating/loading the script does NOT auto-open the dialog (only the menu/macro opens it).
- [ ] Importing the duplicate-object `.w3d` via the menu yields the SAME scene as importing the same file with `legacy/w3dimporter-v21.4.ms` (same node names incl. `~NN` numbering, same materials, same hierarchy). Compare side-by-side or by node-name dump.
- [ ] No new errors in the MAXScript Listener vs the legacy script for the same file.

**Verify:** Manual in 3ds Max 2023 — capture: (1) screenshot of the W3D Tools menu, (2) Listener log of the import, (3) node-name dump diff (importer build vs legacy) showing zero differences. Paste the three artifacts into the task close.

**Steps:**

- [ ] **Step 1: Clean install**
  - Remove any prior `w3dimporter.ms` from `$userScripts` and any prior **W3D Tools** menu (Customize > revert, or delete the user macro `$userMacros\W3D Tools\W3D_Importer.mcr`) to test a true first install.
  - Drag `dist/w3dimporter.mzp` onto a Max 2023 viewport. Confirm no Listener errors and the menu appears.

- [ ] **Step 2: Persistence**
  - Restart Max. Confirm **W3D Tools > W3D Importer** is still there and opens `rltMain`.
  - If the menu does NOT survive restart: also `copy w3dimporter.ms to $startupScripts` in `mzp.run` (Task 6) so it re-registers each launch (the macroScript/menu installer is idempotent), repackage, retest.

- [ ] **Step 3: Behavior parity**
  - Import the duplicate-object `.w3d` via the menu; dump node names (`for o in objects collect o.name`) to a file `built.txt`.
  - In a fresh scene, fileIn `legacy/w3dimporter-v21.4.ms`, import the same file, dump to `legacy.txt`.
  - Diff `built.txt` vs `legacy.txt` → expect zero differences. Spot-check materials and hierarchy.

- [ ] **Step 4: Record evidence + close**
  - Attach the menu screenshot, the import Listener log, and the diff output to the task. Only then mark complete.

```json:metadata
{"userGate": true, "tags": ["user-gate"], "requiresUserSpecification": false}
```

---

### Task 8: Document the modular workflow

**Goal:** Make the "edit modules, never hand-edit the build output" rule discoverable so future contributors (and the editing copy) don't bypass `modules/`.

**Files:**
- Create: `modules/README.md`
- Modify: `Readme.md` (repo root changelog — add a v21.4 build-system note)

**Acceptance Criteria:**
- [ ] `modules/README.md` states: edit `modules/*.ms`, run `build-w3dimporter.ps1`, never edit root `w3dimporter.ms`; documents the boundary table, the `99-register` launch surface, and the three guards (`check-legacy-frozen`, `check-lossless`, `check-build`).
- [ ] Root `Readme.md` gains a short note: source is now modular; `w3dimporter.ms` is generated; install via `dist/w3dimporter.mzp`.

**Verify:** Read both files back; confirm the build command, the menu install, and the regression-guard commands are all named correctly (`build-w3dimporter.ps1`, `tools/check-build.ps1`).

**Steps:**

- [ ] **Step 1: Write `modules/README.md`**

```markdown
# w3dimporter source modules

`w3dimporter.ms` at repo root is **generated** — do not edit it by hand.

## Edit / build
1. Edit the relevant `modules/NN-*.ms` file.
2. `pwsh -NoProfile -File build-w3dimporter.ps1`  → regenerates `w3dimporter.ms`.
3. `pwsh -NoProfile -File tools/check-build.ps1`   → must print `BUILD GUARD OK`.

## Layout (contiguous slices of the v21.4 baseline)
00 header · 01 structs · 02 chunkreader · 03 materials · 04 import-core ·
05 ui-renegade · 06 preferences · 07 mix · 08 ui-main · 99 register (launch surface).

## Launch surface
`99-register.ms` defines the `W3D Tools > W3D Importer` macroScript + idempotent
`menuMan` install. The dialog opens ONLY from that menu/macro (no auto-open).

## Guards
- `tools/check-legacy-frozen.ps1` — `legacy/w3dimporter-v21.4.ms` is the immutable baseline.
- `tools/check-lossless.ps1` — concat(00..08) byte-equals baseline lines 1-6485.
- `tools/check-build.ps1` — built file == banner + modules; baseline body unchanged.

## Install
`pwsh -NoProfile -File packaging/pack-mzp.ps1` → `dist/w3dimporter.mzp`; drag onto a Max viewport.
```

- [ ] **Step 2: Add a note to root `Readme.md`** (under the latest version heading)

```markdown
### Build system (v21.4+)
`w3dimporter.ms` is now generated from `modules/*.ms` by `build-w3dimporter.ps1`.
Edit modules, not the output. Install via the drag-drop `dist/w3dimporter.mzp`,
which adds a **W3D Tools > W3D Importer** menu. See `modules/README.md`.
```

- [ ] **Step 3: Commit**

```bash
git add modules/README.md Readme.md
git commit -m "docs: document modular source layout, build step, and .mzp install"
```

---

## Self-Review

**Spec coverage:**
- Split into focused modules → Tasks 1–2 (boundary table, byte-exact slices). ✓
- Build-concatenate to single `w3dimporter.ms` → Task 4. ✓
- Ship as `.mzp` with W3D Tools menu, auto-open removed → Tasks 3, 6. ✓
- Change no behavior / byte-for-byte guard → Tasks 2 + 5 (lossless + determinism). ✓
- Keep legacy single file (`legacy/w3dimporter-v21.4.ms`) → Task 1. ✓
- Baseline = `main` at v21.4 (`~NN` fix included) → Ground Facts; already on `refactor/modular-plugin` off `470f0de`. ✓
- ~9 modules cap → exactly 00..08 + 99. ✓
- Manual Max smoke test incl. duplicate-object file → Task 7. ✓
- Risk "future edits bypass modules" mitigation (banner warns) → banner in Task 4 + docs in Task 8. ✓

**Out of scope (per spec, not planned):** pointing the `W3dTools/src` editing copy at the build output; CI up-to-date check; menu polish beyond one entry.

**Placeholder scan:** none — every code step carries complete content.

**Type/name consistency:** `build-w3dimporter.ps1`, `tools/slice-modules.ps1`, `tools/check-legacy-frozen.ps1`, `tools/check-lossless.ps1`, `tools/check-build.ps1`, `packaging/mzp.run`, `packaging/pack-mzp.ps1`, macro `W3D_Importer` (category `"W3D Tools"`), `fn w3dInstallMenu`, `dist/w3dimporter.mzp` — used consistently across tasks.
