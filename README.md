# REAPER Random SFX Inserter

A tiny REAPER ReaScript that drops a random sound effect onto a track, chosen
by the track's name, either at the edit cursor or directly at the mouse.

> **Status: Phase 3 (fast interaction) in progress.** Five categories
> (`transition`, `gun`, `impact`, `whoosh`, `footstep`) and two workflows —
> standard action and **Alt+click in the Arrange View** — are implemented. See
> [Current status](#current-status) and the [roadmap](docs/roadmap.md).

## What it does

In a sound-design session you often know *what* you want ("a transition here")
but not *which* file. Instead of opening a browser and auditioning, you point at
where the sound belongs and press a key or Alt+click. The script looks at the
track's name, treats it as a **category**, finds that category's folder, picks a
random supported audio file, and inserts it as a normal REAPER media item.

There are two workflows, sharing one implementation.

**Standard action** — selected track + edit cursor:

```text
selected track name
       ↓
category_folders lookup
       ↓
configured folder
       ↓
random audio file
       ↓
insert at edit cursor
```

**Fast mouse workflow** — track + time under the mouse, edit cursor untouched:

```text
mouse position in the Arrange View
       ↓
track under mouse  +  time under mouse (from mouse X)
       ↓
category_folders lookup  ->  configured folder
       ↓
random audio file
       ↓
insert at the mouse time on the mouse track
```

Several categories ship out of the box:

```text
track "transition"  ->  Transitions folder
track "gun"         ->  Guns folder
track "impact"      ->  Impacts folder
track "whoosh"      ->  Whooshes folder
track "footstep"    ->  Footsteps folder
```

Adding more categories is a configuration change, not a rewrite. See
[`docs/architecture.md`](docs/architecture.md).

## Current status

This is an intentionally small, dependency-free project:

- ✅ Five categories: `transition`, `gun`, `impact`, `whoosh`, `footstep`.
- ✅ Case-insensitive track-name matching.
- ✅ Random selection from a configured folder.
- ✅ Standard action: selected track + edit cursor, single undo step.
- ✅ Fast mouse workflow: **Alt+left-click** in the Arrange View inserts at the
  mouse time on the track under the mouse, **without moving the edit cursor**.
- ✅ Clear error messages, silent success.
- ❌ No GUI, no database, no transient detection, no advanced randomisation.
  (Those are future phases — see [`docs/roadmap.md`](docs/roadmap.md).)

## Requirements

- REAPER 6.x or 7.x (any version with the Lua ReaScript API used here).
- One folder per category you want to use, each containing that category's
  audio files.
- No Python, no Node.js, no external Lua modules. Lua is embedded in REAPER.

## Installation

Two scripts are provided. Keep them **in the same folder** (the mouse wrapper
loads `InsertRandomSFX.lua` from its own directory).

1. In REAPER, open **Actions → Show action list…**
2. Click **New action → Load ReaScript…** and select
   `scripts/InsertRandomSFX.lua` (the standard action).
3. Click **New action → Load ReaScript…** again and select
   `scripts/InsertRandomSFXAtMouse.lua` (the Alt+click workflow).
4. (Optional) Right-click the standard action and assign a keyboard shortcut or
   toolbar button.
5. For the Alt+click workflow, configure the mouse modifiers (see
   [Fast mouse workflow](#fast-mouse-workflow-altclick)).

Both scripts have no dependencies; Lua is embedded in REAPER.

> Tip: REAPER's action list can store the scripts wherever you keep your
> ReaScripts. If you edit a file later, reload it from the action list (or use
> `Ctrl+S` in the built-in editor if you open it there).

## Configuration

Everything user-editable lives in the `CONFIG` table at the very top of
`scripts/InsertRandomSFX.lua`.

The important part is `category_folders`. **The left-hand key is the REAPER
track name (the category); the right-hand value is the folder on disk:**

```lua
category_folders = {
    transition = "D:/SFX/Transitions",
    gun        = "D:/SFX/Guns",
    impact     = "D:/SFX/Impacts",
    whoosh     = "D:/SFX/Whooshes",
    footstep   = "D:/SFX/Footsteps",
}
```

For example, `gun = "D:/SFX/Guns"` means:

> A selected REAPER track named `gun` uses audio files from `D:/SFX/Guns`.

The paths shown are **placeholders** — point them at real folders on your
machine before using the script.

Rules and tips:

- Use an **absolute path** for each folder.
- Prefer **forward slashes** (`/`) on all platforms. They work on Windows too:
  `D:/SFX/Guns` is equivalent to `D:\SFX\Guns` but avoids Lua backslash
  escaping. On macOS: `/Users/you/SFX/Guns`.
- The script does **not** search subfolders; only the folder itself is used.
- Track names are matched **case-insensitively**, so `gun`, `Gun` and `GUN` all
  resolve to the `gun` category. Matching is exact (no partial matching): a
  track named `guns` is not the same as `gun`.
- A selected track whose name is not a key here is rejected with a clear
  message and nothing is inserted.
- Add a category by adding a row, for example `door = "D:/SFX/Doors"`.
- After editing, make sure REAPER reloads the script (re-run it from the action
  list, or reopen it if you edited it in REAPER's editor).

The other `CONFIG` fields are `supported_extensions` (which file types count as
audio) and `undo_prefix` (the undo label). You normally don't need to change
them.

## Usage

Both workflows share the same category configuration. Name a track after a
configured category (`transition`, `gun`, `impact`, `whoosh`, `footstep`, or one
you added).

### Standard action (selected track + edit cursor)

1. Select the track.
2. Put the edit cursor where you want the sound.
3. Run the `InsertRandomSFX.lua` action (shortcut or toolbar).
4. A random supported audio file from that category's folder is inserted at the
   cursor.

### Fast mouse workflow (Alt+click)

This is the fastest way to work: never leave the Arrange View.

1. Move the mouse over the target track at the exact time you want the sound.
2. **Alt+left-click.**

The script resolves the track under the mouse and the project time under the
mouse (from the mouse's X position), picks a random file for that track's
category, and inserts it there. **The edit cursor is not moved.**

One-time mouse-modifier setup (required), in
**Preferences → Editing Behavior → Mouse Modifiers**:

| Context | Behavior | Modifier | Action |
| --- | --- | --- | --- |
| **Track** | left click | Alt | `InsertRandomSFXAtMouse.lua` |
| **Media item** | left click | Alt | `InsertRandomSFXAtMouse.lua` |

Both contexts are required because REAPER hit-tests left clicks differently:
empty track lane uses the **Track** context, while a click over a media item
uses the **Media item** context. Assigning the same script to both makes
Alt+click behave identically in either case.

Selecting the track under the mouse is part of this workflow (the importer
inserts on the current track). That selection change is intentional and is not
an undo step.

For example, a track named `impact` pulls a random file from the folder mapped
to `impact`; a track named `whoosh` pulls from the `whoosh` folder.

Success is silent (no dialog); nothing is shown unless there is an error.

Errors you may see:

| Situation | Message |
| --- | --- |
| No track selected (standard action) | "No track selected." |
| No track under the mouse (Alt+click) | "No track under the mouse." |
| Track isn't a known category | "Selected track is not a supported category." |
| Folder doesn't exist | "The <category> folder does not exist: …" |
| Folder has no supported audio | "No supported audio files found …" |
| Insertion failed | "Failed to insert the selected file: …" |

If anything goes wrong, `Ctrl+Z` (a single undo) removes an inserted item.

## Limitations

Deliberately **not** implemented yet:

- No subfolder scanning.
- Plain uniform random selection (no "avoid immediate repeat", no weighting).
- No GUI / settings dialog.
- No transient detection, no snap-to-transient.
- The Alt+click workflow covers the **Track** and **Media item** contexts only.
  Alt+click on some item sub-contexts (item edge, fade/autocrossfade, and
  "Media item bottom half" if enabled) may use a different REAPER mouse context
  and may require an additional binding in a future task.
- No random gain/pitch/pan, no fades, no trimming.
- No project-specific or global config; the folder is edited in the script.
- Folder existence is checked with REAPER's directory APIs (no direct
  `stat`), which is sufficient but not a full filesystem abstraction.

## Development & testing

Automated tests cover the pure (non-REAPER) logic and need Lua 5.3+ but not
REAPER:

```sh
lua tests/run_tests.lua
```

DAW behaviour must be tested manually inside REAPER. The full procedure and
manual test cases are in [`docs/development.md`](docs/development.md).

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) for the staged plan (categories, better
randomisation, fast interaction, production workflow, and when/if to move beyond
ReaScript).

## License

MIT — see [`LICENSE`](LICENSE).
