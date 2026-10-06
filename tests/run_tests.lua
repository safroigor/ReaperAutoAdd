--[[
  run_tests.lua -- unit tests for the pure logic in InsertRandomSFX.lua.

  These tests never call REAPER. The script exposes its pure helpers when it
  is loaded with _G.SFX_TEST_MODE set (see the TEST HOOK section of the
  script).

  Run from the repository root with any Lua 5.3+ interpreter:

      lua tests/run_tests.lua

  REAPER itself ships Lua 5.4, so the syntax used here is safe there too.
]]

_G.SFX_TEST_MODE = true

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
-- resolveCategoryFromTrackName (MVP: only "transition")
-- ---------------------------------------------------------------------

equals("resolve: lower", Sfx.resolveCategoryFromTrackName("transition"), "transition")
equals("resolve: Title", Sfx.resolveCategoryFromTrackName("Transition"), "transition")
equals("resolve: UPPER", Sfx.resolveCategoryFromTrackName("TRANSITION"), "transition")
equals("resolve: surrounding spaces", Sfx.resolveCategoryFromTrackName("  transition  "), "transition")
equals("resolve: wrong category", Sfx.resolveCategoryFromTrackName("dialogue"), nil)
equals("resolve: no partial match", Sfx.resolveCategoryFromTrackName("trans"), nil)
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
equals("collect: first", files[1], "C:/SFX/Transitions/boom.wav")
equals("collect: uppercase ext kept", files[4], "C:/SFX/Transitions/hit.FLAC")

local none = Sfx.collectSupportedAudioFiles("C:/empty", fakeEnumerate({ "x.txt", "y.png", "z" }))
equals("collect: nothing supported", #none, 0)

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
equals("configuredCategories: count", #categories, 1)
equals("configuredCategories: first", categories[1], "transition")

-- ---------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
