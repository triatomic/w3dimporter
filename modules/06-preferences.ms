-- ============================================================================
-- W3D Importer Preferences (ported from w3d-importer-1.16b.ms, importer-only)
-- Profile-based pivot/proxy/aggregate/dazzle visualisation settings, persisted
-- to (getDir #userScripts)\W3D-Importer.ini. Open via Edit > Preferences on
-- the importer dialog's menu bar.
--
-- Differences from 1.16b's prefs:
--   - No "CreateMeshesBones" (export-side concern, not the importer)
--   - No "Always use one profile" / Char / Vehicle profile assignment
--     (export-side; v20 is import-only)
--   - INI lives in user-scripts dir, not next to the script
--   - BoneSize/ProxySize/AggregateSize/DazzleSize: 0 = auto-fit from bbox
-- ============================================================================

struct W3D_Importer_Init
(
	ImporterInitFile = (getDir #userScripts) + "\\W3D-Importer.ini",
	Initialized = false,
	CurrentProfile,
	W3DPaths = #(),
	ProfilesList = #(),
	-- Per-profile values, packed: 12 fields per profile.
	-- index = (12 * (profile - 1)) + fieldOffset, fieldOffsets:
	--   1=BoneShape 2=BoneSize 3=BoneColor
	--   4=ProxyShape 5=ProxySize 6=ProxyColor
	--   7=AggregateShape 8=AggregateSize 9=AggregateColor
	--  10=DazzleShape 11=DazzleSize 12=DazzleColor
	-- Shape codes: 1=Box 2=Sphere 3=Cylinder
	UserProfiles = #(),
	ProfilesDefaults = #(),

	fn ColorToString val =
	(
		val = val as color
		((val.r as integer) as string) + "," + ((val.g as integer) as string) + "," + ((val.b as integer) as string)
	),

	fn valToShape val =
	(
		case val of
		(
			1: "box"
			2: "sphere"
			3: "cylinder"
			default: "box"
		)
	),

	fn fieldOffset name =
	(
		case name of
		(
			"BoneShape": 1
			"BoneSize": 2
			"BoneColor": 3
			"ProxyShape": 4
			"ProxySize": 5
			"ProxyColor": 6
			"AggregateShape": 7
			"AggregateSize": 8
			"AggregateColor": 9
			"DazzleShape": 10
			"DazzleSize": 11
			"DazzleColor": 12
			default: 0
		)
	),

	fn getProfileValue profile fieldName =
	(
		if profile == undefined or profile < 1 or profile > ProfilesList.count do return undefined
		local fOff = fieldOffset fieldName
		if fOff == 0 do return undefined
		UserProfiles[(12 * (profile - 1)) + fOff]
	),

	-- (getActive lives at the END of the struct: it calls init(), and MAXScript
	-- struct methods can only reference members declared before them -- in its
	-- old position here, init() resolved to an undefined global.)

	-- Default values for the three baseline profiles, mirroring 1.16b's
	-- ProfilesDefaults but stripped of CreateMeshesBones (export-side).
	fn getProfileDefaults profile fieldName:"all" =
	(
		if profile < 1 or profile > 3 do profile = 1
		local index = (12 * (profile - 1)) + 1
		if fieldName == "all" then
		(
			local out = #()
			for i = 0 to 11 do append out ProfilesDefaults[index + i]
			return out
		)
		local fOff = fieldOffset fieldName
		if fOff == 0 do return undefined
		ProfilesDefaults[index + fOff - 1]
	),

	-- Build a scene node for the given shape code. Used by the importer for
	-- proxies and aggregates so the user's profile choice takes effect.
	-- Shape: 1=Box (point helper box), 2=Sphere, 3=Cylinder (point helper cross).
	-- Bones use a separate code path because Max Bone has no `size` arg.
	fn makeShape shapeCode nodeName sz wcol =
	(
		case shapeCode of
		(
			2: ( sphere name:nodeName radius:sz segs:6 wirecolor:wcol )
			3: ( point name:nodeName size:sz cross:true box:false axisTripod:false centermarker:false wirecolor:wcol )
			default: ( point name:nodeName size:sz cross:false box:true axisTripod:false centermarker:false wirecolor:wcol )
		)
	),

	-- Persist all profiles + the active selection back to the INI file.
	-- Uses setINISetting (per-key) which is more reliable than rewriting the
	-- whole file ourselves and avoids the GamePacks/edit-file dance 1.16b did.
	fn saveToFile =
	(
		setINISetting ImporterInitFile "W3D_Importer" "CurrentProfile" (CurrentProfile as string)
		for i = 1 to 5 do
			if W3DPaths[i] != undefined do setINISetting ImporterInitFile "W3D_Importer" ("W3DPath_" + i as string) W3DPaths[i]
		-- Clear and rewrite the profiles list (so a deleted profile vanishes).
		for i = 1 to 20 do delIniSetting ImporterInitFile "Profiles_List" (i as string)
		for i = 1 to ProfilesList.count do
			setINISetting ImporterInitFile "Profiles_List" (i as string) ProfilesList[i]
		-- Per-profile sections.
		for i = 1 to ProfilesList.count do
		(
			local idx = (12 * (i - 1))
			local sect = ProfilesList[i]
			setINISetting ImporterInitFile sect "BoneShape"      (valToShape UserProfiles[idx + 1])
			setINISetting ImporterInitFile sect "BoneSize"       (UserProfiles[idx + 2] as string)
			setINISetting ImporterInitFile sect "BoneColor"      (ColorToString UserProfiles[idx + 3])
			setINISetting ImporterInitFile sect "ProxyShape"     (valToShape UserProfiles[idx + 4])
			setINISetting ImporterInitFile sect "ProxySize"      (UserProfiles[idx + 5] as string)
			setINISetting ImporterInitFile sect "ProxyColor"     (ColorToString UserProfiles[idx + 6])
			setINISetting ImporterInitFile sect "AggregateShape" (valToShape UserProfiles[idx + 7])
			setINISetting ImporterInitFile sect "AggregateSize"  (UserProfiles[idx + 8] as string)
			setINISetting ImporterInitFile sect "AggregateColor" (ColorToString UserProfiles[idx + 9])
			setINISetting ImporterInitFile sect "DazzleShape"    (valToShape UserProfiles[idx + 10])
			setINISetting ImporterInitFile sect "DazzleSize"     (UserProfiles[idx + 11] as string)
			setINISetting ImporterInitFile sect "DazzleColor"    (ColorToString UserProfiles[idx + 12])
		)
	),

	fn init =
	(
		if Initialized do return false

		-- Defaults: same baseline values as 1.16b for the three reference profiles
		-- (Default / Default Characters / Default Vehicles), minus the trailing
		-- CreateMeshesBones field which v20 doesn't use.
		ProfilesDefaults = #( \
			1, 0.0, (color 0 0 255),   1, 1.0, (color 255 255 0),   1, 1.0, (color 255 155 247), 2, 1.0, (color 255 0 0), \
			1, 0.1, (color 0 0 255),   1, 0.2, (color 255 255 0),   1, 0.2, (color 255 155 247), 2, 0.3, (color 255 0 0), \
			1, 0.2, (color 0 0 255),   1, 1.0, (color 255 255 0),   1, 0.3, (color 255 155 247), 2, 0.5, (color 255 0 0))

		local Shapes = #("box", "sphere", "cylinder")
		local sectionFields = #( \
			#("BoneShape",      "shape"), #("BoneSize",      "size"), #("BoneColor",      "color"), \
			#("ProxyShape",     "shape"), #("ProxySize",     "size"), #("ProxyColor",     "color"), \
			#("AggregateShape", "shape"), #("AggregateSize", "size"), #("AggregateColor", "color"), \
			#("DazzleShape",    "shape"), #("DazzleSize",    "size"), #("DazzleColor",    "color"))

		CurrentProfile = (getINISetting ImporterInitFile "W3D_Importer" "CurrentProfile") as integer
		if CurrentProfile == 0 or CurrentProfile == undefined do CurrentProfile = 1

		W3DPaths = #()
		for i = 1 to 5 do
		(
			local p = getINISetting ImporterInitFile "W3D_Importer" ("W3DPath_" + i as string)
			if p != "" do append W3DPaths p
		)
		if W3DPaths.count == 0 do W3DPaths[1] = (getDir #maxroot)

		-- Profiles list: read indices 1..20 until we hit a gap.
		ProfilesList = #()
		local pid = 1
		while pid <= 20 do
		(
			local val = getINISetting ImporterInitFile "Profiles_List" (pid as string)
			if val == "" do exit
			ProfilesList[pid] = val
			pid += 1
		)
		if ProfilesList[1] == undefined do ProfilesList[1] = "Default"
		if ProfilesList[2] == undefined do ProfilesList[2] = "Default Characters"
		if ProfilesList[3] == undefined do ProfilesList[3] = "Default Vehicles"

		-- Pull values for each profile, falling back to defaults when the INI
		-- doesn't have a key (or the profile is one we just created on first run).
		UserProfiles = #()
		for i = 1 to ProfilesList.count do
		(
			local idx = (12 * (i - 1))
			for f = 1 to 12 do
			(
				local fname = sectionFields[f][1]
				local ftype = sectionFields[f][2]
				local raw = getINISetting ImporterInitFile ProfilesList[i] fname
				local resolved
				if raw == "" then
				(
					if i <= 3 then resolved = getProfileDefaults i fieldName:fname
					else            resolved = getProfileDefaults 1 fieldName:fname
				)
				else
				(
					case ftype of
					(
						"shape": resolved = (findItem Shapes raw)
						"size":  resolved = (raw as float)
						"color":
						(
							local parts = filterString raw ","
							if parts.count >= 3 then
								resolved = color (parts[1] as float) (parts[2] as float) (parts[3] as float)
							else
								resolved = (if i <= 3 then getProfileDefaults i fieldName:fname else getProfileDefaults 1 fieldName:fname)
						)
					)
				)
				UserProfiles[idx + f] = resolved
			)
		)

		if CurrentProfile > ProfilesList.count do CurrentProfile = 1

		Initialized = true
	),

	-- Convenience: read a field from the active profile. Defined after init()
	-- on purpose -- see the note at its former location above.
	fn getActive fieldName =
	(
		if not Initialized do init()
		getProfileValue CurrentProfile fieldName
	)
)

global W3DImporterInit = W3D_Importer_Init()

rollout W3DNewProfile "New Profile" width:323 height:85
(
	local NewName
	edittext ProfileName "Profile Name : " pos:[27,20] fieldWidth:195 text:"New Profile" align:#left
	button OKButton "OK" pos:[159,60] width:75
	button CancelButton "Cancel" pos:[240,60] width:75

	fn Open XYPos =
	(
		NewName = undefined
		createDialog W3DNewProfile style:#(#style_titlebar, #style_sysmenu) modal:true
	)

	on OKButton pressed do
	(
		if ProfileName.text.count > 0 do
		(
			NewName = ProfileName.text
			destroyDialog W3DNewProfile
		)
	)
	on CancelButton pressed do destroyDialog W3DNewProfile
)

rollout W3DPreferences "W3D Importer Preferences" width:418 height:425
(
	local ProfilesSettings = #()

	groupBox Settings "Settings:" width:410 height:307 pos:[4,9]

	label ProfileLabel "Profile : " pos:[14,33] align:#left
	dropdownlist ProfileCombo pos:[56,30] width:196 align:#left
	button NewButton "New" pos:[257,30] width:70
	button DeleteButton "Delete" pos:[333,30] width:71

	label bShapeLabel "Bones Shape :" pos:[18,70] align:#left
	dropdownlist bShapeCombo pos:[95,67] width:81 height:5 align:#left tooltip:"Pick 'Bone' if you plan to use Auto-Bind > max skin. Geometry / Point Helper pivots aren't recognised as Max bones, so max-skin will skip them and skinning will fail."
	edittext bSizeEdit "Bones Size : " pos:[29,100] fieldWidth:80 align:#left
	colorpicker bColorPick "Bones Color : " pos:[25,127] fieldWidth:80 title:"Bones Color" align:#left

	label pShapeLabel "Proxies Shape :" pos:[14,169] align:#left
	dropdownlist pShapeCombo pos:[95,166] width:81 height:5 align:#left
	edittext pSizeEdit "Proxies Size : " pos:[25,199] fieldWidth:80 align:#left
	colorpicker pColorPick "Proxies Color : " pos:[21,226] fieldWidth:80 title:"Proxies Color" align:#left

	label aShapeLabel "Aggregates Shape : " pos:[223,70] align:#left
	dropdownlist aShapeCombo pos:[324,67] width:81 height:5 align:#left
	edittext aSizeEdit "Aggregates Size : " pos:[234,100] fieldWidth:80 align:#left
	colorpicker aColorPick "Aggregates Color : " pos:[230,127] fieldWidth:80 title:"Aggregates Color" align:#left

	label dShapeLabel "Dazzles Shape : " pos:[240,169] align:#left
	dropdownlist dShapeCombo pos:[324,166] width:81 height:5 align:#left
	edittext dSizeEdit "Dazzles Size : " pos:[251,199] fieldWidth:80 align:#left
	colorpicker dColorPick "Dazzles Color : " pos:[247,226] fieldWidth:80 title:"Dazzles Color" align:#left

	label sizeNote "Note: Size 0 = auto-fit from imported bbox." pos:[18,270] width:380
	button RestoreButton "Restore" pos:[329,290] width:75

	groupBox W3DPathGroup "Default W3D Path:" width:410 height:57 pos:[4,326]
	dropdownlist W3DPathCombo pos:[14,347] width:310 align:#left
	button BrowseButton "Browse" pos:[329,347] width:75

	button OkButton "OK" pos:[173,395] width:75
	button CancelButton "Cancel" pos:[254,395] width:75
	button ApplyButton "Apply" pos:[335,395] width:75

	fn UpdateProfile sel restore:false isNew:false fromInit:false =
	(
		local index = (12 * (sel - 1))

		if sel <= 3 then
		(
			DeleteButton.enabled = false
			RestoreButton.enabled = true
		)
		else
		(
			DeleteButton.enabled = true
			RestoreButton.enabled = false
		)

		if isNew do
		(
			W3DNewProfile.Open (getDialogPos W3DPreferences)
			local newName = W3DNewProfile.NewName
			if newName != undefined then
			(
				local tmpProfiles = ProfileCombo.items
				-- Disambiguate duplicate names with (n) suffix.
				if findItem tmpProfiles newName > 0 do
				(
					local nameIndex = 2
					local nameIndexArray = #()
					for i = 1 to tmpProfiles.count do
					(
						local s = tmpProfiles[i]
						if matchPattern s pattern:(newName + "(*)") do
						(
							nameIndex = (trimRight (trimLeft s (newName + "(")) ")") as integer
							append nameIndexArray nameIndex
						)
					)
					for i = 0 to nameIndexArray.count do
					(
						if findItem nameIndexArray (i + 2) == 0 then
						(
							nameIndex = i + 2
							exit
						)
					)
					newName = newName + "(" + (nameIndex as string) + ")"
				)
				append tmpProfiles newName
				ProfileCombo.items = tmpProfiles
				ProfileCombo.selection = tmpProfiles.count
				sel = tmpProfiles.count
				index = (12 * (sel - 1))
				-- New profile inherits Default values.
				restore = true
			)
			else return false
		)

		if restore do
		(
			-- For built-in profiles 1..3, restore from their own defaults; for
			-- user-created profiles, fall back to Default's defaults.
			local srcIdx = if sel <= 3 then sel else 1
			local d = W3DImporterInit.getProfileDefaults srcIdx
			for i = 0 to 11 do ProfilesSettings[index + i + 1] = d[i + 1]
		)

		bShapeCombo.selection = ProfilesSettings[index + 1]
		bSizeEdit.text  = ProfilesSettings[index + 2] as string
		bColorPick.color = ProfilesSettings[index + 3]
		pShapeCombo.selection = ProfilesSettings[index + 4]
		pSizeEdit.text  = ProfilesSettings[index + 5] as string
		pColorPick.color = ProfilesSettings[index + 6]
		aShapeCombo.selection = ProfilesSettings[index + 7]
		aSizeEdit.text  = ProfilesSettings[index + 8] as string
		aColorPick.color = ProfilesSettings[index + 9]
		dShapeCombo.selection = ProfilesSettings[index + 10]
		dSizeEdit.text  = ProfilesSettings[index + 11] as string
		dColorPick.color = ProfilesSettings[index + 12]

		ApplyButton.enabled = not fromInit
	)

	fn UpdateSettings field val =
	(
		local index = (12 * (ProfileCombo.selection - 1))
		case field of
		(
			"BoneShape":      ProfilesSettings[index + 1]  = val
			"BoneSize":       ProfilesSettings[index + 2]  = val as float
			"BoneColor":      ProfilesSettings[index + 3]  = val
			"ProxyShape":     ProfilesSettings[index + 4]  = val
			"ProxySize":      ProfilesSettings[index + 5]  = val as float
			"ProxyColor":     ProfilesSettings[index + 6]  = val
			"AggregateShape": ProfilesSettings[index + 7]  = val
			"AggregateSize":  ProfilesSettings[index + 8]  = val as float
			"AggregateColor": ProfilesSettings[index + 9]  = val
			"DazzleShape":    ProfilesSettings[index + 10] = val
			"DazzleSize":     ProfilesSettings[index + 11] = val as float
			"DazzleColor":    ProfilesSettings[index + 12] = val
		)
		ApplyButton.enabled = true
	)

	fn UpdateW3DPaths val =
	(
		local tmpPaths = W3DPathCombo.items
		local pathCount = tmpPaths.count
		local currentPath = tmpPaths[val]
		if pathCount > 1 do
		(
			while pathCount > 1 do
			(
				if pathCount <= val do tmpPaths[pathCount] = tmpPaths[pathCount - 1]
				pathCount -= 1
			)
			tmpPaths[1] = currentPath
			W3DPathCombo.items = tmpPaths
			W3DPathCombo.selection = 1
		)
		ApplyButton.enabled = true
	)

	fn ApplyChanges =
	(
		W3DImporterInit.ProfilesList = #()
		join W3DImporterInit.ProfilesList ProfileCombo.items
		W3DImporterInit.UserProfiles = #()
		join W3DImporterInit.UserProfiles ProfilesSettings
		W3DImporterInit.W3DPaths = #()
		join W3DImporterInit.W3DPaths W3DPathCombo.items
		W3DImporterInit.CurrentProfile = ProfileCombo.selection
		W3DImporterInit.saveToFile()
		ApplyButton.enabled = false
	)

	fn doInit =
	(
		if not W3DImporterInit.Initialized do W3DImporterInit.init()
		-- Display labels: indices still map to 1=Box, 2=Sphere, 3=Cylinder in the
		-- INI's shape vocabulary (so 1.16b INI files stay readable). Only the
		-- user-facing names changed.
		local Shapes = #("Bone", "Geometry", "Point Helper")
		ProfilesSettings = #()
		join ProfilesSettings W3DImporterInit.UserProfiles

		ProfileCombo.items = #()
		local pl = #()
		join pl W3DImporterInit.ProfilesList
		ProfileCombo.items = pl
		ProfileCombo.selection = W3DImporterInit.CurrentProfile

		bShapeCombo.items = Shapes
		pShapeCombo.items = Shapes
		aShapeCombo.items = Shapes
		dShapeCombo.items = Shapes

		W3DPathCombo.items = (local p = #(); join p W3DImporterInit.W3DPaths; p)

		UpdateProfile ProfileCombo.selection fromInit:true
	)

	fn Open XYPos =
	(
		createDialog W3DPreferences style:#(#style_titlebar, #style_sysmenu)
		doInit()
		setFocus W3DPreferences
	)

	on ProfileCombo selected val do UpdateProfile val
	on NewButton pressed do
	(
		if ProfileCombo.items.count < 20 then UpdateProfile (ProfileCombo.items.count + 1) isNew:true
		else messageBox "Profile limit (20) reached. Delete unused profiles first." title:"Profiles Limit" beep:true
	)
	on DeleteButton pressed do
	(
		local profileCount = ProfileCombo.items.count
		local delProfile = ProfileCombo.selection
		if delProfile <= 3 do return false   -- built-ins are protected

		local tmpSettings = #()
		local tmpProfiles = #()
		for i = 1 to profileCount do
		(
			if i != delProfile do
			(
				local idx = (12 * (i - 1))
				for j = 1 to 12 do append tmpSettings ProfilesSettings[idx + j]
				append tmpProfiles ProfileCombo.items[i]
			)
		)
		ProfilesSettings = tmpSettings
		ProfileCombo.items = tmpProfiles
		if delProfile > tmpProfiles.count do ProfileCombo.selection = tmpProfiles.count
		UpdateProfile ProfileCombo.selection
		ApplyButton.enabled = true
	)

	on bShapeCombo selected val do UpdateSettings "BoneShape" val
	on bSizeEdit changed val do UpdateSettings "BoneSize" val
	on bColorPick changed val do UpdateSettings "BoneColor" val
	on pShapeCombo selected val do UpdateSettings "ProxyShape" val
	on pSizeEdit changed val do UpdateSettings "ProxySize" val
	on pColorPick changed val do UpdateSettings "ProxyColor" val
	on aShapeCombo selected val do UpdateSettings "AggregateShape" val
	on aSizeEdit changed val do UpdateSettings "AggregateSize" val
	on aColorPick changed val do UpdateSettings "AggregateColor" val
	on dShapeCombo selected val do UpdateSettings "DazzleShape" val
	on dSizeEdit changed val do UpdateSettings "DazzleSize" val
	on dColorPick changed val do UpdateSettings "DazzleColor" val

	on RestoreButton pressed do UpdateProfile ProfileCombo.selection restore:true

	on W3DPathCombo selected val do UpdateW3DPaths val
	on BrowseButton pressed do
	(
		local picked = getSavePath caption:"Choose Default W3D Folder"
		if picked != undefined do
		(
			local existing = findItem W3DPathCombo.items picked
			if existing > 0 then UpdateW3DPaths existing
			else
			(
				local tmpPaths = W3DPathCombo.items
				local pathCount = tmpPaths.count + 1
				while pathCount > 1 do
				(
					if pathCount <= 5 do tmpPaths[pathCount] = tmpPaths[pathCount - 1]
					pathCount -= 1
				)
				tmpPaths[1] = picked
				W3DPathCombo.items = tmpPaths
				W3DPathCombo.selection = 1
				ApplyButton.enabled = true
			)
		)
	)

	on OkButton     pressed do ( if ApplyButton.enabled do ApplyChanges(); destroyDialog W3DPreferences )
	on CancelButton pressed do destroyDialog W3DPreferences
	on ApplyButton  pressed do ApplyChanges()
)

