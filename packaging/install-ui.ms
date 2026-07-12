-- ===========================================================================
-- install-ui.ms -- W3D Importer .mzp installer window (v21.13)
--
-- The .mzp's mzp.run copies w3dimporter.ms into #userScripts and then drops
-- THIS script. It loads the importer (which performs its usual idempotent
-- menu + startup-stub install) and shows a small Install / Uninstall window,
-- so dropping the .mzp always gives visible feedback -- previously an
-- UPGRADE installed silently (the old success notice only appeared on a
-- genuine fresh install) and users could not tell whether anything happened.
--
-- Runs from the .mzp's temp extraction folder, alongside w3dimporter.ms --
-- so Install/Update can (re)copy the script into #userScripts even if the
-- mzp.run copy step failed or the user previously uninstalled.
-- Never evaluated at Max startup (the autoload stub fileIns w3dimporter.ms
-- directly), so this window only ever appears on an actual .mzp drop.
-- ===========================================================================

(
	-- The rollout must bind to the GLOBAL name: this script body is a local
	-- scope block (needed for `local` below), and a block-local rollout could
	-- neither be destroyed on a re-drop nor inspected from outside.
	global rltW3DInstaller

	-- Folder this script (and the packaged w3dimporter.ms) was extracted to.
	global w3dInstallerSrcDir = getFilenamePath (getSourceFileName())

	-- Tells 99-register to skip its own fresh-install messageBox; this window
	-- is the feedback now.
	global w3dInstallerActive = true

	local userCopy = (getDir #userScripts) + "\\w3dimporter.ms"

	-- Ensure the userScripts copy exists (mzp.run normally placed it already).
	if (not doesFileExist userCopy) and (doesFileExist (w3dInstallerSrcDir + "w3dimporter.ms")) do
		try ( copyFile (w3dInstallerSrcDir + "w3dimporter.ms") userCopy ) catch ()

	-- Load the importer: defines everything and runs the idempotent
	-- menu/startup install from 99-register.
	local loadOk = true
	try ( fileIn userCopy ) catch ( loadOk = false )

	try ( destroyDialog rltW3DInstaller ) catch ()

	rollout rltW3DInstaller "W3D Importer Setup"
	(
		label lblTitle  "W3D Importer"                                pos:[14,12]  width:330 align:#left
		label lblVer    ""                                            pos:[14,30]  width:330 align:#left
		label lblStatus ""                                            pos:[14,54]  width:330 align:#left
		label lblHint   "Open it from  W3D Tools > W3D Importer."     pos:[14,72]  width:330 align:#left
		button btnInstall   "Install / Update" pos:[24,100] width:150 height:28
		button btnUninstall "Uninstall"        pos:[186,100] width:150 height:28
		button btnClose     "Close"            pos:[105,136] width:150 height:26

		fn refreshStatus =
		(
			local installed = doesFileExist ((getDir #userScripts) + "\\w3dimporter.ms")
			lblVer.caption    = "Version: " + (try ( ::W3DImporterVersion ) catch ( "unknown" ))
			lblStatus.caption = if installed then "Status: installed." else "Status: not installed."
			lblHint.visible   = installed
		)

		on rltW3DInstaller open do refreshStatus()

		on btnInstall pressed do
		(
			local src = ::w3dInstallerSrcDir + "w3dimporter.ms"
			local dst = (getDir #userScripts) + "\\w3dimporter.ms"
			local ok = true
			if doesFileExist src then
			(
				try ( deleteFile dst ) catch ()
				try ( copyFile src dst ) catch ( ok = false )
			)
			if ok then
			(
				try ( fileIn dst ) catch ( ok = false )
				try ( w3dInstallMenu() ) catch ()
				try ( w3dInstallStartupLoader() ) catch ()
			)
			refreshStatus()
			lblStatus.caption = if ok then "Status: installed." else "Status: install FAILED -- see Listener."
		)

		on btnUninstall pressed do
		(
			if (queryBox "Remove the W3D Importer?\n\n(Removes the menu entry, startup loader and installed script.\nYour W3D-Importer.ini preferences are kept.)" title:"W3D Importer") do
			(
				local msg = try ( w3dUninstall() ) catch ( "uninstall FAILED: " + (getCurrentException()) )
				refreshStatus()
				lblStatus.caption = "Status: " + msg
				lblHint.visible = false
			)
		)

		on btnClose pressed do destroyDialog rltW3DInstaller
	)

	-- A rollout DEFINED in a local block always binds locally, even with the
	-- global declaration above -- publish it to the global slot explicitly so
	-- a re-drop can destroy the previous window and tools can inspect it.
	::rltW3DInstaller = rltW3DInstaller

	createDialog rltW3DInstaller 360 176

	if not loadOk do
		rltW3DInstaller.lblStatus.caption = "Status: load FAILED -- see Listener."
)
