# Higher-Order Projections

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md)

Higher-order projections compose other projections. Each one lives in its own
module under its package's projection folder: the nine domain-independent
combinators in `source/platform/projection/higherorder/`, and four decorators beside the
domain each one touches — `source/platform/screen/`, `source/platform/tooltip/`,
`source/platform/dragging/`, `source/platform/widget/`. Each implements
`print_document`, `read_intent`, and the two reference-mapping
functions. Most never touch any specific domain — their argument is always
some other projection.

There are thirteen higher-order projections in ProjecturEd:

| Projection | Selects by | Key file |
|---|---|---|
| `ChainingProjection` | order in a list | `Chaining.jl` |
| `TypeDispatchingProjection` | `typeof(input)` | `TypeDispatching.jl` |
| `PredicateDispatchingProjection` | `pred(input)` | `PredicateDispatching.jl` |
| `ReferenceDispatchingProjection` | the `reference` argument | `ReferenceDispatching.jl` |
| `RecursiveProjection` | identity — wraps a child and supplies *itself* as `recursion` | `Recursive.jl` |
| `SwitchingProjection` | a reactive `Cell{Int}` index | `Switching.jl` |
| `NestingProjection` | nests by element list, with recursion fallback | `Nesting.jl` |
| `WindowManagingProjection` | passthrough printer; reader applies `OpenWindowOperation`/`CloseWindowOperation` to the `ScreenDocument` | `WindowManaging.jl` |
| `WindowInputUnwrappingProjection` | passthrough printer; reader strips the `WindowInput` off the gesture for pipelines with no screen/window layer | `WindowInputUnwrapping.jl` |
| `FaultCatchingProjection` | passthrough printer for one part; a fault in a cell that the part built draws the `substitute` mark of the output domain in place of the part | `FaultCatching.jl` |
| `TooltipDecoratorProjection` | dispatches on `TooltipSource`; reader runs a show/hide state machine | `TooltipDecorator.jl` |
| `DraggingProjection` | dispatches on `DraggingState`; reader runs a press→drag→drop state machine emitting `MoveRangeOperation` | `Dragging.jl` |

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
step's input and stores every step's iomap in `ChainingIoMap.step_iomaps`.
`read_intent` walks from the *last* step backward. If a step returns
`nothing`, the reader keeps trying earlier steps until one accepts the event,
then translates the result through the remaining earlier steps. This is what
lets a `:left`/`:right` key be consumed by `TextToGraphics` and translated
back through `SyntaxToText` and `JsonToSyntax` into a JSON-domain
`ReplaceSelectionOperation`.

A claim that no earlier step can carry is no claim. If a step can not
translate the result of a later step, that step and the steps before it read
the raw event, as if no later step had answered it. `TextToGraphics` makes a
character insert of a `,` on the closing quote of a JSON string. `JsonToSyntax`
can not carry an edit of a delimiter, so it reads the `,` itself and inserts the
next entry. A key that some step carries, such as a `,` inside the string, is
not changed.

**A change with a route.** The chain maps the route forward, stage by stage, as
the printer maps a reference. An operation keeps to the stages that print the
place as the same document, and the last of them reads it. A gesture goes on as
far as the forward maps answer, also into a stage that shows the place as
something else: a widget that a view makes for a part of its input, or for a
place that the view names with an introduced reference. The deepest stage reads
the gesture first, and an earlier stage reads it when the later answers nothing,
as for a gesture with no route. So a dwell that a command sends to a file by
route, to show its tooltip, reaches the row of the tree that shows the file.

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
wins. It is a transparent wrapper — the IoMap returned is the *inner*
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

# Function form — handles wildcards and ancestors via @reference_case
ReferenceDispatchingProjection(ref -> @reference_case ref begin
    above(entries)  => CopyingProjection()
    entries         => SortingProjection(by = e -> e.key)
    __              => IdentityProjection()
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
*itself* as the `recursion` argument. The 4th argument is a
`PrinterContext` that *carries* the document-root-relative reference path
plus layout extent and properties. This lets node-shaped
inner projections recurse with `print_child(recursion, child, child_ctx)`
without hard-coding the inner pipeline. Every multi-shape domain projection
(JsonToSyntax, XmlToSyntax, ObjectToSyntax, WidgetToGraphics, …) wraps a
TypeDispatchingProjection in a RecursiveProjection.

The reason node projections take `recursion` instead of calling a fixed inner
projection is precisely to keep each projection **single-level and composable**:
a projection renders one level and delegates children, so any subtree can be
swapped for, or composed with, another projection. A projection that recurses
over its own subtree instead would foreclose that. `recursion` is the printer's
half of [the recursion contract](../../kernel/projection-system.md#the-recursion-contract):
descent rides the four core functions and never a fifth one (see also the recursion
principle in [projection-system.md](../../kernel/projection-system.md#recursion-across-projections)).

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
DraggingProjection()   # dispatched on a DraggingState document, and holds no field of its own
```

Adds drag-and-drop reordering to whatever document a `DraggingState` wraps. Like
`TooltipDecoratorProjection`, it is a **transparent decorator**: `print_document`
just recurses into `state.content` and returns its output, so the wrapper is
invisible. The state of the press is a field of the document, not of the
projection: `DraggingState.press` holds `(x, y, source, started)` or `nothing`,
written with `ReplaceViewStateOperation`, so a history does not record it and
the field survives a new print.

**Resolving the grab and the drop.** A left `MouseDown` with no press yet keeps
one: `source` is the path that the mouse target of the content names at the
press, or the selection when the content names no target. A move past
`threshold` pixels starts the drag: the state answers
`StartDragOperation(EmptyReference(), press.source)`, so the code that tracks a
drag ([dragtracking.md](../dragtracking/dragtracking.md)) sends `DragEnd` and
`DragCancel` to the state by its own path from then on, wherever the pointer
is. Every other event, the moves included, still goes on to the content, so
the mouse target of the content follows the pointer also during a drag;
`DragEnd` reads the drop at that same mouse target, at the release, with no
event made for the purpose.

**The move.** `DragEnd` makes a `MoveRangeOperation` (see
[operation.md](../../kernel/operation.md)) from
`find_drop_zone(state::DraggingState, dragged, point)`, which resolves the
source and the drop point to `(CellVector, index)` pairs (splitting each path
at its last element `RangeReferenceStep`; the prefix resolves to the owning
collection) and stores the `CellVector`s **directly** in the operation, the way
the split-pane operations carry the `WidgetSplitPane` itself. This sidesteps
re-rooting the reference up through the projections above. `evaluate_operation`
then lifts the raw `Cell`s out of the source and `insert!`s them at the
destination, preserving cell identity. `DragCancel` clears the press and moves
nothing.

## FaultCatchingProjection

A barrier at a recursion point: `RecursiveProjection(FaultCatchingProjection(inner
= SyntaxToText(), substitute = FaultToText()))`. Each call of its printer makes the
IoMap of one part and prints the part in a fault scope, so a fault in any cell
that the part built goes to that IoMap, whatever reader reached the cell. The
editor then draws the `substitute` mark in place of the part. While the part
prints, the IoMap of the barrier adds nothing to it. The whole design is in
[fault.md](../fault/fault.md).

## Compound combinators

[projection/HigherOrderCompound.jl](../../../../source/platform/projection/compound/HigherOrderCompound.jl)
defines `ApplyAtProjection`, the most useful combinator built on top:

```julia
ApplyAtProjection(@reference(entries), SortingProjection(by = e -> e.key))
```

Reads as "apply `SortingProjection` exactly at the path
`entries`, copy the spine from the root to that path, and preserve
everything below." Internally it expands to:

```julia
RecursiveProjection(ReferenceDispatchingProjection(ref -> @reference_case ref begin
    above(^(reference)) => CopyingProjection()
    ^(reference)        => NestingProjection(projection; recursion = IdentityProjection())
    __                  => IdentityProjection()
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
