# Architecture

This document describes how the scripts are put together and, importantly,
where the extension points are. It is deliberately short — the implementation is
two small Lua files.

## Entry points and pipeline

Two entry points share one implementation, so the standard and mouse workflows
can never drift apart:

```text
  Entry point A: standard action          Entry point B: Alt+click wrapper
  InsertRandomSFX.lua                     InsertRandomSFXAtMouse.lua
    selected track                          track under mouse
    + reaper.GetCursorPosition()            + reaper.GetSet_ArrangeView2(mouse x)
                \                                   /
                 \                                 /
                  v                               v
            insertRandomForTrackAtPosition(track, position)
                              │
                              ▼
                     Category Resolver          resolveCategoryFromTrackName()
                              │
                              ▼
                     Configured Folder          CONFIG.category_folders[category]
                              │
                              ▼
                     Audio File List            collectSupportedAudioFiles()
                              │
                              ▼
                     Random Selection           math.random(#files)
                              │
                              ▼
                     REAPER Insert              insertMediaAtCursor()
                              │
                              ▼
                          Media Item
```

## Code layers

There are two scripts:

- **`scripts/InsertRandomSFX.lua`** — the core module and standard action. It
  holds all configuration, pure helpers and REAPER helpers, and exposes the
  shared `insertRandomForTrackAtPosition(track, position)`.
- **`scripts/InsertRandomSFXAtMouse.lua`** — a thin wrapper. It resolves the
  track under the mouse and the time under the mouse, selects the track, and
  calls the shared function. It contains no category/folder/undo logic.

`InsertRandomSFX.lua` is split into three sections, in this order:

### 1. Configuration (`CONFIG`)

The only place users edit. It holds:

- `category_folders` — the **track name → folder** map. This is the single
  source of truth for routing. The key is the REAPER track name (the category);
  the value is the folder on disk. The default configuration defines five
  categories:

  ```lua
  category_folders = {
      transition = "D:/SFX/Transitions",
      gun        = "D:/SFX/Guns",
      impact     = "D:/SFX/Impacts",
      whoosh     = "D:/SFX/Whooshes",
      footstep   = "D:/SFX/Footsteps",
  }
  ```

  For example, `gun = "D:/SFX/Guns"` means a track named `gun` uses audio from
  `D:/SFX/Guns`. The paths are placeholders for the user to change.
- `supported_extensions` — which file extensions count as importable audio.
- `undo_prefix` — prefix for the undo description.

No business logic mentions any specific category name; categories exist only as
rows in this table. Adding one is a configuration change.

### 2. Pure helpers (no REAPER API)

Deterministic, side-effect-free functions that can run outside REAPER and are
covered by `tests/run_tests.lua`:

| Function | Responsibility |
| --- | --- |
| `getExtension(fileName)` | lower-cased extension without the dot |
| `isSupportedAudioFile(fileName)` | extension is in `supported_extensions` |
| `joinPath(folder, name)` | separator-aware path joining |
| `resolveCategoryFromTrackName(trackName)` | track name → category key (case-insensitive, exact) |
| `collectSupportedAudioFiles(folder, [enumerate])` | folder listing → supported full paths |
| `directoryExists(path, [enumerateFiles], [enumerateSubdirs])` | best-effort folder-existence check |
| `capitalize(word)` | used for the undo description |
| `supportedFormatList()` | human-readable format list for errors |
| `configuredCategories()` | sorted category keys for errors |

The directory/file enumerators are **injectable** (they default to the REAPER
API). That is what makes these functions testable without REAPER.

### 3. REAPER API helpers

A thin boundary around `reaper.*`:

| Function | Responsibility |
| --- | --- |
| `getSelectedTrackOrNil()` | first selected track, or nil |
| `getTrackName(track)` | track name (empty string if unnamed) |
| `showError(message)` | modal error dialog |
| `insertMediaAtCursor(track, filePath, pos)` | insert via REAPER, pin to `pos` |
| `seedRandom()` | seed the RNG with time + high-resolution time |
| `insertRandomForTrackAtPosition(track, position)` | **shared**: resolve category → folder → files → random pick → insert (single undo) → errors |

`main()` (standard action) validates that a track is selected and calls
`insertRandomForTrackAtPosition(track, reaper.GetCursorPosition())`.

### 4. Mouse wrapper (`InsertRandomSFXAtMouse.lua`)

A thin script that:

1. `x, y = reaper.GetMousePosition()`
2. `track = reaper.GetTrackFromPoint(x, y)` (error if none)
3. `position = reaper.GetSet_ArrangeView2(0, false, x, x + 1)` — native
   screen-X → project-time conversion (no manual pixel math, no SWS)
4. `reaper.SetOnlyTrackSelected(track)` — because `InsertMedia(file, 0)`
   inserts on the current track
5. calls `insertRandomForTrackAtPosition(track, position)`

It never calls `SetEditCurPos`, so the edit cursor is preserved. It loads the
core module with `loadfile`, setting `_G.SFX_LOAD_AS_MODULE` so the module
returns its functions instead of running `main()`. The two scripts must stay in
the same directory.

## Insertion details

Insertion uses `reaper.InsertMedia(file, 0)` (`0` = add to current track). This
lets REAPER create the media source and determine its properties — the script
never decodes audio.

Because `InsertMedia` ultimately follows REAPER's import behaviour, the item(s)
it creates are then explicitly set to `D_POSITION = position`, where `position`
is supplied by the caller (the edit cursor for the standard action, the mouse
time for the Alt+click wrapper). The script detects the new item(s) by diffing
the track's item pointers before and after the call. This guarantees the
requested position regardless of any REAPER preference about where inserted
media lands, and gives a reliable success/failure signal.

The whole insertion is wrapped in:

```lua
reaper.Undo_BeginBlock()
-- insert
reaper.Undo_EndBlock(undo_description, -1)
```

so it is a single undo step.

## Extension points

These are the seams intended for future growth. They are intentionally small.

| Future feature | Touch point |
| --- | --- |
| Additional categories (beyond the five defaults) | add rows to `CONFIG.category_folders` |
| Fuzzy/partial track matching | `resolveCategoryFromTrackName` |
| Config file instead of inline table | replace the literal `CONFIG` table; the rest is unchanged |
| Avoid immediate repeats / weighting | the selection step in `insertRandomForTrackAtPosition`; add a pure `pickRandomFile(files, history)` helper |
| Recursive subfolders | `collectSupportedAudioFiles` (add subdir traversal) |
| Random gain/pitch/pan | a new step after `insertMediaAtCursor` |
| Additional mouse contexts (item edge/fade, bottom half) | REAPER-side wiring only; the wrapper already works from mouse position |
| Different formats | `CONFIG.supported_extensions` |

## Non-goals (for now)

No GUI, database, external service, project sync, mouse hooks, transient/peak
detection, audio analysis, automatic folder discovery, or native extension. See
`docs/roadmap.md`.
