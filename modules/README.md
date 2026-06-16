# w3dimporter source modules

`w3dimporter.ms` at repo root is **generated** — do not edit it by hand.

## Edit / build
1. Edit the relevant `modules/NN-*.ms` file.
2. `pwsh -NoProfile -File build-w3dimporter.ps1`  -> regenerates `w3dimporter.ms`.
3. `pwsh -NoProfile -File tools/check-build.ps1`   -> must print `BUILD GUARD OK`.

## Layout (originally sliced from the v21.4 baseline)
The modules began as byte-exact contiguous slices of the v21.4 monolith and now
diverge from it only by intentional, changelog-documented fixes.
00 header / version / globals · 01 structs · 02 chunkreader · 03 materials ·
04 import-core (cfW3DImporter) · 05 ui-renegade · 06 preferences · 07 mix ·
08 ui-main (rltMain + rltMainMenu) · 99 register (launch surface).

## Launch surface
`99-register.ms` defines the `W3D Tools > W3D Importer` macroScript + an idempotent
`menuMan` install. The dialog opens ONLY from that menu/macro (no auto-open on load).

## Guards
- `tools/check-legacy-frozen.ps1` — `legacy/w3dimporter-v21.4.ms` is the frozen
  historical pre-split baseline (hash/size pinned); kept for lineage.
- `tools/check-build.ps1` — built `w3dimporter.ms` == banner + concat(modules):
  proves the build output is mechanically generated from the modules and never
  hand-edited. (The earlier `check-lossless` byte-exact-vs-monolith proof was a
  one-time migration check, retired now that the modules intentionally diverge
  from v21.4 — see the root README changelog.)

## Install
`pwsh -NoProfile -File packaging/pack-mzp.ps1` -> `dist/w3dimporter.mzp`; drag onto a Max viewport.
