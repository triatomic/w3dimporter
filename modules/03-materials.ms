-- ---------------------------------------------------------------------------
-- Top-level W3DMaterial builders.
--
-- These used to live nested inside cfW3DImporter, hidden ~1000 lines into a
-- 3200-line function. Pulled out so they're navigable and testable. They take
-- the W3DMaterial-plugin availability flag explicitly (see ::w3dMatlAvailable
-- probed in `rltMain open` / cfW3DImporter entry) rather than each setProperty
-- being individually wrapped in `try (...) catch ()`. If the plugin isn't
-- registered they return undefined immediately; callers already handle that.
-- ---------------------------------------------------------------------------

fn buildW3DMatl matName vm texFile blendMode w3dMatlAvailable =
(
	if not w3dMatlAvailable do return undefined
	local m = undefined
	try ( m = W3DMaterial name:matName ) catch ( m = undefined )
	if m == undefined do return undefined

	-- vertex material colors / opacity / shininess. Guarded: the stage-mapping
	-- block below already checks vm.vmInfo != undefined, but these lines used to
	-- dereference it unconditionally first, making that guard dead code -- a
	-- VERTEX_MATERIAL chunk without a VERTEX_MATERIAL_INFO sub-chunk now degrades
	-- to plugin defaults instead of throwing.
	if vm.vmInfo != undefined do
	(
		setProperty m #ambientcolour vm.vmInfo.ambient
		setProperty m #diffusecolour vm.vmInfo.diffuse
		setProperty m #specularcolour vm.vmInfo.specular
		setProperty m #emissivecolour vm.vmInfo.emissive
		setProperty m #opacity vm.vmInfo.opacity
		setProperty m #shininess vm.vmInfo.shininess
		setProperty m #translucency vm.vmInfo.translucency
	)

	-- stage0/stage1 mapping types come from W3D vmInfo.attrs bitfield:
	-- bits 16-23 = stage0Mapping, bits 8-15 = stage1Mapping. The mapper-args
	-- strings live in vmArgs0/vmArgs1.
	if vm.vmInfo != undefined do
	(
		local attrsVal = vm.vmInfo.attrs
		local stage0Map = bit.and (bit.shift attrsVal -16) 0xFF
		local stage1Map = bit.and (bit.shift attrsVal -8) 0xFF
		setProperty m #stage0mapping stage0Map
		setProperty m #stage1mapping stage1Map
	)
	if vm.vmArgs0 != undefined and vm.vmArgs0 != "" do
		setProperty m #stage0mappingargs vm.vmArgs0
	if vm.vmArgs1 != undefined and vm.vmArgs1 != "" do
		setProperty m #stage1mappingargs vm.vmArgs1

	-- W3D doesn't carry these; apply sensible defaults.
	setProperty m #stage0mappinguvchannel 1
	setProperty m #stage1mappinguvchannel 1
	setProperty m #speculartodiffuse false

	-- blend mode comes straight from the W3D shader classification
	setProperty m #blendmode blendMode
	setProperty m #alphatest (blendMode == 6 or blendMode == 7)

	-- additive (Add): don't write to z-buffer, force alphatest off, set src/dst = One/One
	if blendMode == 1 do
	(
		setProperty m #customblendwritezbuffer false
		setProperty m #alphatest false
		setProperty m #blendmodesrc 1  -- One
		setProperty m #blendmodedest 1 -- One
	)
	-- alpha blend (5) and alpha-test+blend (7): set src/dst = SrcAlpha / OneMinusSrcAlpha
	-- The plugin's blendmode dropdown sometimes doesn't auto-fill these; write them explicitly.
	if (blendMode == 5) or (blendMode == 7) do
	(
		setProperty m #customblendwritezbuffer false
		setProperty m #blendmodesrc 2  -- SrcAlpha
		setProperty m #blendmodedest 5 -- OneMinusSrcAlpha
	)

	-- stage 0 texture
	if texFile != undefined and texFile != "" do
	(
		setProperty m #stage0texenabled true
		try ( setProperty m #stage0texturemap (bitmaptex filename:texFile) )
		catch ( format "*** [buildW3DMatl] bitmaptex failed for %\n" texFile )
		setProperty m #stage0display true -- show in viewport
	)
	return m
)

fn _w3dSetPassProp m baseName suffix value =
(
	-- Suffixed param names are only defined for the pass indices the plugin
	-- exposes. A typo or a plugin built without pass 4 paramblocks is a real
	-- bug, not something to silently swallow -- but we don't want one bad
	-- param to abort the whole material build, so we catch+log per call.
	local nm = (baseName + suffix) as Name
	try ( setProperty m nm value )
	catch ( format "*** [W3DMatl] setProperty % failed (value=%)\n" nm value )
)

fn buildMultiPassW3DMatl matName vmList texList tex1List bmList w3dMatlAvailable =
(
	-- Builds a single W3DMaterial with native multi-pass support.
	-- Requires a max2w3d.dle build where pass 2/3/4 ParamBlock2 declarations have
	-- suffixed param internal-names (_p2/_p3/_p4); pass 1 keeps bare names. See
	-- src/w3dmaxtools/Source/w3dmaterial.cpp -> W3DMAT_PASS_PARAMS macro.
	if not w3dMatlAvailable do return undefined
	local nPasses = vmList.count
	if nPasses < 1 or nPasses > 4 do return undefined
	local m = undefined
	try ( m = W3DMaterial name:matName ) catch ( m = undefined )
	if m == undefined do return undefined
	-- Set pass count first (lives on PassCountBlock, exposed as #passcount)
	setProperty m #passcount nPasses
	local suffixes = #("", "_p2", "_p3", "_p4")
	-- Pick the best pass for viewport display.
	-- Priority 1: stage0 mapping == UV (0). Priority 2 (tiebreaker): opaque blend mode (0).
	-- A pass without a stage0 texture is skipped; stage1-only passes are never chosen.
	local displayPassIdx = 0
	local displayPassIsUV = false
	local displayPassIsOpaque = false
	for p = 1 to nPasses do
	(
		if texList[p] != undefined and texList[p] != "" do
		(
			local vm = vmList[p]
			local stage0Map = 0
			if vm.vmInfo != undefined do
				stage0Map = bit.and (bit.shift vm.vmInfo.attrs -16) 0xFF
			local isUV = (stage0Map == 0)
			local isOpaque = (bmList[p] == 0)
			local isBetter = (displayPassIdx == 0)
			if not isBetter do
			(
				if isUV and not displayPassIsUV then
					isBetter = true
				else if isUV and displayPassIsUV and isOpaque and not displayPassIsOpaque then
					isBetter = true
			)
			if isBetter do
			(
				displayPassIdx = p
				displayPassIsUV = isUV
				displayPassIsOpaque = isOpaque
			)
		)
	)
	for p = 1 to nPasses do
	(
		local sfx = suffixes[p]
		local vm = vmList[p]
		local tex0 = texList[p]
		local tex1 = tex1List[p]
		local blendMode = bmList[p]
		-- vertex material colors / opacity / shininess (guarded for the same
		-- reason as buildW3DMatl: vm.vmInfo can legitimately be absent)
		if vm.vmInfo != undefined do
		(
			_w3dSetPassProp m "ambientcolour" sfx vm.vmInfo.ambient
			_w3dSetPassProp m "diffusecolour" sfx vm.vmInfo.diffuse
			_w3dSetPassProp m "specularcolour" sfx vm.vmInfo.specular
			_w3dSetPassProp m "emissivecolour" sfx vm.vmInfo.emissive
			_w3dSetPassProp m "opacity" sfx vm.vmInfo.opacity
			_w3dSetPassProp m "shininess" sfx vm.vmInfo.shininess
			_w3dSetPassProp m "translucency" sfx vm.vmInfo.translucency
		)
		if vm.vmInfo != undefined do
		(
			local attrsVal = vm.vmInfo.attrs
			local stage0Map = bit.and (bit.shift attrsVal -16) 0xFF
			local stage1Map = bit.and (bit.shift attrsVal -8) 0xFF
			_w3dSetPassProp m "stage0mapping" sfx stage0Map
			_w3dSetPassProp m "stage1mapping" sfx stage1Map
		)
		if vm.vmArgs0 != undefined and vm.vmArgs0 != "" do
			_w3dSetPassProp m "stage0mappingargs" sfx vm.vmArgs0
		if vm.vmArgs1 != undefined and vm.vmArgs1 != "" do
			_w3dSetPassProp m "stage1mappingargs" sfx vm.vmArgs1
		_w3dSetPassProp m "stage0mappinguvchannel" sfx 1
		_w3dSetPassProp m "stage1mappinguvchannel" sfx 1
		_w3dSetPassProp m "speculartodiffuse" sfx false
		_w3dSetPassProp m "blendmode" sfx blendMode
		_w3dSetPassProp m "alphatest" sfx (blendMode == 6 or blendMode == 7)
		if blendMode == 1 do
		(
			_w3dSetPassProp m "customblendwritezbuffer" sfx false
			_w3dSetPassProp m "alphatest" sfx false
			_w3dSetPassProp m "blendmodesrc" sfx 1
			_w3dSetPassProp m "blendmodedest" sfx 1
		)
		if (blendMode == 5) or (blendMode == 7) do
		(
			_w3dSetPassProp m "customblendwritezbuffer" sfx false
			_w3dSetPassProp m "blendmodesrc" sfx 2
			_w3dSetPassProp m "blendmodedest" sfx 5
		)
		if tex0 != undefined and tex0 != "" do
		(
			_w3dSetPassProp m "stage0texenabled" sfx true
			try ( _w3dSetPassProp m "stage0texturemap" sfx (bitmaptex filename:tex0) )
			catch ( format "*** [buildMultiPassW3DMatl] bitmaptex failed for stage0 %\n" tex0 )
			if p == displayPassIdx do
				_w3dSetPassProp m "stage0display" sfx true
		)
		if tex1 != undefined and tex1 != "" do
		(
			_w3dSetPassProp m "stage1texenabled" sfx true
			try ( _w3dSetPassProp m "stage1texturemap" sfx (bitmaptex filename:tex1) )
			catch ( format "*** [buildMultiPassW3DMatl] bitmaptex failed for stage1 %\n" tex1 )
		)
	)
	format "    [buildMultiPassW3DMatl] OK matName=% nPasses=%\n" matName nPasses
	return m
)

