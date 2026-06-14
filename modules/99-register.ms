-- ===========================================================================
-- 99-register.ms  --  plugin launch surface (replaces the legacy auto-open tail)
-- AUTO-GENERATED w3dimporter.ms is built from modules/; edit modules, not output.
--
-- Legacy tail (lines 6486-6487 of v21.4) was:
--     W3DImporterInit.init()
--     createDialog rltMain menu:rltMainMenu      -- auto-opened on every eval
-- The dialog now opens ONLY from the W3D Tools > W3D Importer menu / macroScript.
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

-- Idempotent menu install: add a single "W3D Tools" main menu with one
-- "W3D Importer" item bound to the macroScript above. menuMan edits persist in
-- Max's saved menu config on exit; the duplicate guard makes re-evaluation safe.
fn w3dInstallMenu =
(
    if menuMan == undefined do return false
    if (menuMan.findMenu "W3D Tools") != undefined do return false   -- already installed
    local mainBar = menuMan.getMainMenuBar()
    local w3dMenu = menuMan.createMenu "W3D Tools"
    local item    = menuMan.createActionItem "W3D_Importer" "W3D Tools" -- macroName, category
    w3dMenu.addItem item -1
    local sub = menuMan.createSubMenuItem "W3D Tools" w3dMenu
    mainBar.addItem sub -1
    menuMan.updateMenuBar()
    true
)

try ( w3dInstallMenu() ) catch ( format "*** w3dInstallMenu failed: %\n" (getCurrentException()) )
