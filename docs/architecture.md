# Architecture

This document describes how the script is put together and, importantly, where
the extension points are. It is deliberately short — the implementation is one
Lua file.

## Pipeline

```text
                    ┌──────────────┐
                    │ Selected     │
                    │ REAPER Track │
                    └──────┬───────┘
                           │
                           ▼
                    Track Name
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

`scripts/InsertRandomSFX.lua` is split into three sections, in this order:

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

`main()` orchestrates: validate selection → resolve category → check folder →
list files → pick → insert (inside an undo block) → report only on failure.

## Insertion details

Insertion uses `reaper.InsertMedia(file, 0)` (`0` = add to current track). This
lets REAPER create the media source and determine its properties — the script
never decodes audio.

Because `InsertMedia` ultimately follows REAPER's import behaviour, the item(s)
it creates are then explicitly set to `D_POSITION = reaper.GetCursorPosition()`.
The script detects the new item(s) by diffing the track's item pointers before
and after the call. This guarantees the requested position regardless of any
REAPER preference about where inserted media lands, and gives a reliable
success/failure signal.

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
| Avoid immediate repeats / weighting | the selection step in `main()`; add a pure `pickRandomFile(files, history)` helper |
| Recursive subfolders | `collectSupportedAudioFiles` (add subdir traversal) |
| Random gain/pitch/pan | a new step after `insertMediaAtCursor` |
| Mouse modifiers / toolbar | REAPER-side action wiring; no change to this script's core |
| Different formats | `CONFIG.supported_extensions` |

## Non-goals (for now)

No GUI, database, external service, project sync, mouse hooks, audio analysis,
automatic folder discovery, or native extension. See `docs/roadmap.md`.
