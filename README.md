# ReaperAutoAdd

A native REAPER ReaScript Lua tool for quickly inserting and browsing SFX based
on the selected track's configured category. Name a track after a category
(`gun`, `impact`, …), point at where the sound belongs, and one gesture inserts a
random sound from that category's folder. The same tool can browse through a
library on an existing item.

No SWS, no `js_ReaScriptAPI`, no external files — REAPER's own API only.

## Features

- **Track-name → SFX category mapping.** A track's name is treated as a category
  and resolved against the configured categories (case-insensitively).
- **In-REAPER settings window** (`InsertRandomSFX_Settings.lua`) to add, edit and remove
  categories/folders — no script editing. Stored in
  `InsertRandomSFX_Settings.ini`.
- **Random SFX insertion** from the category's folder.
- **Alt+Left Click on empty track area** → insert a random SFX at the mouse's
  timeline position.
- **Alt+Left Click on an existing SFX item** → browse to the next sample from
  that item's stored library.
- **Next Sample / Previous Sample** actions for the selected item.
- **Wrap-around browsing** (last → first and first → last).
- **No immediate random repeat** within the relevant library/category.
- **Existing-item replacement keeps:**
  - the same media item,
  - the same track,
  - the exact item position,
  - the new source's natural length,
  - `D_STARTOFFS = 0`,
  - `D_PLAYRATE = 1`.
- **Item metadata** is stored on the item, so browsing does not depend on the
  current track name.
- **Supported audio extensions:** `.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`.
- **Native ReaScript Lua only** (Lua is embedded in REAPER).

## Requirements

- **REAPER** (a version whose Lua ReaScript API includes the functions used here;
  REAPER 6.x and 7.x both work).
- **ReaScript Lua** — embedded in REAPER, nothing to install.
- **Native REAPER API only.**
- **No SWS / `js_ReaScriptAPI` dependency.**
- One folder per category you want to use, each containing that category's audio
  files.

## Installation

Five production scripts are provided. **Keep all five in the same folder** — the
action wrappers load `InsertRandomSFX.lua` from their own directory, and the
settings window writes its settings file into the same Scripts resource folder.

| Script | Role |
| --- | --- |
| `InsertRandomSFX.lua` | Standard **action** (also the shared core module) |
| `InsertRandomSFXAtMouse.lua` | **Mouse-modifier action** |
| `NextSample.lua` | Standard **action** |
| `PreviousSample.lua` | Standard **action** |
| `InsertRandomSFX_Settings.lua` | **Settings window** (edit categories and folders) |

> REAPER lists a ReaScript in the **Action List** by its **file name**, shown as
> `Script: <file>.lua` — for example `Script: InsertRandomSFX_Settings.lua`.
> Use that name to find and run the scripts; this README refers to them by their
> file names.

Steps:

1. Clone or download the repository to a location you keep, for example
   `D:/Tools/ReaperAutoAdd`. By default the scripts live in REAPER's own
   resource `Scripts` folder.
2. Locate the five scripts under `scripts/`.
3. In REAPER, open **Actions → Show action list…**
4. Click **New action → Load ReaScript…** and load each of the five scripts:
   - `scripts/InsertRandomSFX.lua`
   - `scripts/InsertRandomSFXAtMouse.lua`
   - `scripts/NextSample.lua`
   - `scripts/PreviousSample.lua`
   - `scripts/InsertRandomSFX_Settings.lua`
5. Open `InsertRandomSFX_Settings.lua` to set up your categories and folders (see
   [Settings](#settings)).
6. Configure the workflows you want:
   - assign `InsertRandomSFX.lua` to a keyboard shortcut / toolbar (optional),
   - assign `InsertRandomSFXAtMouse.lua` to the Alt+Left Click mouse
     modifiers (see [Mouse Modifier setup](#mouse-modifier-setup)),
   - `NextSample.lua` / `PreviousSample.lua` can be left as Action-List
     actions or given shortcuts.

> Tip: REAPER's action list stores a reference to the scripts. If you move or
> edit them later, re-run them from the action list.

## Settings

Run the **`InsertRandomSFX_Settings.lua`** script to edit the category mapping
from inside REAPER — no script editing required. The window lists one row per
category:

```text
transition  ->  D:/SFX/Transitions
gun         ->  D:/SFX/Guns
impact      ->  D:/SFX/Impacts
```

Buttons: **Add** (asks for the track name, then opens REAPER's folder picker),
**Edit** (rename / re-pick the folder; also opened by double-clicking a row),
**Remove**, **Up** / **Down** (reorder; matching is by name, so order is only
cosmetic), **Reload** (re-read from disk), **Save**, **Close**.

Saving writes `InsertRandomSFX_Settings.ini` into **REAPER's Scripts resource
folder** (next to the scripts by default; find it via
**Options → Show REAPER resource path**). Every SFX action reads that file when
it runs, so changes apply to the next action without reloading anything. The file
is plain text and safe to edit by hand:

```ini
# REAPER Random SFX Inserter -- category mapping.
# One line per category:  track name = folder
transition = D:/SFX/Transitions
gun = D:/SFX/Guns
```

Rules and behaviour:

- The category name is the **track name**. Names are stored lower-case and
  matched case-insensitively (`Gun`, `gun`, `GUN` all resolve to `gun`).
- Duplicate names are rejected, and empty names are not saved.
- If you delete a folder, saving warns you and lets you confirm or cancel.
- If `InsertRandomSFX_Settings.ini` does not exist (or is empty), the built-in
  defaults in the script are used and shown in the window.

## Configuration

The category mapping can be changed either through the `InsertRandomSFX_Settings.lua` action
(recommended; see [Settings](#settings)) or by editing the `CONFIG` table at the
top of `scripts/InsertRandomSFX.lua`.

The `CONFIG.category_folders` table holds the **built-in defaults**. They are
used only when no `InsertRandomSFX_Settings.ini` exists. Once the settings file is
present it overrides this table at startup.

The important field is `category_folders`. **The key is the category ID (which
is also the track name); the value is the folder on disk:**

```lua
category_folders = {
    transition = "D:/SFX/Transitions",
    gun        = "D:/SFX/Guns",
    impact     = "D:/SFX/Impacts",
    whoosh     = "D:/SFX/Whooshes",
    footstep   = "D:/SFX/Footsteps",
},
```

Rules:

- **Keys are category IDs** and are matched against track names.
- **Values are absolute filesystem paths** to the folder holding that category's
  audio files.
- **Track names must match a configured category ID case-insensitively.** A
  track named `Gun`, `gun` or `GUN` all resolve to the `gun` category. Matching
  is exact after trimming surrounding whitespace — there is no partial matching
  (`guns` is not `gun`) and **no automatic inference from folder names**.
- **Only files directly inside the configured folder are read.** Subfolders are
  not scanned (the scanner uses REAPER's file enumeration, which lists files
  only).
- **Only the supported extensions** listed in `CONFIG.supported_extensions`
  count as audio (`.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`).
- Add a category by adding a row, for example `door = "D:/SFX/Doors"`.

The paths shown above are **examples/placeholders**. Replace them with your own
SFX library paths before using the tool. Prefer forward slashes (`/`) on every
platform; on Windows `D:/SFX/Guns` is equivalent to `D:\SFX\Guns` and avoids Lua
backslash escaping.

The other `CONFIG` fields (`supported_extensions`, `undo_prefix`) normally do not
need to be changed.

## Track naming

A track maps to a category purely by name:

| Track name (any case) | Category | Folder used |
| --- | --- | --- |
| `Transition` | `transition` | `D:/SFX/Transitions` |
| `Gun` | `gun` | `D:/SFX/Guns` |
| `Impact` | `impact` | `D:/SFX/Impacts` |
| `Whoosh` | `whoosh` | `D:/SFX/Whooshes` |
| `Footstep` | `footstep` | `D:/SFX/Footsteps` |

Matching is **case-insensitive and based on the configured category ID**. If the
track's name is not a configured category, the operation is refused with a clear
message and nothing is changed.

## Actions

### `InsertRandomSFX.lua`

Direct action:

- uses the **selected track**,
- inserts a random SFX from that category's folder at the **current Edit Cursor
  position**,
- moves the Edit Cursor to the new item's start,
- is a single undo step (`Insert Random <Category>`).

### `InsertRandomSFXAtMouse.lua`

Mouse action, assigned to a mouse modifier:

- **Empty track area** → insert a random SFX at the **mouse's timeline
  position** (the track under the mouse is used; selection is not required and
  is not changed),
- **Existing media item under the mouse** → browse to the **next** sample from
  that item's stored library (the target is the item under the mouse, never the
  selection),
- moves the Edit Cursor to the affected item's start.

### `NextSample.lua`

Moves the **selected** item to the **next** sample in its stored library,
wrapping from the last file to the first. The item is not moved; the new source
sets the natural length. Single undo step.

### `PreviousSample.lua`

Moves the **selected** item to the **previous** sample in its stored library,
wrapping from the first file to the last. The item is not moved; the new source
sets the natural length. Single undo step.

> `NextSample.lua` and `PreviousSample.lua` operate on the **selected**
> item. The Alt+Left Click gesture instead targets the **item under the mouse**
> and needs no selection.

## Mouse Modifier setup

`InsertRandomSFXAtMouse.lua` must be assigned to **Alt+Left Click in BOTH
contexts**. REAPER hit-tests left clicks differently depending on what is under
the pointer, so both bindings are required.

In **Preferences → Editing Behavior → Mouse Modifiers**:

1. Context: **Track** → Behavior: **left click** → Modifier: **Alt** →
   `InsertRandomSFXAtMouse.lua`
2. Context: **Media item** → Behavior: **left click** → Modifier: **Alt** →
   `InsertRandomSFXAtMouse.lua`

The same ReaScript is used in both contexts; it decides what to do from the item
actually under the mouse.

Resulting behavior:

- **Alt+Left Click on empty track area** = insert a random SFX at the mouse
  time.
- **Alt+Left Click on an existing media item** = browse/replace with the next
  sample from that item's library.

> Note: a few item sub-contexts (item edge, fade/autocrossfade, and "Media item
> bottom half" if enabled) are separate REAPER mouse contexts. If Alt+Left Click
> does nothing there, add the same action to that context as well.

## Recommended keyboard shortcuts

Assign shortcuts via **Actions → Show action list → (select action) →
Shortcuts → Add**. Example bindings (not defaults — choose what fits your
keyboard):

| Action | Example shortcut |
| --- | --- |
| `InsertRandomSFX.lua` | `Ctrl+Alt+I` |
| `NextSample.lua` | `Alt+.` |
| `PreviousSample.lua` | `Alt+,` |

You may also add the actions to a toolbar button.

## How it works

- **Configuration is loaded at startup.** Each script reads
  `InsertRandomSFX_Settings.ini` (edited by `InsertRandomSFX_Settings.lua`) in
  REAPER's Scripts resource folder and falls back to the built-in
  `CONFIG.category_folders` defaults when it is missing.
- **Configuration resolves track → category.** The selected track's name is
  matched case-insensitively against the configured category IDs.
- **Library scanner** enumerates the category folder, keeps only supported audio
  extensions, and sorts the result deterministically (case-insensitive).
  Subfolders are not scanned.
- **Insertion** creates a new media item and take, attaches the selected file as
  a PCM source, sets the item position and the natural source length, records
  item metadata, and finishes as one undo step.
- **Item metadata** records the SFX `category`, `library` and `source` on the
  item itself (REAPER `P_EXT:` state).
- **Browsing** uses the stored item metadata (library/source), not the current
  track name, so an item keeps browsing its library even if the track is
  renamed.
- **Random selection avoids immediate repeats** per category (the last pick is
  remembered in project state, saved in the `.RPP`).
- **Replacement preserves** the item, its track and its exact position, and uses
  the newly attached source's natural length with no time-stretch.

## Important implementation notes

These are internal details, not user configuration steps. You do not need to
call these APIs yourself.

1. **Newly created items get their peaks built and are explicitly refreshed.**
   After a new item is fully configured, the code builds the source's peaks and
   then refreshes the item:

   ```lua
   buildPeaks(reaper.GetMediaItemTake_Source(take))  -- Begin/Run/Finish
   reaper.MarkTrackItemsDirty(reaper.GetMediaItem_Track(item), item)
   reaper.UpdateItemInProject(item)
   reaper.UpdateArrange()
   ```

   Building the peaks makes the waveform appear **immediately** (a new source
   has no peaks yet; without this REAPER builds them lazily and the waveform only
   shows up later, on a zoom/redraw). The refresh registers the programmatically
   created item with REAPER's project/arrange state so it cannot act as a
   playback boundary (playback stopping at the item's end).

2. **Existing-item replacement refreshes the waveform.** After swapping an
   existing item's source, the code builds the new source's peaks with the same
   `buildPeaks` helper, so the displayed waveform is the new source's, not the
   previous one.

3. **Inserted and browsed takes are named after their file.** REAPER's own media
   import names a take after the file it plays, which is what the item label
   shows. A take created through the API starts with an **empty** take name, so
   an item built directly would display no name. Insertion and browsing therefore
   set the take name (`P_NAME`) to the source file's name, so the item shows the
   sample name just like a normal import (and stays correct after browsing).

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| "Selected track is not a supported category." | The track name is not one of the `category_folders` keys. Rename the track to a configured category (case-insensitive), or run `InsertRandomSFX_Settings.lua` to add it. The message also shows the settings file path and whether it was found. |
| "The &lt;category&gt; folder does not exist." | The configured path is wrong or not mounted. Use an absolute path with forward slashes. |
| "No supported audio files found…" | The folder exists but contains no supported extensions directly inside it (subfolders are not scanned). Check the files and `supported_extensions`. |
| Settings saved via `InsertRandomSFX_Settings.lua` but the category is still unknown | The category name must match the track name. The error message shows the settings file path — make sure the file exists at `…/REAPER/Scripts/InsertRandomSFX_Settings.ini`. |
| Script does not appear in the Action List | Re-run **New action → Load ReaScript…** and re-select the file. Keep all five scripts in the same folder. |
| Alt+Left Click does nothing | The mouse modifier is not set in **both** the **Track** and **Media item** contexts, or the click landed in an item sub-context (edge/fade). Add the action to that context too. |
| Waveform not updating after browsing | Replacement builds the attached source's peaks; if it still looks stale, re-run the action. Verify the file has readable audio. |
| Waveform missing right after inserting an item | This is fixed: inserted items build the new source's peaks immediately. Make sure you are running the current scripts. |
| Playback/transport stops at an inserted item | This is fixed: newly created items are refreshed with `UpdateItemInProject` + `UpdateArrange`. Make sure you are running the current scripts. |
| Inserted item shows no file name | This is fixed: takes are named from their source file (`P_NAME`), like REAPER's normal import. Make sure you are running the current scripts. |

Errors are shown as a REAPER message box; success is silent. `Ctrl+Z` undoes
each operation in a single step.

## Development

- Implementation is **native ReaScript Lua** only.
- Pure (non-REAPER) logic is unit-tested:

  ```sh
  lua tests/run_tests.lua
  ```

  The tests require Lua 5.3+ but not REAPER. (The tests as written expect the
  five standard categories; extra local categories are outside their scope.)

- Further documentation:
  - [`docs/architecture.md`](docs/architecture.md) — code structure and
    extension points.
  - [`docs/development.md`](docs/development.md) — development and manual test
    procedures.
  - [`docs/roadmap.md`](docs/roadmap.md) — planned work.

## Configuration example

A complete, minimal example of the production configuration (replace the paths
with your own library folders):

```lua
category_folders = {
    transition = "D:/SFX/Transitions",
    gun        = "D:/SFX/Guns",
    impact     = "D:/SFX/Impacts",
    whoosh     = "D:/SFX/Whooshes",
    footstep   = "D:/SFX/Footsteps",
}
```

With this configuration:

```text
track "transition"  ->  random file from D:/SFX/Transitions
track "gun"         ->  random file from D:/SFX/Guns
track "impact"      ->  random file from D:/SFX/Impacts
track "whoosh"      ->  random file from D:/SFX/Whooshes
track "footstep"    ->  random file from D:/SFX/Footsteps
```

## License

MIT — see [`LICENSE`](LICENSE).
