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

Two entry points share one implementation.

**Standard action** —
[`scripts/InsertRandomSFX.lua`](scripts/InsertRandomSFX.lua):

1. Requires a selected track (errors otherwise).
2. Resolves the track's name to a category, case-insensitively. Five categories
   are configured by default: `transition`, `gun`, `impact`, `whoosh`,
   `footstep`.
3. Looks in the folder configured for that category.
4. Lists the supported audio files directly inside that folder (subfolders are
   ignored).
5. Picks one at random.
6. Inserts it as a normal media item at the current edit cursor position.
7. Wraps the insertion in a single REAPER undo step
   (`Insert Random <Category>`, e.g. `Insert Random Gun`).

**Fast mouse workflow** —
[`scripts/InsertRandomSFXAtMouse.lua`](scripts/InsertRandomSFXAtMouse.lua):

1. Resolves the track under the mouse (`GetTrackFromPoint`) and the project time
   under the mouse (`GetSet_ArrangeView2`, from the mouse X).
2. Selects that track so `InsertMedia(file, 0)` targets it (selection is not an
   undo step).
3. Calls the same shared insertion logic at the mouse time.
4. **Never moves the edit cursor.**

Both entry points call `insertRandomForTrackAtPosition(track, position)` in the
core script. The wrapper must be bound to the **Track** and **Media item**
left-click / Alt mouse-modifier contexts.

Supported formats: `.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`.

Everything else in `docs/roadmap.md` is a plan, not a feature. Do not build it
without being asked.

## 3. Architecture

Two entry points converge on one shared function:

```text
  standard action                Alt+click wrapper
  selected track + edit cursor   track + time under mouse
                \                       /
                 v                     v
        insertRandomForTrackAtPosition(track, position)
                        │
                        ▼
        Category            (resolveCategoryFromTrackName)
                        │
                        ▼
        Folder              (CONFIG.category_folders)
                        │
                        ▼
     Audio file list        (collectSupportedAudioFiles)
                        │
                        ▼
    Random selection        (math.random)
                        │
                        ▼
     REAPER Insert          (insertMediaAtCursor -> reaper.InsertMedia)
                        │
                        ▼
       Media Item
```

Key rule: **the code must not be hard-coded around any single category.** Each
category is just a row in the `CONFIG.category_folders` table. Adding a category
is a configuration change, not a logic change.

The core script is organised into three layers so future growth stays cheap:

1. **Configuration** — the `CONFIG` table at the top of the script. Users edit
   this; logic does not.
2. **Pure helpers** — no REAPER API calls (extension parsing, category
   resolution, path joining, file filtering, directory detection). These are
   unit-tested outside REAPER.
3. **REAPER API helpers** — small wrappers around `reaper.*` (track selection,
   track name, error dialog, insertion). Keeping the API surface small keeps the
   pure layer testable.

Plus a thin **mouse wrapper** (`InsertRandomSFXAtMouse.lua`) that only resolves
track + time from the mouse and calls the shared function.

The core script ends with a documented **module hook**: when loaded with
`_G.SFX_LOAD_AS_MODULE` set, it returns its functions instead of running
`main()`. The tests and the mouse wrapper both use this.

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
  `GetTrackFromPoint`, `GetSet_ArrangeView2` and `SetOnlyTrackSelected`. Do not
  add SWS, js_ReaScriptAPI, or window-message hooks.

## 5. Coding rules

- Keep scripts **small and readable**. The implementation is two files on
  purpose (core + thin mouse wrapper).
- **Avoid unnecessary abstraction.** Add a function when it isolates something
  real (an API call, an error path, a future extension point), not for symmetry.
- **Isolate REAPER API interaction** in the "REAPER API HELPERS" section.
  Business logic must not call `reaper.*` directly.
- **Keep configuration separate from logic** where practical. `CONFIG` is data;
  the functions consume it.
- **Do not introduce external dependencies** without a strong, documented
  reason.
- **Preserve REAPER undo behaviour.** Any state-changing operation goes inside
  `reaper.Undo_BeginBlock()` / `reaper.Undo_EndBlock(desc, -1)` with a
  human-readable description, and must be a single undo step.
- **Do not silently fail.** Show a clear REAPER message on every error path.
  Do **not** show a modal dialog on the successful path.
- **The mouse workflow must not move the edit cursor.** Never call
  `SetEditCurPos` in the wrapper. `GetCursorPosition()` must be unchanged
  before and after an Alt+click insertion.
- **Do not break existing workflows.** Both workflows are the contract:
  * standard action — select a category track, position the cursor, run once,
    get one item at the cursor;
  * Alt+click — hover a track/time in the Arrange View, get one item there.
  In both cases `Ctrl+Z` removes it in a single step.
- Match the surrounding style: 4-space indent, `local function` declarations,
  lowercase names, snake-case config keys.

## 6. Development workflow

1. **Read** `AGENTS.md`, `docs/architecture.md` and the relevant source.
2. **Modify** `scripts/InsertRandomSFX.lua` (core) and/or
   `scripts/InsertRandomSFXAtMouse.lua` (wrapper), or add files under
   `scripts/`. Keep the two scripts in the same directory: the wrapper loads the
   core by relative path.
3. **Run the automated tests** from the repository root:

   ```sh
   lua tests/run_tests.lua
   ```

   These cover the pure logic only and require Lua 5.3+ but not REAPER.
   Also syntax-check both scripts:

   ```sh
   luac -p scripts/InsertRandomSFX.lua
   luac -p scripts/InsertRandomSFXAtMouse.lua
   ```

   The mouse/time APIs cannot be unit-tested outside REAPER.
4. **Test inside REAPER** for anything touching the real API. DAW behaviour
   cannot be validated outside REAPER. Follow the manual test cases in
   `docs/development.md`.
5. **Document** behaviour changes in `README.md`, and update
   `docs/architecture.md` when the architecture or extension points change.
6. **Update `docs/roadmap.md`** when something moves between "planned" and
   "done", or when scope changes.
7. Keep commits small and focused; explain the REAPER-side verification you
   performed.

If you change `CONFIG` keys, update the README's configuration section at the
same time.

## 7. Future direction

These are **ideas, not requirements**. Do not implement them unless the task
explicitly asks. Ordered roughly by the phases in `docs/roadmap.md`.

- **Configurable category mapping** — categories defined in a data file rather
  than inline Lua, if it stays simple. (Multiple inline categories are already
  implemented — Phase 1.)
- **Additional mouse contexts** — item edge / fade / "Media item bottom half"
  bindings, only if a real workflow needs them. (Alt+left-click on the Track and
  Media item contexts is already implemented — Phase 3.)
- **Transient / peak detection** — optionally snap an inserted item to a nearby
  transient.
- **Randomisation improvements** — avoid immediate repeats, optional history,
  weighted selection.
- **Subfolders** — optional recursive lookup within a category folder.
- **Configuration levels** — project-specific config, per-user/global library
  config.
- **Preview** — audition before/after insertion.
- **Parameter randomisation** — random gain, pitch, pan.
- **Batch insertion** — several items at once.
- **UI/settings** — a small settings window if configuration outgrows a table.
- **Native extension** — only if ReaScript eventually proves insufficient for
  the workflow (for example, true mouse hooks). Explicitly out of scope now.
