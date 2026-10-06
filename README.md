# REAPER Random SFX Inserter

A tiny REAPER ReaScript that drops a random sound effect onto a track, chosen
by the track's name, at the edit cursor.

> **Status: MVP / prototype.** One category (`transition`) is implemented. See
> [Current status](#current-status) and the [roadmap](docs/roadmap.md).

## What it does

In a sound-design session you often know *what* you want ("a transition here")
but not *which* file. Instead of opening a browser and auditioning, you put the
edit cursor where the sound belongs and press a key. The script looks at the
selected track's name, treats it as a **category**, finds that category's
folder, picks a random supported audio file, and inserts it as a normal REAPER
media item at the cursor.

The long-term vision is a whole vocabulary of categories:

```text
track "transition"  ->  Transitions folder
track "gun"         ->  Guns folder
track "impact"      ->  Impacts folder
track "whoosh"      ->  Whooshes folder
track "footstep"    ->  Footsteps folder
```

Only `transition` exists right now, but the code is built so adding categories
is a configuration change, not a rewrite. See
[`docs/architecture.md`](docs/architecture.md).

## Current status

This is an **MVP**. It is intentionally small and dependency-free:

- ✅ One category: `transition`.
- ✅ Case-insensitive track-name matching.
- ✅ Random selection from a configured folder.
- ✅ Inserts at the edit cursor as a single undo step.
- ✅ Clear error messages, silent success.
- ❌ No GUI, no database, no mouse modifiers, no advanced randomisation.
  (Those are future phases — see [`docs/roadmap.md`](docs/roadmap.md).)

## Requirements

- REAPER 6.x or 7.x (any version with the Lua ReaScript API used here).
- A folder of transition audio files on your machine.
- No Python, no Node.js, no external Lua modules. Lua is embedded in REAPER.

## Installation

1. In REAPER, open **Actions → Show action list…**
2. Click **New action → Load ReaScript…**
3. Select `scripts/InsertRandomSFX.lua` from this repository.
4. (Optional but recommended) Right-click the new action and choose
   **Duplicate**/*Set shortcut* to bind a key or add it to a toolbar.

That's it — the script is a single file and has no dependencies.

> Tip: REAPER's action list can store the script wherever you keep your
> ReaScripts. If you edit the file later, reload it from the action list (or use
> `Ctrl+S` in the built-in editor if you open it there).

## Configuration

Everything user-editable lives in the `CONFIG` table at the very top of
`scripts/InsertRandomSFX.lua`.

```lua
local CONFIG = {
    category_folders = {
        transition = "C:/SFX/Transitions",
    },
    supported_extensions = {
        wav = true, aif = true, aiff = true,
        flac = true, ogg = true, mp3 = true,
    },
    undo_prefix = "Insert Random ",
}
```

Change `transition` to point at **your** transitions folder:

- Use an **absolute path**.
- Prefer **forward slashes** (`/`) on all platforms. They work on Windows too:
  `C:/SFX/Transitions` is equivalent to `C:\SFX\Transitions` but avoids Lua
  backslash escaping. On macOS: `/Users/you/SFX/Transitions`.
- The script does **not** search subfolders; only the folder itself is used.
- After editing, make sure REAPER reloads the script (reload from the action
  list, or reopen it if you edited it in REAPER's editor).

To add a category later, add a row and a track-name match:

```lua
category_folders = {
    transition = "C:/SFX/Transitions",
    gun        = "C:/SFX/Guns",
},
```

The track name is matched case-insensitively against the category keys, so
`transition`, `Transition` and `TRANSITION` all resolve to `transition`.

## Usage

The exact MVP workflow:

1. Create or select a track and name it `transition`.
2. Select that track (click it).
3. Put the edit cursor where you want the sound.
4. Run the action (shortcut or toolbar).
5. A randomly chosen supported audio file is inserted at the cursor.

The script does **not** move the edit cursor after insertion, and success is
silent (no dialog). Nothing is shown unless there is an error.

Errors you may see:

| Situation | Message |
| --- | --- |
| No track selected | "No track selected." |
| Selected track isn't a known category | "Selected track is not a supported category." |
| Folder doesn't exist | "The transition folder does not exist: …" |
| Folder has no supported audio | "No supported audio files found …" |
| Insertion failed | "Failed to insert the selected file: …" |

If anything goes wrong, `Ctrl+Z` (a single undo) removes an inserted item.

## Limitations

Deliberately **not** implemented yet:

- Only one category (`transition`).
- No subfolder scanning.
- Plain uniform random selection (no "avoid immediate repeat", no weighting).
- No GUI / settings dialog.
- No mouse-modifier (Ctrl/Shift/Alt-click) interaction.
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
