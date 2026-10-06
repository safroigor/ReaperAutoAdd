# Architecture

This document describes how the scripts are put together and, importantly,
where the extension points are. It is deliberately short — the implementation is
one core module plus three thin action wrappers.

## Scripts and entry points

Four scripts; all shared logic lives in the core:

| Script | Role |
| --- | --- |
| `scripts/InsertRandomSFX.lua` | **Core module** + standard action. Holds `CONFIG`, pure helpers, REAPER helpers and the two shared operations. |
| `scripts/InsertRandomSFXAtMouse.lua` | Wrapper: Alt+click. If an item is under the mouse → `browseSample(item, BROWSE_NEXT)`; otherwise → insert at the mouse time. |
| `scripts/NextSample.lua` | Wrapper: `browseSelectedSample(BROWSE_NEXT)`. |
| `scripts/PreviousSample.lua` | Wrapper: `browseSelectedSample(BROWSE_PREVIOUS)`. |

The wrappers contain no category/folder/undo logic. Each loads the core with
`loadfile`, setting `_G.SFX_LOAD_AS_MODULE` so the core returns its functions
instead of running `main()`. **All four files must stay in the same directory.**

```text
  Entry point                              Shared operation
  -----------                              ----------------
  InsertRandomSFX.lua (standard action,
    selected track + GetCursorPosition) --> insertRandomForTrackAtPosition(track, position)

  InsertRandomSFXAtMouse.lua (Alt+click)
    + GetMousePosition
    + GetItemFromPoint(mouse)
      item under mouse?  yes ------------> browseSample(item, BROWSE_NEXT)
                         no -------------> insertRandomForTrackAtPosition(track, position)
                                          (track from GetTrackFromPoint,
                                           position from GetSet_ArrangeView2)

  NextSample.lua      (selected item) ---> browseSelectedSample(BROWSE_NEXT)
  PreviousSample.lua  (selected item) ---> browseSelectedSample(BROWSE_PREVIOUS)

  insertRandomForTrackAtPosition:
      category -> folder -> files -> random pick -> insert
      -> item metadata + project state + cursor to item start
  browseSample(item, direction):
      item metadata -> library -> files -> step -> replace source
      -> item metadata update
```

## Core code layers

`scripts/InsertRandomSFX.lua` is organised as:

### 1. Configuration (`CONFIG`)

The only place users edit:

- `category_folders` — the **track name → folder** map (single source of truth
  for routing). The key is the REAPER track name (the category); the value is
  the folder on disk:

  ```lua
  category_folders = {
      transition = "D:/SFX/Transitions",
      gun        = "D:/SFX/Guns",
      impact     = "D:/SFX/Impacts",
      whoosh     = "D:/SFX/Whooshes",
      footstep   = "D:/SFX/Footsteps",
  }
  ```

- `supported_extensions` — which file extensions count as importable audio.
- `undo_prefix` — prefix for the insert undo description.

No business logic mentions any specific category name; categories exist only as
rows in this table.

### 2. Stored-state identifiers

- `ITEM_META` — the `P_EXT:` keys written on each inserted item:
  `category`, `library`, `source`.
- `PROJ_STATE_SECTION` — the `SetProjExtState` section used for the
  "avoid immediate repeat" memory (one key per category).
- `BROWSE_NEXT` / `BROWSE_PREVIOUS` — the browsing directions.

### 3. Pure helpers (no REAPER API)

Deterministic, side-effect-free functions covered by `tests/run_tests.lua`:

| Function | Responsibility |
| --- | --- |
| `getExtension(fileName)` | lower-cased extension without the dot |
| `isSupportedAudioFile(fileName)` | extension is in `supported_extensions` |
| `joinPath(folder, name)` | separator-aware path joining |
| `canonicalizePath(path)` | forward slashes, collapsed separators, no trailing slash |
| `pathsEqual(a, b)` | case-insensitive comparison of canonical paths |
| `sortPaths(paths)` | deterministic, case-insensitive, raw tie-break |
| `findPathIndex(paths, target)` | 1-based index by canonical comparison, or nil |
| `chooseRandomIndex(count, excludeIndex)` | uniform random index, avoiding one excluded index |
| `browseIndex(index, count, direction)` | step forward/backward with wrap-around |
| `resolveCategoryFromTrackName(trackName)` | track name → category key (case-insensitive, exact) |
| `collectSupportedAudioFiles(folder, [enumerate])` | folder listing → supported full paths, **sorted** |
| `directoryExists(path, [enumerateFiles], [enumerateSubdirs])` | best-effort folder-existence check |
| `capitalize(word)` | used for the undo description |
| `supportedFormatList()` | human-readable format list for errors |
| `configuredCategories()` | sorted category keys for errors |

The directory/file enumerators are **injectable** (they default to the REAPER
API), which is what makes these functions testable without REAPER.

### 4. REAPER API helpers

A thin boundary around `reaper.*`:

| Function | Responsibility |
| --- | --- |
| `getSelectedTrackOrNil()` / `getSelectedMediaItemOrNil()` | first selected track/item, or nil |
| `getTrackName(track)` | track name (empty string if unnamed) |
| `showError(message)` | modal error dialog |
| `getItemMetadata` / `setItemMetadata` / `writeItemMetadata` | item `P_EXT:` string state |
| `getProjectState` / `setProjectState` | project-scoped string state (`SetProjExtState`) |
| `insertMediaOnTrack(track, filePath, pos)` | insert via REAPER, pin to `pos`, return the new item |
| `setEditCursorToItemStart(item)` | `SetEditCurPos` to the item's `D_POSITION` |
| `replaceTakeSource(take, newPath)` | swap the take's source, return its natural length |
| `seedRandom()` | seed the RNG with time + high-resolution time |

### 5. Shared operations

- `insertRandomForTrackAtPosition(track, position)` — resolve category → folder
  → files → random pick (avoiding the immediate previous pick) → insert →
  write metadata → remember pick → move edit cursor to item start. One undo
  step (insert + metadata).
- `browseSample(item, direction)` — read `item`'s metadata → resolve the library
  → find the current source → step (wrap-around) → replace the take source →
  keep exact position → set natural length → update metadata. One undo step.
  The target item is passed in explicitly, so the same logic serves the item
  under the mouse and the selected item.
- `browseSelectedSample(direction)` — resolves the selected item and calls
  `browseSample`. Used by the Next/Previous wrappers.

`main()` (standard action) validates that a track is selected and calls
`insertRandomForTrackAtPosition(track, reaper.GetCursorPosition())`.

## Insertion details

Insertion uses `reaper.InsertMedia(file, 0)` (`0` = add to current track), so
REAPER creates the media source and determines its properties — the script never
decodes audio. The new item(s) are found by diffing the track's item pointers
before/after the call, then pinned to `D_POSITION = position` (edit cursor for
the standard action, mouse time for the wrapper).

The insert **and** the metadata write are wrapped in one undo block:

```lua
reaper.Undo_BeginBlock()
-- insert + write P_EXT: metadata
reaper.Undo_EndBlock(undo_description, -1)
```

After that (outside undo), the previous pick is stored in project state and the
edit cursor is moved to the item's `D_POSITION`. Neither is an undo point.

## Item metadata and project state

- **Item metadata** uses `GetSetMediaItemInfo_String(item, "P_EXT:<key>", …)`.
  It is item-local and, importantly, part of REAPER's undo history, so it lives
  inside the undo block.
- **Project state** uses `SetProjExtState` / `GetProjExtState`. It is outside
  undo history and is saved in the `.RPP`, so it survives separate script runs
  and is scoped to the project. It stores the last random pick **per category**.

Paths are canonicalized before storage and comparison, so `D:\SFX\Guns\a.wav`
and `d:/sfx/guns/A.WAV` are treated as the same file.

## Source replacement details

`browseSample(item, direction)` replaces the active take's source:

```lua
local newSource = reaper.PCM_Source_CreateFromFile(newPath)
local oldSource = reaper.GetMediaItemTake_Source(take)
reaper.SetMediaItemTake_Source(take, newSource)   -- take now owns newSource
reaper.PCM_Source_Destroy(oldSource)              -- we own the old source
```

`SetMediaItemTake_Source` does **not** destroy the old source, so the script
destroys it. To make the new source define the item's natural length, the take's
`D_STARTOFFS` is reset to 0 and `D_PLAYRATE` to 1, then the item's `D_LENGTH` is
set to `GetMediaSourceLength(newSource)`. The item's exact `D_POSITION` is
re-asserted; volume, pan and mute are untouched.

## Extension points

| Future feature | Touch point |
| --- | --- |
| Additional categories | add rows to `CONFIG.category_folders` |
| Fuzzy/partial track matching | `resolveCategoryFromTrackName` |
| Config file instead of inline table | replace the literal `CONFIG` table |
| Long-term history / weighting | the selection step in `insertRandomForTrackAtPosition`; add a pure helper |
| Recursive subfolders | `collectSupportedAudioFiles` |
| Random gain/pitch/pan | a new step after `insertMediaOnTrack` |
| Additional mouse contexts (item edge/fade, bottom half) | REAPER-side wiring only |
| Different formats | `CONFIG.supported_extensions` |

## Non-goals (for now)

No GUI, database, external service, project sync, mouse hooks, transient/peak
detection, audio analysis, automatic folder discovery, or native extension. See
`docs/roadmap.md`.
