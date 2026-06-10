# Make the originating gesture available to every projection reader

Right now a projection reader sees **either** the raw input event **or** a
backward-mapped operation — never both. The reader chain in
[`Sequential.jl`](../../program/src/projection/higherorder/Sequential.jl)
tries each step *last → first* with the raw event until one returns an
`Operation`, then walks *back* through the earlier steps handing each the
**operation** only ([`Sequential.jl:78-92`](../../program/src/projection/higherorder/Sequential.jl#L78-L92)).
So by the time a click-derived `ReplaceSelectionOperation` reaches
`SyntaxToText` on the backward walk, the original `MousePress` (and its
modifiers) is gone.

This plan adds the missing capability: **the originating gesture should ride
through the whole reader chain alongside the operation**, so any reader can
inspect *what the user did* while transforming *what it means*. It is the
prerequisite for finishing the mouse side of tree navigation — see
[`finish-syntax-tree-navigation.md`](finish-syntax-tree-navigation.md).

## Why — what the Lisp original does

In ProjecturEd-Lisp the unit that flows through the reader chain is a
**command**, not a bare operation:

```lisp
(def class* command ()
  ((gesture :type gesture)        ; the raw input — constant through the chain
   (operation :type operation)    ; what to do — filled in / transformed
   (domain ...) (description ...) (icon ...) (accessible ...)))
```
([`command.lisp:12-18`](../../../projectured-lisp/source/editor/command.lisp#L12-L18))

The read starts from `make-nothing-command(gesture)` — the gesture wrapped in
a "Does nothing" operation ([`command.lisp:30`](../../../projectured-lisp/source/editor/command.lisp#L30)).
Every reader receives that command as `-input-` and exposes
`-gesture- = (gesture-of -input-)` ([`reader.lisp:19-21`](../../../projectured-lisp/source/editor/reader.lisp#L19-L21)).
A reader that acts returns a **fresh** command via `clone-command`, which
**keeps the gesture** and only swaps in a real operation
([`command.lisp:33-35`](../../../projectured-lisp/source/editor/command.lisp#L33-L35)).
`merge-commands` then picks the first command carrying a real operation
([`command.lisp:46-59`](../../../projectured-lisp/source/editor/command.lisp#L46-L59)).

Net effect: the gesture is a **constant context** available at every layer;
the operation is the part that gets produced and mapped. That is exactly the
piece the Julia pipeline lacks. Concretely it lets the syntax reader do things
like ([`syntax-to-text.lisp:1236-1246`](../../../projectured-lisp/source/projection/primitive/syntax-to-text.lisp#L1236-L1246)):

```lisp
(if (and (typep -gesture- 'gesture/mouse/click)        ; raw gesture
         (typep operation 'operation/replace-selection) ; backward-mapped op
         (equal (selection-of operation) selection))    ; current selection
    (promote-to-whole-node)
    operation)
```

## The Julia structural constraint

Lisp has **one reader per projection** and inspects gesture/operation
*inside* it (`gesture-case`, `reference-case`). Julia uses **multiple
dispatch on the operation's type**:
`projection_read(p, iomap, op::ReplaceSelectionOperation)`,
`projection_read(p, iomap, evt::KeyDown)`, etc. That difference is what makes
the port a real design choice, captured as the two options below.

Reference points in the current Julia code:
- Top-level entry: `read!` passes the event into the pipeline reader and reads
  back `editor.operation` ([`Editor.jl:72-91`](../../program/src/editor/Editor.jl#L72-L91)).
  (The `EventEnvelope` is unwrapped to a raw event upstream at the screen layer —
  [`Copying.jl:271-292`](../../program/src/projection/generic/Copying.jl#L271-L292).)
- The default reader handles `ReplaceSelectionOperation` / `ToggleCollapseOperation`
  and returns `nothing` otherwise ([`Projection.jl:69-81`](../../program/src/common/Projection.jl#L69-L81)).
- Transparent wrappers forward whatever they get:
  [`Recursive.jl:45-47`](../../program/src/projection/higherorder/Recursive.jl#L45-L47),
  [`TypeDispatching.jl:56-63`](../../program/src/projection/higherorder/TypeDispatching.jl#L56-L63).

---

## Option A — literal command wrapper (most faithful)

Introduce a `Command{gesture, operation}` and flow it through the reader chain,
mirroring Lisp 1:1.

- New `struct Command; gesture; operation; end` (operation may be `nothing`).
- `read!` seeds `Command(event, nothing)`; after the read it uses
  `command.operation`.
- `projection_read(projection, iomap, cmd::Command) -> Command` everywhere; each
  reader inspects `cmd.gesture` and/or `cmd.operation` and returns a `Command`
  with the gesture preserved.

**Cost.** Julia readers stop dispatching on operation type — every
`projection_read(p, iomap, op::SomeOp)` becomes one `cmd::Command` method with
an internal `if cmd.operation isa …` / `if cmd.gesture isa …` ladder. That is a
large, cross-cutting rewrite of every projection's reader and discards the
multiple-dispatch structure the codebase is built on. It also changes the
`read!` boundary (unwrap `.operation`).

**Pro.** Exactly the original architecture; `merge-commands`-style composition
and per-command metadata (domain/description, useful later for a command
palette / context help — cf. [`gesture-help.md`](../tentative/gesture-help.md))
become natural.

## Option B — thread the gesture as reader context (keeps dispatch)

Keep operation-type dispatch; pass the originating gesture as an extra,
optional argument that is available to any reader that wants it.

1. Generic fallback so existing readers are untouched
   ([`Projection.jl`](../../program/src/common/Projection.jl)):
   ```julia
   projection_read(p, iomap, op, gesture) = projection_read(p, iomap, op)
   ```
2. `Sequential` threads it through the **backward** walk only (the forward/while
   phase already passes the raw event, so keyboard handling is unchanged):
   ```julia
   op = projection_read(seq.projections[i], iomap.step_iomaps[i], op, event)
   ```
   Add a 4-arg `Sequential` method too, for nested sequentials.
3. `Recursive` / `TypeDispatching` gain 4-arg forwarders so the gesture reaches
   the leaf projection.
4. A reader that needs it overrides the 4-arg form, e.g.
   `projection_read(p::SyntaxNodeToText, iomap, op::ReplaceSelectionOperation, gesture)`.

**Cost.** A handful (~5) of contained method additions; one extra argument on a
seldom-overridden path. The `read!` boundary and return type are unchanged.

**Pro.** Idiomatic Julia; preserves multiple dispatch; minimal blast radius.

**Con vs A.** No first-class `Command` object, so the metadata/`merge-commands`
machinery is not gained here (can be added later independently if a command
palette is ever wanted).

---

## Recommendation

**Option B**, unless we specifically want the `Command` object for a future
command-palette / context-help feature. B delivers the only thing the tree-nav
work needs — *the gesture available in the reader* — at a fraction of the churn.
**This is the open decision (the user is undecided).**

## Payoff once either lands

With the gesture reachable in `SyntaxToText`, the ad-hoc carrier can go away:

- The `from_click::Bool` flag on `ReplaceSelectionOperation`
  ([`Operation.jl:35-61`](../../program/src/common/Operation.jl#L35-L61)) — today
  the only way click-ness reaches the syntax layer — collapses to a direct
  `gesture isa MousePress` check, exactly Lisp's `(typep -gesture- 'gesture/mouse/click)`.
  Its sole consumer is the marker-toggle disambiguation in `SyntaxToText`'s
  `ReplaceSelectionOperation` reader.
- The mouse half of tree navigation can move entirely into `SyntaxToText`
  (see the sibling plan).

## Testing

- `test_cell()` is unaffected; the change is in the reader plumbing.
- Reader/selection/repl coverage is what exercises this: `test_reader(json_example)`,
  `test_selection(json_example)`, `test_repl(json_example)`, plus
  `test_text_to_graphics()`. Click round-trips:
  [`ClickRoundtripTest.jl`](../../test/src/editor/ClickRoundtripTest.jl),
  [`MouseClickTest.jl`](../../test/src/editor/MouseClickTest.jl).
- Broad sweeps (`test_readers()` / `test_selections()` / `test_repls()`) only as a
  final check — per [`CLAUDE.md`](../../CLAUDE.md).
- For Option B specifically, add a focused test that a click-derived
  `ReplaceSelectionOperation` reaches a 4-arg `SyntaxNodeToText` reader carrying
  the `MousePress` gesture.

## Open decisions

1. **A (command wrapper) vs B (threaded gesture context).** Undecided.
   Recommendation: B.
2. If B: extra **positional** arg (chosen above, plays well with dispatch) vs a
   keyword arg (awkward with multiple dispatch — rejected unless a reason emerges).
3. Whether to also **remove `from_click`** as part of this change or in the
   tree-navigation finish plan (it is listed there to keep this plan
   mechanism-only).

## Relationship to other plans

- **Blocks** [`finish-syntax-tree-navigation.md`](finish-syntax-tree-navigation.md)
  (mouse promotion needs the gesture in the syntax reader).
- **Touches the same readers** as the deferred Phase 3 of
  [`event-case-migration.md`](event-case-migration.md); sequence this first, then
  migrate those readers to `@event_case`.
