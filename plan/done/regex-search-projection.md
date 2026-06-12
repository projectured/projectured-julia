# Regex Search Projection

A domain-independent projection that walks any input document recursively and
collects every object that has a field whose string value matches a given
`Regex`. The output is a flat collection (`CellVector`) of the matching objects,
in pre-order, with each result mapping back to where the object lives in the
input so selection round-trips.

This is the search/collect sibling of `FilteringProjection`. Where
`FilteringProjection` keeps a *shallow* subset of one collection's direct
elements, `SearchingProjection` performs a *deep* recursive walk of an arbitrary
document tree (or graph) and gathers matches from anywhere inside it.

## Goal

Provide a generic "find all objects matching this pattern" projection that works
on any domain (JSON, XML, syntax, object graphs, …) without knowing the domain.
Given a `Regex`, it produces a collection of every `Document` node that owns at
least one field whose string value matches the pattern. Because it is
domain-neutral it lives in `program/src/projection/generic/` alongside
`FilteringProjection`, `SortingProjection`, and `ReversingProjection`.

Concretely, this enables a search view: project a large document down to just the
nodes that mention some text, navigate the results, and have the cursor map back
into the original document.

## Design

### File: `program/src/projection/generic/Searching.jl`

Module `SearchingProjectionModule`, registered the same way as the other generic
projections (see Registration below).

```julia
struct SearchingProjection <: Projection
    pattern::Regex
    field_match::Function   # (field_name::String, value) -> Bool
end

"""
    SearchingProjection(pattern; field_match=default_field_match)

Walk the input document recursively and collect every `Document` object that has
a field for which `field_match(name, value)` returns `true`. The default
`field_match` matches a field whose value is an `AbstractString` matching
`pattern`.
"""
SearchingProjection(pattern::Regex; field_match::Function = _default_field_match(pattern)) =
    SearchingProjection(pattern, field_match)

# Convenience: accept a plain string and compile it.
SearchingProjection(pattern::AbstractString; kw...) = SearchingProjection(Regex(pattern); kw...)

_default_field_match(pattern::Regex) =
    (name, value) -> value isa AbstractString && occursin(pattern, value)
```

`field_match` is a configurable hook so a caller can broaden what counts as a
match — e.g. also matching the *name* of a field, or matching a primitive
string-valued document (`value.value isa AbstractString`) rather than a raw
`String`. The default covers the literal request: a field with a matching
string.

### IoMap

```julia
struct SearchingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any                      # CellVector of the matched objects
    match_paths::Vector{ReferencePath}   # input-root-relative path to each match[j]
end
```

`match_paths[j]` is the `ReferencePath` from the input root down to the j-th
matched object. This is the single source of truth the reference maps use to
round-trip a path between the output collection and the input tree.

### The recursive walk

`projection_print` performs a pre-order depth-first walk, building the
`ReferencePath` to the current node as it descends and carrying a **seen set** so
cyclic or shared structure (object graphs, `ListNode` rings, the document graph)
is visited at most once.

```julia
function projection_print(p::SearchingProjection, recursion, input, ctx)
    matches = Tuple{ReferencePath,Any}[]
    seen = Base.IdSet{Any}()
    _walk(p, input, EmptyReferencePath(), matches, seen)

    out_cells = Cell[Cell(obj) for (_, obj) in matches]
    output = CellVector(out_cells)
    SearchingProjectionIoMap(p, input, output,
        ReferencePath[path for (path, _) in matches])
end
```

`_walk` descends through the three structural shapes the codebase uses:

```julia
function _walk(p, node, path, matches, seen)
    node isa Document || return
    node in seen && return        # IdSet → identity membership; breaks cycles
    push!(seen, node)

    # 1. Does THIS object qualify? Test every non-:selection field.
    if node isa <struct Document> && _object_matches(p, node)
        push!(matches, (path, node))
    end

    # 2. Recurse into children, extending `path` by the step that reaches each.
    _walk_children(p, node, path, matches, seen)
end
```

- **Struct `Document`** — enumerate `fieldnames`, skip `:selection`. A field
  whose unwrapped value satisfies `p.field_match(name, value)` qualifies the
  object (step 1). Recurse into every field whose unwrapped value `isa Document`,
  extending the path with `FieldReference(string(name))` (step 2). This mirrors
  `CopyingProjection`'s struct handling (`_is_doc_field` / `_unwrap`), so the
  walk follows exactly the field structure the rest of the system addresses.
- **`CellVector` / `Vector{Cell}`** — recurse into each element, extending the
  path with `PositionReference(i)` (consistent with `CopyingProjection` and
  `ReversingProjection`). A bare collection is not itself an "object with
  fields", so it never qualifies — only its element objects can.
- **`ListNode`** — recurse along `next` (and, if reachable, `prev`) with
  `ElementReference(index)`, relying on the seen set to terminate. Guard the
  walk depth/visited count so an unbounded lazy list does not force forever; the
  seen set already prevents revisiting a finite ring.

`_object_matches(p, node)` returns `true` iff any non-`:selection` field's
unwrapped value satisfies `p.field_match(string(name), value)`.

### Reference mapping

Forward: an input path that lands on (or inside) the j-th matched object becomes
`PositionReference(j)` plus the suffix beyond the match.

```julia
function map_reference_forward(p::SearchingProjection, iomap::SearchingProjectionIoMap, reference)
    for (j, mp) in enumerate(iomap.match_paths)
        rest = _strip_prefix(reference, mp)        # nothing if `mp` is not a prefix
        rest === nothing && continue
        return ConcreteReferencePath(PositionReference(j), rest)
    end
    return nothing                                  # not inside any match → no image
end
```

Backward: peel the leading `PositionReference(j)`/`ElementReference`, look up
`match_paths[j]`, and prepend it to the remaining tail.

```julia
function map_reference_backward(p::SearchingProjection, iomap::SearchingProjectionIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            (j < 1 || j > length(iomap.match_paths)) && return nothing
            _concat(iomap.match_paths[j], rest)
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end
```

Two small path helpers are needed because the exported primitives don't quite
fit:

- `_strip_prefix(reference, prefix)` walks both paths step-by-step comparing each
  step with `==`/`reference_equal`, returning the unmatched tail of `reference`
  when `prefix` is fully consumed (an `EmptyReferencePath` when they are equal),
  or `nothing` when `prefix` is not a prefix. The exported `is_prefix_of` is a
  *proper*-prefix boolean — it excludes equality and returns no tail — so it
  can't be used directly here (the whole-object case has `reference == prefix`),
  but `_strip_prefix` can call it / mirror its step comparison.
- `_concat(prefix::ReferencePath, tail::ReferencePath)` joins two paths
  (recursing down `prefix`'s spine, then grafting `tail` at the end).
  `append_reference` takes `ReferenceStep` varargs, not a trailing path, so it
  can't join two paths directly — `_concat` is the path-to-path version (or call
  `append_reference(prefix, steps_of(tail)...)`).

> **Note on School A.** `FilteringProjection`/`ReversingProjection` delegate
> their tail through stored child IO maps because they re-project children with
> `recursion`. `SearchingProjection` does **not** re-project its matches through
> any inner projection — the output element *is* the input object unchanged — so
> there is no child IO map to delegate to. The stored `match_paths` are the
> equivalent record of "how each output slot relates to the input", and the
> mappers translate against them directly. If a later variant re-projects each
> match through `recursion`, switch to storing per-match child IO maps and
> delegate the tail through them (the `ReversingProjection` pattern).

### Selection

The output collection's `selection` is wired the canonical way — forward-project
the input selection so the cursor lands on the matching result if it points
inside one:

```julia
output.selection = Cell(() -> map_reference_forward(p, iomap, input.selection))
```

using the deferred-iomap trick (build `iomap`, then assign the cell) since the
iomap is referenced inside the selection thunk.

### projection_read

The default `projection_read` (handling `ReplaceSelectionOperation` via
`map_reference_backward`) is sufficient for navigation. The search view is
read-only with respect to structure: editing a matched object's text is a future
extension — a `StringReplaceRangeOperation` arriving with a
`PositionReference(j)`-rooted path would be retargeted through
`map_reference_backward` and forwarded. List that under Future work rather than
implementing it now.

## Design Decisions

**Walk by structure, not by domain type.** The walk dispatches on the three
structural shapes (`Document` struct, collection, `ListNode`) exactly as
`CopyingProjection` does, never on concrete domain types. This is what makes the
projection domain-independent and keeps it from drifting as domains are added.

**Seen set keyed by object identity (`IdSet`).** Documents are mutable cells and
graphs can share or cycle through substructure. Identity membership
(`Base.IdSet`/`objectid`) is the correct dedup key — two distinct objects with
equal content are different matches; the same object reached by two paths is
collected once (at the first path the pre-order walk reaches it). Structural
`==` would be both wrong (merging distinct equal objects) and expensive on large
trees.

**Output is a `CellVector` of the objects themselves, not copies or references.**
The result elements are the live matched documents, so the search view shows the
real nodes and `match_paths` records where each came from. This matches
`FilteringProjection`, which also puts the original elements into the output
collection.

**`match_paths` instead of re-projection.** The matches are surfaced unchanged,
so there is no need to re-run `recursion` over them and no child IO maps to
store. Recording the input-relative path per match is the minimal state that
makes the reference round-trip exact. (Contrast `ReversingProjection`, which
*does* re-project and therefore stores child IO maps.)

**`field_match` is a hook, defaulted to the literal request.** The default
matches a field whose value is an `AbstractString` matching the regex — "an
object with a field with a matching string". Exposing the predicate lets callers
extend to field-name matching or primitive string documents without a second
projection type, mirroring how `FilteringProjection` exposes `predicate` and
`SortingProjection` exposes `by`/`lt`/`rev`.

**Pre-order, depth-first ordering.** Results read top-down in document order,
which is the intuitive order for a search results list and makes the ordering
deterministic and stable for tests.

## Exports

From `program/src/Projectured.jl`:

```julia
using .SearchingProjectionModule: SearchingProjection, SearchingProjectionIoMap
...
export SearchingProjection, SearchingProjectionIoMap
```

## Registration

In `program/src/Projectured.jl`, alongside the other generic projections
(currently lines ~81–94):

```julia
include("projection/generic/Searching.jl")
```

Place it after `Filtering.jl` so it can reuse the same imports pattern; it has no
dependency on the other generic projections.

## Integration Points

- **Search view / workbench tool.** A `SearchingProjection(pattern)` feeding a
  `CollectionToSyntax` (or any collection renderer) produces a navigable results
  list. This is the primary intended consumer.
- **`DocumentLocator` (see `plan/pending/document-locator.md`).** The sketched
  `DocumentLocatorPredicate` / `DocumentLocatorPattern` addressing modes are the
  same idea at the locator layer; `SearchingProjection` is the projection-layer
  realization. A future `field_match` built from a `DocumentLocatorPattern` would
  let the two share matching semantics.
- **Composition.** Wrap with `ApplyAtProjection(@reference(...), SearchingProjection(r))`
  to search only a sub-tree, or feed its output to `SortingProjection` to order
  results by a field.

## Implementation Steps

1. **Create `Searching.jl`** with `SearchingProjection`, `SearchingProjectionIoMap`,
   the `_walk` / `_object_matches` / `_strip_prefix` helpers, `projection_print`,
   and the two reference maps. Mirror the imports of `Filtering.jl` /
   `Reversing.jl` (`ProjectionApiModule`, `IoMapApiModule`/`IoMapModule`,
   `ReactiveModule`, `CollectionModule`, `ReferenceModule`, `ReferenceCaseModule`,
   `DocumentModule.Document`).
2. **Register and export** in `Projectured.jl` (`include`, `using`, `export`).
3. **Write tests** (see below).
4. **Verify** with the narrowest test (`test_cell()` is unrelated; use a small
   bespoke test as below), then run `test_json_to_syntax()`-style sweeps only if
   wiring it into a pipeline.

## Tests

Add a focused test (e.g. `program/test/.../searching.jl`) covering:

- **Flat match.** A document with two string fields, one matching → output has
  the one owning object; `length(output) == 1`.
- **Deep match.** A nested object tree (JSON-like) where a match sits several
  levels down → `match_paths[1]` is the correct `Field/Position` path; the output
  element is the matching node.
- **Multiple matches, order.** Several matches at different depths come out in
  pre-order.
- **Seen set / cycles.** Build a small cyclic graph (object A references B
  references A) with a match → the walk terminates and collects each object once.
- **No match.** Empty output collection.
- **Reference round-trip.** For each match j,
  `map_reference_backward(p, iomap, ConcreteReferencePath(PositionReference(j), EmptyReferencePath()))`
  equals `match_paths[j]`, and `map_reference_forward(p, iomap, match_paths[j])`
  equals `PositionReference(j)`-rooted empty tail. A deeper input path inside a
  match round-trips with its suffix preserved.
- **Custom `field_match`.** A predicate matching on field *name* collects the
  expected objects, proving the hook works.

## Dependencies

- `ProjectionApiModule` (`Projection`, `projection_print`, `map_reference_*`).
- `ReferenceModule` (`ReferencePath`, `EmptyReferencePath`, `ConcreteReferencePath`,
  `FieldReference`, `PositionReference`, `ElementReference`, `RangeReference`,
  `append_reference`, `reference_equal`, `is_prefix_of`) — for path building and
  the mappers. The local `_strip_prefix`/`_concat` helpers fill the path-to-path
  gaps these primitives leave.
- `ReferenceCaseModule` (`@reference_case`) — for the backward mapper.
- `CollectionModule` (`CellVector`, `ListNode`) — output collection and list walk.
- `ReactiveModule` (`Cell`), `DocumentModule` (`Document`), `IoMap` API.
- No dependency on other generic/domain projections; foundational and standalone.
```
