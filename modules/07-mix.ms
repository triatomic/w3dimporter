-- ============================================================================
-- MIX file support (ported from w3d-importer-1.16b.ms)
-- Renegade .mix / .pkg / .dat container format. Layout (after the 4-byte
-- "MIX1" magic):
--   uint32 filesIndexOffset   -- jumps to the per-entry (id, offset, size) table
--   uint32 namesTableOffset   -- jumps to the parallel filename table
-- Names table: uint32 count, then `count` length-prefixed strings.
-- Files index: uint32 count, then `count` * (uint32 id, uint32 offset, uint32 size).
-- The two arrays share an index, so name[i] <-> entry[i].
-- ============================================================================

struct Mix_File
(
	MixID, MixFilesOffset, MixNamesOffset, MixNumFilesNames, MixNumFiles,
	MixFileID, MixFileOffset, MixFileSize,

	fn ReadMix MixStream =
	(
		local mixStr = ""
		for i = 1 to 4 do mixStr += bit.IntAsChar (readByte MixStream #unsigned)
		MixID = mixStr
		if MixID != "MIX1" do return false
		MixFilesOffset = ReadLong MixStream #unsigned
		MixNamesOffset = ReadLong MixStream #unsigned
		true
	),

	fn getMixFilesNames MixStream =
	(
		local filesNames = #()
		fseek MixStream MixNamesOffset #seek_Set
		MixNumFilesNames = ReadLong MixStream #unsigned
		for i = 1 to MixNumFilesNames do
		(
			local nameStr = ""
			local NameLen = ReadByte MixStream #unsigned
			for j = 1 to NameLen do nameStr += bit.IntAsChar (readByte MixStream #unsigned)
			append filesNames nameStr
		)
		filesNames
	),

	fn getMixFile MixStream FileIndex =
	(
		fseek MixStream MixFilesOffset #seek_Set
		MixNumFiles = ReadLong MixStream #unsigned
		if MixNumFiles != MixNumFilesNames do
		(
			format "Mix index/names mismatch: % vs %\n" MixNumFiles MixNumFilesNames
			return false
		)
		local fileIndexOffset = (ftell MixStream) + (12 * (FileIndex - 1))
		fseek MixStream fileIndexOffset #seek_Set
		MixFileID     = ReadLong MixStream #unsigned
		MixFileOffset = ReadLong MixStream #unsigned
		MixFileSize   = ReadLong MixStream #unsigned
		true
	)
)

-- Extract one entry from a mix to a temp file. Returns the temp path on
-- success, undefined on failure. NOTE: MAXScript file streams have no bulk
-- binary copy, so this is unavoidably one ReadByte/WriteByte pair per byte
-- (a 5 MB asset = ~10 million MAXScript calls; expect a few seconds). A
-- dotNet FileStream would be faster, but the importer is kept dotNet-free.
fn ExtractMixEntry mixPath entryName outPath =
(
	local mixStream = fopen mixPath "rb"
	if mixStream == undefined do return undefined
	local mf = Mix_File()
	if not mf.ReadMix mixStream do ( fclose mixStream; return undefined )
	local names = mf.getMixFilesNames mixStream
	local idx = findItem names entryName
	if idx == 0 do ( fclose mixStream; return undefined )
	if not mf.getMixFile mixStream idx do ( fclose mixStream; return undefined )

	fseek mixStream mf.MixFileOffset #seek_Set
	local out = fopen outPath "wb"
	if out == undefined do ( fclose mixStream; return undefined )

	for i = 1 to mf.MixFileSize do WriteByte out (ReadByte mixStream #unsigned)
	fclose out
	fclose mixStream
	outPath
)

-- Multi-select listbox of .w3d entries inside the chosen mix. The listbox is
-- populated by the caller before the dialog opens (via global so the rollout
-- doesn't need a struct-style accessor).
global mixDlgEntries = #()
global mixDlgSelected = #()
global mixDlgUseAdvanced = false

rollout SelectFromMixDlg "Select W3D File(s) From Mix" width:340 height:465
(
	multiListBox lbW3D "" pos:[10,10] width:320 height:25
	checkbox ckbAdvanced "Use Advanced Import for each file" pos:[10,395] width:300 height:18 \
		tooltip:"When checked, each selected entry opens the Renegade Advanced Import dialog (LOD / mesh / proxy / animation picker) per file. Otherwise files import in bulk using the Basic-tab settings."
	button btnAll    "All"     pos:[10,420] width:50
	button btnNone   "None"    pos:[65,420] width:50
	button btnInvert "Invert"  pos:[120,420] width:60
	button btnImport "Import"  pos:[195,420] width:65 default:true
	button btnCancel "Cancel"  pos:[265,420] width:65

	on SelectFromMixDlg open do
	(
		lbW3D.items = mixDlgEntries
		mixDlgSelected = #()
		ckbAdvanced.checked = mixDlgUseAdvanced
		-- Dynamic tooltip: temp dir varies per user (lives under their AppData),
		-- so resolve at open-time rather than baking it in.
		btnImport.tooltip = "Extracts selected entries to:\n" + (getDir #temp)
	)

	on btnAll    pressed do lbW3D.selection = #{1..lbW3D.items.count}
	on btnNone   pressed do lbW3D.selection = #{}
	on btnInvert pressed do
	(
		local inv = #{}
		for i = 1 to lbW3D.items.count do if not lbW3D.selection[i] do inv[i] = true
		lbW3D.selection = inv
	)
	on btnImport pressed do
	(
		local picks = #()
		for i in lbW3D.selection do append picks lbW3D.items[i]

		-- Warn before committing to N Advanced dialogs in a row, since the user
		-- has to click through each one. >=2 because a single file getting one
		-- dialog is the expected Advanced flow, no warning needed.
		if ckbAdvanced.checked and picks.count >= 2 do
		(
			local msg = "You selected " + (picks.count as string) + " files with Advanced Import enabled.\n" + \
				"The Advanced Import dialog will open " + (picks.count as string) + " times in sequence — " + \
				"once per file.\n\nContinue?"
			if not (queryBox msg title:"Multiple Advanced Imports" beep:true) do return false
		)

		mixDlgSelected = picks
		mixDlgUseAdvanced = ckbAdvanced.checked
		destroyDialog SelectFromMixDlg
	)
	on btnCancel pressed do
	(
		mixDlgSelected = #()
		destroyDialog SelectFromMixDlg
	)
)

-- File > Select From Mix handler. Opens the mix, lists .w3d entries, lets the
-- user pick (multi-select), extracts each selected entry to (getDir #temp),
-- and runs cfW3DImporter on each. Per-file Basic-tab settings (no Advanced
-- dialog) — bulk operations shouldn't pop N dialogs.
fn DoSelectFromMix =
(
	local mixPath = getOpenFileName caption:"Select Mix file" \
		types:"MIX (*.mix)|*.mix|Package (*.pkg)|*.pkg|DAT (*.dat)|*.dat|All Files (*.*)|*.*|"
	if mixPath == undefined do return false

	-- Parse the mix index up front so we can populate the dialog.
	local s = fopen mixPath "rb"
	if s == undefined do ( messageBox "Could not open mix file." beep:true; return false )
	local mf = Mix_File()
	if not mf.ReadMix s do
	(
		fclose s
		messageBox "Invalid or unsupported mix file (no MIX1 magic)." beep:true
		return false
	)
	local names = mf.getMixFilesNames s
	fclose s

	-- Filter to .w3d only, sorted for browsability.
	local w3dEntries = #()
	for n in names do
		if matchPattern (getFileNameType n) pattern:".w3d" do append w3dEntries n
	if w3dEntries.count == 0 do
	(
		messageBox "No .w3d entries found in this mix." title:"Empty Mix" beep:true
		return false
	)
	sort w3dEntries

	mixDlgEntries  = w3dEntries
	mixDlgSelected = #()
	createDialog SelectFromMixDlg modal:true style:#(#style_titlebar, #style_sysmenu, #style_resizing)
	if mixDlgSelected.count == 0 do return false

	-- Snapshot the Basic-tab settings once; mix-extracted files all use the
	-- same config (consistent with batch-import behaviour). Mirrors btnW3DImporter's
	-- non-batch branch so prefs / WWSkin / split / auto-bind all apply.
	local splt   = try ( rltMain.ckbSplitDependencies.checked ) catch ( false )
	local autoB  = try ( rltMain.rbgAutoBind.state )            catch ( 0 )
	local dbg    = try ( rltMain.ckbDebugOutput.checked )       catch ( false )
	local w3dmat = try ( rltMain.ckbUseW3DMatl.checked )        catch ( false )
	local ignE   = try ( not rltMain.ckbIgnoreErrors.checked )  catch ( true )
	local fxN    = try ( rltMain.ckbFixNormals.checked )        catch ( false )
	local t2d    = try ( rltMain.ckbTga2Dds.checked )           catch ( false )
	local fxV    = try ( rltMain.ckbFixVertices.checked )       catch ( false )
	local nmm    = try ( rltMain.ckbNoMultiMat.checked )        catch ( false )
	local t2dr   = try ( rltMain.ckbTga2DdsRev.checked )        catch ( false )
	local wwsk   = try ( rltMain.ckbUseWWSkin.checked )         catch ( false )
	local extW3D = try ( rltMain.ckbImportExtendedW3D.checked ) catch ( false )
	local extSkel = try ( if rltMain.ckbUseExternalSkel.checked then rltMain.externalSkeletonFile else undefined ) catch ( undefined )

	local tmpDir = getDir #temp
	local mixBase = getFilenameFile mixPath
	local extracted = #()
	for entry in mixDlgSelected do
	(
		-- Namespace temp filenames by mix basename so two mixes with the same
		-- entry name don't clobber each other across consecutive imports.
		local outPath = tmpDir + "\\w3di_" + mixBase + "_" + entry
		local got = ExtractMixEntry mixPath entry outPath
		if got != undefined then append extracted got
		else format "Failed to extract: %\n" entry
	)
	if extracted.count == 0 do
	(
		messageBox "Extraction failed for all selected entries." beep:true
		return false
	)

	if mixDlgUseAdvanced then
	(
		-- Open the Renegade Advanced dialog once per extracted file. Modal so
		-- the loop blocks until the user clicks Import / Cancel / Bones-only,
		-- which is the only way to drive a one-at-a-time inspect-and-import
		-- flow without dropping files. The Renegade dialog already calls
		-- cfW3DImporter and destroys itself on its terminal buttons.
		for f in extracted do
		(
			try ( destroyDialog rltRenegade ) catch ()
			::rnPendingFile = f
			createDialog rltRenegade modal:true
		)
	)
	else
	(
		-- batch=false: cfW3DImporter only pops the file picker when batch=false AND
		-- w3dfilename==undefined; we always pass a path here, so the picker stays
		-- shut. batch=true would also save the imported scene as a .max next to the
		-- source and reset the scene — fine for folder batches, wrong for us.
		for f in extracted do
			cfW3DImporter f splt autoB false dbg w3dmat ignE fxN t2d fxV nmm t2dr wwsk extSkel extW3D
	)
	true
)

