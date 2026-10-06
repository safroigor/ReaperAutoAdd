-- @description SFX: Next Sample
-- @version 1.0
--[[
  NextSample.lua
  --------------
  Replaces the selected SFX item's source with the NEXT file in the same
  library (recorded in the item's metadata), keeping the item, its track and
  its exact start position. Wraps around from the last file to the first.

  The item is not moved and the new source determines the item's natural
  length. One undo step. If there is no valid selected item, or the library
  cannot be resolved, nothing is changed and a clear message is shown.

  Recommended mouse-wheel binding (see README.md > Sample browsing):
      Context: Media item   Behavior: mouse wheel up   Modifier: Alt
      -> SFX: Next Sample

  This is a thin wrapper: it only loads the shared core module
  (InsertRandomSFX.lua) and calls browseSample(). Keep both files together.

  Native REAPER APIs only. No SWS, no js_ReaScriptAPI, no external files.
]]

local MODULE_FILENAME = "InsertRandomSFX.lua"

local function showError(message)
    reaper.ShowMessageBox(message, "Random SFX Inserter", 0)
end

-- Directory containing this script, so its sibling module can be loaded
-- regardless of where the user keeps the repository.
local function thisScriptDirectory()
    local _, filename = reaper.get_action_context()
    if not filename or filename == "" then
        if debug and debug.getinfo then
            local source = debug.getinfo(1, "S").source
            filename = source:match("^@(.*)$") or source
        end
    end
    if not filename or filename == "" then
        return ""
    end
    return filename:match("^(.*[\\/])") or ""
end

-- Load InsertRandomSFX.lua without running its standard action.
local function loadSfxModule()
    local path = thisScriptDirectory() .. MODULE_FILENAME
    local chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr
    end

    _G.SFX_LOAD_AS_MODULE = true
    local ok, module = pcall(chunk)
    _G.SFX_LOAD_AS_MODULE = nil

    if not ok then
        return nil, module
    end
    return module
end

local function main()
    local sfx, err = loadSfxModule()
    if not sfx then
        return showError("Could not load " .. MODULE_FILENAME .. ":\n"
            .. tostring(err))
    end
    if type(sfx.browseSample) ~= "function" then
        return showError(MODULE_FILENAME .. " does not expose browseSample.\n\n"
            .. "Make sure both scripts are the same version and live in the "
            .. "same folder.")
    end

    sfx.browseSample(sfx.BROWSE_NEXT)
end

main()
