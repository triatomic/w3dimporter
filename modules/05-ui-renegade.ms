-- ---------------------------------------------------------------------------
-- Renegade Import dialog  (mirrors 1.16b W3DImportDlg layout)
-- Parses a picked .w3d using existing script-scope readers, shows all lists,
-- then calls cfW3DImporter with an optional RenegadeSelection filter.
-- ---------------------------------------------------------------------------
rollout rltRenegade "W3D Importer - Advanced" width:718 height:575 silentErrors:false
(
	-- parsed data kept at rollout scope so import handlers can read it
	local rnFilename   = undefined
	local rnParsedHier = undefined
	local rnParsedHlod = undefined
	local rnMeshNames  = #()   -- "CONTAINER.MESH" strings from HLOD sub-objects
	local rnBoneNames  = #()   -- pivot names
	local rnAggNames   = #()   -- aggregate short names
	local rnProxNames  = #()   -- proxy short names
	local rnAnimFrames = 0     -- frame count from anim header (0 = no animation)
	local rnAnimRate   = 0     -- fps from anim header

	-- ---- Import Options outer box ----
	groupBox grpOptions "Import Options:" pos:[4,5] width:710 height:431

	-- Meshes
	groupBox grpMeshSel "Meshes Selection:" pos:[13,25] width:226 height:261
	multiListBox mlbMeshes "" pos:[22,43] width:208 height:15
	button btnMeshAll    "All"    pos:[23,254]  width:64
	button btnMeshInvert "Invert" pos:[94,254]  width:64
	button btnMeshClear  "Clear"  pos:[165,254] width:64

	-- Proxies
	groupBox grpProxSel "Proxies Selection:" pos:[246,25] width:226 height:261
	multiListBox mlbProxies "" pos:[255,43] width:208 height:15
	button btnProxAll    "All"    pos:[256,254] width:64
	button btnProxInvert "Invert" pos:[327,254] width:64
	button btnProxClear  "Clear"  pos:[398,254] width:64

	-- Aggregates
	groupBox grpAggSel "Aggregates Selection:" pos:[479,25] width:226 height:192
	multiListBox mlbAgg "" pos:[488,43] width:208 height:10
	button btnAggAll    "All"    pos:[489,187] width:64
	button btnAggInvert "Invert" pos:[560,187] width:64
	button btnAggClear  "Clear"  pos:[631,187] width:64

	-- Dazzles (display only — dazzles not imported by cfW3DImporter)
	groupBox grpDazzSel "Dazzles Selection:" pos:[479,227] width:226 height:200
	multiListBox mlbDazzles "" pos:[488,246] width:208 height:10
	button btnDazzAll    "All"    pos:[489,395] width:64
	button btnDazzInvert "Invert" pos:[560,395] width:64
	button btnDazzClear  "Clear"  pos:[631,395] width:64

	-- Animation: dropdown gates the From/To spinners.
	-- Items + spinner range are populated from the file's actual frame count
	-- in populateDialog(). Disabled when ckbImportAnim is unchecked.
	groupBox grpAnim "Animation:" pos:[13,296] width:226 height:61
	checkbox ckbImportAnim "Import Animation Frames" pos:[23,314] checked:true
	dropDownList ddlAnimRange "" pos:[23,335] width:96 items:#("All Frames", "Custom Range")
	spinner spnAnimFrom "F:" type:#integer pos:[131,338] fieldwidth:32 range:[0,99999,0]
	spinner spnAnimTo   "T:" type:#integer pos:[183,338] fieldwidth:32 range:[0,99999,0]

	-- LOD: dropdown is populated in populateDialog() based on actual LOD count.
	-- Items: "All", "0".."N-1" (capped to lodArrays.count), "None".
	groupBox grpLod "Level Of Details:" pos:[13,367] width:226 height:60
	dropDownList ddlLod "Import:" pos:[23,384] width:206 height:40 items:#("All")

	-- Bones
	groupBox grpBones "Bones:" pos:[246,296] width:226 height:131
	checkbox ckbImportBones    "Import Bones"                         pos:[256,314] checked:true
	checkbox ckbDepBones       "Bones in Selection's Hierarchy Only"  pos:[256,333] checked:false enabled:false \
		tooltip:"Only meaningful with 'Import Selected'. When checked, only bones referenced by the selected meshes (and their parent ancestors) are created. Bones unrelated to the selection are skipped."
	checkbox ckbOriginBone     "Create Origin Bone"                   pos:[256,352] checked:false \
		tooltip:"Add a single Max Bone at world origin and reparent the imported root pivots under it. Useful as a single transform handle for the whole rig."
	checkbox ckbLodBones       "Create A Set Of Bones For Each LOD"   pos:[256,371] checked:false enabled:false \
		tooltip:"Not implemented. W3D files share one hierarchy across all LODs by design, so per-LOD bone duplication doesn't round-trip through the exporter."
	button   btnBonesOnly      "Import Bones Only" pos:[281,395] width:156

	-- W3D File Properties
	groupBox grpProps "W3D File Properties:" pos:[4,446] width:590 height:126

	label lblNameL     "Name :"       pos:[23,465]
	label lblNameV     "N/A"          pos:[65,465]  width:200 align:#left
	label lblTypeL     "Type :"       pos:[27,485]
	label lblTypeV     "N/A"          pos:[65,485]  width:200 align:#left
	label lblLodL      "LOD :"        pos:[29,505]
	label lblLodV      "N/A"          pos:[65,505]  width:37  align:#left
	label lblMeshL     "Meshes :"     pos:[14,525]
	label lblMeshV     "N/A"          pos:[65,525]  width:37  align:#left
	label lblFramesL   "Frames :"     pos:[17,545]
	label lblFramesV   "N/A"          pos:[65,545]  width:37  align:#left
	label lblBonesL    "Bones :"      pos:[155,505]
	label lblBonesV    "N/A"          pos:[200,505] width:37  align:#left
	label lblAggL      "Aggregates :" pos:[131,525]
	label lblAggV      "N/A"          pos:[200,525] width:37  align:#left
	label lblFrameRtL  "Frame Rate :" pos:[130,545]
	label lblFrameRtV  "N/A"          pos:[200,545] width:37  align:#left
	label lblProxL     "Proxies :"    pos:[287,505]
	label lblProxV     "N/A"          pos:[336,505] width:37  align:#left
	label lblDazzL     "Dazzles :"    pos:[284,525]
	label lblDazzV     "N/A"          pos:[336,525] width:37  align:#left
	label lblBoxesL    "Boxes :"      pos:[292,545]
	label lblBoxesV    "N/A"          pos:[336,545] width:37  align:#left

	-- Bones list
	groupBox grpBoneList "Bones List:" pos:[401,465] width:184 height:98
	listBox lbBonesList "" pos:[410,483] width:168 height:5

	-- Right-side action buttons
	button btnImportSel "Import Selected" pos:[610,472] width:100
	button btnImport    "Import"          pos:[610,501] width:100
	button btnCancel    "Cancel"          pos:[610,530] width:100

	-- ---- helpers ----
	-- Toggles enabled-state of the animation range controls based on the master
	-- "Import Animation Frames" checkbox and the Range dropdown.
	-- Defined before populateDialog so the forward call resolves.
	fn updateAnimEnabled =
	(
		local masterOn = ckbImportAnim.enabled and ckbImportAnim.checked
		ddlAnimRange.enabled = masterOn
		local custom = masterOn and (ddlAnimRange.selection == 2)
		spnAnimFrom.enabled = custom
		spnAnimTo.enabled   = custom
	)

	fn populateDialog =
	(
		-- properties
		local modelName = if rnFilename != undefined then getFilenameFile rnFilename else "N/A"
		local modelType = "N/A"
		if rnParsedHlod != undefined and rnParsedHlod.header != undefined do
		(
			modelName = rnParsedHlod.header.hlodName as string
			modelType = "HLOD"
		)
		if rnParsedHier != undefined and rnParsedHier.header != undefined do
		(
			if modelType == "N/A" do modelName = rnParsedHier.header.hierName as string
			modelType = if rnParsedHlod != undefined then "HLOD + Hierarchy" else "Hierarchy"
		)
		lblNameV.caption = modelName
		lblTypeV.caption = modelType

		local lodCnt  = if rnParsedHlod != undefined then rnParsedHlod.lodArrays.count else 0
		local aggCnt  = rnAggNames.count
		local proxCnt = rnProxNames.count
		local boneCnt = rnBoneNames.count

		lblLodV.caption    = lodCnt          as string
		lblMeshV.caption   = rnMeshNames.count as string
		lblBonesV.caption  = boneCnt         as string
		lblAggV.caption    = aggCnt          as string
		lblProxV.caption   = proxCnt         as string
		lblDazzV.caption   = "0"
		lblBoxesV.caption  = "0"
		lblFramesV.caption  = if rnAnimFrames > 0 then (rnAnimFrames as string) else "N/A"
		lblFrameRtV.caption = if rnAnimRate   > 0 then (rnAnimRate   as string) else "N/A"

		mlbMeshes.items   = rnMeshNames
		mlbProxies.items  = rnProxNames
		mlbAgg.items      = rnAggNames
		mlbDazzles.items  = #()
		lbBonesList.items = rnBoneNames

		-- LOD dropdown: "All", one entry per LOD index (capped to lodArrays.count), "None"
		local lodItems = #("All")
		for i = 0 to (lodCnt - 1) do append lodItems (i as string)
		append lodItems "None"
		ddlLod.items     = lodItems
		ddlLod.selection = 1   -- default: All
		ddlLod.enabled   = (lodCnt > 0)

		-- Animation: pre-fill spinners with the file's actual frame range.
		-- frame indices in W3D animations are 0-based; "All" means [0..frameCount-1].
		local maxFrame = if rnAnimFrames > 0 then (rnAnimFrames - 1) else 0
		spnAnimFrom.range = [0, maxFrame, 0]
		spnAnimTo.range   = [0, maxFrame, maxFrame]
		spnAnimFrom.value = 0
		spnAnimTo.value   = maxFrame
		ckbImportAnim.enabled = (rnAnimFrames > 0)
		if not ckbImportAnim.enabled do ckbImportAnim.checked = false
		ddlAnimRange.selection = 1
		updateAnimEnabled()

		btnImport.enabled    = (rnFilename != undefined)
		btnImportSel.enabled = false
	)

	fn getSelectedItems mlb =
	(
		local sel = #()
		for i = 1 to mlb.items.count do
			if mlb.selection[i] do append sel mlb.items[i]
		sel
	)

	fn doImport selOnly =
	(
		if rnFilename == undefined do return undefined
		-- capture everything into true locals before destroying the dialog,
		-- since destroying the rollout clears rollout-scope variables
		local importFile = rnFilename
		local doAnim     = ckbImportAnim.checked
		local doBones    = ckbImportBones.checked
		-- LOD dropdown: index 1 = "All" (-1), last = "None" (-2), middle = LOD index (0-based)
		local lodSel = ddlLod.selection
		local lodN   = ddlLod.items.count
		local lodMd  = if lodSel == 1 then -1 else if lodSel == lodN then -2 else (lodSel - 2)
		-- Animation range: -1/-1 = all frames; otherwise honor user-chosen [from..to]
		local aFrom = -1
		local aTo   = -1
		if doAnim and ddlAnimRange.selection == 2 do
		(
			aFrom = spnAnimFrom.value
			aTo   = spnAnimTo.value
		)
		-- DepBones only takes effect with selOnly + a non-empty meshes list
		-- (computeBones gates on rnSelection.meshes.count > 0). The flag is
		-- still passed through for "Import All" so the importer's behaviour
		-- is fully described by the selection struct, but it'll no-op there.
		local depB   = ckbDepBones.checked
		local origB  = ckbOriginBone.checked
		local sel = if selOnly then
		(
			local sm = getSelectedItems mlbMeshes
			local sp = getSelectedItems mlbProxies
			local sa = getSelectedItems mlbAgg
			RenegadeSelection meshes:sm proxies:sp aggregates:sa importAnim:doAnim importBones:doBones bonesOnly:false lodMode:lodMd animFrom:aFrom animTo:aTo depBonesOnly:depB originBone:origB
		)
		else
		(
			RenegadeSelection meshes:#() proxies:#() aggregates:#() importAnim:doAnim importBones:doBones bonesOnly:false lodMode:lodMd animFrom:aFrom animTo:aTo depBonesOnly:depB originBone:origB
		)

		-- snapshot settings from rltMain Advanced tab BEFORE destroying any dialog,
		-- so the import path uses the same options the regular Import button would.
		-- Wrap in try/catch per-control so a missing/renamed control falls back safely.
		local dbg    = try ( rltMain.ckbDebugOutput.checked )       catch ( false )
		local w3dmat = try ( rltMain.ckbUseW3DMatl.checked )        catch ( false )
		local extW3D = try ( rltMain.ckbImportExtendedW3D.checked ) catch ( false )
		local fxN    = try ( rltMain.ckbFixNormals.checked )        catch ( false )
		local fxV    = try ( rltMain.ckbFixVertices.checked )       catch ( false )
		local t2d    = try ( rltMain.ckbTga2Dds.checked )           catch ( false )
		local t2dr   = try ( rltMain.ckbTga2DdsRev.checked )        catch ( false )
		local nmm    = try ( rltMain.ckbNoMultiMat.checked )        catch ( false )
		local wwsk   = try ( rltMain.ckbUseWWSkin.checked )         catch ( false )
		local splt   = try ( rltMain.ckbSplitDependencies.checked ) catch ( false )
		local autoB  = try ( rltMain.rbgAutoBind.state )            catch ( 0 )
		local ignE   = try ( not rltMain.ckbIgnoreErrors.checked )  catch ( true )
		-- externalSkeletonFile is a rollout-LOCAL of rltMain; the bare name here
		-- (inside rltRenegade) silently reads an unrelated undefined global and
		-- the catch never fires. Must be qualified, same as DoSelectFromMix does.
		local extSkel = try ( if rltMain.ckbUseExternalSkel.checked then rltMain.externalSkeletonFile else undefined ) catch ( undefined )

		try ( destroyDialog rltRenegade ) catch ()

		cfW3DImporter importFile splt autoB false dbg w3dmat ignE fxN t2d fxV nmm t2dr wwsk extSkel extW3D rnSelection:sel
	)

	-- DepBones only makes sense when there's a non-empty mesh subset selected
	-- (it walks selected meshes' vertInfs to compute the keep-set). Mirrors
	-- the meshes-multi-listbox state across every site that mutates it.
	fn _refreshDepEnabled =
	(
		ckbDepBones.enabled = (getSelectedItems mlbMeshes).count > 0
		if not ckbDepBones.enabled do ckbDepBones.checked = false
	)

	-- ---- list button handlers ----
	on btnMeshAll    pressed do ( mlbMeshes.selection  = #{1..mlbMeshes.items.count};   btnImportSel.enabled = true; _refreshDepEnabled() )
	on btnMeshClear  pressed do ( mlbMeshes.selection  = #{};                           btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0; _refreshDepEnabled() )
	on btnMeshInvert pressed do
	(
		local inv = #{}
		for i = 1 to mlbMeshes.items.count do if not mlbMeshes.selection[i] do inv[i] = true
		mlbMeshes.selection = inv
		btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0
		_refreshDepEnabled()
	)

	on btnProxAll    pressed do ( mlbProxies.selection = #{1..mlbProxies.items.count};  btnImportSel.enabled = true )
	on btnProxClear  pressed do ( mlbProxies.selection = #{};                           btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0 )
	on btnProxInvert pressed do
	(
		local inv = #{}
		for i = 1 to mlbProxies.items.count do if not mlbProxies.selection[i] do inv[i] = true
		mlbProxies.selection = inv
		btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0
	)

	on btnAggAll    pressed do ( mlbAgg.selection = #{1..mlbAgg.items.count};            btnImportSel.enabled = true )
	on btnAggClear  pressed do ( mlbAgg.selection = #{};                                 btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0 )
	on btnAggInvert pressed do
	(
		local inv = #{}
		for i = 1 to mlbAgg.items.count do if not mlbAgg.selection[i] do inv[i] = true
		mlbAgg.selection = inv
		btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0
	)

	on btnDazzAll    pressed do mlbDazzles.selection = #{1..mlbDazzles.items.count}
	on btnDazzClear  pressed do mlbDazzles.selection = #{}
	on btnDazzInvert pressed do
	(
		local inv = #{}
		for i = 1 to mlbDazzles.items.count do if not mlbDazzles.selection[i] do inv[i] = true
		mlbDazzles.selection = inv
	)

	-- enable Import Selected whenever any list selection changes
	on mlbMeshes   selected i do ( btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0; _refreshDepEnabled() )
	on mlbProxies  selected i do btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0
	on mlbAgg      selected i do btnImportSel.enabled = (getSelectedItems mlbMeshes).count > 0 or (getSelectedItems mlbProxies).count > 0 or (getSelectedItems mlbAgg).count > 0

	on btnBonesOnly pressed do
	(
		local importFile = rnFilename
		local doAnim     = ckbImportAnim.checked
		local dbg    = try ( rltMain.ckbDebugOutput.checked )       catch ( false )
		local w3dmat = try ( rltMain.ckbUseW3DMatl.checked )        catch ( false )
		local extW3D = try ( rltMain.ckbImportExtendedW3D.checked ) catch ( false )
		local fxN    = try ( rltMain.ckbFixNormals.checked )        catch ( false )
		local fxV    = try ( rltMain.ckbFixVertices.checked )       catch ( false )
		local t2d    = try ( rltMain.ckbTga2Dds.checked )           catch ( false )
		local t2dr   = try ( rltMain.ckbTga2DdsRev.checked )        catch ( false )
		local nmm    = try ( rltMain.ckbNoMultiMat.checked )        catch ( false )
		local wwsk   = try ( rltMain.ckbUseWWSkin.checked )         catch ( false )
		local splt   = try ( rltMain.ckbSplitDependencies.checked ) catch ( false )
		local autoB  = try ( rltMain.rbgAutoBind.state )            catch ( 0 )
		local ignE   = try ( not rltMain.ckbIgnoreErrors.checked )  catch ( true )
		-- externalSkeletonFile is a rollout-LOCAL of rltMain; the bare name here
		-- (inside rltRenegade) silently reads an unrelated undefined global and
		-- the catch never fires. Must be qualified, same as DoSelectFromMix does.
		local extSkel = try ( if rltMain.ckbUseExternalSkel.checked then rltMain.externalSkeletonFile else undefined ) catch ( undefined )
		try ( destroyDialog rltRenegade ) catch ()
		local bSel   = RenegadeSelection meshes:#() proxies:#() aggregates:#() importAnim:doAnim importBones:true bonesOnly:true lodMode:-1 animFrom:-1 animTo:-1 depBonesOnly:false originBone:ckbOriginBone.checked
		cfW3DImporter importFile splt autoB false dbg w3dmat ignE fxN t2d fxV nmm t2dr wwsk extSkel extW3D rnSelection:bSel
	)

	on btnImport    pressed do doImport false
	on btnImportSel pressed do doImport true
	on btnCancel    pressed do ( try ( destroyDialog rltRenegade ) catch () )

	-- Animation control wiring
	on ckbImportAnim changed v do updateAnimEnabled()
	on ddlAnimRange  selected i do updateAnimEnabled()
	-- Keep From <= To when the user edits either spinner
	on spnAnimFrom changed v do ( if spnAnimTo.value < v do spnAnimTo.value = v )
	on spnAnimTo   changed v do ( if spnAnimFrom.value > v do spnAnimFrom.value = v )

	on rltRenegade open do
	(
		-- pick up the filename passed via global from btnRenegade.
		-- Use ::rnPendingFile to force global-scope access; otherwise MAXScript
		-- treats the bare name as a rollout-local and reads undefined.
		local _pf = ::rnPendingFile
		rnFilename = if _pf != undefined then _pf else undefined
		::rnPendingFile = undefined
		if rnFilename == undefined do
		(
			try ( destroyDialog rltRenegade ) catch ()
			return undefined
		)

		-- parse the file using existing script-scope readers
		local fs = fopen rnFilename "rb"
		if fs == undefined do
		(
			messageBox ("Could not open: " + rnFilename) title:"Renegade Inspector"
			try ( destroyDialog rltRenegade ) catch ()
			return undefined
		)

		-- Guarantee fclose on parse failure so the .w3d isn't locked for the rest
		-- of the Max session if a malformed chunk throws below.
		try
		(
		fseek fs 0 #seek_end
		local fsize = ftell fs
		fseek fs 0 #seek_set

		rnParsedHier = undefined
		rnParsedHlod = undefined
		rnMeshNames  = #()
		rnBoneNames  = #()
		rnAggNames   = #()
		rnProxNames  = #()
		rnAnimFrames = 0
		rnAnimRate   = 0

		while (ftell fs < fsize) do
		(
			local cType = ReadLong fs #unsigned
			local cSize = GetChunkSize(ReadLong fs #unsigned)
			local cEnd  = (ftell fs) + cSize
			case cType of
			(
				0x00000100: ( rnParsedHier = ReadHierarchy fs cEnd )
				0x00000000:
				(
					local mhdr = undefined
					while (ftell fs < cEnd) and (mhdr == undefined) do
					(
						local scType = ReadLong fs #unsigned
						local scSize = GetChunkSize(ReadLong fs #unsigned)
						local scEnd  = (ftell fs) + scSize
						if scType == 0x0000001F then mhdr = ReadMeshHeader fs
						fseek fs scEnd #seek_set
					)
					if mhdr != undefined do
						append rnMeshNames (mhdr.containerName + "." + mhdr.meshName)
					fseek fs cEnd #seek_set
				)
				0x00000700: ( rnParsedHlod = ReadHLod fs cEnd )
				0x00000200: -- W3D_CHUNK_ANIMATION
				(
					-- only read the header sub-chunk (0x201), skip the rest
					while (ftell fs < cEnd) do
					(
						local scType = ReadLong fs #unsigned
						local scSize = GetChunkSize(ReadLong fs #unsigned)
						local scEnd  = (ftell fs) + scSize
						if scType == 0x00000201 then
						(
							local ah = ReadAnimationHeader fs
							rnAnimFrames = ah.frameCount
							rnAnimRate   = ah.frameRate
						)
						fseek fs scEnd #seek_set
					)
				)
				0x00000280: -- W3D_CHUNK_COMPRESSED_ANIMATION
				(
					while (ftell fs < cEnd) do
					(
						local scType = ReadLong fs #unsigned
						local scSize = GetChunkSize(ReadLong fs #unsigned)
						local scEnd  = (ftell fs) + scSize
						if scType == 0x00000281 then
						(
							local ah = ReadCompressedAnimationHeader fs
							rnAnimFrames = ah.frameCount
							rnAnimRate   = ah.frameRate
						)
						fseek fs scEnd #seek_set
					)
				)
				default:    ( fseek fs cSize #seek_cur )
			)
		)
		)
		catch
		(
			fclose fs
			fs = undefined
			format "*** Renegade pre-scan failed for %; closing handle and rethrowing.\n" rnFilename
			throw()
		)
		if fs != undefined do fclose fs

		-- build name lists from parsed data
		if rnParsedHlod != undefined then
		(
			rnMeshNames = #()
			for a = 1 to rnParsedHlod.lodArrays.count do
			(
				local arr = rnParsedHlod.lodArrays[a]
				for o = 1 to arr.lodObjects.count do
					append rnMeshNames arr.lodObjects[o].lodName
			)
			if rnParsedHlod.aggregates != undefined do
				for i = 1 to rnParsedHlod.aggregates.count do
				(
					local dotPos = findString rnParsedHlod.aggregates[i].name "."
					append rnAggNames (if dotPos != undefined then subString rnParsedHlod.aggregates[i].name (dotPos+1) -1 else rnParsedHlod.aggregates[i].name)
				)
			if rnParsedHlod.proxies != undefined do
				for i = 1 to rnParsedHlod.proxies.count do
				(
					local dotPos = findString rnParsedHlod.proxies[i].name "."
					append rnProxNames (if dotPos != undefined then subString rnParsedHlod.proxies[i].name (dotPos+1) -1 else rnParsedHlod.proxies[i].name)
				)
		)
		if rnParsedHier != undefined and rnParsedHier.pivots != undefined do
			for i = 1 to rnParsedHier.pivots.count do
				append rnBoneNames (rnParsedHier.pivots[i].pivotName as string)

		populateDialog()
	)
)

