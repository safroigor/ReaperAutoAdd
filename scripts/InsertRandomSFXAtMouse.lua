--[[
  InsertRandomSFXAtMouse.lua
  --------------------------
  Fast mouse-placement entry point for the "REAPER Random SFX Inserter".

  What it does
  ------------
  Inserts a random SFX from the folder of the track UNDER THE MOUSE, at the
  project time UNDER THE MOUSE in the Arrange View, WITHOUT moving the edit
  cursor.

      mouse position
           |
  transition -------*------------   Alt+left-click
                    |                |
                    v                v
             random transition -> [SFX] inserted at the mouse time

  Required setup (one-time, per REAPER install)
  ---------------------------------------------
  Preferences -> Editing Behavior -> Mouse Modifiers, assign this script to
  BOTH of these:

      Context: Track        Behavior: left click   Modifier: Alt
      Context: Media item   Behavior: left click   Modifier: Alt

  Both bindings are required because REAPER hit-tests left clicks differently
  depending on whether the mouse is over empty track lane ("Track") or over an
  existing media item ("Media item").

  Known limitation: a few item sub-contexts (item edge, fade/autocrossfade,
  and "Media item bottom half" if enabled) are separate REAPER mouse contexts.
  Alt+left-click in those spots may not fire this script; a future task may add
  bindings for them. See docs/development.md.

  Design
  ------
  This wrapper only resolves "where" (track + time) and then calls the shared
  insertion logic in InsertRandomSFX.lua, so the two workflows can never drift
  apart. All category/folder/file/undo logic lives in that module.

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

-- Load InsertRandomSFX.lua without running its main() action.
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
    if type(sfx.insertRandomForTrackAtPosition) ~= "function" then
        return showError(MODULE_FILENAME .. " does not expose the shared "
            .. "insertion function.\n\nMake sure both scripts are the same "
            .. "version and live in the same folder.")
    end

    -- Where is the mouse?
    local x, y = reaper.GetMousePosition()

    -- Which track is under the mouse?
    local track = reaper.GetTrackFromPoint(x, y)
    if not track then
        return showError("No track under the mouse.\n\n"
            .. "Move the mouse over a track in the Arrange View, then "
            .. "Alt+left-click.")
    end

    -- Which project time corresponds to the mouse X coordinate?
    -- Native API; no manual pixel math and no SWS. Passing x and x+1 asks for
    -- the 1-pixel range at the mouse; the first return value is its start time.
    local position = reaper.GetSet_ArrangeView2(0, false, x, x + 1)

    -- InsertMedia(file, 0) targets the "current" track, so select the track
    -- under the mouse first. Selection is not an undoable operation, so it
    -- does not add an undo point. The edit cursor is never touched.
    reaper.SetOnlyTrackSelected(track)

    -- Shared insertion logic: category -> folder -> random file -> insert at
    -- the mouse-derived position.
    sfx.insertRandomForTrackAtPosition(track, position)
end

main()
