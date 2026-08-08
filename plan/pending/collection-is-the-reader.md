# Collection is the reader

Gather the available commands by **running the reader**, the way
`projectured-lisp` does, instead of walking the projection chain a second time.
The reader already routes a gesture to the document that owns it and reroots the
operation at every level on the way back. A second traversal that does neither is
why a collected binding cannot be run.

## What is wrong today

There are two traversals over the same chain.

- `read_intent` — routes a gesture down, threads the operation back up, and
  reroots it at every level.
- `collect_gesture_bindings` — walks the same chain, appends every
  `GestureBinding` it finds, and returns a flat vector.

The collector discards two things the reader keeps: **which document** each
binding builds its operation against, and **what path** would bring that
operation back to the top. A caller therefore cannot run what the collector
returned. The command palette tried, by calling `binding.operation(input, …)`
with its own input document, and that only works when the binding happens to
belong to that exact document.

Measured on `run_example(; clipboard=true)`, where a `ClipboardSlice` wraps the
JSON document: 44 bindings collected, 33 with a name, **0 runnable**. The JSON
rules belong to a document one level down and the clipboard's own commands belong
to a projection, so neither is reachable. The palette lists everything and can run
nothing.

The same defect, in a milder form, is why every binding from a deeper chain stage
was marked "key only".

## How projectured-lisp does it

One traversal. The reader *is* the collector.

`gesture-case` is the form every Lisp reader is written as. Each case carries
`:domain`, `:description` and `:operation`. When the incoming gesture is the help
key, the macro does not dispatch. It evaluates **every case's `:operation` form**
and returns one command carrying `operation/show-context-sensitive-help`, whose
`commands` slot holds a `command` per case — with the built operation inside
([source/editor/command.lisp:60](/home/projectured/workspace/projectured-lisp/source/editor/command.lisp)).

Two consequences fall out of that shape.

**Applicability is not a separate predicate.** A case whose `:operation` form
evaluates to nil contributes no command. "Can this fire now?" is answered by
building the operation and seeing whether one exists.

**The collection rides the ordinary path home.** `operation/extend`, the function
that reroots an operation by prepending a path, has a case for the help operation
([source/document/t.lisp:141](/home/projectured/workspace/projectured-lisp/source/document/t.lisp)):
it maps over the carried commands and extends each one's operation with the same
path. `merge-commands` unions a stage's own set with its child's as the chain
unwinds.

So the list that arrives at the top holds operations already expressed in the top
document's vocabulary. A caller picks one and evaluates it. There is no name to
send back down and no second lookup.

## The change

### 1. A collected item is an `Intent` that knows what it is called

There is no new item type. The reader already traffics in half of one:

```julia
struct Intent
    gesture::Any
    operation::Any
end
```

The Lisp's `command` is exactly that plus its labels, and
[plan/tentative/gesture-help.md](../tentative/gesture-help.md) said so years ago:
*"This is exactly Julia's `Change`, except `Change` carries only gesture +
operation — it is missing the domain/description/accessible metadata."*

So widen `Intent`:

```julia
struct Intent
    gesture::Any
    operation::Any
    description::String     # default ""
    domain::String          # default ""
end
```

Both new fields default, so every existing construction site keeps working and
ordinary reader traffic carries empty labels. A collection is then a
`Vector{Intent}`, and `operation === nothing` is the greyed row the help window
already shows. Keeping that row rather than dropping it is the one deliberate
difference from the Lisp, which lists only what can fire.

`GestureBinding` stays what it is: the *rule*. An `Intent` is that rule resolved
against the current document and selection.

### 2. A payload that asks for them

A reader payload, not an event — no device reports it and no pattern matches it.
`Intent.gesture` is `Any`, so it needs no place in the input vocabulary. The
existing `ClaimedGesture` in
[Intent.jl](../../package/kernel/main/projection/Intent.jl) is the precedent.

```julia
struct CollectIntents end
```

### 3. An operation that carries them home

```julia
struct CollectedIntentsOperation <: Operation
    intents::Vector{Intent}
end
```

Evaluating it does nothing — it is a carrier, exactly as the Lisp's evaluator for
the help operation returns no values. What matters is that it is rerooted like
any other operation:

```julia
reroot_operation(op::CollectedIntentsOperation, steps::Tuple) =
    CollectedIntentsOperation([Intent(i.gesture, reroot_operation(i.operation, steps),
                                      i.description, i.domain)
                               for i in op.intents])
```

`CompoundOperation` is the model: a container whose members are mapped
elementwise, already handled by both `reroot_operation` and the default reader.
Follow it exactly, and every seam that maps a `CompoundOperation` must map this
one — that is the checkable constraint for the whole change.

### 4. The three firing funnels answer it

Everything that fires a binding already goes through one of three places:
`fire_gesture_bindings`, `read_bound_gesture` and `read_projection_gesture`
([GestureBinding.jl](../../package/kernel/main/binding/GestureBinding.jl),
[GestureBindings.jl](../../package/kernel/main/projection/GestureBindings.jl)).
Each gets one branch: on a `CollectIntents` payload, build an `Intent` per
binding in the table instead of firing the first match.

Because they are funnels, every `@gestures`-declared document and every
projection that delegates to `read_projection_gesture` answers the collect
payload with no change of its own. That is what keeps *what fires* and *what is
listed* the same set.

### 5. Chaining merges instead of taking the first match

This is the one combinator whose reader shape is wrong for collection.
[Chaining.jl:141](../../package/base/main/projection/higherorder/Chaining.jl)
tries the last stage, falls back to earlier stages **until one answers**, then
threads that answer back. Collection wants every stage to contribute.

Add a collect branch: walk every stage, and as the walk unwinds, thread the
accumulated `CollectedIntentsOperation` through the earlier stage's reader and
append that stage's own commands. This is `merge-commands` plus the ordinary
backward pass. It is the only place where "first answers" and "all answer"
differ.

Containers that route to one child by *coordinate* have no coordinate here.
Route the collect payload to the child the selection is in, which is what
"context sensitive" means.

### 6. The readers label what they produce

The widened `Intent` carries `description` and `domain` on **every** read, not
only on a collection. That is the Lisp's shape: each `gesture-case` case names its
domain and description, so every command flowing through the chain is labelled.

The labels arrive by three different routes, and only the third is work.

- **Free — the reified tables.** 20 `@gestures` / `@gesture_set` blocks and 7
  `get_projection_gesture_bindings` tables already hold a `description` and a
  `domain`. Whatever fires through the three funnels gets labelled with no change
  at the call site.
- **Free — the routing readers.** Most of the 288 `read_intent` methods *route*:
  a container hands the gesture to a child and reroots what comes back. Routing
  keeps the `Intent` it was given, so the labels ride along untouched. The rule
  to hold: **a reader that reroots an operation must preserve the labels**, the
  same way `reroot_operation` preserves everything but the path.
- **Work — the originating readers.** A reader that builds an operation itself,
  outside any table, produces an unlabelled `Intent`. Those are the ones to
  sweep: `SyntaxToText` (10 methods), `WidgetToGraphics` (39), `SqlToSyntax` (40),
  the layout and pane readers, and so on.

The sweep is **incremental by construction**. An unlabelled `Intent` carries
`""` for both fields, which costs nothing at read time and groups under a
fallback heading in the two views. So the change lands working, and each
originating reader is labelled when someone decides its rows should read better.
Do not treat it as a prerequisite.

Pick each `domain` to name the thing that owns the gesture, as the tables already
do: a document type name for a document's rules (`"JsonObject"`), the slice or
projection name for a projection's own (`"clipboard"`, `"Text"`, `"Widget"`).

### 7. Delete the second traversal

`collect_gesture_bindings` and its six overrides go:

- `package/kernel/main/projection/GestureBindings.jl` — the default.
- `package/base/main/projection/higherorder/` — `Chaining.jl`, `Nesting.jl`,
  `Recursive.jl`, `TypeDispatching.jl`.
- `package/visual/main/clipboard/ClipboardToAny.jl` — two overrides.
- `package/visual/main/widget/WidgetHoverTracking.jl`.

Each override exists to mirror what its reader already does. Once collection *is*
the reader, they have nothing left to mirror.

### 8. The two views read the carrier

Both decorators stop walking and start reading:

```julia
result = read_intent(p.inner, recursion, Intent(CollectIntents()), iomap.inner_iomap)
intents = result.operation.intents          # already rerooted
```

- [GestureHelpDecorator.jl](../../package/domain/main/gesturemap/GestureHelpDecorator.jl)
  builds its rows from `intents`.
- [CommandPaletteDecorator.jl](../../package/domain/main/gesturemap/CommandPaletteDecorator.jl)
  does the same, and Enter simply returns the selected `intent.operation`. No
  name, no re-dispatch, no `fire_named_gesture_binding` at that point.
- `GestureRow` loses `name` and `runnable`: a row is runnable when its intent
  carries an operation.

**The domain is the grouping key.** It already is:
[GestureMapToSyntax](../../package/domain/main/gesturemap/GestureMapToSyntax.jl)
emits a heading whenever `row.domain` changes, and the palette matches the query
against `"<domain> <description>"`. The difference is where the value comes from —
the `Intent` the reader returned, rather than a field the collector re-derived
from a binding. Group in collection order, which is chain order: the innermost
document's rules first, the outer stages after, so the rows a user is most likely
to want head the list.

An intent whose `domain` is `""` groups under one fallback heading, so an
unlabelled originating reader is visible as exactly that — a group asking to be
labelled — instead of being silently mixed into someone else's.

## What this retires

- The `run set` / `show set` split in the palette, and the "key only" marking.
- `gesture_row(…; runnable, applicable)` and the guessing behind both flags.
- The reason a keyless command needed a name to be reachable at depth. The name
  stays useful — it is what the user types to *find* a command — but it is no
  longer how the command is *run*.

## Decisions to take first

1. **Does a declining binding still produce a row?** This plan keeps it, with
   `operation === nothing`, so the help window keeps its greyed rows. The Lisp
   drops it. Dropping it is simpler and loses the greyed display.
2. **Does an unlabelled reader block the change?** No — see "the readers label
   what they produce" below. It is listed here only so the incremental sweep is a
   decision taken on purpose rather than a thing left half done.

## `Intent` moves to the operation layer

Settled. `Intent` lives in `projection/Intent.jl` — **layer 13** — while
`fire_gesture_bindings`, the funnel that must build one, lives in
`binding/GestureBinding.jl` — **layer 11**. That is an upward edge
`test_kernel_layering()` rejects.

Move `Intent.jl` to `operation/`, layer 10. It is two untyped fields, it names
nothing above layer 10, and its other half *is* an operation, so the operation
layer is its honest home. `ClaimedGesture` moves with it.

The include lists that change are `operation/OperationLayer.jl` and
`projection/ProjectionLayer.jl`, both **unsealed**. The sealed
`ProjecturedKernel.jl` includes only the per-layer files, so it does not change.
Update the layer inventory in `CLAUDE.md` in the same commit.

## Phases

Work in a dedicated worktree. Commit after each phase. Keep
`collect_gesture_bindings` alive until Phase 6, so every phase runs green.

### Phase 1 — the vocabulary

1. Move `Intent.jl` down (see the decision above), then widen `Intent` with
   `description` and `domain`, both defaulted.
2. Add `CollectIntents` and `CollectedIntentsOperation`.
3. Add the `reroot_operation` method.
4. Test the reroot in isolation, mirroring the `CompoundOperation` test in
   `RerootingTest`.

### Phase 2 — the funnels

1. Add the collect branch to `fire_gesture_bindings`, `read_bound_gesture` and
   `read_projection_gesture`.
2. Test on a `@gestures` probe document: the collected set equals the fired set.

### Phase 3 — the combinators

1. Chaining: walk every stage and merge as it unwinds.
2. Nesting, Recursive, TypeDispatching: route the payload as the reader routes a
   gesture.
3. Clipboard and hover tracking: same.
4. Test against today's `collect_gesture_bindings` output — the two must agree on
   *which* bindings are found, while the new path adds the operations.

### Phase 4 — the two views

1. The help window builds rows from the carrier.
2. The palette builds rows from the carrier, and Enter returns the operation.
3. Test the clipboard-wrapped pipeline: rows are runnable and running one edits
   the JSON document inside the wrapper. This is the case that fails today.

### Phase 5 — label the originating readers

1. Open the help window over each example and read the fallback group.
2. Give each originating reader in it a `domain` and a `description`.
3. Repeat until the fallback group is empty, or stop wherever the value runs out —
   the rows work either way.

This phase has no end state that blocks the others. It can land after Phase 6.

### Phase 6 — remove the old traversal

1. Delete `collect_gesture_bindings` and its six overrides.
2. Move the tests that call it onto the reader path.
3. Run `test_kernel()`, `test_base()`, `test_visual()`, `test_domain()`.

### Phase 7 — documentation

1. The binding-layer section of
   [devices-and-backends.md](../../package/kernel/doc/devices-and-backends.md).
2. The gesturemap slice in the domain architecture guide.

## Risks

- **Building an operation must be pure and cheap.** Every candidate operation is
  now constructed whenever the user opens the help window or the palette. A
  binding whose right-hand side has a side effect would fire it. Audit the
  `@gestures` bodies for anything that mutates before Phase 2 lands.
- **A reader that does not answer the payload contributes nothing.** It declines,
  as it declines an unknown event, so the failure mode is a missing row rather
  than an error. That makes an incomplete migration quiet; Phase 3's comparison
  against the old collector is what catches it.
- **Chaining's first-match shape is load-bearing** for ordinary gestures. The
  collect branch must not disturb it.
