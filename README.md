# REAPER Random SFX Inserter

A tiny, dependency-free REAPER ReaScript toolkit that drops a random sound
effect onto a track, chosen by the track's name, and lets you browse through the
same library with a mouse gesture.

> **Status: categories, mouse placement and sample browsing implemented.**
> Five categories (`transition`, `gun`, `impact`, `whoosh`, `footstep`). The
> main gesture is **Alt+left-click**: on empty track lane it inserts a random
> SFX; on an existing SFX item it replaces it with the next sample. See
> [Current status](#current-status) and the [roadmap](docs/roadmap.md).

## What it does

In a sound-design session you often know *what* you want ("a transition here")
but not *which* file. Instead of opening a browser and auditioning, you point at
where the sound belongs and press a key or Alt+click. The script looks at the
track's name, treats it as a **category**, finds that category's folder, picks a
random supported audio file, and inserts it as a normal REAPER media item.

Random insertion is data-driven:

```text
track name  ->  category_folders lookup  ->  configured folder
            ->  random audio file  ->  media item at the position
```

The same **Alt+left-click** gesture also browses: clicking an existing SFX item
replaces it with the next sample from the library recorded on that item (no
selection needed):

```text
item under mouse  ->  its stored library (P_EXT metadata)
                  ->  next file (sorted, wraps around)
                  ->  replace the item's source in place
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
- ✅ Case-insensitive, exact track-name matching.
- ✅ Random selection from a configured folder, **avoiding the immediately
  previous file** for that category (no long-term history).
- ✅ Standard action: selected track + edit cursor, single undo step.
- ✅ **Alt+left-click** in the Arrange View: on empty track lane it inserts a
  random SFX at the mouse time; on an existing SFX item it replaces the item
  with the **next** sample from that item's stored library (no selection
  needed).
- ✅ The edit cursor moves to the **start of the affected item**.
- ✅ Item-local metadata (`category`, `library`, `source`) via `P_EXT:`.
- ✅ **Next/Previous Sample** actions replace the selected item's source in
  place, keeping its exact start and using the new source's natural length.
- ✅ Clear error messages, silent success.
- ❌ No GUI, no database, no transient detection, no random gain/pitch/pan.
  (Those are future phases — see [`docs/roadmap.md`](docs/roadmap.md)).

## Requirements

- REAPER 6.x or 7.x (any version with the Lua ReaScript API used here).
- One folder per category you want to use, each containing that category's
  audio files.
- No Python, no Node.js, no external Lua modules. Lua is embedded in REAPER.

## Installation

Four scripts are provided. **Keep them in the same folder** — the action
wrappers load `InsertRandomSFX.lua` from their own directory.

| Script | REAPER action |
| --- | --- |
| `scripts/InsertRandomSFX.lua` | `SFX: Insert Random SFX` (standard action) |
| `scripts/InsertRandomSFXAtMouse.lua` | `SFX: Insert Random SFX At Mouse` (Alt+click) |
| `scripts/NextSample.lua` | `SFX: Next Sample` |
| `scripts/PreviousSample.lua` | `SFX: Previous Sample` |

1. In REAPER, open **Actions → Show action list…**
2. Click **New action → Load ReaScript…** and load each of the four scripts.
3. (Optional) Assign a keyboard shortcut or toolbar button to the standard
   action.
4. Configure the mouse modifiers / shortcuts for the workflows you want (see
   [Usage](#usage)).

The scripts have no dependencies; Lua is embedded in REAPER.

> Tip: REAPER's action list can store the scripts wherever you keep your
> ReaScripts. If you edit a file later, re-run it from the action list (or use
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
- Files are listed in a **deterministic, case-insensitive sorted order**, which
  is what Next/Previous Sample steps through.
- Track names are matched **case-insensitively**, so `gun`, `Gun` and `GUN` all
  resolve to the `gun` category. Matching is exact (no partial matching): a
  track named `guns` is not the same as `gun`.
- A selected track whose name is not a key here is rejected with a clear
  message and nothing is inserted.
- Add a category by adding a row, for example `door = "D:/SFX/Doors"`.
- After editing, make sure REAPER reloads the script (re-run it from the action
  list, or reopen it if you edited it in REAPER's editor).

The other `CONFIG` fields are `supported_extensions` (which file types count as
audio: `.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`) and `undo_prefix` (the
undo label). You normally don't need to change them.

## Usage

All workflows share the same category configuration. Name a track after a
configured category (`transition`, `gun`, `impact`, `whoosh`, `footstep`, or one
you added).

### Standard action (selected track + edit cursor)

1. Select the track.
2. Put the edit cursor where you want the sound.
3. Run the `SFX: Insert Random SFX` action (shortcut or toolbar).
4. A random supported audio file from that category's folder is inserted at the
   cursor. The edit cursor then moves to the **start** of the new item.

### Alt+left-click (insert and browse) — the main workflow

One gesture, two behaviors depending on what is under the mouse.

**Over empty track lane — insert a random SFX:**

1. Move the mouse over the target track at the exact time you want the sound.
2. **Alt+left-click.**

A random file for that track's category is inserted at the mouse time, and the
edit cursor moves to the new item's start.

**Over an existing SFX item — browse to the next sample:**

1. Move the mouse over the item (no need to select it).
2. **Alt+left-click.**

The item's source is replaced in place with the **next** file from its stored
library; the item is not moved and no new item is created. Repeated Alt+clicks
advance through the library and wrap from the last file back to the first. The
edit cursor moves to the item's start.

```text
gun_04.wav  --Alt+click-->  gun_05.wav  --Alt+click-->  gun_06.wav  ...
gun_09.wav  --Alt+click-->  gun_01.wav   (wraps)
```

Only items that carry SFX metadata (inserted by this tool) are browsed. Clicking
a plain, non-SFX media item shows a clear message and changes nothing.

One-time mouse-modifier setup (required), in
**Preferences → Editing Behavior → Mouse Modifiers**:

| Context | Behavior | Modifier | Action |
| --- | --- | --- | --- |
| **Track** | left click | Alt | `SFX: Insert Random SFX At Mouse` |
| **Media item** | left click | Alt | `SFX: Insert Random SFX At Mouse` |

Both contexts are required because REAPER hit-tests left clicks differently:
empty track lane uses the **Track** context, while a click over a media item
uses the **Media item** context. The same script handles both; it decides what
to do from the item actually under the mouse, not from the selection.

For random insertion, the track under the mouse is selected (the importer
inserts on the current track); that selection change is intentional and is not
an undo step. Browsing does not require or change the selection.

### Sample browsing

The recommended way to browse forward is **Alt+left-click on the item** (see
above) — no selection needed. The two Actions remain available and operate on
the **selected** item:

1. Select an inserted SFX item.
2. Run `SFX: Next Sample` or `SFX: Previous Sample`.

Both the Alt+click gesture and the Actions use the same logic: the item is
**not** moved and **no new item is created** — the existing item's media source
is replaced in place. Its exact start position is preserved and the new source
determines the item's **natural length** (the previous length is not kept, and
the new source is not time-stretched). Next wraps from the last file to the
first; Previous wraps from the first to the last. The item's metadata is updated
so further browsing stays in the same library.

If the item has no SFX metadata, the library cannot be resolved, or the current
source is not found in the library, nothing is changed and a clear message is
shown. A one-file library is a safe no-op.

#### Optional: Alt + mouse-wheel browsing

The Alt+click workflow above is the primary way to browse. If you also want a
wheel gesture, note that REAPER has **no "Media item → mouse wheel"
mouse-modifier context**; mouse wheel is assigned as a **shortcut in the Action
List** (select the action, click **Add**, then hold **Alt** and scroll the
wheel). REAPER sends the wheel as a relative value, so a plain action fires for
both scroll directions; to make the direction matter, build a tiny custom
action:

**New action → New custom action…**, name it e.g. `SFX: Browse Sample
(Alt+Wheel)`, and add these actions in order:

```text
1. Item: Select item under mouse cursor
2. Skip next action if CC parameter >0/mid
3. SFX: Previous Sample
4. Skip next action if CC parameter <0/mid
5. SFX: Next Sample
```

Then select the custom action, click **Add**, hold **Alt** and scroll the wheel
so it is bound to `Alt+Mousewheel`. Now:

```text
mouse over an SFX item  ->  hold Alt  ->  wheel up   -> SFX: Next Sample
mouse over an SFX item  ->  hold Alt  ->  wheel down -> SFX: Previous Sample
```

(The two `Skip next action if CC parameter …` actions are REAPER's built-in
way to branch on wheel direction; filter the Action List for `Skip next action
if CC` to find them.)

**Simpler alternative** if you don't need direction branching: select the item,
then bind `Alt+Mousewheel` to `SFX: Next Sample` and e.g.
`Alt+Shift+Mousewheel` to `SFX: Previous Sample` in the Action List.

The `SFX: Next Sample` / `SFX: Previous Sample` Actions operate on the
**selected** item, so the wheel custom action above selects the item under the
mouse first. The **Alt+left-click** workflow does not need this: it targets the
item under the mouse directly.

### Notes

- Success is silent (no dialog); nothing is shown unless there is an error.
- `Ctrl+Z` undoes each operation in a single step (insert, next, previous).

Errors you may see:

| Situation | Message |
| --- | --- |
| No track selected (standard action) | "No track selected." |
| No track under the mouse (Alt+click on empty lane) | "No track under the mouse." |
| Track isn't a known category | "Selected track is not a supported category." |
| Folder doesn't exist | "The <category> folder does not exist: …" |
| Folder has no supported audio | "No supported audio files found …" |
| Insertion failed | "Failed to insert the selected file: …" |
| No item selected (Next/Previous Action) | "No media item selected." |
| Item has no SFX metadata (Alt+click on a plain item, or Next/Previous on one) | "This item has no SFX library metadata." |
| Stored library empty/missing | "No supported audio files found in the stored library: …" |
| Current source not in library | "The item's source is not in its stored library …" |

## Item metadata

Each inserted item stores, in REAPER's native item extension state (`P_EXT:`):

| Key | Example |
| --- | --- |
| `sfx_category` | `gun` |
| `sfx_library` | `D:/SFX/Guns` |
| `sfx_source` | `D:/SFX/Guns/gun_04.wav` |

This is **item-local** state, so an existing SFX item still knows its library
even if the track is renamed. Both **Alt+left-click browsing** and the
Next/Previous Sample Actions use this metadata rather than the current track
name. Paths are stored in a canonical form (forward slashes, no trailing slash)
and compared case-insensitively.

## Edit cursor behaviour

- **Random insertion** (standard action, or Alt+click on empty track lane): the
  edit cursor is set to the new item's exact `D_POSITION` (its start), never
  derived from the source duration and never left at the item's end.
- **Alt+click on an existing SFX item**: the edit cursor is set to that item's
  start.
- The **Next/Previous Sample Actions** do not move the edit cursor (they only
  replace the source).

## Immediate-repeat prevention

Random selection will not pick the same file twice in a row for the same
category. The previous pick is remembered per category in **project state**
(`SetProjExtState`, saved in the `.RPP`), so it survives separate script runs
and is independent for each category:

```text
gun    -> gun_03.wav
impact -> impact_07.wav   (unaffected by the gun pick)
```

Allowed: `gun_01, gun_03, gun_01, gun_02`. Not allowed: `gun_01, gun_01`.

If a library has only one file, that file may be inserted repeatedly (no error).
Otherwise the remaining candidates are chosen uniformly. There is no long-term
history or shuffle bag.

## Limitations

Deliberately **not** implemented yet:

- No subfolder scanning.
- No long-term randomisation history / weighting (only immediate-repeat
  avoidance).
- No GUI / settings dialog.
- No transient detection, no snap-to-transient.
- The **Next/Previous Sample Actions** operate on the **selected** item. The
  Alt+left-click gesture targets the item under the mouse and needs no
  selection.
- REAPER has no media-item mouse-wheel mouse-modifier context; the optional
  Alt+wheel setup is Action-List based (see above).
- The Alt+click workflow covers the **Track** and **Media item** contexts only.
  Alt+click on some item sub-contexts (item edge, fade/autocrossfade, and
  "Media item bottom half" if enabled) may use a different REAPER mouse context
  and may require an additional binding in a future task.
- Next/Previous reset the take's start offset and play rate so the new source
  plays at its natural length (no time-stretch); other item/take properties
  (volume, pan, mute, position) are preserved.
- No random gain/pitch/pan, no fades, no trimming.
- No project-specific or global config; the folder is edited in the script.
- Folder existence is checked with REAPER's directory APIs (no direct `stat`),
  which is sufficient but not a full filesystem abstraction.

## Development & testing

Automated tests cover the pure (non-REAPER) logic and need Lua 5.3+ but not
REAPER:

```sh
lua tests/run_tests.lua
```

DAW behaviour must be tested manually inside REAPER. The full procedure and
manual test cases are in [`docs/development.md`](docs/development.md).

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) for the staged plan.

## License

MIT — see [`LICENSE`](LICENSE).
