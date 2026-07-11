-- w3d importer --
-- scripted by coolfile (his original called itself "version 3.1") --
-- msn: coolfile_cn@hotmail.com --
-- edited and augmented by NDC --
-- edited by tria --
-- credits: Seagle & Sloth --

-- Single source of truth for the importer version. Everything that displays
-- a version reads this: the rltMain window title (set in its open handler)
-- and the cfW3DImporter debug banner. Bump it with any non-trivial logic
-- change so the loaded copy is identifiable from the log.
global W3DImporterVersion = "v21.11"

-- Reload helper: a runtime error inside cfW3DImporter can leave the rollout's
-- event-handler thread stuck, making every button in the dialog unresponsive.
-- The dialog itself can't recover from this (its own handlers are dead), so
-- recovery has to come from outside. Type `w3di.reload()` into the MAXScript
-- Listener after a crash and it'll tear the dialog down and rebuild it from a
-- clean state. (`w3di` is a struct used as a namespace so we can write
-- `w3di.reload`. `w3d` itself is reserved by 3dsmax.)
struct W3DImporterNamespace ( fn reload =
(
	try ( destroyDialog rltMain ) catch ()
	createDialog rltMain menu:rltMainMenu
))
global w3di = W3DImporterNamespace()

-- Forward declarations: these globals are assigned further down the file
-- (W3DImporterInit at ~line 5341, rnPendingFile at ~line 6182) but are
-- referenced inside function/rollout bodies defined above those assignments
-- (cfW3DImporter at ~line 1853, rltMain handler at ~line 6177). Manual
-- `Evaluate All` from the editor tolerates this because the whole buffer
-- runs in one shared scope; but 3ds Max's scripts/startup/ autoload
-- compiles function bodies before the later assignments execute, capturing
-- the names as undefined locals. Forward-declaring them here binds the
-- global slots up front so both paths behave identically.
global W3DImporterInit
global rnPendingFile
-- rltMain is defined at ~line 5979, after rltRenegade (~line 4655) whose
-- doImport handler reads rltMain.ckb*.checked. Under scripts/startup/ that
-- read otherwise fails (undefined) and the try/catch around it silently
-- defaults every Advanced-tab option to false — making the imported file
-- appear correct but with all advanced options ignored.
global rltMain

-- reference table for adaptive delta motion channels --
deltaTable = #()

-- Cached W3DMaterial plugin availability. Probed once by `rltMain open`
-- (the rollout open handler) and, as a fallback, by cfW3DImporter on entry
-- when the rollout has not been opened (batch path). The two material
-- builder functions short-circuit when this is false, so a missing plugin
-- produces a clear "falling back to Standard materials" log line instead of
-- ~30 silent setProperty failures further down.
global w3dMatlAvailable = undefined

-- Duplicate-object name disambiguation.
-- The W3D exporter requires every Max node to have a unique name and aborts
-- with "duplicate names found" otherwise (w3dexport.cpp:2128). Renegade's
-- convention for instanced/placeholder objects is a trailing "~NN": the
-- exporter strips everything from the first '~' onward (CopyW3DName /
-- ProxyExportTaskClass, w3dexport.cpp:9761) and re-references the base name, so
-- "GDI SPAWNER", "GDI SPAWNER~01", "GDI SPAWNER~02" all round-trip back to the
-- single render object "GDI SPAWNER". We keep the first occurrence bare and
-- give each subsequent duplicate ~01, ~02, ... (2-digit minimum, growing).
-- Comparison is case-insensitive because the exporter upper-cases W3D names,
-- and the check is against the live scene so it also avoids colliding with
-- nodes from a previous import in the same session.
fn w3dUniqueNodeName baseName =
(
	if (getNodeByName baseName exact:true ignoreCase:true) == undefined then baseName
	else
	(
		local result = baseName
		local n = 1
		do
		(
			result = baseName + "~" + (formattedPrint n format:"02d")
			n += 1
		)
		while (getNodeByName result exact:true ignoreCase:true) != undefined
		result
	)
)

