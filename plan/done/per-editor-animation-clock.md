# Per-Editor Animation Clock — the clock-as-document redesign

Make animation time a **first-class document** with a **per-editor** clock, so that:

- many editors run in one process with **independent** time (AR-45),
- **time-dependent documents**, **animated projections**, and **faster-than-real-time
  video recording** are all first-class supported features, and
- the process-global `_EDITOR_TIME` cell **goes away**, replaced by a per-editor
  `Clock` plus one principled global **wall clock**.

This supersedes the earlier "Option A" draft (editor owns a bare `mutable struct
Clock`, ambient `DEFAULT_CLOCK`). Two changes: the clock becomes a **document** (a
`time::Cell` field) living in the **document layer** (`Clock.jl`, relocated out of
the cell layer — the file is already moved as `document/Time.jl`), and the ambient
default becomes a semantically-honest **wall clock** tracking OS time instead of an
arbitrary default.

---

## Why

`_EDITOR_TIME` (a module-global `Cell(0.0)`) is process-global mutable state
(AR-6/AR-45). Two editors in one process collide three ways:

1. **Judder** — each `run_editor!` writes `Base.time() - t_start` into the one
   shared cell every frame; two loops with different start instants fight over it.
2. **Cross-editor invalidation** — editor A's tick invalidates *every* subscriber
   of the one cell, including editor B's animated cells.
3. **No determinism** — a single global cell can't be seeked per-editor for headless
   render / tests, so faster-than-real-time recording of one editor corrupts another.

### Features this must enable

1. **Time-dependent documents** — a document whose content is a function of time.
2. **Animated projection output** — a projection that re-renders as time advances.
3. **Faster-than-real-time video recording** — render frames by *driving the clock
   deterministically* (seek `t = 0, 1/fps, 2/fps, …`) as fast as the machine allows,
   not by waiting for wall time.

---

## Design

### 1. `Clock` is a document with a `time` field — `document/Clock.jl`

```julia
@document struct Clock
    time::Float64 = 0.0        # a transparent Cell-backed field
end
```

- `clock.time` reads (SUBSCRIBE, tracked); `clock.time = t` writes (invalidate
  subscribers) — the transparent-Cell field gives both.
- A `Clock` is a plain document: constructed, shared, linked into another document,
  and — if wanted later — *projected* (a timeline / scrubber UI).
- Reads named for intent:
  - `get_reactive_time(clock)` = `clock.time` — SUBSCRIBE: the calling cell re-runs
    each tick. Use inside an animated thunk.
  - `get_time(clock)` = untracked sample (`peek` the field) — capture a start instant
    without subscribing. Use to *arm* an animation.
  - `tick!(clock, t)` / `seek!(clock, t)` = `clock.time = Float64(t)`.

### 2. One global **wall clock** — real OS time

```julia
const WALL_CLOCK = Clock()          # advanced by a single heartbeat to Base.time()
get_wall_clock() = WALL_CLOCK
```

- Reflects **OS wall-clock time**: one background heartbeat writes `Base.time()` into
  it; everything else only *reads* it.
- The ambient default for callers with no editor (direct `print_document`,
  `write_image`, tests, editor-less documents).
- **Why a global is acceptable here (accepted AR-45 carve-out):** the AR-45 hazard is
  editors *writing conflicting elapsed values* into one shared cell. The wall clock
  has exactly **one writer** (the heartbeat) and represents a **genuine singleton**
  (there is one real time); editors only *read* it, so it never breaks their
  independence. A shared read of a real external truth is not shared mutable *editor*
  state. See Caveats.

### 3. The `Editor` owns its clock — `editor/Editor.jl`

```julia
mutable struct Editor
    ...
    clock::Clock
end
Editor(...; clock::Clock = Clock()) = Editor(..., clock)   # fresh private clock per editor
```

- **Live editor**: `run_editor!` advances `editor.clock` from OS time each frame
  (`tick!(editor.clock, Base.time() - t_start)`) — tracks real time but
  *independently*, so A's tick never touches B's cells.
- **Recording editor**: the recorder advances `editor.clock` deterministically
  (`seek!(editor.clock, frame/fps)`), decoupled from wall time — this is what makes
  faster-than-real-time recording work.
- Default = a fresh `Clock()` (full independence by default); editor-less contexts
  fall back to `get_wall_clock()`.

### 4. The clock rides down through `PrinterContext` — `projection/PrinterContext.jl`

Add a typed `clock::Clock` field (like `available_width`), propagated through both
constructors, both `make_child_context`, `with_available_size`, `with_property`, plus
a `with_clock` helper. `print!` mints the root context with `editor.clock`. A
projection-driven animation reads `ctx.clock`, closes over it, and subscribes to *its
own* editor's clock — per-editor invalidation falls out for free.

### 5. Document construction functions take a `clock` — the linkage

A self-animating document takes an optional `clock` argument and wires its cells to it:

```julia
make_rotating_vector_document(; clock::Clock = get_wall_clock(), …)
```

Link a document to a specific editor by passing the *same* `Clock` to both the
constructor and `run_editor!`. Two independent (document, editor) pairs with two
distinct `Clock`s animate fully independently.

### 6. The three features, realized

- **Time-dependent documents** — the construction `clock` argument + `clock.time`
  reads inside the document's cells.
- **Animated projection output** — `ctx.clock` in a printer thunk.
- **Faster-than-real-time recording** — the recording editor seeks `editor.clock`
  frame-by-frame; `ProjecturedVideo` drives that clock instead of the old global.

---

## Placement

`Clock` lives in the **document layer** (`document/Clock.jl`), not the cell layer — a
time value is document-model data built on `Cell`, not part of the reactive engine.
(The file is already relocated as `document/Time.jl`; this redesign renames it
`Clock.jl`.) `PrinterContext` (projection, layer 7) and `Editor` (layer 9) import
`Clock` from the document layer (2) — valid downward edges. The wall clock lives with
`Clock` in the document layer.

---

## Caveats / accepted exceptions

1. **The wall clock is a process-global** — accepted as a *principled* AR-45 carve-out:
   one writer (the heartbeat), read-only for editors, representing the genuine
   singleton of OS time. Record this exception at the `WALL_CLOCK` definition and in
   AR-45. It does **not** reintroduce the cross-editor *write* conflict AR-45 targets.
2. **Reader-armed animations stay on the wall clock (per-editor deferred).** A reader
   (`read_intent`) receives `iomap`, not `ctx`, so it cannot reach the editor's clock.
   The printer-subscribe and reader-arm sides of a reader-armed widget (e.g.
   WidgetSwitch) must sample the *same* clock, so both use `get_wall_clock()`.
   Consequence: reader-armed widgets animate only against the wall clock; in a
   private-clock editor they hold their final position. Making them per-editor needs a
   clock reachable from readers (an iomap-borne clock, or a reader context analogous to
   `PrinterContext`) — a separate follow-up.

---

## Breaking changes

The zero-arg time API (`get_reactive_editor_time()`, `get_editor_time()`,
`tick_editor_time!(t)`) is **removed**; every read/tick takes an explicit `Clock`. No
compat shim. In-tree callers (`run_editor!`, `Playback`, `RotatingVector`,
`WidgetToGraphics`, `ProjecturedVideo`, tests) are updated wholesale.

## Consumer audit

| Consumer | Action |
|---|---|
| `run_editor!` / `Playback` (kernel editor) | tick `editor.clock` instead of the global |
| `print!` (kernel editor) | mint the root `PrinterContext` with `editor.clock` |
| RotatingVector (example, self-animating doc) | `clock` param; cells read the clock (§5) |
| WidgetToGraphics switch (visual, printer + reader) | both sides read `get_wall_clock()`; per-editor deferred |
| ProjecturedVideo (video) | drive the recording editor's `clock` (seek per frame) |

## Determinism / tests (acceptance criteria)

- **Independence** — two editors with two `Clock`s, ticked to different values, print
  both; assert each animated cell reflects *its own* clock and ticking A does not
  recompute B's cells.
- **Time-dependent document** — build a document against a clock; seek it; assert the
  dependent field changed and a static sibling did not recompute.
- **Animated projection** — seek an editor's clock; assert an animated coordinate in
  its output changed.
- **Faster-than-real-time recording** — record N frames by seeking the editor clock
  deterministically (no `sleep`); assert wall-clock elapsed ≪ N/fps and each frame
  reflects its seeked time.

## Implementation steps

1. **`document/Clock.jl`** (rename from `Time.jl`): the `Clock` document + `time`
   field; `get_reactive_time` / `get_time` / `tick!` / `seek!`; `WALL_CLOCK` +
   `get_wall_clock` + the heartbeat; **delete** the zero-arg API. Update the
   `DocumentLayer.jl` include name.
2. **`PrinterContext`**: typed `clock` field; propagate through constructors /
   child-context / with-helpers; add `with_clock`.
3. **`Editor`**: `clock` field (fresh `Clock()` default); `print!` mints a
   clock-bearing root context; `run_editor!` advances `editor.clock`; audit `Playback`.
4. **Consumers**: RotatingVector → `clock` param; WidgetToGraphics printer+reader →
   `get_wall_clock()`; ProjecturedVideo → drive the recording editor's clock.
5. **Tests**: the four acceptance tests above; fix any test using the deleted zero-arg API.
6. **Docs & requirements**: rewrite the `Clock` docstring and move cell.md's relocated
   `TimeModule` section into a document-layer doc; record the wall-clock AR-45
   carve-out in AR-45; note the reader-seam follow-up.
7. **Seal**: once migrated and green, `document/Clock.jl` is eligible for the seal walk.

## Open questions

- **`@document` vs `@cell_struct` for `Clock`** — full document machinery
  (snapshot / `rekind` / selection) only earns its keep if the clock is itself
  *projected* (a timeline / scrubber). If not, `@cell_struct` is lighter. Decide when
  the projecting-the-clock feature is scoped.
- **Live editor: private clock vs shared wall clock** — proposed: a fresh private
  `Clock()` per editor, ticked from OS time (full independence). Alternative: live
  editors share the wall clock (simpler, but cross-invalidates). Proposed keeps
  independence; revisit if a per-editor tick proves redundant with the heartbeat.
- **Reader-seam follow-up** — the mechanism to let reader-armed widgets read a
  per-editor clock (an iomap-borne clock, or a reader context analogous to
  `PrinterContext`).

## Related — already migrated (not part of this plan)

The two *other* process-global offenders AR-45 named were fixed independently, as
**task-local** state rather than per-editor, because they are per-*evaluation*, not
per-*editor*:

- `PerformanceCounterModule`'s `_perf` → a task-local `with_performance_counters`
  binding.
- `ReactiveCell`'s `_computing` dependency-tracking stack → task-local storage.

The animation clock is genuinely per-*editor* (and must flow down to printers), which
is why it needs this `PrinterContext`-threading approach instead.
