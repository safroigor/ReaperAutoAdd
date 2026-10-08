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
| `scripts/InsertRandomSFX_Settings.lua` | Settings window (`gfx`): edits the category→folder mapping and writes `InsertRandomSFX_Settings.ini`. |

The wrappers contain no category/folder/undo logic. Each loads the core with
`loadfile`, setting `_G.SFX_LOAD_AS_MODULE` so the core returns its functions
instead of running `main()`. **All five files must stay in the same directory.**

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
  InsertRandomSFX_Settings.lua (Settings action)
    -> reads/writes InsertRandomSFX_Settings.ini (core loads it at startup)

  insertRandomForTrackAtPosition:
      category -> folder -> files -> random pick -> insert
      -> item metadata + project state + cursor to item start
  browseSample(item, direction):
      item metadata -> library -> files -> step -> replace source
      -> item metadata update
```

## Core code layers

`scripts/InsertRandomSFX.lua` is organised as:

### 1. Configuration (`CONFIG` + `InsertRandomSFX_Settings.ini`)

`CONFIG` holds the **built-in defaults**. The live mapping normally comes from
`InsertRandomSFX_Settings.ini`, a small text file next to the scripts that is edited by the
`SFX: Settings` action and loaded at startup (see below).

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

**Configuration file.** `CONFIG_FILENAME` (`InsertRandomSFX_Settings.ini`) lives next to
the scripts. Its format is one `track name = folder` line per category (`#`/`;`
comments and blank lines ignored). At the bottom of the core, before the module
hook, `loadCategoriesFromFile(configFilePath())` runs — only when the `reaper`
global exists, so the Lua unit tests keep the inline defaults. A non-empty file
replaces `CONFIG.category_folders` through `applyCategoryRows`. The settings
window writes the same format through `saveCategories`.

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
| `getFileName(path)` | last path component (the file name), for take naming |
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
| `trim(text)` | surrounding-whitespace trim |
| `normalizeCategoryName(name)` | trim + lower-case a category/track name |
| `parseCategories(text)` | settings text → ordered `{name, folder}` rows |
| `serializeCategories(rows)` | rows → settings text |
| `currentCategoryRows()` | current `CONFIG.category_folders` as sorted rows |
| `applyCategoryRows(rows)` | replace `CONFIG.category_folders` with rows |

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
| `attachSource(take, filePath)` | attach the file as the take's source, return its natural length (shared by insert + browse) |
| `setTakeName(take, filePath)` | set the take's displayed name (`P_NAME`) to the file name, matching a normal import |
| `buildPeaks(source)` | build a source's peaks now (Begin/Run/Finish) so the waveform draws immediately |
| `insertMediaOnTrack(track, filePath, pos)` | create the item + take, attach the source at `pos`, return the new item |
| `refreshItem(item)` | after a source change: mark the item's track dirty, refresh the item, redraw |
| `setEditCursorToItemStart(item)` | `SetEditCurPos` to the item's `D_POSITION` |
| `seedRandom()` | seed the RNG with time + high-resolution time |
| `scriptDirectory()` | directory of the running script (for the config file) |
| `configFilePath()` | absolute path of `InsertRandomSFX_Settings.ini` |
| `readTextFile` / `writeTextFile` | small `io.open` wrappers |
| `readCategoryRowsFromFile(path)` | parse the settings file, or nil if missing |
| `loadCategoriesFromFile(path)` | apply the settings file over the defaults |
| `saveCategories(path, rows)` | write rows to the settings file |

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

Insertion creates the item directly: `AddMediaItemToTrack` +
`AddTakeToMediaItem`, then attaches the source through the shared
`attachSource(take, filePath)` helper (`PCM_Source_CreateFromFile` +
`SetMediaItemTake_Source`), and sets `D_POSITION = position` (edit cursor for the
standard action, mouse time for the wrapper) and `D_LENGTH` from the source
length. REAPER still creates and owns the media source and determines its
properties — the script never decodes audio. The take is then named after the
file (`setTakeName` → `P_NAME`), because an API-created take has an empty name
and the item label would otherwise be blank; a normal REAPER import shows the
file name here. Finally it builds the new source's peaks (`buildPeaks`) and
refreshes the item (`refreshItem`), so the waveform is drawn immediately instead
of only after a later redraw or zoom.

The script deliberately does **not** use `reaper.InsertMedia`: it inserts at the
edit cursor and then moves the edit/play cursor to the end of the inserted item,
which disturbs playback (and would require moving the item to the mouse position
for the Alt+click workflow). Direct creation keeps the transport untouched.

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

Both insertion and browsing create and attach sources through the **same**
helper, `attachSource(take, filePath)`, so there is one source-construction path
and one ownership rule. `browseSample(item, direction)` uses it on the item's
existing take:

```lua
local length = attachSource(take, newPath)  -- create + attach, natural length
setTakeName(take, newPath)                  -- label follows the new file
buildPeaks(reaper.GetMediaItemTake_Source(take))  -- new waveform, immediately
-- set D_LENGTH/metadata; the item's exact D_POSITION is left untouched
refreshItem(item)                           -- item state + redraw
-- the OLD source is intentionally NOT destroyed (see below)
```

Ownership and lifetime:

- `PCM_Source_CreateFromFile` returns a source owned by the caller.
- `SetMediaItemTake_Source` transfers the **new** source to the take (REAPER
  duplicates it first if it is already used elsewhere). If the call fails the
  source is not attached and the script frees it.
- The **old** source is left alone. The API doc says the caller may destroy it
  (SWS's native `SetTakeSourceFromFile` does, via the C++ `P_SOURCE` setter), but
  in ReaScript `SetMediaItemTake_Source` is a higher-level path that does not
  refresh every internal reference, so freeing the old source was observed to
  corrupt playback and leave a stale waveform. REAPER reclaims it when safe.

Refresh: `SetMediaItemTake_Source` alone leaves REAPER's cached item state
(playback and peaks) pointing at the previous source, so `D_LENGTH` would change
while the old audio/waveform stayed. `buildPeaks(source)` builds the new
source's peaks (REAPER's Begin/Run/Finish sequence) so the waveform is available
to draw right away, and `refreshItem(item)` marks the item's track dirty
(`MarkTrackItemsDirty`, so peaks are rebuilt from the new source), refreshes the
item (`UpdateItemInProject`) and redraws (`UpdateArrange`). Insertion uses the
same two helpers so a brand-new item never draws with missing peaks.

To make the new source define the item's natural length, `attachSource` resets
the take's `D_STARTOFFS` to 0 and `D_PLAYRATE` to 1 and returns
`GetMediaSourceLength(source)`; the caller sets the item's `D_LENGTH`. Browsing
does not touch `D_POSITION`: `SetMediaItemTake_Source` does not move the item, so
its exact start is preserved. Volume, pan and mute are untouched.

## Extension points

| Future feature | Touch point |
| --- | --- |
| Additional categories | `SFX: Settings` (or rows in `CONFIG.category_folders`) |
| Fuzzy/partial track matching | `resolveCategoryFromTrackName` |
| Different config-file format | `parseCategories` / `serializeCategories`, `CONFIG_FILENAME` |
| Adjust the settings window | `InsertRandomSFX_Settings.lua` |
| Long-term history / weighting | the selection step in `insertRandomForTrackAtPosition`; add a pure helper |
| Recursive subfolders | `collectSupportedAudioFiles` |
| Random gain/pitch/pan | a new step after `insertMediaOnTrack` |
| Additional mouse contexts (item edge/fade, bottom half) | REAPER-side wiring only |
| Different formats | `CONFIG.supported_extensions` |

## Non-goals (for now)

No general-purpose GUI, database, external service, project sync, mouse hooks,
transient/peak detection, audio analysis, automatic folder discovery, or native
extension. The `SFX: Settings` window is a small, focused exception that edits
the category mapping only. See `docs/roadmap.md`.
