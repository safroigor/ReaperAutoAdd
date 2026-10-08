-- @description SFX: Settings
-- @version 1.0
--[[
  InsertRandomSFX_Settings.lua
  ----------------------------
  Settings window for the "REAPER Random SFX Inserter". It edits the mapping
  between a category (the track name) and its folder on disk, so the mapping can
  be changed from inside REAPER instead of editing a script by hand.

  The result is written to InsertRandomSFX_Settings.ini next to the scripts. Every other
  SFX action reads that file when it runs, so changes take effect on the next
  action (no reload of the scripts needed).

  A row is a pair: category name  ->  folder.

    Add       new pair (asks for the name, then picks the folder)
    Edit      rename / re-pick the folder of the selected row
    Remove    delete the selected row
    Up/Down   reorder rows (order is cosmetic; matching is by name)
    Reload    discard unsaved changes and re-read the file
    Save      validate and write the file
    Close     close the window (asks before discarding unsaved changes)

  Double-clicking a row edits it directly.

  Automation types: REAPER's native API plus Lua's standard library only.
  Text entry uses GetUserInputs and the folder picker uses GetUserFileName(3);
  the list itself is drawn with the built-in gfx window. No SWS, no
  js_ReaScriptAPI, no external dependencies.

  Keep this file in the same folder as InsertRandomSFX.lua, which it loads as a
  module for the parsing, validation and file I/O helpers.
]]

local MODULE_FILENAME = "InsertRandomSFX.lua"
local WINDOW_TITLE = "SFX: Settings"

local function showError(message)
    reaper.ShowMessageBox(message, WINDOW_TITLE, 0)
end

-- Directory containing this script, so its sibling module can be loaded
-- regardless of where the user keeps the scripts.
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

local sfx, loadErr = loadSfxModule()
if not sfx then
    return showError("Could not load " .. MODULE_FILENAME .. ":\n"
        .. tostring(loadErr))
end

-- The helpers this window relies on must exist in the loaded module.
for _, name in ipairs({
    "configFilePath", "readCategoryRowsFromFile", "currentCategoryRows",
    "saveCategories", "normalizeCategoryName", "canonicalizePath",
    "directoryExists",
}) do
    if type(sfx[name]) ~= "function" then
        return showError(MODULE_FILENAME .. " does not expose " .. name
            .. ".\n\nMake sure both scripts are the same version and live in "
            .. "the same folder.")
    end
end

local CONFIG_PATH = sfx.configFilePath()

-- =====================================================================
-- LOOK AND METRICS
-- =====================================================================

local COL = {
    bg          = { 0.10, 0.10, 0.11, 1 },
    header      = { 0.16, 0.16, 0.18, 1 },
    rowAlt      = { 0.13, 0.13, 0.15, 1 },
    rowSelected = { 0.20, 0.32, 0.48, 1 },
    border      = { 0.28, 0.28, 0.31, 1 },
    text        = { 0.88, 0.88, 0.90, 1 },
    textDim     = { 0.60, 0.60, 0.64, 1 },
    name        = { 0.96, 0.90, 0.70, 1 },
    error       = { 0.95, 0.55, 0.50, 1 },
    ok          = { 0.65, 0.85, 0.65, 1 },
    button      = { 0.22, 0.22, 0.25, 1 },
    buttonHover = { 0.30, 0.30, 0.34, 1 },
    buttonOff   = { 0.16, 0.16, 0.18, 1 },
}

local HEADER_H = 46
local FOOTER_H = 86
local ROW_H = 26
local PAD = 12
local BTN_H = 28
local BTN_W = 80
local BTN_GAP = 8

-- =====================================================================
-- STATE
-- =====================================================================

local state = {
    rows = {},
    selected = 0,
    scroll = 0,
    status = "",
    statusError = false,
    dirty = false,
    buttons = {},
    mouseDown = false,
    lastClickIndex = 0,
    lastClickTime = 0,
    closed = false,
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function setColor(color, alpha)
    gfx.set(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function viewTop()
    return HEADER_H
end

local function viewBottom()
    return gfx.h - FOOTER_H
end

local function viewHeight()
    return viewBottom() - viewTop()
end

local function setStatus(text, isError)
    state.status = text or ""
    state.statusError = isError and true or false
end

-- =====================================================================
-- DATA OPERATIONS
-- =====================================================================

local function ensureVisible()
    if state.selected < 1 then return end
    local height = viewHeight()
    local top = (state.selected - 1) * ROW_H
    local bottom = top + ROW_H
    if top < state.scroll then state.scroll = top end
    if bottom > state.scroll + height then state.scroll = bottom - height end
    state.scroll = clamp(state.scroll, 0,
        math.max(0, #state.rows * ROW_H - height))
end

local function loadRows()
    local rows = sfx.readCategoryRowsFromFile(CONFIG_PATH)
    if rows then
        state.rows = rows
        setStatus("Loaded " .. #rows .. " categories from " .. CONFIG_PATH, false)
    else
        state.rows = sfx.currentCategoryRows()
        setStatus("No settings file yet - showing the built-in defaults.", false)
    end
    state.selected = (#state.rows > 0) and 1 or 0
    state.scroll = 0
    state.dirty = false
end

local function validate(rows)
    if #rows == 0 then
        return "Add at least one category before saving."
    end
    local seen = {}
    for i = 1, #rows do
        local name = sfx.normalizeCategoryName(rows[i].name)
        if name == "" then
            return "Row " .. i .. " has an empty name."
        end
        if seen[name] then
            return "Duplicate category name: " .. name
        end
        seen[name] = true
    end
    return nil
end

local function missingFolders(rows)
    local missing = {}
    for _, row in ipairs(rows) do
        if not sfx.directoryExists(row.folder) then
            missing[#missing + 1] = row.folder
        end
    end
    return missing
end

local function saveRows()
    local problem = validate(state.rows)
    if problem then
        setStatus(problem, true)
        return
    end

    local missing = missingFolders(state.rows)
    if #missing > 0 then
        local answer = reaper.MB(
            "These folders do not exist:\n\n" .. table.concat(missing, "\n")
            .. "\n\nSave anyway?",
            WINDOW_TITLE, 4) -- 4 = YES/NO
        if answer ~= 6 then -- 6 = YES
            setStatus("Save cancelled.", false)
            return
        end
    end

    local ok, err = sfx.saveCategories(CONFIG_PATH, state.rows)
    if not ok then
        setStatus("Could not write " .. CONFIG_PATH .. ": " .. tostring(err),
            true)
        return
    end

    state.dirty = false
    setStatus("Saved " .. #state.rows .. " categories to " .. CONFIG_PATH, false)
end

local function nameUsed(rows, name, skipIndex)
    for i = 1, #rows do
        if i ~= skipIndex
            and sfx.normalizeCategoryName(rows[i].name) == name then
            return true
        end
    end
    return false
end

-- Ask for a category name, normalized and lower-cased. nil if cancelled.
local function askName(initial)
    local ok, ret = reaper.GetUserInputs(
        "Category name", 1, "Track name (category)", initial or "")
    if not ok then return nil end
    local first = (ret or ""):match("^([^,]*)") or ""
    local name = sfx.normalizeCategoryName(first)
    if name == "" then
        setStatus("A category name is required.", true)
        return nil
    end
    return name
end

-- Ask for a folder with REAPER's native directory picker. nil if cancelled.
local function askFolder(initial)
    local ok, path = reaper.GetUserFileName(
        3, "Choose this category's folder", initial or "", "")
    if not ok or not path or path == "" then return nil end
    return sfx.canonicalizePath(path)
end

local function addRow()
    local name = askName("")
    if not name then return end
    if nameUsed(state.rows, name) then
        setStatus("Category '" .. name .. "' already exists.", true)
        return
    end
    local folder = askFolder("")
    if not folder then return end
    state.rows[#state.rows + 1] = { name = name, folder = folder }
    state.selected = #state.rows
    state.dirty = true
    setStatus("Added '" .. name .. "'. Remember to Save.", false)
    ensureVisible()
end

local function editRow(index)
    local row = state.rows[index]
    if not row then return end
    local name = askName(row.name)
    if not name then return end
    if nameUsed(state.rows, name, index) then
        setStatus("Category '" .. name .. "' already exists.", true)
        return
    end
    local folder = askFolder(row.folder)
    if not folder then return end
    row.name = name
    row.folder = folder
    state.dirty = true
    setStatus("Updated '" .. name .. "'. Remember to Save.", false)
end

local function removeRow(index)
    local row = state.rows[index]
    if not row then return end
    table.remove(state.rows, index)
    if state.selected > #state.rows then state.selected = #state.rows end
    if state.selected < 1 and #state.rows > 0 then state.selected = 1 end
    state.dirty = true
    setStatus("Removed '" .. row.name .. "'. Remember to Save.", false)
end

local function moveRow(index, delta)
    local target = index + delta
    if target < 1 or target > #state.rows then return end
    state.rows[index], state.rows[target] = state.rows[target], state.rows[index]
    state.selected = target
    state.dirty = true
    ensureVisible()
end

local function requestClose()
    if state.dirty then
        local answer = reaper.MB(
            "You have unsaved changes. Discard them and close?",
            WINDOW_TITLE, 4) -- 4 = YES/NO
        if answer ~= 6 then return end -- 6 = YES
    end
    state.closed = true
    gfx.quit()
end

local function onClick(id)
    if id == "Add" then
        addRow()
    elseif id == "Edit" then
        editRow(state.selected)
    elseif id == "Remove" then
        removeRow(state.selected)
    elseif id == "Up" then
        moveRow(state.selected, -1)
    elseif id == "Down" then
        moveRow(state.selected, 1)
    elseif id == "Reload" then
        loadRows()
    elseif id == "Save" then
        saveRows()
    elseif id == "Close" then
        requestClose()
    end
end

-- =====================================================================
-- DRAWING
-- =====================================================================

local function drawButton(id, label, x, y, w, h, enabled, hovered)
    if not enabled then
        setColor(COL.buttonOff, 1)
    elseif hovered then
        setColor(COL.buttonHover, 1)
    else
        setColor(COL.button, 1)
    end
    gfx.rect(x, y, w, h, true)
    setColor(COL.border, 1)
    gfx.rect(x, y, w, h, false)

    gfx.setfont(1, "Arial", 14)
    setColor(enabled and COL.text or COL.textDim, 1)
    gfx.x, gfx.y = x, y
    gfx.drawstr(label, 5, x + w, y + h) -- flags 5 = centered, clipped

    state.buttons[#state.buttons + 1] = {
        id = id, x = x, y = y, w = w, h = h, enabled = enabled,
    }
end

local function drawRows()
    local top, bottom = viewTop(), viewBottom()
    gfx.setfont(1, "Arial", 14)

    if #state.rows == 0 then
        setColor(COL.textDim, 1)
        gfx.x, gfx.y = PAD, top + 12
        gfx.drawstr("No categories yet. Click Add to create one.")
        return
    end

    local nameW = math.max(160, math.floor(gfx.w * 0.28))
    for i = 1, #state.rows do
        local y = top + (i - 1) * ROW_H - state.scroll
        if y + ROW_H > top and y < bottom then
            if i == state.selected then
                setColor(COL.rowSelected, 1)
                gfx.rect(PAD - 4, y, gfx.w - 2 * (PAD - 4), ROW_H, true)
            elseif i % 2 == 0 then
                setColor(COL.rowAlt, 1)
                gfx.rect(PAD - 4, y, gfx.w - 2 * (PAD - 4), ROW_H, true)
            end

            setColor(COL.name, 1)
            gfx.x, gfx.y = PAD, y + 5
            gfx.drawstr(state.rows[i].name, 0, PAD + nameW - 8, y + ROW_H)

            setColor(COL.text, 1)
            gfx.x, gfx.y = PAD + nameW, y + 5
            gfx.drawstr(state.rows[i].folder, 0, gfx.w - PAD, y + ROW_H)
        end
    end
end

local function drawFooter()
    setColor(COL.header, 1)
    gfx.rect(0, gfx.h - FOOTER_H, gfx.w, FOOTER_H, true)
    setColor(COL.border, 1)
    gfx.rect(0, gfx.h - FOOTER_H, gfx.w, 1, true)

    local by = gfx.h - FOOTER_H + 10
    local mx, my = gfx.mouse_x, gfx.mouse_y

    local function hovered(x)
        return mx >= x and mx <= x + BTN_W and my >= by and my <= by + BTN_H
    end

    local left = {
        { "Add", true },
        { "Edit", state.selected >= 1 },
        { "Remove", state.selected >= 1 },
        { "Up", state.selected > 1 },
        { "Down", state.selected >= 1 and state.selected < #state.rows },
    }
    local x = PAD
    for _, item in ipairs(left) do
        drawButton(item[1], item[1], x, by, BTN_W, BTN_H, item[2], hovered(x))
        x = x + BTN_W + BTN_GAP
    end

    local right = { "Reload", "Save", "Close" }
    x = gfx.w - PAD - (#right * BTN_W + (#right - 1) * BTN_GAP)
    for _, id in ipairs(right) do
        drawButton(id, id, x, by, BTN_W, BTN_H, true, hovered(x))
        x = x + BTN_W + BTN_GAP
    end

    gfx.setfont(1, "Arial", 13)
    setColor(state.statusError and COL.error or COL.ok, 1)
    gfx.x, gfx.y = PAD, gfx.h - 26
    gfx.drawstr(state.status or "", 0, gfx.w - PAD, gfx.h - 6)
end

local function draw()
    state.buttons = {}

    setColor(COL.bg, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, true)

    setColor(COL.header, 1)
    gfx.rect(0, 0, gfx.w, HEADER_H, true)
    gfx.setfont(1, "Arial", 15, "b")
    setColor(COL.text, 1)
    gfx.x, gfx.y = PAD, 8
    gfx.drawstr("Category mapping")
    gfx.setfont(1, "Arial", 13)
    setColor(COL.textDim, 1)
    gfx.x, gfx.y = PAD, 27
    gfx.drawstr("A track named after a category uses that category's folder.   Track name  ->  folder")
    setColor(COL.border, 1)
    gfx.rect(0, HEADER_H - 1, gfx.w, 1, true)

    drawRows()
    drawFooter()
end

-- =====================================================================
-- INPUT
-- =====================================================================

local function handleKeyboard()
    local char
    repeat
        char = gfx.getchar()
        if char == -1 then
            state.closed = true
            return
        elseif char == 27 then -- ESC
            requestClose()
            if state.closed then return end
        end
    until char == 0
end

local function handleMouse()
    local down = (math.floor(gfx.mouse_cap) % 2) == 1
    local clicked = down and not state.mouseDown
    state.mouseDown = down
    if not clicked then return end

    local mx, my = gfx.mouse_x, gfx.mouse_y

    for _, button in ipairs(state.buttons) do
        if button.enabled
            and mx >= button.x and mx <= button.x + button.w
            and my >= button.y and my <= button.y + button.h then
            onClick(button.id)
            return
        end
    end

    local top, bottom = viewTop(), viewBottom()
    if my >= top and my < bottom then
        local index = math.floor((my - top + state.scroll) / ROW_H) + 1
        if index >= 1 and index <= #state.rows then
            local now = reaper.time_precise()
            if state.selected == index and state.lastClickIndex == index
                and (now - state.lastClickTime) < 0.4 then
                editRow(index)
            else
                state.selected = index
                ensureVisible()
            end
            state.lastClickIndex = index
            state.lastClickTime = now
        end
    end
end

local function handleWheel()
    local wheel = gfx.mouse_wheel
    if wheel and wheel ~= 0 then
        gfx.mouse_wheel = 0
        local maxScroll = math.max(0, #state.rows * ROW_H - viewHeight())
        state.scroll = clamp(state.scroll - (wheel / 120) * ROW_H * 3,
            0, maxScroll)
    end
end

-- =====================================================================
-- MAIN LOOP
-- =====================================================================

local function loop()
    handleKeyboard()
    if state.closed then return end

    handleWheel()
    handleMouse()
    if state.closed then return end

    draw()
    gfx.update()
    reaper.defer(loop)
end

local function main()
    loadRows()
    gfx.init(WINDOW_TITLE, 820, 480, 0, 120, 120)
    gfx.ext_retina = 1
    gfx.setfont(1, "Arial", 14)
    reaper.defer(loop)
end

main()
