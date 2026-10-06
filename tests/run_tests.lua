--[[
  run_tests.lua -- unit tests for the pure logic in InsertRandomSFX.lua.

  These tests never call REAPER. The script exposes its pure helpers when it
  is loaded with _G.SFX_LOAD_AS_MODULE set (see the MODULE HOOK section of the
  script).

  Run from the repository root with any Lua 5.3+ interpreter:

      lua tests/run_tests.lua

  REAPER itself ships Lua 5.4, so the syntax used here is safe there too.
]]

_G.SFX_LOAD_AS_MODULE = true

-- Locate the script relative to this test file (or the current directory).
local function locateScript()
    local invoked = (arg and arg[0]) or "tests/run_tests.lua"
    local root = invoked:gsub("[\\/]tests[\\/]run_tests%.lua$", "")
    if root == invoked then root = "." end
    return root .. "/scripts/InsertRandomSFX.lua"
end

local scriptPath = locateScript()
local chunk, loadErr = loadfile(scriptPath)
if not chunk then
    io.stderr:write("Could not load " .. scriptPath .. ": " .. tostring(loadErr) .. "\n")
    os.exit(1)
end
local Sfx = chunk()

-- ---------------------------------------------------------------------
-- Tiny test harness
-- ---------------------------------------------------------------------

local passed, failed = 0, 0
local function check(name, condition)
    if condition then
        passed = passed + 1
        print("PASS  " .. name)
    else
        failed = failed + 1
        print("FAIL  " .. name)
    end
end

local function equals(name, actual, expected)
    local ok = actual == expected
    if not ok then
        print(string.format("      expected %s, got %s",
            tostring(expected), tostring(actual)))
    end
    check(name, ok)
end

-- ---------------------------------------------------------------------
-- getExtension
-- ---------------------------------------------------------------------

equals("getExtension: wav", Sfx.getExtension("kick.wav"), "wav")
equals("getExtension: case-folded", Sfx.getExtension("KICK.WAV"), "wav")
equals("getExtension: aiff", Sfx.getExtension("sweep.aiff"), "aiff")
equals("getExtension: no extension", Sfx.getExtension("noextension"), "")
equals("getExtension: trailing dot", Sfx.getExtension("tricky."), "")
equals("getExtension: path with slash", Sfx.getExtension("dir/sub/boom.flac"), "flac")
equals("getExtension: windows path", Sfx.getExtension("C:\\x\\y.ogg"), "ogg")
equals("getExtension: non-string", Sfx.getExtension(nil), "")

-- ---------------------------------------------------------------------
-- isSupportedAudioFile
-- ---------------------------------------------------------------------

for _, ext in ipairs({ "wav", "aif", "aiff", "flac", "ogg", "mp3" }) do
    check("supported: ." .. ext, Sfx.isSupportedAudioFile("file." .. ext))
    check("supported: ." .. ext:upper(), Sfx.isSupportedAudioFile("file." .. ext:upper()))
end
check("unsupported: .txt", not Sfx.isSupportedAudioFile("readme.txt"))
check("unsupported: no extension", not Sfx.isSupportedAudioFile("transition"))
check("unsupported: .mp4", not Sfx.isSupportedAudioFile("clip.mp4"))
check("unsupported: .wav.bak", not Sfx.isSupportedAudioFile("kick.wav.bak"))

-- ---------------------------------------------------------------------
-- joinPath
-- ---------------------------------------------------------------------

equals("joinPath: no trailing slash", Sfx.joinPath("C:/a", "b.wav"), "C:/a/b.wav")
equals("joinPath: forward trailing slash", Sfx.joinPath("C:/a/", "b.wav"), "C:/a/b.wav")
equals("joinPath: backslash path", Sfx.joinPath("C:\\a\\", "b.wav"), "C:\\a\\b.wav")

-- ---------------------------------------------------------------------
-- resolveCategoryFromTrackName (Phase 1: five categories)
-- ---------------------------------------------------------------------

local CATEGORIES = { "transition", "gun", "impact", "whoosh", "footstep" }

-- Every configured category resolves from a track name, in any case.
for _, category in ipairs(CATEGORIES) do
    equals("resolve: " .. category .. " (lower)", Sfx.resolveCategoryFromTrackName(category), category)
    equals("resolve: " .. category .. " (UPPER)", Sfx.resolveCategoryFromTrackName(category:upper()), category)
end

equals("resolve: Title case", Sfx.resolveCategoryFromTrackName("Transition"), "transition")
equals("resolve: mixed case", Sfx.resolveCategoryFromTrackName("WhOoSh"), "whoosh")
equals("resolve: surrounding spaces", Sfx.resolveCategoryFromTrackName("  transition  "), "transition")

-- Unknown categories must be rejected (exact match only).
equals("resolve: unknown category", Sfx.resolveCategoryFromTrackName("dialogue"), nil)
equals("resolve: no partial match", Sfx.resolveCategoryFromTrackName("trans"), nil)
equals("resolve: no superstring match", Sfx.resolveCategoryFromTrackName("transition2"), nil)
equals("resolve: empty string", Sfx.resolveCategoryFromTrackName(""), nil)
equals("resolve: nil", Sfx.resolveCategoryFromTrackName(nil), nil)

-- ---------------------------------------------------------------------
-- collectSupportedAudioFiles (REAPER enumerator replaced by a fake)
-- ---------------------------------------------------------------------

-- Only files are returned by reaper.EnumerateFiles, but the fake includes a
-- directory-like entry and various unsupported files to prove filtering.
local fakeListing = {
    "boom.wav",
    "reverse.wav",
    "sweep.aiff",
    "note.txt",
    "subfolder",
    "readme.md",
    "hit.FLAC",
}

local function fakeEnumerate(list)
    return function(_, index)
        return list[index + 1]
    end
end

local files = Sfx.collectSupportedAudioFiles("C:/SFX/Transitions", fakeEnumerate(fakeListing))
equals("collect: count", #files, 4)
equals("collect: first (sorted)", files[1], "C:/SFX/Transitions/boom.wav")
equals("collect: uppercase ext kept", files[2], "C:/SFX/Transitions/hit.FLAC")
equals("collect: sorted deterministically", table.concat(files, ","),
    "C:/SFX/Transitions/boom.wav,C:/SFX/Transitions/hit.FLAC,"
    .. "C:/SFX/Transitions/reverse.wav,C:/SFX/Transitions/sweep.aiff")

local filesAgain = Sfx.collectSupportedAudioFiles("C:/SFX/Transitions", fakeEnumerate(fakeListing))
equals("collect: same order on repeat", table.concat(filesAgain, ","), table.concat(files, ","))

local none = Sfx.collectSupportedAudioFiles("C:/empty", fakeEnumerate({ "x.txt", "y.png", "z" }))
equals("collect: nothing supported", #none, 0)

-- Folder/file validation works for any configured category folder, not just
-- the transition one.
local gunFiles = Sfx.collectSupportedAudioFiles("D:/SFX/Guns",
    fakeEnumerate({ "shot1.wav", "shot2.wav", "notes.txt", "cover.png" }))
equals("collect: gun folder filters unsupported", #gunFiles, 2)
equals("collect: gun path joined", gunFiles[1], "D:/SFX/Guns/shot1.wav")

-- ---------------------------------------------------------------------
-- directoryExists (REAPER enumerators replaced by fakes)
-- ---------------------------------------------------------------------

-- Returns a fake EnumerateSubdirectories over `list`.
local function fakeSubdirs(list)
    return function(_, index)
        if index == -1 then return nil end -- cache invalidation call
        return list[index + 1]
    end
end

local function fakeNoFiles()
    return function(_, _) return nil end
end

check("directoryExists: non-empty folder",
    Sfx.directoryExists("C:/SFX/Transitions",
        function(_, i) return i == 0 and "boom.wav" or nil end,
        fakeSubdirs({})))

check("directoryExists: empty but existing",
    Sfx.directoryExists("C:/SFX/Transitions",
        fakeNoFiles(),
        fakeSubdirs({ "Other", "Transitions" })))

check("directoryExists: case-insensitive parent lookup",
    Sfx.directoryExists("C:/SFX/Transitions",
        fakeNoFiles(),
        fakeSubdirs({ "transitions" })))

check("directoryExists: missing folder",
    not Sfx.directoryExists("C:/SFX/Transitions",
        fakeNoFiles(),
        fakeSubdirs({ "Other", "Impacts" })))

check("directoryExists: missing parent",
    not Sfx.directoryExists("C:/SFX/Transitions",
        fakeNoFiles(),
        fakeSubdirs({})))

check("directoryExists: backslash + trailing slash",
    Sfx.directoryExists("C:\\SFX\\Transitions\\",
        fakeNoFiles(),
        fakeSubdirs({ "Transitions" })))

check("directoryExists: empty path",
    not Sfx.directoryExists(""))

-- ---------------------------------------------------------------------
-- Presentation helpers
-- ---------------------------------------------------------------------

equals("capitalize: transition", Sfx.capitalize("transition"), "Transition")
equals("capitalize: gun", Sfx.capitalize("gun"), "Gun")
equals("capitalize: already capitalized", Sfx.capitalize("Whoosh"), "Whoosh")

equals("supportedFormatList", Sfx.supportedFormatList(), ".aif, .aiff, .flac, .mp3, .ogg, .wav")

local categories = Sfx.configuredCategories()
equals("configuredCategories: count", #categories, 5)
equals("configuredCategories: sorted", table.concat(categories, ","),
    "footstep,gun,impact,transition,whoosh")

-- Every configured category must point at a non-empty string folder.
for _, category in ipairs(CATEGORIES) do
    local folder = Sfx.CONFIG.category_folders[category]
    check("config: " .. category .. " has a folder",
        type(folder) == "string" and folder ~= "")
end

-- ---------------------------------------------------------------------
-- canonicalizePath / pathsEqual
-- ---------------------------------------------------------------------

equals("canonicalizePath: backslashes", Sfx.canonicalizePath("D:\\SFX\\Guns"), "D:/SFX/Guns")
equals("canonicalizePath: trailing slash", Sfx.canonicalizePath("D:/SFX/Guns/"), "D:/SFX/Guns")
equals("canonicalizePath: duplicate slashes", Sfx.canonicalizePath("D:/SFX//Guns"), "D:/SFX/Guns")
equals("canonicalizePath: drive root kept", Sfx.canonicalizePath("C:/"), "C:/")
equals("canonicalizePath: posix root kept", Sfx.canonicalizePath("/"), "/")
equals("canonicalizePath: empty", Sfx.canonicalizePath(""), "")
equals("canonicalizePath: non-string", Sfx.canonicalizePath(nil), "")

check("pathsEqual: case + separators",
    Sfx.pathsEqual("D:/SFX/Guns/a.wav", "d:\\sfx\\guns\\A.WAV"))
check("pathsEqual: different files",
    not Sfx.pathsEqual("D:/SFX/Guns/a.wav", "D:/SFX/Guns/b.wav"))
check("pathsEqual: trailing slash folder",
    Sfx.pathsEqual("D:/SFX/Guns/", "D:/SFX/Guns"))

-- ---------------------------------------------------------------------
-- sortPaths / findPathIndex
-- ---------------------------------------------------------------------

local sorted = Sfx.sortPaths({ "b.wav", "A.wav", "c.wav", "B.wav" })
equals("sortPaths: case-insensitive order", table.concat(sorted, ","),
    "A.wav,B.wav,b.wav,c.wav")

local paths = {
    "D:/SFX/Guns/gun_01.wav",
    "D:/SFX/Guns/gun_02.wav",
    "D:/SFX/Guns/gun_03.wav",
}
equals("findPathIndex: exact", Sfx.findPathIndex(paths, "D:/SFX/Guns/gun_02.wav"), 2)
equals("findPathIndex: canonical + case", Sfx.findPathIndex(paths, "d:\\sfx\\guns\\GUN_03.WAV"), 3)
equals("findPathIndex: missing", Sfx.findPathIndex(paths, "D:/SFX/Guns/gun_09.wav"), nil)
equals("findPathIndex: nil target", Sfx.findPathIndex(paths, nil), nil)

-- ---------------------------------------------------------------------
-- chooseRandomIndex (immediate-repeat avoidance)
-- ---------------------------------------------------------------------

math.randomseed(20240101)
local seen, avoided = {}, true
for _ = 1, 200 do
    local i = Sfx.chooseRandomIndex(3, 2)
    if i == 2 or i < 1 or i > 3 then avoided = false end
    seen[i] = true
end
check("chooseRandomIndex: never returns excluded index", avoided)
check("chooseRandomIndex: still covers the other candidates", seen[1] and seen[3])

equals("chooseRandomIndex: single candidate allowed", Sfx.chooseRandomIndex(1, 1), 1)
equals("chooseRandomIndex: empty library", Sfx.chooseRandomIndex(0, nil), nil)

local ranged = true
for _ = 1, 100 do
    local i = Sfx.chooseRandomIndex(2, nil)
    if i < 1 or i > 2 then ranged = false end
end
check("chooseRandomIndex: no exclusion covers all", ranged)

local outOfRange = true
for _ = 1, 100 do
    local i = Sfx.chooseRandomIndex(2, 99)
    if i < 1 or i > 2 then outOfRange = false end
end
check("chooseRandomIndex: out-of-range exclusion ignored", outOfRange)

-- ---------------------------------------------------------------------
-- browseIndex (next/previous with wrap-around)
-- ---------------------------------------------------------------------

equals("browseIndex: next", Sfx.browseIndex(1, 3, Sfx.BROWSE_NEXT), 2)
equals("browseIndex: next wraps last->first", Sfx.browseIndex(3, 3, Sfx.BROWSE_NEXT), 1)
equals("browseIndex: previous", Sfx.browseIndex(3, 3, Sfx.BROWSE_PREVIOUS), 2)
equals("browseIndex: previous wraps first->last", Sfx.browseIndex(1, 3, Sfx.BROWSE_PREVIOUS), 3)
equals("browseIndex: single file is a no-op", Sfx.browseIndex(1, 1, Sfx.BROWSE_NEXT), 1)

-- Compose findPathIndex + browseIndex the same way browseSample() does, so the
-- file-selection behavior is covered without REAPER.
local function browseTarget(fileList, current, direction)
    local i = Sfx.findPathIndex(fileList, current)
    if not i then return nil end
    return fileList[Sfx.browseIndex(i, #fileList, direction)]
end

equals("browse: next file", browseTarget(paths, paths[1], Sfx.BROWSE_NEXT), paths[2])
equals("browse: previous file", browseTarget(paths, paths[2], Sfx.BROWSE_PREVIOUS), paths[1])
equals("browse: next wraps last->first", browseTarget(paths, paths[3], Sfx.BROWSE_NEXT), paths[1])
equals("browse: previous wraps first->last", browseTarget(paths, paths[1], Sfx.BROWSE_PREVIOUS), paths[3])
equals("browse: unknown current source is safe", browseTarget(paths, "D:/SFX/Guns/zzz.wav", Sfx.BROWSE_NEXT), nil)
equals("browse: single file stays put", browseTarget({ paths[1] }, paths[1], Sfx.BROWSE_NEXT), paths[1])

-- ---------------------------------------------------------------------
-- Stored-state identifiers and module surface
-- ---------------------------------------------------------------------

for _, key in ipairs({ "category", "library", "source" }) do
    check("ITEM_META." .. key, type(Sfx.ITEM_META[key]) == "string" and Sfx.ITEM_META[key] ~= "")
end
check("PROJ_STATE_SECTION is set",
    type(Sfx.PROJ_STATE_SECTION) == "string" and Sfx.PROJ_STATE_SECTION ~= "")

-- The wrappers call these shared functions; they must be exported, and main()
-- must not run when the module is loaded. Their bodies use the REAPER API and
-- are therefore only exercised manually inside REAPER.
check("module exports insertRandomForTrackAtPosition",
    type(Sfx.insertRandomForTrackAtPosition) == "function")
check("module exports browseSample", type(Sfx.browseSample) == "function")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
