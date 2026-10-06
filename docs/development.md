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
scripts/InsertRandomSFX.lua   the runtime ReaScript (single file)
tests/run_tests.lua           unit tests for the pure logic
docs/                         architecture, development, roadmap
```

## Loading the script in REAPER

1. Open the repository in an editor of your choice.
2. In REAPER: **Actions → Show action list… → New action → Load ReaScript…**
3. Choose `scripts/InsertRandomSFX.lua`.
4. Optionally assign a keyboard shortcut (right-click the action).

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

This loads `scripts/InsertRandomSFX.lua` in a special test mode
(`_G.SFX_TEST_MODE = true`), which makes the script return its pure helper table
instead of executing `main()`. The tests cover extension parsing, format
filtering, path joining, category resolution (including case-insensitivity),
file listing with an injected fake enumerator, and folder-existence detection.

Also worth running as a syntax gate:

```sh
luac -p scripts/InsertRandomSFX.lua
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

Run these inside REAPER. They mirror the acceptance criteria of the MVP.

| # | Scenario | Setup | Expected |
| --- | --- | --- | --- |
| 1 | Happy path | Track named `transition` selected, cursor placed, folder has several supported files | One random file inserted at the cursor on that track; no dialog |
| 2 | Case-insensitive | Repeat #1 with track named `Transition`, then `TRANSITION` | Same behaviour each time |
| 3 | No selected track | Deselect all tracks, run the action | Clear "No track selected." dialog; nothing inserted |
| 4 | Wrong track | Select a track named `dialogue`, run the action | "Selected track is not a supported category." dialog; nothing inserted |
| 5 | Missing folder | Point `CONFIG` at a non-existent path, run | "The transition folder does not exist…" dialog; nothing inserted |
| 6 | Empty folder | Point `CONFIG` at an existing empty folder, run | "No supported audio files found…" dialog; nothing inserted |
| 7 | Unsupported files | Folder contains only `.txt`/images (and/or subfolders), run | Same "no supported audio files" dialog; subfolders/files ignored |
| 8 | Undo | Perform #1, then press `Ctrl+Z` once | The inserted item is removed in one step; cursor/selection unchanged |
| 9 | Multiple invocations | Move the cursor and run several times | Each run inserts an independent item at its own cursor position |

Additional checks worth doing once:

- Run with the track **unnamed** → treated as unsupported category (error).
- Run with a folder containing mixed-case extensions (`KICK.WAV`) → included.
- Confirm a **single** undo entry named `Insert Random Transition` appears in
  **Edit → Undo History**.

## Reporting a change

When you change behaviour:

1. Update the automated tests and run them.
2. Update `README.md` if usage/configuration changed.
3. Update `docs/architecture.md` if the structure or extension points changed.
4. Update `docs/roadmap.md` if scope moved.
5. State clearly in your commit/PR what you verified **in REAPER** and what you
   only verified statically.
