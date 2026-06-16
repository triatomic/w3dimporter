# w3dimporter

A MAXScript importer for Westwood 3D (`.w3d`) files in 3ds Max / gMax.

Originally scripted by **coolfile**, edited and augmented by **NDC**, further edited by **tria**.

# **Note:** versions after v8 require the modified W3D Tools (rebuilt `max2w3d.dle`) from [https://github.com/triatomic/max2w3d](https://github.com/triatomic/max2w3d) to function properly.

Tested on 3ds Max 2023.

![W3D Importer dialog](dialog.png)

- [w3dimporter](#w3dimporter)
  - [Usage](#usage)
  - [Changelog (v21.9)](#changelog-v219)
  - [Changelog (v21.8)](#changelog-v218)
  - [Changelog (v21.7)](#changelog-v217)
  - [Changelog (v21.6)](#changelog-v216)
  - [Changelog (v21.5)](#changelog-v215)
  - [Changelog (v20.0 vs v17.1)](#changelog-v200-vs-v171)
    - [Advanced Renegade Import dialog](#advanced-renegade-import-dialog)
    - [Preferences and named profiles](#preferences-and-named-profiles)
    - [Import from Mix (Renegade .mix archives)](#import-from-mix-renegade-mix-archives)
    - [Pure animation FBX bake](#pure-animation-fbx-bake)
    - [Prelit chunk wrapper handling](#prelit-chunk-wrapper-handling)
    - [Compressed animation channels](#compressed-animation-channels)
    - [Autoload (scripts/startup/) fixes](#autoload-scriptsstartup-fixes)
    - [Other](#other)
  - [Changelog (v17.1 vs v17)](#changelog-v171-vs-v17)
    - [Use 3dsMax8 Normals removed](#use-3dsmax8-normals-removed)
    - [Fix Normals + Fix Vertices interaction fixed](#fix-normals--fix-vertices-interaction-fixed)
  - [Changelog (v17 vs v11)](#changelog-v17-vs-v11)
    - [Import extended W3D Info](#import-extended-w3d-info)
    - [Pivots dropdown (Basic tab)](#pivots-dropdown-basic-tab)
    - [External skeleton popup](#external-skeleton-popup)
    - [Use 3dsMax8 Normals now works on WWSkin meshes](#use-3dsmax8-normals-now-works-on-wwskin-meshes)
    - [Credits](#credits)
  - [Changelog (v11 vs v10)](#changelog-v11-vs-v10)
    - [Use 3dsMax8 Normals](#use-3dsmax8-normals)
  - [Changelog (v10 vs v8)](#changelog-v10-vs-v8)
  - [Changelog (v8 vs v7)](#changelog-v8-vs-v7)
    - [Bit-channel visibility import bug](#bit-channel-visibility-import-bug)
    - [&#34;Ignore Errors&#34; → &#34;Strict Mode&#34;](#ignore-errors--strict-mode)
  - [Changelog (v7 vs v6)](#changelog-v7-vs-v6)
    - [Known limitation (carried from v6)](#known-limitation-carried-from-v6)
  - [Changelog (v6 vs v5)](#changelog-v6-vs-v5)
    - [Two-tab dialog layout](#two-tab-dialog-layout)
    - [Fix Normals](#fix-normals)
    - [Fix Vertices](#fix-vertices)
    - [tga2DDS](#tga2dds)
    - [No Multi-Mat](#no-multi-mat)
    - [Single material with two texture stages (auto-detect)](#single-material-with-two-texture-stages-auto-detect)
    - [Pass / binding ordering](#pass--binding-ordering)
    - [Default diffuse `alphaSource = None` for opaque meshes](#default-diffuse-alphasource--none-for-opaque-meshes)
    - [Per-sub blend mode debug + tab-aware UI](#per-sub-blend-mode-debug--tab-aware-ui)
    - [Reload helper](#reload-helper)
  - [Changelog (v5 vs v3.1)](#changelog-v5-vs-v31)
    - [W3D material support](#w3d-material-support)
    - [Per-shader blend mode mapping](#per-shader-blend-mode-mapping)
    - [Per-sub-material blend mode picking](#per-sub-material-blend-mode-picking)
    - [AlphaTest detection ordering](#alphatest-detection-ordering)
    - [Ignore errors checkbox](#ignore-errors-checkbox)
    - [Expanded debug output](#expanded-debug-output)
    - [Other small fixes](#other-small-fixes)
    - [Known limitation: no multi-pass W3DMaterial output](#known-limitation-no-multi-pass-w3dmaterial-output)
  - [Changelog (v3.1 vs v2.0)](#changelog-v31-vs-v20)
    - [Multi-texture meshes](#multi-texture-meshes)
    - [Alpha textures](#alpha-textures)
    - [Additive textures](#additive-textures)
    - [Debug output toggle](#debug-output-toggle)
  - [License](#license)

---

<details id="usage">
<summary><h2>Usage</h2></summary>

1. Run`w3dimporter.ms` in 3ds Max (Scripting → Run Script).
2. The "W3D Importer" dialog opens. Click**Import a file** and pick a`.w3d`.
3. The dialog has two tabs:
   - **Basic** — Split by dependencies, Auto-Bind, Auto-Bind type (max skin / w3d skin), Batch processing.
   - **Advanced** — Use W3D Materials, Debug Output, Import extended W3D Info, Strict Mode, Fix Normals, tga2DDS (with`rev` companion), Fix Vertices, No Multi-Mat, Use 2023WWSkin, Use External Skeleton.

If a runtime error inside an import leaves the dialog's buttons unresponsive, type `w3di.reload()` in the MAXScript Listener to rebuild the dialog.

</details>

### Build system (v21.4+)
`w3dimporter.ms` is now generated from `modules/*.ms` by `build-w3dimporter.ps1`.
Edit modules, not the output. Install via the drag-drop `dist/w3dimporter.mzp`,
which adds a **W3D Tools > W3D Importer** menu. See `modules/README.md`.

<details id="changelog-v219">
<summary><h2>Changelog (v21.9)</h2></summary>

### Alpha DCG now round-trips end-to-end

The v21.6 limitation is resolved. Per-vertex **alpha** DCG — the `(255,255,255, a)` painted-transparency form ubiquitous in Renegade levels — now survives a full import → re-export, not just import. The blocker was never the importer; it was the shipped `max2w3d.dle` exposing only a single material pass to script. With a `max2w3d.dle` that authors all four W3DMaterial passes, importing with **Use W3D Materials** on rebuilds each alpha mesh as a two-pass material whose second pass is alpha-blended (`SrcAlpha` / `OneMinusSrcAlpha`); that pass is what makes the exporter emit the alpha DCG again. Verified on `blizzard.w3d`: all 6 DCG meshes round-trip (was 2), and each mesh's set of alpha values is identical to the source (per-mesh vertex counts differ only because the exporter splits verts at UV/normal seams, which is expected and lossless for the alpha data). Colour DCG continues to round-trip as before.

Alpha round-trip **requires Use W3D Materials on** — with it off the mesh gets a single Standard-material pass, which cannot express the alpha-blended overlay, so the alpha is dropped on re-export. The importer now warns when that happens (see below).

### Debug output

- The multi-pass material builder no longer prints a `[buildMultiPassW3DMatl] OK …` line for every multi-pass material on a normal import; the per-pass detail still appears under **Debug Output**.
- When a mesh carries alpha DCG but **Use W3D Materials** is off — the exact case where the alpha will be silently dropped on re-export — the importer now logs a `*** DCG: <mesh> has per-vertex ALPHA but 'Use W3D Materials' is OFF …` warning (always, not only under Debug Output), so the loss is visible instead of silent.

</details>

<details id="changelog-v218">
<summary><h2>Changelog (v21.8)</h2></summary>

### Per-mesh user text (`W3D_CHUNK_MESH_USER_TEXT`) is now imported

The importer previously skipped `W3D_CHUNK_MESH_USER_TEXT` (0x0C) — the per-mesh note taken from the node's **User Defined Properties** buffer (the old "MAX comment field") — so it was discarded on import and, having nothing left in the buffer, dropped on any re-export. Renegade level meshes use it to record what each consolidated vertex material originally was, e.g. `LVSMaterial8 = shine metal`.

It is now read and written back onto the imported mesh node via `setUserPropBuffer`, which is the exact buffer the exporter reads (`GetUserPropBuffer`) — so it survives a round-trip with no exporter/DLL change. You can see it per object under **Object Properties → User Defined**, and because the text is `key = value` lines it is also queryable with `getUserProp <node> "LVSMaterial8"`. This is authoring metadata only: no runtime loader reads the chunk, so it has no effect on how meshes render in-game or in W3DView — it is purely a data-preservation fix. Meshes without a user-text chunk (e.g. collision/blocker meshes) are unaffected. Line endings are normalised by Max (`\r\n`), so the round-trip is content-faithful rather than strictly byte-identical.

</details>

<details id="changelog-v217">
<summary><h2>Changelog (v21.7)</h2></summary>

### Optional auto-open on Max startup

The dialog can again open automatically when Max loads the plugin — but it is now **opt-in and off by default**, rather than the old v21.4 behaviour of force-opening on every script evaluation.

The legacy auto-open tail was removed when the plugin moved to a menu install (`W3D Tools > W3D Importer`), because popping the dialog on every Max launch is wrong for a menu-installed tool. Users who preferred the old behaviour can turn it back on: tick **Auto-open importer on Max startup** in **Edit > Preferences**, or run `w3dSetAutoStart true` in the Listener. The choice persists in `W3D-Importer.ini` under `[Startup] AutoOpen`. When enabled, the install pass reopens the dialog once on load (interactive sessions only — it is suppressed in quiet / network-render mode).

</details>

<details id="changelog-v216">
<summary><h2>Changelog (v21.6)</h2></summary>

### Per-vertex colour (`W3D_CHUNK_DCG`) is now imported and round-trips

The importer previously skipped `W3D_CHUNK_DCG` (per-vertex diffuse colour / alpha) entirely — the chunk reader `fseek`'d past it and no Max vertex-colour channel was ever built — so the data was lost on import and dropped on any re-export.

It is now read into the mesh model and applied to the Max vertex-colour channel. W3D stores DCG in two forms, distinguished by the exporter's per-node **VAlpha** geometry flag: as real per-vertex **colour** `(rgb, 255)`, or as per-vertex **alpha** `(255,255,255, a)` — white RGB with painted transparency, ubiquitous in Renegade levels. The importer detects which form each mesh uses and reconstructs the matching Max state: RGB into the vertex-colour channel for colour data, or grayscale alpha plus the VAlpha node flag (`wwSetVAlpha`) for alpha data, so a re-export regenerates the identical chunk. DCG is also located across **all** material passes, not just the first, since multi-pass Renegade meshes store it in a later pass.

**Round-trip status:** colour DCG round-trips byte-exact. Alpha DCG is fully reconstructed on import; at the time of v21.6 it did not yet survive re-export, because the shipped `max2w3d.dle` could author only a single material pass (the same PassOne-only limit as multi-pass W3DMaterial output). That limit has since been lifted — see the [v21.9 changelog](#changelog-v219): with a multi-pass-capable `max2w3d.dle` and **Use W3D Materials** on, alpha DCG now round-trips too.

</details>

<details id="changelog-v215">
<summary><h2>Changelog (v21.5)</h2></summary>

### Renegade level/terrain proxies no longer re-export as box meshes

Re-exporting an imported Renegade level or terrain `.w3d` — one whose HLOD references base buildings as **proxies** (`MG*` / `MN*` with `_AG_n` / `_INT_N` / `_VIS` / `_VISX` suffixes, plus `WEP#*`, `REF_TIB_DUMP`) — produced a file that **crashed W3DView** on load.

The importer creates a small visual marker per proxy (from the active profile's *Proxy* shape). Those markers were created with the export-geometry flag **on**, so the W3D exporter wrote each one out as a real ~1.5-unit box mesh — inflating the mesh count, colliding proxy-array names with real meshes, and duplicating proxies/bones. That malformed HLOD is what crashed W3DView.

The proxy array is in fact reproduced entirely from the `~`-named proxy **pivot bones** (rebuilt from the file's `PIVOTS` chunk). The fix makes the proxy marker a Max-only visual node that does **not** export — both its export-geometry and export-bone flags are cleared — so the round-tripped HLOD matches the source file's proxy/pivot structure exactly and loads cleanly. Aggregates (a separate code path, keyed by geometry type) are unaffected.

</details>

<details id="changelog-v200-vs-v171">
<summary><h2>Changelog (v20.0 vs v17.1)</h2></summary>

Catch-up release: v18 and v19 happened in the local working copy without published tags, so v20.0 bundles all of v18 → v20 plus the autoload fixes from the final cycle.

### Advanced Renegade Import dialog

A new **Advanced Import** button next to *Import a file* opens a per-file Renegade-style inspector (`rltRenegade`) that lists every mesh, proxy, aggregate, and dazzle in the picked `.w3d`. You can:

- Multi-select which meshes / proxies / aggregates to import (rest skipped).
- Choose a LOD: *All*, an individual LOD index, or *None*.
- Clamp animation to a custom `[from..to]` frame range, or skip animation entirely.
- Toggle *Import Bones*, *Bones-only* import, *DepBones only* (keep only the bones referenced by the selected meshes), and *Origin Bone* (add a single Bone at world origin, reparent root pivots under it).
- Run a Bones-only pass that skips geometry entirely.

### Preferences and named profiles

A new **File > Preferences** dialog (`W3DPreferences`) replaces the old hard-coded Pivots dropdown. Bones, Proxies, Aggregates, and Dazzles each get their own shape (Bone / Sphere / Point Helper), size, and color. The configuration is stored as named profiles in `W3D-Importer.ini` with *Default*, *Default Characters*, and *Default Vehicles* baseline profiles mirroring 1.16b. The Basic-tab Pivots control is gone; the active profile drives everything.

### Import from Mix (Renegade .mix archives)

**File > Select From Mix** opens a Renegade `.mix` archive, lists every `.w3d` inside, lets you multi-select, and extracts + imports each. An optional checkbox routes every extracted file through the Advanced Renegade Import dialog instead of straight import — useful when you want per-file LOD/animation/selection control across a batch.

### Pure animation FBX bake

A new **Pure animation** checkbox on the Basic tab. After import, the importer writes an `.fbx` next to the source `.w3d` (single-file and batch). Useful for baking out anim-only clips for tools that don't read `.w3d`. Requires the FBX exporter plugin.

### Prelit chunk wrapper handling

Meshes containing `W3D_CHUNK_PRELIT_VERTEX` (0x24) now import their materials, shaders, and textures correctly. Previously the wrapper was treated as opaque and the inner `MATERIAL_INFO / SHADERS / VERTEX_MATERIALS / TEXTURES / MATERIAL_PASS` chunks were skipped, leaving prelit meshes (common in Renegade exteriors) with default Standard materials. The lightmap-prelit siblings (`0x23 PRELIT_UNLIT`, `0x25 PRELIT_LIGHTMAP_MULTI_PASS`, `0x26 PRELIT_LIGHTMAP_MULTI_TEXTURE`) are still deliberately skipped — they need real lightmap-texture + secondary-UV handling, not just a wrapper descend.

### Compressed animation channels

The importer now reads `ANIM_MOTION_CHANNEL_DELTA_Q` (compressed-quaternion delta), `ANIM_MOTION_CHANNEL_DELTA_X/Y/Z` (compressed translation deltas), `ANIM_FLAVOUR_TIMECODED` (time-coded keyframes), and `ANIM_FLAVOUR_VALID` channels. Models that ship `W3D_CHUNK_COMPRESSED_ANIMATION` (adaptive-delta or time-coded compressed clips) now animate correctly instead of importing with empty motion.

### Autoload (scripts/startup/) fixes

Dropping `w3dimporter.ms` into `<3dsmax>/scripts/startup/` previously caused two symptoms:

- **Hard error on import.** `cfW3DImporter` references `W3DImporterInit`, which is assigned via `global W3DImporterInit = ...` about 3.5k lines later in the file. Manual drag-drop tolerates this (the editor evaluates the whole buffer in one shared scope so the global is visible everywhere by the time anything runs); startup-folder autoload doesn't (function bodies are compiled before later top-level statements execute, so the name is captured as `undefined` inside `cfW3DImporter`). Result: `Unknown property: "getActive" in undefined` at the first call to `W3DImporterInit.getActive`.
- **Silent wrong import via Advanced Import.** `rltRenegade.doImport` snapshotted each Advanced-tab checkbox as `try ( rltMain.ckbXxx.checked ) catch ( false )`. Under autoload `rltMain` was likewise undefined inside the earlier-defined `rltRenegade`'s scope, the `.ckbXxx` access threw, the `try` swallowed it, and every advanced option silently fell back to `false`. The imported model looked correct but with every Advanced-tab toggle (Use W3D Materials, Import extended W3D Info, Fix Normals, tga2DDS, etc.) effectively unchecked regardless of the UI state.

Both are fixed by adding forward `global Name` declarations at the top of the file (`W3DImporterInit`, `rnPendingFile`, `rltMain`). MAXScript's `global X` followed by a later `global X = value` is idempotent — the later assignment reuses the same global slot — so manual drag-drop behaviour is unchanged.

### Other

- Bone / proxy / aggregate marker sizes auto-fit from the imported mesh bounding box when the profile's size is `0`.
- External-skeleton handling: file picker exposed; the picked path survives across multiple imports in the same session.
- Generals-era HLOD: `lodArrays`, `aggregates`, `proxies` arrays are read out of the HLOD chunk (was previously only `lodArray`).
- Reload helper unchanged: `w3di.reload()` in the Listener still rebuilds the dialog from a clean state after a runtime error.

</details>

<details id="changelog-v171-vs-v17">
<summary><h2>Changelog (v17.1 vs v17)</h2></summary>

### Use 3dsMax8 Normals removed

The **Use 3dsMax8 Normals** checkbox is gone, along with the `wwMakeNormalsExplicit` call site in both `w3dimporter.ms` and `w3dimporter_renegade.ms`. The feature did not reproduce 3ds Max 8's `RVertex` per-vertex normal shading on Max 2023's `MeshNormalSpec` pipeline: marking every spec normal Explicit only flips a flag, but the spec's per-face-corner table is still routed by smoothing groups during `CheckNormals`, so corners that Max 8 would have shared can split (and vice versa). The result was that imported meshes still shaded differently from Max 8 even with the box checked. The function signature, dialog checkbox, mutual-exclusion handlers, and basic/advanced visibility toggle have all been removed; the remaining checkboxes shift up to close the gap.

The `wwMakeNormalsExplicit` primitive itself is left in `max2w3d.dle` because the older `w3dimporterv8.ms` still references it.

### Fix Normals + Fix Vertices interaction fixed

Running both **Fix Normals** and **Fix Vertices** in the same import produced wrong shading on the output model. Fix Vertices assigns a unique smoothing group per connected element so welded element seams keep their hard edges, then Fix Normals would force every face to SG 1 before its `Edit_Normals → Reset` pass — wiping out the per-element split and bleeding shading across element seams.

Two changes:

- The two checkboxes are now mutually exclusive in the dialog. Enabling one auto-unchecks the other.
- As a safety net for programmatic callers, Fix Normals' `setFaceSmoothGroup f 1` baseline is skipped when `fixVertices` is true. `Edit_Normals → Reset` then operates on whatever SGs are in place, preserving Fix Vertices' per-element edges.

Both fixes apply to `w3dimporter.ms` and `w3dimporter_renegade.ms`.

</details>

<details id="changelog-v17-vs-v11">
<summary><h2>Changelog (v17 vs v11)</h2></summary>

### Import extended W3D Info

New **Import extended W3D Info** checkbox (Advanced tab, off by default). When enabled, each imported mesh has its W3D Tools panel populated from the source `W3D_MESH_HEADER3.Attributes` and `SortLevel`: Geometry Type (Normal / CamParallel / Skin / AABox / OBBox / CamOriented / CamZOriented), geometry flags (Hide, 2-Sided, CastShadow, Shatter, Tangents, Prelit, AlwaysDynLight), collision flags (Physical / Projectile / Vis / Camera / Vehicle), and Static Sort Level. W3DBOX collision boxes get the same decode (Aligned / Oriented + collision bits). Without this pass, imported meshes always read back as the default (Normal, no flags) regardless of what the source `.w3d` encoded. Requires the rebuilt `max2w3d.dle` (provides `wwSetFlags` / `wwSetSorting`).

### Pivots dropdown (Basic tab)

New **Pivots:** dropdown on the Basic tab to control how hierarchy pivots are represented in the scene:

- **Bone (default)** — original importer behaviour, Max bone object.
- **Sphere** — V1.16-style green sphere. Visually distinctive but`max2w3d.dle` treats it as render geometry, so the exporter / Select Bones won't classify it as a bone — beware.
- **Point Helper** — small helper marker. Uses`HELPER_CLASS_ID`, so W3D Tools' Select Bones picks it up as a bone and it stays out of the geometry export. Recommended alternative when bones are visually noisy.

Sphere / Point Helper marker sizes auto-scale from the imported meshes' bbox diagonal (~2% / ~4%, with a sensible floor) so they stay readable across infantry, vehicles, and structures without a per-import scale knob.

### External skeleton popup

When the HLOD header references an external rig (HTree name differs from the HLOD name and ends in `_SKL`, the W3D convention for standalone skeleton files), the importer now surfaces a message box naming the expected skeleton — matching the V1.16 reference importer's behaviour. Fires regardless of whether the auto-derive step located the rig on disk; the import succeeds either way, but the popup makes the dependency obvious for infantry models (which always declare an HTree).

### Use 3dsMax8 Normals now works on WWSkin meshes

> **Removed in v17.1:** the entire **Use 3dsMax8 Normals** feature has been removed from the importer. The notes below describe what it used to do.

The `wwMakeNormalsExplicit` skip list is narrowed to native **Skin / Physique** only. Previously WWSkin was skipped too. The rebuilt `SkinModifierClass::ModifyObject` in `max2w3d.dle` now (a) sets `MESH_NORMAL_MODIFIER_SUPPORT` so Max doesn't auto-clear Explicit normals, and (b) re-skins each Explicit base-mesh normal by `Inverse(baseTM) * curTM` of its driving bone every evaluation, so explicit normals follow the rig instead of staying frozen in bind pose. Skin / Physique still recompute normals on evaluation and discard explicit base-mesh normals, so they remain skipped.

### Credits

Header comment updated to credit **Seagle & Sloth** for the v11→v17 contributions.

</details>

<details id="changelog-v11-vs-v10">
<summary><h2>Changelog (v11 vs v10)</h2></summary>

### Use 3dsMax8 Normals

> **Removed in v17.1:** the entire **Use 3dsMax8 Normals** feature has been removed from the importer. The notes below describe what it used to do.

New **Use 3dsMax8 Normals** checkbox (Advanced tab, on by default). After import, promotes the per-vertex normals written from the W3D file to Explicit in the base mesh's `MeshNormalSpec` via the `wwMakeNormalsExplicit` primitive in the rebuilt `max2w3d.dle`. Without this, Max 2023's Nitrous renderer re-derives normals from smoothing groups, making imported meshes look different from Max 8 (which used the legacy `RVertex/RNormal` path directly).

Mutually exclusive with Fix Normals (the UI enforces this). Skinned meshes (Skin / Physique on the modifier stack) are skipped automatically — the Skin modifier recomputes normals on evaluation and discards the base mesh's explicit normals. Requires the rebuilt `max2w3d.dle`.

</details>

<details id="changelog-v10-vs-v8">
<summary><h2>Changelog (v10 vs v8)</h2></summary>

- **WWSKIN Ported.** Support for importing legacy WWSKIN skin;bones has been ported and integrated.
- **External Skeleton**.  W3D files don't always carry their own bones. A character .w3d (e.g.
  usinftroop.w3d) typically contains only meshes + an HLOD chunk that names a
  skeleton — like "GDIRIFLEMAN_SKL". The importer normally tries to find
  GDIRIFLEMAN_SKL.w3d sitting next to the mesh and load bones from there. If it
  can't find it, it pops up a file picker.
- **Added "Use2023WWSkin"**  checkbox which is very similar to the basic use w3d skin but with some changes.
- **Multi-pass W3DMaterial Limitation Removed.** The hard limitation preventing the creation of true multi-pass W3DMaterials (which previously forced multi-texture/multi-shader meshes into 3ds Max multi-materials) has been completely resolved. True multi-pass W3DMaterials are now generated natively.*Requires the updated exporter/tools from [https://github.com/triatomic/max2w3d](https://github.com/triatomic/max2w3d).*
- **Various bugfixes.**

</details>

<details id="changelog-v8-vs-v7">
<summary><h2>Changelog (v8 vs v7)</h2></summary>

**Highlight: animation import fixed.** Models with bit-channel visibility animation now round-trip correctly through 3ds Max — they render correctly in 3ds Max, in W3DView, and in-game.

### Bit-channel visibility import bug

The bit-channel handler created an `On_Off` controller with a single key at frame 0 with value `1`. With 3ds Max's default playable timeline starting at frame 1, that controller evaluates to `false` across the entire timeline (verified: `at time 1f (b.visibility)` returned `false`). On re-export, `node->GetVisibility(t)` reported the bone as hidden at every frame, baking "hidden everywhere" into the bit channel — making the round-tripped model **completely invisible in-game**.

The handler now:

- **Pre-scans the channel** and only creates an`On_Off` controller when the bit data actually changes. Constant "always visible" channels leave`.visibility` as the static default, which matches the conventional 3ds Max workflow and lets the exporter fall back to its`floatvis = 1.0` default.
- **No longer seeds a frame-0 key** for animated channels; keys go directly at the transition frames.
- **Places transition keys at frame `f`** instead of`f+1`, removing the off-by-one frame shift that showed up as`frames=0..150` instead of`frames=1..150` in re-export dumps.
- **Uses `.value`** instead of`.selected` for`On_Off` keys (the correct property —`.selected` is scene-selection state, not the key's value).

As a side effect, the 39 spurious `ANIM_CHANNEL_VIS` motion channels that re-exports were producing alongside the bit channels also disappear: they only get emitted when `GetVisibility` returns non-`1.0` values, which the broken `On_Off` was causing on every frame.

### "Ignore Errors" → "Strict Mode"

The Advanced-tab `Ignore Errors` checkbox is renamed to `Strict Mode` and the polarity inverted:

- **Strict Mode off (default)** —`pivotID == 0` (ROOTTRANSFORM, by design not in the scene-bone array) and out-of-range pivot IDs are silently skipped. Matches what the motion-channel loop already did via`try`/`catch` for the same condition.
- **Strict Mode on** — the importer halts on a bad pivot ID, for users who want to be told when something is malformed.

The previous default (`Ignore Errors` unchecked) caused the importer to abort on the very first bit channel of any file containing a `W3D_CHUNK_BIT_CHANNEL` for `pivotID == 0` (root visibility, present in many files), with the message *"array index must be positive number, got: 0"*.

</details>

<details id="changelog-v7-vs-v6">
<summary><h2>Changelog (v7 vs v6)</h2></summary>

- **Multi-pass mesh support.** The importer now reads every`MATERIAL_PASS` chunk in a mesh (was discarding all but the last). Two-pass meshes get a 2-sub MultiMaterial preserving W3D pass order so re-export round-trips correctly.
- **Viewport matches W3DView for AlphaBlend overlays.** When pass 2 is AlphaBlend, face matIDs are pointed at the AlphaBlend sub so the textured overlay shows instead of the underlay.
- **Glow fix for true multi-sub meshes.** Standard-material multi-sub now classifies each sub independently — only`_G` glow subs get opacity+self-illum wired, base subs render normally instead of going black. Orphan textures (in the W3D table but not face-referenced) default to Opaque, with`_G`-suffix textures defaulting to Add.
- **`rev` companion to tga2DDS.** A new`rev` checkbox sits next to tga2DDS (disabled until tga2DDS is checked). Enabling`rev` flips the rewrite direction so`.dds` references become`.tga` instead of the default`.tga` →`.dds`.
- **Pass-aware debug log.**`=== Mesh: NAME ===` now prints`matlheader: passCount=N` and per-pass`txIds/vmIds/shaderIds` so it's clear which faces use which (vertMatl, shader, texture) per pass.

### Known limitation (carried from v6)

> **Resolved in v10:** True multi-pass W3DMaterials are now fully supported. Requires the updated tools from [https://github.com/triatomic/max2w3d](https://github.com/triatomic/max2w3d).

Meshes that combine a base diffuse texture with a glow texture as a second additive pass cannot be re-exported back as a true two-pass W3D, and the 3ds Max viewport cannot reproduce the engine's pass-1-then-pass-2 composite (3ds Max draws one material per face; W3D's runtime overlays multiple passes per draw). Pass 2+ of `W3DMaterial` is UI-only and not writable from MAXScript. The importer uses a multi-sub MultiMaterial as the workaround, which preserves the data structurally but exports as a multi-sub mesh rather than a multi-pass mesh. To author a true multi-pass W3DMaterial for export, the second pass must be set manually in the Material Editor.

</details>

<details id="changelog-v6-vs-v5">
<summary><h2>Changelog (v6 vs v5)</h2></summary>

### Two-tab dialog layout

The import options have been split across **Basic** and **Advanced** tabs (radio-button switcher at the top of the dialog), keeping the window compact while making room for the new Advanced toggles below.

### Fix Normals

Adds an Edit Normals modifier to each imported mesh and applies the exact "Reset Normals" sequence that the user would otherwise run by hand (subobject toggle → SetSelection #{1..N} → Reset). Without this, 3ds Max ignores the W3D-supplied per-vertex normals and the model looks faceted until you reset normals manually via the W3D Tools modifier. Smoothing-group baseline is set to group 1 first so the reset has consistent input.

### Fix Vertices

For each non-skinned mesh:

1. Clears all existing smoothing groups.
2. Assigns one unique smoothing group per connected element (cycling 1..32 if the mesh has more than 32 elements).
3. Welds vertices at a fixed 0.01 threshold via`meshOp.weldVertsByThreshold`.

Smoothing-group flags travel with each face through the weld, so faces from the same original element stay smooth across the seam, and faces from different elements keep their hard edges. Skinned meshes (Skin / Physique on the stack) are skipped automatically because welding renumbers/removes vertices and would silently break Skin's per-vertex weight binding.

### tga2DDS

Rewrites every `.tga` extension on imported texture references to `.dds` (case-insensitive match, filename preserved). Useful when a W3D file references TGA textures that have since been re-exported as DDS.

### No Multi-Mat

Splits meshes that would otherwise become multi-materials into separate mesh objects, one per matID actually used. Each split node is built directly from the W3D source data (verts, faces, normals, txCoords) with the matching single sub-material assigned, the original transform/parent copied, and named `OriginalName [matID N]`. The original multi-material node is replaced; downstream post-processing (skin, normals reset, fix vertices, HLOD reparent) still operates correctly because `gmMeshes[i]` is rebound to the first split node.

### Single material with two texture stages (auto-detect)

When a mesh has 1 vertex material + 1 shader + 2 textures and the vertex material's `attrs` bitfield (or `vmArgs1`) signals stage-1 usage, the importer now builds a single W3DMaterial with stage 0 = texture[1] and stage 1 = texture[2] instead of splitting into a multi-material. Matches the engine's actual rendering: e.g. SHIELDS uses LinearOffset on both stages with different mapper args, and only renders correctly as a single two-stage material.

### Pass / binding ordering

Fix Vertices and Fix Normals are now deferred to run **after** the Auto-Bind pass (max skin / w3d skin). The original code ran them mid-loop, before binding, which:

- Caused Skin to bind to a post-weld vertex topology (wrong weights).
- Caused Skin to be stacked on top of Edit Normals, which interferes with weight calculation.

With the new order: bind first, then mutate geometry/normals on top.

### Default diffuse `alphaSource = None` for opaque meshes

The Standard-material path now sets `diffuseTex.alphaSource = 2` (None) unconditionally on the diffuse bitmap, so opaque meshes don't accidentally render transparent when the bitmap carries an alpha channel. The alpha and additive branches still wire opacity maps the same way as before.

### Per-sub blend mode debug + tab-aware UI

- The per-sub-material debug line in multi-material meshes now prints the literal blend-mode label alongside the integer (`-> sub[2] tex=... picked blendmode=1 (Add)`).
- The shader-row debug renamed`depthMask=` to`WriteZBuffer=` to match the W3DMaterial vocabulary.
- Vertex-material debug now lists ambient/diffuse/specular/emissive on their own lines, plus opacity, translucency, shininess, and the decoded`stage0mapping` /`stage1mapping` (integer + literal name from the`W3DMaterialMappingType` enum),`stage0mappingargs` /`stage1mappingargs`, plus defaults for fields the W3D file doesn't carry (`stage0/1mappinguvchannel`,`speculartodiffuse`).

### Reload helper

Type `w3di.reload()` in the MAXScript Listener to recover from a stuck dialog after a runtime error. (The dialog's own buttons can't recover themselves because the runtime error leaves the rollout's event-handler thread hung; recovery has to come from outside the broken dialog.)

</details>

<details id="changelog-v5-vs-v31">
<summary><h2>Changelog (v5 vs v3.1)</h2></summary>

### W3D material support

New **Use W3D materials** checkbox. When the W3D Tools `W3DMaterial` plugin is installed, the importer builds W3DMaterials instead of Standard materials, with the following wired in from the W3D file:

- **Vertex material colors** — ambient, diffuse, specular, emissive
- **Vertex material scalars** — opacity, translucency, shininess
- **Stage 0 / Stage 1 mapping types** — decoded from`vmInfo.attrs` bits 8–15 and 16–23 (UV, Environment, ClassicEnvironment, Screen, LinearOffset, Silhouette, Scale, Grid, Rotate, Sine, Step, ZigZag, WSClassicEnv, WSEnvironment, GridClassicEnv, GridEnvironment, Random, Edge, BumpEnv, GridWSClassicEnv, GridWSEnv)
- **Stage 0 / Stage 1 mapping args** — copied from`VERTEX_MAPPER_ARGS0` /`VERTEX_MAPPER_ARGS1` chunks
- **Stage 0 texture** — assigned with`stage0texenabled = on`,`stage0display = on` (visible in viewport)
- **Defaults for fields not stored in W3D** —`stage0/1mappinguvchannel = 1`,`speculartodiffuse = off`

### Per-shader blend mode mapping

Each W3D shader's `srcBlend` / `destBlend` / `alphaTest` is mapped to the matching W3DMaterial blend mode:


| W3D shader                                            | W3DMaterial blendmode                      |
| ------------------------------------------------------- | -------------------------------------------- |
| `srcBlend=ONE`, `destBlend=ZERO`                      | `Opaque (0)`                               |
| `srcBlend=ONE`, `destBlend=ONE`                       | `Add (1)`                                  |
| `srcBlend=ZERO`, `destBlend=SRC_COLOR`                | `Multiply (2)`                             |
| `srcBlend=ONE`, `destBlend=SRC_COLOR`                 | `MultiplyAndAdd (3)`                       |
| `srcBlend=ONE`, `destBlend=ONE_MINUS_SRC_COLOR`       | `Screen (4)`                               |
| `srcBlend=SRC_ALPHA`, `destBlend=ONE_MINUS_SRC_ALPHA` | `AlphaBlend (5)`                           |
| any with`alphaTest != 0`                              | `AlphaTest (6)` or `AlphaTestAndBlend (7)` |
| anything else                                         | `Custom (8)`                               |

`Add`, `AlphaBlend`, and `AlphaTestAndBlend` also explicitly write `blendmodesrc`, `blendmodedest`, and force `customblendwritezbuffer = off` so the material renders correctly without manual fix-up.

### Per-sub-material blend mode picking

For multi-texture meshes that build a multi-material, each sub-material now gets its own blend mode picked from the shader its faces actually reference (`pickBlendModeForSub`), instead of the whole mesh inheriting a single mesh-level mode. Fixes the bug where an opaque sub-material would inherit its parent's `Add` mode (or vice versa).

Handles three matlPass encodings:

- Single-shader meshes (`shaderIds.count == 1` and`shaders.count == 1`) — every sub uses the one shader.
- Short-form multi-shader meshes (`shaderIds.count == 1` but`shaders.count > 1`) — sub`N` maps to`shaders[N]`.
- Per-face shader meshes (`shaderIds.count > 1`) — walks the faces, collects shaders for each sub's`txIds`, and promotes toward the strongest (Add wins).

### AlphaTest detection ordering

`alphaTest != 0` is now checked **before** the `srcBlend=ONE, destBlend=ZERO` opaque pattern. The W3D `SC_ATEST_2D` preset uses the same blend factors as opaque and only differs by the `alphaTest` flag, so the previous order classified alpha-test meshes as opaque. Fixed in all four classification sites.

### Ignore errors checkbox

New checkbox (unchecked by default) in the import dialog. When enabled, the bit-channel animation loop skips entries whose `pivotID` is `0` or out of range, instead of erroring with `array index must be positive number, got: 0`. Use this when an asset's visibility track references `ROOTTRANSFORM` (pivotID 0) and you want the rest of the import to succeed.

*NOTE: this is destructive to the model shown in the 3dsmax viewport the model will look wrong; exported model should be fine. Proceed with caution.*

### Expanded debug output

The **Debug output** checkbox now also prints, per mesh:

- Each shader's literal blend-mode label (Opaque / Add / Multiply / AlphaBlend / AlphaTest / etc.) alongside the raw values
- Each vertex material's colors, opacity, translucency, shininess
- Each vertex material's`attrs` bitfield with decoded`stage0mapping` /`stage1mapping` (integer + name)
- Each vertex material's`stage0mappingargs` /`stage1mappingargs` strings
- Per-sub-material blend mode picks for multi-material meshes (texture name + integer + label)
- The final W3DMaterial blendmode the mesh would receive

### Other small fixes

- Stage 0 textures show in the viewport (`stage0display = on`).
- The "alpha" / "additive" mesh classification now uses the engine's actual`Uses_Alpha()` rule (`destBlend ∈ {SRC_ALPHA, ONE_MINUS_SRC_ALPHA}` or`srcBlend ∈ {SRC_ALPHA, ONE_MINUS_SRC_ALPHA}`), matching`shader.h`.

### Known limitation: no multi-pass W3DMaterial output

> **Resolved in v10:** True multi-pass W3DMaterials are now fully supported. Requires the updated tools from [https://github.com/triatomic/max2w3d](https://github.com/triatomic/max2w3d).

The W3DMaterial plugin supports up to 4 passes per material, with each pass holding its own texture, blend mode, and shader settings. The W3D file format encodes this as multiple shader entries per mesh — e.g. an "Opaque base + Additive glow" mesh ships two shaders and two textures meant to render in two passes on a single material.

**The importer cannot produce multi-pass W3DMaterials.** This is a hard limitation imposed by how the W3DMaterial plugin exposes itself to MAXScript, not a missing feature in the importer:

- `getNumParamBlocks` and`getNumRefs` both return`0` on a`W3DMaterial` instance — the per-pass param blocks are not reachable through MAXScript's standard plugin reflection.
- `showProperties` on the material lists every per-pass property (`blendmode`,`stage0texturemap`, etc.)**four times** — once per pass — but with identical names. Dotted access (`m.blendmode = X`) and`setProperty` only ever hit the**first** occurrence (pass 1).
- There is no`m.passone` /`m.passtwo` / pass-indexed accessor exposed to script.

This was confirmed empirically by walking the material's exposed surface during import (see the `[probe]` lines in the debug log if you want to reproduce). Without a per-pass write API, the importer cannot set pass 2/3/4's texture or blend mode from script.

**What happens instead:** when a mesh has 2+ textures and 2+ distinct shaders, the importer falls back to building a 3ds Max **multi-material** with one W3DMaterial sub per texture, each correctly configured with its own blend mode (via `pickBlendModeForSub`). Per-face material IDs are assigned from `txIds` so each face uses the right sub. Visually this looks correct in 3ds Max, but it is **not a round-trip-safe representation** of the original W3D mesh — re-exporting through the W3D Tools exporter will write multiple separate single-pass materials, not the original multi-pass one.

If you need to preserve multi-pass W3DMaterials, you have to author/edit them by hand in 3ds Max after import.

</details>

<details id="changelog-v31-vs-v20">
<summary><h2>Changelog (v3.1 vs v2.0)</h2></summary>

### Multi-texture meshes

Meshes that reference more than one texture now produce a `MultiSubObjectMaterial`
with one Standard sub-material per texture. Per-face material IDs are assigned from
the W3D `txIds` array (W3D_CHUNK_TEXTURE_IDS), so each face renders with the right
texture instead of all faces collapsing onto texture[0].

### Alpha textures

When the mesh's shader signals alpha usage — i.e. `alphaTest != 0`, or `srcBlend` /
`destBlend` references `SRC_ALPHA` / `ONE_MINUS_SRC_ALPHA` — the importer:

- Sets the diffuse bitmap's`alphaSource = 2` (None / Opaque) so the diffuse channel
  ignores its own alpha.
- Wires a second instance of the same bitmap into the Opacity slot with`monoOutput = 1` (Alpha), so only the opacity map drives transparency.

The detection rule mirrors `ShaderClass::Uses_Alpha()` from the engine's `shader.h`.

### Additive textures

When the mesh's shader matches the W3D `SC_ADDITIVE` preset
(`srcBlend = ONE (1)` and `destBlend = ONE (1)`), the importer:

- Wires the texture into the Opacity slot.
- Wires the texture into the Self-Illumination slot.
- Sets`useSelfIllumColor = true` so the self-illumination is driven by the map.

### Debug output toggle

New checkbox under "Auto-Bind" in the import dialog. When enabled, every imported
mesh prints to the Listener:

- `vertMatls.count`,`textures.count`, and each texture filename
- `txIds` and`vmIds` arrays from the material pass
- Per-shader`srcBlend`,`destBlend`,`alphaTest`,`depthMask`, plus an`alpha=` and`additive=` verdict for that shader
- Final mesh-level`meshUsesAlpha` and`meshIsAdditive` rollups

Useful for diagnosing why a particular asset isn't getting alpha or additive wiring.

</details>

<details id="license">
<summary><h2>License</h2></summary>

Original script © coolfile. Modifications released under the same terms.

</details>
