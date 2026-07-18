# Higher-Order Projections

Higher-order projections compose other projections. Each one lives in its own
module under its package's projection folder (the generic combinators in
`package/kernel/main/projection/higherorder/`, the document-shaped ones in
`package/base/main/projection/`) and implements
`print_document`, `read_intent`, and the two reference-mapping
functions. They never touch any specific domain — their argument is always
some other projection.

There are twelve higher-order projections in ProjecturEd:

| Projection | Selects by | Key file |
|---|---|---|
| `ChainingProjection` | order in a list | `Sequential.jl` |
| `TypeDispatchingProjection` | `typeof(input)` | `TypeDispatching.jl` |
| `PredicateDispatchingProjection` | `pred(input)` | `PredicateDispatching.jl` |
| `ReferenceDispatchingProjection` | the `reference` argument | `ReferenceDispatching.jl` |
| `RecursiveProjection` | identity — wraps a child and supplies *itself* as `recursion` | `Recursive.jl` |
| `SwitchingProjection` | a reactive `Cell{Int}` index | `Alternative.jl` |
| `NestingProjection` | nests by element list, with recursion fallback | `Nesting.jl` |
| `WindowManagingProjection` | passthrough printer; reader applies `OpenWindowOperation`/`CloseWindowOperation` to the `ScreenDocument` | `WindowManager.jl` |
| `WindowInputUnwrappingProjection` | passthrough printer; reader strips the `WindowInput` off the gesture for pipelines with no screen/window layer | `WindowInputUnwrapping.jl` |
| `TooltipDecoratorProjection` | dispatches on `TooltipSource`; reader runs a show/hide state machine | `TooltipDecorator.jl` |
| `DraggingProjection` | dispatches on `DraggingState`; reader runs a press→drag→drop state machine emitting `MoveRangeOperation` | `Dragging.jl` |
| `ProjectionConfiguringProjection` | extends the inner projection's output with an editable parameter-control bar | `ProjectionConfiguring.jl` |

## ChainingProjection

Pipelines projections left-to-right for the printer and right-to-left for the
reader.

```julia
ChainingProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = ...),
)
```

`print_document` threads the previous step's `iomap.output` as the next
step's input and stores every step's iomap in `ChainingProjectionIoMap.step_iomaps`.
`read_intent` walks from the *last* step backward. If a step returns
`nothing`, the reader keeps trying earlier steps until one accepts the event,
then translates the result through the remaining earlier steps. This is what
lets a `:left`/`:right` key be consumed by `TextToGraphics` and translated
back through `SyntaxToText` and `JsonToSyntax` into a JSON-domain
`ReplaceSelectionOperation`.

## TypeDispatchingProjection

```julia
TypeDispatchingProjection(
    JsonNull   => JsonNullToSyntaxLeaf(),
    JsonString => JsonStringToSyntaxLeaf(),
    JsonArray  => JsonArrayToSyntaxNode(),
    ...
)
```

Tries each `(Type, projection)` pair in order; the first `input isa T`
wins. It's a transparent wrapper — the IoMap returned is the *inner*
projection's IoMap, not a wrapping one. Use this whenever you need to
project a heterogeneous tree (JSON, XML, widgets, …). Pairs are tried in
declaration order, so put specific types before general fallbacks
(`Any => …` at the end).

## PredicateDispatchingProjection

Same shape as `TypeDispatchingProjection`, but each key is a predicate
function `input -> Bool` instead of a type. Use it when type alone is not
discriminating enough — for example dispatching on a `kind::Symbol` field
inside a struct.

## ReferenceDispatchingProjection

Dispatches on the `reference` argument (the path from the document root to
the current input). Two construction forms:

```julia
# Structural-equality form
ReferenceDispatchingProjection(
    default,
    @reference(entries) => SortingProjection(by = e -> e.key),
)

# Function form — handles wildcards and prefixes via @reference_case
ReferenceDispatchingProjection(ref -> @reference_case ref begin
    prefix(entries) => CopyingProjection()
    entries         => SortingProjection(by = e -> e.key)
    _               => IdentityProjection()
end)
```

This is the mechanism by which a single projection can selectively apply a
transformation to one part of a document and leave everything else alone.
The compound projection `ApplyAtProjection` (see below) is built on top.

## RecursiveProjection

```julia
RecursiveProjection(TypeDispatchingProjection(
    JsonArray => JsonArrayToSyntaxNode(),
    ...
))
```

Calls `print_document(child, self, input, ctx)` — that is, it passes
*itself* as the `recursion` argument. (The 4th argument is a
`PrinterContext` that *carries* the document-root-relative reference path
plus layout extent and properties; it was historically a bare
`Reference`, since promoted to the context struct.) This lets node-shaped
inner projections recurse with `print_child(recursion, child, child_ctx)`
without hard-coding the inner pipeline. Every multi-shape domain projection
(JsonToSyntax, XmlToSyntax, ObjectToSyntax, WidgetToGraphics, …) wraps a
TypeDispatchingProjection in a RecursiveProjection.

The reason node projections take `recursion` instead of calling a fixed inner
projection is precisely to keep each projection **single-level and composable**:
a projection renders one level and delegates children, so any subtree can be
swapped for — or composed with — another projection. A projection that recurses
over its own subtree instead would foreclose that. `recursion` is the printer's
half of [the recursion contract](projection-system.md#the-recursion-contract):
descent rides the four core functions and never a fifth one (see also the recursion
principle in [projection-system.md](projection-system.md#recursion-across-projections)).

## SwitchingProjection

```julia
index = Cell(1)
ap    = SwitchingProjection([JsonToSyntax(), XmlToSyntax()], index)
# later:
ap.index[] = 2   # next print uses XmlToSyntax
```

Holds a list of projections and a `Cell{Int}` that selects which one is
active. The IoMap records the index used at print time so the reader
always routes events to the branch that produced the output. Use it for
mode-switching, e.g. between view-mode and edit-mode rendering.

## NestingProjection

```julia
NestingProjection(outer, inner; recursion = IdentityProjection())
```

Applies the first element to the input, passing a new `NestingProjection`
built from the remaining elements as the `recursion` argument. The outer
projection thus controls the surface structure and delegates inner
content to the rest of the list. When elements run out, it falls back to a
recursion.

**Recursion precedence (load-bearing for `ApplyAtProjection`).** A
`NestingProjection` carries both a *stored* `recursion` (the keyword argument)
and the *inherited* `recursion` passed in at print time. The **stored one wins**;
the inherited one is used only when none is stored
(`effective = stored !== nothing ? stored : inherited`). This is exactly how
`ApplyAtProjection(reference, projection)` preserves the target subtree's
contents: it builds `NestingProjection(projection; recursion = IdentityProjection())`,
so once `projection` has run at the target, everything below is handed to the
stored `IdentityProjection` rather than continuing down the outer pipeline.

## DraggingProjection

```julia
DraggingProjection()   # dispatched on a DraggingState document
```

Adds drag-and-drop reordering to whatever document a `DraggingState` wraps. Like
`TooltipDecoratorProjection`, it is a **transparent decorator**: `print_document`
just recurses into `state.content` and returns its output, so the wrapper is
invisible. All the work is in the reader, a press→drag→drop state machine whose
transient state (`:idle` / `:pending` / `:dragging` + grab coords + source
reference) lives on the projection instance — one drag at a time, never
serialised.

**Resolving the grab and drop points.** Mouse events are pixel coordinates; they
only become document references at the graphics layer, and only for `MousePress`
(a real drag fires `MouseDown` → `MouseMove*` → `MouseUp`, with no synthesised
`MousePress`). Rather than teach every graphics reader to hit-test `MouseUp`,
`DraggingProjection` resolves both endpoints itself:

> on the grabbing `MouseDown` and the dropping `MouseUp`, it **synthesises a left
> `MousePress` at that pixel and delegates it to the inner chain** — the exact
> path a real click takes down through the graphics layer to the content domain.
> The returned `ReplaceSelectionOperation`'s path is the reference under the
> point.

The synthetic press is only *read*, never applied, so it is a side-effect-free
query (a drop onto, say, a collapse marker yields a `ToggleCollapseOperation`,
which the projection ignores → no move, no toggle). This needs **zero changes
outside `Dragging.jl`** and works for any domain whose graphics reader already
hit-tests `MousePress`.

**The move.** A completed drag emits a `MoveRangeOperation` (see
[operations.md](operation.md)). The reader resolves each reference to a
`(CellVector, index)` pair (splitting the path at its last element
`RangeReferenceStep`; the prefix resolves to the owning collection) and stores the
`CellVector`s **directly** in the operation — like the split-pane operations
carry the `WidgetSplitPane` itself, which sidesteps re-rooting the reference up
through the projections above. `evaluate_operation` then lifts the raw `Cell`s
out of the source and `insert!`s them at the destination, preserving cell
identity.

## Compound combinators

[projection/HigherOrderCompound.jl](../../../package/base/main/projection/HigherOrderCompound.jl)
defines `ApplyAtProjection`, the most useful combinator built on top:

```julia
ApplyAtProjection(@reference(entries), SortingProjection(by = e -> e.key))
```

Reads as "apply `SortingProjection` exactly at the path
`entries`, copy the spine from the root to that path, and preserve
everything below." Internally it expands to:

```julia
RecursiveProjection(ReferenceDispatchingProjection(ref -> @reference_case ref begin
    prefix(^(reference)) => CopyingProjection()
    ^(reference)         => NestingProjection(projection; recursion = IdentityProjection())
    _                    => IdentityProjection()
end))
```

`SortingAtProjection(@reference(entries), key_fn)` is a convenience for the
common case of sorting.

## Choosing between dispatchers

| You want to switch on… | Use |
|---|---|
| The Julia type of the input | `TypeDispatchingProjection` |
| A predicate over the input | `PredicateDispatchingProjection` |
| The location of the input in the document | `ReferenceDispatchingProjection` |
| A reactive flag that changes at runtime | `SwitchingProjection` |
| The shape of a recursive call | `RecursiveProjection` |
| A "do X at path P, preserve elsewhere" pattern | `ApplyAtProjection` |

All of these compose freely with `ChainingProjection`.
