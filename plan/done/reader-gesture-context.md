# Plan: Make the reader symmetric with the printer (a `Change` flows backward)

**Status: done.** Shipped as four commits on `plan/xml-to-syntax-reader`:

| Commit | Phase |
|---|---|
| `4fede92` | Rename `ProjectionContext` → `PrinterContext` |
| `0ada91a` | Reorder printer args to `(projection, recursion, input, context)` |
| `a06e107` | Thread a `Change` (gesture + operation) through the reader pipeline |
| `31f083d` | Consume the gesture in `SyntaxToText`; remove `from_click` |

---

## Motivation

A projection reader used to see **either** the raw input event **or** a
backward-mapped operation — never both. The `SequentialProjection` reader tried
each step *last → first* with the raw event until one returned an `Operation`,
then walked *back* through the earlier steps handing each the **operation** only.
So by the time a click-derived `ReplaceSelectionOperation` reached `SyntaxToText`
on the backward walk, the original `MousePress` (and its modifiers) was gone. The
only way click-ness reached the syntax layer was an ad-hoc `from_click::Bool`
flag smuggled on the operation.

The fix is not a side-channel argument but **making the reader's unit symmetric
with the printer's**. The printer transforms a *document*; the reader transforms
a *change*. A change is a first-class object carrying **both** the originating
**gesture** (invariant — the raw input, constant through the chain) **and** the
**operation** (the part produced and re-mapped at each layer). This mirrors Lisp's
`command` ([`command.lisp:12-18`](../../../projectured-lisp/source/editor/command.lisp#L12-L18)),
whose read starts from `make-nothing-command(gesture)` and whose acting readers
return a fresh command via `clone-command` that keeps the gesture and swaps in a
real operation.

## The symmetric interface

Both halves of a projection now read `(projection, recursion, payload, context)`:

```julia
projection_print(projection, recursion, document, context::PrinterContext) -> IoMap
projection_read (projection, recursion, change,   context::IoMap)          -> Change
```

| arg / role | Forward (`projection_print`) | Backward (`projection_read`) |
|---|---|---|
| payload (3rd) | the **document** (transformed value) | the **`Change`** (transformed delta) |
| context (4th) | **`PrinterContext`** — where input sits + layout | the **`IoMap`** — the correspondence built by the printer |
| returns | an **`IoMap`** | a **`Change`** |

The `IoMap` is the **pivot**, not a unit: built on the forward pass, consumed on
the backward pass (the bidirectional-lens fact that `get`/print establishes the
correspondence and `put`/read reuses it). It fills the reader's context slot, dual
to the printer's `PrinterContext`.

### `Change` — the backward payload

Defined in `ProjectionApiModule` ([`api/Projection.jl`](../../program/src/api/Projection.jl)):

```julia
struct Change
    gesture::Any     # invariant cause; constant through the chain (the event for now)
    operation::Any   # current-domain delta; `nothing` until a reader fills it in
end
Change(gesture) = Change(gesture, nothing)
```

- The read **starts from `Change(gesture, nothing)`** (Lisp's `make-nothing-command`).
- An acting reader returns a fresh `Change` that **keeps the gesture** and swaps in
  a real operation (Lisp's `clone-command`); a reader with nothing to say returns
  the change with `operation === nothing` (a nothing-change), which passes through.
- `Editor.read!` seeds `Change(envelope, nothing)` and reads back `change.operation`.

The `gesture` field holds the existing backend event structs (`MousePress`,
`KeyDown`, …; clicks are already synthesised in the SDL backend). A dedicated
`Gesture` type unifying them can come later — it was not required here.

## Migration mechanism — multiple dispatch under the symmetric façade

The symmetric signature dispatches on `change::Change` (one type), which would
otherwise kill the per-operation-type method dispatch the codebase is built on.
A **generic bridge** in `ProjectionModule`
([`common/Projection.jl`](../../program/src/common/Projection.jl)) recovers it:

```julia
function projection_read(p::Projection, recursion, change::Change, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = projection_read(p, iomap, payload)        # legacy 3-arg dispatch
    return Change(change.gesture, op)
end
```

So **leaf and node readers keep their existing 3-arg `projection_read(p, iomap, x)`
methods untouched** — the bridge unwraps the `Change`, dispatches the legacy
reader on the operation (or the gesture when none has been produced yet, e.g. at
the graphics layer's gesture→operation step), and re-wraps the result with the
gesture preserved. The `operation === nothing ? gesture : operation` fallback is
also what lets the 3-arg compatibility shims (below) pass a bare operation through
unchanged.

Only the **compound projections** that thread the change to their children were
converted to a 4-arg `Change` method, each keeping a thin 3-arg shim
(`projection_read(p, iomap, payload) = projection_read(p, nothing, as_change(payload), iomap).operation`)
so existing test / hit-test callers are unchanged:

- `SequentialProjection` — the two-phase event/op walk collapsed into **one
  uniform walk** threading a single `Change` (the gesture is constant for free as a
  field of the threaded change).
- `RecursiveProjection` — passes **itself as `recursion`** (symmetric with its
  printer), giving node readers the same recursion handle.
- `TypeDispatchingProjection`, `AlternativeProjection`, `NestingProjection`,
  `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`,
  `TooltipDecoratorProjection`, `WindowManagerProjection`.
- `CopyingProjection` — routes the `EventEnvelope` by `window_id` and threads a
  fresh `Change(env.event, nothing)` into the matching window's content reader.

Leaf-like generics that never forward to a child (`FocusingProjection`,
`InvariablyProjection`, `PreservingProjection`) and all primitive `*ToSyntax /
*ToText / *ToGraphics` readers stayed 3-arg, reached via the bridge. Graphics
hit-test recursion (`*ToGraphicsCanvas`) stays 3-arg among graphics leaves.

## Payoff — `from_click` removed

With the gesture reachable in the syntax reader, the ad-hoc carrier is gone:

- `SyntaxNodeToText` gained a 4-arg `Change` reader
  ([`SyntaxToText.jl`](../../program/src/projection/primitive/SyntaxToText.jl)) that
  reinterprets a `ReplaceSelectionOperation` as a `ToggleCollapseOperation` only
  when **`change.gesture isa MousePress`** and the click landed on a collapse glyph
  — exactly Lisp's `(typep -gesture- 'gesture/mouse/click)`. Keyboard navigation
  that lands on the marker still places the cursor.
- `ReplaceSelectionOperation` lost its `from_click::Bool` field
  ([`common/Operation.jl`](../../program/src/common/Operation.jl)); the four click
  readers in `TextToGraphics` dropped the trailing `true`.
- `ToggleCollapseOperation` is now exported from `Projectured` (parallel to
  `ReplaceSelectionOperation`).

## Validation

Behaviour-preserving across the suite:

- Readers 6975/6975, Repls 6975/6975, Selections 5167/5167, Printers 89108/89108.
- SyntaxToText collapse/marker suites, TreeNavigation 16/16, MouseClicks 10/10,
  Typeins, Tooltip+WindowManager 23/23.
- Phase 4 directly confirmed by **CollapseRoundtrip 18/18** and **ClickRoundtrips
  10/10** (marker-click → `ToggleCollapseOperation` via the gesture). Both suites
  had been *erroring* at the pre-change baseline on a missing `ToggleCollapseOperation`
  export, which the phase-4 export fix also resolved.
- `AssistantMvp` fails identically on the untouched `ad33fa3` baseline (async
  FakeLlm / display timing in this environment) — pre-existing, unrelated.

## Notes / deviations from the original options

The original draft framed this as **Option A** (a literal `Command` wrapper,
collapsing all readers to internal `if` ladders) vs **Option B** (thread the
gesture as an extra positional argument, keeping dispatch). What shipped is the
**synthesis**: the first-class `Change` carrier of A, but with B's multiple
dispatch preserved via the unwrap bridge — so existing operation-typed readers are
untouched and the gesture is structurally available everywhere (a field of the one
threaded carrier), not a second-class argument each combinator must remember to
forward. Per-`Change` metadata (`domain`/`description`/`icon` for a future command
palette / context help) can be added as fields later without changing the interface.

## Follow-ups unblocked

- The mouse half of tree navigation can move further into `SyntaxToText`
  (see [`finish-syntax-tree-navigation.md`](finish-syntax-tree-navigation.md)).
- Phase 3 of [`event-case-migration.md`](../pending/event-case-migration.md) touches
  the same readers; migrate them to `@event_case` next.
