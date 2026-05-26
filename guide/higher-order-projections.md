# Higher-Order Projections

Higher-order projections compose other projections. Each one lives in its own
module under `program/src/projection/higherorder/` and implements
`projection_print`, `projection_read`, and the two reference-mapping
functions. They never touch any specific domain — their argument is always
some other projection.

There are seven higher-order projections in ProjecturEd:

| Projection | Selects by | Key file |
|---|---|---|
| `SequentialProjection` | order in a list | `Sequential.jl` |
| `TypeDispatchingProjection` | `typeof(input)` | `TypeDispatching.jl` |
| `PredicateDispatchingProjection` | `pred(input)` | `PredicateDispatching.jl` |
| `ReferenceDispatchingProjection` | the `reference` argument | `ReferenceDispatching.jl` |
| `RecursiveProjection` | identity — wraps a child and supplies *itself* as `recursion` | `Recursive.jl` |
| `AlternativeProjection` | a reactive `Cell{Int}` index | `Alternative.jl` |
| `NestingProjection` | nests by element list, with recursion fallback | `Nesting.jl` |

## SequentialProjection

Pipelines projections left-to-right for the printer and right-to-left for the
reader.

```julia
SequentialProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = ...),
)
```

`projection_print` threads the previous step's `iomap.output` as the next
step's input and stores every step's iomap in `SequentialProjectionIoMap.step_iomaps`.
`projection_read` walks from the *last* step backward. If a step returns
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
    _               => PreservingProjection()
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

Calls `projection_print(child, input, self, reference)` — that is, it
passes *itself* as the `recursion` argument. This lets node-shaped inner
projections call `projection_print(recursion, child, recursion, child_ref)`
to recurse without hard-coding the inner pipeline. Every multi-shape
domain projection (JsonToSyntax, XmlToSyntax, ObjectToSyntax,
WidgetToGraphics, …) wraps a TypeDispatchingProjection in a
RecursiveProjection.

## AlternativeProjection

```julia
index = Cell(1)
ap    = AlternativeProjection([JsonToSyntax(), XmlToSyntax()], index)
# later:
ap.index[] = 2   # next print uses XmlToSyntax
```

Holds a list of projections and a `Cell{Int}` that selects which one is
active. The IoMap records the index used at print time so the reader
always routes events to the branch that produced the output. Use it for
mode-switching, e.g. between view-mode and edit-mode rendering.

## NestingProjection

```julia
NestingProjection(outer, inner; recursion = PreservingProjection())
```

Applies the first element to the input, passing a new `NestingProjection`
built from the remaining elements as the `recursion` argument. The outer
projection thus controls the surface structure and delegates inner
content to the rest of the list. When elements run out, falls back to the
optional stored `recursion`. This is the mechanism used inside
`ApplyAtProjection` to insert a target projection at a specific
reference path while preserving the rest of the document.

## Compound combinators

[compound/HigherOrder.jl](../program/src/projection/compound/HigherOrder.jl)
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
    ^(reference)         => NestingProjection(projection; recursion = PreservingProjection())
    _                    => PreservingProjection()
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
| A reactive flag that changes at runtime | `AlternativeProjection` |
| The shape of a recursive call | `RecursiveProjection` |
| A "do X at path P, preserve elsewhere" pattern | `ApplyAtProjection` |

All five dispatchers compose freely with `SequentialProjection`.
