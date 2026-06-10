# Make the reader symmetric with the printer: a `Change` flows backward

Right now a projection reader sees **either** the raw input event **or** a
backward-mapped operation — never both. The reader chain in
[`Sequential.jl`](../../program/src/projection/higherorder/Sequential.jl)
tries each step *last → first* with the raw event until one returns an
`Operation`, then walks *back* through the earlier steps handing each the
**operation** only ([`Sequential.jl:78-92`](../../program/src/projection/higherorder/Sequential.jl#L78-L92)).
So by the time a click-derived `ReplaceSelectionOperation` reaches
`SyntaxToText` on the backward walk, the original `MousePress` (and its
modifiers) is gone.

The fix is not a side-channel argument — it is to make the **reader's unit
symmetric with the printer's**. The printer transforms a *document*; the reader
transforms a *change*. A change is a first-class object carrying **both** the
originating **gesture** (invariant — the raw input, constant through the chain)
**and** the **operation** (the part that gets produced and transformed). Any
reader, anywhere in the pipeline, can then inspect *what the user did* while
transforming *what it means*. This is the prerequisite for finishing the mouse
side of tree navigation — see
[`finish-syntax-tree-navigation.md`](finish-syntax-tree-navigation.md).

## The decided interface

Both halves of a projection take the same shape — `(projection, recursion,
payload, context)` — differing only in what flows and what the context is:

```julia
projection_print(projection, recursion, document, context::PrinterContext) -> IoMap
projection_read (projection, recursion, change,   context::IoMap)          -> Change
```

| arg / role | Forward (`projection_print`) | Backward (`projection_read`) |
|---|---|---|
| payload (3rd) | the **document** (transformed value) | the **change** (transformed delta) |
| context (4th) | **`PrinterContext`** — where input sits + layout | the **`IoMap`** — the correspondence built by the printer |
| returns | an **`IoMap`** (output document + child iomaps) | a **`Change`** (operation filled in / re-mapped, gesture kept) |
| flows step→step | `iomap.output` (the next document) | the `Change` (the next-domain delta) |

The `IoMap` is the **pivot**, not a unit: built on the forward pass, consumed on
the backward pass. The document↔change pair are the duals; the iomap stands
outside that pair as the shared scaffold both lean on (the bidirectional-lens
fact that `get`/print establishes the correspondence and `put`/read reuses it).

### `Change` — the backward payload

```julia
struct Change
    gesture     # invariant cause; constant through the chain (may be the raw event for now)
    operation   # current-domain delta; `nothing` until a reader fills it in
end
```

- The read **starts from `Change(gesture, nothing)`** — the gesture wrapped in a
  do-nothing operation (Lisp's `make-nothing-command`,
  [`command.lisp:30`](../../../projectured-lisp/source/editor/command.lisp#L30)).
- A reader that acts returns a **fresh** `Change` that **keeps the gesture** and
  swaps in a real operation (Lisp's `clone-command`,
  [`command.lisp:33-35`](../../../projectured-lisp/source/editor/command.lisp#L33-L35)).
- A reader with nothing to say returns the change **unchanged** (still
  `operation === nothing`) — the nothing-change passes through.
- `read!` reads back `change.operation` at the boundary.

The `gesture` field initially just holds the existing event structs the backend
already produces (`MousePress`, `KeyDown`, …; clicks are already synthesised in
[`Sdl.jl`](../../program/src/backend/Sdl.jl) → `MousePress`). A dedicated
`Gesture` type unifying them (mirroring Lisp's `gesture/*` classes,
[`gesture.lisp:12-48`](../../../projectured-lisp/source/editor/gesture.lisp#L12-L48))
can come later — it is not required here.

### Context rename: `ProjectionContext` → `PrinterContext`

The forward context type is renamed for symmetry — it is the **printer's**
context (the reader's context is the `IoMap`). Rename the struct and its module
in [`ProjectionContext.jl`](../../program/src/context/ProjectionContext.jl)
(`ProjectionContext` → `PrinterContext`, `ProjectionContextModule` →
`PrinterContextModule`) and update every import/usage. Behaviour is unchanged;
this is a mechanical rename. The reader context keeps the name `IoMap` (it is the
printer's output record; "ReaderContext" would lose that meaning) — the symmetry
is in the **slot and role**, not the type name.

## Why this is the symmetric design — what the Lisp original does

In ProjecturEd-Lisp the unit that flows through the reader chain is a
**command**, not a bare operation
([`command.lisp:12-18`](../../../projectured-lisp/source/editor/command.lisp#L12-L18)),
and the printer/reader signatures are deliberately parallel:

```lisp
(printer -projection- -recursion- -input- -input-reference-)  ; -> iomap
(reader  -projection- -recursion- -input- -printer-iomap-)    ; -> command
```
([`printer.lisp:17`](../../../projectured-lisp/source/editor/printer.lisp#L17),
[`reader.lisp:17`](../../../projectured-lisp/source/editor/reader.lisp#L17))

Every reader exposes `-gesture- = (gesture-of -input-)`
([`reader.lisp:19-21`](../../../projectured-lisp/source/editor/reader.lisp#L19-L21)),
so the gesture is a **constant context available at every layer** while the
operation is the part produced and mapped. `merge-commands` picks the first
command carrying a real operation
([`command.lisp:46-59`](../../../projectured-lisp/source/editor/command.lisp#L46-L59)).
Concretely it lets the syntax reader do
([`syntax-to-text.lisp:1236-1246`](../../../projectured-lisp/source/projection/primitive/syntax-to-text.lisp#L1236-L1246)):

```lisp
(if (and (typep -gesture- 'gesture/mouse/click)         ; raw gesture
         (typep operation 'operation/replace-selection) ; backward-mapped op
         (equal (selection-of operation) selection))     ; current selection
    (promote-to-whole-node)
    operation)
```

The Julia port adds the one thing the pipeline lacks (the gesture) by adopting
the whole symmetric shape rather than smuggling it.

## What changes, concretely

1. **`Change` type + `PrinterContext` rename** as above.

2. **Editor boundary** ([`Editor.jl:72-91`](../../program/src/editor/Editor.jl#L72-L91)).
   Seed `Change(gesture, nothing)` and read back `.operation`:
   ```julia
   change = projection_read(editor.projection, editor.projection,
                            Change(gesture, nothing), editor.iomap)
   change.operation isa Operation && (editor.operation = change.operation; return true)
   ```
   The `EventEnvelope` (window_id + event) is a transport wrapper handled at the
   screen layer: `CopyingProjection` keeps routing by `window_id`, and the point
   where it currently unwraps `env.event`
   ([`Copying.jl:292`](../../program/src/projection/generic/Copying.jl#L292))
   becomes where it seeds `Change(env.event, nothing)` for the inner content
   reader. From a window's content inward the gesture is invariant.

3. **`Sequential`** ([`Sequential.jl:78-92`](../../program/src/projection/higherorder/Sequential.jl#L78-L92))
   threads **one `Change`** through both phases, which *removes* today's
   event-vs-operation asymmetry:
   ```julia
   function projection_read(seq::SequentialProjection, recursion, change::Change, iomap::SequentialProjectionIoMap)
       n = length(seq.projections); i = n
       out = projection_read(seq.projections[n], recursion, change, iomap.step_iomaps[n])
       while out.operation === nothing && i > 1            # search last→first for the converter
           i -= 1
           out = projection_read(seq.projections[i], recursion, change, iomap.step_iomaps[i])
       end
       out.operation === nothing && return change          # nothing-change passes through
       for j in (i-1):-1:1                                  # translate inward
           out = projection_read(seq.projections[j], recursion, out, iomap.step_iomaps[j])
           out.operation === nothing && return change
       end
       return out
   end
   ```
   The gesture is constant for free — it is a field of the threaded `Change`, not
   a separate argument every combinator must remember to forward.

4. **`recursion` becomes load-bearing for the reader too.** `Recursive` passes
   itself as `recursion` (mirroring its printer,
   [`Recursive.jl:38-47`](../../program/src/projection/higherorder/Recursive.jl#L38-L47)):
   ```julia
   projection_read(rp::RecursiveProjection, recursion, change::Change, iomap) =
       projection_read(rp.child, rp, change, iomap)
   ```
   A node reader that descends into a child then recurses via
   `projection_read(recursion, recursion, child_change, child_iomap)` — re-entering
   the whole pipeline (`Recursive`→`TypeDispatching`) exactly as the printer does,
   instead of reaching into the child iomap's stored projection
   ([`Copying.jl:282`](../../program/src/projection/generic/Copying.jl#L282)).
   `TypeDispatching`
   ([`TypeDispatching.jl:56-63`](../../program/src/projection/higherorder/TypeDispatching.jl#L56-L63))
   forwards `recursion` + `change` and returns the nothing-change when no branch
   matches.

5. **Printer argument reorder** so both halves read `(projection, recursion,
   payload, context)`. Every `projection_print(p, input, recursion, ctx)` becomes
   `projection_print(p, recursion, input, ctx)`. Pure mechanical churn, no
   behaviour change — best done as one isolated sweep (its own phase below).
   Provide a 3-arg `projection_read(p, change, iomap)` convenience supplying
   `recursion = nothing`, mirroring the existing 2-arg `projection_print(p, input)`.

## Migration: keeping multiple dispatch under the symmetric façade

The public interface dispatches on `change::Change` (one type), so the per-
operation-type method dispatch the codebase uses today does not come for free.
Recover it with a **default that fans out on the change's parts**, so existing
readers migrate mechanically:

```julia
# Symmetric default for any Projection: re-dispatch on operation (+ gesture),
# re-wrap keeping the gesture. Lives in ProjectionModule, replacing Projection.jl:69-81.
function projection_read(p::Projection, recursion, change::Change, iomap)
    op = projection_read(p, recursion, change.gesture, change.operation, iomap)
    return Change(change.gesture, op)
end

# 5-arg fan-out: default ignores the gesture and keeps today's op-typed methods.
projection_read(p, recursion, gesture, operation, iomap) =
    projection_read(p, recursion, operation, iomap)
```

- A projection that only re-maps selections needs **no reader** — the default's
  `ReplaceSelectionOperation` / `ToggleCollapseOperation` handling
  ([`Projection.jl:69-81`](../../program/src/common/Projection.jl#L69-L81)) moves
  into this method unchanged.
- An existing op-typed reader keeps its body and only gains the `recursion` arg:
  `projection_read(p::Foo, recursion, op::SomeOp, iomap)`.
- A **gesture-aware** reader overrides the 5-arg form for its op type — this is
  Lisp's `gesture-case`, expressed through Julia dispatch:
  ```julia
  projection_read(p::SyntaxNodeToText, recursion, g::MousePress, op::ReplaceSelectionOperation, iomap) = …
  ```
- The graphics-layer readers that today dispatch on a raw event (e.g.
  `TextToGraphics`'s `MousePress` handler) become the
  `operation === nothing` + gesture-typed converters — the explicit
  gesture→operation step at the chain's outer end.

This honours the symmetric public contract while leaving the multiple-dispatch
structure the codebase is built on intact.

## Phasing

Each phase compiles and tests green on its own:

1. **Rename** `ProjectionContext` → `PrinterContext` (mechanical, isolated).
2. **Reorder** printer args to `(projection, recursion, input, ctx)` (mechanical,
   no behaviour change).
3. **Introduce `Change`** + the symmetric reader signature + the fan-out default;
   thread it through `Sequential` / `Recursive` / `TypeDispatching` / `Copying`
   and the `read!` boundary. Existing readers gain `recursion`; behaviour
   unchanged because no reader consults the gesture yet.
4. **Consume the gesture** in `SyntaxToText` and finish mouse tree-nav (the
   sibling plan), removing the ad-hoc carriers below.

## Payoff once phase 3 lands

- The `from_click::Bool` flag on `ReplaceSelectionOperation`
  ([`Operation.jl:35-61`](../../program/src/common/Operation.jl#L35-L61)) — today
  the only way click-ness reaches the syntax layer — collapses to a direct
  `change.gesture isa MousePress` check, exactly Lisp's
  `(typep -gesture- 'gesture/mouse/click)`. Its sole consumer is the marker-toggle
  disambiguation in `SyntaxToText`'s `ReplaceSelectionOperation` reader.
- The mouse half of tree navigation moves entirely into `SyntaxToText`
  (see the sibling plan).
- Per-`Change` metadata (`domain`/`description`/`icon`, the command-palette /
  context-help fields Lisp's `command` carries) can be added as fields later
  **without touching the interface** — cf.
  [`gesture-help.md`](../tentative/gesture-help.md).

## Testing

- `test_cell()` is unaffected; the change is in the reader plumbing.
- Reader/selection/repl coverage exercises this: `test_reader(json_example)`,
  `test_selection(json_example)`, `test_repl(json_example)`, plus
  `test_text_to_graphics()`. Click round-trips:
  [`ClickRoundtripTest.jl`](../../test/src/editor/ClickRoundtripTest.jl),
  [`MouseClickTest.jl`](../../test/src/editor/MouseClickTest.jl).
- Broad sweeps (`test_readers()` / `test_selections()` / `test_repls()`) only as a
  final check — per [`CLAUDE.md`](../../CLAUDE.md).
- Phase 4 test: a click-derived `ReplaceSelectionOperation` reaches the
  `SyntaxNodeToText` reader carrying the `MousePress` in `change.gesture`.

## Open questions

1. **Type name `Change` vs `Command`.** `Change` matches the document↔change
   framing; `Command` matches Lisp and reads better once the palette metadata is
   added. Recommendation: `Change` now, revisit if/when metadata fields land.
2. **Reader `recursion` vs deriving it from the iomap.** Included for symmetry and
   to give node readers the same recursion handle the printer has (§4); the child
   iomap's stored projection could serve instead. Recommendation: include it.
3. **Remove `from_click`** in this change or in the tree-navigation finish plan.
   Listed in *Payoff* but mechanically belongs with phase 4.

## Relationship to other plans

- **Blocks** [`finish-syntax-tree-navigation.md`](finish-syntax-tree-navigation.md)
  (mouse promotion needs the gesture in the syntax reader).
- **Touches the same readers** as the deferred Phase 3 of
  [`event-case-migration.md`](event-case-migration.md); sequence this first, then
  migrate those readers to `@event_case`.
