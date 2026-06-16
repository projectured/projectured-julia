# The Projection System

A **projection** is a bidirectional transformation between two domains. It is the
central abstraction of ProjecturEd: every screen the user sees, and every gesture
they make, flows through one or more projections.

A projection has four entry points:

```julia
projection_print(projection, recursion, input, context::PrinterContext) → iomap
projection_read(projection, recursion, change::Change, iomap)            → Change
map_reference_forward(projection, iomap, reference)                       → output_ref_or_nothing
map_reference_backward(projection, iomap, reference)                      → input_ref_or_nothing
```

The four functions come in two symmetric pairs, one per direction of data flow.
Forward, `projection_print` produces the output **and** wires the cursor by
calling `map_reference_forward`. Backward, `projection_read` consumes a
backward-flowing [`Change`](#the-change-the-reader-threads) (a gesture plus the
operation produced so far) **and** maps the cursor by calling
`map_reference_backward`.
The rule of thumb that follows from this symmetry — and that the rest of this
guide leans on — is:

> **`projection_print` uses `map_reference_forward`; `projection_read` uses
> `map_reference_backward`.** The two mappers are the single source of truth for
> how a path crosses the projection, written once and reused on both sides.

All four are generic functions declared in
[program/src/api/Projection.jl](../program/src/api/Projection.jl) and dispatched on
the concrete projection struct.

## The four functions

### `projection_print` — the printer

Forward transformation from the input domain to the output domain. Returns an
`IoMap` (subtype of `IoMap`, see [api/IoMap.jl](../program/src/api/IoMap.jl))
that records the input, the output, and any extra data the reader needs to
invert the transformation.

The two extra arguments are essential:

- **`recursion`** is the projection to call when descending into sub-documents
  (typically populated by `RecursiveProjection`, which passes *itself* so the
  inner projection can recurse through the whole pipeline). A leaf projection
  that never descends ignores it. A node projection threads it **twice** — as
  the projection to call *and* as that call's own `recursion` argument; see
  [§ Recursion across projections](#recursion-across-projections).
- **`context`** is a [`PrinterContext`](../program/src/context/PrinterContext.jl):
  a downward-flowing, extensible struct carrying the `reference` path from the
  editor's document root to the *current* input, plus optional layout extent
  (`available_width`/`available_height`) and an open `properties` Dict. Each
  projection extends the reference before recursing into a child by calling
  `child_context(ctx, step…)` (or `child_context(ctx, full_path)`), so every
  projection knows where in the original document it sits — which is what
  enables [ReferenceDispatchingProjection](higher-order-projections.md) to
  switch behaviour based on document-root-relative location. The top-level call
  passes a fresh `PrinterContext()` (whose reference is
  `EmptyReferencePath()`).

A two-argument convenience overload `projection_print(p, input)` is defined in
[common/Projection.jl](../program/src/common/Projection.jl) and supplies
`nothing` and a fresh `PrinterContext()`. The editor uses this.

**Wiring the selection.** The output document's `selection::Cell` is not a
parameter — it is computed reactively. The canonical form maps the input
selection forward through this projection's own mapper, so the path mapping is
defined in exactly one place:

```julia
output.selection = Cell(() -> map_reference_forward(p, iomap, input.selection))
```

For a node projection the `iomap` does not exist yet when the cell is built; use
the deferred-iomap trick (`iomap_cell = Cell(nothing)`; assign it after
constructing the IoMap — see `CopyingProjection`). A leaf whose input and
output selection formats are identical may instead *share* the same
`selection::Cell` on both sides (`getfield(input, :selection)`); that shortcut
is valid only leaf-to-leaf (see [§7 of the selection deep dive](selection-deep-dive.md)).

A compound projection that introduces *structural* output nodes with no input
counterpart (e.g. `WorkbenchToWidget`, whose shell inserts split panes around
the projected pages) wires those nodes' `selection` cells explicitly: it
forward-projects the workbench selection and re-roots it onto each split with a
small prefix strip. Once wired, those forward-projected selection cells let the
reader route events by selection — see below and
[the selection guide](editor/selection.md#forward-projecting-selection).

### The `Change` the reader threads

The reader's payload is a **`Change`** ([api/Projection.jl](../program/src/api/Projection.jl)) —
the backward-flowing dual of the document that flows forward through the printer:

```julia
struct Change
    gesture    # the originating device event (MousePress/KeyDown), threaded UNCHANGED
    operation  # the change in the current projection's input domain; starts nothing
end
```

- **`gesture`** is the raw thing the user did. It rides along **unchanged** the
  whole way up the chain, so any reader can inspect *what the user did*, not just
  what it currently means. (Example: `SyntaxToText`'s reader needs the raw click
  coordinates from the gesture to hit-test a mouse click back to a character
  offset, even though what eventually flows back is a selection move.)
- **`operation`** starts as `nothing` (a "nothing-change") and is filled in /
  re-mapped by each reader as the change travels one domain inward.

A reader returns a `Change`: either it keeps `operation === nothing` (it had
nothing to say) or it returns a fresh `Change` with the gesture preserved and a
real operation swapped in.

### `projection_read` — the reader

```julia
projection_read(projection, recursion, change::Change, iomap) → Change
```

The symmetric dual of `projection_print` — both take
`(projection, recursion, payload, context)`, where the payload is the `Change`
and the context is the printer's `iomap`. The reader turns an output-domain
change into an input-domain one and returns a `Change` (operation filled in /
re-mapped, gesture preserved), or a nothing-change if it has nothing to say.

The editor hands the raw device event to the **top-level** projection's
`projection_read`; routing from there is up to each projection. A
`SequentialProjection` forwards the change down its chain and threads the
operation that comes back up through each earlier step; a routing projection
instead dispatches it to the sub-projection of the relevant document part.

**Most projections need no `projection_read` method.** The default in
`ProjectionModule` re-targets any reference-carrying operation —
`ReplaceSelectionOperation`, `StringReplaceRangeOperation`,
`NumberReplaceRangeOperation` — by mapping its reference with
`map_reference_backward`. So a projection that only moves the cursor or edits a
value through a structure-preserving map needs **only** the two reference-mapping
functions. Write a `projection_read` method (the 4-arg `Change` form above) only
when you must do more than re-target a reference. The moves available, from the
lightest touch to the most involved:

- **Re-target the references.** Most often the incoming operation is the right
  *kind* and only its references need moving from output to input coordinates
  with `map_reference_backward` — rewrite the `.reference` of a
  `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`, or the `.path`
  of a `ReplaceSelectionOperation` (this is what the default already does for
  you), then rebuild the op.
- **Convert to a different operation.** It is perfectly valid to turn the
  incoming operation into a *completely different* one — retype it (e.g.
  `JsonNumberToSyntaxLeaf` turns a `StringReplaceRangeOperation` into a
  `NumberReplaceRangeOperation` so the evaluator re-parses the value), or
  replace it outright with whatever operation expresses the same intent in this
  projection's input domain.
- **Recurse, then extend.** When `projection_print` descended into children,
  mirror it: forward the event/operation to the matching child's
  `projection_read`, take the operation it returns, and extend it to this
  projection's context — typically by prepending the steps that reach the child
  (see [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)).
- **Probe a child to decide.** A reader may *speculatively* recurse into a
  document part's reader just to see what operation it would return, and use
  that answer to decide its own final operation — e.g. to choose among
  alternatives, or to act only when the child declines (returns `nothing`).
- **Route by selection.** When the printer forward-projected the selection onto
  this node (see [Wiring the selection](#projection_print--the-printer)), a
  reader can read its node's `selection` to forward a coordless event (a
  keystroke) *only* to the child the selection points at, rather than
  broadcasting to every child. This is the usual desired behavior — the
  keystroke goes where the cursor is. The widget split pane and tabbed pane do
  exactly this; see
  [the selection guide](editor/selection.md#selection-directed-event-routing).

Whichever moves it makes, a projection returns a `Change` carrying an operation
in its own input domain (or a nothing-change); the operation the **top-level**
projection ultimately returns is the final answer the editor applies to the
document.

> **Legacy 3-arg shim.** You may still see a 3-arg
> `projection_read(projection, iomap, event_or_op)` returning a bare operation.
> That form is **obsolete** — a transitional shim the generic bridge adapts to
> the 4-arg `Change` interface. Write the 4-arg `Change` form in new code.

### `map_reference_forward` / `map_reference_backward` — the reference maps

These translate a `ReferencePath` from input-domain coordinates to
output-domain coordinates and vice versa. Returning `nothing` means "this
reference has no image" — e.g. structural delimiters introduced by the
projection cannot map back to the input.

`ReplaceSelectionOperation` flowing up the pipeline is implemented entirely in
terms of these two functions, so getting them right gives you cursor
navigation across the entire pipeline for free.

The pattern-matching DSL `@reference_case` (see
[the reference guide](editor/reference.md)) makes these methods readable:

```julia
function map_reference_backward(::JsonBoolToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference value{k}
    end
end
```

Two principles keep these methods correct across the whole pipeline:

- **Recurse in lockstep with the printer.** If `projection_print` recursed into
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
  matched_input_prefix + ProjectionReference(projection, unmatched_output_suffix)
  ```

  The path then reads like a sentence — input steps say where in the document
  you are, and `ProjectionReference(projection, …)` marks the exact point where
  you cross into something that exists only in `projection`'s output. Because
  `map_reference_forward` strips that same step, the path round-trips cleanly.
  (When a projection's introduced positions are not separately addressable — the
  brackets and commas of a node, say — it is fine to collapse the whole group to a
  single flattened character offset `ProjectionReference(p, {flat})`, which
  `_syntax_to_flat` inverts; the `*ToSyntax` node readers use this for the
  delimiters they own. Use the fine-grained form when individual positions matter.)

## IoMap

`IoMap` is the abstract supertype of every map returned by `projection_print`.
Every IoMap has a `projection`, `input`, and `output` field. Common shapes:

| Type | Use case |
|---|---|
| `SimpleIoMap` | Projection with a strict positional contract; the reader can recover everything from the structure |
| `ChildrenIoMap` | Output has recursively projected children; a `child_iomaps::Cell` holds the per-child IoMaps |
| `ContentIoMap` | Wraps a single inner projection |
| `{Name}IoMap` | Specialised — each non-trivial projection defines its own |

`SequentialProjectionIoMap` stores `step_iomaps::Vector{Any}` so the reader can
walk the pipeline backward. `TextToGraphicsIoMap` carries a
`char_to_coord::Cell` so the reader can binary-search a click position back to
a character offset.

The `@iomap` macro (parallel to `@document`) generates an IoMap struct whose
`::Cell` fields are accessed transparently — see [the macros guide](macros.md).

## Projection categories

The **higher-order** and **generic** rows below are the complete sets — an
agent can treat them as exhaustive. The domain-to-domain and domain-preserving
rows are representative (every domain adds its own `*To*` projection).

| Category | Members | Purpose |
|---|---|---|
| **Domain-to-domain** | `JsonToSyntax`, `SyntaxToText`, `TextToGraphics`, `WidgetToGraphics`, `WorkbenchToWidget`, `XmlToSyntax`, `ObjectToSyntax`, `BookToSyntax`, `JuliaToSyntax`, `MathToSyntax`, `FileSystemToSyntax`, `TableToGraphics`, `PrimitiveToSyntax`, `CollectionToSyntax`, … | Translate between two distinct domains |
| **Domain-preserving** | `WordWrapping`, `LineNumbering`, `TextHighlighting`, `TextFiltering`, `GraphicsCaching`, `ScreenToScreen`, … | Same domain in and out (`ScreenToScreen` is the screen-domain projection — see [the screen pipeline](#the-screen-pipeline)) |
| **Generic (domain-independent)** | `CopyingProjection`, `SortingProjection`, `ReversingProjection`, `FilteringProjection`, `SearchingProjection`, `FocusingProjection`, `PreservingProjection`, `InvariablyProjection`, `ObjectToWidget` | Operate on any input domain *by structure, not by type* (the 9 in `generic/`). Most also preserve the domain; `ObjectToWidget` is input-independent but produces widgets |
| **Higher-order** | `SequentialProjection`, `TypeDispatchingProjection`, `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`, `RecursiveProjection`, `AlternativeProjection`, `NestingProjection`, `WindowManagerProjection`, `TooltipDecoratorProjection`, `ProjectionConfiguringProjection` | Compose other projections (the 10 in `higherorder/`) |
| **Compound** | `ApplyAtProjection`, `SortingAtProjection` | Convenience combinators built from higher-order primitives |

See [higher-order projections](higher-order-projections.md) and
[generic projections](generic-projections.md) for details.

## The forward and reverse paths

A typical pipeline looks like:

```
JsonString ──JsonStringToSyntaxLeaf──► SyntaxLeaf ──SyntaxLeafToText──► TextText ──TextToGraphics──► GraphicsCanvas ──► SDL window
   ▲  (selection shared)                                                                    │
   └─────────────────── projection_read chain ◄──── KeyPress / MouseClick ─────────────────┘
```

Forward, each step extends the `context`'s reference path (via
`child_context`) so child projections know their position relative to the
document root, and wires its output selection with `map_reference_forward`.
Backward, each step's IoMap is visited in reverse, with each projection's
`projection_read` translating the operation a step closer to the document's
domain (via `map_reference_backward`).

## Writing a custom projection

1. Define a struct that subtypes `Projection`. Use `@projection` if you have
   reactive Cell fields.
2. Implement `projection_print(p, recursion, input, ctx)` returning an
   `IoMap`. Use `SimpleIoMap` for positional projections, or define your own
   IoMap struct (with `<: IoMap`) when you need to carry extra data.
3. Implement `map_reference_forward` and `map_reference_backward` — usually
   the cleanest way is `@reference_case`. `projection_print` wires its output
   selection by calling `map_reference_forward`; the default `projection_read`
   handles selection by calling `map_reference_backward`. Write the pair once
   and both directions work.
4. If your projection needs to do more than re-target a reference (e.g. mouse
   scroll, type-to-edit, retyping an operation), add a 4-arg
   `projection_read(p, recursion, change::Change, iomap)` method that returns a
   `Change` carrying the corresponding domain operation. Selection moves and
   structure-preserving edits need no method — the default handles them.

```julia
struct MyProjection <: Projection end

function projection_print(p::MyProjection, recursion, input, ctx)
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

### A compound (node-shaped) projection

A leaf projection maps one document value to one output value. A compound
projection maps one input *node* to an output node whose children are the
recursively-projected input children. The extra requirements are:

1. **Recurse into each child** with `projection_printer_recurse(recursion, child, child_ctx)`
   (see [§ Recursion across projections](#recursion-across-projections)).
2. **Store the child IO maps** in a shared reactive `Cell` (not inline in two
   separate cells — see [§8 of the selection deep dive](selection-deep-dive.md)).
3. **Project the selection reactively.** Canonically this is
   `Cell(() -> map_reference_forward(p, iomap, node.selection))` with the
   deferred-iomap trick for the not-yet-built `iomap`. The inline form shown
   below reads the child IO maps directly; it is equivalent when the mapper
   would perform the same walk.
4. **Use `ChildrenIoMap`** rather than `SimpleIoMap` so the reader and the
   reference maps can locate the correct child IO map when translating
   backward (see [§ Mapping references when the printer recurses](#mapping-references-when-the-printer-recurses)).

```julia
struct MyNodeProjection <: Projection end

function projection_print(p::MyNodeProjection, recursion, node::MyNode, ctx)
    # Step 1+2: project children, store IO maps in a shared cell.
    # `projection_printer_recurse` re-enters the whole pipeline for each child;
    # `child_context` extends the reference path to child i.
    child_iomaps = Cell(() -> [
        projection_printer_recurse(recursion,
                                   getfield(node, :children)[][i][],
                                   child_context(ctx, ElementReference(i)))
        for i in 1:length(node.children)
    ])

    # Build the output children from the IO maps
    out_children = Cell(() -> CellVector(Cell[Cell(m.output) for m in child_iomaps[]]))

    # Step 3: project the selection reactively
    sel = Cell(() -> begin
        path = node.selection
        @reference_case path begin
            children[i] + rest => begin
                iomaps = child_iomaps[]
                i > length(iomaps) && return nothing
                child_sel = iomaps[i].output.selection
                child_sel === nothing && return nothing
                ConcreteReferencePath(ElementReference(Cell(i)), child_sel)
            end
            _ => nothing
        end
    end)

    # Step 4: ChildrenIoMap so the reader can find child IO maps
    ChildrenIoMap(p, node,
        SyntaxNode(..., out_children, ..., sel),
        child_iomaps)
end

function map_reference_forward(::MyNodeProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children[i] + rest => begin
            iomaps = iomap.child_iomaps[]
            i > length(iomaps) && return nothing
            child_iomap = iomaps[i]
            child_ref = map_reference_forward(child_iomap.projection, child_iomap, rest)
            child_ref === nothing && return nothing
            ConcreteReferencePath(ElementReference(Cell(i)), child_ref)
        end
    end
end

function map_reference_backward(::MyNodeProjection, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        [i] + rest => begin
            iomaps = iomap.child_iomaps[]
            i > length(iomaps) && return nothing
            child_iomap = iomaps[i]
            child_ref = map_reference_backward(child_iomap.projection, child_iomap, rest)
            child_ref === nothing && return nothing
            ConcreteReferencePath(FieldReference(Cell("children")),
                ConcreteReferencePath(ElementReference(i), child_ref))
        end
    end
end
```

See [the tutorial](tutorial-new-domain.md) for a complete worked
example with document types, example, and test.

## Recursion across projections

Whenever a node-shaped projection produces children, it recurses into each with

```julia
projection_printer_recurse(recursion, child, child_ctx)
```

where `child_ctx` extends the current context
(`child_context(ctx, <step to the child>)`). The helper expands to
`projection_print(recursion, recursion, child, child_ctx)` — `recursion`
appears **twice** on purpose: the first slot is the projection to invoke, the
second is *that* call's own `recursion` argument. Both must be `recursion` (not
`p`, not `nothing`) so the child re-enters the whole pipeline — typically a
`RecursiveProjection` wrapping a `TypeDispatchingProjection` — rather than this
one projection. The node projection thus does not hard-code which inner
projections handle each child type. **Always recurse through
`projection_printer_recurse`** rather than open-coding the doubled argument: it
keeps the doubling in one place and call sites read as "recurse into this
child". (Open-coding it and getting either slot wrong silently breaks
heterogeneous recursion — the child gets projected by the wrong projection, or
not recursively at all.)

## Mapping references when the printer recurses

When `projection_print` recurses into children, `map_reference_forward` and
`map_reference_backward` must recurse in lockstep — the path mapping has to
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

Why delegate rather than recurse over the input document yourself? Because a node
projection must **compose with any other domain in unforeseen ways** — its child
could be rendered by a projection from a different domain. Delegating through the
child IO map means the recursion follows whatever projection actually ran, so the
mapper can never drift from the printer and never assumes what kind of document a
child is. (This is also why the printer must *store* its child IO maps —
[§ A compound projection](#a-compound-node-shaped-projection).)

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
- **Structural positions with no input pre-image** collapse to a flat offset
  (`ProjectionReference(p, {flat})`, inverted by `_syntax_to_flat`).

When the child the printer recursed into went through a `CopyingProjection` (as
`JsonObjectToSyntaxNode`'s entries do), reach its stored child IO map with
`copying_field_iomap` / `copying_element_iomap` and delegate through that.

> **Anti-pattern — re-walking the input by type (the former "School B").** Do
> *not* implement the mapper by recursing over the input document and dispatching
> on each child's concrete type (`_forward(v::SomeNode, …)` calling
> `_forward(v.left, …)`). It duplicates every child's mapping logic, hard-codes
> which domains a child may be, and drifts from the printer the moment the inner
> pipeline changes. The codebase used to do this (`_forward_json_path`,
> `_forward_math_path`, `_translate_xml_path`, `_forward_book_path`, …); all of it
> was deleted in favour of the delegation rule above. Whatever you write, the two
> directions must agree with each other *and* with how the printer wired the
> output selection.

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

`JsonToSyntax()`, `XmlToSyntax()`, `WidgetToGraphics()`,
`WorkbenchToWidget()`, `ObjectToSyntax()` — every multi-shape projection
exposes a zero-arg factory that returns exactly this shape.

## The screen pipeline

The multi-window root document is a `ScreenDocument` holding a list of
`WindowDocument`s (each with window metadata and a `content::Document`). Two
projections cooperate at the top of the pipeline, with one clear responsibility
each:

- **`ScreenToScreen`** (a domain projection over `ScreenDocument` /
  `WindowDocument`) owns all screen *structure*. Its printer copies the screen
  shell, copies each window's metadata verbatim, and recurses each window's
  `content` back through the pipeline with `projection_printer_recurse` —
  seeding the window's `width`/`height` as the available layout extent so
  layout-aware content sizes itself to the window. Its reader routes an
  `EventEnvelope` to the matching window by `window_id`, hands the inner event
  to that window's content reader, and prepends the `windows[i].content` steps
  to the operation that comes back. The window-content reference is
  `windows[i].content` (the i-th window is an `ElementReference`).
- **`WindowManagerProjection`** wraps `ScreenToScreen` (`inner = ScreenToScreen()`)
  and owns window-management *operations* — it intercepts
  `OpenWindowOperation` / `CloseWindowOperation` / resize bubbling up and applies
  them to both the input and the projected output.

`CopyingProjection` is deliberately **not** involved: it is generic and knows
nothing about screens. Keeping the screen-structural concern in `ScreenToScreen`
and the operation-interception concern in `WindowManagerProjection` is why each
has a single reason to change.
