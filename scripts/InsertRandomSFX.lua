-- @description SFX: Insert Random SFX
-- @version 1.0
--[[
  InsertRandomSFX.lua
  -------------------
  Core module + standard action for the "REAPER Random SFX Inserter".

  What it does
  ------------
  Takes the currently selected REAPER track, resolves its name to a
  "category" (configured in CONFIG.category_folders, e.g. transition, gun,
  impact, whoosh, footstep), picks a random supported audio file from that
  category's configured folder, and inserts it as a normal media item at the
  current edit cursor position. The edit cursor then moves to the start of the
  inserted item, and item-local metadata records where the sound came from.

  Entry points
  ------------
  Standard action (this file, run directly):
    1. Select a track named after a configured category (e.g. `transition`).
    2. Put the edit cursor where you want the sound.
    3. Run this action (assign a shortcut / toolbar button if you like).

  Fast mouse workflow (see InsertRandomSFXAtMouse.lua):
    Move the mouse over the Arrange View at the desired track/time and press
    Alt+left-click.

  Sample browsing (see NextSample.lua / PreviousSample.lua):
    With an inserted SFX item selected, step to the next/previous file in the
    same library, replacing the item's source in place.

  All entry points call the shared functions below
  (`insertRandomForTrackAtPosition`, `browseSample`), so they cannot drift
  apart.

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
-- STORED-STATE IDENTIFIERS (not user-editable)
-- =====================================================================

-- Item-local metadata keys, stored with REAPER's native P_EXT: mechanism so an
-- item keeps knowing its library even if the track is renamed later.
local ITEM_META = {
    category = "sfx_category",
    library  = "sfx_library",
    source   = "sfx_source",
}

-- Project-level state section for the "avoid immediate repeat" memory. Saved
-- in the .RPP and therefore survives separate script runs.
local PROJ_STATE_SECTION = "RandomSFXInserter"

local BROWSE_NEXT = 1
local BROWSE_PREVIOUS = -1

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

-- Normalize a filesystem path for stable storage/comparison: forward slashes,
-- collapsed separators and no trailing slash (except a drive/root path).
local function canonicalizePath(path)
    if type(path) ~= "string" or path == "" then return "" end
    local p = path:gsub("\\", "/"):gsub("//+", "/")
    if #p > 1 and p:sub(-1) == "/" and not p:match("^%a:/$") then
        p = p:gsub("/+$", "")
    end
    return p
end

-- Compare two paths case-insensitively using their canonical forms.
local function pathsEqual(a, b)
    return canonicalizePath(a):lower() == canonicalizePath(b):lower()
end

-- Deterministic, human-friendly sort: case-insensitive, raw tie-break.
local function sortPaths(paths)
    table.sort(paths, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la == lb then return a < b end
        return la < lb
    end)
    return paths
end

-- 1-based index of `target` in `paths` (canonical comparison), or nil.
local function findPathIndex(paths, target)
    if type(target) ~= "string" or target == "" then return nil end
    for i = 1, #paths do
        if pathsEqual(paths[i], target) then return i end
    end
    return nil
end

-- Uniform random 1-based index in [1, count], avoiding `excludeIndex`.
-- With a single candidate that same index is returned (repeats allowed).
local function chooseRandomIndex(count, excludeIndex)
    if count <= 0 then return nil end
    if count == 1 then return 1 end
    if not excludeIndex or excludeIndex < 1 or excludeIndex > count then
        return math.random(count)
    end
    local r = math.random(count - 1)
    if r >= excludeIndex then r = r + 1 end
    return r
end

-- Step one item forward/backward with wrap-around. count <= 1 is a no-op.
local function browseIndex(index, count, direction)
    if count <= 1 then return index end
    local i = index + direction
    if i < 1 then
        i = count
    elseif i > count then
        i = 1
    end
    return i
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

-- Collect the supported audio files in `folder`, sorted deterministically,
-- returning full paths. `enumerate` is injectable for tests; it defaults to
-- the REAPER API. reaper.EnumerateFiles lists files only (subdirectories come
-- from EnumerateSubdirectories), so subfolders are ignored by construction and
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
    return sortPaths(files)
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

local function getSelectedMediaItemOrNil()
    if reaper.CountSelectedMediaItems(0) < 1 then return nil end
    return reaper.GetSelectedMediaItem(0, 0)
end

local function getTrackName(track)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name or ""
end

local function showError(message)
    reaper.ShowMessageBox(message, "Random SFX Inserter", 0)
end

-- Item-local metadata (persistent P_EXT: string state).
local function getItemMetadata(item, key)
    local _, value = reaper.GetSetMediaItemInfo_String(
        item, "P_EXT:" .. key, "", false)
    return value or ""
end

local function setItemMetadata(item, key, value)
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, value or "", true)
end

local function writeItemMetadata(item, category, library, source)
    setItemMetadata(item, ITEM_META.category, category)
    setItemMetadata(item, ITEM_META.library, canonicalizePath(library))
    setItemMetadata(item, ITEM_META.source, canonicalizePath(source))
end

-- Project-level state (survives separate script runs; saved in the .RPP).
local function getProjectState(key)
    local retval, value = reaper.GetProjExtState(0, PROJ_STATE_SECTION, key)
    if retval == 0 or not value or value == "" then return nil end
    return value
end

local function setProjectState(key, value)
    reaper.SetProjExtState(0, PROJ_STATE_SECTION, key, value or "")
end

-- Insert `filePath` onto `track` at `pos`, returning the new media item (or
-- nil). Uses REAPER's own importer (InsertMedia) so REAPER determines the
-- media source properties, then pins the new item to the exact position.
local function insertMediaOnTrack(track, filePath, pos)
    local existing = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        existing[reaper.GetTrackMediaItem(track, i)] = true
    end

    reaper.InsertMedia(filePath, 0) -- 0 = add to current track

    local inserted = nil
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if not existing[item] then
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
            inserted = item
        end
    end
    return inserted
end

-- Move the edit cursor onto `item`'s exact start (from its D_POSITION, never
-- from the source duration).
local function setEditCursorToItemStart(item)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetEditCurPos(pos, false, false)
    return pos
end

-- Replace `take`'s media source with the file at `newPath`.
-- Returns (true, naturalLength, oldSource) on success; the caller must destroy
-- `oldSource` afterwards (SetMediaItemTake_Source does not). The freshly
-- created new source becomes owned by the take.
local function replaceTakeSource(take, newPath)
    local newSource = reaper.PCM_Source_CreateFromFile(newPath)
    if not newSource then return false end

    local oldSource = reaper.GetMediaItemTake_Source(take)
    if not reaper.SetMediaItemTake_Source(take, newSource) then
        reaper.PCM_Source_Destroy(newSource)
        return false
    end

    -- Natural length, no stretch and no offset: the new source defines the
    -- item, we do not preserve the previous D_LENGTH.
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1)
    local length = reaper.GetMediaSourceLength(newSource)
    return true, length, oldSource
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
-- (avoiding the immediately previous pick for that category) and insert it on
-- `track` at `position`. Writes item metadata, remembers the pick for
-- duplicate prevention and moves the edit cursor to the item start.
-- Returns true on success. Errors are reported to the user.
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

    -- 4. Pick at random, avoiding the immediately previous file for this
    -- category (tracked per category, project-scoped).
    seedRandom()
    local previous = getProjectState(category)
    local index = chooseRandomIndex(#files, findPathIndex(files, previous))
    local filePath = files[index]

    -- 5. Insert, tag the item and finish as one undo step.
    reaper.Undo_BeginBlock()
    local item = insertMediaOnTrack(track, filePath, position)
    if item then
        writeItemMetadata(item, category, folder, filePath)
    end
    reaper.Undo_EndBlock(CONFIG.undo_prefix .. capitalize(category), -1)

    if not item then
        return showError("Failed to insert the selected file:\n" .. filePath)
    end

    -- Remember this pick (outside undo: project state is not undoable) and put
    -- the edit cursor on the new item's start.
    setProjectState(category, canonicalizePath(filePath))
    setEditCursorToItemStart(item)
    return true
end

-- =====================================================================
-- SAMPLE BROWSING
-- =====================================================================

-- Replace `item`'s source with the next/previous file from the library
-- recorded in its metadata. `direction` is BROWSE_NEXT or BROWSE_PREVIOUS.
-- Keeps the item, its track and its exact start position; the new source
-- determines the natural length. One undo step.
--
-- The target item is passed in explicitly, so the same logic serves the
-- selected item (NextSample.lua / PreviousSample.lua) and the item under the
-- mouse (InsertRandomSFXAtMouse.lua) without depending on selection state.
-- Returns true on success (including the one-file no-op), false on error.
local function browseSample(item, direction)
    if not item then
        return false
    end

    -- The item must carry our metadata.
    local library = getItemMetadata(item, ITEM_META.library)
    local source = getItemMetadata(item, ITEM_META.source)
    if library == "" or source == "" then
        showError("This item has no SFX library metadata.\n\n"
            .. "Insert it with 'SFX: Insert Random SFX' first.")
        return false
    end

    -- The recorded library must still contain supported audio files.
    local files = collectSupportedAudioFiles(library)
    if #files == 0 then
        showError(string.format(
            "No supported audio files found in the stored library:\n%s",
            library))
        return false
    end

    -- The item's current source must be findable, otherwise refuse to make an
    -- arbitrary destructive change.
    local index = findPathIndex(files, source)
    if not index then
        showError(string.format(
            "The item's source is not in its stored library, so nothing was "
            .. "changed.\n\nSource:\n%s\n\nLibrary:\n%s",
            source, library))
        return false
    end

    if #files == 1 then
        return true -- single-file library: nothing to browse to
    end

    local take = reaper.GetActiveTake(item)
    if not take then
        showError("This item has no active take.")
        return false
    end

    local newIndex = browseIndex(index, #files, direction)
    local newPath = files[newIndex]
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local description = (direction == BROWSE_NEXT)
        and "SFX: Next Sample" or "SFX: Previous Sample"

    reaper.Undo_BeginBlock()
    local ok, length, oldSource = replaceTakeSource(take, newPath)
    if ok then
        -- Keep the exact start; let the new source define the length.
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
        setItemMetadata(item, ITEM_META.source, canonicalizePath(newPath))
        -- SetMediaItemTake_Source swaps the take's source, but REAPER keeps a
        -- cached item state. Without this refresh the item keeps playing the
        -- previous source even though D_LENGTH was already updated.
        reaper.UpdateItemInProject(item)
        reaper.UpdateArrange()
        -- The item no longer references the old source, so it is safe to free.
        if oldSource then
            reaper.PCM_Source_Destroy(oldSource)
        end
    end
    reaper.Undo_EndBlock(description, -1)

    if not ok then
        showError("Failed to replace the source:\n" .. newPath)
        return false
    end
    return true
end

-- Browse the currently selected item. Used by NextSample.lua /
-- PreviousSample.lua. Returns true on success, false on error.
local function browseSelectedSample(direction)
    local item = getSelectedMediaItemOrNil()
    if not item then
        showError("No media item selected.\n\n"
            .. "Select an SFX item inserted by this tool, then try again.")
        return false
    end
    return browseSample(item, direction)
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

-- When this file is loaded as a module -- by the automated tests, or by the
-- action wrappers -- it must NOT run main(); it only returns its functions.
-- Running it normally inside REAPER executes main().
if not _G.SFX_LOAD_AS_MODULE then
    main()
end

return {
    CONFIG = CONFIG,
    ITEM_META = ITEM_META,
    PROJ_STATE_SECTION = PROJ_STATE_SECTION,
    BROWSE_NEXT = BROWSE_NEXT,
    BROWSE_PREVIOUS = BROWSE_PREVIOUS,
    getExtension = getExtension,
    isSupportedAudioFile = isSupportedAudioFile,
    joinPath = joinPath,
    canonicalizePath = canonicalizePath,
    pathsEqual = pathsEqual,
    sortPaths = sortPaths,
    findPathIndex = findPathIndex,
    chooseRandomIndex = chooseRandomIndex,
    browseIndex = browseIndex,
    resolveCategoryFromTrackName = resolveCategoryFromTrackName,
    collectSupportedAudioFiles = collectSupportedAudioFiles,
    directoryExists = directoryExists,
    capitalize = capitalize,
    supportedFormatList = supportedFormatList,
    configuredCategories = configuredCategories,
    insertRandomForTrackAtPosition = insertRandomForTrackAtPosition,
    browseSample = browseSample,
    browseSelectedSample = browseSelectedSample,
    setEditCursorToItemStart = setEditCursorToItemStart,
}
