# Animation via a Global Time Cell

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> Animation support falls out of the existing reactive system almost for free
> by introducing **time** as a single global `Cell` that is rewritten once per
> printer cycle. Any projection can read it; a computed cell that reads time
> produces a value that changes every frame. No new evaluation model, no
> tweening engine bolted onto the side — animation is just an ordinary
> reactive dependency on one extra cell.

---

## Motivation

Today the editor only does visible work when the user does something. The main
loop (`run!` in [package/kernel/src/editor/Editor.jl](../../package/kernel/src/editor/Editor.jl))
reads an input gesture, evaluates the resulting operation, and reprints. When
there is no operation, `evaluate!` is a no-op, `editor.iomap` stays cached, and
`print!` just re-writes the same canvas. Nothing changes between frames unless a
cell was written.

There is no way to express a value that varies *over time on its own* — a
position that eases from `x = 10` to `x = 100` over half a second and then
holds, a cursor that blinks, a panel that slides in when opened, a highlight
that fades out after an edit. Every one of these is "attach a value that is a
function of wall-clock time to a spot in the document and let it redraw itself".

The whole point of the reactive cell system is that *when an input cell is
written, everything downstream that read it recomputes lazily on the next
pull*. Animation is the same shape with exactly one new input: **a clock**.

---

## Core Idea

Introduce a single global, primitive `Cell` — call it `TIME` — that holds the
current logical time. The main loop **writes** it once per cycle:

```julia
# inside run!, each frame, before print!
tick!(TIME)      # TIME[] = <current logical time>
```

Because invalidation is **write-driven** (see
[design-decisions §10](../../documentation/design-decisions.md) and
[reactive-cells.md](../../documentation/reactive-cells.md)), writing `TIME`
unconditionally invalidates every cell that read it — transitively — and the
next pull during `write_to_devices` recomputes exactly those cells and nothing
else. A projection animates a field by wiring a *computed* cell that reads
`TIME`:

```julia
# x = 10 at t0, eases to 100 at t1, holds at 100 afterwards
position_x = Cell(() -> animate(10.0, 100.0, t0, t1; easing = ease_out)(TIME[]))
```

That is the entire mechanism. The reactive graph already does the rest:
incrementality (only time-dependent cells recompute), composition (a
time-dependent cell can feed any other computed cell), and laziness (an
off-screen animated node is never pulled, so it costs nothing).

---

## Why this fits the reactive model (the important subtlety)

The reactive engine has a hard purity invariant
([reactive-cells.md](../../documentation/reactive-cells.md), "Invariants the
engine relies on"):

> **Thunks must be pure and deterministic in their cell inputs** … depend only
> on the cells it reads (**no clocks**, RNG, or external mutable state) — or the
> cache is wrong.

A naïve animation implementation would read `Base.time()` *inside* a thunk —
which is exactly the forbidden pattern: the thunk's value would depend on
something the engine cannot see, so its cached result would be silently stale
and never invalidated.

Making time a **cell that the loop writes** is precisely what makes this legal.
The thunk reads `TIME[]` — a real cell — so:

- the dependency is tracked (the thunk becomes a dependent of `TIME`);
- the value only changes when `TIME` is *written*, which the loop does
  explicitly and observably;
- the cached value is correct between writes and invalidated on each write.

So the rule isn't "animation is impossible", it's "the clock must enter the
graph through a cell, not through a side channel". This plan is the disciplined
way to add a clock without breaking purity. (The existing wording in
reactive-cells.md should be updated to say "no *ad-hoc* clocks — read the global
`TIME` cell instead".)

---

## Design

### 1. The time cell

Lives in [package/kernel/src/common/Reactive.jl](../../package/kernel/src/common/Reactive.jl),
next to the engine it belongs to (and the existing global `_computing` stack),
so any layer can read it without a dependency cycle:

```julia
const TIME = Cell(0.0)          # current logical time, seconds

now_time() = TIME[]             # convenience read (tracks the dependency)
tick!(t)   = (TIME[] = t)       # loop writes the new time
```

`Float64` seconds is the natural unit for easing math; a frame counter is the
alternative but couples animations to frame rate and makes easing awkward.

### 2. A small clock abstraction (logical, not wall-clock)

For an *editor* the clock should be more than `Base.time()`. Animations want to
be pausable, seekable, and resettable — for scrubbing a timeline, recording,
and (critically) deterministic tests and headless rendering. Wrap the cell:

```julia
mutable struct Clock
    origin::Float64     # wall-clock reference
    paused_at::Union{Float64,Nothing}
    rate::Float64       # 1.0 = realtime; 0 = frozen; >1 = fast
end
advance!(clock) → writes TIME[] with the current logical time
seek!(clock, t)  → TIME[] = t   (scrubbing / tests)
pause!/resume!/set_rate!
```

The loop calls `advance!(clock)` each frame; tests call `seek!`. The cell stays
the single source of truth; the `Clock` is just policy over *what value gets
written*.

### 3. Main-loop integration

In `run!`, write time every frame before printing:

```julia
while true
    perf_reset!()
    advance!(editor.clock)              # ← TIME[] = logical now
    @perf_time :read_time     read!(editor)
    @perf_time :evaluate_time evaluate!(editor)
    @perf_time :print_time    print!(editor)   # re-pulls invalidated cells
    perf!(editor)
    sleep(0.01)
end
```

`print!` already calls `write_to_devices`, which re-reads the output canvas
cells every frame (confirmed in
[ProjecturedSdl.jl `write_to_devices`](../../package/sdl/src/ProjecturedSdl.jl)
— it walks `screen.windows` → `w.content` → renders the canvas, all
cell-backed). So no structural change to the print path is needed: bumping
`TIME` invalidates the animated cells, and the existing per-frame pull
recomputes them. The cached `editor.iomap` does **not** need to be discarded —
the *structure* is unchanged, only animated *values* recompute. This is the
whole reason it's cheap.

> Note one consequence: today idle frames recompute nothing. After this change,
> idle frames still recompute nothing *as long as no animated cell depends on
> TIME*. Writing `TIME` with zero dependents only walks an empty dependent set —
> cheap. CPU cost appears only when something is actually animating. See
> Performance below.

### 4. Animation helpers (value-level)

Give projections a vocabulary for "value as a function of time" so they don't
hand-roll interpolation. A pure helper that returns a function of `t`:

```julia
animate(from, to, t0, t1; easing = linear) = t ->
    t <= t0 ? from :
    t >= t1 ? to   :
    from + (to - from) * easing((t - t0) / (t1 - t0))
```

Easing functions (`linear`, `ease_in`, `ease_out`, `ease_in_out`, `spring`, …)
are pure `Float64 → Float64`. Composites:

- `keyframes([(t0, v0), (t1, v1), (t2, v2), …]; easing)` — piecewise.
- `repeat(anim, period)` / `pingpong(anim, period)` — looping (blink, pulse).
- `delay(anim, d)` / `after(t_start, anim)` — start offsets.
- `sequence(anim1, anim2, …)` — chain.

A projection wires one into a computed cell:

```julia
setfn!(getfield(node, :position_x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(TIME[]))
```

**Absolute vs. relative start times.** Animation start times should be
*absolute* (`t0` captured from `TIME[]` at the moment the animation is armed),
not "N seconds from when this cell was built". Cells get rebuilt whenever the
iomap is dropped (e.g. after a whole-document swap,
[Operation.jl](../../package/kernel/src/common/Operation.jl) sets
`editor.iomap = nothing`). Absolute start times mean a rebuild doesn't restart
mid-flight animations.

### 5. Output-only, but the *spec* is editable

Interpolated values flow printer → graphics only; there is nothing to read back
(you don't "edit" an eased x at frame 37). So **animations need no reader** —
they're outside the bidirectional contract, like a computed layout coordinate.

But the *animation specification* (the keyframes, durations, easing) is itself
data and can be a document that is projected and edited like anything else
(a timeline/curve editor is a natural future projection). That keeps the
"everything is a projected document" story intact: the spec is editable data,
the playback is a derived value.

---

## Worked example (the one from the request)

`x = 10` at `t0`, animates to `100` at `t1`, then stays at `100`:

```julia
t0 = now_time()                 # absolute start, captured when armed
t1 = t0 + 0.5                   # half-second slide
setfn!(getfield(rect, :x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(TIME[]))
```

- Before `t0`: pulls return `10`.
- Between `t0` and `t1`: each frame `TIME` is written → the `x` cell is
  invalidated → next pull recomputes the eased value → the rect redraws at its
  new position.
- After `t1`: the cell still recomputes each frame (write-driven, no equality
  short-circuit) but returns a constant `100`. See "settling" under Open
  Questions for stopping that churn.

---

## Implementation Steps

### 1. Time cell + clock
- Add `TIME`, `now_time()`, `tick!`/`seek!` to `Reactive.jl`; export them.
- Add a `Clock` struct with `advance!/seek!/pause!/resume!/set_rate!`.
- Hold a `Clock` on the `Editor` (default realtime, rate 1.0).

### 2. Loop integration
- Call `advance!(editor.clock)` at the top of each `run!` frame (all three
  loop variants: plain, bootstrap, and the timeline-driven `run!`).
- Confirm `write_to_devices` re-pulls animated cells with the iomap cached
  (it should — verify with a one-cell smoke test).

### 3. Animation helpers
- Pure `animate`, easing library, `keyframes`, `repeat`, `pingpong`, `delay`,
  `sequence` in a new `Animation.jl` (graphics or a new `animation` layer).
- All pure `Float64`-in/`Float64`-out (and generic over interpolatable values
  — numbers, colors, points).

### 4. First animated projection (demo)
- A graphics-domain decoration that slides/fades a node, wired to `TIME`.
- Example: a panel that eases in on open, or a post-edit highlight that fades.
- Run via `run_example(...)` to see motion; capture frames via `write_image`
  at successive `seek!` values to verify deterministically.

### 5. Determinism for tests / headless
- `test_printers` and friends must pin time: `seek!(clock, FIXED_T)` (or
  `TIME[] = 0.0`) before projecting, so printer output is reproducible.
- `write_example_image` / screenshot helpers take an optional `at::Float64`
  that does `seek!` before rendering.
- Add a test that bumps `TIME` across two values and asserts an animated
  coordinate changed (and that a non-animated sibling did **not** recompute —
  the incrementality guarantee).

### 6. Idle/active gating (performance)
- Detect whether anything is animating by inspecting `TIME`'s dependent set
  (non-empty ⇒ animations live). When empty, the loop can `sleep` longer / skip
  the redraw entirely.
- Optionally let animations *retire*: once an `animate` has passed `t1` and is
  constant, detach the cell's dependency on `TIME` (switch it from a computed
  cell back to a primitive holding the final value) so it stops being
  invalidated every frame. This is the "settling" optimization.

---

## Performance

- **Idle is still free.** Writing `TIME` with no dependents walks an empty set.
  The only always-on cost is the write itself plus the existing 10 ms poll loop.
- **Active cost is proportional to the animated subtree**, by construction of
  the pull-based engine — siblings that don't read `TIME` never recompute. Use
  `perf_counters()` to confirm `:computes` per frame tracks only the animated
  nodes.
- **No equality short-circuit.** A finished animation that recomputes to a
  constant still recomputes every frame (the engine is not value-stabilising).
  The "settling"/retire step (6) is the fix; without it, lots of finished
  animations slowly accrue per-frame churn.
- **Synergy with dirty-rect rendering**
  ([optimize-rendering-dirty-rect.md](../pending/optimize-rendering-dirty-rect.md)):
  animation makes per-frame partial redraw worthwhile — only the moving region
  needs repainting, and the reactive graph already knows which cells changed.

---

## Open Questions

- **Logical time origin & units.** Seconds since editor start (Float64) is the
  proposal. Confirm easing math and `keyframes` read cleanly in those units;
  decide whether `Clock.rate`/pause are needed in v1 or can be deferred (realtime
  monotonic clock is the minimum).
- **Settling / retiring finished animations.** When and how to stop a constant
  animation from recomputing forever. Detaching the `TIME` dependency once
  `t >= t1` is clean but needs a trigger (who notices "it's done"?). One option:
  the helper returns a sentinel when finished and the wiring swaps the cell to a
  primitive. Another: accept the churn and rely on dirty-rect to keep redraw
  cheap.
- **Interaction with the cached iomap.** Confirmed structure is preserved across
  frames, so animated values recompute without a rebuild. But an operation that
  *drops* the iomap (whole-document swap, [Operation.jl](../../package/kernel/src/common/Operation.jl))
  rebuilds and re-arms animations — verify absolute start times survive this and
  in-flight animations don't visibly jump or restart.
- **Determinism vs. realtime.** Tests/headless must use `seek!`; the live editor
  uses `advance!`. Make sure there is no path where a thunk reads wall-clock
  directly (audit for `Base.time()`/`time_ns()` in projection code) — everything
  must go through `TIME`.
- **Where helpers live.** `Animation.jl` in the graphics layer (animations are
  mostly graphics values) vs. a standalone `animation` package vs. the kernel
  (alongside the cell). The cell itself belongs in the kernel; the easing/keyframe
  vocabulary probably belongs with graphics.
- **Generality of interpolation.** `animate` over numbers is obvious; over colors
  (fades), points (motion paths), and styled-string attributes needs an
  interpolation typeclass (`lerp(a, b, fraction)` per type).
- **Spec as a document.** Modelling keyframes/curves as an editable document (a
  timeline editor projection) is attractive but a separate, larger effort; v1
  can hardcode animation specs in projection code.
- **Frame pacing.** The fixed 10 ms `sleep` gives ~100 fps ceiling regardless of
  load. Animation may want a target frame interval and to skip frames under load;
  out of scope for v1 but worth noting.

---

## Relationship to Existing Plans

| Plan | Overlap |
|---|---|
| [optimize-rendering-dirty-rect.md](../pending/optimize-rendering-dirty-rect.md) | Animation is the strongest motivation for partial redraw — only the moving region changes each frame. Should land together or at least be co-designed. |
| [headless-video-recording.md](../done/headless-video-recording.md) / [extract-video-package.md](../done/extract-video-package.md) | Rendering successive `seek!(t)` frames to images *is* video. A global time cell makes recorded animation a natural extension of headless rendering. |
| [generate-screenshots.md](../done/generate-screenshots.md) / [write-image.md](../done/write-image.md) | Deterministic screenshots require pinning time; these helpers should grow an `at::Float64` parameter. |
| timeline-driven `run!` (in [Editor.jl](../../package/kernel/src/editor/Editor.jl)) | That loop injects *operations* on a schedule (event-level scripting). Animation is the *value-level* analog — interpolated state rather than discrete operations. Conceptually complementary; both are "the editor changing without live user input". |
| [tooltip.md](../pending/tooltip.md) / [annotation.md](../tentative/annotation.md) | Fade-in/out and slide presentations for popups and annotations become trivial once a time cell exists. |

---

## Dependencies

- The reactive cell engine ([Reactive.jl](../../package/kernel/src/common/Reactive.jl))
  — `TIME` is added there; write-driven invalidation is the load-bearing
  mechanism and already exists.
- The main loop ([Editor.jl](../../package/kernel/src/editor/Editor.jl)) — one
  `advance!` call per frame; the per-frame `write_to_devices` re-pull already
  happens.
- No backend changes for in-canvas animation (the SDL/web/console backends
  already re-render the cell-backed canvas each frame).
- A one-line doc correction to
  [reactive-cells.md](../../documentation/reactive-cells.md): the purity rule
  should clarify that the clock must enter the graph through the `TIME` cell,
  not via an ad-hoc wall-clock read inside a thunk.
