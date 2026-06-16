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

-- Install, then (interactive sessions only) either prompt about a legacy entry
-- or show a one-time success notice on a genuine fresh install.
try
(
    local changed = w3dInstallMenu()
    if (menuMan != undefined) and (not (try (GetQuietMode()) catch (false))) do
    (
        local m = menuMan.findMenu "W3D Tools"
        local legacyPresent = (m != undefined) and (w3dMenuHasItem m "Import W3D")
        local handled = (w3dGetMigrationFlag()) != ""
        if (legacyPresent and not handled) then
            createDialog rltW3DMigrate 360 205
        else if changed do
            messageBox ("W3D Importer " + (::W3DImporterVersion) + " installed.\n\nOpen it from W3D Tools > W3D Importer.") title:"W3D Importer"
    )
)
catch ( format "*** w3dInstallMenu failed: %\n" (getCurrentException()) )
