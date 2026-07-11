rcMenu rltMainMenu
(
	subMenu "&File"
	(
		menuItem mi_w3d "Select &W3D..."
		menuItem mi_mix "Select From &Mix..."
	)
	subMenu "&Edit"
	(
		menuItem mi_prefs "&Preferences..."
		separator sep_edit_1
		menuItem mi_clean "Clean &Temp"
	)
	on mi_w3d picked do
	(
		-- Run the exact same code path as the "Import a file" button (incl. batch
		-- mode and the external-skeleton pick). The previous version invoked
		-- rltMain.btnW3DImporter.pressed() inside a try with a full re-import in
		-- the catch -- meaning any error thrown MID-IMPORT (e.g. a corrupt file)
		-- triggered a complete second import. No try here on purpose: a genuine
		-- import error should surface once, not re-run.
		rltMain.doImportPressed()
	)
	on mi_mix picked do DoSelectFromMix()
	on mi_prefs picked do W3DPreferences.Open (try (getDialogPos rltMain) catch ([100,100]))
	on mi_clean picked do
	(
		-- Delete the w3di_*.w3d files we extracted from mixes into Max's temp
		-- directory. Pattern matches our ExtractMixEntry naming scheme; nothing
		-- else in #temp uses that prefix, so unrelated Max temp data is safe.
		local pat = (getDir #temp) + "\\w3di_*.w3d"
		local hits = getFiles pat
		local removed = 0
		for f in hits do ( if (deleteFile f) do removed += 1 )
		messageBox ("Cleaned " + (removed as string) + " temp file(s) from\n" + (getDir #temp)) \
			title:"Clean Temp" beep:false
	)
)

macroscript ImportW3D
	-- NOTE: macroscript category must be a string literal, so it stays
	-- version-free on purpose -- a versioned category would orphan users'
	-- toolbar buttons on every release.
	category: "W3D Importer/Processor Cabal"
	buttontext: "Import W3D"
	tooltip: "W3D Importer"
	icon:#("gMax",2)
( createDialog rltMain menu:rltMainMenu )

-- Title is version-free here; the open handler appends ::W3DImporterVersion
-- so the caption always matches the single version constant at file top.
rollout rltMain "W3D Importer" width:177 height:314
(
	button btnW3DImporter "Import a file" pos:[25,17] width:127 height:36
	button btnRenegade     "Renegade Import" pos:[25,57] width:127 height:18 tooltip:"Open a .w3d file in the Renegade import dialog — inspect meshes, bones, aggregates and proxies, choose LODs and animation range, then import all or selected items."

	-- Tab strip: clicking these toggles which group of controls is visible below.
	-- (MAXScript rollouts have no native tab control, but a radio-button strip is the
	-- conventional substitute and behaves exactly like tabs.)
	radiobuttons rbgTab "" pos:[12,82] width:153 height:18 labels:#("Basic", "Advanced") default:1 columns:2

	-- BASIC tab controls
	checkbox ckbSplitDependencies "Split by dependencies" pos:[25,107] width:127 height:15 enabled:true
	checkbox ckbAutoBind "Auto-Bind" pos:[25,124] width:127 height:15 checked:true
	radiobuttons rbgAutoBind "Auto-Bind type" pos:[17,149] width:162 height:30 enabled:true labels:#("max skin", "w3d skin") default:1 columns:2
	checkbox ckbBatchProcessing "Batch processing" pos:[25,187] width:127 height:15 checked:false
	-- Pivot shape/size/color now come from the active W3DPreferences profile (Edit > Preferences).
	-- v19: bone-fins display toggle (defaults on to match v18 behaviour); pure-anim FBX bake (batch only).
	checkbox ckbShowBoneFins "Show bone fins" pos:[25,210] width:127 height:15 checked:true tooltip:"Display fins/links on imported max bones. When unchecked, sets showLinks/showFins false and zeros fin sizes. Viewport-only, no effect on export."
	checkbox ckbPureAnim     "Pure animation"  pos:[25,227] width:127 height:15 checked:false tooltip:"After import, export an .fbx next to the source .w3d (same basename). Works in both single-file and batch mode. Useful for baking out anim-only clips. Requires the FBX exporter plugin."

	-- ADVANCED tab controls (overlap the same vertical space; visibility toggled by rbgTab)
	checkbox ckbDebugOutput "Debug Output" pos:[25,107] width:127 height:15 checked:false visible:false
	checkbox ckbUseW3DMatl "Use W3D Materials" pos:[25,124] width:127 height:15 checked:false visible:false
	checkbox ckbImportExtendedW3D "Import extended W3D Info" pos:[25,141] width:152 height:15 checked:false visible:false tooltip:"Restore each mesh's W3D Tools settings (Geometry Type, geometry flags like Hide / 2-Sided / Shadow / Shatter / Tangents / Prelit / AlwaysDynLight, Collision flags, Static Sort Level) from the imported .w3d's MESH_HEADER3 Attributes. Requires the rebuilt max2w3d.dle (provides wwSetFlags / wwSetSorting)."
	checkbox ckbIgnoreErrors "Strict Mode" pos:[25,158] width:127 height:15 checked:false visible:false tooltip:"Halt the import if a channel references an invalid pivot ID, instead of skipping it."
	checkbox ckbFixNormals "Fix Normals" pos:[25,175] width:127 height:15 checked:false visible:false tooltip:"Destructive fallback for W3D files with broken normals: forces all faces to one smoothing group, then resets normals via Edit_Normals."
	checkbox ckbTga2Dds "tga2DDS" pos:[25,192] width:65 height:15 checked:false visible:false tooltip:"Rewrite .tga texture references to .dds (extension only; filename preserved)"
	checkbox ckbTga2DdsRev "rev" pos:[92,192] width:60 height:15 checked:false enabled:false visible:false tooltip:"Reverse: rename .dds to .tga (only available while tga2DDS is enabled)"
	checkbox ckbFixVertices "Fix Vertices" pos:[25,209] width:127 height:15 checked:false visible:false tooltip:"Per-element smoothing groups, then weld vertices at 0.01 threshold (preserves smoothing across the weld)"
	checkbox ckbNoMultiMat "No Multi-Mat" pos:[25,226] width:127 height:15 checked:false visible:false tooltip:"Split meshes that would use a multi-material into separate meshes (one per texture), each with a single material assigned"
	checkbox ckbUseWWSkin "Use 2023WWSkin" pos:[25,243] width:127 height:15 checked:false visible:false tooltip:"Bind skinned meshes using the 2023-toolchain WWSkin (Westwood Space Warp + WWSkin Binding) instead of Max's native Skin modifier. Requires the rebuilt max2w3d.dle (Phase 1+ of the WWSkin port)."
	checkbox ckbUseExternalSkel "Use External Skeleton" pos:[25,260] width:127 height:15 checked:false visible:false tooltip:"Load the bone hierarchy from an external .w3d file (e.g. a shared skeleton) instead of the main w3d / auto-derive."
	button btnSelectSkeleton "Select Skeleton" pos:[25,277] width:152 height:18 enabled:false visible:false

	-- Path to the user-picked external skeleton w3d. Lives at rollout scope
	-- so it survives across multiple imports without re-prompting.
	local externalSkeletonFile = undefined

	-- Shared by the Import button and the File > Select W3D menu item so both
	-- run the exact same code path (incl. batch mode and external skeleton).
	-- Must be defined AFTER `local externalSkeletonFile` above so the reference
	-- binds to the rollout local, not an implicit global.
	fn doImportPressed =
	(
		if ckbBatchProcessing.checked then
		(
			fldrPath = getSavePath()
			if (fldrPath != undefined) do
			(
				w3dFiles = getFiles(fldrPath + "\\*.w3d")
				for i=1 to w3dFiles.count do
				( cfW3DImporter w3dFiles[i] ckbSplitDependencies.checked rbgAutoBind.state true ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked ckbUseWWSkin.checked (if ckbUseExternalSkel.checked then externalSkeletonFile else undefined) ckbImportExtendedW3D.checked )
			)
		)
		else
		( cfW3DImporter undefined ckbSplitDependencies.checked rbgAutoBind.state false ckbDebugOutput.checked ckbUseW3DMatl.checked (not ckbIgnoreErrors.checked) ckbFixNormals.checked ckbTga2Dds.checked ckbFixVertices.checked ckbNoMultiMat.checked ckbTga2DdsRev.checked ckbUseWWSkin.checked (if ckbUseExternalSkel.checked then externalSkeletonFile else undefined) ckbImportExtendedW3D.checked )
	)

	on btnW3DImporter pressed do doImportPressed()

	-- enable rev only while tga2DDS is on; uncheck it when tga2DDS is turned off
	on ckbTga2Dds changed st do
	(
		ckbTga2DdsRev.enabled = st
		if not st do ckbTga2DdsRev.checked = false
	)

	-- Fix Normals and Fix Vertices are mutually exclusive: Fix Vertices' per-element
	-- SGs preserve hard edges across the weld, while Fix Normals forces every face
	-- to a single SG and resets normals. Running both produces smoothing artifacts
	-- across element seams, so enabling one disables the other.
	on ckbFixNormals changed st do
	(
		if st do ckbFixVertices.checked = false
	)
	on ckbFixVertices changed st do
	(
		if st do ckbFixNormals.checked = false
	)

	on ckbSplitDependencies changed state do
	( if ckbSplitDependencies.checked then ckbAutoBind.checked = false )

	on ckbAutoBind changed state do
	(
		if ckbAutoBind.checked then
		(
			ckbSplitDependencies.checked = false

			rbgAutoBind.enabled = true
			rbgAutoBind.state = 1

			ckbBatchProcessing.enabled = true

			-- Mutually exclusive with the 2023 WWSkin override on the Advanced
			-- tab — checking Auto-Bind clears it so users aren't confused why
			-- the radio choice is being ignored.
			if ckbUseWWSkin.checked do ckbUseWWSkin.checked = false
		)
		else
		(
			rbgAutoBind.enabled = false
			rbgAutoBind.state = 0

			ckbBatchProcessing.checked = false
			ckbBatchProcessing.enabled = false
		)
	)

	-- 2023 WWSkin override: when on, the binding path is forced to the new
	-- WWSkin Space Warp regardless of Basic-tab Auto-Bind, so reflect that in
	-- the UI by disabling the Basic Auto-Bind controls.
	on ckbUseWWSkin changed state do
	(
		if ckbUseWWSkin.checked then
		(
			ckbAutoBind.checked   = false
			ckbAutoBind.enabled   = false
			rbgAutoBind.enabled   = false
			rbgAutoBind.state     = 0
		)
		else
		(
			ckbAutoBind.enabled   = true
		)
	)

	-- External Skeleton: enables the Select Skeleton button. Unchecking clears
	-- the picked file so the next run falls back to the auto-derive path.
	on ckbUseExternalSkel changed state do
	(
		btnSelectSkeleton.enabled = state
		if not state do
		(
			externalSkeletonFile = undefined
			btnSelectSkeleton.caption = "Select Skeleton"
		)
	)

	on btnSelectSkeleton pressed do
	(
		local picked = getOpenFileName \
			caption:"Select Skeleton W3D" \
			types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
		if picked != undefined do
		(
			externalSkeletonFile = picked
			btnSelectSkeleton.caption = (filenameFromPath picked)
		)
	)

	on ckbBatchProcessing changed state do
	(
		if ckbBatchProcessing.checked then btnW3DImporter.caption = "Import files"
		else btnW3DImporter.caption = "Import a file"
	)

	-- Tab switcher: state 1 = Basic, state 2 = Advanced.
	on rbgTab changed st do
	(
		local basic = (st == 1)
		ckbSplitDependencies.visible = basic
		ckbAutoBind.visible          = basic
		rbgAutoBind.visible          = basic
		ckbBatchProcessing.visible   = basic
		ckbShowBoneFins.visible      = basic
		ckbPureAnim.visible          = basic

		ckbUseW3DMatl.visible        = not basic
		ckbDebugOutput.visible       = not basic
		ckbIgnoreErrors.visible      = not basic
		ckbFixNormals.visible        = not basic
		ckbTga2Dds.visible           = not basic
		ckbTga2DdsRev.visible        = not basic
		ckbFixVertices.visible       = not basic
		ckbNoMultiMat.visible        = not basic
		ckbUseWWSkin.visible         = not basic
		ckbImportExtendedW3D.visible = not basic
		ckbUseExternalSkel.visible   = not basic
		btnSelectSkeleton.visible    = not basic
	)

	on rltMain open do
	(
		-- Window caption carries the unified version (single source of truth
		-- at file top).
		rltMain.title = "W3D Importer " + ::W3DImporterVersion

		local i
		deltaTable = #()

		for i=1 to 16 do
		( append deltaTable (pow 10 (float(i)-7)) ) -- Technically needs to be i-9, but Max rounds 10^(-8) and 10^(-7) to 0
		for i=1 to 240 do
		( append deltaTable (1-sin(float(i-1)/240*90)) )

		-- Detect whether the W3D Tools material plugin is registered. If not, disable the checkbox.
		-- Writes the file-scope global ::w3dMatlAvailable so cfW3DImporter and the
		-- material builders share the same answer without re-probing every call.
		::w3dMatlAvailable = false
		try
		(
			local probe = W3DMaterial()
			if probe != undefined do ::w3dMatlAvailable = true
		)
		catch ( ::w3dMatlAvailable = false )
		ckbUseW3DMatl.enabled = ::w3dMatlAvailable
		if not ::w3dMatlAvailable do
		(
			ckbUseW3DMatl.checked = false
			ckbUseW3DMatl.caption = "Use W3D materials (not installed)"
		)
	)

	on btnRenegade pressed do
	(
		local fname = getOpenFileName caption:"Select Renegade W3D file" \
			types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
		if fname == undefined do return undefined
		try ( destroyDialog rltRenegade ) catch ()
		-- globals are the only reliable way to pass data into a rollout before createDialog.
		-- Use ::rnPendingFile to force global-scope assignment from inside the rollout.
		::rnPendingFile = fname
		createDialog rltRenegade
	)
)

global rnPendingFile = undefined
