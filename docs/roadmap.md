# Roadmap

Staged plan. Each phase is deliberately small. **Phases 0 and 1 are
implemented.** Everything below them is a plan, not a promise — do not build
ahead of the task you were given.

## Phase 0 — MVP ✅

One track, one folder, one random file, inserted at the cursor.

```text
transition → one folder → random file → insert at cursor
```

Done when: a user can select a track named `transition`, place the edit cursor,
run one action, and get one random supported audio file inserted at that
position on that track, undoable in a single step.

See [`architecture.md`](architecture.md) for how it works.

## Phase 1 — Categories ✅ (current)

Multiple track names / categories, configured rather than hard-coded.

```text
transition → Transitions folder
gun        → Guns folder
impact     → Impacts folder
whoosh     → Whooshes folder
footstep   → Footsteps folder
```

Implemented by defining five categories in `CONFIG.category_folders`. The key
is the REAPER track name; the value is the folder. Matching stays **exact but
case-insensitive**. Users can add more categories as configuration.

Still open for later:

- Decide whether to move the mapping from inline Lua to a small config file.
- Consider a helper action that lists the configured categories, so users can
  discover them.

## Phase 2 — Better randomisation

- Avoid immediate repetition (remember the last file, or a short history).
- Optional history / weight per category.
- Weighted selection (e.g., some samples more likely than others).
- Keep this logic **pure and tested**; the folder-listing layer should not need
  to change.

## Phase 3 — Fast interaction

Investigate the most native and reliable REAPER mechanism before assuming
Ctrl-click is technically best:

- keyboard shortcuts on the script action;
- toolbar buttons;
- custom actions (composing built-in actions + this script);
- mouse modifiers (`GetMouseModifier`, track/arrange mouse contexts);
- REAPER's "GetThingFromPoint" / track-under-mouse APIs.

Deliverable: a documented, recommended interaction, with the script unchanged in
its core. If the chosen interaction needs a different entry point, add it as a
thin wrapper.

## Phase 4 — Production workflow

Potentially, in rough priority:

- **Project-level configuration** (per-project folder mapping).
- **Global / user library configuration** (shared across projects).
- **Subfolders** — optional recursive lookup within a category.
- **Favorites** and pinned samples.
- **Preview** — audition a sample before or after insertion.
- **Batch placement** — insert several at once.
- **Random gain / pitch / pan** and light humanisation.
- **Metadata** — read tags/notes for filtering.
- **UI** — a small settings panel, only if the config outgrows a table.

Each item should be justified by a real workflow need.

## Phase 5 — Evaluate whether ReaScript is enough

Only if the workflow genuinely demands it, investigate a native REAPER
extension/plugin (e.g., true mouse hooks or tighter integration).

**Do not implement this now.** ReaScript should carry the project as far as
possible before introducing a compiled component.
