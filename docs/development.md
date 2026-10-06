# Development

How to develop and test the script. Because this is a DAW integration, a large
part of testing necessarily happens **inside REAPER**. The pure logic, however,
is unit-tested outside REAPER.

## Required software

- **REAPER 6.x / 7.x** — the runtime target. Lua is embedded; nothing else is
  needed to *run* the script.
- **Lua 5.3+** (optional, for the automated tests) — only for development. On
  Windows/macOS/Linux, `lua` from your package manager is fine. REAPER itself
  ships Lua 5.4, so avoid features newer than that in the runtime script.
- A **folder of audio files** to test with (a handful of `.wav` files is
  enough), and a few non-audio files to confirm they are ignored.

No other dependencies. Do not add any.

## Repository layout

```text
scripts/InsertRandomSFX.lua        core module + standard action
scripts/InsertRandomSFXAtMouse.lua Alt+click wrapper (loads the core module)
tests/run_tests.lua                unit tests for the pure logic
docs/                              architecture, development, roadmap
```

## Loading the scripts in REAPER

1. Open the repository in an editor of your choice.
2. In REAPER: **Actions → Show action list… → New action → Load ReaScript…**
   and choose `scripts/InsertRandomSFX.lua`.
3. Repeat for `scripts/InsertRandomSFXAtMouse.lua`. Keep both files in the same
   folder — the wrapper loads the core module from its own directory.
4. Optionally assign a keyboard shortcut to the standard action.

### Mouse-modifier setup for the Alt+click workflow

In **Preferences → Editing Behavior → Mouse Modifiers**, assign
`InsertRandomSFXAtMouse.lua` to **both**:

- Context **Track**, behavior **left click**, modifier **Alt**
- Context **Media item**, behavior **left click**, modifier **Alt**

Two bindings are required because REAPER hit-tests left clicks differently over
empty track lane vs. over a media item. Item edge / fade / "Media item bottom
half" are separate contexts and are intentionally not bound yet.

### The fast edit loop

- Preferred: edit the file in your external editor, then re-run the action from
  the action list (or press the shortcut). REAPER re-reads the file each time.
- Alternatively, open the script from the action list in REAPER's built-in
  editor (`Edit action…`) and press `Ctrl+S` then run. REAPER's editor does not
  have great tooling, so external editing plus a shortcut is usually faster.

## Automated tests (no REAPER required)

From the repository root:

```sh
lua tests/run_tests.lua
```

This loads `scripts/InsertRandomSFX.lua` as a module
(`_G.SFX_LOAD_AS_MODULE = true`), which makes it return its helper table instead
of executing `main()`. The tests cover extension parsing, format filtering, path
joining, category resolution (including case-insensitivity), file listing with an
injected fake enumerator, folder-existence detection, and that the shared
`insertRandomForTrackAtPosition` entry point is exported.

The mouse/time APIs cannot be unit-tested outside REAPER — they are covered by
the manual test cases below. Also run the syntax gate on both scripts:

```sh
luac -p scripts/InsertRandomSFX.lua
luac -p scripts/InsertRandomSFXAtMouse.lua
```

If you add pure logic, add tests for it. If a helper needs the REAPER API,
prefer making its API dependency injectable (as the enumerators already are)
instead of testing it only manually.

## Inspecting errors and output inside REAPER

- **Script errors** (Lua runtime/syntax errors) appear in a dialog and are also
  written to the REAPER console. Open it with
  **Actions → Show action list → (search "Show console")**, or run the action
  *"Show REAPER console"*.
- **Our error messages** are shown with `reaper.ShowMessageBox`, so they appear
  as a normal REAPER dialog. Success shows nothing by design.
- For quick debugging, temporarily add `reaper.ShowConsoleMsg("...\n")` calls;
  remember to remove them before committing.
- If a script seems to cache an old version, re-run it from the action list
  (REAPER reloads the file each run).

## Manual test cases

Run these inside REAPER. They mirror the acceptance criteria of the project.

| # | Scenario | Setup | Expected |
| --- | --- | --- | --- |
| 1 | Happy path | Track named `transition` selected, cursor placed, folder has several supported files | One random file inserted at the cursor on that track; no dialog |
| 2 | Category routing | Repeat #1 for tracks named `gun`, `impact`, `whoosh`, `footstep` (each with its own folder) | Each category pulls from its own folder; e.g. `impact` never uses the `gun` folder |
| 3 | Case-insensitive | Repeat #1 with track named `Transition`, `Gun`, `IMPACT`, etc. | Same behaviour each time |
| 4 | No selected track | Deselect all tracks, run the action | Clear "No track selected." dialog; nothing inserted |
| 5 | Wrong track | Select a track named `dialogue`, run the action | "Selected track is not a supported category." dialog; nothing inserted |
| 6 | Missing folder | Point a category's `CONFIG` path at a non-existent folder, run | "The <category> folder does not exist…" dialog; nothing inserted |
| 7 | Empty folder | Point a category's `CONFIG` path at an existing empty folder, run | "No supported audio files found…" dialog; nothing inserted |
| 8 | Unsupported files | Folder contains only `.txt`/images (and/or subfolders), run | Same "no supported audio files" dialog; subfolders/files ignored |
| 9 | Undo | Perform #1, then press `Ctrl+Z` once | The inserted item is removed in one step; cursor/selection unchanged |
| 10 | Multiple invocations | Move the cursor and run several times | Each run inserts an independent item at its own cursor position |

Additional checks worth doing once:

- Run with the track **unnamed** → treated as unsupported category (error).
- Run with a folder containing mixed-case extensions (`KICK.WAV`) → included.
- Confirm a **single** undo entry named `Insert Random <Category>` (e.g.
  `Insert Random Gun`) appears in **Edit → Undo History**.

## Fast mouse workflow (Alt+click) test cases

These require the mouse modifiers to be configured first (see above). They
cannot be automated outside REAPER.

| # | Scenario | Setup / action | Expected |
| --- | --- | --- | --- |
| A | Empty track lane | Hover an empty spot on a `transition` track, Alt+left-click | Random transition file inserted at the mouse time on that track |
| B | Existing media item | Hover over an existing item, Alt+left-click | Random file inserted at the mouse time on that item's track (existing item untouched) |
| C | Edit cursor | Note `Edit cursor` position, Alt+click, note it again | **Identical** before and after; only the item is added |
| D | Multiple tracks | Select track A, then Alt+click a different track B | SFX uses track B's category and lands on B, not A |
| E | Zoom / scroll | Repeat A at several horizontal zoom levels and scroll positions | Insert time always matches the mouse X exactly |
| F | Undo | Alt+click, then `Ctrl+Z` once | The inserted item is removed in a single undo; edit cursor still unchanged |
| G | Standard action regression | Select a `transition` track, place the cursor, run `InsertRandomSFX.lua` | Behaves exactly as before (selected track + edit cursor) |

Additional mouse checks worth doing once:

- Alt+click over a track whose name is not a configured category → clear
  "not a supported category" dialog, nothing inserted.
- Alt+click below the last track (no track under mouse) → clear
  "No track under the mouse." dialog.
- Confirm the Alt+click insertion is a **single** undo entry and that selecting
  the track under the mouse did **not** create its own undo step.
- Note the known gap: Alt+click on an item **edge** or **fade** may not fire
  (separate REAPER context). This is expected for now.

## Reporting a change

When you change behaviour:

1. Update the automated tests and run them.
2. Update `README.md` if usage/configuration changed.
3. Update `docs/architecture.md` if the structure or extension points changed.
4. Update `docs/roadmap.md` if scope moved.
5. State clearly in your commit/PR what you verified **in REAPER** and what you
   only verified statically.
