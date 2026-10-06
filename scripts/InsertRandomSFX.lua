--[[
  InsertRandomSFX.lua
  -------------------
  ReaScript for the "REAPER Random SFX Inserter" project.

  What it does
  ------------
  Takes the currently selected REAPER track, resolves its name to a
  "category" (configured in CONFIG.category_folders, e.g. transition, gun,
  impact, whoosh, footstep), picks a random supported audio file from that
  category's configured folder, and inserts it as a normal media item at the
  current edit cursor position.

  Two workflows, one implementation
  ---------------------------------
  Standard action (this file, run directly):
    1. Select a track named after a configured category (e.g. `transition`).
    2. Put the edit cursor where you want the sound.
    3. Run this action (assign a shortcut / toolbar button if you like).

  Fast mouse workflow (see InsertRandomSFXAtMouse.lua):
    Move the mouse over the Arrange View at the desired track/time and press
    Alt+left-click. The track/time under the mouse are used and the edit
    cursor is left untouched.

  Both call the shared `insertRandomForTrackAtPosition(track, position)`
  below, so they can never drift apart.

  Design
  ------
  The mapping is deliberately data-driven so more categories can be added
  later without touching the logic:

      track name -> category -> configured folder -> audio files
                 -> random pick -> media item at position

  The pure logic (no REAPER API) is isolated in the "PURE HELPERS" section so
  it can be unit-tested outside REAPER. See docs/architecture.md.

  Configuration
  -------------
  Edit the CONFIG table below. See README.md > Configuration.
]]

-- =====================================================================
-- CONFIGURATION -- this is the part users are expected to edit
-- =====================================================================

local CONFIG = {
    -- Map: REAPER track name (the category) -> absolute folder of audio files
    -- for that category. The KEY is the track name; the VALUE is the folder.
    --
    --     gun = "D:/SFX/Guns"
    --
    -- means: a selected REAPER track named "gun" uses audio files from
    -- D:/SFX/Guns. Track names are matched case-insensitively, so "gun",
    -- "Gun" and "GUN" all resolve to the same category.
    --
    -- NOTE: the folders below are PLACEHOLDERS. Point them at real folders on
    -- your own machine before using the script.
    --
    -- Use forward slashes "/" on every platform: they work on Windows,
    -- macOS and Linux. On Windows, "D:/SFX/Guns" is equivalent to
    -- "D:\\SFX\\Guns" but avoids Lua backslash escaping.
    --
    -- Add more categories by adding lines.
    category_folders = {
        transition = "D:/SFX/Transitions",
        gun        = "D:/SFX/Guns",
        impact     = "D:/SFX/Impacts",
        whoosh     = "D:/SFX/Whooshes",
        footstep   = "D:/SFX/Footsteps",
    },

    -- File extensions treated as importable audio. Matched
    -- case-insensitively. Do not include the leading dot.
    supported_extensions = {
        wav = true,
        aif = true,
        aiff = true,
        flac = true,
        ogg = true,
        mp3 = true,
    },

    -- Prefix for the single REAPER undo description. The resolved category is
    -- appended, e.g. "Insert Random Transition".
    undo_prefix = "Insert Random ",
}

-- =====================================================================
-- PURE HELPERS -- no REAPER API access, unit-tested in tests/run_tests.lua
-- =====================================================================

-- Lower-cased extension of a file name without the leading dot, or "".
local function getExtension(fileName)
    if type(fileName) ~= "string" then return "" end
    local ext = fileName:match("%.([^./\\]+)$")
    if not ext then return "" end
    return ext:lower()
end

local function isSupportedAudioFile(fileName)
    local ext = getExtension(fileName)
    return ext ~= "" and CONFIG.supported_extensions[ext] == true
end

local function joinPath(folder, name)
    if folder:sub(-1) == "/" or folder:sub(-1) == "\\" then
        return folder .. name
    end
    return folder .. "/" .. name
end

-- Turn a track name into a configured category key, or nil.
-- Case-insensitive and whitespace-tolerant. Exact match only for now;
-- this is isolated here so fuzzy/partial matching can be added later.
local function resolveCategoryFromTrackName(trackName)
    if type(trackName) ~= "string" then return nil end
    local key = trackName:lower():match("^%s*(.-)%s*$")
    if key ~= "" and CONFIG.category_folders[key] ~= nil then
        return key
    end
    return nil
end

-- Collect the supported audio files in `folder`, returning full paths.
-- `enumerate` is injectable for tests; it defaults to the REAPER API.
-- reaper.EnumerateFiles lists files only (subdirectories come from
-- EnumerateSubdirectories), so subfolders are ignored by construction and
-- unsupported files are filtered out here.
local function collectSupportedAudioFiles(folder, enumerate)
    enumerate = enumerate or function(path, index)
        return reaper.EnumerateFiles(path, index)
    end
    local files = {}
    local index = 0
    while true do
        local name = enumerate(folder, index)
        if not name then break end
        if isSupportedAudioFile(name) then
            files[#files + 1] = joinPath(folder, name)
        end
        index = index + 1
    end
    return files
end

-- Best-effort "does this directory exist" test using only REAPER APIs.
-- EnumerateFiles returns nil for BOTH a missing and an empty folder, so to
-- tell those apart we fall back to looking the folder up in its parent.
local function directoryExists(path, enumerateFiles, enumerateSubdirs)
    if type(path) ~= "string" or path == "" then return false end

    enumerateFiles = enumerateFiles or function(p, i)
        return reaper.EnumerateFiles(p, i)
    end
    enumerateSubdirs = enumerateSubdirs or function(p, i)
        return reaper.EnumerateSubdirectories(p, i)
    end

    -- Fast path: a non-empty, existing folder.
    if enumerateFiles(path, 0) ~= nil then return true end

    -- Slow path: distinguish empty-but-existing from missing.
    local normalized = path:gsub("\\", "/"):gsub("/+$", "")
    local parent, name = normalized:match("^(.*/)([^/]+)$")
    if not parent or name == "" then return false end

    enumerateSubdirs(parent, -1) -- invalidate REAPER's directory cache
    local index = 0
    while true do
        local sub = enumerateSubdirs(parent, index)
        if not sub then break end
        if sub:lower() == name:lower() then return true end
        index = index + 1
    end
    return false
end

local function capitalize(word)
    return (word:gsub("^%l", string.upper))
end

local function supportedFormatList()
    local list = {}
    for ext in pairs(CONFIG.supported_extensions) do
        list[#list + 1] = "." .. ext
    end
    table.sort(list)
    return table.concat(list, ", ")
end

local function configuredCategories()
    local list = {}
    for key in pairs(CONFIG.category_folders) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

-- =====================================================================
-- REAPER API HELPERS -- kept small so the pure logic above stays testable
-- =====================================================================

local function getSelectedTrackOrNil()
    if reaper.CountSelectedTracks(0) < 1 then return nil end
    return reaper.GetSelectedTrack(0, 0)
end

local function getTrackName(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or ""
end

local function showError(message)
    reaper.ShowMessageBox(message, "Random SFX Inserter", 0)
end

-- Insert `filePath` onto `track` at `pos`, returning true on success.
-- Uses REAPER's own importer (InsertMedia) so REAPER determines the media
-- source properties, then pins the newly created item(s) to the exact cursor
-- position, independent of REAPER's insert-position preference.
local function insertMediaAtCursor(track, filePath, pos)
    local existing = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        existing[reaper.GetTrackMediaItem(track, i)] = true
    end

    reaper.InsertMedia(filePath, 0) -- 0 = add to current track

    local inserted = false
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if not existing[item] then
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
            inserted = true
        end
    end
    return inserted
end

local function seedRandom()
    local seed = os.time()
    if reaper.time_precise then
        seed = seed + math.floor((reaper.time_precise() % 1) * 1000000)
    end
    math.randomseed(seed)
end

-- =====================================================================
-- SHARED INSERTION LOGIC
-- =====================================================================

-- Resolve `track`'s category, pick a random file from that category's folder
-- and insert it on `track` at `position`. Returns true on success. Errors are
-- reported to the user; success is silent.
--
-- This is the single implementation shared by both entry points:
--   * InsertRandomSFX.lua        -> selected track + current edit cursor
--   * InsertRandomSFXAtMouse.lua -> track + time under the mouse
local function insertRandomForTrackAtPosition(track, position)
    -- 1. The track's name must resolve to a configured category.
    local trackName = getTrackName(track)
    local category = resolveCategoryFromTrackName(trackName)
    if not category then
        return showError(string.format(
            "Selected track is not a supported category.\n\n"
            .. "Selected track: %q\n"
            .. "Supported track names: %s",
            trackName,
            table.concat(configuredCategories(), ", ")))
    end

    -- 2. The category must point at an existing folder.
    local folder = CONFIG.category_folders[category]
    if not directoryExists(folder) then
        return showError(string.format(
            "The %s folder does not exist:\n%s\n\n"
            .. "Edit CONFIG.category_folders at the top of the script.",
            category, folder))
    end

    -- 3. That folder must contain at least one supported audio file.
    local files = collectSupportedAudioFiles(folder)
    if #files == 0 then
        return showError(string.format(
            "No supported audio files found in the %s folder:\n%s\n\n"
            .. "Supported formats: %s\n"
            .. "Subfolders are not searched in this version.",
            category, folder, supportedFormatList()))
    end

    -- 4. Pick one at random and insert it at `position`.
    seedRandom()
    local filePath = files[math.random(#files)]

    reaper.Undo_BeginBlock()
    local ok = insertMediaAtCursor(track, filePath, position)
    reaper.Undo_EndBlock(CONFIG.undo_prefix .. capitalize(category), -1)

    -- 5. Only complain on failure; success stays silent and instant.
    if not ok then
        return showError("Failed to insert the selected file:\n" .. filePath)
    end
    return true
end

-- =====================================================================
-- MAIN (standard action: selected track + current edit cursor)
-- =====================================================================

local function main()
    -- A track must be selected.
    local track = getSelectedTrackOrNil()
    if not track then
        return showError("No track selected.\n\n"
            .. "Select a track named after a configured category "
            .. "(see CONFIG.category_folders) first.")
    end

    insertRandomForTrackAtPosition(track, reaper.GetCursorPosition())
end

-- =====================================================================
-- ENTRY POINT / MODULE HOOK
-- =====================================================================

-- When this file is loaded as a module -- by the automated tests, or by
-- InsertRandomSFXAtMouse.lua -- it must NOT run main(); it only returns its
-- functions. Running it normally inside REAPER executes main().
if not _G.SFX_LOAD_AS_MODULE then
    main()
end

return {
    CONFIG = CONFIG,
    getExtension = getExtension,
    isSupportedAudioFile = isSupportedAudioFile,
    joinPath = joinPath,
    resolveCategoryFromTrackName = resolveCategoryFromTrackName,
    collectSupportedAudioFiles = collectSupportedAudioFiles,
    directoryExists = directoryExists,
    capitalize = capitalize,
    supportedFormatList = supportedFormatList,
    configuredCategories = configuredCategories,
    insertRandomForTrackAtPosition = insertRandomForTrackAtPosition,
}
