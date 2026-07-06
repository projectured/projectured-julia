# Per-Editor Animation Clock (multi-editor time)

Make the animation clock a **per-editor** value instead of a single process-global
`Cell`, so two independent editors can run in one process with independent time —
and so a self-animating *document* (the rotating-vector example) can be **linked**
to a specific editor's clock.

Chosen approach: **Option A** — the editor owns a clock; the clock flows down to
printers through `PrinterContext`; `run_editor!` / the `Editor` constructor take an
**optional** clock; and self-animating document constructors take an optional clock
so a document and its editor can share one.

**Backward compatibility is explicitly a non-goal.** The zero-argument time API
(`get_reactive_editor_time()`, `get_editor_time()`, `tick_editor_time!(t)`) that
reads a hidden process-global is **removed**: every read/tick takes an explicit
`Clock`. Call sites are updated wholesale; no compatibility shim is kept.

---

## Problem

[Time.jl](../../package/kernel/src/cell/Time.jl) is a process-global singleton:
one `const _EDITOR_TIME = Cell(0.0)`, and all three verbs (`tick_editor_time!`,
`get_reactive_editor_time`, `get_editor_time`) operate on it. Two editors in one
process therefore collide three ways:

1. **Judder (correctness bug).** Each [`run_editor!`](../../package/kernel/src/editor/Editor.jl)
   loop computes its own `t_start` and writes `Base.time() - t_start` every frame.
   Two loops with different start instants write different elapsed values into the
   *same* cell each frame → the shared time ping-pongs between origins → both
   editors' animations stutter.
2. **Cross-editor invalidation (waste).** Editor A's tick invalidates *every*
   subscriber of the one cell, including editor B's animated thunks — B recomputes
   for nothing. The "only the animated subtree recomputes" guarantee leaks across
   editor boundaries.
3. **No independence (capability gap).** A single cell can't have per-editor
   pause / rate / seek, and — critically — a deterministic per-editor `seek!` for
   headless render / tests corrupts the other editor.

(The same disease affects [PerformanceCounter.jl](../../package/kernel/src/cell/PerformanceCounter.jl)'s
process-global `_perf` dict, which `run_editor!` resets each frame; see
**Deferred / related**. Out of scope here, but the fix shape is identical.)

## The crux

Consumers read time with **zero arguments**, deep in the pipeline, and are two
different kinds of caller:

- **Printer thunks** — closures *built* during `print_document` but *pulled* later
  during `write_to_devices` (e.g. [RotatingVector.jl](../../package/example/src/document/RotatingVector.jl),
  the knob-`cx` cell in [WidgetToGraphics.jl:3474](../../package/visual/src/widget/WidgetToGraphics.jl#L3474)).
- **Readers** — `read_intent` *samples* time at arm-time and gets `(projection, iomap, evt)`
  — **no context** (e.g. `_switch_toggle` at [WidgetToGraphics.jl:3504](../../package/visual/src/widget/WidgetToGraphics.jl#L3504)).

The printer path already has a downward-flow vehicle: [`PrinterContext`](../../package/kernel/src/projection/PrinterContext.jl)
(`ctx`) is threaded through the entire print pipeline and is built for exactly this
kind of ambient, per-invocation data. That is where the clock rides down. Two
consumer shapes need different injection points:

- **Projection-driven animation** (a printer with `ctx`) reads `ctx.clock` and
  closes over it → subscribes to *its own* editor's cell → per-editor invalidation
  falls out for free.
- **Self-animating document** (e.g. RotatingVector, projected by `IdentityProjection`)
  is a *document constructor* with **no `ctx`**. Its clock must be injected at
  construction, and the document is built *before* the editor — so the linkage is:
  create a `Clock`, pass it to the constructor **and** to `run_editor!`, so both
  read/tick the same clock.

---

## Design

### 1. A `Clock` value + an ambient default clock — `TimeModule`

Replace the bare global cell with a small `Clock` value that owns its own time cell.
Keep **one** module-level `DEFAULT_CLOCK` — not as a compatibility shim but as the
*ambient default argument* for callers that have no editor in scope (direct
`print_document`, `write_image` / `pure_print_document`, tests). It is frozen at
`0.0` until something ticks or seeks it.

```julia
# package/kernel/src/cell/Time.jl
mutable struct Clock          # mutable so pause/rate/origin fields can be added later
    time::Cell                # Cell{Float64}; the single source of truth for THIS clock
end
Clock() = Clock(Cell(0.0))

# the ONLY time API — every call takes an explicit clock:
get_reactive_editor_time(clock::Clock) = clock.time[]        # SUBSCRIBE (tracked)
get_editor_time(clock::Clock)          = peek(clock.time)    # SAMPLE   (untracked)
tick_editor_time!(clock::Clock, t::Real) = (clock.time[] = Float64(t); nothing)

const DEFAULT_CLOCK = Clock()   # ambient clock for editor-less print / export / tests
get_default_clock() = DEFAULT_CLOCK
```

- **The zero-arg forms are deleted.** There is no hidden-global read left; a caller
  that wants the ambient clock names it (`get_reactive_editor_time(get_default_clock())`).
- Export `Clock`, `get_default_clock` alongside the three clock-parameterized verbs.
- `peek(::Cell)` is already available (Time.jl uses it today for the sample read),
  so no new engine primitive is needed.
- **Pause / rate / seek are deferred.** `Clock` is a struct precisely so those
  fields can land later without touching call sites; v1 ships just the time cell.
  (`seek!(clock, t)` can be added as an alias for `tick_editor_time!` for clarity.)

### 2. `PrinterContext` carries the clock — `PrinterContext.jl`

Add a typed `clock` field, defaulting to the ambient default, and propagate it
through every builder.

```julia
struct PrinterContext
    reference::ReferencePath
    available_width::Union{Nothing, Cell}
    available_height::Union{Nothing, Cell}
    clock::Clock                       # NEW — ambient animation clock for this print
    properties::Dict{Symbol, Any}
end
```

- A **typed field**, not a `properties` key: the clock is a *universal* concern
  (any animated printer may read it) and type-stability matters on the print hot
  path — exactly the rationale already used for `available_width`/`available_height`.
- Thread `clock` through: `PrinterContext()` and `PrinterContext(ref)` (default
  `get_default_clock()`), both `make_child_context` overloads, `with_available_size`,
  and `with_property`. Add a `with_clock(ctx, clock)` helper.
- Import `Clock` from `TimeModule` (the cell layer, no kernel deps — a clean import).

### 3. The `Editor` owns the clock — `Editor.jl`

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
    recognizer::GestureRecognizer
    clock::Clock                      # NEW
end

# optional clock; the ambient default when unspecified (see the editor-default
# decision under Open Questions)
Editor(backend, document, projection, devices; clock::Clock=get_default_clock()) =
    Editor(backend, document, projection, devices,
           nothing, nothing, GestureRecognizer(), clock)
```

- **`print!` stamps the clock into the root context.** Today it calls the 2-arg
  [`print_document(projection, input)`](../../package/kernel/src/projection/Projection.jl#L40),
  which injects a fresh `PrinterContext()`. Change `print!` to build a root context
  carrying `editor.clock` and call the 4-arg form:

  ```julia
  function print!(editor::Editor)
      if editor.iomap === nothing
          ctx = PrinterContext(EmptyReferencePath(), nothing, nothing,
                               editor.clock, Dict{Symbol,Any}())
          editor.iomap = print_document(editor.projection, nothing, editor.document, ctx)
      end
      write_to_devices(editor.backend, editor.devices, editor.iomap.output)
  end
  ```

- **`run_editor!` advances the editor's clock**, not a global:
  `tick_editor_time!(editor.clock, Base.time() - t_start)`.
- **Bootstrap overload** gains an optional `clock` and threads it to `Editor`:
  `run_editor!(backend, projection, document; clock::Clock=get_default_clock(), mcp=false, devices=…)`.
- **Audit other tick sites.** [ProjecturedVideo.jl:146](../../package/video/src/ProjecturedVideo.jl#L146)
  calls `tick_editor_time!(time() - anim_t0)` on the global — migrate it to advance
  the editor's clock (thread the recorded editor's clock, or accept a `clock` arg).
  [Playback.jl](../../package/kernel/src/editor/Playback.jl) has its own scripted
  loop — audit whether it ticks time and, if so, advance the editor's clock.

### 4. Link the rotating-vector example to an editor's clock — the acceptance target

Give the self-animating document constructor a `clock` parameter (defaulting to the
ambient clock so `run_example` still works — see the harness note), and read that
clock inside its cells:

```julia
# package/example/src/document/RotatingVector.jl
function make_rotating_vector_document(; clock::Clock = get_default_clock(),
                                       w = 600, h = 600, …)
    phase0 = get_editor_time(clock)                 # SAMPLE this clock
    …
    () -> round(Int32, cx + r * cos(angle(get_reactive_editor_time(clock))))  # SUBSCRIBE this clock
    …
end
```

The linkage pattern — one private clock shared between a document and its editor,
giving a fully independent animated editor:

```julia
clk = Clock()
doc = make_rotating_vector_document(; clock = clk)
run_editor!(backend, IdentityProjection(), doc; clock = clk)   # ticks clk
```

Two such pairs with two distinct `Clock`s run as **two independent** animated
editors — different times, no cross-invalidation, independently seekable.

> **Example-harness note.** [`run_example`](../../package/example/src/Examples.jl)
> composes **pre-built, cached** `Example.document`s into a multi-window screen, and
> `Example` builds its document once via `make_document()` at load time. For the
> single-editor harness the simplest correct wiring is: the harness runs the editor
> with the ambient default clock (`run_editor!(…; clock=get_default_clock())`), and
> self-animating example documents default their `clock` to `get_default_clock()`,
> so the cached document and the editor share it with no per-run surgery. Linking a
> self-animating document to a *private* clock (the two-independent-editors case) is
> the deliberate opt-in shown above: build a fresh document with an explicit `clock`
> and run its editor with the same one, rather than reusing the cached document.

### 5. Consumer audit

Every zero-arg time read must be updated (the zero-arg API is gone). Only two files
read the time API today:

| Consumer | Path | Action |
|---|---|---|
| RotatingVector (printer/subscribe, self-animating doc) | [RotatingVector.jl](../../package/example/src/document/RotatingVector.jl) | **Migrate** — `clock` param, cells read `…(clock)` (§4). |
| WidgetSwitch knob (printer subscribe **+** reader arm) | [WidgetToGraphics.jl](../../package/visual/src/widget/WidgetToGraphics.jl) | **Migrate to `get_default_clock()` on both sides; per-editor deferred** (below). |

**Why WidgetSwitch stays on the default clock (per-editor deferred).** Its animation
is *reader-armed*: `_switch_toggle` (the reader, line 3499/3513) **samples** the
start instant, and readers receive `iomap`, not `ctx` — they cannot reach the
editor's clock. The printer's subscribe and the reader's arm **must sample the same
clock** (they compute `t - t0` together). The printer *has* `ctx` and could read
`ctx.clock`, but the reader can only reach a globally-named clock, so to keep the two
consistent, **both** read `get_default_clock()`. Consequence: WidgetSwitch animates
only in an editor whose clock is the default clock; in an editor with a private
clock it simply holds its final position (no wrong animation). Making reader-armed
widgets per-editor needs the clock reachable from readers (an iomap-borne clock or a
reader context) — a separate follow-up.

---

## Breaking changes

- **Zero-arg time API removed.** `get_reactive_editor_time()`, `get_editor_time()`,
  `tick_editor_time!(t)` no longer exist. Every call site passes an explicit `Clock`
  (`get_default_clock()` where there is no editor). Grep confirms the only in-tree
  readers are RotatingVector and WidgetToGraphics; the only ticker is `run_editor!`
  plus ProjecturedVideo — all updated here.
- **Tests that pin time** switch from `tick_editor_time!(t)` to
  `tick_editor_time!(get_default_clock(), t)` (or seek a named clock).
- No compatibility shim, no deprecation path — this is a clean cut.

## Determinism / tests

- Add an **independence test**: build two `Editor`s with two `Clock`s (or two
  rotating-vector documents each linked to its own clock), `tick_editor_time!` each
  clock to *different* values, print both, and assert (a) each animated cell reflects
  **its own** clock and (b) ticking clock A does **not** recompute clock B's cells
  (cross-editor incrementality). No live loop needed — direct `print!` + tick.
- Keep a default-clock smoke test proving `run_example("rotating_vector")` still
  animates (seek `get_default_clock()`, assert an animated coordinate changed and a
  static sibling did not recompute).

## Implementation steps

1. **`TimeModule`**: `Clock` struct, clock-parameterized verbs, `DEFAULT_CLOCK` +
   `get_default_clock`; **delete** the zero-arg forms. Export `Clock`,
   `get_default_clock`. Update the module docstring (per-editor + ambient default).
2. **`PrinterContext`**: add typed `clock` field; propagate through both constructors,
   both `make_child_context`, `with_available_size`, `with_property`; add `with_clock`.
   Update docstring.
3. **`Editor`**: `clock` field + optional constructor arg; `print!` mints a
   clock-bearing root context; `run_editor!` advances `editor.clock`; bootstrap
   overload gains optional `clock`.
4. **Audit tick sites**: migrate [ProjecturedVideo.jl](../../package/video/src/ProjecturedVideo.jl#L146);
   audit [Playback.jl](../../package/kernel/src/editor/Playback.jl).
5. **Consumers**: RotatingVector → `clock` param; WidgetToGraphics printer+reader →
   `get_default_clock()`.
6. **Tests**: independence test + default-clock smoke test; fix any test that used a
   zero-arg tick/read.
7. **Docs**: `TimeModule` docstring, `PrinterContext` docstring,
   [reactive-cells.md](../../documentation/reactive-cells.md) purity note (the clock
   enters the graph through a `Clock`'s cell), and record the per-editor decision in
   [animation-global-time.md](animation-global-time.md).

Commit per step; do the work in a dedicated worktree.

## Deferred / related

- **Reader-armed widgets per-editor** (WidgetSwitch et al.): needs the clock
  reachable from readers (iomap-borne clock, or a reader context analogous to
  `PrinterContext`). Separate follow-up. Until then they use the default clock.
- **`PerformanceCounterModule` is the same singleton class of bug**
  ([PerformanceCounter.jl](../../package/kernel/src/cell/PerformanceCounter.jl)):
  the process-global `_perf` dict is reset each frame by `run_editor!`, so two
  editors stomp each other's counters. Same fix shape (move onto `Editor`). Not in
  scope here; worth a sibling plan.

## Open questions

- **Editor default clock — the real remaining decision.**
  - *Ambient `DEFAULT_CLOCK` (proposed).* Keeps the example harness surgery-free and
    keeps reader-armed widgets (WidgetSwitch) animating in the default editor.
    Independence is opt-in: pass distinct `Clock`s. Two no-arg editors share the
    ambient clock (not independent), which is acceptable because independence is the
    deliberate case the optional argument exists for.
  - *Fresh `Clock()` per editor.* Auto-isolates projection-driven animations across
    editors with zero wiring — but (a) the harness must thread a per-run clock and
    rebuild self-animating documents against it, and (b) reader-armed widgets stop
    animating (their reader can only reach the ambient clock, which the editor no
    longer ticks). Both costs are about the reader seam and the pre-built-document
    harness, **not** backward compatibility.

  Proposed: ambient default now; revisit fresh-per-editor once the reader-seam
  follow-up lands (which removes cost (b)).
- **When `Clock` gains pause / rate / seek**: deferred; the struct is ready for it.
