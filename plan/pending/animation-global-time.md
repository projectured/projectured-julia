# Animation via a Global Time Cell

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> Animation support falls out of the existing reactive system almost for free
> by introducing **time** as a single global `Cell` that is rewritten once per
> printer cycle. Any projection can *subscribe* to it (read `TIME[]`, become a
> dependent, re-run every frame) or merely *sample* it (read `time_now()`, no
> dependency). No new evaluation model, no tweening engine bolted onto the side
> — animation is just an ordinary reactive dependency on one extra cell, and
> retirement of finished animations is done from *above* the engine, leaving
> the reactive layer untouched.

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

Introduce a single global, primitive `Cell` — call it `TIME` — that holds the
current logical time. The main loop **writes** it once per cycle:

```julia
# inside run!, each frame, before print!
tick!(TIME)      # TIME[] = <current logical time>
```

Because invalidation is **write-driven** (see
[design-decisions §10](../../documentation/design-decisions.md) and
[reactive-cells.md](../../documentation/reactive-cells.md)), writing `TIME`
unconditionally invalidates every cell that *read* it — transitively — and the
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

## Two read modes: subscribe vs sample

A single `TIME[]` conflates two genuinely different intents, and the conflation
is a footgun: *anyone* who reads `TIME[]` from inside a computation silently
becomes reactive on it, whether they meant to or not.

- **Subscribe** — "wake me every frame." This is what an animated value wants:
  read `TIME[]`, register the dependency, re-run on every tick.
- **Sample** — "what time is it right now?" This is what *arming* an animation
  wants (capture the start instant), and what the retirement sweep wants (decide
  whether an animation is finished). These must **not** subscribe — otherwise
  the arming/bookkeeping code itself starts re-running every frame.

Back both modes with **one cell** (single source of truth), exposing a second,
untracked read. The untracked read is a *generic reactive primitive* — Solid has
`untrack`/`peek`, MobX has `untracked`; it is not an animation concept, so it
belongs in the engine without leaking anything downward:

```julia
# Layer 0 (Reactive.jl) — generic untracked read, no dependency registered:
peek(c::Cell) = (c.valid || recompute!(c); c.value)
```

```julia
# time layer:
const TIME  = Cell(0.0)
time_now()  = peek(TIME)   # SAMPLE  — no subscription, essentially free
# TIME[]                    # SUBSCRIBE — tracked, re-runs every tick
```

For a *primitive* cell like `TIME`, `peek` never recomputes (`TIME.value` is
always valid after the loop writes it), registers no edge, and skips the
dependency-tracking branch in `getindex` — strictly cheaper than `TIME[]`.

> **The footgun is symmetric — name for intent.** Reading the *sample* form
> inside a thunk that *should* animate yields a value that is correct once and
> then frozen forever (no dependency → never re-runs). Make the call sites
> impossible to confuse. `TIME[]` vs `time_now()` is acceptable; louder still is
> `animated_time()` vs `sample_time()`.

Why not two independent globals (`NOW::Ref` + `TIME::Cell`)? It works and needs
no `peek`, but it duplicates the source of truth: the loop must write both, and a
future edit that updates one and forgets the other gives a silent intra-frame
divergence that is miserable to debug. One cell + `peek` keeps a single place
where time lives; "sample" and "subscribe" are just two reads of it.

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
The thunk reads `TIME[]` — a real cell — so:

- the dependency is tracked (the thunk becomes a dependent of `TIME`);
- the value only changes when `TIME` is *written*, which the loop does
  explicitly and observably;
- the cached value is correct between writes and invalidated on each write.

So the rule isn't "animation is impossible", it's "the clock must enter the
graph through a cell, not through a side channel". This plan is the disciplined
way to add a clock without breaking purity. (The existing wording in
reactive-cells.md should be updated to say "no *ad-hoc* clocks — read the global
`TIME` cell, or sample it via `peek`".)

---

## Design

### 1. The time cell and its two readers

Lives in [package/kernel/src/common/Reactive.jl](../../package/kernel/src/common/Reactive.jl),
next to the engine it belongs to (and the existing global `_computing` stack),
so any layer can read it without a dependency cycle:

```julia
const TIME = Cell(0.0)          # current logical time, seconds (single source of truth)

peek(c::Cell) = (c.valid || recompute!(c); c.value)   # generic untracked read

now_time()  = TIME[]            # SUBSCRIBE: tracked read (use in animated thunks)
time_now()  = peek(TIME)        # SAMPLE:    untracked read (use to arm / to bookkeep)
tick!(t)    = (TIME[] = t)      # loop writes the new time
```

`Float64` seconds is the natural unit for easing math; a frame counter is the
alternative but couples animations to frame rate and makes easing awkward.
`peek` is added to the engine's exports as a first-class, generic primitive.

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
the single source of truth (so both `TIME[]` and `time_now()` see the new value
immediately); the `Clock` is just policy over *what value gets written*.

### 3. Main-loop integration

In `run!`, write time every frame before printing, and sweep finished animations
after (see §5):

```julia
while true
    perf_reset!()
    advance!(editor.clock)                  # ← TIME[] = logical now
    @perf_time :read_time     read!(editor)
    @perf_time :evaluate_time evaluate!(editor)
    @perf_time :print_time    print!(editor)        # re-pulls invalidated cells
    retire_finished!(editor.animations, time_now()) # external retirement (§5)
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
> idle frames still recompute nothing *as long as no animated cell subscribes to
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

A projection wires one into a computed cell, **sampling** the start instant so
the arming code does not itself subscribe to time:

```julia
t0 = time_now()                 # SAMPLE the absolute start (no subscription)
t1 = t0 + 0.5
setfn!(getfield(node, :position_x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(TIME[]))  # SUBSCRIBE
```

**Absolute vs. relative start times.** Animation start times should be
*absolute* (`t0` captured from `time_now()` at the moment the animation is
armed), not "N seconds from when this cell was built". Cells get rebuilt
whenever the iomap is dropped (e.g. after a whole-document swap,
[Operation.jl](../../package/kernel/src/common/Operation.jl) sets
`editor.iomap = nothing`). Absolute start times mean a rebuild doesn't restart
mid-flight animations.

### 5. Retiring finished animations — from above the engine

A finished animation that keeps recomputing to a constant is wasteful (the
engine has no value-equality short-circuit — it re-runs the thunk every frame
even when the result is unchanged). We want such a cell to stop subscribing to
`TIME` once it is done. **The retirement must not touch the engine and must not
happen inside a thunk** — it is an animation-layer concern, expressed only
through the engine's existing public API.

An `AnimationManager` (held on the `Editor`, next to the `Clock`) keeps a
registry of live, *finite* animations and sweeps it once per frame, between
ticks — never inside a computation:

```julia
struct LiveAnimation
    cell::Cell
    done::Function        # (now)::Float64 -> Bool, e.g. now -> now >= t1
end

function retire_finished!(mgr, now)            # called in the loop, after print!
    filter!(mgr.live) do a
        if a.done(now)                          # SAMPLE-based predicate
            setval!(a.cell, a.cell[])           # pull final value, pin it as primitive
            false                               # drop from registry
        else
            true
        end
    end
end
```

`setval!(cell, cell[])` is the whole trick: at `now >= t1`, `cell[]` already
returns the final value, and `setval!` converts the cell to a primitive holding
it — which severs its `TIME` dependency via the engine's existing
`_detach_upstream!`. It runs **between frames**, outside `_computing`, so there
is no mid-recompute hazard and no purity violation. It is the same kind of
external write the loop already performs on `TIME`.

Properties of this approach:

- **Engine untouched** — no sentinel, no return-type check, no knowledge of
  animation in Layer 0. Reactivity never hears the word "animation".
- **Thunks stay pure** — they only read `TIME` and compute; nothing mutates
  itself.
- **Removable** — retirement is a pure optimization layered on top. Delete the
  manager and everything still works, just with the per-frame churn (kept cheap
  by dirty-rect rendering; see Performance).
- **Perpetual animations are never registered** — a rotating dot or a blinking
  cursor has no end, so it simply stays subscribed to `TIME` and is *not* added
  to the manager. Only finite animations retire.

Two things the manager must get right:

1. **Stale registrations on rebuild.** When an operation drops `editor.iomap`
   ([Operation.jl:193](../../package/kernel/src/common/Operation.jl)) the
   animated cells are orphaned and rebuilt. Clear the registry on iomap rebuild
   (or hold cells by `WeakRef`) so it does not pin garbage or freeze a cell that
   no longer renders.
2. **Order: retire after print.** Render the `t >= t1` frame with the computed
   value first, then freeze. Since the frozen value equals the computed one this
   is cosmetic, but it keeps the rule simple.

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
t0 = time_now()                 # SAMPLE the absolute start
t1 = t0 + 0.5                   # half-second slide
setfn!(getfield(rect, :x),
       () -> animate(10.0, 100.0, t0, t1; easing = ease_out)(TIME[]))  # SUBSCRIBE
register!(editor.animations, LiveAnimation(getfield(rect, :x), now -> now >= t1))
```

- Before `t0`: pulls return `10`.
- Between `t0` and `t1`: each frame `TIME` is written → the `x` cell is
  invalidated → next pull recomputes the eased value → the rect redraws.
- At `t1`: the value reaches `100`; the next `retire_finished!` sweep pins the
  cell to `100` as a primitive and unregisters it. From then on it costs
  nothing — it no longer subscribes to `TIME`.

This is the *finite* path. The next example is the *perpetual* path.

---

## Worked example B — rotating vector with sine & cosine charts

The canonical unit-circle demonstration, and a good stress of composition: a
point rotates forever on a circle, while two line charts trace its coordinates —
the **sine** of the angle (the y-coordinate) aligned to the vertical axis, and
the **cosine** (the x-coordinate) aligned to the horizontal axis. Because it
never ends, nothing here is registered with the `AnimationManager`; it simply
stays subscribed to `TIME`. This exercises the always-on path.

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
arm time; every animated value **subscribes** to `TIME`.

```julia
const ω  = 2.0          # rad / s
const R  = 120
const N  = 240          # samples in each chart's time window
const dθ = 0.02         # angle between adjacent samples
const GAP = 24

phase0 = time_now()                 # SAMPLE the start instant (no subscription)
θ(t)   = ω * (t - phase0)

# ── the rotating dot (GraphicsCircle) — perpetual, NOT registered ──────────
setfn!(getfield(dot, :cx), () -> round(Int32, cx0 + R * cos(θ(TIME[]))))   # SUBSCRIBE
setfn!(getfield(dot, :cy), () -> round(Int32, cy0 - R * sin(θ(TIME[]))))   # SUBSCRIBE

# ── sine chart (GraphicsPolyline) — aligned to the Y axis, scrolling right ─
# newest sample (i = 0) sits at the chart's left edge, at the dot's exact cy,
# so a horizontal link line meets the curve where the dot is.
setfn!(getfield(sin_chart, :points), () -> begin
    t = TIME[]                                                              # SUBSCRIBE
    [(cx0 + R + GAP + i, round(Int, cy0 - R * sin(θ(t) - i * dθ))) for i in 0:N]
end)

# ── cosine chart (GraphicsPolyline) — aligned to the X axis, scrolling down ─
# newest sample (i = 0) sits at the chart's top edge, at the dot's exact cx,
# so a vertical link line meets the curve where the dot is.
setfn!(getfield(cos_chart, :points), () -> begin
    t = TIME[]                                                              # SUBSCRIBE
    [(round(Int, cx0 + R * cos(θ(t) - i * dθ)), cy0 + R + GAP + i) for i in 0:N]
end)
```

Two optional connector lines (`GraphicsLine`) make the projection legible — each
reads the dot's animated coordinate (so it animates transitively, no new `TIME`
read needed):

```julia
# horizontal link: dot → left edge of the sin chart, at the dot's y
setfn!(getfield(sin_link, :x1), () -> dot.cx);  setfn!(getfield(sin_link, :y1), () -> dot.cy)
setfn!(getfield(sin_link, :x2), () -> Int32(cx0 + R + GAP)); setfn!(getfield(sin_link, :y2), () -> dot.cy)
# vertical link: dot → top edge of the cos chart, at the dot's x  (symmetric)
```

### Why this is a good test

- **Analytic, fully pure.** The charts recompute their whole polyline from
  `TIME` each frame — no stored history, no per-frame side effect. The curve
  *scrolls* because the window `[θ(t) − N·dθ, θ(t)]` slides forward; this is the
  clean, side-effect-free way to draw a moving signal. (For a non-analytic
  signal you'd keep a ring buffer instead — stateful, and explicitly the
  not-pure case; call it out where used.)
- **Composition.** The link lines depend on the dot's cells, which depend on
  `TIME`; invalidation flows through two hops with no special handling.
- **Alignment falls out of the math.** The newest chart sample equals the dot's
  projected coordinate by construction, so "aligned to the corresponding axis"
  needs no extra layout logic.
- **Perpetual ⇒ exercises the always-on path.** Nothing settles, so the
  retirement machinery is correctly *not* involved; this is the counterpart to
  example A. Ship both as examples (`run_example("rotating_vector")` and a
  settling demo) so reviewers see retirement and non-retirement side by side.
- **Deterministic capture.** Frames at `seek!(clock, kΔt)` produce a filmstrip
  of the rotation for image/video tests (see Determinism and the video plans).

---

## Implementation Steps

### 1. Time cell, readers, clock
- Add `TIME`, `peek`, `now_time()` (subscribe), `time_now()` (sample),
  `tick!`/`seek!` to `Reactive.jl`; export them. `peek` is a generic untracked
  read, not animation-specific.
- Add a `Clock` struct with `advance!/seek!/pause!/resume!/set_rate!`.
- Hold a `Clock` and an `AnimationManager` on the `Editor`.

### 2. Loop integration
- Call `advance!(editor.clock)` at the top of each `run!` frame and
  `retire_finished!(editor.animations, time_now())` after `print!` (all three
  loop variants: plain, bootstrap, and the timeline-driven `run!`).
- Confirm `write_to_devices` re-pulls animated cells with the iomap cached
  (verify with a one-cell smoke test).

### 3. Animation helpers
- Pure `animate`, easing library, `keyframes`, `repeat`, `pingpong`, `delay`,
  `sequence` in a new `Animation.jl` (graphics layer).
- All pure and generic over interpolatable values (numbers, colors, points).

### 4. External retirement
- `AnimationManager` + `LiveAnimation` + `register!` + `retire_finished!`,
  using only `setval!`/`peek` from the engine.
- Clear the registry when the iomap is rebuilt (or use `WeakRef`).

### 5. Examples
- **Settling demo** (example A): a value that eases and retires; assert via
  `perf_counters()` that it stops recomputing after `t1`.
- **Rotating vector** (example B): the circle + sin/cos charts above, as a
  graphics-domain example wired entirely from `TIME`. Run via
  `run_example(...)`; capture a filmstrip via `write_image` at successive
  `seek!` values.

### 6. Determinism for tests / headless
- `test_printers` and friends must pin time: `seek!(clock, FIXED_T)` (or
  `TIME[] = 0.0`) before projecting, so printer output is reproducible.
- `write_example_image` / screenshot helpers take an optional `at::Float64`
  that does `seek!` before rendering.
- Add a test that bumps `TIME` across two values and asserts an animated
  coordinate changed (and that a non-animated sibling did **not** recompute —
  the incrementality guarantee), plus a test that a finite animation retires
  (subscribes before `t1`, primitive after).

### 7. Idle/active gating (performance)
- Detect whether anything is animating by inspecting `TIME`'s dependent set
  (non-empty ⇒ animations live). When empty, the loop can `sleep` longer / skip
  the redraw entirely.

---

## Performance

- **Idle is still free.** Writing `TIME` with no subscribers walks an empty set.
  The only always-on cost is the write itself plus the existing 10 ms poll loop.
- **`time_now()` is cheaper than `TIME[]`.** Sampling skips dependency tracking
  and never recomputes a primitive cell — so arming and the retirement sweep add
  negligible cost and, crucially, register no edges.
- **Active cost is proportional to the animated subtree**, by construction of
  the pull-based engine — siblings that don't subscribe to `TIME` never
  recompute. Use `perf_counters()` to confirm `:computes` per frame tracks only
  the animated nodes.
- **Retirement removes finished finite animations** from the subscriber set, so
  a screen that accumulates many one-shot effects (fades, slides) does not slowly
  accrue per-frame churn. Perpetual animations stay subscribed by design.
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
- **Naming for the subscribe/sample split.** `TIME[]`/`now_time()` vs
  `time_now()` may be too quiet given the symmetric footgun (sampling where you
  meant to subscribe freezes silently). Consider louder names
  (`animated_time()`/`sample_time()`).
- **Retirement registry lifetime.** Clearing on iomap rebuild vs `WeakRef`
  cells. `WeakRef` is robust but adds indirection; clear-on-rebuild is simple but
  must hook every iomap-drop site. Decide once the rebuild paths are enumerated.
- **Determinism vs. realtime.** Tests/headless use `seek!`; the live editor uses
  `advance!`. Audit projection code for any direct `Base.time()`/`time_ns()` —
  everything must go through `TIME`/`peek`.
- **Where helpers live.** `Animation.jl` in the graphics layer vs a standalone
  package. The cell + `peek` belong in the kernel; the easing/keyframe/manager
  vocabulary belongs with graphics.
- **Generality of interpolation.** `animate` over numbers is obvious; over colors
  (fades), points (motion paths), and styled-string attributes needs an
  interpolation typeclass (`lerp(a, b, fraction)` per type).
- **Non-analytic signals.** Example B is analytic (recomputed from `TIME`).
  Charts of measured/streamed signals need a stored history (ring buffer), which
  is stateful — decide how that state is owned without violating thunk purity
  (likely a primitive cell holding the buffer, written by an external sampler in
  the loop, exactly like `TIME` itself).
- **Spec as a document.** Modelling keyframes/curves as an editable document (a
  timeline editor projection) is attractive but a separate, larger effort; v1
  can hardcode animation specs in projection code.
- **Frame pacing.** The fixed 10 ms `sleep` gives a ~100 fps ceiling regardless
  of load. Animation may want a target frame interval and to skip frames under
  load; out of scope for v1 but worth noting.

---

## Rejected Alternatives

- **An engine-level "freeze" sentinel** (a `Frozen` value the thunk returns and
  `recompute!` special-cases to retire the cell). Rejected: it drags a
  higher-layer lifetime/animation concept *down* into Layer 0, which must stay
  generic and dependency-free. The leak is contagious — every future reader of
  the engine would have to understand a concept that belongs three layers up.
- **Self-elimination inside the thunk** (the thunk calls `setval!` on its own
  cell when done). It happens to work — under the monotone-invalidation
  invariant the self-write's dependent walk is a no-op, because every dependent
  is already invalid while the cell is being recomputed from a `TIME` write. But
  it violates the thunk-purity contract (a side effect inside a thunk that may
  run 0/1/many times), relies on a non-obvious proof, has a read-ordering trap
  (must not read any cell after eliminating), and is fragile against any future
  engine change (value-equality short-circuit, speculative/parallel recompute).
  The external `AnimationManager` (§5) achieves the same retirement with a pure
  thunk and an untouched engine.
- **Two independent time globals** (`NOW::Ref` + `TIME::Cell`). Works and needs
  no `peek`, but duplicates the source of truth and invites silent intra-frame
  divergence. One cell read two ways (`TIME[]` / `peek`) is the same ergonomics
  without the duplication.

---

## Relationship to Existing Plans

| Plan | Overlap |
|---|---|
| [optimize-rendering-dirty-rect.md](../pending/optimize-rendering-dirty-rect.md) | Animation is the strongest motivation for partial redraw — only the moving region changes each frame. Should land together or at least be co-designed. |
| [headless-video-recording.md](../done/headless-video-recording.md) / [extract-video-package.md](../done/extract-video-package.md) | Rendering successive `seek!(t)` frames to images *is* video. The rotating-vector example is a natural recorded-animation test case. |
| [generate-screenshots.md](../done/generate-screenshots.md) / [write-image.md](../done/write-image.md) | Deterministic screenshots require pinning time; these helpers should grow an `at::Float64` parameter. |
| timeline-driven `run!` (in [Editor.jl](../../package/kernel/src/editor/Editor.jl)) | That loop injects *operations* on a schedule (event-level scripting). Animation is the *value-level* analog — interpolated state rather than discrete operations. Conceptually complementary; both are "the editor changing without live user input". |
| [tooltip.md](../pending/tooltip.md) / [annotation.md](../tentative/annotation.md) | Fade-in/out and slide presentations for popups and annotations become trivial once a time cell exists (and they retire via §5). |

---

## Dependencies

- The reactive cell engine ([Reactive.jl](../../package/kernel/src/common/Reactive.jl))
  — `TIME` and the generic `peek` (untracked read) are added there; write-driven
  invalidation is the load-bearing mechanism and already exists.
- The main loop ([Editor.jl](../../package/kernel/src/editor/Editor.jl)) — one
  `advance!` and one `retire_finished!` call per frame; the per-frame
  `write_to_devices` re-pull already happens.
- The graphics domain primitives used by example B already exist:
  `GraphicsCircle`, `GraphicsPolyline`, `GraphicsLine`, `GraphicsCanvas`
  ([Graphics.jl](../../package/domain/src/document/Graphics.jl)) — all
  cell-backed, so their fields can be driven by computed cells that read `TIME`.
- No backend changes for in-canvas animation (the SDL/web/console backends
  already re-render the cell-backed canvas each frame).
- A doc correction to
  [reactive-cells.md](../../documentation/reactive-cells.md): the purity rule
  should clarify that the clock enters the graph through the `TIME` cell
  (subscribe via `TIME[]`, sample via `peek`), never via an ad-hoc wall-clock
  read inside a thunk.
