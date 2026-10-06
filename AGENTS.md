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
is **not** part of the current MVP.

The value of the project is speed: keep the mouse on the timeline, press one
key, get a suitable sound at the cursor.

## 2. Current MVP

Implemented today, in [`scripts/InsertRandomSFX.lua`](scripts/InsertRandomSFX.lua):

1. Requires a selected track (errors otherwise).
2. Resolves the selected track's name to a category, case-insensitively.
   The only configured category is `transition`.
3. Looks in the folder configured for that category.
4. Lists the supported audio files directly inside that folder
   (subfolders are ignored).
5. Picks one at random.
6. Inserts it as a normal media item at the current edit cursor position on the
   selected track.
7. Wraps the insertion in a single REAPER undo step
   (`Insert Random Transition`).

Supported formats: `.wav`, `.aif`, `.aiff`, `.flac`, `.ogg`, `.mp3`.

Everything else in `docs/roadmap.md` is a plan, not a feature. Do not build it
without being asked.

## 3. Architecture

The intended pipeline is:

```text
        Track
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

Key rule: **the code must not be hard-coded around `transition`.** The only
transition-specific thing is a single row in the `CONFIG.category_folders`
table. Adding a category is a configuration change, not a logic change.

The script is organised into three layers so future growth stays cheap:

1. **Configuration** — the `CONFIG` table at the top of the script. Users edit
   this; logic does not.
2. **Pure helpers** — no REAPER API calls (extension parsing, category
   resolution, path joining, file filtering, directory detection). These are
   unit-tested outside REAPER.
3. **REAPER API helpers** — small wrappers around `reaper.*` (track selection,
   track name, error dialog, insertion). Keeping the API surface small keeps the
   pure layer testable.

The script ends with a documented **test hook**: when loaded with
`_G.SFX_TEST_MODE` set, it returns its pure helpers instead of running `main()`.

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

## 5. Coding rules

- Keep scripts **small and readable**. The MVP is one file on purpose.
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
- **Do not break existing workflows.** The MVP workflow is the contract:
  select `transition` track, position cursor, run once, get one item at the
  cursor, `Ctrl+Z` removes it.
- Match the surrounding style: 4-space indent, `local function` declarations,
  lowercase names, snake-case config keys.

## 6. Development workflow

1. **Read** `AGENTS.md`, `docs/architecture.md` and the relevant source.
2. **Modify** `scripts/InsertRandomSFX.lua` (or add files under `scripts/`).
3. **Run the automated tests** from the repository root:

   ```sh
   lua tests/run_tests.lua
   ```

   These cover the pure logic only and require Lua 5.3+ but not REAPER.
   Also run `luac -p scripts/InsertRandomSFX.lua` for a syntax check.
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

- **Multiple categories** — more track-name → folder mappings (gun, impact,
  whoosh, footstep, ...).
- **Configurable category mapping** — categories defined in a data file rather
  than inline Lua, if it stays simple.
- **Mouse interaction** — Ctrl/Shift/Alt-click and mouse modifiers. Investigate
  what REAPER supports natively (mouse modifier contexts, custom actions,
  toolbar buttons) before committing to an implementation.
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
