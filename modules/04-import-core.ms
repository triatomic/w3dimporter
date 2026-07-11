function cfW3DImporter w3dfilename splitMeshes autoBindType batch debugOutput useW3DMatl ignoreErrors fixNormals tga2dds fixVertices noMultiMat tga2ddsRev useWWSkin externalSkelFile importExtendedW3D rnSelection:undefined =
(
	-- Version lives in the file-top global; see its comment for the bump rule.
	local importerVersion = ::W3DImporterVersion
	if debugOutput do
	(
		format "=================================================\n"
		format " w3dimporter % loaded from script\n" importerVersion
		format " CABAL: initializing %\n" (bit.intAsHex (random 0 0x7FFFFFFF))
		format "=================================================\n"
	)

	-- Fallback W3DMaterial-plugin probe for the batch / no-rollout path.
	-- The rltMain open handler normally writes ::w3dMatlAvailable when the UI
	-- is shown, but batch callers can reach cfW3DImporter without ever opening
	-- the dialog. Probe once here so the material builders below can rely on
	-- the flag being a bool rather than undefined.
	if ::w3dMatlAvailable == undefined do
	(
		::w3dMatlAvailable = false
		try
		(
			local probe = W3DMaterial()
			if probe != undefined do ::w3dMatlAvailable = true
		)
		catch ( ::w3dMatlAvailable = false )
		if debugOutput do format " W3DMaterial plugin available: %\n" ::w3dMatlAvailable
	)
	if useW3DMatl and not ::w3dMatlAvailable do
	(
		format "*** W3DMaterial plugin not installed -- falling back to Standard materials.\n"
		useW3DMatl = false
	)

	-- for the interface in future version
	userSeparateMaterial = false

	global anim = undefined
	global cmpAnim = undefined
	-- Last skeleton w3d that was successfully loaded by cfW3DImporter (whether
	-- auto-derived from the HLOD/anim header or picked via Use External Skeleton).
	-- Lets follow-up operations (e.g. Batch Anims to XAF) reuse the same rig
	-- without re-prompting the user for a file they already chose.
	global lastUsedSkeletonFile = undefined
	global hier = undefined
	global meshes = #()
	global hlodSet = undefined
	global pickbox = undefined

	global gmPivots = #()
	global gmMeshes = #()

	global depStacks = #()

	global maxBinding = false
	global wwBinding = false

	-- Binding type (if any)
	-- When ckbUseWWSkin (Advanced tab) is checked, override the radio-button
	-- choice and force the 2023 WWSkin path, which constructs the WSM via the
	-- C++ class registered in max2w3d.dle (class name "WWSkin"). The legacy
	-- `wwSkinSpaceWarp` constructor never resolves on a 2023 toolchain build,
	-- so the historical fallback would always have hit Max's native Skin.
	if useWWSkin then
	(
		-- WSM Object classes get a `SpaceWarp` suffix in MAXScript: our C++
		-- InternalName "WWSkin" is exposed as the constructor `WWSkinSpaceWarp`.
		try ( wwSkin = WWSkinSpaceWarp pos:[0,0,-15] isSelected:off )
		catch
		(
			wwSkin = undefined
			messageBox "Use 2023WWSkin is checked but creating a WWSkin Space Warp failed.\nMake sure max2w3d.dle (Phase 1+ of the WWSkin port) is installed and registered." title:"WWSkin unavailable" beep:true
		)
		if wwSkin != undefined then
		(
			wwBinding = true
			maxBinding = false
		)
		else
		(
			-- Fall back to native Skin so the import doesn't silently produce an unrigged mesh.
			wwBinding = false
			maxBinding = true
		)
	)
	else if (autoBindType > 0) do
	(
		maxBinding = (autoBindType == 1)
		if (autoBindType == 2) do
		(
			wwBinding = true
			try ( wwSkin = wwSkinSpaceWarp pos:[0,0,-15] isSelected:off )
			catch
			(
				wwBinding = false
				if (queryBox "Unable to create WWSkin!\nW3d binding cannot be done!\n\nWould you like to use 3dsMax's skin modifier instead?" title:"Error!" beep:true) then
				( maxBinding = true )
				else (maxBinding = false)
			)
		)
	)

	fn GetHLodObject searchName =
	(
		--renegade: search across all LOD arrays (Generals models have only one, so no perf impact)
		for a = 1 to hlodSet.lodArrays.count do
		(
			local arr = hlodSet.lodArrays[a]
			for i = 1 to arr.lodObjects.count do
			( if searchName == arr.lodObjects[i].lodName do return arr.lodObjects[i] )
		)
		result = undefined
	)

	if not batch and w3dfilename == undefined do
	( w3dfilename = getOpenFileName caption:"W3D Import Dialogue" types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|" )

	if w3dfilename != undefined then
	(
		fstream = fopen w3dfilename "rb"  ---binary
		if fstream == undefined then
		(
			messageBox ("Could not open W3D file:\n" + w3dfilename) title:"W3D import" beep:true
			return undefined
		)
		-- Guarantee fclose on a parse exception. Without this, a corrupt chunk
		-- leaks the handle and Max keeps the .w3d locked until restart.
		try
		(
		fseek fstream 0 #seek_end
		filesize = ftell fstream
		fseek fstream 0 #seek_set

		while (ftell fstream < filesize) do -- or (CounterAux < 100)) do
		(
			chunkType = ReadLong fstream #unsigned
			------ debug start ------
			--chunkSize = ReadLong fstream
			--print (bit.intAsHex chunkSize)
			--chunkSize = GetChunkSize(chunkSize)
			--print (bit.intAsHex chunkSize)
			------ debug end ------
			chunkSize = GetChunkSize(ReadLong fstream #unsigned)
			chunkEnd = (ftell fstream) + chunkSize

			------ debug start ------
			--chunkSize = ReadLong fstream
			--chunkSize = GetChunkSize(chunkSize)
			--print (bit.intAsHex chunkSize)
			------ debug end ------

			case chunkType of
			(
				0x00000000:	--W3D_CHUNK_MESH	-- mesh definition
				( meshes[meshes.count+1] = ReadMesh fstream chunkEnd )

				0x00000100:	--W3D_CHUNK_HIERARCHY	-- hierarchy tree definition
				( hier = ReadHierarchy fstream chunkEnd )

				0x00000200:	--W3D_CHUNK_ANIMATION	-- hierarchy animation data
				( anim = ReadAnimation fstream chunkEnd )

				0x00000280:	--W3D_CHUNK_COMPRESSED_ANIMATION	// compressed hierarchy animation data
				( cmpAnim = ReadCompressedAnimation fstream chunkEnd )

				--0x000002C0:	--W3D_CHUNK_MORPH_ANIMATION	// hierarchy morphing animation data (morphs between poses, for facial animation)
				--0x00000300:	--W3D_CHUNK_HMODEL	// blueprint for a hierarchy model
				--0x00000400:	--W3D_CHUNK_LODMODEL	// blueprint for an LOD model
				--0x00000420:	--W3D_CHUNK_COLLECTION	// collection of render object names
				--0x00000440:	--W3D_CHUNK_POINTS	// array of W3dVectorStruct's.  May appear in meshes, hmodels, lodmodels, or collections.
				--0x00000460:	--W3D_CHUNK_LIGHT	// description of a light
				--0x00000500:	--W3D_CHUNK_EMITTER	// description of a particle emitter
				--0x00000600:	--W3D_CHUNK_AGGREGATE	// description of an aggregate object

				0x00000700:	--W3D_CHUNK_HLOD	// description of an HLod object (see HLodClass)
				(
					if debugOutput do format "=== HLOD chunk found ===\n"
					hlodSet = ReadHLod fstream chunkEnd
					if debugOutput do
					(
						format "  lodArrays: %  aggregates: %  proxies: %\n" \
							hlodSet.lodArrays.count \
							(if hlodSet.aggregates != undefined then hlodSet.aggregates.count else 0) \
							(if hlodSet.proxies != undefined then hlodSet.proxies.count else 0)
						for a = 1 to hlodSet.lodArrays.count do
						(
							local arr = hlodSet.lodArrays[a]
							format "  HLOD_LOD_ARRAY[%]: % sub-object(s)\n" a arr.lodObjects.count
							for o = 1 to arr.lodObjects.count do
								format "    [%] % -> pivot %\n" o arr.lodObjects[o].lodName arr.lodObjects[o].pivotIndex
						)
					)
				)

				0x00000740:	--W3D_CHUNK_BOX	// defines an collision box render object (W3dBoxStruct)
				( pickbox = ReadAABox fstream chunkEnd )

				--0x00000741:	--W3D_CHUNK_SPHERE
				--0x00000742:	--W3D_CHUNK_RING
				--0x00000750:	--W3D_CHUNK_NULL_OBJECT	// defines a NULL object (W3dNullObjectStruct)
				--0x00000800:	--W3D_CHUNK_LIGHTSCAPE	// wrapper for lights created with Lightscape.
				--0x00000900:	--W3D_CHUNK_DAZZLE	// wrapper for a glare object.  Creates halos and flare lines seen around a bright light source
				--0x00000A00:	--W3D_CHUNK_SOUNDROBJ	// description of a sound render object

				default:
				( fseek fstream chunkSize #seek_cur )
			)
			------ debug start ------
			--print (bit.intAsHex filesize)
			--print (bit.intAsHex (ftell fstream))
			------ debug end ------
		)
		)
		catch
		(
			fclose fstream
			fstream = undefined
			format "*** W3D parse failed for %; closing handle and rethrowing.\n" w3dfilename
			throw()
		)
		if fstream != undefined do fclose fstream

		-- HLOD header carries the name of the rig the meshes were authored
		-- against. We only treat it as "needs an external skeleton" when:
		--   * the HTree name differs from the HLOD's own Name (a name that
		--     matches the HLOD name means the rig lives inside this same w3d,
		--     no external file required), AND
		--   * the HTree name ends in "_SKL" (W3D convention for a standalone
		--     skeleton file -- e.g. "S_GDIINF_SKL").
		-- Anything else (e.g. terrain props pointing at themselves, or files
		-- with a non-_SKL hier reference) skips the popup.
		local hlodHTreeName = undefined
		if hlodSet != undefined and hlodSet.header != undefined do
		(
			local hn = hlodSet.header.hierarchyName
			local hlodN = hlodSet.header.hlodName
			if hn != undefined and (hn as string) != "" do
			(
				local hnStr   = hn as string
				local hlodStr = if hlodN == undefined then "" else (hlodN as string)
				local sameAsHlod = (stricmp hnStr hlodStr) == 0
				local endsWithSkl = false
				if hnStr.count >= 4 do
					endsWithSkl = (stricmp (substring hnStr (hnStr.count - 3) 4) "_SKL") == 0
				if (not sameAsHlod) and endsWithSkl do
					hlodHTreeName = hn
			)
		)

		-- In batch mode, skip files that contain neither meshes nor animation
		-- channels (probably empty / not-actually-w3d). Anim-only files
		-- legitimately have meshes.count == 0 and must still load their
		-- skeleton + keyframes, so check anim/cmpAnim too.
		if (batch and meshes.count == 0 and anim == undefined and cmpAnim == undefined) do
		( return() )

		-- Resolve the skeleton source. Three cases, in priority order:
		--   1. user-picked external skeleton (Use External Skeleton checkbox) — always wins
		--   2. main w3d already had a hierarchy chunk → keep it as-is
		--   3. neither — auto-derive from hlodSet/anim/cmpAnim header, prompt if missing
		local skelfilename = undefined
		local _skelDeclined = false   -- user explicitly chose to import without the skeleton
		if externalSkelFile != undefined then
		(
			skelfilename = externalSkelFile
			-- Force re-load even if the main w3d already had a hier so the
			-- external file's bones win.
			hier = undefined
		)
		else if hier == undefined then
		(
			if hlodSet != undefined do skelfilename = (getFilenamePath w3dfilename) + hlodSet.header.hierarchyName + ".w3d"

			if anim != undefined then
				skelfilename = (getFilenamePath w3dfilename) + anim.header.skelName + ".w3d"
			else
				if cmpAnim != undefined do skelfilename = (getFilenamePath w3dfilename) + cmpAnim.header.skelName + ".w3d"

			if (skelfilename != undefined) and (not (doesFileExist skelfilename)) then
			(
				-- Explain the dependency BEFORE any picker appears. Previously a
				-- bare file picker popped here with only its caption as a hint,
				-- and the "requires a skeleton" popup fired afterwards regardless
				-- of outcome.
				local _skelBase = getFilenameFile skelfilename
				if queryBox ("This model requires the skeleton file:  " + _skelBase + ".w3d\n\nIt was not found next to the model.\n\nLocate it now?  (No = import without bones/rigging)") title:"Skeleton required" beep:true then
					skelfilename = getOpenFileName caption:("Import Skeleton W3D: " + _skelBase) types:"Westwood 3D (*.w3d)|*.w3d|All Files (*.*)|*.*|"
				else
				(
					skelfilename = undefined
					_skelDeclined = true   -- they answered the question; don't nag again below
				)
			)
		)

		if skelfilename != undefined then
		(
			fstream = fopen skelfilename "rb"  -- binary
			if fstream == undefined then
			(
				messageBox ("Could not open skeleton W3D:\n" + skelfilename) title:"W3D import" beep:true
			)
			else
			(
			try
			(
			fseek fstream 0 #seek_end
			local filesize = ftell fstream

			fseek fstream 0 #seek_set
			while (ftell fstream < filesize) do
			(
				chunkType = ReadLong fstream #unsigned
				chunkSize = GetChunkSize(ReadLong fstream #unsigned)
				chunkEnd = (ftell fstream) + chunkSize
				case chunkType of
				(
					0x00000100:	--W3D_CHUNK_HIERARCHY	-- hierarchy tree definition
					( hier = ReadHierarchy fstream chunkEnd )
					default:
					( fseek fstream chunkSize #seek_cur )
				)
			)
			)
			catch
			(
				fclose fstream
				fstream = undefined
				format "*** Skeleton W3D parse failed for %; closing handle and rethrowing.\n" skelfilename
				throw()
			)
			if fstream != undefined do fclose fstream
			-- Remember which skeleton file backed this import; the batch tools
			-- key off this so the user doesn't get asked again.
			lastUsedSkeletonFile = skelfilename
			)
		)

		-- Skeleton outcome, surfaced sensibly. (Rework of the 1.16b-style popup
		-- that fired unconditionally AFTER resolution: it announced a skeleton
		-- was "required" even when one had already been auto-loaded, and in the
		-- missing-file case the picker appeared before any explanation.)
		--   * skeleton loaded (or embedded in the file) -> no popup; the
		--     dependency is satisfied. Debug log records what was loaded.
		--   * skeleton expected but still missing (declined / picker cancelled /
		--     picked file had no HIERARCHY chunk) -> explicit warning that the
		--     import will be unrigged, instead of silently importing boneless.
		if hier != undefined then
		(
			if debugOutput and skelfilename != undefined do
				format " skeleton loaded from: %\n" skelfilename
		)
		else if (not _skelDeclined) and ((hlodHTreeName != undefined) or (skelfilename != undefined)) then
		(
			local _expName = if hlodHTreeName != undefined then (hlodHTreeName as string) else (getFilenameFile (skelfilename as string))
			messageBox ("No skeleton was loaded for this model.\n\nSkeleton expected by model: " + _expName + "\n\nMeshes will import without bones, rigging or bone-relative placement.") title:"Importing without skeleton" beep:true
		)

		if debugOutput do
		(
			if hier == undefined then
			(
				if hlodHTreeName != undefined then
					format " expected skeleton (HTree name): %\n" hlodHTreeName
				else
					format " expected skeleton (HTree name): none found\n"
			)
		)
		------ debug start ------
		--print hier
		--print anim
		--print meshes
		--print hlodSet
		------ debug end ------

		-- create pivots(bones)
		local _rnImportBones = not (rnSelection != undefined and rnSelection.importBones == false)
		local _rnBonesOnly   = (rnSelection != undefined and rnSelection.bonesOnly == true)
		local _rnImportAnim  = not (rnSelection != undefined and rnSelection.importAnim == false)
		-- LOD filter: -1 = all (default), -2 = none, 0..N = specific LOD index in hlodSet.lodArrays
		local _rnLodMode = if rnSelection != undefined then rnSelection.lodMode else -1
		-- Animation range: -1/-1 = no clamp (import all frames in file)
		local _rnAnimFrom = if rnSelection != undefined then rnSelection.animFrom else -1
		local _rnAnimTo   = if rnSelection != undefined then rnSelection.animTo   else -1
		if debugOutput do
		(
			local _lodN = if hlodSet != undefined and hlodSet.lodArrays != undefined then hlodSet.lodArrays.count else 0
			local _lodPick = if _rnLodMode == -1 then "All" \
				else if _rnLodMode == -2 then "None" \
				else (_rnLodMode as string)
			format "=== LOD selection ===\n"
			format "  LODs in file : % (indices 0..%)\n" _lodN (if _lodN > 0 then _lodN - 1 else -1)
			format "  Chosen LOD   : %\n" _lodPick
			local _animPick = if _rnAnimFrom < 0 or _rnAnimTo < 0 then "All" else (((_rnAnimFrom as string) + ".." + (_rnAnimTo as string)))
			format "  Anim range   : %\n" _animPick
		)
		fn _rnMeshInLod meshFullName lodMode hlodSet =
		(
			if lodMode == -1 do return true
			if lodMode == -2 do return false
			if hlodSet == undefined or hlodSet.lodArrays == undefined do return true
			local idx = lodMode + 1
			if idx < 1 or idx > hlodSet.lodArrays.count do return false
			local arr = hlodSet.lodArrays[idx]
			for o = 1 to arr.lodObjects.count do
				if arr.lodObjects[o].lodName == meshFullName do return true
			false
		)

		-- "Bones in Selection's Hierarchy Only" (ckbDepBones): when the user
		-- imported a subset of meshes via "Import Selected", optionally prune
		-- the bone hierarchy to just the pivots those meshes reference (incl.
		-- their parent ancestors up to root). Build the keep-set up front so
		-- the bone-creation loop can skip everything else.
		--
		-- Walk: for each kept mesh, collect unique boneIds from vertInfs and
		-- the mesh's own boneIndex (rigid skinning), then climb parentID
		-- chains to root, marking every ancestor as kept.
		--
		-- gmPivots is built in lockstep with hier.pivots[2..N]; skipped slots
		-- get `undefined` so indices remain valid for vertInfs lookups (the
		-- existing guards already treat undefined as "not present").
		local _depBones = (rnSelection != undefined and rnSelection.depBonesOnly == true \
			and rnSelection.meshes != undefined and rnSelection.meshes.count > 0)
		local _keepBone = #{}   -- bitset of pivot IDs (0-based) to create
		if _depBones and hier != undefined do
		(
			-- Always keep root (ID 0) since it's not represented in gmPivots.
			-- Mark IDs 1..pivots.count-1; will close under parent ancestry.
			for mi = 1 to meshes.count do
			(
				local _mfn = meshes[mi].header.containerName + "." + meshes[mi].header.meshName
				if findItem rnSelection.meshes _mfn == 0 do continue
				if meshes[mi].vertInfs != undefined then
				(
					for v = 1 to meshes[mi].vertInfs.boneIds1.count do
					(
						local b = meshes[mi].vertInfs.boneIds1[v]
						if b > 0 and b < hier.pivots.count do _keepBone[b] = true
					)
					for v = 1 to meshes[mi].vertInfs.boneIds2.count do
					(
						local b = meshes[mi].vertInfs.boneIds2[v]
						if b > 0 and b < hier.pivots.count do _keepBone[b] = true
					)
				)
				-- Rigid mesh: the attach pivot comes from the HLOD sub-object's
				-- pivotIndex (W3dMeshHeader has no bone field -- the previous
				-- isProperty #boneIndex check was dead code, so DepBones pruned
				-- the very pivot a non-skinned mesh parents to and the mesh
				-- imported unplaced at the origin). Keep that pivot too.
				if hlodSet != undefined do
				(
					local _hlodObj = GetHLodObject _mfn
					if _hlodObj != undefined and _hlodObj.pivotIndex > 0 and \
						_hlodObj.pivotIndex < hier.pivots.count do
						_keepBone[_hlodObj.pivotIndex] = true
				)
			)
			-- Close under parent ancestry: a kept bone's parents must be kept
			-- too, otherwise the scene-graph parenting breaks.
			local changed = true
			while changed do
			(
				changed = false
				for b in _keepBone do
				(
					local pid = hier.pivots[b + 1].parentID
					if pid > 0 and pid < hier.pivots.count and not _keepBone[pid] do
					(
						_keepBone[pid] = true
						changed = true
					)
				)
			)
		)

		if hier != undefined and _rnImportBones then
		(
			-- Bone visuals come from the active W3DPreferences profile.
			-- Shape codes (UI label -> INI value -> scene node):
			--   1 = "Bone"          -> "box"      -> Max Bone (only choice that
			--                                          works with Auto-Bind > max skin)
			--   2 = "Geometry"      -> "sphere"   -> sphere primitive
			--   3 = "Point Helper"  -> "cylinder" -> point helper (recognised as a
			--                                          W3D bone by max2w3d.dle's
			--                                          IsW3DBoneNode via HELPER_CLASS_ID)
			-- INI vocabulary kept as box/sphere/cylinder for cross-compat with 1.16b's
			-- W3D-Importer.ini files.
			-- BoneSize: literal size; 0 = auto-fit from imported bbox.
			-- BoneColor: wirecolor.
			local _pt = W3DImporterInit.getActive "BoneShape"
			if _pt == undefined do _pt = 1
			local _bsize  = W3DImporterInit.getActive "BoneSize"
			if _bsize == undefined do _bsize = 0
			local _bcolor = W3DImporterInit.getActive "BoneColor"
			if _bcolor == undefined do _bcolor = (color 0 255 0)
			local pivotBoxColor = _bcolor

			-- Size 0 = auto-fit from imported meshes' bbox.
			-- Bones (shape 1) ignore this (Max sizes them from parent-to-child distance).
			local pivotBoxSize    = _bsize
			local pointMarkerSize = _bsize
			if _bsize == 0 then
			(
				pivotBoxSize    = 0.075   -- fallback for empty / no-vert files
				pointMarkerSize = 0.15
				if meshes.count > 0 do
				(
					local minX = 1e30; local minY = 1e30; local minZ = 1e30
					local maxX = -1e30; local maxY = -1e30; local maxZ = -1e30
					for mi = 1 to meshes.count do
					(
						if meshes[mi].verts == undefined do continue
						for v in meshes[mi].verts do
						(
							if v.x < minX do minX = v.x
							if v.y < minY do minY = v.y
							if v.z < minZ do minZ = v.z
							if v.x > maxX do maxX = v.x
							if v.y > maxY do maxY = v.y
							if v.z > maxZ do maxZ = v.z
						)
					)
					if maxX > minX do
					(
						local diag = length (Point3 (maxX - minX) (maxY - minY) (maxZ - minZ))
						pivotBoxSize    = amax #(diag * 0.02, 0.5)
						pointMarkerSize = amax #(diag * 0.04, 1.0)
					)
				)
			)

			-- Wrap the whole creation loop in `with redraw off` -- otherwise
			-- each `point ... cross:true` triggers a viewport redraw per pivot
			-- and infantry rigs (30-80 pivots) feel sluggish, especially the
			-- helper paths whose display has more elements than a Bone.
			with redraw off
			(
				--pivotName, parentID, pos, eulerAngles, rotation
				-- to skip the ROOTTRANSFORM, i starts at 2
				for i = 2 to hier.pivots.count do
				(
					curPivot = undefined
					-- DepBones gate: hier.pivots[i] has 0-based ID (i-1). If a
					-- pivot isn't in the keep-set, append undefined to gmPivots
					-- to keep indices aligned with pivot IDs and skip creation.
					if _depBones and not _keepBone[i - 1] do
					(
						append gmPivots undefined
						continue
					)
					case _pt of
					(
						2: -- Sphere (V1.16 reference look)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = sphere name:hier.pivots[i].pivotName \
									radius:pivotBoxSize segs:4 wirecolor:pivotBoxColor
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = sphere name:hier.pivots[i].pivotName \
									parent:gmPivots[hier.pivots[i].parentID] \
									radius:pivotBoxSize segs:4 wirecolor:pivotBoxColor
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
							setUserProp curPivot "bone" "yes"
						)
						3: -- Point helper (recognised as a W3D bone by max2w3d.dle)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = point name:hier.pivots[i].pivotName \
									size:pointMarkerSize cross:true box:true \
									axisTripod:false centermarker:false \
									wirecolor:pivotBoxColor
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = point name:hier.pivots[i].pivotName \
									parent:gmPivots[hier.pivots[i].parentID] \
									size:pointMarkerSize cross:true box:true \
									axisTripod:false centermarker:false \
									wirecolor:pivotBoxColor
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
						)
						default: -- 1: Max Bone (original behaviour)
						(
							if hier.pivots[i].parentID == 0 then
							(
								curPivot = bone name:hier.pivots[i].pivotName
								in coordsys world curPivot.rotation = hier.pivots[i].rotation
								in coordsys world curPivot.pos = hier.pivots[i].pos
							)
							else
							(
								curPivot = bone name:hier.pivots[i].pivotName parent:gmPivots[hier.pivots[i].parentID]
								in coordsys parent curPivot.rotation = hier.pivots[i].rotation
								in coordsys parent curPivot.pos = hier.pivots[i].pos
							)
						)
					)
					append gmPivots curPivot
				)
			)

			-- "Create Origin Bone" (ckbOriginBone): one Max Bone at world origin
			-- that becomes the parent of every existing root pivot. Useful as a
			-- single transform handle for the whole rig (move/rotate the origin
			-- to translate the model). Not added to gmPivots so vertInfs / anim
			-- channel indices stay aligned with hier.pivots.
			--
			-- Always a real Max Bone regardless of profile shape; the maxBinding
			-- second pass (line ~3478) only converts class==Bone, and the origin
			-- isn't referenced by skin weights, so this is purely a transform
			-- parent.
			--
			-- Sized from the profile's BoneSize (literal). When BoneSize is 0
			-- (auto-fit), reuse the bbox-derived pivotBoxSize. Either way, scale
			-- up by 4x: the origin is a "parent the rig" handle, so being
			-- visually distinct from child bones helps users grab it.
			if rnSelection != undefined and rnSelection.originBone == true do
			(
				-- Bone length is set by the start->end distance arg of
				-- createBone, NOT by width/height. Earlier version used
				-- [0,0,0]->[1,0,0] which baked in a 1-unit length regardless
				-- of profile size. Now: length = scaled profile size, width
				-- and height are proportional so the bone box stays tidy.
				local _osz = if _bsize > 0 then _bsize else pivotBoxSize
				_osz *= 4.0
				if _osz <= 0 do _osz = 1.0
				local _origin = boneSys.createBone [0,0,0] [_osz,0,0] [0,0,1]
				_origin.name = "Origin"
				-- BoneGeometry width/height live on the underlying object, not
				-- the node. Setting `_origin.width` directly silently no-ops
				-- (or shadows to a node-level prop that doesn't render).
				_origin.baseObject.width  = _osz * 0.25
				_origin.baseObject.height = _osz * 0.25
				_origin.wirecolor = (color 255 255 0)
				for p in gmPivots do
				(
					if p == undefined do continue
					if p.parent == undefined do p.parent = _origin
				)
			)
		)

		-- // renegade part of the code
		-- Per-import material cache, keyed by composite (vmName + texFile + blendMode).
		-- Decoupled from sceneMaterials/mat.name on purpose: mat.name stays set to vmName
		-- so re-export through max2w3d.dle preserves the original W3D vertex-material
		-- name (composite mat.names leaked into the .w3d output and broke the in-game
		-- model). findItem on a parallel-array hash works on every Max version with no
		-- dotNet dependency.
		local _matCacheKeys = #()
		local _matCacheVals = #()

		-- ESC interrupt: user can press ESC to abort the build between meshes.
		-- Partial work is kept in the scene; user can manually clean up.
		local _rnAborted = false

		-- create meshes (skipped entirely when bonesOnly is set)
		for i = 1 to meshes.count do
		(
			if keyboard.escPressed do
			(
				format "*** Import aborted by user (ESC) at mesh %/% ***\n" i meshes.count
				_rnAborted = true
				exit
			)
			if _rnBonesOnly do continue

			local _rnMeshFullName = meshes[i].header.containerName + "." + meshes[i].header.meshName

			-- renegade selection filter: skip meshes not in the selected list
			if rnSelection != undefined and rnSelection.meshes.count > 0 do
			(
				if findItem rnSelection.meshes _rnMeshFullName == 0 do continue
			)

			-- renegade LOD filter: skip meshes not in the selected LOD level
			if not (_rnMeshInLod _rnMeshFullName _rnLodMode hlodSet) do continue

			gmVerts = meshes[i].verts
			gmFaces = #()
			for f = 1 to meshes[i].faces.count do
				gmFaces[f] = meshes[i].faces[f].vertIds + 1 -- gMax array lower-limit is 1 while w3d's is 0

			-- Per-triangle W3D surface type (W3dTriStruct.Attributes) -> per-material in
			-- Max. Pick the dominant value for this mesh; every W3DMaterial built below
			-- gets it via surfaceType: (only honored on the "Use W3D Materials" path --
			-- the standardMaterial fallback has no surface-type slot). Warn under Debug
			-- Output when faces disagree, since a single material can't round-trip a mix.
			local _rnSurfType = w3dDominantSurfaceType meshes[i].faces
			if debugOutput and useW3DMatl do
			(
				local _stAllSame = true
				for f = 2 to meshes[i].faces.count while _stAllSame do
					if meshes[i].faces[f].attrs != meshes[i].faces[1].attrs do _stAllSame = false
				if not _stAllSame then
					format "  [%] mixed per-face surface types -> using dominant=% (won't fully round-trip on one material)\n" meshes[i].header.meshName _rnSurfType
				else if _rnSurfType != 0 do
					format "  [%] surface type=%\n" meshes[i].header.meshName _rnSurfType
			)

			-- create a mesh
			gmMeshes[i] = mesh name:(w3dUniqueNodeName meshes[i].header.meshName) vertices:gmVerts faces:gmFaces
			-- Set by the No Multi-Mat splitter when it replaces gmMeshes[i] with a split node;
			-- guards the post-material UV/normal loops that assume the original mesh size.
			local noMultiMatHandled = false

			-- create a new material or apply an exist one and
			if (meshes[i].vertMatls != undefined) and (meshes[i].vertMatls.count > 0) then
			(
				numTextures = 0
				if meshes[i].textures != undefined do numTextures = meshes[i].textures.count

				-- Optional .tga <-> .dds extension rewrite. Many W3D files reference TGA
				-- textures that have been re-exported as DDS later; toggling tga2dds swaps just
				-- the extension (case-insensitive, name preserved) so the bitmaptex calls
				-- and debug output below pick up the .dds versions automatically.
				-- When tga2ddsRev is also on, the rewrite goes the other direction (.dds -> .tga).
				if tga2dds and (meshes[i].textures != undefined) do
				(
					local fromExt = if tga2ddsRev then ".dds" else ".tga"
					local toExt   = if tga2ddsRev then ".tga" else ".dds"
					for t = 1 to meshes[i].textures.count do
					(
						local fn0 = meshes[i].textures[t].txFileName
						if fn0 != undefined and fn0.count >= 4 do
						(
							local ext = toLower (substring fn0 (fn0.count - 3) 4)
							if ext == fromExt do
								meshes[i].textures[t].txFileName = (substring fn0 1 (fn0.count - 4)) + toExt
						)
					)
				)

				-- W3D shader enums (from shader.h):
				--   SrcBlend: 0=ZERO, 1=ONE, 2=SRC_ALPHA, 3=ONE_MINUS_SRC_ALPHA
				--   DstBlend: 0=ZERO, 1=ONE, 2=SRC_COLOR, 3=ONE_MINUS_SRC_COLOR, 4=SRC_ALPHA, 5=ONE_MINUS_SRC_ALPHA
				-- Per-shader alpha test (mirror of ShaderClass::Uses_Alpha() in shader.h)
				fn shaderUsesAlphaW3D sh =
				(
					if sh.alphaTest != 0 do return true
					if (sh.destBlend == 4) or (sh.destBlend == 5) do return true
					if (sh.srcBlend == 2) or (sh.srcBlend == 3) do return true
					return false
				)
				-- Additive preset (SC_ADDITIVE in shader.cpp): srcBlend=ONE(1), destBlend=ONE(1)
				fn shaderIsAdditiveW3D sh =
				(
					return ((sh.srcBlend == 1) and (sh.destBlend == 1))
				)

				-- Mesh-level rollups (inline shader scans because MAXScript disallows nested fn refs)
				meshAlpha = false
				meshAlphaTest = false
				meshAdditive = false
				-- W3DMaterial blendmode enum: 0=Opaque,1=Add,2=Multiply,3=MultiplyAndAdd,4=Screen,
				--                              5=AlphaBlend,6=AlphaTest,7=AlphaTestAndBlend,8=Custom
				meshBlendMode = 0 -- defaults to Opaque if no shader signals otherwise
				if (meshes[i].shaders != undefined) and (meshes[i].shaders.count > 0) do
				(
					for s = 1 to meshes[i].shaders.count do
					(
						sh = meshes[i].shaders[s]
						if sh.alphaTest != 0 do meshAlphaTest = true
						if (sh.alphaTest != 0) or (sh.destBlend == 4) or (sh.destBlend == 5) or (sh.srcBlend == 2) or (sh.srcBlend == 3) do meshAlpha = true
						if (sh.srcBlend == 1) and (sh.destBlend == 1) do meshAdditive = true

						-- Derive the W3DMaterial blendmode from this shader.
						-- IMPORTANT: alphaTest is orthogonal to blend mode in W3D, so it must be
						-- checked BEFORE the opaque/add/etc. blend patterns. The AlphaTest preset
						-- has the same src/dst as Opaque (ONE/ZERO) and only differs by alphaTest.
						local thisBm = -1
						if (sh.srcBlend == 2) and (sh.destBlend == 5) then thisBm = (if sh.alphaTest != 0 then 7 else 5) -- AlphaTestAndBlend / AlphaBlend
						else if sh.alphaTest != 0 then thisBm = 6   -- AlphaTest (any blend, but typically ONE/ZERO)
						else if (sh.srcBlend == 1) and (sh.destBlend == 0) then thisBm = 0   -- Opaque
						else if (sh.srcBlend == 1) and (sh.destBlend == 1) then thisBm = 1   -- Add
						else if (sh.srcBlend == 0) and (sh.destBlend == 2) then thisBm = 2   -- Multiply
						else if (sh.srcBlend == 1) and (sh.destBlend == 2) then thisBm = 3   -- MultiplyAndAdd
						else if (sh.srcBlend == 1) and (sh.destBlend == 3) then thisBm = 4   -- Screen
						else thisBm = 8   -- Custom (unrecognised src/dst combo)

						-- Promote the mesh's blend mode toward the most expressive shader.
						-- Order of promotion: Opaque < Custom < AlphaTest < AlphaBlend < AlphaTestAndBlend < Screen < MultiplyAndAdd < Multiply < Add
						-- (Add wins because it's the strongest visual override; this matches the precedence used elsewhere.)
						if thisBm == 1 then meshBlendMode = 1
						else if (meshBlendMode != 1) and (thisBm == 7) then meshBlendMode = 7
						else if (meshBlendMode != 1) and (meshBlendMode != 7) and (thisBm == 5) then meshBlendMode = 5
						else if (meshBlendMode != 1) and (meshBlendMode != 7) and (meshBlendMode != 5) and (thisBm == 6) then meshBlendMode = 6
						else if (meshBlendMode == 0) and (thisBm > 0) then meshBlendMode = thisBm
					)
				)

				------ debug: material/texture diagnostics ------
				if debugOutput do
				(
					format "=== Mesh: % ===\n" meshes[i].header.meshName
					format "  vertMatls.count = %\n" meshes[i].vertMatls.count
					format "  textures.count  = %\n" numTextures
					if meshes[i].textures != undefined do
					(
						for t = 1 to meshes[i].textures.count do
						( format "    texture[%] = %\n" t meshes[i].textures[t].txFileName )
					)
					-- material info header (declared pass count from W3D_CHUNK_MATERIAL_INFO)
					if meshes[i].matlheader != undefined do
					( format "  matlheader: passCount=% vertMatlCount=% shaderCount=% textureCount=%\n" meshes[i].matlheader.passCount meshes[i].matlheader.vertMatlCount meshes[i].matlheader.shaderCount meshes[i].matlheader.textureCount )
					-- walk every MATERIAL_PASS chunk (one per render pass)
					local mPasses = meshes[i].matlPasses
					if mPasses == undefined or mPasses.count == 0 then
					(
						if meshes[i].matlPass != undefined then ( mPasses = #(meshes[i].matlPass) ) else ( mPasses = #() )
					)
					format "  matlPasses.count = %\n" mPasses.count
					for p = 1 to mPasses.count do
					(
						local mpD = mPasses[p]
						format "  -- pass[%] --\n" p
						local dStages = mpD.textureStages
						if (dStages == undefined) or (dStages.count == 0) do
						(
							if mpD.textureStage != undefined then ( dStages = #(mpD.textureStage) ) else ( dStages = #() )
						)
						format "    textureStages.count = %\n" dStages.count
						for s = 1 to dStages.count do
						(
							local dStg = dStages[s]
							if (dStg != undefined) and (dStg.txIds != undefined) then
							(
								-- collect the SET of unique txIds used in this stage so we can see whether
								-- the pass is genuinely uniform (one value) or per-face split across multiple
								-- textures. The default `format` truncates large arrays with "..." which hides
								-- the cases that determine which build path the importer should take.
								local uniqVals = #()
								for k = 1 to dStg.txIds.count do
								(
									if findItem uniqVals dStg.txIds[k] == 0 do append uniqVals dStg.txIds[k]
								)
								format "      stage[%]: txIds.count = %, unique = %, values = %\n" s dStg.txIds.count uniqVals dStg.txIds
							)
							else
								format "      stage[%]: txIds = undefined\n" s
						)
						if mpD.vmIds != undefined then
							format "    vmIds.count = %, values = %\n" mpD.vmIds.count mpD.vmIds
						else
							format "    vmIds = undefined\n"
						if mpD.shaderIds != undefined then
							format "    shaderIds.count = %, values = %\n" mpD.shaderIds.count mpD.shaderIds
						else
							format "    shaderIds = undefined\n"
					)
					-- alpha diagnostics
					format "  shaders.count = %\n" (if meshes[i].shaders != undefined then meshes[i].shaders.count else 0)
					if meshes[i].shaders != undefined do
					(
						for s = 1 to meshes[i].shaders.count do
						(
							sh = meshes[i].shaders[s]
							-- per-shader literal label inferred from src/dst blend (alphaTest checked first)
							local blendLabel = "Custom"
							if (sh.srcBlend == 2) and (sh.destBlend == 5) then blendLabel = (if sh.alphaTest != 0 then "AlphaTestAndBlend" else "AlphaBlend")
							else if sh.alphaTest != 0 then blendLabel = "AlphaTest"
							else if (sh.srcBlend == 1) and (sh.destBlend == 0) then blendLabel = "Opaque"
							else if (sh.srcBlend == 1) and (sh.destBlend == 1) then blendLabel = "Add"
							else if (sh.srcBlend == 0) and (sh.destBlend == 2) then blendLabel = "Multiply"
							else if (sh.srcBlend == 1) and (sh.destBlend == 2) then blendLabel = "MultiplyAndAdd"
							else if (sh.srcBlend == 1) and (sh.destBlend == 3) then blendLabel = "Screen"
							format "    shader[%]: srcBlend=%, destBlend=%, alphaTest=%, WriteZBuffer=%  -> alpha=%, additive=%, blendMode=%\n" s sh.srcBlend sh.destBlend sh.alphaTest sh.depthMask (shaderUsesAlphaW3D sh) (shaderIsAdditiveW3D sh) blendLabel
						)
					)
					-- per-vertex-material info (one entry per pass): colors + stage0/stage1 mapping types + mapper args.
					-- W3D vmInfo.attrs encodes mapping types: bits 16-23 = stage0Mapping, bits 8-15 = stage1Mapping.
					-- vmArgs0/vmArgs1 are the per-stage mapper args strings (match stage0mappingargs/stage1mappingargs).
					if meshes[i].vertMatls != undefined do
					(
						for v = 1 to meshes[i].vertMatls.count do
						(
							local vmEntry = meshes[i].vertMatls[v]
							format "    vertMatl[%]: name=%\n" v vmEntry.vmName
							if vmEntry.vmInfo != undefined do
							(
								format "      ambient   = %\n" vmEntry.vmInfo.ambient
								format "      diffuse   = %\n" vmEntry.vmInfo.diffuse
								format "      specular  = %\n" vmEntry.vmInfo.specular
								format "      emissive  = %\n" vmEntry.vmInfo.emissive
								format "      opacity      = %\n" vmEntry.vmInfo.opacity
								format "      translucency = %\n" vmEntry.vmInfo.translucency
								format "      shininess    = %\n" vmEntry.vmInfo.shininess
								local attrsVal = vmEntry.vmInfo.attrs
								local stage0Map = bit.and (bit.shift attrsVal -16) 0xFF
								local stage1Map = bit.and (bit.shift attrsVal -8) 0xFF
								-- W3DMaterialMappingType enum (from w3dmaterial.h)
								local mapNames = #("UV","Environment","ClassicEnvironment","Screen","LinearOffset","Silhouette","Scale","Grid","Rotate","Sine","Step","ZigZag","WSClassicEnv","WSEnvironment","GridClassicEnv","GridEnvironment","Random","Edge","BumpEnv","GridWSClassicEnv","GridWSEnv")
								local s0Label = if (stage0Map + 1) >= 1 and (stage0Map + 1) <= mapNames.count then mapNames[stage0Map + 1] else "Unknown"
								local s1Label = if (stage1Map + 1) >= 1 and (stage1Map + 1) <= mapNames.count then mapNames[stage1Map + 1] else "Unknown"
								format "      attrs=0x% stage0mapping=% (%) stage1mapping=% (%)\n" (bit.intAsHex attrsVal) stage0Map s0Label stage1Map s1Label
								-- W3D doesn't store stage0mappinguvchannel or speculartodiffuse; defaults on import.
								format "      stage0mappinguvchannel = 1 (default; W3D file has no value)\n"
								format "      stage1mappinguvchannel = 1 (default; W3D file has no value)\n"
								format "      speculartodiffuse = off (default; W3D file has no value)\n"
							)
							if vmEntry.vmArgs0 != undefined and vmEntry.vmArgs0 != "" do
								format "      stage0mappingargs = \"%\"\n" vmEntry.vmArgs0
							if vmEntry.vmArgs1 != undefined and vmEntry.vmArgs1 != "" do
								format "      stage1mappingargs = \"%\"\n" vmEntry.vmArgs1
						)
					)
					format "  meshUsesAlpha = %\n" meshAlpha
					format "  meshIsAlphaTest = %\n" meshAlphaTest
					format "  meshIsAdditive = %\n" meshAdditive
					-- final W3DMaterial blendmode that buildW3DMatl will set
					local pickedLabel = "Opaque"
					case meshBlendMode of
					(
						0: pickedLabel = "Opaque"
						1: pickedLabel = "Add"
						2: pickedLabel = "Multiply"
						3: pickedLabel = "MultiplyAndAdd"
						4: pickedLabel = "Screen"
						5: pickedLabel = "AlphaBlend"
						6: pickedLabel = "AlphaTest"
						7: pickedLabel = "AlphaTestAndBlend"
						8: pickedLabel = "Custom"
					)
					format "  W3DMaterial blendmode -> % (%)\n" meshBlendMode pickedLabel
				)
				------ end debug ------

				-- Build a W3DMaterial (from the installed W3D Tools plugin) configured from a vertex material + texture.
				-- Returns undefined if the W3DMaterial class is not available.
				-- blendMode enum: 0=Opaque, 1=Add, 2=Multiply, 3=MultiplyAndAdd, 4=Screen,
				--                 5=AlphaBlend, 6=AlphaTest, 7=AlphaTestAndBlend, 8=Custom
				-- Pick the blend mode for sub-material `subIx` (0-based texture index in W3D, 1-based here).
				-- Looks for a face whose txIds entry matches subIx-1, then reads that face's shader from shaderIds.
				-- Falls back to meshBlendMode if no per-face data is present.
				-- (shader->blendMode logic is inlined because MAXScript disallows nested fn cross-refs.)
				fn pickBlendModeForSub mesh subIx fallback =
				(
					if mesh.matlPass == undefined do return fallback
					if mesh.shaders == undefined or mesh.shaders.count == 0 do return fallback

					local txIds = undefined
					if mesh.matlPass.textureStage != undefined do txIds = mesh.matlPass.textureStage.txIds
					local shIds = mesh.matlPass.shaderIds

					if shIds == undefined or shIds.count == 0 do return fallback

					-- Short-form matlPass: shaderIds has 1 entry. If the mesh actually has multiple
					-- shaders (one per pass), map sub index -> shaders[subIx] directly; otherwise
					-- every sub uses the single referenced shader.
					if shIds.count == 1 do
					(
						local sxSel = -1
						if mesh.shaders.count > 1 and subIx >= 1 and subIx <= mesh.shaders.count then
							sxSel = subIx
						else if subIx > mesh.shaders.count then
						(
							-- unmapped sub beyond shader count (orphan texture not face-referenced).
							-- Use SAGE naming convention: textures ending in "_G" are glow/Add, else Opaque base.
							local tName = ""
							try ( tName = mesh.textures[subIx].txFileName ) catch ()
							if tName != undefined and tName != "" do
							(
								local lcName = toLower tName
								-- strip extension
								local dotIx = findString lcName "."
								local baseName = lcName
								if dotIx != undefined and dotIx > 1 do baseName = substring lcName 1 (dotIx - 1)
								if baseName.count >= 2 and (substring baseName (baseName.count - 1) 2) == "_g" do return 1
							)
							sxSel = 1  -- default to first/base shader (typically Opaque)
						)
						else
							sxSel = shIds[1] + 1
						if sxSel < 1 or sxSel > mesh.shaders.count do return fallback
						local sh = mesh.shaders[sxSel]
						-- alphaTest must be checked before opaque/add patterns (see comment in rollup).
						if (sh.srcBlend == 2) and (sh.destBlend == 5) do return (if sh.alphaTest != 0 then 7 else 5)
						if sh.alphaTest != 0 do return 6
						if (sh.srcBlend == 1) and (sh.destBlend == 0) do return 0
						if (sh.srcBlend == 1) and (sh.destBlend == 1) do return 1
						if (sh.srcBlend == 0) and (sh.destBlend == 2) do return 2
						if (sh.srcBlend == 1) and (sh.destBlend == 2) do return 3
						if (sh.srcBlend == 1) and (sh.destBlend == 3) do return 4
						return 8
					)

					-- No per-face txIds: assume sub i uses shader i (best-effort).
					if txIds == undefined or txIds.count <= 1 do
					(
						if subIx < 1 or subIx > shIds.count do return fallback
						local sx2 = shIds[subIx] + 1
						if sx2 < 1 or sx2 > mesh.shaders.count do return fallback
						local sh2 = mesh.shaders[sx2]
						if (sh2.srcBlend == 2) and (sh2.destBlend == 5) do return (if sh2.alphaTest != 0 then 7 else 5)
						if sh2.alphaTest != 0 do return 6
						if (sh2.srcBlend == 1) and (sh2.destBlend == 0) do return 0
						if (sh2.srcBlend == 1) and (sh2.destBlend == 1) do return 1
						if (sh2.srcBlend == 0) and (sh2.destBlend == 2) do return 2
						if (sh2.srcBlend == 1) and (sh2.destBlend == 2) do return 3
						if (sh2.srcBlend == 1) and (sh2.destBlend == 3) do return 4
						return 8
					)

					-- Per-face txIds + per-face shaderIds: walk faces, collect blend modes used by any face whose
					-- texture matches this sub, and promote toward the strongest expressive shader (Add wins).
					local picked = -1
					local target = subIx - 1
					local n = txIds.count
					if shIds.count < n do n = shIds.count
					for f = 1 to n do
					(
						if txIds[f] != target do continue
						local sx3 = shIds[f] + 1
						if sx3 < 1 or sx3 > mesh.shaders.count do continue
						local sh3 = mesh.shaders[sx3]
						local bm = 8
						if (sh3.srcBlend == 2) and (sh3.destBlend == 5) then bm = (if sh3.alphaTest != 0 then 7 else 5)
						else if sh3.alphaTest != 0 then bm = 6
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 0) then bm = 0
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 1) then bm = 1
						else if (sh3.srcBlend == 0) and (sh3.destBlend == 2) then bm = 2
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 2) then bm = 3
						else if (sh3.srcBlend == 1) and (sh3.destBlend == 3) then bm = 4

						if picked == -1 then picked = bm
						else if bm == 1 then picked = 1
						else if (picked != 1) and (bm == 7) then picked = 7
						else if (picked != 1) and (picked != 7) and (bm == 5) then picked = 5
						else if (picked != 1) and (picked != 7) and (picked != 5) and (bm == 6) then picked = 6
						else if (picked == 0) and (bm > 0) then picked = bm
					)
					if picked == -1 do return fallback
					return picked
				)

				-- (Material builder fns buildW3DMatl / buildMultiPassW3DMatl have been
				--  hoisted to top-level — see ~line 1482. Call sites below pass the
				--  shared ::w3dMatlAvailable flag.)

				-- Detect "single material, two texture stages" pattern:
				-- W3D encodes this as 1 vertMatl + 1 shader + 2 textures, with the vertMatl's
				-- attrs bitfield (or vmArgs1) signalling a stage-1 mapping. In that case the
				-- engine renders it as one material with stage0 = textures[1] and stage1 =
				-- textures[2] (e.g. SHIELDS: noise + gradient via LinearOffset on both stages).
				-- Without this detection the importer would split it into a multi-material,
				-- which is wrong because the engine never renders these as separate sub-materials.
				local twoStageHandled = false
				if useW3DMatl and (numTextures == 2) and (meshes[i].vertMatls.count == 1) and (meshes[i].shaders != undefined) and (meshes[i].shaders.count == 1) do
				(
					local tsVm = meshes[i].vertMatls[1]
					local tsStage1Map = 0
					if tsVm.vmInfo != undefined do
						tsStage1Map = bit.and (bit.shift tsVm.vmInfo.attrs -8) 0xFF
					local tsHasStage1Args = (tsVm.vmArgs1 != undefined) and (tsVm.vmArgs1 != "")
					if (tsStage1Map != 0) or tsHasStage1Args do
					(
						-- buildW3DMatl writes stage 0 (texture[1]) and both stages' mapping
						-- types/args from the vertex material; we just append stage 1's texture.
						local tex0 = meshes[i].textures[1].txFileName
						local tex1 = meshes[i].textures[2].txFileName
						local tsMatl = buildW3DMatl meshes[i].header.meshName tsVm tex0 meshBlendMode ::w3dMatlAvailable surfaceType:_rnSurfType
						if tsMatl != undefined do
						(
							try ( setProperty tsMatl #stage1texenabled true ) catch ()
							try ( setProperty tsMatl #stage1texturemap (bitmaptex filename:tex1) ) catch ()
							gmMeshes[i].material = tsMatl
							twoStageHandled = true
							if debugOutput do
							(
								format "  -> single W3DMaterial, two stages: stage0=% stage1=%\n" tex0 tex1
							)
						)
					)
				)

				-- Detect "single sub-material, multi-pass" pattern (e.g. base + glow) using matlPasses:
				-- W3D stores one MATERIAL_PASS chunk per render pass. When each pass has uniform
				-- single-valued vmIds/txIds/shaderIds (every face uses the same triple in that pass),
				-- the file is describing a single sub-material with N render passes -- not a multi-sub.
				-- Build an N-sub MultiMaterial (one W3DMaterial per pass) so that on re-export the W3D
				-- exporter writes all passes back out. Pass 2+ properties aren't writable on a single
				-- W3DMaterial from MAXScript, so multi-sub is the round-trip workaround.
				if (not twoStageHandled) and (meshes[i].matlPasses != undefined) and (meshes[i].matlPasses.count >= 2) and (meshes[i].shaders != undefined) and (meshes[i].vertMatls != undefined) do
				(
					local mPs = meshes[i].matlPasses
					local nPasses = mPs.count
					-- per-pass arrays of (vmIx, shIx) -- 1-based for max
					-- per-pass texture indices: passTxIxStages[p] is an array (one tx index per stage)
					local passVmIx = #()
					local passTxIxStages = #()
					local passShIx = #()
					local passUniform = true
					for p = 1 to nPasses while passUniform do
					(
						local pp = mPs[p]
						if pp == undefined do ( passUniform = false; exit )
						local vIds = pp.vmIds
						local sIds = pp.shaderIds
						-- assemble the per-pass list of texture stages (prefer multi-stage array,
						-- fall back to legacy single-stage field for older-shaped data)
						local stages = pp.textureStages
						if (stages == undefined) or (stages.count == 0) do
						(
							if pp.textureStage != undefined then ( stages = #(pp.textureStage) ) else ( stages = #() )
						)
						-- check vmIds / shaderIds uniformity (single-element short form is fine)
						if vIds != undefined and vIds.count > 1 do
						( for k = 2 to vIds.count while passUniform do ( if vIds[k] != vIds[1] do passUniform = false ) )
						if passUniform and sIds != undefined and sIds.count > 1 do
						( for k = 2 to sIds.count while passUniform do ( if sIds[k] != sIds[1] do passUniform = false ) )
						-- check per-stage txIds uniformity, collect one tx index per stage
						local stageTxList = #()
						if passUniform do
						(
							for s = 1 to stages.count while passUniform do
							(
								local stg = stages[s]
								local tIds = undefined
								if stg != undefined do tIds = stg.txIds
								if tIds != undefined and tIds.count > 1 do
								( for k = 2 to tIds.count while passUniform do ( if tIds[k] != tIds[1] do passUniform = false ) )
								if passUniform do
								(
									local txZero = if tIds != undefined and tIds.count > 0 then tIds[1] else 0
									append stageTxList (txZero + 1)
								)
							)
						)
						if passUniform do
						(
							local vmZero = if vIds != undefined and vIds.count > 0 then vIds[1] else 0
							local shZero = if sIds != undefined and sIds.count > 0 then sIds[1] else 0
							append passVmIx (vmZero + 1)
							append passShIx (shZero + 1)
							append passTxIxStages stageTxList
						)
					)
					if passUniform and passTxIxStages.count == nPasses do
					(
						-- classify shader -> blendMode
						fn _tpClassify sh =
						(
							if sh == undefined do return 0
							if (sh.srcBlend == 2) and (sh.destBlend == 5) do return (if sh.alphaTest != 0 then 7 else 5)
							if sh.alphaTest != 0 do return 6
							if (sh.srcBlend == 1) and (sh.destBlend == 0) do return 0
							if (sh.srcBlend == 1) and (sh.destBlend == 1) do return 1
							if (sh.srcBlend == 0) and (sh.destBlend == 2) do return 2
							if (sh.srcBlend == 1) and (sh.destBlend == 2) do return 3
							if (sh.srcBlend == 1) and (sh.destBlend == 3) do return 4
							return 8
						)

						-- Resolve per-pass (vm, tex0, tex1, blendMode) up-front. Used by both the
						-- single-W3DMaterial-with-N-passes path (preferred) and the legacy
						-- multi-sub fallback path.
						local mpVms = #()
						local mpTex0 = #()
						local mpTex1 = #()
						local mpBms = #()
						local mpResolved = true
						for p = 1 to nPasses while mpResolved do
						(
							local vmIx = passVmIx[p]
							local stageTxIxs = passTxIxStages[p]
							local shIx = passShIx[p]
							if vmIx < 1 or vmIx > meshes[i].vertMatls.count do ( mpResolved = false; exit )
							if shIx < 1 or shIx > meshes[i].shaders.count do ( mpResolved = false; exit )
							if (stageTxIxs == undefined) or (stageTxIxs.count == 0) do ( mpResolved = false; exit )
							local stagesOk = true
							for s = 1 to stageTxIxs.count while stagesOk do
							( if (stageTxIxs[s] < 1) or (stageTxIxs[s] > meshes[i].textures.count) do stagesOk = false )
							if not stagesOk do ( mpResolved = false; exit )
							append mpVms meshes[i].vertMatls[vmIx]
							append mpTex0 meshes[i].textures[stageTxIxs[1]].txFileName
							if stageTxIxs.count >= 2 then ( append mpTex1 meshes[i].textures[stageTxIxs[2]].txFileName ) else ( append mpTex1 "" )
							append mpBms (_tpClassify meshes[i].shaders[shIx])
						)

						-- Preferred path: build a SINGLE W3DMaterial with N native passes via the
						-- plugin's passcountblock + passone/passtwo/... param blocks. This matches
						-- how the W3D Tools plugin actually represents multi-pass materials and
						-- round-trips correctly through the W3D exporter.
						local singleMatlBuilt = false
						if useW3DMatl and mpResolved do
						(
							local mpW3D = buildMultiPassW3DMatl meshes[i].header.meshName mpVms mpTex0 mpTex1 mpBms ::w3dMatlAvailable surfaceType:_rnSurfType
							if mpW3D != undefined do
							(
								gmMeshes[i].material = mpW3D
								twoStageHandled = true
								singleMatlBuilt = true
								-- single material -> all faces use matID 1
								for f = 1 to meshes[i].faces.count do
								( setFaceMatID gmMeshes[i] f 1 )
								update gmMeshes[i]
								if debugOutput do
								(
									format "  -> single W3DMaterial with % native passes:\n" nPasses
									for p = 1 to nPasses do
									(
										if mpTex1[p] != "" then
											format "       pass[%]: stage0=% stage1=% blendmode=%\n" p mpTex0[p] mpTex1[p] mpBms[p]
										else
											format "       pass[%]: stage0=% blendmode=%\n" p mpTex0[p] mpBms[p]
									)
								)
							)
						)

						-- Fallback (legacy): build one sub-material per pass and assemble a MultiMaterial.
						-- Used when the W3DMaterial plugin doesn't expose multi-pass blocks (older builds)
						-- or when useW3DMatl is false (standardMaterial fallback path).
						local subs = #()
						local subNames = #()
						local bms = #()
						local texFiles = #()		-- stage 0 file per pass (used for diagnostics + std-mat fallback)
						local tex1Files = #()		-- stage 1 file per pass (or "" if absent)
						local allBuilt = (not singleMatlBuilt) and mpResolved
						for p = 1 to nPasses while allBuilt do
						(
							local vmIx = passVmIx[p]
							local stageTxIxs = passTxIxStages[p]
							local shIx = passShIx[p]
							local pVm = meshes[i].vertMatls[vmIx]
							local pTex = meshes[i].textures[stageTxIxs[1]].txFileName	-- stage 0
							local pTex1 = ""
							if stageTxIxs.count >= 2 do pTex1 = meshes[i].textures[stageTxIxs[2]].txFileName
							local pBm = _tpClassify meshes[i].shaders[shIx]
							local pName = pVm.vmName + "_pass" + (p as string)
							local pSub = undefined
							if useW3DMatl then
							(
								pSub = buildW3DMatl pName pVm pTex pBm ::w3dMatlAvailable surfaceType:_rnSurfType
								-- wire stage 1 texture if this pass uses two texture stages
								if (pSub != undefined) and (pTex1 != "") do
								(
									try ( setProperty pSub #stage1texenabled true ) catch ()
									try ( setProperty pSub #stage1texturemap (bitmaptex filename:pTex1) ) catch ()
								)
							)
							else
							(
								-- standard material per pass: alpha/additive wired from this pass's blendmode
								local pAlpha = (pBm == 5) or (pBm == 7)
								local pAdditive = (pBm == 1)
								pSub = standardMaterial name:pName
								pSub.ambient = pVm.vmInfo.ambient
								pSub.diffuse = pVm.vmInfo.diffuse
								pSub.specular = pVm.vmInfo.specular
								pSub.glossiness = pVm.vmInfo.shininess * 100
								pSub.opacity = pVm.vmInfo.opacity * 100
								local pDiffTex = bitmaptex filename:pTex
								try ( pDiffTex.alphaSource = 2 ) catch ()
								pSub.diffuseMap = pDiffTex
								showTextureMap pSub pSub.diffuseMap true
								if pAlpha do
								(
									local pOpTex = bitmaptex filename:pTex
									pOpTex.monoOutput = 1
									pSub.opacityMap = pOpTex
									showTextureMap pSub pSub.opacityMap true
								)
								if pAdditive do
								(
									local pAddOp = bitmaptex filename:pTex
									pSub.opacityMap = pAddOp
									showTextureMap pSub pSub.opacityMap true
									local pAddSi = bitmaptex filename:pTex
									pSub.selfIllumMap = pAddSi
									showTextureMap pSub pSub.selfIllumMap true
									try ( pSub.useSelfIllumColor = true ) catch ()
								)
							)
							if pSub == undefined do ( allBuilt = false; exit )
							append subs pSub
							append subNames pName
							append bms pBm
							append texFiles pTex
							append tex1Files pTex1
						)
						if allBuilt and subs.count == nPasses do
						(
							local mpMulti = multiMaterial numsubs:nPasses name:meshes[i].header.meshName
							for p = 1 to nPasses do
							(
								mpMulti.materialList[p] = subs[p]
								mpMulti.names[p] = subNames[p]
							)
							gmMeshes[i].material = mpMulti
							twoStageHandled = true

							-- Viewport heuristic: 3ds Max multi-sub renders only one sub per face.
							-- The W3D pass order is preserved in the material list (so re-export round-trips),
							-- but for visual fidelity we point face matIDs at the "main" pass:
							--   * If any pass is AlphaBlend (5) or AlphaTestAndBlend (7), prefer that
							--     pass -- it's typically the authored building/object texture composited
							--     onto an Opaque base/tint pass (e.g. WELL: lakedusk Opaque + cbmogwell01 AlphaBlend).
							--   * Otherwise default to sub 1 (pass 1, the base).
							local viewportSub = 1
							for p = 1 to nPasses do
							(
								if (bms[p] == 5) or (bms[p] == 7) do ( viewportSub = p; exit )
							)
							if viewportSub != 1 do
							(
								for f = 1 to meshes[i].faces.count do
								( setFaceMatID gmMeshes[i] f viewportSub )
								update gmMeshes[i]
							)

							if debugOutput do
							(
								format "  -> %-pass MultiMaterial (viewport sub=%):\n" nPasses viewportSub
								for p = 1 to nPasses do
								(
									if tex1Files[p] != "" then
										format "       sub[%]: stage0=% stage1=% blendmode=% vm=% sh=%\n" p texFiles[p] tex1Files[p] bms[p] passVmIx[p] passShIx[p]
									else
										format "       sub[%]: tex=% blendmode=% vm=% sh=%\n" p texFiles[p] bms[p] passVmIx[p] passShIx[p]
								)
							)
						)
					)
				)

				-- Detect "multi-sub × multi-pass" pattern (e.g. CHASSIS in the AVOM file):
				-- Each pass has UNIFORM vm/shader (single bucket of vertex-material + shader per pass)
				-- but PER-FACE-varying txIds. Faces split into N material buckets where each bucket
				-- uses a different texture per pass. Result: one W3DMaterial per bucket, with
				-- passcount=nPasses, pass p's stage 0 = textures[bucket.tex[p]+1].
				--
				-- W3D file shape this targets:
				--   passCount=2, vmCount=2, shCount=2, textureCount=N (N>2)
				--   pass[1].txIds = per-face values from bucket-A's pass-1 texture index, bucket-B's pass-1 idx, ...
				--   pass[2].txIds = per-face values from bucket-A's pass-2 texture index, bucket-B's pass-2 idx, ...
				if (not twoStageHandled) and useW3DMatl and (meshes[i].matlPasses != undefined) and (meshes[i].matlPasses.count >= 2) and (meshes[i].shaders != undefined) and (meshes[i].vertMatls != undefined) and (numTextures > 1) do
				(
					local mPs2 = meshes[i].matlPasses
					local nPasses2 = mPs2.count
					local nFaces2 = meshes[i].faces.count
					if debugOutput do format "  [mxBranch] entered: nPasses=% nFaces=% numTextures=% useW3DMatl=%\n" nPasses2 nFaces2 numTextures useW3DMatl
					-- collect per-pass uniform vm/shader and per-face txIds (1-based for max indexing)
					local mxVmIx = #()			-- one per pass
					local mxShIx = #()			-- one per pass
					local mxFaceTex = #()		-- mxFaceTex[p][f] = 1-based texture index for face f in pass p
					local mxOk = true
					for p = 1 to nPasses2 while mxOk do
					(
						local pp = mPs2[p]
						if pp == undefined do ( mxOk = false; exit )
						local vIds = pp.vmIds
						local sIds = pp.shaderIds
						-- vm uniformity per pass
						local vmUniform = true
						if vIds == undefined or vIds.count == 0 do ( mxOk = false; exit )
						for k = 2 to vIds.count while vmUniform do ( if vIds[k] != vIds[1] do vmUniform = false )
						if not vmUniform do ( mxOk = false; exit )
						-- shader uniformity per pass
						local shUniform = true
						if sIds == undefined or sIds.count == 0 do ( mxOk = false; exit )
						for k = 2 to sIds.count while shUniform do ( if sIds[k] != sIds[1] do shUniform = false )
						if not shUniform do ( mxOk = false; exit )
						-- need a single texture stage with a per-face txIds (or short-form uniform)
						local stages2 = pp.textureStages
						if (stages2 == undefined) or (stages2.count == 0) do
						(
							if pp.textureStage != undefined then ( stages2 = #(pp.textureStage) ) else ( stages2 = #() )
						)
						-- only handle 1 texture stage per pass in this branch (stage1 not supported here yet)
						if stages2.count != 1 do ( mxOk = false; exit )
						local stg2 = stages2[1]
						if stg2 == undefined or stg2.txIds == undefined or stg2.txIds.count == 0 do ( mxOk = false; exit )
						-- build per-face texture-index array (1-based). Short-form (count==1) means uniform.
						local faceTex = #()
						if stg2.txIds.count == 1 then
						(
							for f = 1 to nFaces2 do append faceTex (stg2.txIds[1] + 1)
						)
						else if stg2.txIds.count == nFaces2 then
						(
							for f = 1 to nFaces2 do append faceTex (stg2.txIds[f] + 1)
						)
						else
						(
							-- unexpected count; bail
							mxOk = false; exit
						)
						-- validate every per-face index is in range
						local rangeOk = true
						for f = 1 to nFaces2 while rangeOk do
						( if (faceTex[f] < 1) or (faceTex[f] > meshes[i].textures.count) do rangeOk = false )
						if not rangeOk do ( mxOk = false; exit )
						-- validate vm/shader range
						local vmIxC = vIds[1] + 1
						local shIxC = sIds[1] + 1
						if (vmIxC < 1) or (vmIxC > meshes[i].vertMatls.count) do ( mxOk = false; exit )
						if (shIxC < 1) or (shIxC > meshes[i].shaders.count) do ( mxOk = false; exit )
						append mxVmIx vmIxC
						append mxShIx shIxC
						append mxFaceTex faceTex
						if debugOutput do format "  [mxBranch] pass[%] OK: vm=% sh=% txIds.count=%\n" p vmIxC shIxC stg2.txIds.count
					)
					if debugOutput do format "  [mxBranch] mxOk=% mxFaceTex.count=%\n" mxOk mxFaceTex.count
					if mxOk do
					(
						-- group faces into buckets by their (pass1.tex, pass2.tex, ..., passN.tex) tuple.
						-- bucketKeys is parallel to bucketIxPerPass: bucketKeys[k] is the key string,
						-- bucketIxPerPass[k] is an array (one tex index per pass) for that bucket.
						local bucketKeys = #()
						local bucketIxPerPass = #()
						local faceBucketId = #()
						for f = 1 to nFaces2 do
						(
							local key = ""
							local ixs = #()
							for p = 1 to nPasses2 do
							(
								append ixs mxFaceTex[p][f]
								key = key + (mxFaceTex[p][f] as string) + ","
							)
							local b = findItem bucketKeys key
							if b == 0 then
							(
								append bucketKeys key
								append bucketIxPerPass ixs
								b = bucketKeys.count
							)
							append faceBucketId b
						)
						-- only fire this branch when there's actually >1 bucket (otherwise the uniform
						-- detector would already have caught it) and bucket count <= 4 passes' worth of
						-- usable W3DMaterial subs (no hard cap on subs themselves).
						if debugOutput do format "  [mxBranch] bucketKeys.count=%\n" bucketKeys.count
						if bucketKeys.count >= 2 do
						(
							-- shader -> blendmode classifier (inlined; MAXScript disallows local fn cross-refs)
							local mxBms = #()
							for p = 1 to nPasses2 do
							(
								local sh = meshes[i].shaders[mxShIx[p]]
								local bm = 0
								if sh == undefined then bm = 0
								else if (sh.srcBlend == 2) and (sh.destBlend == 5) then bm = (if sh.alphaTest != 0 then 7 else 5)
								else if sh.alphaTest != 0 then bm = 6
								else if (sh.srcBlend == 1) and (sh.destBlend == 0) then bm = 0
								else if (sh.srcBlend == 1) and (sh.destBlend == 1) then bm = 1
								else if (sh.srcBlend == 0) and (sh.destBlend == 2) then bm = 2
								else if (sh.srcBlend == 1) and (sh.destBlend == 2) then bm = 3
								else if (sh.srcBlend == 1) and (sh.destBlend == 3) then bm = 4
								else bm = 8
								append mxBms bm
							)
							-- build one multi-pass W3DMaterial per bucket
							local mxSubs = #()
							local mxSubsOk = true
							for b = 1 to bucketKeys.count while mxSubsOk do
							(
								local ixs = bucketIxPerPass[b]
								-- per-pass arrays for buildMultiPassW3DMatl
								local bVms = #()
								local bTex0 = #()
								local bTex1 = #()
								local bBms = #()
								for p = 1 to nPasses2 do
								(
									append bVms meshes[i].vertMatls[mxVmIx[p]]
									append bTex0 meshes[i].textures[ixs[p]].txFileName
									append bTex1 ""
									append bBms mxBms[p]
								)
								local subName = meshes[i].header.meshName + "_bucket" + (b as string)
								local sub = buildMultiPassW3DMatl subName bVms bTex0 bTex1 bBms ::w3dMatlAvailable surfaceType:_rnSurfType
								if sub == undefined do ( mxSubsOk = false; exit )
								append mxSubs sub
							)
							if debugOutput do format "  [mxBranch] subs built: mxSubsOk=% subs.count=% expected=%\n" mxSubsOk mxSubs.count bucketKeys.count
							if mxSubsOk and mxSubs.count == bucketKeys.count do
							(
								local mxMulti = multiMaterial numsubs:bucketKeys.count name:meshes[i].header.meshName
								for b = 1 to bucketKeys.count do
								(
									mxMulti.materialList[b] = mxSubs[b]
									mxMulti.names[b] = mxSubs[b].name
								)
								gmMeshes[i].material = mxMulti
								-- assign per-face matIDs to bucket index
								for f = 1 to nFaces2 do ( setFaceMatID gmMeshes[i] f faceBucketId[f] )
								update gmMeshes[i]
								twoStageHandled = true
								if debugOutput do
								(
									format "  -> multi-sub x multi-pass: % buckets, % passes each:\n" bucketKeys.count nPasses2
									for b = 1 to bucketKeys.count do
									(
										local ixs = bucketIxPerPass[b]
										format "       bucket[%]: " b
										for p = 1 to nPasses2 do
										( format "pass%-tex=% (bm=%) " p meshes[i].textures[ixs[p]].txFileName mxBms[p] )
										format "\n"
									)
								)
							)
						)
					)
				)

				if twoStageHandled then
				(
					-- already assigned a single two-stage / two-pass W3DMaterial; skip the multi-material path
				)
				else if numTextures > 1 then
				(
					-- build a MultiMaterial with one sub-material per texture
					baseVm = meshes[i].vertMatls[1]
					gmMultiMatl = multiMaterial numsubs:numTextures name:meshes[i].header.meshName
					for m = 1 to numTextures do
					(
						-- pick a vertex material if available, else reuse the first
						vmIx = m
						if vmIx > meshes[i].vertMatls.count do vmIx = 1
						curVm = meshes[i].vertMatls[vmIx]

						subName = curVm.vmName + "_" + (meshes[i].textures[m].txFileName)
						subMatl = undefined
						if useW3DMatl do
						(
							local subBlendMode = pickBlendModeForSub meshes[i] m meshBlendMode
							if debugOutput do
							(
								local subBmLabel = "Opaque"
								case subBlendMode of
								(
									0: subBmLabel = "Opaque"
									1: subBmLabel = "Add"
									2: subBmLabel = "Multiply"
									3: subBmLabel = "MultiplyAndAdd"
									4: subBmLabel = "Screen"
									5: subBmLabel = "AlphaBlend"
									6: subBmLabel = "AlphaTest"
									7: subBmLabel = "AlphaTestAndBlend"
									8: subBmLabel = "Custom"
								)
								format "  -> sub[%] tex=% picked blendmode=% (%)\n" m meshes[i].textures[m].txFileName subBlendMode subBmLabel
							)
							subMatl = buildW3DMatl subName curVm meshes[i].textures[m].txFileName subBlendMode ::w3dMatlAvailable surfaceType:_rnSurfType
						)

						if subMatl == undefined then
						(
							-- per-sub blendmode classification (same logic as W3D material path).
							-- Without this every sub inherits the mesh-wide meshAlpha/meshAdditive flag,
							-- which is wrong when a mesh has e.g. one Opaque base + one Add glow sub.
							local subBlendModeS = pickBlendModeForSub meshes[i] m 0
							local subAlpha = (subBlendModeS == 5) or (subBlendModeS == 7)
							local subAdditive = (subBlendModeS == 1)
							local subAlphaTest = (subBlendModeS == 6) or (subBlendModeS == 7)

							subMatl = standardMaterial name:subName
							subMatl.ambient = curVm.vmInfo.ambient
							subMatl.diffuse = curVm.vmInfo.diffuse
							subMatl.specular = curVm.vmInfo.specular
							subMatl.glossiness = curVm.vmInfo.shininess * 100
							subMatl.opacity = curVm.vmInfo.opacity * 100
							diffuseTex = bitmaptex filename:meshes[i].textures[m].txFileName
							-- default the diffuse bitmap to alphaSource = None so opaque meshes don't
							-- accidentally render transparent because the .dds carries an alpha channel.
							-- The alpha / additive branches below rely on this being None, so it's safe
							-- to set unconditionally here.
							try ( diffuseTex.alphaSource = 2 ) catch () -- 0=Image,1=RGB Intensity,2=None(Opaque)
							subMatl.diffuseMap = diffuseTex
							showTextureMap subMatl subMatl.diffuseMap true

							-- if this sub uses alpha, wire opacity to the same bitmap with mono output = Alpha
							if subAlpha do
							(
								opTex = bitmaptex filename:meshes[i].textures[m].txFileName
								opTex.monoOutput = 1 -- 0=RGB Intensity, 1=Alpha
								subMatl.opacityMap = opTex
								showTextureMap subMatl subMatl.opacityMap true
							)
							-- additive blending: assign texture to opacity and self-illumination, with selfIllumColor on
							if subAdditive do
							(
								addOpTex = bitmaptex filename:meshes[i].textures[m].txFileName
								subMatl.opacityMap = addOpTex
								showTextureMap subMatl subMatl.opacityMap true

								addSiTex = bitmaptex filename:meshes[i].textures[m].txFileName
								subMatl.selfIllumMap = addSiTex
								showTextureMap subMatl subMatl.selfIllumMap true

								try ( subMatl.useSelfIllumColor = true ) catch ()

								if debugOutput do
								( format "  -> sub[%] additive: opacity+selfIllum maps wired\n" m )
							)
							if debugOutput do
							(
								local sbLabel = "Opaque"
								case subBlendModeS of
								(
									1: sbLabel = "Add"
									2: sbLabel = "Multiply"
									3: sbLabel = "MultiplyAndAdd"
									4: sbLabel = "Screen"
									5: sbLabel = "AlphaBlend"
									6: sbLabel = "AlphaTest"
									7: sbLabel = "AlphaTestAndBlend"
									8: sbLabel = "Custom"
								)
								format "  -> std sub[%] tex=% blendmode=% (%) alpha=% additive=%\n" m meshes[i].textures[m].txFileName subBlendModeS sbLabel subAlpha subAdditive
							)
						)

						gmMultiMatl.materialList[m] = subMatl
						gmMultiMatl.materialIDList[m] = m
						gmMultiMatl.names[m] = subName
					)
					gmMeshes[i].material = gmMultiMatl

					-- assign per-face material IDs from txIds (0-based in w3d, 1-based in max)
					txIdList = undefined
					if (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) do
					( txIdList = meshes[i].matlPass.textureStage.txIds )

					if txIdList != undefined then
					(
						if txIdList.count == 1 then
						(
							for f = 1 to meshes[i].faces.count do
							( setFaceMatID gmMeshes[i] f (txIdList[1] + 1) )
						)
						else
						(
							for f = 1 to meshes[i].faces.count do
							(
								if f <= txIdList.count do
								( setFaceMatID gmMeshes[i] f (txIdList[f] + 1) )
							)
						)
						update gmMeshes[i]
					)

					-- "No Multi-Mat" splitter: instead of leaving the mesh with a multi-material,
					-- split it into separate mesh objects (one per matID actually used), each
					-- with a single material assigned. Builds every bucket as a new mesh from
					-- the W3D source data (verts, faces, normals, txCoords) and then deletes
					-- the original node entirely. This is more reliable than mutating the
					-- original via meshOp.deleteFaces, which corrupts the TVFace/normal arrays
					-- and triggers "TVFace index out of range" errors downstream.
					-- Skip skinned meshes: the split rebuilds geometry with new vertex
					-- numbering, but vertInfs (the influenced-verts fix-up below and the
					-- skin-binding passes after the loop) address the ORIGINAL vertex
					-- indices -- setVert would run past the split node's vert count and
					-- weights would land on the wrong verts. Skinning is the
					-- higher-priority feature, same call as Fix Vertices makes.
					if noMultiMat and meshes[i].vertInfs != undefined do
					(
						if debugOutput do
							format "  -> No Multi-Mat: [%] is skinned; split skipped (weights address original verts)\n" gmMeshes[i].name
					)
					if noMultiMat and meshes[i].vertInfs == undefined do
					(
						try
						(
							-- Snapshot the W3D source data for this mesh.
							local srcVertsW = meshes[i].verts
							local srcNormalsW = meshes[i].normals
							local srcFacesW = meshes[i].faces -- array of W3dMeshFace (vertIds is 0-based)
							local srcTxCoordsW = undefined
							if (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) and (meshes[i].matlPass.textureStage.txCoords != undefined) do
								srcTxCoordsW = meshes[i].matlPass.textureStage.txCoords

							-- bucket faces by matID using the live mesh's per-face IDs (these were
							-- assigned just above from txIdList).
							local matIdBuckets = #()
							local matIdList2 = #()
							for f = 1 to gmMeshes[i].numFaces do
							(
								local mid = getFaceMatID gmMeshes[i] f
								local idx = findItem matIdList2 mid
								if idx == 0 then
								(
									append matIdList2 mid
									append matIdBuckets #{f}
								)
								else
								(
									matIdBuckets[idx][f] = true
								)
							)

							if matIdList2.count > 1 then
							(
								local origName = gmMeshes[i].name
								local origParent = gmMeshes[i].parent
								local origTransform = gmMeshes[i].transform
								local createdNames = #()
								local createdNodes = #()

								for k = 1 to matIdList2.count do
								(
									local mid = matIdList2[k]
									local newName = origName + " [matID " + (mid as string) + "]"
									local bucketFaces = matIdBuckets[k]

									-- Collect this bucket's face vertex-index triples (1-based) and
									-- the unique source vert IDs they use.
									local usedVerts = #{}
									local faceTris = #()
									for f in bucketFaces do
									(
										-- W3D vertIds are 0-based; +1 to match MAXScript indexing.
										local v0 = (srcFacesW[f].vertIds.x as integer) + 1
										local v1 = (srcFacesW[f].vertIds.y as integer) + 1
										local v2 = (srcFacesW[f].vertIds.z as integer) + 1
										append faceTris #(f, v0, v1, v2)
										usedVerts[v0] = true
										usedVerts[v1] = true
										usedVerts[v2] = true
									)

									-- Compact: only carry the verts this bucket actually uses.
									local oldToNew = #()
									local newVerts = #()
									local newNormals = #()
									for v in usedVerts do
									(
										append newVerts srcVertsW[v]
										if srcNormalsW != undefined and v <= srcNormalsW.count do
											append newNormals srcNormalsW[v]
										oldToNew[v] = newVerts.count
									)

									local newFaces = #()
									for tri in faceTris do
										append newFaces [oldToNew[tri[2]], oldToNew[tri[3]], oldToNew[tri[4]]]

									local newNode = undefined
									try ( newNode = mesh name:newName vertices:newVerts faces:newFaces ) catch ()

									if newNode != undefined then
									(
										-- per-vert normals
										for v = 1 to newNormals.count do
										( try ( setNormal newNode v newNormals[v] ) catch () )

										-- texture vertices (UVs) — copy txCoords for the used verts.
										if srcTxCoordsW != undefined do
										(
											try
											(
												setNumTVerts newNode newVerts.count
												buildTVFaces newNode
												local idxList = #()
												for v in usedVerts do append idxList v
												for j = 1 to idxList.count do
												(
													local sv = idxList[j]
													if sv <= srcTxCoordsW.count do
													(
														local uv = srcTxCoordsW[sv]
														setTVert newNode j (Point3 uv.x uv.y 0)
													)
												)
												-- setTVFace expects three integer args, not a Point3.
												for fIx = 1 to newFaces.count do
												(
													local nf = newFaces[fIx]
													setTVFace newNode fIx (nf.x as integer) (nf.y as integer) (nf.z as integer)
												)
											) catch ()
										)

										try ( newNode.material = gmMultiMatl.materialList[mid] ) catch ()
										try ( newNode.transform = origTransform ) catch ()
										try ( newNode.parent = origParent ) catch ()
										update newNode
										append createdNames newName
										append createdNodes newNode
										if debugOutput do
											format "    -> created matID % node=% (verts=% faces=%) at pos=%\n" mid newNode.name newVerts.count newFaces.count newNode.pos
									)
									else
									(
										if debugOutput do
											format "    -> matID % FAILED to create new mesh node\n" mid
									)
								)

								-- Replace the original in gmMeshes so downstream post-processing
								-- (normals reset, fix vertices, HLOD reparent) operates on a real
								-- node instead of the soon-to-be-deleted original. Pick the first
								-- created node as the representative.
								if createdNodes.count > 0 then
								(
									try ( delete gmMeshes[i] ) catch ()
									gmMeshes[i] = createdNodes[1]
									noMultiMatHandled = true
								)

								if debugOutput do
									format "  -> No Multi-Mat: split [%] into % mesh(es): %\n" origName createdNames.count createdNames
							)
							else
							(
								if debugOutput do
									format "  -> No Multi-Mat: [%] only uses 1 matID, no split needed\n" gmMeshes[i].name
							)
						)
						catch
						(
							if debugOutput do
								format "  -> No Multi-Mat [%]: FAILED with error: %\n" meshes[i].header.meshName (getCurrentException())
						)
					)
				)
				else
				(
					gmMatl = undefined
					matlName = meshes[i].vertMatls[1].vmName

					-- // renegade part of the code
					-- Decouple cache key from display name. mat.name stays = vmName so
					-- re-export preserves the original W3D vertex-material label
					-- (max2w3d.dle writes mat.name straight into the output .w3d).
					-- Lookup key composes vmName + stage-0 texFile + blendMode so
					-- distinct (texture, blend) tuples that share a vmName don't collide
					-- in the cache. Renegade assets reuse vmNames like "silo_top",
					-- "Material #28" across meshes pointing at different textures.
					local _matCacheTex = ""
					if (meshes[i].textures != undefined) and (meshes[i].textures.count > 0) and (meshes[i].textures[1] != undefined) and (meshes[i].textures[1].txFileName != undefined) do
						_matCacheTex = meshes[i].textures[1].txFileName
					local _matCacheKey = matlName + "|" + _matCacheTex + "|bm" + (meshBlendMode as string)
					local _matCacheHit = findItem _matCacheKeys _matCacheKey

					if userSeparateMaterial or (_matCacheHit == 0) then
					(
						-- Try W3D Tools material first when requested
						if useW3DMatl do
						(
							local texFile = ""
							if (meshes[i].textures != undefined) and (meshes[i].textures.count > 0) do
							( texFile = meshes[i].textures[1].txFileName )
							gmMatl = buildW3DMatl matlName meshes[i].vertMatls[1] texFile meshBlendMode ::w3dMatlAvailable surfaceType:_rnSurfType
						)

						if gmMatl != undefined then
						(
							append sceneMaterials gmMatl
							-- // renegade part of the code
							append _matCacheKeys _matCacheKey
							append _matCacheVals gmMatl
						)
						else
						(
						gmMatl = standardMaterial name:matlName
						gmMatl.ambient = meshes[i].vertMatls[1].vmInfo.ambient
						gmMatl.diffuse = meshes[i].vertMatls[1].vmInfo.diffuse
						gmMatl.specular = meshes[i].vertMatls[1].vmInfo.specular
						--gmMatl.emissive = meshes[i].vertMatls[1].vmInfo.emissive
						gmMatl.glossiness = meshes[i].vertMatls[1].vmInfo.shininess * 100
						gmMatl.opacity = meshes[i].vertMatls[1].vmInfo.opacity * 100
						--gmMatl.translucency = meshes[i].vertMatls[1].vmInfo.translucency
						if (meshes[i].textures != undefined) and (meshes[i].textures.count > 0) then
						(
							diffuseTex = bitmaptex filename:meshes[i].textures[1].txFileName
							-- default alphaSource = None so opaque meshes don't render transparent
							-- when the bitmap carries an alpha channel (alpha/additive branches below
							-- expect this to be None as well, so it's safe to set unconditionally).
							try ( diffuseTex.alphaSource = 2 ) catch () -- 0=Image,1=RGB Intensity,2=None(Opaque)
							gmMatl.diffuseMap = diffuseTex
							showTextureMap gmMatl gmMatl.diffuseMap true

							if meshAlpha do
							(
								opTex = bitmaptex filename:meshes[i].textures[1].txFileName
								opTex.monoOutput = 1 -- Alpha
								gmMatl.opacityMap = opTex
								showTextureMap gmMatl gmMatl.opacityMap true
							)
							if meshAdditive do
							(
								addOpTex = bitmaptex filename:meshes[i].textures[1].txFileName
								gmMatl.opacityMap = addOpTex
								showTextureMap gmMatl gmMatl.opacityMap true

								addSiTex = bitmaptex filename:meshes[i].textures[1].txFileName
								gmMatl.selfIllumMap = addSiTex
								showTextureMap gmMatl gmMatl.selfIllumMap true

								try ( gmMatl.useSelfIllumColor = true ) catch ()

								if debugOutput do
								( format "  -> additive: opacity+selfIllum maps wired\n" )
							)
						)
						append sceneMaterials gmMatl
						-- // renegade part of the code
						append _matCacheKeys _matCacheKey
						append _matCacheVals gmMatl
						)  -- end inner else (standardMaterial fallback)
					)
					else
					(
						-- // renegade part of the code: cache hit by composite key
						gmMatl = _matCacheVals[_matCacheHit]
					)
					gmMeshes[i].material = gmMatl
				)
			)

			-- map a texture at v1.02
			-- Skip when No Multi-Mat already replaced gmMeshes[i] with a split node:
			-- the split path already set up its own per-bucket UVs/normals, and the
			-- original-sized arrays here would index out of range on the smaller node.
			if not noMultiMatHandled and (meshes[i].matlPass != undefined) and (meshes[i].matlPass.textureStage != undefined) and (meshes[i].matlPass.textureStage.txCoords != undefined) then
			(
				numTVerts = meshes[i].matlPass.textureStage.txCoords.count
				setNumTVerts gmMeshes[i] numTVerts
				for v = 1 to numTVerts do
				(
					txCoord = meshes[i].matlPass.textureStage.txCoords[v]
					setTVert gmMeshes[i] v (Point3 txCoord.x txCoord.y 0)
				)
				numTFaces = meshes[i].faces.count
				buildTVFaces gmMeshes[i]

				for f = 1 to numTFaces do
				( setTVFace gmMeshes[i] f gmFaces[f] )
			)

			-- set vert normals at v1.03
			if not noMultiMatHandled do
			(
				for v = 1 to meshes[i].normals.count do
				( setNormal gmMeshes[i] v meshes[i].normals[v] )
			)

			-- per-vertex diffuse color / alpha (W3D_CHUNK_DCG) -- v21.6
			-- max2w3d writes DCG two ways (w3dexport.cpp ~7826; vertex defaults
			-- DiffuseColor=(1,1,1) / Alpha=1 at ~4772):
			--   VAlpha OFF -> DCG = (vertColor.rgb, 255)              per-vertex colour
			--   VAlpha ON  -> DCG = (255,255,255, avg(vertColor.rgb)) per-vertex alpha
			-- C&C meshes use the first form; Renegade level meshes use the second
			-- (white RGB, painted alpha) -- which is why an rgb-only apply silently
			-- lost it. Invert the exporter: if every alpha is 255 treat DCG as colour
			-- and store rgb; if any alpha < 255 the meaningful channel is alpha, so
			-- store it as a grayscale colour and flag the node VAlpha (wwSetVAlpha,
			-- maxscript.cpp:432) so re-export regenerates the identical DCG. Skipped on
			-- the No-Multi-Mat split path, like the normals/UV blocks above.
			-- DCG can sit in ANY material pass: multi-pass Renegade meshes (e.g.
			-- MGREF^2PASS) store the coloured data as pass 1 while the legacy
			-- meshes[i].matlPass points at pass 2, so scan every pass for the one
			-- carrying per-vertex data. Max has a single vertex-colour channel and the
			-- exporter regenerates every pass's DCG from it, so one source pass suffices.
			local dcgCols = undefined
			local dcgPasses = meshes[i].matlPasses
			if dcgPasses == undefined and meshes[i].matlPass != undefined do dcgPasses = #(meshes[i].matlPass)
			if dcgPasses != undefined do
			for pi = 1 to dcgPasses.count while dcgCols == undefined do
			(
				local pp = dcgPasses[pi]
				if pp != undefined and pp.dcg != undefined and pp.dcg.count == gmMeshes[i].numverts do
				(
					-- ignore a degenerate all-(255,255,255,255) pass: it holds no
					-- information and the exporter would drop it again anyway.
					local varies = false
					for c in pp.dcg while not varies do
					( if (c.a != 255 or c.r != 255 or c.g != 255 or c.b != 255) do varies = true )
					if varies do dcgCols = pp.dcg
				)
			)
			if not noMultiMatHandled and dcgCols != undefined do
			(
				local dcgIsAlpha = false
				for v = 1 to dcgCols.count while not dcgIsAlpha do
				( if dcgCols[v].a != 255 do dcgIsAlpha = true )

				setNumCPVVerts gmMeshes[i] dcgCols.count
				for v = 1 to dcgCols.count do
				(
					local c = dcgCols[v]
					if dcgIsAlpha then ( setVertColor gmMeshes[i] v (color c.a c.a c.a) )
					else ( setVertColor gmMeshes[i] v (color c.r c.g c.b) )
				)
				buildVCFaces gmMeshes[i]
				for f = 1 to gmFaces.count do
				( setVCFace gmMeshes[i] f gmFaces[f] )
				update gmMeshes[i]

				if dcgIsAlpha do
				(
					try ( wwSetVAlpha gmMeshes[i] true )
					catch ( format "*** wwSetVAlpha failed on %\n" gmMeshes[i].name )
					-- Alpha-mode DCG only survives re-export through a 2-pass W3DMaterial whose
					-- second pass is alpha-blended (the exporter's IsAlpha gate). That pass is only
					-- authored on the "Use W3D Materials" path; with it OFF the mesh gets a single
					-- Standard-material pass and the alpha is silently dropped on export. Note that
					-- as a debug diagnostic (cf. the v21.6 DCG finding) -- gated by Debug Output like
					-- the sibling DCG line below, so a normal import isn't spammed with it.
					if debugOutput and not useW3DMatl do
						format "*** DCG: % has per-vertex ALPHA but 'Use W3D Materials' is OFF -- the alpha-blend pass won't be authored, so this alpha will be LOST on re-export. Re-import with 'Use W3D Materials' ON to round-trip it.\n" gmMeshes[i].name
				)
				if debugOutput do
				( format "  DCG -> % (% verts, mode=%)\n" gmMeshes[i].name dcgCols.count (if dcgIsAlpha then "alpha" else "color") )
			)

			-- W3D_CHUNK_MESH_USER_TEXT: restore the level author's per-mesh "User Defined
			-- Properties" note (e.g. "LVSMaterial8 = shine metal"). The exporter re-emits it
			-- verbatim from that buffer (meshsave.cpp GetUserPropBuffer), so this round-trips
			-- with no DLL change. Node-level metadata with no vertex dependency, so -- unlike
			-- DCG -- it also applies on the No-Multi-Mat split path (gmMeshes[i] = representative).
			if meshes[i].userText != undefined and meshes[i].userText != "" do
			(
				try ( setUserPropBuffer gmMeshes[i] meshes[i].userText )
				catch ( format "*** setUserPropBuffer failed on %\n" gmMeshes[i].name )
				if debugOutput do
				( format "  UserText -> % (% chars)\n" gmMeshes[i].name meshes[i].userText.count )
			)

			-- Fix Vertices and Fix Normals were originally applied here, but they interfere
			-- with the skin-binding pass that runs after this loop:
			--   - Fix Vertices welds verts (changes vertex count) -> Skin's per-vertex
			--     weights would address the wrong verts.
			--   - Fix Normals adds an Edit Normals modifier, then Skin gets stacked on top
			--     of it -> Skin sees the post-Edit-Normals topology and the weights bind
			--     to the wrong points.
			-- Both passes are deferred to after the skin binding loop (search for the
			-- "deferred Fix Vertices / Fix Normals" block below).

			--find the exist pivot of the mesh and replace it.
			if (hlodSet != undefined) and (hier != undefined) then
			(
				meshLod = GetHLodObject (meshes[i].header.containerName + "." + meshes[i].header.meshName)
				if meshLod != undefined then
				(
					p = meshLod.pivotIndex
					if p > 0 then  -- the mesh is in ROOTTRANSFORM when p == 0
					(
						if gmPivots[p] != undefined then
						(
							-- Same-name rigid mesh: W3D mesh and its target bone share a name
								-- (Renegade vehicle/building parts, and the camera-aligned sprites in
								-- files like o_em_cross). The mesh must OCCUPY the pivot -- inherit its
								-- transform/parent/children, delete the redundant bone -- matching how
								-- max2w3d re-exports it. Compare the ORIGINAL W3D mesh name, not
								-- gmMeshes[i].name: the bone is created first, so w3dUniqueNodeName
								-- already suffixed the mesh node to "<name>~01"; comparing the Max node
								-- name never matched, leaving the mesh a stray "~01" child that on
								-- re-export the '~' disqualified from normal mesh export (it returned an
								-- empty proxy, geometry lost). Match on the W3D name; rename node clean.
								if (stricmp meshes[i].header.meshName gmPivots[p].name == 0) then
							(
								gmMeshes[i].parent = gmPivots[p].parent
								gmMeshes[i].rotation = gmPivots[p].rotation  --have not to swap the line of rotation and pos, why?
								gmMeshes[i].pos = gmPivots[p].pos
								for c = gmPivots[p].children.count to 1 by -1 do
								(													   --only want to rearrange the hierarchy
									if(gmPivots[p].children[c] != undefined) then
									( gmPivots[p].children[c].parent = gmMeshes[i] )   --not the pivot positions of the children
								)
								disusedPivot = gmPivots[p]
								gmPivots[p] = gmMeshes[i]
								-- Delete the redundant bone FIRST to free its name, then rename
								-- the mesh to the clean W3D name. Without freeing it first, setName
								-- would re-suffix to "~01" and the round-trip bug would persist.
								local _cleanNodeName = meshes[i].header.meshName
								delete disusedPivot
								gmMeshes[i].name = _cleanNodeName
							)
							else
							(
								gmMeshes[i].parent = gmPivots[p]
								gmMeshes[i].rotation = gmPivots[p].rotation  --have not to swap the line of rotation and pos, why?
								gmMeshes[i].pos = gmPivots[p].pos
							)
						)
					)
				)
			)

			-- fix the influenced verts in infantry skin at v1.03
			if (meshes[i].vertInfs != undefined) and (hier != undefined) then
			(
				for v = 1 to meshes[i].vertInfs.boneIds1.count do
				(
					p = meshes[i].vertInfs.boneIds1[v]
					-- please enable these 2 lines when unexpected error happen here
					if p <= 0 do continue
					if gmPivots[p] == undefined do continue
					in coordsys gmPivots[p] setVert gmMeshes[i] v meshes[i].verts[v]
				)

				--to show influenced info at v1.08
				--format "%: \n" meshes[i].header.meshName - obsolete, replaced with the 'Auto-Bind' option

				if (autoBindType > 0) do
				( currDeps = #() )

				for p = 1 to hier.pivots.count do
				(
					ivs = #()
					-- was `count - 1`: an off-by-one that silently dropped the last
					-- vertex from every bone's dependency set (and from the
					-- Split-by-dependencies detach below)
					for v = 1 to meshes[i].vertInfs.boneIds1.count do
					( if meshes[i].vertInfs.boneIds1[v] == (p - 1) do (append ivs v) )

					if splitMeshes do
					(
						if (ivs.count > 1) do
						(
							hide gmMeshes[i]
							tmpChunk = meshop.detachVerts gmMeshes[i] ivs delete:false asMesh:true

							newChunk = Editable_Mesh()
							newChunk.mesh = tmpChunk
							newChunk.name = hier.pivots[p].pivotName
							newChunk.parent = gmPivots[p-1]
							update newChunk
						)
						update
					)

					if (autoBindType > 0) do
					(
						if (ivs.count > 1) do
						(
							try
							(
								currDep = Dependency gmPivots[p-1] ivs
								append currDeps currDep
							)
							catch
							( continue )
						)
					)
					--(format "% %: %\n" p hier.pivots[p].pivotName ivs)
				)

				if (autoBindType > 0) do
				(
					currDepStack = DependencyStack gmMeshes[i] currDeps
					append depStacks currDepStack
				)
			)
		)

		--somehow when inserting max bones directly to the code generating gmPivots some parts of meshes start flipping around.
		--can't be bothered to look for the reason why, so helper bones are replaced with max ones here.

		-- Bone-fins display toggle (v19): read once from the rollout if present.
		-- Defaults to true so behaviour matches v18 when the checkbox is absent
		-- (rollout bypassed for batch/programmatic calls).
		local showBoneFins = true
		try
		(
			if isProperty rltMain #ckbShowBoneFins do showBoneFins = rltMain.ckbShowBoneFins.checked
		)
		catch()

		if maxBinding do
		(
			for i=1 to gmPivots.count do
			(
				if (classOf gmPivots[i] != Bone) do continue
				maxPivot = boneSys.createBone [0,0,0] [0,0,0] [0,0,1]
				maxPivot.width = 0.5
				maxPivot.height = 0.5

				maxPivot.name = gmPivots[i].name
				maxPivot.transform = gmPivots[i].transform
				if isProperty maxPivot #showLinks do maxPivot.showLinks = showBoneFins
				if isProperty maxPivot #showFins  do maxPivot.showFins  = showBoneFins
				if (not showBoneFins) do
				(
					if isProperty maxPivot #frontFinSize do maxPivot.frontFinSize = 0
					if isProperty maxPivot #backFinSize  do maxPivot.backFinSize  = 0
					if isProperty maxPivot #sideFinSize  do maxPivot.sideFinSize  = 0
				)

				if (hier.pivots[i+1].parentID != 0) then
				( maxPivot.parent = gmPivots[hier.pivots[i+1].parentID] )
				else
				(
					-- Root pivot: inherit whatever parent the old bone had -- the
					-- "Create Origin Bone" handle, or nothing. Without this the
					-- replacement silently detached root bones from the Origin.
					maxPivot.parent = gmPivots[i].parent
				)

				obsltPivot = gmPivots[i]
				gmPivots[i] = maxPivot
				-- `delete` unlinks the old bone's children to the world. Child
				-- BONES recover (each is re-parented via the hier table when its
				-- own replacement runs), but meshes parented by the HLOD pass --
				-- and any other non-bone children -- stayed orphaned, so bone
				-- animation stopped moving rigid meshes (vehicle turrets/wheels).
				-- Hand all children over to the replacement bone first; same
				-- backwards loop the HLOD mesh-swap branch uses.
				for c = obsltPivot.children.count to 1 by -1 do
				( obsltPivot.children[c].parent = maxPivot )
				delete obsltPivot
			)
		)

		if (anim != undefined) and (hier != undefined) and _rnImportAnim then
		(
			-- Honor user-chosen animation range (from Renegade dialog spinners).
			-- Frame indices in W3D are 0-based; Max's animationRange is 1-based,
			-- so we add 1. -1 means "no clamp".
			local _rangeStart = if _rnAnimFrom >= 0 then (_rnAnimFrom + 1) else 1
			local _rangeEnd   = if _rnAnimTo   >= 0 then (_rnAnimTo   + 1) else anim.header.frameCount
			if _rangeEnd <= _rangeStart do _rangeEnd = _rangeStart + 1
			if anim.header.frameCount > 1 then
				animationRange = interval _rangeStart _rangeEnd
			else
				animationRange = interval 0 1
			frameRate = anim.header.frameRate

			for i = 1 to anim.channels.count do
			(
				if keyboard.escPressed do
				(
					format "*** Import aborted by user (ESC) at anim channel %/% ***\n" i anim.channels.count
					_rnAborted = true
					exit
				)
				curChn = anim.channels[i]
				--curObj = execute ("$'" + hier.pivots[curChn.pivotID + 1].pivotName + "'") -- at v1.02. it should be curChn.pivotID + 1 at v1.04

				try
				( curObj = gmPivots[curChn.pivotID] ) -- test at v1.04
				catch
				( continue )
				--print curObj
				--print curChn
				if curObj != undefined then
				(
					datumPos = hier.pivots[curChn.pivotID + 1].pos
					datumRot = hier.pivots[curChn.pivotID + 1].rotation
					case curChn.flags of
					(
						0x0000: --ANIM_CHANNEL_X = 0
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								( curKey = curObj.pos.controller.keys[k] )
								curKey.value += [curChn.values[(f - curChn.firstFrame + 1)], 0, 0] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 2)
							--)
							--else
							--(
							--	curKey = addNewKey curObj.pos.controller (curChn.firstFrame)
							--)
							--curKey.value = datumPos
						)
						0x0001: --ANIM_CHANNEL_Y = 1
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								(
									curKey = curObj.pos.controller.keys[k]
								)
								curKey.value += [0, curChn.values[(f - curChn.firstFrame + 1)], 0] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 1)
							--		curKey.value = datumPos
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.firstFrame - 1)
							--		curKey.value = datumPos
							--	)
							--)
						)
						0x0002: --ANIM_CHANNEL_Z = 2
						(
							curObj.pos.controller = linear_position()
							curKey = addNewKey curObj.pos.controller 0
							curKey.value = datumPos
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								k = getKeyIndex curObj.pos.controller (f + 1)
								if k == 0 then
								(
									curKey = addNewKey curObj.pos.controller (f + 1)
									curKey.value = datumPos
								)
								else
								(
									curKey = curObj.pos.controller.keys[k]
								)
								curKey.value += [0, 0, curChn.values[(f - curChn.firstFrame + 1)]] * (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.lastFrame + 1)
							--		curKey.value = datumPos
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.pos.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.pos.controller (curChn.firstFrame - 1)
							--		curKey.value = datumPos
							--	)
							--)
						)
					--	--0x0003: --ANIM_CHANNEL_XR = 3
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.x = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
					--	--0x0004: --ANIM_CHANNEL_YR = 4
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.y = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
					--	--0x0005: --ANIM_CHANNEL_ZR = 5
					--	--(
					--	--	curKey = addNewKey curObj.pos.controller f
					--	--	curKey.value.z = curChn.values[(f - curChn.firstFrame + 1)]
					--	--)
						0x0006: --ANIM_CHANNEL_Q = 6
						(
							curObj.rotation.controller = linear_rotation()
							curKey = addNewKey curObj.rotation.controller 0
							curKey.value = datumRot
							for f = curChn.firstFrame to curChn.lastFrame do
							(
								curKey = addNewKey curObj.rotation.controller (f + 1)
								curKey.value = curChn.values[(f - curChn.firstFrame + 1)] - (inverse datumRot)
							)
							--if curChn.firstFrame == 0 then
							--(
							--	k = getKeyIndex curObj.rotation.controller (curChn.lastFrame + 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.rotation.controller (curChn.lastFrame + 1)
							--		curKey.value = datumRot
							--	)
							--)
							--else
							--(
							--	k = getKeyIndex curObj.rotation.controller (curChn.firstFrame - 1)
							--	if k == 0 then
							--	(
							--		curKey = addNewKey curObj.rotation.controller (curChn.firstFrame - 1)
							--		curKey.value = datumRot
							--	)
							--)
						)
					)
				)
			)

			for i = 1 to anim.bitchannels.count do
			(
				curChn = anim.bitchannels[i]
				-- curObj = execute ("$'" + hier.pivots[curChn.pivotID].pivotName + "'") -- at v1.02. it should be curChn.pivotID + 1 at v1.04
				-- pivotID == 0 = ROOTTRANSFORM (not in gmPivots). Skip out-of-range
				-- pivots cleanly unless Strict Mode is enabled by the user.
				if ignoreErrors do
				(
					if curChn.pivotID < 1 or curChn.pivotID > gmPivots.count do continue
				)
				curObj = gmPivots[curChn.pivotID] -- test at v1.04
				if curObj != undefined then
				(
					case curChn.flags of
					(
						0x0000: --BIT_CHANNEL_VIS = 0	// turn meshes on and off depending on anim frame.
						(
							defVal = (curChn.defaultVal > 0)
							-- A single On_Off key at frame 0 evaluates to "off" across
							-- the playable timeline (1..N), which on re-export bakes
							-- "hidden everywhere" into the bit channel and makes the
							-- model invisible in-game. Pre-scan to detect whether the
							-- channel is constant; if so, leave .visibility static and
							-- don't create any controller at all - the exporter then
							-- defaults to "always visible" which matches the file.
							hasTransition = false
							byteIdx = 1
							bitIdx = 1
							for f = curChn.firstFrame to curChn.lastFrame while not hasTransition do
							(
								curVal = bit.get (curChn.values[byteIdx]) bitIdx
								if curVal != defVal then hasTransition = true
								bitIdx += 1
								if bitIdx > 8 then
								(
									byteIdx += 1
									bitIdx = 1
								)
							)
							if not hasTransition then
							(
								curObj.visibility = defVal
							)
							else
							(
								curObj.visibility = defVal
								-- On_Off keys carry NO value: each key simply flips the
								-- state, and accessing key properties on this controller
								-- throws "Cannot access keys for this controller". The old
								-- code did `curKey.value = curVal`, so this branch crashed
								-- on the FIRST model with a non-constant visibility channel
								-- ever imported. Re-emit the channel as toggle keys: the
								-- controller outputs ON before its first key, so walk the
								-- frames comparing desired state vs current toggle state and
								-- drop a key wherever they differ. Keys go at (f + 1) to
								-- match the motion channels' W3D->Max frame offset.
								local visOk = true
								try
								(
									local ooCtrl = On_Off()
									curObj.visibility.controller = ooCtrl
									local ooState = true   -- On_Off output before the first key
									if not defVal do
									(
										addNewKey ooCtrl 0
										ooState = false
									)
									byteIdx = 1
									bitIdx = 1
									for f = curChn.firstFrame to curChn.lastFrame do
									(
										curVal = bit.get (curChn.values[byteIdx]) bitIdx
										if curVal != ooState then
										(
											addNewKey ooCtrl (f + 1)
											ooState = curVal
										)
										bitIdx += 1
										if bitIdx > 8 then
										(
											byteIdx += 1
											bitIdx = 1
										)
									)
								)
								catch ( visOk = false )
								-- Fallback: stepped float track (0/1) for Max versions that
								-- refuse MAXScript key creation on On_Off as well. Step
								-- tangents avoid fade ramps; the exporter samples visibility
								-- over time, so this round-trips the same.
								if not visOk do
								(
									local fc = bezier_float()
									curObj.visibility.controller = fc
									local k0 = addNewKey fc 0
									k0.value = if defVal then 1.0 else 0.0
									k0.inTangentType = #step
									k0.outTangentType = #step
									prevVal = defVal
									byteIdx = 1
									bitIdx = 1
									for f = curChn.firstFrame to curChn.lastFrame do
									(
										curVal = bit.get (curChn.values[byteIdx]) bitIdx
										if curVal != prevVal then
										(
											local kk = addNewKey fc (f + 1)
											kk.value = if curVal then 1.0 else 0.0
											kk.inTangentType = #step
											kk.outTangentType = #step
											prevVal = curVal
										)
										bitIdx += 1
										if bitIdx > 8 then
										(
											byteIdx += 1
											bitIdx = 1
										)
									)
								)
							)
							--curKey = addNewKey curObj.visibility.controller (curChn.lastFrame + 1)
							--curKey.selected = defVal
						)
						--0x0001: --BIT_CHANNEL_TIMECODED_VIS
					)
				)
			) --for end
		) --if end

		/*for i=1 to cmpAnim.channels.count do
		(
			if cmpAnim.channels[i].type == 2 then
				format "%;%;%\n" cmpAnim.channels[i].pivotID cmpAnim.channels[i].increment gmPivots[cmpAnim.channels[i].pivotID].name
			else
				format "%;%;%\n" cmpAnim.channels[i].pivotID cmpAnim.channels[i].timeCodesCount gmPivots[cmpAnim.channels[i].pivotID].name
		)*/

		if (cmpAnim != undefined) and (hier != undefined) and _rnImportAnim then
		(
			if cmpAnim.header.frameCount < 1 do cmpAnim.header.frameCount = 1
			-- Honor user-chosen animation range (Renegade dialog spinners).
			local _rangeStart = if _rnAnimFrom >= 0 then (_rnAnimFrom + 1) else 1
			local _rangeEnd   = if _rnAnimTo   >= 0 then (_rnAnimTo   + 1) else cmpAnim.header.frameCount
			if _rangeEnd <= _rangeStart do _rangeEnd = _rangeStart + 1
			animationRange = interval _rangeStart _rangeEnd
			frameRate = cmpAnim.header.frameRate

			case cmpAnim.header.flavour of
			(
				0x0: --ANIM_FLAVOUR_TIMECODED
				(
					for i = 1 to cmpAnim.channels.count do
					(
						if keyboard.escPressed do
						(
							format "*** Import aborted by user (ESC) at compressed-timecoded channel %/% ***\n" i cmpAnim.channels.count
							_rnAborted = true
							exit
						)
						curChn = cmpAnim.channels[i]
						try
						( curObj = gmPivots[curChn.pivotID] ) -- test at v1.04
						catch
						( continue )
						if curObj != undefined then
						(
							datumPos = hier.pivots[curChn.pivotID + 1].pos
							datumRot = hier.pivots[curChn.pivotID + 1].rotation

							-- added in 1.12, handles channels with a single value
							if curChn.values.count == 1 do
							(
								curChn.values[curChn.values.count+1] = AnimationTimeCodedKey cmpAnim.header.frameCount curChn.values[curChn.values.count].keyValue
								curChn.timeCodesCount += 1
							)

							case curChn.flags of
							(
								0x0000: --ANIM_CHANNEL_TIMECODED_X = 0
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 then
									(
										for t=1 to curChn.timeCodesCount do
										(
											fCurr = curChn.values[t].keyTime
											vCurr = curChn.values[t].keyValue

											if t > 1 then
											(
												fPrev = curChn.values[t-1].keyTime + 1
												vPrev = curChn.values[t-1].keyValue
											)
											else
											(
												fPrev = fCurr
												vPrev = vCurr
											)

											if (fCurr >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fCurr do
												(
													--print f
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													( curKey = curObj.pos.controller.keys[k] )

													step = vPrev + ((vCurr - vPrev) * (f - fPrev + 1) / (fCurr - fPrev + 1))
													curKey.value += [step, 0, 0] * (inverse datumRot)
												)
											)
										)
									)
									else if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0 then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [curChn.initDelta,0,0] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [curChn.initDelta,0,0] * (inverse datumRot)
										)
										prevKey = curKey

										byteIdx = 1
										bitIdx = 1

										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
										--for b = 1 to cmpAnim.channels[i].values.count do
										--( print cmpAnim.channels[i].values[b] )
										for t = 2 to cmpAnim.channels[i].values.count do
										(

											for bitIdx = 1 to 8 do
											(
												curVal = bit.get (curChn.values[byteIdx]) bitIdx
												--print curVal
											)
										)
											/*if curVal then
											(
												curKey = addNewKey curObj.pos.controller t
												temp = [curChn.increment,0,0] * (inverse datumRot)
												break()
												curKey.value = prevKey.value + [curChn.increment,0,0]
												prevKey = curKey
												break()
											)
											else
											(
												curKey = addNewKey curObj.pos.controller t
												curKey.value = prevKey.value - [curChn.increment,0,0]
												prevKey = curKey
											)*/
										--)
									)
								)
								0x0001: --ANIM_CHANNEL_TIMECODED_Y = 1
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											fNext = curChn.values[t].keyTime
											vNext = curChn.values[t].keyValue
											if t > 1 then
											(
												fPrev = curChn.values[(t - 1)].keyTime + 1
												vPrev = curChn.values[(t - 1)].keyValue
											)
											else
											(
												fPrev = fNext
												vPrev = vNext
											)

											if (fNext >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fNext do
												(
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													(
														curKey = curObj.pos.controller.keys[k]
													)
													step = vPrev + ((vNext - vPrev) * (f - fPrev + 1) / (fNext - fPrev + 1))
													curKey.value += [0, step, 0] * (inverse datumRot)
												)
											)
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0f then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [0,curChn.initDelta,0] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [0,curChn.initDelta,0] * (inverse datumRot)
										)

										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x0002: --ANIM_CHANNEL_TIMECODED_Z = 2
								(
									curObj.pos.controller = linear_position()
									curKey = addNewKey curObj.pos.controller 0
									curKey.value = datumPos
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											fNext = curChn.values[t].keyTime
											vNext = curChn.values[t].keyValue
											if t > 1 then
											(
												fPrev = curChn.values[(t - 1)].keyTime + 1
												vPrev = curChn.values[(t - 1)].keyValue
											)
											else
											(
												fPrev = fNext
												vPrev = vNext
											)
											if (fNext >= 0) and (fPrev >= 0) then
											(
												for f = fPrev to fNext do
												(
													k = getKeyIndex curObj.pos.controller (f + 1)
													if k == 0 then
													(
														curKey = addNewKey curObj.pos.controller (f + 1)
														curKey.value = datumPos
													)
													else
													(
														curKey = curObj.pos.controller.keys[k]
													)
													step = vPrev + ((vNext - vPrev) * (f - fPrev + 1) / (fNext - fPrev + 1))
													curKey.value += [0, 0, step] * (inverse datumRot)
												)
											)
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										k = getKeyIndex curObj.pos.controller 1
										if k == 0f then
										(
											curKey = addNewKey curObj.pos.controller 1
											curKey.value = datumPos + [0,0,curChn.initDelta] * (inverse datumRot)
										)
										else
										(
											curKey = curObj.pos.controller.keys[k]
											curKey.value += [0,0,curChn.initDelta] * (inverse datumRot)
										)

										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x0006: --ANIM_CHANNEL_TIMECODED_Q = 6
								(
									curObj.rotation.controller = linear_rotation()
									curKey = addNewKey curObj.rotation.controller 0
									curKey.value = datumRot
									if cmpAnim.channels[i].type == 1 do
									(
										for t = 1 to curChn.timeCodesCount do
										(
											f = curChn.values[t].keyTime
											curKey = addNewKey curObj.rotation.controller (f + 1)
											curKey.value = curChn.values[t].keyValue - (inverse datumRot)

											/*prvKey = getKey curObj.rotation.controller (curObj.rotation.controller.keys.count - 1)
											if (prvKey.time < curKey.time - 1) do
											(
												for q = (prvKey.time + 1) to (curKey.time - 1) do
												(
													prvCoef = ((curKey.time - q) as Integer)/((curKey.time - prvKey.time) as Integer)
													curCoef = ((q - prvKey.time) as Integer)/((curKey.time - prvKey.time) as Integer)

													x = curCoef*curKey.value.x + prvCoef*prvKey.value.x
													y = curCoef*curKey.value.y + prvCoef*prvKey.value.y
													z = curCoef*curKey.value.z + prvCoef*prvKey.value.z
													w = curCoef*curKey.value.w + prvCoef*prvKey.value.w

													newKey = addNewKey curObj.rotation.controller q
													newKey.value = Quat x y z w
												)
											)*/
										)
									)
									if cmpAnim.channels[i].type == 2 do
									(
										curKey = addNewKey curObj.rotation.controller 1
										curKey.value = datumRot + curChn.initDelta

										--print ("-----" + (cmpAnim.channels[i].pivotID As String) + "-----")
										--print ("Type:" + (cmpAnim.channels[i].flags As String))
										--print ("Frames:" + (cmpAnim.channels[i].framesCount As String))
										--print (cmpAnim.channels[i].values.count)
									)
								)
								0x000F:
								(
								)
							)
						)
					)
					--for i = 1 to cmpAnim.bitchannels.count do
					--(
					--	curChn = cmpAnim.bitchannels[i]
					--	curObj = gmPivots[curChn.pivotID] -- test at v1.04
					--	if curObj != undefined then
					--	(
					--		case curChn.flags of
					--		(
					--			--0x0000: --BIT_CHANNEL_VIS = 0	// turn meshes on and off depending on anim frame.
					--			0x0001: --BIT_CHANNEL_TIMECODED_VIS = 1
					--			(
					--				defVal = (curChn.defaultVal > 0)
					--				curObj.visibility = defVal
					--				curObj.visibility.controller = On_Off()
					--				curKey = addNewKey curObj.visibility.controller 0
					--				curKey.selected = defVal
					--				prevVal = defVal
					--				byteIdx = 1
					--				bitIdx = 1
					--				for t = 1 to curChn.timeCodesCount do
					--				(
					--					f = curChn.values[t].time
					--					curVal = bit.get (curChn.values[byteIdx]) bitIdx
					--					if curVal != prevVal then
					--					(
					--						curKey = addNewKey curObj.visibility.controller (f + 1)
					--						curKey.selected = curVal
					--						prevVal = curVal
					--					)
					--					bitIdx += 1
					--					if bitIdx > 8 then
					--					(
					--						byteIdx += 1
					--						bitIdx = 1
					--					)
					--				)
					--			)
					--		)
					--	)
					--) --for end
				)
				0x1: --ANIM_FLAVOUR_ADAPTIVE_DELTA
				(
				)
				--0x2: --ANIM_FLAVOUR_VALID
			)
		) --if end

		if wwBinding do
		(
			for m = 1 to meshes.count do
			(
				-- gmMeshes has undefined holes whenever mesh creation was skipped
				-- (Renegade subset/LOD filter, bonesOnly, ESC abort) -- binding an
				-- undefined node throws, so skip those slots.
				if gmMeshes[m] == undefined do continue
				if (meshes[m].vertInfs != undefined) do
				(
					--convertTo gmMeshes[m] Editable_Poly
					--convertTo gmMeshes[m] Editable_Mesh
					bindSpaceWarp gmMeshes[m] wwSkin

					for p = 1 to gmPivots.count do
					(
						if gmPivots[p] != undefined do
							wwAddBone gmPivots[p] gmMeshes[m]
					)

					for v = 1 to (meshes[m].vertInfs.boneIds1.count) do
					(
						--print v
						--print meshes[m].vertInfs.boneIds1[v]
						--print meshes[m].vertInfs.boneWgts1[v]
						--print meshes[m].vertInfs.boneIds2[v]
						--print meshes[m].vertInfs.boneWgts2[v]
						--print "---------------"

						-- Bone-index guards: vertInfs reference into gmPivots, but if the
						-- skeleton came from a different file (Use External Skeleton) or
						-- the model contains bone indices past the loaded pivot count,
						-- the lookup yields `undefined`. wwSetBoneWeight requires a real
						-- INode, so skip the influence rather than throwing.
						local b1 = meshes[m].vertInfs.boneIds1[v]
						if (b1 > 0) and (b1 <= gmPivots.count) do
						(
							curBone = gmPivots[b1]
							if curBone != undefined do
								wwSetBoneWeight gmMeshes[m] (v - 1) 1 curBone meshes[m].vertInfs.boneWgts1[v]
						)
						local b2 = meshes[m].vertInfs.boneIds2[v]
						if (b2 > 0) and (b2 <= gmPivots.count) and (meshes[m].vertInfs.boneWgts1[v] < 100) do
						(
							curBone = gmPivots[b2]
							if curBone != undefined do
								wwSetBoneWeight gmMeshes[m] (v - 1) 2 curBone meshes[m].vertInfs.boneWgts2[v]
						)
					)
				)
			)
		)

		if maxBinding do
		(
			for m = 1 to meshes.count do
			(
				-- Same undefined-hole guard as the wwBinding loop above.
				if gmMeshes[m] == undefined do continue
				if (meshes[m].vertInfs != undefined) do
				(
					local currSkin = skin()
					addModifier gmMeshes[m] currSkin
					currSkin.bone_Limit = 2

					setCommandPanelTaskMode #modify
					modPanel.setCurrentObject currSkin ui:true

					-- DepBones leaves undefined gaps in gmPivots, and Skin's bone
					-- indices count only the bones actually added -- so build a
					-- pivot-ID -> skin-bone-index map while adding, instead of
					-- assuming pivot ID p lands at skin index p. (With no gaps the
					-- map is the identity, preserving the original behaviour.)
					local skinIxOfPivot = #()
					local addedBones = 0
					for p = 1 to gmPivots.count do
					(
						if gmPivots[p] != undefined then
						(
							skinOps.addBone currSkin gmPivots[p] 0 --0 for no redrawing
							addedBones += 1
							skinIxOfPivot[p] = addedBones
						)
						else skinIxOfPivot[p] = 0
					)

					max modify mode
					redrawViews()

					for v = 1 to (meshes[m].vertInfs.boneIds1.count) do
					(
						local b1 = meshes[m].vertInfs.boneIds1[v]
						if (b1 > 0) and (b1 <= gmPivots.count) and (skinIxOfPivot[b1] > 0) do
						(
							skinOps.unNormalizeVertex currSkin v false
							skinOps.selectBone currSkin skinIxOfPivot[b1]
							skinOps.replaceVertexWeights currSkin v skinIxOfPivot[b1] 1
							skinOps.setVertexWeights currSkin v skinIxOfPivot[b1] 1
						)

						local b2 = meshes[m].vertInfs.boneIds2[v]
						if (b2 > 0) and (b2 <= gmPivots.count) and (skinIxOfPivot[b2] > 0) and (meshes[m].vertInfs.boneWgts1[v] < 100) do
						(
							skinOps.selectBone currSkin skinIxOfPivot[b2]
							skinOps.setVertexWeights currSkin v skinIxOfPivot[b2] (0.01*meshes[m].vertInfs.boneWgts2[v])
						)
					)
				)
			)
		)

		-- ---- deferred Fix Vertices / Fix Normals ----
		-- Run after wwBinding / maxBinding so that Skin or W3DSkin (which were applied to
		-- gmMeshes[m] during the binding pass) see the original topology when they bind,
		-- and the geometry edits below sit on top of (or beneath) Skin without changing
		-- the vert count Skin already weighted to.
		if fixVertices do
		(
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue

				-- Skip skinned meshes: Skin's per-vertex weights are bound to specific
				-- vertex indices, and welding renumbers/removes verts, which would
				-- silently break the binding. Skinning is the higher-priority feature.
				local isSkinned = false
				try
				(
					for m in gmMeshes[i].modifiers while not isSkinned do
					(
						local cn = (classOf m) as string
						if cn == "Skin" or cn == "Physique" do isSkinned = true
					)
				) catch ()

				if isSkinned then
				(
					if debugOutput do
						format "  -> Fix Vertices [%]: skipped (mesh has Skin/Physique; weld would break weights)\n" gmMeshes[i].name
					continue
				)

				try
				(
					local vBefore = gmMeshes[i].numVerts
					local elementId = 0

					for f = 1 to gmMeshes[i].numFaces do
						setFaceSmoothGroup gmMeshes[i] f 0
					update gmMeshes[i]

					local visited = #{}
					for f = 1 to gmMeshes[i].numFaces do
					(
						if visited[f] do continue
						elementId += 1
						local elemFaces = meshOp.getElementsUsingFace gmMeshes[i] #{f}
						local sg = bit.shift 1 (mod (elementId - 1) 32)
						for ef in elemFaces do
						(
							setFaceSmoothGroup gmMeshes[i] ef sg
							visited[ef] = true
						)
					)
					update gmMeshes[i]

					meshOp.weldVertsByThreshold gmMeshes[i] #all 0.01
					update gmMeshes[i]

					if debugOutput do
					(
						try
						(
							local vAfter = gmMeshes[i].numVerts
							local welded = vBefore - vAfter
							local sgSpan = if elementId <= 32 then (elementId as string) else ("32 (cycled, " + (elementId as string) + " elements)")
							format "  -> Fix Vertices [%]: cleared SGs, found % element(s), assigned SG span=%, welded %->% verts (-% removed) at threshold 0.01\n" gmMeshes[i].name elementId sgSpan vBefore vAfter welded
						)
						catch ( format "  -> Fix Vertices [%]: completed but debug print failed: %\n" gmMeshes[i].name (getCurrentException()) )
					)
				)
				catch
				(
					if debugOutput do
						format "  -> Fix Vertices [%]: FAILED with error: %\n" gmMeshes[i].name (getCurrentException())
				)
			)
		)

		-- "Import extended w3d information": surface the W3D_MESH_HEADER3 Attributes
		-- (Geometry Type + Hide/2-Sided/Shadow/Shatter/Tangents/Prelit/AlwaysDynLight,
		-- Collision Physical/Projectile/Vis/Camera/Vehicle) and SortLevel into each
		-- imported mesh's W3D Tools panel via the wwSetFlags / wwSetSorting primitives
		-- in max2w3d.dle. Without this pass, imported meshes always read back as the
		-- default (Normal, no flags) regardless of what the source .w3d encoded.
		-- W3DBOX (collision box) attrs are decoded by the same wwSetFlags helper.
		if importExtendedW3D do
		(
			if debugOutput do
				format "=== Import extended W3D Info: applying mesh-header attrs ===\n"
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue
				if meshes[i] == undefined or meshes[i].header == undefined do continue
				local hdr = meshes[i].header
				if debugOutput do
				(
					format "  [%] read: attrs=% sortLevel=% (props: %)\n" \
						gmMeshes[i].name (bit.intAsHex hdr.attrs) hdr.sortLevel (cfDecodeW3DAttrs hdr.attrs)
				)
				try
				(
					wwSetFlags gmMeshes[i] hdr.attrs
					wwSetSorting gmMeshes[i] hdr.sortLevel
					if debugOutput do
						format "  [%] applied: wwSetFlags + wwSetSorting OK\n" gmMeshes[i].name
				)
				catch
				(
					if debugOutput do
						format "  [%] FAILED to apply (rebuilt max2w3d.dle required): %\n" gmMeshes[i].name (getCurrentException())
				)
			)
		)

		if fixNormals do
		(
			for i = 1 to gmMeshes.count do
			(
				if gmMeshes[i] == undefined do continue
				try
				(
					-- Smoothing-group baseline write goes to the base mesh; if a modifier is
					-- already on the stack (Skin or the Edit_Mesh from Fix Vertices), the base
					-- mesh is locked. Wrap in try/catch and fall through — Edit Normals' Reset
					-- still works without it, just from the modifier's own normal data.
					-- Skip the SG=1 baseline when Fix Vertices ran: that pass assigned a
					-- unique SG per element to preserve hard edges across the weld, and
					-- forcing every face to SG 1 here would smooth across those element
					-- seams. Reset will recompute from whatever SGs are in place.
					if not fixVertices do
					(
						try
						(
							for f = 1 to gmMeshes[i].numFaces do
								setFaceSmoothGroup gmMeshes[i] f 1
							update gmMeshes[i]
						) catch ()
					)

					local enMod = Edit_Normals()
					addModifier gmMeshes[i] enMod

					local prevSel = selection as array
					select gmMeshes[i]
					max modify mode

					subobjectLevel = 0
					modPanel.setCurrentObject enMod
					subobjectLevel = 1
					modPanel.setCurrentObject enMod

					local nrmCount = enMod.EditNormalsMod.GetNumNormals()
					if nrmCount > 0 do
					(
						enMod.EditNormalsMod.SetSelection #{1..nrmCount}
						enMod.EditNormalsMod.Reset()
					)

					subobjectLevel = 0

					try
					(
						if prevSel.count == 0 then clearSelection() else select prevSel
					) catch ()
				) catch ()
			)
		)
		-- ---- end deferred ----

		if pickbox != undefined then
		(
			sName = pickbox.boxName
			dotPos = findString sName "."
			if (dotPos != undefined) and (dotPos < sName.count) do (sName = subString sName (dotPos + 1) -1)
			gmBox = Box name:sName pos:pickbox.centre
			gmBox.width = pickbox.extent.x
			gmBox.length = pickbox.extent.y
			gmBox.height = pickbox.extent.z
			gmBox.wirecolor = pickbox.boxColor

			-- W3DBOX attrs (W3D_BOX_ATTRIBUTE_ALIGNED/ORIENTED + W3D_MESH_FLAG_COLLISION_TYPE_*)
			-- get decoded by the same wwSetFlags helper used for meshes.
			if importExtendedW3D do
			(
				if debugOutput do
					format "  [%] read: box attrs=% (props: %)\n" \
						gmBox.name (bit.intAsHex pickbox.attrs) (cfDecodeW3DAttrs pickbox.attrs)
				try
				(
					wwSetFlags gmBox pickbox.attrs
					if debugOutput do
						format "  [%] applied: wwSetFlags OK\n" gmBox.name
				)
				catch
				(
					if debugOutput do
						format "  [%] FAILED to apply (rebuilt max2w3d.dle required): %\n" gmBox.name (getCurrentException())
				)
			)
		)

		-- ---- renegade: aggregate and proxy bones ----
		-- Aggregates (0x705): referenced sub-objects that aren't imported as geometry;
		-- represented as hidden point helpers parented to the declared bone.
		-- Proxies (0x706): application-defined markers; represented as visible point helpers.
		if hlodSet != undefined and hier != undefined then
		(
			if hlodSet.aggregates != undefined and hlodSet.aggregates.count > 0 do
			(
				if debugOutput do format "=== HLOD Aggregates: % entries ===\n" hlodSet.aggregates.count
				local _aShape = W3DImporterInit.getActive "AggregateShape"
				local _aSize  = W3DImporterInit.getActive "AggregateSize"
				local _aColor = W3DImporterInit.getActive "AggregateColor"
				if _aShape == undefined do _aShape = 1
				if _aSize  == undefined or _aSize == 0 do _aSize = 1.0
				if _aColor == undefined do _aColor = (color 255 128 0)
				for i = 1 to hlodSet.aggregates.count do
				(
					local agg = hlodSet.aggregates[i]
					local dotPos = findString agg.name "."
					local shortName = if dotPos != undefined then (subString agg.name (dotPos + 1) -1) else agg.name
					-- renegade selection filter
					if rnSelection != undefined and rnSelection.aggregates.count > 0 do
						if findItem rnSelection.aggregates shortName == 0 do continue
					local aggNode = W3DImporterInit.makeShape _aShape (w3dUniqueNodeName shortName) _aSize _aColor
					hide aggNode
					try ( wwSetExportGeoFlag aggNode true ) catch ()
					try ( wwSetExportBoneFlag aggNode false ) catch ()
					try ( wwSetType aggNode 8 ) catch ()
					if agg.pivotIndex > 0 and agg.pivotIndex <= gmPivots.count and gmPivots[agg.pivotIndex] != undefined then
						aggNode.parent = gmPivots[agg.pivotIndex]
					if debugOutput do format "  aggregate [%] -> pivot %\n" shortName agg.pivotIndex
				)
			)
			if hlodSet.proxies != undefined and hlodSet.proxies.count > 0 do
			(
				if debugOutput do format "=== HLOD Proxies: % entries ===\n" hlodSet.proxies.count
				local _pShape = W3DImporterInit.getActive "ProxyShape"
				local _pSize  = W3DImporterInit.getActive "ProxySize"
				local _pColor = W3DImporterInit.getActive "ProxyColor"
				if _pShape == undefined do _pShape = 1
				if _pSize  == undefined or _pSize == 0 do _pSize = 1.0
				if _pColor == undefined do _pColor = (color 0 200 255)
				for i = 1 to hlodSet.proxies.count do
				(
					local prx = hlodSet.proxies[i]
					local dotPos = findString prx.name "."
					local shortName = if dotPos != undefined then (subString prx.name (dotPos + 1) -1) else prx.name
					-- renegade selection filter
					if rnSelection != undefined and rnSelection.proxies.count > 0 do
						if findItem rnSelection.proxies shortName == 0 do continue
					local prxNode = W3DImporterInit.makeShape _pShape (w3dUniqueNodeName shortName) _pSize _pColor
					-- Visual marker only -- do NOT export it. The HLOD proxy array is generated by
					-- max2w3d from the '~'-named proxy PIVOT bones (built from the file's PIVOTS, they
					-- carry the proxy name + '~'); exporting this marker too would double the proxy
					-- array (geo+'~') or write a stray box mesh (geo+bare name). So geo/bone flags off.
					try ( wwSetExportGeoFlag prxNode false ) catch ()
					try ( wwSetExportBoneFlag prxNode false ) catch ()
					if prx.pivotIndex > 0 and prx.pivotIndex <= gmPivots.count and gmPivots[prx.pivotIndex] != undefined then
						prxNode.parent = gmPivots[prx.pivotIndex]
					if debugOutput do format "  proxy [%] -> pivot %\n" shortName prx.pivotIndex
				)
			)
		)
		-- ---- end renegade aggregate/proxy ----

		-- Pure animation (v19): when checked, bake an FBX next to the source .w3d
		-- (works in both batch and single-file mode). Wrapped in try() because
		-- FBXEXP requires the FBX plugin to be loaded; failure is non-fatal.
		local pureAnimationMode = false
		try
		(
			if isProperty rltMain #ckbPureAnim do pureAnimationMode = rltMain.ckbPureAnim.checked
		)
		catch()

		local baseName = substring w3dfilename 1 (w3dfilename.count-4)

		if pureAnimationMode do
		(
			try
			(
				local fbxPath = baseName + ".fbx"
				format "Pure animation: exporting FBX to: %\n" fbxPath
				exportFile fbxPath #noPrompt selectedOnly:false using:FBXEXP
			)
			catch
			(
				format "Pure animation: FBX export failed (%)\n" (getCurrentException())
			)
		)

		if batch and not _rnAborted do
		(
			saveMaxFile baseName
			resetMaxFile #noPrompt
		)

		if _rnAborted do
			format "*** Import incomplete -- partial scene left for manual cleanup ***\n"
	)
)

