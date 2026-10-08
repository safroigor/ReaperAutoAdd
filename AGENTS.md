# AGENTS.md

Guidance for anyone (human or AI coding agent) working in this repository.
Read this before changing code.

Cross-references:

- [`README.md`](README.md) — what the project is and how to use it.
- [`docs/architecture.md`](docs/architecture.md) — how the code is structured.
- [`docs/development.md`](docs/development.md) — how to develop and test.
- [`docs/roadmap.md`](docs/roadmap.md) — where this is going.

---

## 1. Project purpose

**REAPER Random SFX Inserter** is a workflow tool for [REAPER](https://www.reaper.fm/).
The long-term vision is a sound-design workflow where the user works directly on
a REAPER timeline and places random sound effects from predefined folders based
on the selected track's name:

```text
track named "transition"  ->  random file from the "Transitions" folder
track named "gun"         ->  random file from the "Guns" folder
track named "impact"      ->  random file from the "Impacts" folder
...
```

The eventual UX may be invoked with a keyboard shortcut, a toolbar button, or a
mouse modifier (Ctrl-click, Shift-click, ...) on a track. That interaction layer
is **not** part of the current scope.

The value of the project is speed: keep the mouse on the timeline, press one
key, get a suitable sound at the cursor.

## 2. Current implementation

All shared logic lives in
[`scripts/InsertRandomSFX.lua`](scripts/InsertRandomSFX.lua) (core module +
standard action). Three thin action wrappers and one settings window load it.

**Insertion** — standard action, and Alt+click on **empty track lane** via
[`InsertRandomSFXAtMouse.lua`](scripts/InsertRandomSFXAtMouse.lua):

1. Requires a selected track (standard) or a track under the mouse (Alt+click).
2. Resolves the track's name to a category, case-insensitively. Five categories
   are configured by default: `transition`, `gun`, `impact`, `whoosh`,
   `footstep`.
3. Looks in the folder configured for that category and lists its supported
   audio files (subfolders ignored), sorted deterministically.
4. Picks one at random, **avoiding the immediately previous pick for that
   category** (state kept in the project, tracked per category).
5. Inserts it as a normal media item at the position (edit cursor, or mouse
   time for Alt+click).
6. Writes item metadata (`category`, `library`, `source`) via `P_EXT:`.
7. Moves the edit cursor to the inserted item's start (`D_POSITION`).
8. Wraps insert + metadata in a single REAPER undo step
   (`Insert Random <Category>`, e.g. `Insert Random Gun`).

**Sample browsing** — Alt+click on an **existing SFX item** via
`InsertRandomSFXAtMouse.lua`, or the selected item via
[`NextSample.lua`](scripts/NextSample.lua) /
[`PreviousSample.lua`](scripts/PreviousSample.lua):

1. `browseSample(item, direction)` takes the target item **explicitly**, so it
   serves both the item under the mouse (no selection needed) and the selected
   item.
2. Reads the item's `library` / `source` metadata.
3. Steps to the next/previous file in that library (sorted, wrap-around).
4. Replaces the item's media source in place — no new item, same track, exact
   start preserved, and the new source determines the item's natural length (no
   time-stretch, old length not kept).
5. Updates the `source` metadata. Single undo step.

The Alt+click wrapper decides between insertion and browsing from the item
under the mouse (`GetItemFromPoint`): item present → browse next; no item →
insert random. It never relies on the selection for browsing.

**Settings** —
[`InsertRandomSFX_Settings.lua`](scripts/InsertRandomSFX_Settings.lua) (action
`SFX: Settings`) is a small `gfx` window that edits the track-name → folder
mapping and writes `InsertRandomSFX_Settings.ini` into REAPER's Scripts resource
folder (where the scripts live). The core
reads that file at startup and applies it over the built-in
`CONFIG.category_folders` defaults, so the mapping can be changed without editing
any script.

Supported formats: `.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`.

Everything else in `docs/roadmap.md` is a plan, not a feature. Do not build it
without being asked.

## 3. Architecture

Two shared operations, called by thin wrappers:

```text
  Entry point                              Shared operation
  -----------                              ----------------
  standard action (selected track
    + edit cursor)  ---------------------> insertRandomForTrackAtPosition(track, position)
  Alt+click, no item under mouse
    (empty track lane) ------------------> insertRandomForTrackAtPosition(track, position)
  Alt+click, item under mouse  ---------> browseSample(item, BROWSE_NEXT)
  NextSample.lua (selected item) -------> browseSample(item, BROWSE_NEXT)
  PreviousSample.lua (selected item) ---> browseSample(item, BROWSE_PREVIOUS)
  InsertRandomSFX_Settings.lua (settings action) ----> edits InsertRandomSFX_Settings.ini
                                          (core loads it at startup)

  insertRandomForTrackAtPosition:
      category -> folder -> files -> random pick -> insert
      -> item metadata + project state + cursor to item start
  browseSample:
      item metadata -> library -> files -> step -> replace source
      -> item metadata update
```

Key rule: **the code must not be hard-coded around any single category.** Each
category is just a row in the `CONFIG.category_folders` table. Adding a category
is a configuration change, not a logic change.

The core script is organised into these layers so future growth stays cheap:

1. **Configuration** — `CONFIG.category_folders` holds the built-in defaults;
   the live mapping is loaded from `InsertRandomSFX_Settings.ini` at startup
   (see below). Logic never edits this.
2. **Stored-state identifiers** — `ITEM_META` (`P_EXT:` keys),
   `PROJ_STATE_SECTION`, browse directions.
3. **Pure helpers** — no REAPER API calls (extension parsing, category
   resolution, path joining/canonicalization/comparison, file filtering and
   sorting, directory detection, random-index and browse stepping). Unit-tested
   outside REAPER.
4. **REAPER API helpers** — small wrappers around `reaper.*` (selection, track
   name, error dialog, item `P_EXT:` metadata, project state, insertion, edit
   cursor, source replacement).
5. **Shared operations** — `insertRandomForTrackAtPosition` and `browseSample`.

Plus three thin **wrappers** (`InsertRandomSFXAtMouse.lua`, `NextSample.lua`,
`PreviousSample.lua`) that only resolve an entry point and call the shared
function, and the **settings window** `InsertRandomSFX_Settings.lua`, which uses
the core's pure `parseCategories` / `serializeCategories` helpers and the file
I/O helpers to read and write `InsertRandomSFX_Settings.ini`.

The settings file is loaded at the bottom of the core, before the module hook,
only when the `reaper` global exists — so the Lua unit tests keep the inline
defaults. The parser/serializer stay pure and tested.

The core script ends with a documented **module hook**: when loaded with
`_G.SFX_LOAD_AS_MODULE` set, it returns its functions instead of running
`main()`. The tests and all wrappers use this.

See `docs/architecture.md` for extension points.

## 4. Technology constraints

- **REAPER ReaScript**, written in **Lua**.
- **REAPER's native API** only.
- **No runtime dependencies.** The runtime script must run on a clean REAPER
  install with no package manager, no `lua` binary, no Python, no third-party
  Lua modules. Do not add `require` of external modules.
- **No manual audio decoding.** REAPER imports the media; we never parse audio.
- **Compatibility.** Target the Lua version REAPER ships (currently Lua 5.4).
  Prefer widely available standard-library constructs. When a pure-logic test
  needs a newer feature, remember REAPER's Lua is the ceiling, not the latest
  upstream release.
- **Cross-platform.** Windows and macOS are both first-class. Prefer forward
  slashes `/` in paths; they work on both. Use `reaper.EnumerateFiles` /
  `reaper.EnumerateSubdirectories` instead of Lua's `io.popen`, which is
  platform-specific.
- **Mouse placement uses native APIs only.** `GetMousePosition`,
  `GetTrackFromPoint` and `GetSet_ArrangeView2`. Do not add SWS,
  js_ReaScriptAPI, or window-message hooks.

## 5. Coding rules

- Keep scripts **small and readable**. The implementation is a small set of
  files on purpose: the core, three thin action wrappers, and one settings
  window.
- **Avoid unnecessary abstraction.** Add a function when it isolates something
  real (an API call, an error path, a future extension point), not for symmetry.
- **Isolate REAPER API interaction** in the "REAPER API HELPERS" section.
  Business logic must not call `reaper.*` directly.
- **Keep configuration separate from logic.** `CONFIG.category_folders` holds
  the built-in defaults; the live mapping comes from
  `InsertRandomSFX_Settings.ini` (edited by `SFX: Settings`).
  Parsing/serialization stays pure and unit-tested; configuration loading must
  never run when `reaper` is absent (the tests).
- **Do not introduce external dependencies** without a strong, documented
  reason.
- **Preserve REAPER undo behaviour.** Any state-changing operation goes inside
  `reaper.Undo_BeginBlock()` / `reaper.Undo_EndBlock(desc, -1)` with a
  human-readable description, and must be a single undo step.
- **Do not silently fail.** Show a clear REAPER message on every error path.
  Do **not** show a modal dialog on the successful path.
- **Insertion moves the edit cursor to the inserted item's start**, read from
  the item's `D_POSITION` (never from the source duration, never left at the
  item's end). Alt+click browsing also moves the cursor to the browsed item's
  start.
- **Never move the transport.** `SetEditCurPos` is always called as
  `SetEditCurPos(pos, false, false)` (`moveview=false`, `seekplay=false`) so the
  edit cursor and the play position stay independent — do not seek, stop or
  start playback.
- **Insertion must not use `reaper.InsertMedia`.** It inserts at the edit cursor
  and then moves the edit/play cursor to the end of the inserted item, which
  disturbs playback. Create the item directly instead (`AddMediaItemToTrack` +
  `AddTakeToMediaItem` + `PCM_Source_CreateFromFile` + `SetMediaItemTake_Source`).
- **A take created through the API must be named from its source file.** REAPER
  names a take after the file on a normal media import (that is what the item
  label shows), but an API-created take starts with an empty name and would
  display no name. Insertion and browsing set `P_NAME` via
  `setTakeName(take, filePath)` to the file's base name (extension included).
- **`MarkTrackItemsDirty` requires a `MediaTrack` as its first argument** (use
  `reaper.GetMediaItem_Track(item)`); passing `nil` throws and aborts the script,
  leaving the undo block open.
- **Insertion and browsing must build the new source's peaks and refresh the
  item.** `buildPeaks(source)` runs REAPER's Begin/Run/Finish sequence so the
  waveform draws immediately; `refreshItem(item)` marks the item's track dirty
  (`MarkTrackItemsDirty`), calls `UpdateItemInProject` and `UpdateArrange`.
  Without the peak build a freshly created item can draw before its peaks exist,
  so the waveform only appears later (on a zoom/redraw).
- **Browsing must not move the item.** Next/Previous (and Alt+click on an item)
  replace the active take's source in place: same item, same track, exact
  `D_POSITION` preserved, and the new source determines the natural length
  (`D_LENGTH`); do not keep the old length or time-stretch.
- **The Alt+click browse target is the item under the mouse**, resolved with
  `GetItemFromPoint`; never fall back to the selected item for that gesture.
- **Item metadata is item-local** (`P_EXT:` keys `sfx_category`, `sfx_library`,
  `sfx_source`). Browsing must use the stored library, never the current track
  name. Canonicalize paths before storing/comparing.
- **Duplicate-prevention state is project-scoped** (`SetProjExtState`), tracked
  per category, outside undo history. Do not rely on Lua globals surviving
  between script runs.
- **Do not break existing workflows.** The contract:
  * standard action — select a category track, position the cursor, run once,
    get one item at the cursor;
  * Alt+click on empty track lane — insert one item at the mouse time;
  * Alt+click on an item — replace that item with the next sample from its
    stored library (target = item under the mouse, never the selection);
  * Next/Previous — replace the selected item's source in place.
  Each operation is a single undo step.
- Match the surrounding style: 4-space indent, `local function` declarations,
  lowercase names, snake-case config keys.

## 6. Development workflow

1. **Read** `AGENTS.md`, `docs/architecture.md` and the relevant source.
2. **Modify** `scripts/InsertRandomSFX.lua` (core), the wrappers
   (`InsertRandomSFXAtMouse.lua`, `NextSample.lua`, `PreviousSample.lua`), or
   the settings window (`InsertRandomSFX_Settings.lua`), or add files under
   `scripts/`. Keep all scripts in the same directory: the wrappers load the
   core by relative path and the settings window writes
   `InsertRandomSFX_Settings.ini` there.
3. **Run the automated tests** from the repository root:

   ```sh
   lua tests/run_tests.lua
   ```

   These cover the pure logic only and require Lua 5.3+ but not REAPER.
   Also syntax-check every script:

   ```sh
   luac -p scripts/InsertRandomSFX.lua
   luac -p scripts/InsertRandomSFXAtMouse.lua
   luac -p scripts/NextSample.lua
   luac -p scripts/PreviousSample.lua
   luac -p scripts/InsertRandomSFX_Settings.lua
   ```

   The REAPER APIs (insertion, edit cursor, metadata, project state, source
   replacement) cannot be unit-tested outside REAPER.
4. **Test inside REAPER** for anything touching the real API. DAW behaviour
   cannot be validated outside REAPER. Follow the manual test cases in
   `docs/development.md`.
5. **Document** behaviour changes in `README.md`, and update
   `docs/architecture.md` when the architecture or extension points change.
6. **Update `docs/roadmap.md`** when something moves between "planned" and
   "done", or when scope changes.
7. Keep commits small and focused; explain the REAPER-side verification you
   performed.

If you change `CONFIG` keys or the settings-file format, update the README's
configuration/settings section and the tests at the same time.

## 7. Future direction

These are **ideas, not requirements**. Do not implement them unless the task
explicitly asks. Ordered roughly by the phases in `docs/roadmap.md`.

- **Configurable category mapping** — ✅ implemented:
  `InsertRandomSFX_Settings.ini` in a data file plus the `SFX: Settings` window.
  (Multiple inline categories were Phase 1.)
- **Additional mouse contexts** — item edge / fade / "Media item bottom half"
  bindings, only if a real workflow needs them. (Alt+left-click on the Track and
  Media item contexts is already implemented — Phase 3.)
- **Transient / peak detection** — optionally snap an inserted item to a nearby
  transient.
- **Randomisation improvements** — optional history and weighted selection.
  (Immediate-repeat avoidance is already implemented — Phase 2.)
- **Subfolders** — optional recursive lookup within a category folder.
- **Configuration levels** — project-specific config, per-user/global library
  config. (Global config is done; per-project is still open.)
- **Preview** — audition before/after insertion.
- **Parameter randomisation** — random gain, pitch, pan.
- **Batch insertion** — several items at once.
- **Metadata-driven filtering** — read tags/notes for filtering.
- **UI/settings** — ✅ implemented as the `SFX: Settings` window.
- **Native extension** — only if ReaScript eventually proves insufficient for
  the workflow (for example, true mouse hooks). Explicitly out of scope now.
