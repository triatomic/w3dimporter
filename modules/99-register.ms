-- ===========================================================================
-- 99-register.ms  --  plugin launch surface (replaces the legacy auto-open tail)
-- AUTO-GENERATED w3dimporter.ms is built from modules/; edit modules, not output.
--
-- Legacy tail (lines 6486-6487 of v21.4) was:
--     W3DImporterInit.init()
--     createDialog rltMain menu:rltMainMenu      -- auto-opened on every eval
-- The dialog now opens ONLY from the W3D Tools > W3D Importer menu / macroScript.
--
-- This module also: (a) installs an idempotent "W3D Tools > W3D Importer" menu
-- item, (b) shows a one-time success notice on a genuine fresh install, and
-- (c) when it detects the pre-modular "Import W3D" entry (old macro ImportW3D,
-- category "W3D Importer/Processor Cabal"), prompts the user to remove it,
-- keep both, or decide later. All dialogs are suppressed in quiet/network-render
-- mode; the menu install itself still runs there (no UI). The keep/remove choice
-- is remembered in W3D-Importer.ini [Migration]LegacyEntry so it stops nagging.
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

-- --- menu helpers ----------------------------------------------------------
-- (use a local for each item; inline (m.getItem i).getTitle() mis-parses)
fn w3dMenuHasItem m title =
(
    for i = 1 to m.numItems() do
    (
        local it = m.getItem i
        if it.getTitle() == title do return true
    )
    false
)

-- Remove every item whose title matches (iterate backwards so positions stay
-- valid as we delete); returns the count removed.
fn w3dRemoveMenuItems m title =
(
    local removed = 0
    for i = m.numItems() to 1 by -1 do
    (
        local it = m.getItem i
        if it.getTitle() == title do ( m.removeItemByPosition i; removed += 1 )
    )
    removed
)

-- --- migration choice persistence (W3D-Importer.ini) -----------------------
fn w3dMigIni = (getDir #userScripts) + "\\W3D-Importer.ini"
fn w3dGetMigrationFlag = ( getINISetting (w3dMigIni()) "Migration" "LegacyEntry" )      -- "" when unset
fn w3dSetMigrationFlag v = ( setINISetting (w3dMigIni()) "Migration" "LegacyEntry" v )

-- --- opt-in autostart persistence (W3D-Importer.ini) -----------------------
-- The legacy v21.4 tail auto-opened the dialog on EVERY script evaluation, which
-- is wrong for a menu-installed plugin (it would pop up on every Max launch), so
-- it was dropped in favour of the W3D Tools > W3D Importer menu. Users who want
-- the old behaviour back can opt in -- via the Preferences checkbox, or
-- `w3dSetAutoStart true` in the Listener -- and the install block below honours
-- the flag, opening the dialog once on load (interactive sessions only).
fn w3dGetAutoStart = ( (getINISetting (w3dMigIni()) "Startup" "AutoOpen") == "1" )
fn w3dSetAutoStart onoff = ( setINISetting (w3dMigIni()) "Startup" "AutoOpen" (if onoff then "1" else "0") )

-- Remove the legacy "Import W3D" item + its orphan macro file, remember the
-- choice, and confirm. Called from the migration prompt's Remove button.
fn w3dDoLegacyRemove =
(
    local m = menuMan.findMenu "W3D Tools"
    local n = 0
    if m != undefined do n = w3dRemoveMenuItems m "Import W3D"
    if n > 0 do menuMan.updateMenuBar()
    -- delete the orphan macro file so it can't re-register next session
    local orphan = (getDir #userMacros) + "\\W3D Importer_Processor Cabal-ImportW3D.mcr"
    try ( if (doesFileExist orphan) do deleteFile orphan ) catch ()
    w3dSetMigrationFlag "removed"
    messageBox "Removed the duplicate.\n\nW3D Importer is ready under W3D Tools > W3D Importer." title:"W3D Importer"
)

-- --- migration prompt ------------------------------------------------------
-- Explicit pos:/width: layout (matches W3DPreferences / W3DNewProfile); labels
-- clip rather than wrap, so each is given room and the dialog is sized to fit.
rollout rltW3DMigrate "W3D Importer"
(
    label  l1 "A previous W3D Importer install was found:" pos:[14,14]  width:330 align:#left
    label  l2 "the legacy \"Import W3D\" menu entry."       pos:[14,32]  width:330 align:#left
    label  l3 "Both open the same dialog."                 pos:[14,56]  width:330 align:#left
    label  l4 "What would you like to do?"                 pos:[14,74]  width:330 align:#left
    button btnRemove "Remove duplicate (recommended)"      pos:[30,102] width:300 height:26
    button btnKeep   "Keep both"                           pos:[30,134] width:300 height:26
    button btnLater  "Decide later"                        pos:[30,166] width:300 height:26

    on btnRemove pressed do ( destroyDialog rltW3DMigrate; w3dDoLegacyRemove() )
    on btnKeep   pressed do ( w3dSetMigrationFlag "kept"; destroyDialog rltW3DMigrate )
    on btnLater  pressed do ( destroyDialog rltW3DMigrate )
)

-- Idempotent, structural menu install. Ensures the "W3D Tools" menu exists and
-- holds exactly one "W3D Importer" item bound to the macroScript above. Does NOT
-- touch the legacy entry (that goes through the prompt). The old guard bailed
-- whenever a "W3D Tools" menu already existed, which meant upgraders never got
-- the current item added -- doing it per-item fixes that too. menuMan edits
-- persist in Max's saved menu config on exit; safe to run on every evaluation.
-- Returns true when it actually created the menu or added the item.
fn w3dInstallMenu =
(
    if menuMan == undefined do return false
    local changed = false
    local w3dMenu = menuMan.findMenu "W3D Tools"
    if w3dMenu == undefined then
    (
        local mainBar = menuMan.getMainMenuBar()
        w3dMenu = menuMan.createMenu "W3D Tools"
        local sub = menuMan.createSubMenuItem "W3D Tools" w3dMenu
        mainBar.addItem sub -1
        changed = true
    )
    if not (w3dMenuHasItem w3dMenu "W3D Importer") then
    (
        local item = menuMan.createActionItem "W3D_Importer" "W3D Tools" -- macroName, category
        if item == undefined then
            format "*** w3dInstallMenu: createActionItem could not resolve macro W3D_Importer (category 'W3D Tools')\n"
        else
        (
            w3dMenu.addItem item -1
            changed = true
        )
    )
    if changed do menuMan.updateMenuBar()
    changed
)

-- Ensure the importer is re-evaluated on every Max launch. The .mzp copies
-- w3dimporter.ms into #userScripts, which Max does NOT auto-run on startup -- so
-- the macroScript and menu (which persist in Max's saved config) outlive the
-- rollout definitions they open, and the next session's menu click throws
-- "CreateDialog requires RolloutClass, got: undefined". Write a tiny startup stub
-- that fileIns this script. fileIn evaluates it in one shared scope (exactly like
-- the manual drag-drop that is known to work), which also sidesteps the
-- scripts/startup compile-before-assign scope trap the 00-header forward-decls
-- guard against. Idempotent (rewrites the same stub); only acts when w3dimporter.ms
-- actually lives in #userScripts, so running from the repo writes nothing. Forward
-- slashes keep the embedded path free of backslash-escaping when the stub parses.
fn w3dInstallStartupLoader =
(
    local src = (getDir #userScripts) + "\\w3dimporter.ms"
    if not (doesFileExist src) do return false   -- not the .mzp layout; nothing to anchor to
    local dst = (getDir #userStartupScripts) + "\\w3dimporter-autoload.ms"
    local srcFwd = substituteString src "\\" "/"
    local nl = "\r\n"
    local body = ""
    body += "-- Auto-generated by w3dimporter (99-register): re-evaluates the importer on every" + nl
    body += "-- Max launch. w3dimporter.ms is installed under #userScripts, which Max does not" + nl
    body += "-- auto-run; without this the W3D Tools menu/macro persist but the rollouts they" + nl
    body += "-- open do not, so the menu throws 'CreateDialog requires RolloutClass: undefined'." + nl
    body += "-- fileIn loads it in one shared scope, sidestepping the startup scope trap. Safe" + nl
    body += "-- to delete; it is recreated whenever the importer next evaluates." + nl
    body += "try ( fileIn \"" + srcFwd + "\" ) catch ( format \"*** w3dimporter autoload failed: %\\n\" (getCurrentException()) )" + nl
    local fw = createFile dst
    if fw == undefined do ( format "*** w3dInstallStartupLoader: could not write %\n" dst; return false )
    format "%" body to:fw
    close fw
    true
)

-- Full uninstall (v21.13). Called from the .mzp installer window
-- (packaging/install-ui.ms). Removes what the install created; deliberately
-- KEEPS W3D-Importer.ini (profiles/preferences survive a reinstall).
-- Returns a short human-readable summary for the installer's status line.
fn w3dUninstall =
(
	local parts = #()
	-- menu item, and the W3D Tools menu itself if that leaves it empty
	if menuMan != undefined do
	(
		local m = menuMan.findMenu "W3D Tools"
		if m != undefined do
		(
			local n = w3dRemoveMenuItems m "W3D Importer"
			if n > 0 do append parts "menu entry"
			if m.numItems() == 0 do
			(
				local mainBar = menuMan.getMainMenuBar()
				for i = mainBar.numItems() to 1 by -1 do
				(
					local it = mainBar.getItem i
					if it.getTitle() == "W3D Tools" do mainBar.removeItemByPosition i
				)
				try ( menuMan.unRegisterMenu m ) catch ()
				append parts "W3D Tools menu"
			)
			menuMan.updateMenuBar()
		)
	)
	-- startup autoload stub
	local stub = (getDir #userStartupScripts) + "\\w3dimporter-autoload.ms"
	if doesFileExist stub do ( try ( deleteFile stub; append parts "startup loader" ) catch () )
	-- installed script
	local scriptCopy = (getDir #userScripts) + "\\w3dimporter.ms"
	if doesFileExist scriptCopy do ( try ( deleteFile scriptCopy; append parts "script" ) catch () )
	-- macroScript file (category "W3D Tools", name W3D_Importer)
	local mcr = (getDir #userMacros) + "\\W3D Tools-W3D_Importer.mcr"
	if doesFileExist mcr do ( try ( deleteFile mcr; append parts "macro" ) catch () )
	if parts.count == 0 then "nothing to remove."
	else
	(
		local s = "removed "
		for i = 1 to parts.count do s += parts[i] + (if i < parts.count then ", " else ".")
		s + " Preferences kept."
	)
)

-- Install, then (interactive sessions only) either prompt about a legacy entry
-- or show a one-time success notice on a genuine fresh install.
try
(
    local changed = w3dInstallMenu()
    try ( w3dInstallStartupLoader() ) catch ( format "*** w3dInstallStartupLoader failed: %\n" (getCurrentException()) )
    if (menuMan != undefined) and (not (try (GetQuietMode()) catch (false))) do
    (
        local m = menuMan.findMenu "W3D Tools"
        local legacyPresent = (m != undefined) and (w3dMenuHasItem m "Import W3D")
        local handled = (w3dGetMigrationFlag()) != ""
        if (legacyPresent and not handled) then
            createDialog rltW3DMigrate 360 205
        -- fresh-install notice; skipped when the .mzp installer window is
        -- driving (install-ui.ms sets ::w3dInstallerActive) -- that window IS
        -- the feedback, and it also reports upgrades, which this never did
        else if changed and (::w3dInstallerActive != true) do
            messageBox ("W3D Importer " + (::W3DImporterVersion) + " installed.\n\nOpen it from W3D Tools > W3D Importer.") title:"W3D Importer"
    )
)
catch ( format "*** w3dInstallMenu failed: %\n" (getCurrentException()) )

-- Opt-in autostart (off by default; see w3dGetAutoStart above). Honour the flag
-- so an autoloaded install can reopen the dialog on launch for users who want
-- it, without forcing it on everyone. Interactive (non-quiet) sessions only.
try
(
    if (not (try (GetQuietMode()) catch (false))) and (w3dGetAutoStart()) do
    (
        try ( destroyDialog rltMain ) catch ()
        createDialog rltMain menu:rltMainMenu
    )
)
catch ( format "*** w3d autostart failed: %\n" (getCurrentException()) )
