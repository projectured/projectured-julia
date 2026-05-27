# The Projection System

A **projection** is a bidirectional transformation between two domains. It is the
central abstraction of ProjecturEd: every screen the user sees, and every gesture
they make, flows through one or more projections.

A projection has four entry points:

```julia
projection_print(projection, input, recursion, reference) → iomap
projection_read(projection, iomap, event_or_op)           → op_or_nothing
map_reference_forward(projection, iomap, reference)       → output_ref_or_nothing
map_reference_backward(projection, iomap, reference)      → input_ref_or_nothing
```

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
  inner projection can recurse through the whole pipeline). When you are not
  recursing, pass `nothing`.
- **`reference`** is the `ReferencePath` from the editor's document root to the
  *current* input. Each projection extends this path before recursing into a
  child, so every projection knows where in the original document it sits.
  The top-level call passes `EmptyReferencePath()`. This is what enables
  [ReferenceDispatchingProjection](higher-order-projections.md) to switch
  behaviour based on document-root-relative location.

A two-argument convenience overload `projection_print(p, input)` is defined in
[common/Projection.jl](../program/src/common/Projection.jl) and supplies
`nothing` and `EmptyReferencePath()`. The editor uses this.

### `projection_read` — the reader

Takes an event from the output domain (key press, mouse click, or an `Operation`
produced by a downstream projection) and returns an `Operation` in the input
domain — or `nothing` if this projection has nothing to say about the event.
The last projection in a pipeline receives raw device events; every earlier
projection receives the operation produced by its downstream neighbour.

The default `projection_read` (in `ProjectionModule`) handles
`ReplaceSelectionOperation` by calling `map_reference_backward` on the path —
so for most simple projections, only the two reference-mapping functions need
methods.

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

| Category | Examples | Purpose |
|---|---|---|
| **Domain-to-domain** | `JsonToSyntax`, `SyntaxToText`, `TextToGraphics`, `WidgetToGraphics`, `WorkbenchToWidget`, `XmlToSyntax`, `ObjectToSyntax`, `BookToSyntax`, `JuliaToSyntax`, `MathToSyntax`, `FileSystemToSyntax`, `TableToGraphics`, `PrimitiveToSyntax`, `CollectionToSyntax` | Translate between two distinct domains |
| **Domain-preserving** | `WordWrapping`, `LineNumbering` | Same domain in and out |
| **Domain-independent** | `CopyingProjection`, `SortingProjection`, `ReversingProjection`, `FocusingProjection`, `PreservingProjection`, `InvariablyProjection` | Work on any domain |
| **Higher-order** | `SequentialProjection`, `TypeDispatchingProjection`, `RecursiveProjection`, `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`, `AlternativeProjection`, `NestingProjection` | Compose other projections |
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

Forward each step extends a `reference` argument so child projections know
their position relative to the document root. Backward each step's IoMap is
visited in reverse, with each projection's `projection_read` translating the
operation a step closer to the document's domain.

## Writing a custom projection

1. Define a struct that subtypes `Projection`. Use `@projection` if you have
   reactive Cell fields.
2. Implement `projection_print(p, input, recursion, reference)` returning an
   `IoMap`. Use `SimpleIoMap` for positional projections, or define your own
   IoMap struct (with `<: IoMap`) when you need to carry extra data.
3. Implement `map_reference_forward` and `map_reference_backward` — usually
   the cleanest way is `@reference_case`. The default `projection_read`
   will then handle selection.
4. If your projection needs to respond to events other than selection moves
   (e.g. mouse scroll, type-to-edit), add a method to `projection_read`
   that returns the corresponding domain operation.

```julia
struct MyProjection <: Projection end

function projection_print(p::MyProjection, input, recursion, reference)
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

1. **Call `projection_print` on each child** via the `recursion` argument.
2. **Store the child IO maps** in a shared reactive `Cell` (not inline in two
   separate cells — see [§8 of the selection deep dive](selection-deep-dive.md)).
3. **Project the selection reactively** using the child IO maps.
4. **Use `ChildrenIoMap`** rather than `SimpleIoMap` so the reader can locate
   the correct child IO map when translating a selection backward.

```julia
struct MyNodeProjection <: Projection end

function projection_print(p::MyNodeProjection, node::MyNode, recursion, reference)
    # Step 1+2: project children, store IO maps in a shared cell
    child_iomaps = Cell(() -> [
        projection_print(recursion, getfield(node, :children)[][i][],
                         recursion,
                         append_reference(reference, ElementReference(Cell(i))))
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
                ConcreteReferencePath(ElementReference(Cell(i)), child_ref))
        end
    end
end
```

See [the tutorial](tutorial-new-domain.md) for a complete worked
example with document types, example, and test.

## Recursion across projections

Whenever a node-shaped projection produces children, it should call
`projection_print(recursion, child, recursion, child_ref)` where `child_ref`
extends the current reference (`append_reference(reference, ...)`). This
delegates back to whatever higher-order projection — typically `RecursiveProjection`
wrapping a `TypeDispatchingProjection` — is driving the traversal. The
node projection thus does not hard-code which inner projections handle each
child type.

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
