# Chase Animation via Arming and Chasing Projections

> **Status (2026-08-12): NOT STARTED.** `TrajectoryDoc`, `ChasePlayback`,
> `ChaseArming`, and `SettledArming` do not exist anywhere under `package/`.
> The prior art this plan builds on is in place and current: the per-editor
> `Clock` lives at
> [package/kernel/main/clock/Clock.jl](../../source/kernel/clock/Clock.jl)
> (not `cell/Clock.jl` as cited below) with `get_reactive_clock_time`/
> `get_clock_time` (not `get_reactive_time`/`get_time` as cited below), and
> `WidgetSwitch`'s flip-site-armed sliding knob is implemented in
> [package/widget/main/Widget.jl](../../source/widget/Widget.jl) and
> [package/widget/main/WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl)
> (`_switch_fraction`/`_switch_toggle`, `anim_from`/`anim_t0`/`duration`
> fields) — exactly the shape this plan's "Rejected alternatives" section
> describes as the coupling to remove.

> **Note:** This document was designed in conversation with AI assistance. It is
> a worked design, not yet implemented; evaluate and refine it against the code
> as the pieces land.

Animate a derived numeric value so it *chases* its target at **constant speed**
whenever the underlying input changes — the canonical case being a boolean that
projects to `0.0` / `100.0` (a switch knob's horizontal position) — with these
hard requirements:

- **Interruptible mid-flight.** Flipping the boolean while the value is still
  moving reverses the trajectory from wherever the value visually is, with no
  jump, still at constant speed.
- **Independent of how the input changes.** A reader operation, a REPL write, an
  agent, a timer — any write to the input animates identically. No arming code
  at any flip site.
- **No editor-loop changes.** No per-tick stepper, no transition registry, no
  hook in `run_editor!`. The existing tick → pull cycle is enough.
- **Static projections, per-instance state.** One projection instance in the
  pipeline serves every boolean the document contains, however many exist right
  now; all per-switch state rides per-node artifacts.
- **The animation is an independent add-on.** The non-animated pipeline works
  with a placeholder that the animated variant replaces without touching any
  other projection.

## Prior art in-tree

- **The per-editor `Clock`**
  ([package/kernel/main/clock/Clock.jl](../../source/kernel/clock/Clock.jl),
  from [plan/done/per-editor-animation-clock.md](../done/per-editor-animation-clock.md))
  gives the SUBSCRIBE/SAMPLE split this design leans on: `get_reactive_time`
  (tracked, re-run every tick) vs `get_time` (untracked, arm without
  subscribing) — named `get_reactive_clock_time`/`get_clock_time` in the shipped
  code. `PrinterContext.clock` delivers it to every printer.
- **`WidgetSwitch`'s sliding knob**
  ([package/widget/main/WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl),
  `_switch_fraction` / `_switch_toggle`) already implements interruptible,
  no-jump chasing — but arms **at the flip site**: the reader bundles
  `anim_from`/`anim_t0` writes into a `CompoundOperation` ahead of the toggle,
  and the state lives as fields **on the widget document**. That couples the
  animation to the edit path (an out-of-band `w.checked = true` snaps instead
  of sliding) and pollutes the domain type with presentation state. This plan
  is the generalization that removes both couplings.
- **[plan/pending/animation-global-time.md](animation-global-time.md) §7**
  posed the "arming on state change" question and answered it with the
  reader-side compound operation. This plan supersedes that answer for
  value-chasing animations; the rest of that document (the time cell, easing
  vocabulary, perpetual animations) is unaffected.

## The key observations

**1. The output of a projection is a signal, not a value.** Every `@document`
field is a `Cell`; a projection that "produces 0 or 100" actually wires a
step-function signal `Cell(() -> b ? 100.0 : 0.0)`. An animated variant does not
produce different values — it wires a different cell. That step-function cell is
the *placeholder* the animated pipeline replaces.

**2. The reactive graph already observes every change, whoever causes it.**
Writing any cell eagerly invalidates its transitive dependents; a computed cell
that (tracked-)reads the input re-runs on the next pull after *any* write, from
*any* source. So "the target changed" needs no interception at write sites and
no polling loop — an ordinary computed cell is the change observer.

**3. Memory is irreducible; only its address is negotiable.** A constant-speed
chase must remember where it was when the target last changed. Cells are
memoryless functions of their current inputs, so *some* state must be written
somewhere, and there are exactly three possible sites: (a) the flip site
(rejected — *Independent of how the input changes*), (b) a per-tick stepper
(rejected — *No editor-loop changes*),
(c) inside the graph, during a pull, when the change is first observed. This
design takes (c) in its most disciplined form and quarantines it in one tiny
projection (see "The purity asterisk" below).

## Core design: a two-step projection chain

Split the animation into **two chained projections** with an intermediate
document between them, so the animation state lives *in the document tree* —
even if only as an intermediate stage of the pipeline:

```
BoolDoc ──(arming projection)──▶ TrajectoryDoc ──(chasing projection)──▶ NumberDoc
            observes the input       the reified          pure playback
            snapshots trajectories   animation state      against the clock
```

### The intermediate document

```julia
@document struct TrajectoryDoc
    from::Float64      # value when the target last changed
    t0::Float64        # clock time when it changed (-Inf = born settled)
    target::Float64    # current target value
    speed::Float64     # units per second — constant
end
```

A trajectory is a complete, self-contained description of "where the value is
heading and from where": the displayed value at any time `t` is the pure
function

```
value(t) = t ≥ t1 ? target : from + sign(target - from) * speed * (t - t0)
where t1 = t0 + |target - from| / speed          # constant speed, by construction
```

Reifying this as a document (rather than hiding it in a closure) buys:

- **Addressability** — references reach it; both projections' reference mappers
  are ordinary; debugging shows the in-flight state when dumping pipeline stages.
- **Reuse** — the chasing projection is generic over *any* trajectory source;
  easing/duration/spring policies are just other arming projections emitting the
  same document.
- **A future inspector** — an editor projection over TrajectoryDocs (live view
  of all in-flight animations) becomes ordinary, in the spirit of
  animation-global-time.md §6 ("the spec is editable data, the playback is a
  derived value").

### The arming projection (`BoolDoc → TrajectoryDoc`)

Prints **once per node** (its print body reads no input values). It creates the
TrajectoryDoc whose fields are fed by a single internal **snapshot cell**:

```julia
function print_document(p::ChaseArming, recursion, i::BoolDoc, ctx)
    clock = ctx.clock
    memory = Ref{Union{Nothing, NamedTuple}}(nothing)   # previous snapshot — see purity note
    snapshot = Cell(() -> begin
        target = i.b ? 100.0 : 0.0            # SUBSCRIBE to the input — the trigger
        prev = memory[]
        now = get_time(clock)                  # SAMPLE — arming must not subscribe
        from = prev === nothing ? target :     # first print: born settled, no animation
               trajectory_value(prev, now)     # OLD trajectory evaluated at now → no jump
        snap = (from = from, t0 = prev === nothing ? -Inf : now, target = target)
        memory[] = snap
        snap
    end)
    output = TrajectoryDoc(Cell(() -> snapshot[].from),
                           Cell(() -> snapshot[].t0),
                           Cell(() -> snapshot[].target),
                           p.speed)
    SimpleIoMap(p, i, output)
end
```

Properties:

- The snapshot cell reads the input **tracked** and the clock **untracked**, so
  it re-runs **once per input change** — never per frame — regardless of who
  wrote the input.
- Mid-flight interruption falls out: `from` is the old trajectory evaluated at
  `now`, so the value reverses from its current visual position, and since
  `t1` derives from the remaining distance, speed stays constant across any
  number of flips.
- The generic form takes a `target_of(input)::Float64` function instead of
  hard-coding the boolean, making the projection domain-independent; the
  bool→0/100 case is one instantiation.

### The chasing projection (`TrajectoryDoc → NumberDoc`)

**Fully pure, completely stateless** — the whole point of the split. One value
cell, using the SUBSCRIBE/SAMPLE split for registry-free settling:

```julia
function print_document(p::ChasePlayback, recursion, traj::TrajectoryDoc, ctx)
    clock = ctx.clock
    value = Cell(() -> begin
        target = traj.target; from = traj.from; t0 = traj.t0   # SUBSCRIBE to the trajectory
        t1 = t0 + abs(target - from) / traj.speed
        now = get_time(clock)                  # SAMPLE to decide "done"
        now >= t1 && return target             # settled → this run reads no clock
        t = get_reactive_time(clock)           # SUBSCRIBE while in flight
        from + sign(target - from) * traj.speed * (t - t0)
    end)
    SimpleIoMap(p, traj, NumberDoc(value))
end
```

Because dependencies re-track on every recompute, an evaluation that returns
before `get_reactive_time` **drops the clock subscription**: a settled value
costs nothing per frame and wakes only when the trajectory fields change. There
is no retirement machinery — same argument as animation-global-time.md §5, but
stronger, since here the settled cell is not even invalidated by ticks.

No ordering hazard: the playback cell reads the trajectory fields, which pull
the snapshot cell, which recomputes if stale — a flip can never render a frame
against outdated parameters.

### The static placeholder is an arming policy

The non-animated pipeline needs no separate shape: a trivial arming projection
that emits **born-settled** trajectories (`from = target, t0 = -Inf`) composed
with the *same* chasing projection reproduces the step function exactly — the
playback returns `target` immediately and never subscribes to the clock. So:

```
static   = SettledArming  ∘ ChasePlayback     # the placeholder
animated = ChaseArming    ∘ ChasePlayback     # the replacement
```

Animated vs static differs in exactly one pipeline binding, and every other
projection — including whatever widget recurses into the boolean via
`print_child` — is byte-identical in both configurations.

### Opt-in per type and per widget

The recursion contract makes the binding external to all involved projections:

- **Per document type**:
  [`TypeDispatchingProjection`](../../source/projection/higherorder/TypeDispatching.jl)
  maps `BoolDoc → SettledArming` or `→ ChaseArming` for the whole pipeline.
- **Per widget / per location**:
  [`ReferenceDispatchingProjection`](../../source/projection/higherorder/ReferenceDispatching.jl)
  switches the arming projection by document-root-relative reference, so *this*
  switch animates while *that* one snaps — no flag on the widget, no change to
  any other projection.

### Multiplicity and state lifetime

Both projections stay static and shared. Per-switch state rides the per-node
print artifacts: each boolean node's print invocation creates its own
TrajectoryDoc + snapshot cell + iomap, created and dropped with the node like
every other output. A **value** change of the input is not a structural change,
so it re-prints nothing — the snapshot cell recomputes in place and the
in-flight state survives, which is exactly what mid-flight interruption needs.
A **structural** re-print of the node recreates the trajectory born-settled
(the value snaps to its target) — same trade-off animation-global-time.md
already accepts for iomap rebuilds, and rare in practice.

## The purity asterisk

The `memory` box in the arming snapshot cell is a side effect inside a thunk,
which the cell invariants
([package/kernel/doc/cell.md](../../documentation/package/kernel/cell.md), "Invariants
the engine relies on") forbid. This is deliberate and must be **named, bounded,
and documented**, not hidden:

- It is the irreducible memory of observation-site arming (key observation 3);
  the alternatives are flip-site arming or a tick stepper, both rejected by the
  requirements.
- Bounded blast radius: the box is a plain untracked `Ref` — writing it
  invalidates nothing and is invisible to the reactive graph. The thunk runs
  once per input change, not per frame. Running it **twice** for one change
  re-snapshots from the same displayed position (harmless — including the
  same-value-write case: propagation is write-driven with no equality check, so
  `doc.b = doc.b` re-arms onto the identical trajectory). Running it **zero**
  times means an unobserved (off-screen, never pulled) change doesn't animate
  and the value renders settled when next pulled — the correct display
  semantics. The playback side stays 100% pure.
- Deliverable: a documented **"previous-value snapshot" idiom** (or a small
  `fold`-style helper) in the animation slice, plus an asterisk in the cell
  guide's purity invariant pointing at it — mirroring how the clock earned its
  own principled carve-out. Nothing in the sealed cell/document layers changes.

## Semantics (stated, not discovered later)

- Arming happens at the **first pull that observes** the change, so animation
  start quantizes to the frame the change becomes visible — the same latency
  the clock itself has.
- Two flips between observations cancel: the target never observably changed,
  so nothing animates. Correct for a display animation.
- Trajectories use **absolute clock times**, so seeking/recording replays
  deterministically: `seek!(clock, t)` then pull yields a reproducible frame.
- Animation is **output-only**: nothing edits an in-flight 37.2, so the chasing
  projection needs no reader beyond the defaults; both projections' reference
  mappers are ordinary single-level maps through the intermediate document.

## Implementation steps

1. **`TrajectoryDoc` + trajectory math.** The document, `trajectory_value(snap, t)`,
   and the constant-speed `t1`. Placement: the visual package next to the
   widget/graphics consumers (or base if a lower-layer consumer appears first) —
   decide against [documentation/architecture.md](../../documentation/architecture.md)
   at implementation time.
2. **`ChasePlayback`** — the pure chasing projection with settle-by-dropping-
   the-subscription. Test first: `test_printer` over hand-built TrajectoryDocs
   at seeked times (settled, in-flight, exactly-at-t1).
3. **`ChaseArming` + `SettledArming`** — generic over `target_of`; the
   bool→0/100 instantiation; the documented previous-value snapshot idiom.
   Tests: flip → re-arm from in-flight position; constant speed across a
   mid-flight reversal; double-run and unobserved-flip semantics; flip via a
   *plain field write* (not an operation) animates — the flip-source-independence
   regression test.
4. **Example** — an animated boolean (e.g. a switch-knob-position demo) wired
   `static` vs `animated` by swapping the arming binding; a
   `ReferenceDispatchingProjection` variant where one of two switches animates.
   Verify with `test_example` on the new example, headless frames via
   `seek!` + `write_example_image`.
5. **Docs** — the cell-guide purity asterisk; a short section in the projection
   docs ("animating a projected value"); update animation-global-time.md §7 to
   point here.
6. **(Later, optional) migrate `WidgetSwitch`** to the chain, deleting
   `anim_from`/`anim_t0` from the widget document and `_switch_toggle`'s
   compound arming — the knob's x becomes a recursion into `checked` through
   `ChaseArming ∘ ChasePlayback`. Do this only after the mechanism has settled;
   it also removes the switch's wall-clock workaround, since printers get
   `ctx.clock`.

## Rejected alternatives

- **Flip-site arming** (the current `WidgetSwitch` shape): reader emits
  *[arm, …, edit]*. Couples animation to the edit path — any out-of-band write
  snaps — and puts presentation state on the domain document.
- **A per-tick transition stepper** in the editor loop (with a registry
  threaded via `PrinterContext`): sound, and the pattern
  animation-global-time.md prescribes for non-analytic *signals*, but it
  modifies the editor loop and adds a registry with lifetime bookkeeping —
  rejected for this feature.
- **State on the projection struct**: projections are static and shared across
  every node they print; per-value state there is simply wrong.
- **Self-`set_value!` / reading a cell's own stale value during recompute**:
  already rejected in animation-global-time.md's Rejected Alternatives; fragile
  against engine changes and violates purity with *reactive* footprint (unlike
  the untracked snapshot box).
- **One-step animated projection with a hidden chaser closure** (the direct
  predecessor of this design): works identically at runtime, but the state is
  invisible and unaddressable, the playback can't be tested in isolation, and
  static-vs-animated needs a separate code path instead of an arming-policy
  swap. The two-step chain keeps all its properties and fixes those.

## Relationship to existing plans

| Plan | Overlap |
|---|---|
| [animation-global-time.md](animation-global-time.md) | Supersedes its §7 arming answer for value-chasing; reuses its subscribe/sample discipline, settling argument, and easing vocabulary (an eased policy is another arming projection). |
| [per-editor-animation-clock.md](../done/per-editor-animation-clock.md) *(done)* | Supplies `Clock` and `PrinterContext.clock` — the time source both projections use. |
| [object-versioning.md](object-versioning.md) | A variant where each arming emits a *fresh immutable* TrajectoryDoc (state as document succession, no mutable box) is versioning-friendly; deferred as an open question. |
| [headless-video-recording.md](../done/headless-video-recording.md) | Absolute-time trajectories + `seek!` make recorded chase animations deterministic. |

## Open questions

- **Package/slice placement** of `TrajectoryDoc` and the three projections
  (visual vs base), per the terminology/architecture guides.
- **Interpolation beyond `Float64`** — colors, points — needs the
  `lerp(a, b, fraction)` typeclass animation-global-time.md already flags; the
  trajectory then carries the interpolated type.
- **Fresh-immutable-TrajectoryDoc variant**: arming re-prints an immutable
  trajectory per change (memory = the previous output instead of a `Ref`).
  Cleaner state story, but needs a seam for a printer to see its previous
  output; evaluate after the mutable-snapshot version works.
- **Whether the previous-value snapshot idiom deserves a first-class helper**
  (a `snapshot_cell(f)` / `fold` in a non-sealed layer) or stays a documented
  pattern.
