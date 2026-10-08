# Development

How to develop and test the scripts. Because this is a DAW integration, a large
part of testing necessarily happens **inside REAPER**. The pure logic, however,
is unit-tested outside REAPER.

## Required software

- **REAPER 6.x / 7.x** — the runtime target. Lua is embedded; nothing else is
  needed to *run* the scripts.
- **Lua 5.3+** (optional, for the automated tests) — only for development. On
  Windows/macOS/Linux, `lua` from your package manager is fine. REAPER itself
  ships Lua 5.4, so avoid features newer than that in the runtime scripts.
- A **folder of audio files** to test with (a handful of `.wav` files of
  **different lengths** is ideal), plus a few non-audio files to confirm they
  are ignored.

No other dependencies. Do not add any.

## Repository layout

```text
scripts/InsertRandomSFX.lua        core module + standard action
scripts/InsertRandomSFXAtMouse.lua Alt+click wrapper (loads the core module)
scripts/NextSample.lua             "SFX: Next Sample" wrapper
scripts/PreviousSample.lua         "SFX: Previous Sample" wrapper
scripts/SFXSettings.lua            "SFX: Settings" gfx window (config editor)
scripts/InsertRandomSFX_Settings.ini          created by the settings window (not committed)
tests/run_tests.lua                unit tests for the pure logic
docs/                              architecture, development, roadmap
```

## Loading the scripts in REAPER

1. Open the repository in an editor of your choice.
2. In REAPER: **Actions → Show action list… → New action → Load ReaScript…**
   and load all five scripts.
3. Keep all five files in the **same folder** — the wrappers load the core
   module from their own directory and the settings window writes its file next
   to them.
4. Optionally assign a keyboard shortcut to the standard action.

### Mouse-modifier setup for the Alt+click workflow

In **Preferences → Editing Behavior → Mouse Modifiers**, assign
`SFX: Insert Random SFX At Mouse` to **both**:

- Context **Track**, behavior **left click**, modifier **Alt**
- Context **Media item**, behavior **left click**, modifier **Alt**

Two bindings are required because REAPER hit-tests left clicks differently over
empty track lane vs. over a media item. Item edge / fade / "Media item bottom
half" are separate contexts and are intentionally not bound yet.

### Alt + mouse-wheel setup for sample browsing

REAPER has **no media-item mouse-wheel mouse-modifier context**; mouse wheel is
assigned as a shortcut in the Action List. Recommended:

1. **New action → New custom action…**, name it `SFX: Browse Sample
   (Alt+Wheel)`, and add in order:
   `Item: Select item under mouse cursor`,
   `Skip next action if CC parameter >0/mid`,
   `SFX: Previous Sample`,
   `Skip next action if CC parameter <0/mid`,
   `SFX: Next Sample`.
2. Select the custom action, click **Add**, hold **Alt** and scroll the wheel.

Simpler alternative: bind `Alt+Mousewheel` to `SFX: Next Sample` and
`Alt+Shift+Mousewheel` to `SFX: Previous Sample`, selecting the item first.
See `README.md` for details.

### The fast edit loop

- Preferred: edit the file in your external editor, then re-run the action from
  the action list (or press the shortcut). REAPER re-reads the file each time.
- Alternatively, open a script from the action list in REAPER's built-in editor
  (`Edit action…`) and press `Ctrl+S` then run. External editing plus a shortcut
  is usually faster.

## Automated tests (no REAPER required)

From the repository root:

```sh
lua tests/run_tests.lua
```

This loads `scripts/InsertRandomSFX.lua` as a module
(`_G.SFX_LOAD_AS_MODULE = true`), which makes it return its helper table instead
of executing `main()`. Coverage includes:

- extension parsing and format filtering;
- path joining and **canonicalization** (backslashes, duplicate/trailing
  slashes, case-insensitive `pathsEqual`);
- deterministic **sorting** of file lists;
- category resolution (case-insensitive, exact);
- file listing with an injected fake enumerator (subfolders/unsupported files
  ignored, sorted, repeatable);
- folder-existence detection;
- **immediate-repeat avoidance** (`chooseRandomIndex`);
- **browse stepping** with wrap-around and safe handling of an unknown/one-file
  library (`findPathIndex` + `browseIndex`), i.e. the same composition
  `browseSample(item, direction)` performs;
- **settings-file parsing/serialization** (`parseCategories` /
  `serializeCategories` / `normalizeCategoryName` / `applyCategoryRows`), the
  same helpers `SFXSettings.lua` uses;
- stored-state identifiers and the exported shared functions
  (`insertRandomForTrackAtPosition`, `browseSample`, `browseSelectedSample`,
  `setEditCursorToItemStart`).

The REAPER APIs (insertion, edit cursor, `P_EXT:` metadata, `SetProjExtState`,
source replacement) and the item-under-mouse hit-test (`GetItemFromPoint`)
cannot be unit-tested outside REAPER — they are covered by the manual test cases
below. Also run the syntax gate on every script:

```sh
luac -p scripts/InsertRandomSFX.lua
luac -p scripts/InsertRandomSFXAtMouse.lua
luac -p scripts/NextSample.lua
luac -p scripts/PreviousSample.lua
luac -p scripts/SFXSettings.lua
```

If you add pure logic, add tests for it. If a helper needs the REAPER API,
prefer making its API dependency injectable (as the enumerators already are)
instead of testing it only manually.

## Inspecting errors and output inside REAPER

- **Script errors** (Lua runtime/syntax errors) appear in a dialog and are also
  written to the REAPER console. Open it with
  **Actions → Show action list → (search "Show console")**.
- **Our error messages** are shown with `reaper.ShowMessageBox`. Success shows
  nothing by design.
- For quick debugging, temporarily add `reaper.ShowConsoleMsg("...\n")` calls;
  remove them before committing.
- **Inspecting item metadata:** `P_EXT:` values are not shown in Item
  Properties. Save the project and search the `.RPP` for `sfx_source`, or run a
  throwaway script with
  `reaper.GetSetMediaItemInfo_String(item, "P_EXT:sfx_source", "", false)`.

## Manual test cases — insertion

| # | Scenario | Setup / action | Expected |
| --- | --- | --- | --- |
| 1 | Happy path | Track named `transition` selected, cursor placed, folder has several supported files | One random file inserted at the cursor; no dialog |
| 2 | Category routing | Repeat #1 for `gun`, `impact`, `whoosh`, `footstep` | Each category pulls from its own folder |
| 3 | Case-insensitive | Repeat #1 with `Transition`, `Gun`, `IMPACT` | Same behaviour |
| 4 | No selected track | Deselect all tracks, run the action | "No track selected." dialog; nothing inserted |
| 5 | Wrong track | Track named `dialogue`, run the action | "not a supported category" dialog; nothing inserted |
| 6 | Missing folder | Point a category at a non-existent path | "The <category> folder does not exist…" dialog |
| 7 | Empty folder | Point a category at an existing empty folder | "No supported audio files found…" dialog |
| 8 | Unsupported files | Folder has only `.txt`/images/subfolders | Same dialog; nothing inserted |
| 9 | **Edit cursor** | Note the cursor, run the action | Cursor ends at the inserted item's **start**, not its end |
| 10 | Undo | Run #1, then `Ctrl+Z` once | Item removed in one step |
| 11 | Multiple invocations | Move the cursor and run several times | Each run inserts an independent item at its position |
| 12 | **Metadata** | Insert, save project, inspect the `.RPP` | Item has `sfx_category`, `sfx_library`, `sfx_source` |
| 12b | **Take name** | Insert with a non-empty library folder | The item label shows the inserted file's name (e.g. `boom.wav`), like a normal import |
| 13 | **Immediate repeat** | With ≥2 files, insert repeatedly | Never two identical sources in a row |
| 14 | **Per-category repeat state** | Insert from `gun`, then from `impact`, then `gun` | The `impact` pick does not affect `gun`'s memory |
| 15 | **One-file library** | Category folder with a single file, insert several times | Same file inserted repeatedly; no error |
| 16 | **State persistence** | Insert, then run the action again (new script run) | The previous pick is still avoided |

## Manual test cases — settings window (`SFX: Settings`)

Run the `SFX: Settings` action. The config file (`InsertRandomSFX_Settings.ini`) lives next
to the scripts.

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| S1 | First open | Run `SFX: Settings` with no config file | Window shows the built-in defaults; status says no settings file yet |
| S2 | Add | Click Add, enter a name, pick a folder | New row appears, marked "Remember to Save" |
| S3 | Save | Click Save | `InsertRandomSFX_Settings.ini` is created next to the scripts; status confirms |
| S4 | Applies to insertion | Save new category `door`, create+select a `door` track, insert | Random file inserted from the chosen folder |
| S5 | Edit | Double-click a row, rename and re-pick the folder | Row updated |
| S6 | Remove | Select a row, click Remove | Row disappears; Save persists the removal |
| S7 | Reorder | Use Up/Down | Rows move; order is cosmetic (matching is by name) |
| S8 | Duplicate name | Add/Edit to an existing name (any case) | Refused with "already exists"; not saved |
| S9 | Empty name | Confirm empty input in the name dialog | Not added; clear status |
| S10 | Missing folder | Add a row whose folder does not exist, Save | Warning listing the folder(s); Save anyway / cancel |
| S11 | Reload | Edit the `.ini` externally, click Reload | Window reflects the file; unsaved changes discarded |
| S12 | Dirty close | Make a change, click Close | Asks to discard; Cancel keeps the window open |
| S13 | ESC / window close | Press ESC or close the OS window | Window closes without saving |
| S14 | Long list | Add more rows than fit | Mouse wheel scrolls; selection stays visible |
| S15 | Read-only folder | Point the script dir at a read-only location, Save | Clear write-error status; nothing else changes |

## Manual test cases — sample browsing

Requires at least three files of **different lengths** in the library, and a
selected item inserted by this tool.

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| B1 | Next | Select the item, run `SFX: Next Sample` | Source becomes the next file in sorted order; item count unchanged |
| B2 | Previous | Run `SFX: Previous Sample` | Source becomes the previous file |
| B3 | Next wrap | At the last file, run Next | Wraps to the first file |
| B4 | Previous wrap | At the first file, run Previous | Wraps to the last file |
| B5 | **Position preserved** | Note the item start, browse | `D_POSITION` is exactly unchanged |
| B6 | **Natural length** | Browse to a longer/shorter file | Item length becomes the new source's length (not the old one, not truncated) |
| B7 | **Metadata updated** | Browse, inspect `.RPP` | `sfx_source` reflects the new file; `sfx_library` unchanged |
| B7b | **Take name updated** | Browse to a different file | The item label shows the new file's name |
| B8 | Undo | Browse, then `Ctrl+Z` once | One step restores the previous source |
| B9 | No item selected | Deselect all items, run Next/Previous | "No media item selected." dialog; nothing changed |
| B10 | No metadata | Select a plain audio item, run Next | "This item has no SFX library metadata." dialog; nothing changed |
| B11 | One-file library | Browse an item whose library has one file | No change, no error |
| B12 | Source not found | Remove the current source file, run Next | Clear message; nothing changed |
| B13 | **Item/track preserved** | Browse | Same item, same track, no new item, volume/pan/mute unchanged |
| B14 | Alt+wheel | Use the custom action (or Alt+wheel binding) over an item | Wheel up = Next, wheel down = Previous |

## Manual test cases — Alt+click (insert and browse)

Requires the two mouse-modifier bindings (Track + Media item, Alt+left-click)
and a category track whose library has several files of different lengths.

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| A | Empty track lane | Hover empty lane on a `transition` track, Alt+left-click | Random file inserted at the mouse time; edit cursor moves to its start |
| B | Existing SFX item | Hover an item inserted by this tool, Alt+left-click | The item **plays and displays** the next library file (the source itself changes, not just the length); item count unchanged |
| C | Repeated Alt+click | Alt+click the same item several times | Advances one file each click |
| D | Last sample | Alt+click when the item is the last file | Wraps to the first file |
| E | **Item position** | Note the item start, Alt+click on it | `D_POSITION` exactly unchanged |
| F | **Item length** | Alt+click to a longer/shorter file | Item length becomes the new source's natural length (not the old one, not truncated) |
| G | **Edit cursor** | Note the cursor, Alt+click an item | Cursor ends at the item's start |
| H | Undo | Alt+click an item, then `Ctrl+Z` once | One step restores the previous sample |
| I | **Non-SFX item** | Alt+click a plain audio item with no metadata | "no SFX library metadata" dialog; source NOT replaced |
| J | **Independent targets** | Select item X, then Alt+click item Y | Y is browsed (item under mouse); X untouched |
| K | Multiple tracks | Select track A, Alt+click empty lane on track B | Uses track B's category and lands on B |
| L | Zoom / scroll | Repeat A at several zoom/scroll positions | Insert time matches the mouse X |
| M | Standard action regression | Run the standard action | Behaves as before |

Additional checks:

- Alt+click over a non-category track → "not a supported category" dialog.
- Alt+click below the last track → "No track under the mouse." dialog.
- Alt+clicking an item does **not** require or change the item selection.
- One Alt+click browse is a **single** undo step; hit-testing/selection adds no
  undo point.
- **Source-replacement regression:** after browsing, the item's **waveform and
  playback** must reflect the new file, not just its length. Source creation and
  attachment are centralized in `attachSource(take, filePath)`; the post-swap
  refresh is centralized in `refreshItem(item)`. `SetMediaItemTake_Source` alone
  leaves REAPER's cached item/peak state on the previous source, so
  `refreshItem` marks the item's track dirty
  (`reaper.MarkTrackItemsDirty(track, item)` — the first argument must be a
  `MediaTrack`), then calls `reaper.UpdateItemInProject` and
  `reaper.UpdateArrange`. The old `PCM_source` is intentionally **not**
  destroyed (REAPER may still reference it; freeing it corrupted playback in
  testing).
- **Insertion must not disturb playback:** insertion creates the item directly
  and does **not** use `reaper.InsertMedia`, which moves the edit/play cursor to
  the end of the inserted item. See the playback regression tests below.
- One-file library → Alt+click leaves the item unchanged (safe no-op).
- Stored library missing / current source not in library → clear message,
  nothing changed.
- Known gap: Alt+click on an item **edge** or **fade** may not fire (separate
  REAPER context). Expected for now.

## Manual test cases — playback and waveform (regression)

These cover the two runtime regressions (playback stopping, stale waveform).
They require REAPER and cannot be checked by the Lua tests.

Playback:

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| P-A | Baseline | Empty project (no SFX items), press Play | Playback runs normally |
| P-B | Insert while stopped | Insert an SFX, press Play | Edit cursor is at the item start; playback starts and runs |
| P-C | Through the item | Play from before the item | Playback continues through the item and beyond (does not stop at/inside it) |
| P-D | After the item | Move the edit cursor after the item, press Play | Playback starts and continues normally |
| P-E | Insert while playing | Insert an SFX during playback | Playback does not stop, rewind or seek |
| P-F | Browse while playing | Alt+click an existing SFX during playback | Playback does not stop, rewind or seek |
| P-G | Content after the item | Put real media after the SFX, play through | Playback passes the SFX and continues into the later content |

Waveform:

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| W-A | Source changes | Alt+click an SFX item | The item plays the new file |
| W-B | Waveform changes | Same as W-A | The displayed waveform is the new file's, not the old one |
| W-C | Natural length | Alt+click to a longer/shorter file | Item length becomes the new source's natural length |
| W-D | Repeated browsing | Alt+click several times | Waveform keeps up each time |
| W-E | Wrap-around | Alt+click at the last file | Wraps to the first; waveform updates |
| W-F | **Initial insert** | Insert an SFX into an empty project (ideally a file never imported before) | The waveform is drawn **immediately** — no zoom, scroll or wait needed |

Undo:

| # | Scenario | Action | Expected |
| --- | --- | --- | --- |
| U-A | One undo per insert | Insert, then `Ctrl+Z` once | The insert is undone in one step |
| U-B | Restore previous source | Browse, then `Ctrl+Z` once | The previous source is restored in one step |
| U-C | No extra undo points | Insert / browse, open Edit → Undo History | Exactly one entry per operation (none for cursor, selection or refresh) |

## Reporting a change

When you change behaviour:

1. Update the automated tests and run them.
2. Update `README.md` if usage/configuration changed.
3. Update `docs/architecture.md` if the structure or extension points changed.
4. Update `docs/roadmap.md` if scope moved.
5. State clearly in your commit/PR what you verified **in REAPER** and what you
   only verified statically.
