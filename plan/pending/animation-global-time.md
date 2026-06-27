# Animation via a Global Time Cell

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> Animation support falls out of the existing reactive system almost for free
> by introducing **time** as a single global `Cell` that is rewritten once per
> printer cycle. Any projection can *subscribe* to it
> (`reactive_editor_time()` — become a dependent, re-run every frame) or merely
> *sample* it (`editor_time()` — read the value, no dependency). No new
> evaluation model, no tweening engine bolted onto the side — animation is just
> an ordinary reactive dependency on one extra cell. Finished animations simply
> evaluate to their final value; there is no retirement machinery, and the
> reactive layer is left untouched.

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
that fades out after an edit, a point rotating forever on a circle. Every one of
these is "attach a value that is a function of time to a spot in the document
and let it redraw itself".

The whole point of the reactive cell system is that *when an input cell is
written, everything downstream that read it recomputes lazily on the next
pull*. Animation is the same shape with exactly one new input: **a clock**.

---

## Core Idea

Introduce a single global, primitive `Cell` — `EDITOR_TIME` — that holds the
current logical time. The main loop **writes** it once per cycle:

```julia
# inside run!, each frame, before print!
tick!()      # EDITOR_TIME[] = <current logical time>
```

Because invalidation is **write-driven** (see
[design-decisions §10](../../documentation/design-decisions.md) and
[reactive-cells.md](../../documentation/reactive-cells.md)), writing
`EDITOR_TIME` unconditionally invalidates every cell that *read* it —
transitively — and the next pull during `write_to_devices` recomputes exactly
those cells and nothing else. A projection animates a field by wiring a
*computed* cell that subscribes to time:

```julia
# x = 10 at t0, eases to 100 at t1, holds at 100 afterwards
position_x = Cell(() -> animate(10.0, 100.0, t0, t1; easing = ease_out)(reactive_editor_time()))
```

That is the entire mechanism. The reactive graph already does the rest:
incrementality (only time-dependent cells recompute), composition (a
time-dependent cell can feed any other computed cell), and laziness (an
off-screen animated node is never pulled, so it costs nothing).

---

## Two read modes: subscribe vs sample

A single tracked read conflates two genuinely different intents, and the
conflation is a footgun: *anyone* who subscribes to time from inside a
computation becomes reactive on it, whether they meant to or not. So expose two
named reads, backed by **one cell** (single source of truth):

- **`reactive_editor_time()` — subscribe.** "Wake me every frame." A tracked
  read of `EDITOR_TIME`; the calling cell becomes a dependent and re-runs on
  every tick. This is what an animated value wants. The `reactive_` prefix is
  deliberately loud: it announces that calling this makes you reactive.
- **`editor_time()` — sample.** "What time is it right now?" An *untracked* read
  that registers no dependency. This is what *arming* an animation wants —
  capturing the start instant — without the arming code itself becoming reactive
  and re-running every frame.

The untracked read is a *generic reactive primitive* — Solid has `untrack`/
`peek`, MobX has `untracked`; it is not an animation concept, so it belongs in
the engine without leaking anything downward:

```julia
# Layer 0 (Reactive.jl) — generic untracked read, no dependency registered:
peek(c::Cell) = (c.valid || recompute!(c); c.value)
```

```julia
# time layer:
const EDITOR_TIME      = Cell(0.0)
reactive_editor_time() = EDITOR_TIME[]      # SUBSCRIBE — tracked, re-runs every tick
editor_time()          = peek(EDITOR_TIME)  # SAMPLE    — untracked, essentially free
```

For a *primitive* cell like `EDITOR_TIME`, `peek` never recomputes
(`EDITOR_TIME.value` is always valid after the loop writes it), registers no
edge, and skips the dependency-tracking branch in `getindex` — strictly cheaper
than the subscribing read.

> **The footgun is symmetric — the names guard against it.** Sampling
> (`editor_time()`) inside a thunk that *should* animate yields a value that is
> correct once and then frozen forever (no dependency → never re-runs). The
> `reactive_` prefix makes the subscribing call the conspicuous one, so reaching
> for the bare `editor_time()` reads as the deliberate "just the number" choice.

Why not two independent globals (a plain `Ref` plus the cell)? It works and
needs no `peek`, but it duplicates the source of truth: the loop must write both,
and a future edit that updates one and forgets the other gives a silent
intra-frame divergence that is miserable to debug. One cell read two ways keeps a
single place where time lives; "sample" and "subscribe" are just two reads of it.

---

## Why this fits the reactive model (the important subtlety)

The reactive engine has a hard purity invariant
([reactive-cells.md](../../documentation/reactive-cells.md), "Invariants the
engine relies on"):

> **Thunks must be pure and deterministic in their cell inputs** … depend only
> on the cells it reads (**no clocks**, RNG, or external mutable state) — or the
> cache is wrong.

A naïve animation implementation would read `Base.time()` *inside* a thunk —
exactly the forbidden pattern: the thunk's value would depend on something the
engine cannot see, so its cached result would be silently stale and never
invalidated.

Making time a **cell that the loop writes** is precisely what makes this legal.
A thunk that calls `reactive_editor_time()` reads a real cell, so:

- the dependency is tracked (the thunk becomes a dependent of `EDITOR_TIME`);
- the value only changes when `EDITOR_TIME` is *written*, which the loop does
  explicitly and observably;
- the cached value is correct between writes and invalidated on each write.

So the rule isn't "animation is impossible", it's "the clock must enter the
graph through a cell, not through a side channel". This plan is the disciplined
way to add a clock without breaking purity. (The existing wording in
reactive-cells.md should be updated to say "no *ad-hoc* clocks — subscribe via
`reactive_editor_time()`, or sample via `editor_time()`".)

---

## Design

### 1. The time cell and its two readers

Lives in [package/kernel/src/common/Reactive.jl](../../package/kernel/src/common/Reactive.jl),
next to the engine it belongs to (and the existing global `_computing` stack),
so any layer can read it without a dependency cycle:

```julia
const EDITOR_TIME = Cell(0.0)   # current logical time, seconds (single source of truth)

peek(c::Cell) = (c.valid || recompute!(c); c.value)   # generic untracked read

reactive_editor_time() = EDITOR_TIME[]       # SUBSCRIBE: tracked read (animated thunks)
editor_time()          = peek(EDITOR_TIME)   # SAMPLE:    untracked read (arm animations)
tick!(t)               = (EDITOR_TIME[] = t) # loop writes the new time
```

`Float64` seconds is the natural unit for easing math; a frame counter is the
alternative but couples animations to frame rate and makes easing awkward.
`peek`, `reactive_editor_time`, and `editor_time` are added to the engine's
exports; `peek` is a generic untracked read, not animation-specific.

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
advance!(clock) → writes EDITOR_TIME[] with the current logical time
seek!(clock, t)  → EDITOR_TIME[] = t   (scrubbing / tests)
pause!/resume!/set_rate!
```

The loop calls `advance!(clock)` each frame; tests call `seek!`. The cell stays
the single source of truth (so both `reactive_editor_time()` and `editor_time()`
see the new value immediately); the `Clock` is just policy over *what value gets
written*.

### 3. Main-loop integration

In `run!`, write time every frame before printing:

```julia
while true
    perf_reset!()
    advance!(editor.clock)                  # ← EDITOR_TIME[] = logical now
    @perf_time :read_time     read!(editor)
    @perf_time :evaluate_time evaluate!(editor)
    @perf_time :print_time    print!(editor)        # re-pulls invalidated cells
    perf!(editor)
    sleep(0.01)
end
```

`print!` already calls `write_to_devices`, which re-reads the output canvas
cells every frame (confirmed in
[ProjecturedSdl.jl `write_to_devices`](../../package/sdl/src/ProjecturedSdl.jl)
— it walks `screen.windows` → `w.content` → renders the canvas, all
cell-backed). So no structural change to the print path is needed: bumping
`EDITOR_TIME` invalidates the animated cells, and the existing per-frame pull
recomputes them. The cached `editor.iomap` does **not** need to be discarded —
the *structure* is unchanged, only animated *values* recompute. This is the
whole reason it's cheap.

> Note one consequence: today idle frames recompute nothing. After this change,
> idle frames still recompute nothing *as long as no animated cell subscribes to
> time*. Writing `EDITOR_TIME` with zero dependents only walks an empty dependent
> set — cheap. CPU cost appears only when something is actually animating. See
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

A projection wires one into a computed cell, **sampling** the start instant so
the arming code does not itself subscribe to time:

```julia
t0 = editor_time()              # SAMPLE the absolute start (no subscription)
t1 = t0 + 0.5
setfn!(getfield(node, :position_x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(reactive_editor_time()))  # SUBSCRIBE
```

**Absolute vs. relative start times.** Animation start times should be
*absolute* (`t0` captured from `editor_time()` at the moment the animation is
armed), not "N seconds from when this cell was built". Cells get rebuilt
whenever the iomap is dropped (e.g. after a whole-document swap,
[Operation.jl](../../package/kernel/src/common/Operation.jl) sets
`editor.iomap = nothing`). Absolute start times mean a rebuild doesn't restart
mid-flight animations.

### 5. When an animation finishes

A finite animation's thunk simply evaluates to its final value once `t >= t1`
and keeps doing so every frame. We deliberately do **not** convert the cell back
to a primitive — there is no retirement registry, no manager, no sweep.

Why that is the right call:

- **The leftover work is trivial.** A settled animation recomputes to a constant:
  read time, return `to`. Cheap arithmetic, no downstream change.
- **Dirty-rect rendering elides the repaint.** The recomputed value equals last
  frame's, so the renderer sees nothing to redraw. The residual cost is a thunk
  evaluation, not pixels — and only while the node is actually on-screen (an
  off-screen settled cell is invalidated but never pulled, so it costs nothing).
- **Every mechanism for *actually* stopping the subscription is worse than the
  problem.** An engine sentinel leaks animation into Layer 0; a self-`setval!`
  thunk breaks purity; an external registry adds bookkeeping (stale entries on
  iomap rebuild, `WeakRef`s, ordering after print) to save what dirty-rect
  already saves. See Rejected Alternatives.

The one real consequence is honest to state: a settled, on-screen animation
keeps `EDITOR_TIME`'s dependent set non-empty, so the idle-gating optimization
(§7) cannot treat the editor as fully idle while any finished animation is
visible. In practice the per-frame work is negligible. If it ever does bite, the
fix is a better idle signal — not a registry.

### 6. Output-only, but the *spec* is editable

Interpolated values flow printer → graphics only; there is nothing to read back
(you don't "edit" an eased x at frame 37). So **animations need no reader** —
they're outside the bidirectional contract, like a computed layout coordinate.

But the *animation specification* (the keyframes, durations, easing) is itself
data and can be a document that is projected and edited like anything else
(a timeline/curve editor is a natural future projection). That keeps the
"everything is a projected document" story intact: the spec is editable data,
the playback is a derived value.

---

## Worked example A — a value that settles (`x: 10 → 100`)

`x = 10` at `t0`, animates to `100` at `t1`, then stays at `100`:

```julia
t0 = editor_time()              # SAMPLE the absolute start
t1 = t0 + 0.5                   # half-second slide
setfn!(getfield(rect, :x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(reactive_editor_time()))  # SUBSCRIBE
```

- Before `t0`: pulls return `10`.
- Between `t0` and `t1`: each frame `EDITOR_TIME` is written → the `x` cell is
  invalidated → next pull recomputes the eased value → the rect redraws.
- After `t1`: the thunk returns the constant `100` every frame. The cell keeps
  subscribing to time, but the value never changes, so dirty-rect skips the
  repaint and the leftover cost is one trivial recompute per frame while the rect
  is on-screen (§5).

---

## Worked example B — rotating vector with sine & cosine charts

The canonical unit-circle demonstration, and a good stress of composition: a
point rotates forever on a circle, while two line charts trace its coordinates —
the **sine** of the angle (the y-coordinate) aligned to the vertical axis, and
the **cosine** (the x-coordinate) aligned to the horizontal axis. It never ends,
so it stays subscribed to time forever — the always-on counterpart to the
settling example A.

### Layout

```
                 sin chart  (aligned to the Y axis, scrolls right, traces sin)
                 ───────────────────────────────▶ time
        ╭───────╮ ·····(horizontal link lines the dot's y to the curve)
        │   •────┼···
        │  ╱     │            the dot rides the circle at (cos θ, sin θ);
        │ C   R  │            its Y projects right into the sin curve,
        ╰───────╯            its X projects down into the cos curve.
            ┊
            ┊ (vertical link lines the dot's x to the curve)
            ▼ time
   cos chart  (aligned to the X axis, scrolls down, traces cos)
```

### Wiring

Center `(cx0, cy0)`, radius `R`, angular velocity `ω`. Screen-y grows downward,
so we negate the sine to make "up" positive. The phase origin is **sampled** at
arm time; every animated value **subscribes** to time.

```julia
const ω  = 2.0          # rad / s
const R  = 120
const N  = 240          # samples in each chart's time window
const dθ = 0.02         # angle between adjacent samples
const GAP = 24

phase0 = editor_time()              # SAMPLE the start instant (no subscription)
θ(t)   = ω * (t - phase0)

# ── the rotating dot (GraphicsCircle) ──────────────────────────────────────
setfn!(getfield(dot, :cx), () -> round(Int32, cx0 + R * cos(θ(reactive_editor_time()))))
setfn!(getfield(dot, :cy), () -> round(Int32, cy0 - R * sin(θ(reactive_editor_time()))))

# ── sine chart (GraphicsPolyline) — aligned to the Y axis, scrolling right ─
# newest sample (i = 0) sits at the chart's left edge, at the dot's exact cy,
# so a horizontal link line meets the curve where the dot is.
setfn!(getfield(sin_chart, :points), () -> begin
    t = reactive_editor_time()                                             # SUBSCRIBE
    [(cx0 + R + GAP + i, round(Int, cy0 - R * sin(θ(t) - i * dθ))) for i in 0:N]
end)

# ── cosine chart (GraphicsPolyline) — aligned to the X axis, scrolling down ─
# newest sample (i = 0) sits at the chart's top edge, at the dot's exact cx,
# so a vertical link line meets the curve where the dot is.
setfn!(getfield(cos_chart, :points), () -> begin
    t = reactive_editor_time()                                             # SUBSCRIBE
    [(round(Int, cx0 + R * cos(θ(t) - i * dθ)), cy0 + R + GAP + i) for i in 0:N]
end)
```

Two optional connector lines (`GraphicsLine`) make the projection legible — each
reads the dot's animated coordinate (so it animates transitively, no new time
read needed):

```julia
# horizontal link: dot → left edge of the sin chart, at the dot's y
setfn!(getfield(sin_link, :x1), () -> dot.cx);  setfn!(getfield(sin_link, :y1), () -> dot.cy)
setfn!(getfield(sin_link, :x2), () -> Int32(cx0 + R + GAP)); setfn!(getfield(sin_link, :y2), () -> dot.cy)
# vertical link: dot → top edge of the cos chart, at the dot's x  (symmetric)
```

### Why this is a good test

- **Analytic, fully pure.** The charts recompute their whole polyline from time
  each frame — no stored history, no per-frame side effect. The curve *scrolls*
  because the window `[θ(t) − N·dθ, θ(t)]` slides forward; this is the clean,
  side-effect-free way to draw a moving signal. (For a non-analytic signal you'd
  keep a ring buffer instead — stateful, and explicitly the not-pure case; call
  it out where used.)
- **Composition.** The link lines depend on the dot's cells, which subscribe to
  time; invalidation flows through two hops with no special handling.
- **Alignment falls out of the math.** The newest chart sample equals the dot's
  projected coordinate by construction, so "aligned to the corresponding axis"
  needs no extra layout logic.
- **Perpetual ⇒ exercises the always-on path.** Nothing settles — the
  counterpart to example A. Ship both as examples
  (`run_example("rotating_vector")` and a settling demo) so reviewers see the
  always-on and settle-to-constant behaviours side by side.
- **Deterministic capture.** Frames at `seek!(clock, kΔt)` produce a filmstrip
  of the rotation for image/video tests (see Determinism and the video plans).

---

## Implementation Steps

### 1. Time cell, readers, clock
- Add `EDITOR_TIME`, `peek`, `reactive_editor_time()` (subscribe),
  `editor_time()` (sample), `tick!`/`seek!` to `Reactive.jl`; export them.
  `peek` is a generic untracked read, not animation-specific.
- Add a `Clock` struct with `advance!/seek!/pause!/resume!/set_rate!`.
- Hold a `Clock` on the `Editor`.

### 2. Loop integration
- Call `advance!(editor.clock)` at the top of each `run!` frame (all three loop
  variants: plain, bootstrap, and the timeline-driven `run!`).
- Confirm `write_to_devices` re-pulls animated cells with the iomap cached
  (verify with a one-cell smoke test).

### 3. Animation helpers
- Pure `animate`, easing library, `keyframes`, `repeat`, `pingpong`, `delay`,
  `sequence` in a new `Animation.jl` (graphics layer).
- All pure and generic over interpolatable values (numbers, colors, points).

### 4. Examples
- **Settling demo** (example A): a value that eases to a constant and then holds.
  Use `perf_counters()` to confirm the settled cell does only a trivial constant
  recompute and triggers no repaint.
- **Rotating vector** (example B): the circle + sin/cos charts above, as a
  graphics-domain example wired entirely from time. Run via `run_example(...)`;
  capture a filmstrip via `write_image` at successive `seek!` values.

### 5. Determinism for tests / headless
- `test_printers` and friends must pin time: `seek!(clock, FIXED_T)` (or
  `EDITOR_TIME[] = 0.0`) before projecting, so printer output is reproducible.
- `write_example_image` / screenshot helpers take an optional `at::Float64`
  that does `seek!` before rendering.
- Add a test that bumps `EDITOR_TIME` across two values and asserts an animated
  coordinate changed (and that a non-animated sibling did **not** recompute —
  the incrementality guarantee).

### 6. Idle/active gating (performance)
- Detect whether anything is animating by inspecting `EDITOR_TIME`'s dependent
  set (non-empty ⇒ animations live). When empty, the loop can `sleep` longer /
  skip the redraw entirely. Note this gate is conservative: a settled but
  on-screen animation keeps the set non-empty (§5), so it only fully idles a
  document with no live animated cells at all.

---

## Performance

- **Idle is still free.** Writing `EDITOR_TIME` with no subscribers walks an
  empty set. The only always-on cost is the write itself plus the existing 10 ms
  poll loop.
- **`editor_time()` is cheaper than `reactive_editor_time()`.** Sampling skips
  dependency tracking and never recomputes a primitive cell — so arming an
  animation adds negligible cost and, crucially, registers no edges.
- **Active cost is proportional to the animated subtree**, by construction of
  the pull-based engine — siblings that don't subscribe to time never recompute.
  Use `perf_counters()` to confirm `:computes` per frame tracks only the
  animated nodes.
- **Settled animations cost a constant recompute, not a repaint.** A finished
  finite animation keeps subscribing to time and re-evaluates to its final value
  each frame; dirty-rect rendering
  ([optimize-rendering-dirty-rect.md](../pending/optimize-rendering-dirty-rect.md))
  sees no change and skips the draw. The residual is arithmetic, and only for
  on-screen nodes.
- **Synergy with dirty-rect rendering.** Animation is the strongest motivation
  for per-frame partial redraw — only the moving region needs repainting, and the
  reactive graph already knows which cells changed. It is also what makes
  not-retiring acceptable.

---

## Open Questions

- **Logical time origin & units.** Seconds since editor start (Float64) is the
  proposal. Confirm easing math and `keyframes` read cleanly in those units;
  decide whether `Clock.rate`/pause are needed in v1 or can be deferred (realtime
  monotonic clock is the minimum).
- **Idle after animations.** Without a retirement step, a settled on-screen
  animation keeps the editor out of the fully-idle state (§5, §6). If
  battery/CPU at rest becomes a concern, find a cheaper idle signal (e.g. "no
  cell's value changed this frame") rather than reintroducing a registry.
- **Determinism vs. realtime.** Tests/headless use `seek!`; the live editor uses
  `advance!`. Audit projection code for any direct `Base.time()`/`time_ns()` —
  everything must go through `EDITOR_TIME` (subscribe or sample).
- **Where helpers live.** `Animation.jl` in the graphics layer vs a standalone
  package. The cell + `peek` + the two readers belong in the kernel; the
  easing/keyframe vocabulary belongs with graphics.
- **Generality of interpolation.** `animate` over numbers is obvious; over colors
  (fades), points (motion paths), and styled-string attributes needs an
  interpolation typeclass (`lerp(a, b, fraction)` per type).
- **Non-analytic signals.** Example B is analytic (recomputed from time). Charts
  of measured/streamed signals need a stored history (ring buffer), which is
  stateful — decide how that state is owned without violating thunk purity
  (likely a primitive cell holding the buffer, written by an external sampler in
  the loop, exactly like `EDITOR_TIME` itself).
- **Arming on state change.** Self-starting animations (examples A, B) capture
  `t0` at construction. Animations triggered by an edit (a toggle sliding when
  its bool flips) need to arm `t0` at the moment the state changes — which can't
  be a thunk side effect. The natural home is the loop (an untracked per-frame
  comparison of the watched value, rewiring the presentation cell on change) or
  the operation/evaluate path. Worth a worked widget example before committing.
- **Spec as a document.** Modelling keyframes/curves as an editable document (a
  timeline editor projection) is attractive but a separate, larger effort; v1
  can hardcode animation specs in projection code.
- **Frame pacing.** The fixed 10 ms `sleep` gives a ~100 fps ceiling regardless
  of load. Animation may want a target frame interval and to skip frames under
  load; out of scope for v1 but worth noting.

---

## Rejected Alternatives

- **A retirement registry** (an `AnimationManager` that tracks finite animations
  and converts each finished cell back to a primitive via `setval!`). Considered
  and dropped: its only real benefit is letting the editor go fully idle again
  after an animation ends, and that does not justify the bookkeeping it requires
  (stale registrations on iomap rebuild, `WeakRef` cells, retire-after-print
  ordering, coupling projections to a manager). Dirty-rect rendering already
  elides the repaint of a settled animation, so the saving is a trivial constant
  recompute (§5). Not worth a subsystem.
- **An engine-level "freeze" sentinel** (a `Frozen` value the thunk returns and
  `recompute!` special-cases to retire the cell). Rejected: it drags a
  higher-layer lifetime/animation concept *down* into Layer 0, which must stay
  generic and dependency-free. The leak is contagious — every future reader of
  the engine would have to understand a concept that belongs three layers up.
- **Self-elimination inside the thunk** (the thunk calls `setval!` on its own
  cell when done). It happens to work — under the monotone-invalidation
  invariant the self-write's dependent walk is a no-op, because every dependent
  is already invalid while the cell is being recomputed from a time write. But it
  violates the thunk-purity contract (a side effect inside a thunk that may run
  0/1/many times), relies on a non-obvious proof, has a read-ordering trap (must
  not read any cell after eliminating), and is fragile against any future engine
  change (value-equality short-circuit, speculative/parallel recompute).
- **Two independent time globals** (a plain `Ref` plus the cell). Works and needs
  no `peek`, but duplicates the source of truth and invites silent intra-frame
  divergence. One cell read two ways (`reactive_editor_time()` / `editor_time()`)
  is the same ergonomics without the duplication.

---

## Relationship to Existing Plans

| Plan | Overlap |
|---|---|
| [optimize-rendering-dirty-rect.md](../pending/optimize-rendering-dirty-rect.md) | Animation is the strongest motivation for partial redraw — only the moving region changes each frame. It is also what makes *not* retiring settled animations acceptable (the repaint is skipped). Should land together or at least be co-designed. |
| [headless-video-recording.md](../done/headless-video-recording.md) / [extract-video-package.md](../done/extract-video-package.md) | Rendering successive `seek!(t)` frames to images *is* video. The rotating-vector example is a natural recorded-animation test case. |
| [generate-screenshots.md](../done/generate-screenshots.md) / [write-image.md](../done/write-image.md) | Deterministic screenshots require pinning time; these helpers should grow an `at::Float64` parameter. |
| timeline-driven `run!` (in [Editor.jl](../../package/kernel/src/editor/Editor.jl)) | That loop injects *operations* on a schedule (event-level scripting). Animation is the *value-level* analog — interpolated state rather than discrete operations. Conceptually complementary; both are "the editor changing without live user input". |
| [tooltip.md](../pending/tooltip.md) / [annotation.md](../tentative/annotation.md) | Fade-in/out and slide presentations for popups and annotations become trivial once a time cell exists. |

---

## Dependencies

- The reactive cell engine ([Reactive.jl](../../package/kernel/src/common/Reactive.jl))
  — `EDITOR_TIME`, the generic `peek` (untracked read), and the two readers
  `reactive_editor_time()` / `editor_time()` are added there; write-driven
  invalidation is the load-bearing mechanism and already exists.
- The main loop ([Editor.jl](../../package/kernel/src/editor/Editor.jl)) — one
  `advance!` call per frame; the per-frame `write_to_devices` re-pull already
  happens.
- The graphics domain primitives used by example B already exist:
  `GraphicsCircle`, `GraphicsPolyline`, `GraphicsLine`, `GraphicsCanvas`
  ([Graphics.jl](../../package/domain/src/document/Graphics.jl)) — all
  cell-backed, so their fields can be driven by computed cells that subscribe to
  time.
- No backend changes for in-canvas animation (the SDL/web/console backends
  already re-render the cell-backed canvas each frame).
- A doc correction to
  [reactive-cells.md](../../documentation/reactive-cells.md): the purity rule
  should clarify that the clock enters the graph through the `EDITOR_TIME` cell
  (subscribe via `reactive_editor_time()`, sample via `editor_time()`), never via
  an ad-hoc wall-clock read inside a thunk.
