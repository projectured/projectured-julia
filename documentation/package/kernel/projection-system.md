# The Projection System

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

A **projection** is a bidirectional transformation between two domains. It is the
central abstraction of ProjecturEd: every screen the user sees, and every gesture
they make, flows through one or more projections.

A projection has four entry points:

```julia
print_document(projection, recursion, input, context::PrinterContext) → iomap
read_intent(projection, recursion, change::Intent, iomap)            → Intent
map_reference_forward(projection, iomap, reference)                       → output_ref_or_nothing
map_reference_backward(projection, iomap, reference)                      → input_ref_or_nothing
```

The four functions come in two symmetric pairs, one per direction of data flow.
Forward, `print_document` produces the output **and** wires the cursor by
calling `map_reference_forward`. Backward, `read_intent` consumes a
backward-flowing [`Intent`](#the-intent-the-reader-threads) (a gesture plus the
operation produced so far) **and** maps the cursor by calling
`map_reference_backward`.
The general rule that follows from this symmetry, and that the rest of this
guide relies on, is:

> **`print_document` uses `map_reference_forward`; `read_intent` uses
> `map_reference_backward`.** The two mappers are the single source of truth for
> how a path crosses the projection, written once and reused on both sides.

All four are generic functions declared in
[source/kernel/projection/ProjectionInterface.jl](../../../source/kernel/projection/ProjectionInterface.jl) and dispatched on
the concrete projection struct.

## The recursion contract

These four functions are **the** interface a projection implements — nothing else
is universal across every projection. The single contract that makes arbitrary
projections compose is that **all recursion flows through these four, and only
these four**:

> When a projection descends into a child document, each of the four functions
> hands that child to the **child projection's own** version of *the same*
> function — the printer via the `recursion` argument
> (`print_child(recursion, child, ctx)`), the reader and both
> mappers via the **stored child IoMaps** (`ChildrenIoMap.child_iomaps`). Every
> function maps its **own single level** and delegates the rest.

Two corollaries, both load-bearing:

1. **You may not introduce a fifth recursive function.** It is tempting, when a
   projection needs to walk a tree, to add a new generic helper that each
   projection implements and that recurses by calling itself. Do not. The four
   functions are implemented by *every* projection; a fifth would not be. The
   moment a pipeline composes a projection that relies on the fifth function with
   one that does not, recursion breaks at that boundary. That is the opposite of
   composition. Express all descent through the four functions everyone already
   implements. This is also why the contract is **validated externally**, by a
   test harness that drives the four functions over composed examples (see
   [Validating the recursion contract](../../guide/testing-guide.md#validating-the-recursion-contract)),
   rather than by adding an introspection method projections would have to
   implement.

2. **You may not self-walk or flatten a subtree by child type.** A function must
   not recurse over the input/output subtree itself, dispatching on each child's
   concrete type, and bake the whole subtree into its result. That is the "School
   B" anti-pattern (see [Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)
   and [Recursion across projections](#recursion-across-projections)). Delegate one
   level through the child IoMap / `recursion` instead ("School A").

The rest of this guide is the contract spelled out per function: the printer
recurses via `recursion` ([§ Recursion across projections](#recursion-across-projections)),
and the reader and both mappers recurse via the stored child IoMaps
([§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)).
Every projection in the tree honours it, including `SyntaxCompoundToText` and
`SyntaxListToText`. See [plan/done/syntaxtotext-delegation.md](../../../plan/done/syntaxtotext-delegation.md) for a worked
before/after example of this contract.

## The four functions

### `print_document` — the printer

Forward transformation from the input domain to the output domain. Returns an
`IoMap` (subtype of `IoMap`, see [iomap/IoMapInterface.jl](../../../source/kernel/iomap/IoMapInterface.jl))
that records the input, the output, and any extra data the reader needs to
invert the transformation.

The two extra arguments are essential:

- **`recursion`** is the projection to call when descending into sub-documents
  (typically populated by `RecursiveProjection`, which passes *itself* so the
  inner projection can recurse through the whole pipeline). A leaf projection
  that never descends ignores it. A node projection threads it **twice** — as
  the projection to call *and* as that call's own `recursion` argument; see
  [§ Recursion across projections](#recursion-across-projections).
- **`context`** is a [`PrinterContext`](../../../source/kernel/projection/PrinterContext.jl):
  a downward-flowing, extensible struct carrying the `reference` path from the
  editor's document root to the *current* input, plus the range that the
  parent gives on each axis (`minimum_width`/`maximum_width`,
  `minimum_height`/`maximum_height`: exact, bounded or free) and an open
  `properties` Dict. Each
  projection extends the reference before recursing into a child by calling
  `make_child_context(ctx, step…)` (or `make_child_context(ctx, full_path)`), so every
  projection's context carries where it sits in the original document. This is
  what enables [ReferenceDispatchingProjection](../platform/projection/higher-order-projections.md) to
  switch behaviour based on document-root-relative location. The top-level call
  passes a fresh `PrinterContext()` (whose reference is
  `EmptyReference()`).

A two-argument convenience overload `print_document(p, input)` is defined in
[projection/ProjectionDefaults.jl](../../../source/kernel/projection/ProjectionDefaults.jl) and supplies
`nothing` and a fresh `PrinterContext()`. It serves a leaf projection, or a
pipeline that a `RecursiveProjection` wraps. A node projection called through it
has no `recursion` to print its children with. The editor calls the four-argument
form: its `recursion` is `nothing`, and its context carries the clock of the
editor, the document of the editor under `:root`, and the fault store and the
fault policy.

**Wiring the selection.** The output document's `selection::Cell` is not a
parameter; it is computed reactively. The canonical form maps the input
selection forward through this projection's own mapper, so the path mapping is
defined in exactly one place:

```julia
output.selection = Cell(@computation map_reference_forward(p, iomap, input.selection))
```

For a node projection the `iomap` does not exist yet when the cell is built; use
the deferred-iomap trick (`iomap_cell = Cell(nothing)`; assign it after
constructing the IoMap — see `CopyingProjection`). A leaf whose input and
output selection formats are identical may instead *share* the same
`selection::Cell` on both sides (`getfield(input, :selection)`); that shortcut
is valid only leaf-to-leaf (see [§7 of the selection deep dive](selection.md)).

A compound projection that introduces *structural* output nodes with no input
counterpart (e.g. `PaneToWidget`, whose tree stage wraps the printed layout in a
`WidgetComposite` that also carries the drop indicator) wires those nodes'
`selection` cells explicitly: it forward-projects the pane tree's own selection
and re-roots it onto the wrapper with a small index prefix. Once wired, those
forward-projected selection cells let the reader route events by selection —
see below and [the selection guide](selection.md#forward-projecting-selection).

### `print_document_pure` / `print_child_pure` — the pure printer

A second interpreter of the same projection produces the output tree directly,
with no `IoMap`, no reactive cells, and no selection wiring:

```julia
print_document_pure(projection, recursion, input, ctx) → output
print_child_pure(recursion, input, ctx) → output
```

The pair is for batch or export work, such as an image, a PDF or a text
serialization, where nothing is edited and no selection maps back. No pipeline of
the repository calls it: the export functions print with `print_document`.
Every projection gets this automatically: the default falls back to a snapshot of the
reactive output, so a projection author writes `print_document_pure` only to
skip that snapshot on a path a profile shows is slow. `ChainingProjection`,
`RecursiveProjection`, and `TypeDispatchingProjection` thread the pure call so a
whole pipeline stays pure. Both functions are declared next to the other four
in
[source/kernel/projection/ProjectionInterface.jl](../../../source/kernel/projection/ProjectionInterface.jl).

### The `Intent` the reader threads

The reader's payload is a **`Intent`** ([intent/Intent.jl](../../../source/kernel/intent/Intent.jl)) —
the backward-flowing dual of the document that flows forward through the printer:

```julia
struct Intent
    gesture::Any        # the originating input (MouseClick/KeyDown), threaded UNCHANGED
    operation::Any      # the change in the current projection's input domain; starts nothing
    description::String # what the change does, in words; empty when the reader says nothing
    domain::String      # the heading that groups the change in a list of what is available
    route::Union{Nothing,Reference}  # the path to the place of an operation that code
                                     # made, or to the part that a gesture is for
end
```

- **`gesture`** is the raw thing the user did. It passes through **unchanged** the
  whole way up the chain, so any reader can inspect *what the user did*, not just
  what it currently means. (Example: `SyntaxToText`'s reader needs the raw click
  coordinates from the gesture to hit-test a mouse click back to a character
  offset, even though what eventually flows back is a selection move.)
- **`operation`** starts as `nothing` (a "nothing-change") and is filled in /
  re-mapped by each reader as the change travels one domain inward.

A reader returns a `Intent`: either it keeps `operation === nothing`, meaning it
found no operation to return, or it returns a fresh `Intent` with the gesture
preserved and a real operation swapped in.

The fifth field, `route`, carries a path when the change comes from code that
already has the place its operation belongs to, rather than from a gesture;
a reader follows it down to that place and lifts the answer back up exactly as
it lifts the answer to a gesture — see
[editor.md](editor.md#an-operation-from-a-place-not-a-gesture). A gesture that is
for one part, such as a leave for the part that the pointer left, carries the path
to that part in the same field. A container whose IO map holds its children follows
a route by default (`read_routed_child`).

### `read_intent` — the reader

```julia
read_intent(projection, recursion, change::Intent, iomap) → Intent
```

The symmetric dual of `print_document` — both take
`(projection, recursion, payload, context)`, where the payload is the `Intent`
and the context is the printer's `iomap`. The reader turns an output-domain
change into an input-domain one and returns a `Intent` (operation filled in /
re-mapped, gesture preserved), or a nothing-change if it has nothing to say.

The editor hands the raw device event to the **top-level** projection's
`read_intent`; routing from there is up to each projection. A
`ChainingProjection` forwards the change down its chain and threads the
operation that comes back up through each earlier step; a routing projection
instead dispatches it to the sub-projection of the relevant document part.

**Most projections need no `read_intent` method.** The default in
`ProjectionModule` re-targets any reference-carrying operation —
`ReplaceSelectionOperation`, `ReplaceStringRangeOperation`,
`ReplaceNumberRangeOperation` — by mapping its reference with
`map_reference_backward`. So a projection that only moves the cursor or edits a
value through a structure-preserving map needs **only** the two reference-mapping
functions. Write a `read_intent` method (the 4-arg `Intent` form above) only
when you must do more than re-target a reference. The moves available, from the
lightest touch to the most involved:

- **Re-target the references.** Most often the incoming operation is the right
  *kind* and only its references need moving from output to input coordinates
  with `map_reference_backward` — rewrite the `.reference` of a
  `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`, or the path of
  a `ReplacePathOperation` (this is what the default already does for you, for
  the selection and for the part under the pointer alike), then rebuild the op
  with `make_path_operation(op, path)`.
- **Convert to a different operation.** It is perfectly valid to turn the
  incoming operation into a *completely different* one — retype it (e.g.
  `JsonNumberToSyntaxLeaf` turns a `ReplaceStringRangeOperation` into a
  `ReplaceNumberRangeOperation` so the evaluator re-parses the value), or
  replace it outright with whatever operation expresses the same intent in this
  projection's input domain.
- **Recurse, then extend.** When `print_document` descended into children,
  mirror it: forward the event/operation to the matching child's
  `read_intent`, take the operation it returns, and extend it to this
  projection's context — typically by prepending the steps that reach the child
  (see [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)).
- **Probe a child to decide.** A reader may *speculatively* recurse into a
  document part's reader just to see what operation it would return, and use
  that answer to decide its own final operation. For example, it can choose
  among alternatives, or act only when the child returns `nothing`.
- **Route by selection.** When the printer forward-projected the selection onto
  this node (see [Wiring the selection](#print_document-the-printer)), a
  reader can read its node's `selection` to forward a coordless event (a
  keystroke) *only* to the child the selection points at, rather than
  broadcasting to every child. This is the usual desired behavior — the
  keystroke goes where the cursor is. The widget split pane and tabbed pane do
  exactly this; see
  [the selection guide](selection.md#selection-directed-event-routing).

Whichever moves it makes, a projection returns a `Intent` carrying an operation
in its own input domain (or a nothing-change); the operation the **top-level**
projection ultimately returns is the final answer the editor applies to the
document.

#### Domain-owned, geometry-free gesture mapping (`read_gesture`)

A projection reader mixes two kinds of gesture handling, and only one of them is
really the *projection's* business:

- **Geometry-dependent.** Needs the laid-out output — pixel coordinates, the
  measured glyph map, hit-testing. Example: a mouse click to a cursor position,
  or visual line up/down. This *must* live in the projection that owns the
  layout (e.g. `TextToGraphics`'s `char_to_coord`).
- **Geometry-independent.** Reads only the domain document's own structure and
  its `selection`. Example: inserting a character, Backspace/Delete, moving the
  character cursor left/right across spans, or stepping a whole-element selection
  around a tree. None of this needs pixels.

The geometry-independent half is a property of the **domain document**, not of
the projection that happens to render it. It lives behind
`read_gesture(document, gesture) -> Union{Operation, Nothing}`
([document/DocumentInterface.jl](../../../source/kernel/document/DocumentInterface.jl)): the document maps the
gesture to an operation in its **own** reference vocabulary (reading only its
structure and `document.selection`), or returns `nothing` when it does not handle
the gesture, which lets an outer layer claim it instead. The operation then flows back through the normal
`map_reference_backward` chain like any other.

A projection reader **delegates** to it and keeps only its geometry arms:

- `TextToGraphics` calls `read_gesture(iomap.input, evt)` for character
  insert/delete and left/right/Ctrl+Home-End cursor motion, and keeps visual
  up/down, plain Home/End, and mouse click.
- `SyntaxToText` (`SyntaxCompoundToText`) calls `read_gesture(iomap.input, evt)` for
  tree navigation (Ctrl+Alt+Home, Ctrl+Space toggle, Alt/structural arrows), and
  keeps the mouse hit-test for collapse glyphs and Alt+click.

The payoff: any backend that renders a domain **directly** gets the
geometry-free editing automatically. The console pipeline (`… → SyntaxToText →
WindowInputUnwrapping`, no `TextToGraphics`) reuses `SyntaxToText`'s existing reader.
When its operation slot is still empty (the console case) and it does not
handle the gesture as a syntax gesture, that reader falls back to
`read_gesture(iomap.output, gesture)` on the output `TextBlock` and maps the
result backward. In SDL the operation slot is already filled by `TextToGraphics`,
so that fallback is a no-op and SDL behaviour is unchanged.

> **The 3-arg reader form.** Many projections implement their reader as a 3-arg
> `read_intent(projection, iomap, event_or_op)` returning a bare operation, which
> the generic bridge adapts to the 4-arg `Intent` interface. Reach for the 4-arg
> `Intent` form when a reader must do more than return an operation.

#### Recursive gesture reading: delegate to the selected child, lift the operation

The "Recurse, then extend" and "act only when the child returns nothing" patterns
above are not just options. Together they are the **default** a structural
(container) projection's reader should follow for a raw authoring gesture:

> **A structural projection delegates a raw gesture to the projection of the
> *selected child* element, and lifts the child's operation back into its own
> domain. It handles the gesture itself only when the child returns nothing for
> it. It may override, but in general it should not.**

This is the reader-side mirror of three things the printer side already does:

- the **printer** is recursive — a `@projection_template`'s `collection`/`project`
  delegate each child subtree to the child's projection and record the per-child
  correspondence (`child_iomaps`);
- the **operation reader** is recursive — `map_reference_backward` walks
  `child_iomaps`, so an operation whose path points into a child is mapped through
  the child projection (see [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses));
- **container event routing already lifts** — `WidgetToGraphics` / `LayoutToGraphics`
  route a mouse gesture to the hit child and lift the returned operation with
  `reroot_operation` ([operation/Rerooting.jl](../../../source/kernel/operation/Rerooting.jl)).

The template engine applies the rule **automatically**: the `TemplateIoMap` reader in
[projection/ProjectionTemplate.jl](../../../source/kernel/projection/ProjectionTemplate.jl)
handles a raw `KeyPress`/`KeyDown` (the keystrokes the Text/Syntax layers
left unhandled — the domain *authoring* gestures of [`read_gesture`](#domain-owned-geometry-free-gesture-mapping-read_gesture))
by (1) finding the selected child from the node's `selection` and its
`child_iomaps`, (2) delegating the gesture to that child's `read_intent`, and
(3) **lifting** the child's operation with `reroot_operation`, prepending the
input step that reaches the child (`entries[i].value`, `elements[i]`). Only when
the focused child returns `nothing` does the node fall back to `read_gesture` on
its own input document. So a node never needs to special-case nested editing. The
recursion descends innermost-first and **bubbles**: the *nearest enclosing*
structural node whose `read_gesture` produces an operation wins (e.g. `,` inserts
a sibling into the nearest enclosing object/array, `Tab` steps key→value in the
enclosing object), exactly where the cursor is.

Each level reads its **own** `iomap.input.selection`: `set_selection!` propagates
the selection down the document tree, so every focused node already holds its own
subtree-relative path (the root the full path, a nested object its relative one).
No selection threading is needed. The lift is purely prepending the input steps.

A caret on a part that a node printed, such as its closing `}`, is that node's
own selection, because the introduced step stands at the node (see the next
section). So a rule can ask where the caret is in its own output. The `,` rules
of a JSON container decline on their own closing delimiter
(`is_on_closing_delimiter` of the syntax slice), and the parent container
answers the key.

### `map_reference_forward` / `map_reference_backward` — the reference maps

These translate a `Reference` from input-domain coordinates to
output-domain coordinates and vice versa. Returning `nothing` means "this
reference has no image" — e.g. structural delimiters introduced by the
projection cannot map back to the input.

`ReplaceSelectionOperation` flowing up the pipeline is implemented entirely in
terms of these two functions, so getting them right gives you cursor
navigation across the entire pipeline with no extra work.

The pattern-matching DSL `@reference_case` (see
[the reference guide](reference.md)) makes these methods readable:

```julia
function map_reference_backward(::JsonBoolToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end
```

Two principles keep these methods correct across the whole pipeline:

- **Recurse in lockstep with the printer.** If `print_document` recursed into
  children, both mappers must recurse too: peel only the step this projection
  owns, look the child up in the stored child IO maps, delegate the remaining
  tail to that child projection's own mapper, and prepend the steps that reach
  the child. This is spelled out in
  [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses).
- **Cross domains as late as possible.** When an output reference points at
  something the projection introduced (a delimiter, separator, bracket,
  indentation), it has no input pre-image. Represent it by keeping input-domain
  steps for as long as the path still has a pre-image, then wrapping *only the
  genuinely output-only tail* in this projection's own step:

  ```
  matched_input_prefix + ProjectionReferenceStep(projection, unmatched_output_suffix)
  ```

  The path then composes in order: input steps say where in the document
  you are, and `ProjectionReferenceStep(projection, …)` marks the exact point where
  you cross into something that exists only in `projection`'s output. Because
  `map_reference_forward` strips that same step, the path round-trips cleanly.

  In a template, the step stands at the innermost node whose projection printed
  the position. When a child can not map a position of its own output back, the
  child makes its own introduced step, and each parent prepends the steps that
  reach the child (`_map_child_backward` in `ProjectionTemplate.jl`). A caret in
  the indentation of a line follows the same rule: the level that widens the
  indentation prints those spaces, so the step stands at that level.

  The step holds a path in the output of the projection that made it, such as
  `.open{0}` for the bracket of a syntax node, and never an offset in the output of
  a later stage, which only that stage can read. The forward map takes off its own
  step and answers that path (`proj(^(p), inner) => inner`), so the next stage maps
  it forward as any path of its input. A flat offset is correct only where it is a
  position in the projection's own output, as in the chrome of
  `SyntaxCompoundToText`.

## IoMap

`IoMap` is the abstract supertype of every map returned by `print_document`.
Every IoMap has a `projection`, `input`, and `output` field. Common shapes:

| Type | Use case |
|---|---|
| `SimpleIoMap` | Projection with a strict positional contract; the reader can recover everything from the structure |
| `ChildrenIoMap` | Output has recursively projected children; a `child_iomaps::Cell` holds the per-child IoMaps |
| `ContentIoMap` | Wraps a single inner projection |
| `{Name}IoMap` | Specialised — each non-trivial projection defines its own |

`ChainingIoMap` stores `step_iomaps::Vector{Any}` so the reader can
walk the pipeline backward. `TextToGraphicsIoMap` carries a
`char_to_coord::Cell` so the reader can binary-search a click position back to
a character offset.

The `@iomap` macro (parallel to `@document`) generates an IoMap struct whose
`::Cell` fields are accessed transparently — see [the macros guide](macros.md).

A fault barrier wraps the IoMap of each part at a recursion point, so the IoMap
of a child can be the IoMap of a barrier. While the part prints, the barrier adds
nothing to it: it keeps the IoMap of the part in `inner_iomap`, and a property
that it does not have is read from that IoMap. Read `.output` of a child through
the barrier, so a mark shows when the part fails. Where a reader or a printer
checks the type of the IoMap of a child, call `get_content_iomap(child)`, which
answers the IoMap of the part, or the barrier while it draws a mark. The fault
guide says why: [fault.md](../platform/fault/fault.md).

### Stable identity, reactive fields

An IoMap keeps its **identity** for the life of its projection instance. A change
never replaces it, so a chain's `step_iomaps` and any other projection that wired
to it stay valid. What *varies* (the `output`, its selection, the child IoMaps) is
a **computed cell** that re-derives from the projection's input and parameter
cells; an operation writes a cell and the change propagates through the existing
IoMap with no re-print. This is
[PAR-STABLE-IOMAP-IDENTITY](../../rule/architecture-invariants.md#par-stable-iomap-identity),
and `make_reconciled_child_iomaps_cell` (iomap layer) is the shared way to keep
child-IoMap identity across a structural edit. Note the split: `@iomap`/`@projection`
give the transparent cell *fields*, but wiring those fields as **derivations** (a
`Cell(@computation …)`, not an eagerly computed value) is what makes them reactive —
`FocusingProjection` is the reference
(`output = Cell(@computation evaluate_reference(input, p.part))`).

## Projection categories

The **higher-order** and **generic** rows below are the complete sets. An
agent can treat them as exhaustive. The domain-to-domain and domain-preserving
rows are representative (every domain adds its own `*To*` projection).

| Category | Members | Purpose |
|---|---|---|
| **Domain-to-domain** | `JsonToSyntax`, `SyntaxToText`, `TextToGraphics`, `WidgetToGraphics`, `PaneToWidget`, `XmlToSyntax`, `ObjectToSyntax`, `BookToSyntax`, `JuliaToSyntax`, `MathToSyntax`, `FileSystemToSyntax`, `PrimitiveToSyntax`, `CollectionToSyntax`, `HighlightedTextToText`, `FilteredTextToText`, … | Translate between two distinct domains |
| **Domain-preserving** | `WordWrapping`, `TextLineNumbering`, `GraphicsCanvasToGraphicsImage`, `ScreenToScreen`, … | Same domain in and out (`ScreenToScreen` is the screen-domain projection — see [the screen pipeline](#the-screen-pipeline)) |
| **Generic (domain-independent)** | `CopyingProjection`, `SortingProjection`, `ReversingProjection`, `FilteringProjection`, `SearchingProjection`, `FocusingProjection`, `IdentityProjection`, `ConstantProjection`, `ObjectToWidget` | Operate on any input domain *by structure, not by type* (8 in `generic/`, plus `ObjectToWidget` in `widget/`). Most also preserve the domain; `ObjectToWidget` is input-independent but produces widgets |
| **Higher-order** | `ChainingProjection`, `TypeDispatchingProjection`, `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`, `RecursiveProjection`, `SwitchingProjection`, `NestingProjection`, `WindowInputUnwrappingProjection`, `WindowManagingProjection`, `TooltipDecoratorProjection`, `DraggingProjection` | Compose other projections (8 in `higherorder/`; the other 3 sit beside the domain each one touches) |
| **Compound** | `ApplyAtProjection`, `SortingAtProjection` | Convenience combinators built from higher-order primitives |

See [higher-order projections](../platform/projection/higher-order-projections.md) and
[generic projections](../platform/projection/generic-projections.md) for details.

## The forward and reverse paths

A typical pipeline looks like:

```
JsonString ──JsonStringToSyntaxLeaf──► SyntaxLeaf ──SyntaxLeafToText──► TextBlock ──TextToGraphics──► GraphicsCanvas ──► SDL window
   ▲  (selection shared)                                                                    │
   └─────────────────── read_intent chain ◄──── KeyPress / MouseClick ─────────────────┘
```

Forward, each step extends the `context`'s reference path (via
`make_child_context`) so child projections carry their position relative to the
document root, and wires its output selection with `map_reference_forward`.
Backward, each step's IoMap is visited in reverse, with each projection's
`read_intent` translating the operation a step closer to the document's
domain (via `map_reference_backward`).

## Writing a custom projection

1. Define a struct that subtypes `Projection`. Use `@projection` if you have
   reactive Cell fields.
2. Implement `print_document(p, recursion, input, ctx)` returning **one** `IoMap`
   kept for the projection's life. Use `SimpleIoMap` for positional projections,
   or define your own `@iomap` struct when you carry extra data. Wire whatever
   varies (`output`, child IoMaps) as computed cells so a parameter/input change
   re-derives it through the same IoMap
   ([PAR-STABLE-IOMAP-IDENTITY](../../rule/architecture-invariants.md#par-stable-iomap-identity));
   reconcile child collections with `make_reconciled_child_iomaps_cell`.
3. Implement `map_reference_forward` and `map_reference_backward`: usually
   the cleanest way is `@reference_case`. `print_document` wires its output
   selection by calling `map_reference_forward`; the default `read_intent`
   handles selection by calling `map_reference_backward`. Write the pair once
   and both directions work.
4. If your projection needs to do more than re-target a reference (e.g. mouse
   scroll, type-to-edit, retyping an operation), add a 4-arg
   `read_intent(p, recursion, change::Intent, iomap)` method that returns a
   `Intent` carrying the corresponding domain operation. Selection moves and
   structure-preserving edits need no method — the default handles them.

```julia
struct MyProjection <: Projection end

function print_document(p::MyProjection, recursion, input, ctx)
    output = transform(input)
    SimpleIoMap(p, input, output)
end

function map_reference_forward(::MyProjection, iomap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end

function map_reference_backward(::MyProjection, iomap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end
```

### Purity: no global state, no side effects

Two invariants keep projections composable and the reactive graph consistent.

**No global mutable state.** A projection must not read or write module-level
mutable state — no `const cache = Dict(...)` populated at runtime, no mutable
global `Ref`/counter. Every cache, memo, or reconciliation table must be created
*per projection invocation* and live in that invocation's `IoMap` or in the
closures of its own cells. Global state silently leaks across unrelated documents
(two documents rendered in the same process would share, and corrupt, each
other's entries), is never evicted, and is unsafe under the editor's reuse of one
process for many documents.

**No side effects from inside a cell.** A reactive computation — a `Cell(@computation …)`,
or the part of `print_document` that builds one — must be a pure
function of its inputs *as observed by every other reactive node*. In particular
it must never **write another cell** (`other_cell[] = v`) or mutate shared
document state. The eager engine invalidates a written cell's consumers
immediately (see [cell.md](cell.md)), so writing a cell from
inside another cell's computation invalidates those consumers *mid-computation*.
Graphics-domain cells *do* have consumers (e.g. `GraphicsCanvasToGraphicsImage` reads them).
That makes recomputation order-dependent and the graph inconsistent.

To preserve output-object identity across recomputes (printer locality —
reconciliation), do **not** rebuild objects, and do **not** reuse-then-mutate them
with imperative cell writes. Instead reuse a *persistent* object whose
geometry/content fields are `set_cell_computation!` cells that **derive** their value from the
upstream layout cell — the cursor/highlight overlays in `TextToGraphics` are the
canonical example, generalised to every span by its per-segment graphics cache. A
projection's *own* private reconciliation cache (a plain `Dict` held in its cell
closure, populated idempotently and observed by no other node) is not a side
effect in this sense, and is the correct way to key that reuse.

### A compound (node-shaped) projection

A leaf projection maps one document value to one output value. A compound
projection maps one input *node* to an output node whose children are the
recursively-projected input children. The extra requirements are:

1. **Recurse into each child** with `print_child(recursion, child, child_ctx)`
   (see [§ Recursion across projections](#recursion-across-projections)).
2. **Store the child IO maps** in a shared reactive `Cell` (not inline in two
   separate cells — see [§8 of the selection deep dive](selection.md)).
   `make_reconciled_child_iomaps_cell` makes that cell, and it keeps the IoMap of each
   child that stays, as PAR-STABLE-IOMAP-IDENTITY asks.
3. **Project the selection reactively.** Canonically this is
   `Cell(@computation map_reference_forward(p, iomap, node.selection))` with the
   deferred-iomap trick for the not-yet-built `iomap`. The inline form shown
   below reads the child IO maps directly; it is equivalent when the mapper
   would perform the same walk.
4. **Use `ChildrenIoMap`** rather than `SimpleIoMap` so the reader and the
   reference maps can locate the correct child IO map when translating
   backward (see [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)).

```julia
struct MyNodeProjection <: Projection end

function print_document(p::MyNodeProjection, recursion, node::MyNode, ctx)
    # Step 1+2: project the children, and keep their IO maps in one cell.
    # `make_reconciled_child_iomaps_cell` reuses the IoMap of each child that stays, so an
    # edit prints again only a child that is new or moved. `print_child`
    # re-enters the whole pipeline for each child, and `make_child_context`
    # extends the reference path to child i, typed against `node`.
    child_iomaps = make_reconciled_child_iomaps_cell(
        () -> node.children,
        (i, child) -> print_child(recursion, child,
            make_child_context(ctx, node, FieldReferenceStep("children"),
                               ElementReferenceStep(i))))

    # Build the output children from the IO maps
    out_children = CellVector(@computation [m.output for m in child_iomaps[]])

    # Step 3: project the selection reactively
    sel = Cell(@computation(begin
        path = node.selection
        @reference_case path begin
            children[i].rest... => begin
                iomaps = child_iomaps[]
                i > length(iomaps) && return nothing
                child_sel = iomaps[i].output.selection
                child_sel === nothing && return nothing
                @reference ::SyntaxNode.children::CellVector[i].^(child_sel)
            end
            __ => nothing
        end
    end))

    # Step 4: ChildrenIoMap so the reader can find child IO maps
    ChildrenIoMap(p, node,
        SyntaxNode(..., out_children, ..., sel),
        child_iomaps)
end

# A property read of an IoMap unwraps its cell, so `iomap.child_iomaps` is the
# vector of the child IO maps. A `@reference` literal types each node it
# builds, and the spliced tail carries the types of the child.
function map_reference_forward(::MyNodeProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children[i].rest... => begin
            iomaps = iomap.child_iomaps
            i > length(iomaps) && return nothing
            child_iomap = iomaps[i]
            child_ref = map_reference_forward(child_iomap.projection, child_iomap, rest)
            child_ref === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[i].^(child_ref)
        end
    end
end

function map_reference_backward(::MyNodeProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children[i].rest... => begin
            iomaps = iomap.child_iomaps
            i > length(iomaps) && return nothing
            child_iomap = iomaps[i]
            child_ref = map_reference_backward(child_iomap.projection, child_iomap, rest)
            child_ref === nothing && return nothing
            @reference ::MyNode.children::CellVector[i].^(child_ref)
        end
    end
end
```

See [the tutorial](../../guide/new-domain-guide.md) for a complete worked
example with document types, example, and test.

## Recursion across projections

Whenever a node-shaped projection produces children, it recurses into each with

```julia
print_child(recursion, child, child_ctx)
```

where `child_ctx` extends the current context
(`make_child_context(ctx, <step to the child>)`). The helper expands to
`print_document(recursion, recursion, child, child_ctx)` — `recursion`
appears **twice** on purpose: the first slot is the projection to invoke, the
second is *that* call's own `recursion` argument. Both must be `recursion` (not
`p`, not `nothing`) so the child re-enters the whole pipeline — typically a
`RecursiveProjection` wrapping a `TypeDispatchingProjection` — rather than this
one projection. The node projection thus does not hard-code which inner
projections handle each child type. **Always recurse through
`print_child`** rather than open-coding the doubled argument: it
keeps the doubling in one place and call sites read as "recurse into this
child". Open-coding it and getting either slot wrong silently breaks
heterogeneous recursion: the child gets projected by the wrong projection, or
not recursively at all.

> **Principle: recurse as little as possible.** A projection should transform
> **only its own single level** and delegate every child to `recursion`, even
> when the child happens to be the same domain. Do *not* walk your input subtree
> yourself and flatten the whole thing into your output. Self-walking a subtree
> hard-codes which projection renders each descendant and forecloses **unforeseen
> combinations of documents and projections**: a child could be a different
> domain, or a substituted projection, and only single-level delegation lets the
> recursion follow whatever projection actually runs. Keeping each projection to
> one level is exactly what makes the library composable. This is one half of
> [the recursion contract](#the-recursion-contract); its other half is that you
> may not reach for a *new* recursive function to do the descent. The four
> functions are the only recursion the contract permits.

## Mapping references when the printer recurses

When `print_document` recurses into children, `map_reference_forward` and
`map_reference_backward` must recurse in lockstep. The path mapping has to
descend through exactly the structure the printer built. **The rule (call it
"School A"): peel only the one step this projection owns, then delegate the
remaining tail to the child projection's own mapper, reached through the stored
child IO maps.** A projection maps its *own* level and nothing below it.

```julia
function map_reference_forward(::MyNodeProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children[i] + rest => begin
            child = iomap.child_iomaps[][i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference children[i].^(inner))
        end
    end
end
```

The backward direction is the mirror image: peel the output step, look the child
up in the same `child_iomaps`, call its `map_reference_backward` on the tail, then
prepend the input-domain step that reaches it.

Delegating, rather than recursing over the input document directly, lets a node
projection **compose with any other domain in unforeseen ways**: its child
could be rendered by a projection from a different domain. Delegating through the
child IO map means the recursion follows whatever projection actually ran, so the
mapper can never drift from the printer and never assumes what kind of document a
child is. This is also why the printer must *store* its child IO maps (see
[§ A compound projection](#a-compound-node-shaped-projection)).

Every `*ToSyntax` node projection follows this rule: `JsonArrayToSyntaxNode` /
`JsonObjectToSyntaxNode`, `MathBinaryOperationToSyntaxNode` and its siblings,
`XmlElementToSyntaxNode`, and `BookBookToSyntaxNode` /
`BookChapterToSyntaxNode` / `BookListToSyntaxNode` — alongside `CopyingProjection`
and `SortingProjection`. Each peels the one step it owns
(`.elements[i] ↔ .children[i]`, `.left ↔ .children[1]`,
`.cell[i] ↔ .children[3].children[i]`, …) and delegates the tail. Two things stay
with the projection, because they are genuinely its own and have no child to
delegate to:

- **Projection-introduced output** — brackets, operators, the object key leaf, an
  XML element's tag and attributes — is mapped by an explicit structural rewrite
  the projection writes itself.
- **Structural positions with no input pre-image** are named by the projection's
  own introduced step, which holds their path in its output; the forward map
  answers that path.

When the child the printer recursed into went through a `CopyingProjection` (as
`JsonObjectToSyntaxNode`'s entries do), reach its stored child IO map with
`make_copying_field_iomap` / `make_copying_element_iomap` and delegate through that.

> **Anti-pattern — re-walking the input by type ("School B").** Do
> *not* implement the mapper by recursing over the input document and dispatching
> on each child's concrete type (`_forward(v::SomeNode, …)` calling
> `_forward(v.left, …)`). It duplicates every child's mapping logic, hard-codes
> which domains a child may be, and drifts from the printer the moment the inner
> pipeline changes. Whatever you write, the two
> directions must agree with each other *and* with how the printer wired the
> output selection.
>
> The same prohibition applies to the **printer**. Flattening a child subtree
> into your own output, walking `input`'s descendants yourself instead of calling
> `print_child(recursion, child, …)` and composing each `child_iomap.output`, is
> the printer-side School B. It forecloses composing any descendant with another
> projection, for the same reasons.

## Type dispatching

The standard idiom for handling a heterogeneous tree (e.g. JSON contains
strings, numbers, arrays, objects) is:

```julia
RecursiveProjection(TypeDispatchingProjection(
    JsonNull   => JsonNullToSyntaxLeaf(),
    JsonBool   => JsonBoolToSyntaxLeaf(),
    JsonNumber => JsonNumberToSyntaxLeaf(),
    JsonString => JsonStringToSyntaxLeaf(),
    JsonArray  => JsonArrayToSyntaxNode(),
    JsonObject => JsonObjectToSyntaxNode(),
))
```

Every multi-shape projection exposes a zero-arg factory that returns exactly
this shape: `JsonToSyntax()`, `XmlToSyntax()`, `WidgetToGraphics()`,
`PaneToWidget()`, `ObjectToSyntax()`.

## The screen pipeline

The multi-window root document is a `ScreenDocument` holding a list of
`WindowDocument`s (each with window metadata and a `content::Document`). Two
projections cooperate at the top of the pipeline, with one clear responsibility
each:

- **`ScreenToScreen`** (a domain projection over `ScreenDocument` /
  `WindowDocument`) owns all screen *structure*. Its printer copies the screen
  shell, copies each window's metadata verbatim, and recurses each window's
  `content` back through the pipeline with `print_child`,
  seeding the window's `width`/`height` as the available layout extent so
  layout-aware content sizes itself to the window. Its reader routes a
  `WindowInput` to the matching window by `window_id`, hands the inner event
  to that window's content reader, and prepends the `windows[i].content` steps
  to the operation that comes back. The window-content reference is
  `windows[i].content` (the i-th window is an `ElementReferenceStep`).
- **`WindowManagingProjection`** wraps `ScreenToScreen` (`inner = ScreenToScreen()`)
  and owns window-management *operations*: it intercepts
  `OpenWindowOperation` / `CloseWindowOperation` / resize bubbling up and applies
  them to both the input and the projected output.

`CopyingProjection` is deliberately **not** involved: it is generic and has no
reference to screens. Keeping the screen-structural concern in `ScreenToScreen`
and the operation-interception concern in `WindowManagingProjection` is why each
has a single reason to change.
