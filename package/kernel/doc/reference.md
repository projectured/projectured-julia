# References

References are path-like pointers into document trees. A reference is a
sequence of typed *steps* that descend one level at a time through a document
tree, addressing exactly one location inside it. References let the editor
represent cursor positions, selections, and navigation through structured data
across domain transformations.

This page is the single home for the **reference grammar**: the step
vocabulary, the boundary axis, the two DSLs, type checkpoints, the path
structs, per-domain path tables, and searching (`search_references`). For how a reference
is *stored, propagated, and forward-projected* as the current selection, see
the sibling [selection guide](selection.md).

## The reference layer (kernel layer 3)

References are **layer 3 of the kernel** — paths into documents. The layer lives
in [main/reference/](../main/reference/), inside one aggregator module
(`ReferenceModule`) split across three fragments that share its namespace:

```
ReferenceModule.jl       (ReferenceModule)             — the aggregator
        │ imports Cell and @cell_struct (from CellModule) and Document (from
        │ DocumentModule, for the reflection-walker traits) and exports every
        │ public name below
        ├─ Reference.jl        — the step + path types (RangeReference,
        │                        FieldReference, TypeReference, …,
        │                        EmptyReferencePath, ConcreteReferencePath)
        │                        plus the value protocol on them
        │                        (append_reference, evaluate_reference,
        │                        annotate_reference_types, …)
        ├─ ReferenceCase.jl    — the @reference_case pattern-matching DSL
        │                        (destructures a path against pattern => result
        │                        rules), plus when/prefix guards
        └─ ReferenceBuilder.jl — the @reference / @step construction DSL
                                 (compact surface syntax for building paths)
```

The three fragments are only ever imported together, so they share one
`ReferenceModule` namespace instead of being separate modules — splitting them
would just multiply import headers. They still live in separate files for
readability, but as **fragments** (0-module files sharing the aggregator's
namespace), not separate modules.

### Downward edges

- `..CellModule: Cell, AbstractCell, @cell_struct` — the reactive box the
  mutable step fields live in, and the macro that builds each step/path
  struct with its cells. Steps and paths are not addressable content —
  nothing navigates into one, selects inside one, or projects one — so they
  carry no `selection` field and need none of `@document`'s document codegen;
  `@cell_struct` gives them the transparent-`Cell` fields alone.
- `..DocumentModule: Document, is_element_collection, is_opaque` — only for
  the reflection-walker traits, not for `@document`.

That is the whole import surface of the layer. No projection, no operation, no
device. This is what makes the reference layer sit at index 3 in the kernel's
dependency DAG.

## Reference steps

Each step descends one level into a document tree. The full vocabulary:

| Step | Selects | Notes |
| --- | --- | --- |
| `FieldReference("foo")` | the field named `foo` | resolved by `getfield(doc, :foo)`, unwrapping a `Cell` if needed — struct field names are public API |
| `ElementReference(i)` | the *i*-th element of a sequence | constructor alias for `RangeReference(i-1, i)`; 1-based (Julia convention) |
| `PositionReference(k)` | cursor at boundary *k* of a sequence | constructor alias for `RangeReference(k, k)`; a zero-width cursor, 0-based |
| `RangeReference(s, e)` | the range `s..e` | the underlying type; `Element`/`Position` are constructor aliases |
| `FunctionReference(f)` | a function value | element produced by applying a function; for closures held by name |
| `ProjectionReference(p, sub)` | a projection-introduced element | see [the opaque-payload pattern](#the-opaque-payload-pattern) below |
| `PointReference(x, y)` | a pixel coordinate | for graphics/geometry endpoints and hit-testing |
| `TextRectangularReference(…)` | a rectangular text region | text-domain endpoint |

`TypeReference(T)` also exists but is **not** a navigation step in stored
paths — it survives only as an internal build-time token that is immediately
folded into per-node `type` fields (see
[Type checkpoints](#type-checkpoints-and-replay-validity)). A path node's `head`
is therefore always one of the navigation steps above.

All dynamic step fields (`ElementReference(index::Cell)`,
`FieldReference(name::Cell)`, `PointReference(x::Cell, y::Cell)`, …) are held in
reactive `Cell`s, so the same path object can be re-pointed in place.

### The boundary axis

`ElementReference` and `PositionReference` are two readings of the *same* axis.
Any sequence — array elements, object entries, child nodes, string characters —
has `n` items and `n+1` boundaries between them:

```
        {0}     {1}     {2}     {3}     {4}
         │   a   │   b   │   c   │   d   │
            [1]     [2]     [3]     [4]
```

- `{i}` is the boundary at offset `i` — a zero-width cursor.
- `[i]` is the item between boundaries `i-1` and `i` — the i-th element (1-based).

Both are encoded as the same underlying `RangeReference(start, stop)`: `[i]` is
`RangeReference(i-1, i)` (one-wide), `{i}` is `RangeReference(i, i)`
(zero-wide). A multi-item selection `{i:j}` is `RangeReference(i, j)`.

The same convention applies regardless of what the items are. In an array, `[1]`
is the first element and `{0}` is the cursor before it. In a string, `[1]` is
the first character and `{0}` is the cursor before it. In an object, `[1]` is
the first entry and `{0}` is the cursor before it.

### ProjectionReference

Points to elements introduced by a projection (delimiters, brackets,
separators) that have no counterpart in the underlying document.

```julia
ProjectionReference(projection,
    ConcreteReferencePath(FieldReference("open"),
        ConcreteReferencePath(PositionReference(0))))
```

## Reference paths and their structs

A `ReferencePath` chains steps. It is an **immutable linked list**, so
extending or sharing a path costs no copying — a new prefix reuses the existing
tail:

```julia
abstract type ReferencePath end
struct EmptyReferencePath <: ReferencePath end
struct ConcreteReferencePath <: ReferencePath
    head::Cell   # holds a ReferenceStep
    tail::Cell   # holds the next ReferencePath
    type         # the Julia type this node stands on (a type checkpoint)
end
```

`EmptyReferencePath()` terminates the list at the root/leaf;
`ConcreteReferencePath(step, tail)` is one cons cell. Both fields are `Cell`s so
the path is reactive — a computed cell can depend on a path's content. The list
*shape* is persistent, but because each `@cell_struct`-backed step/path struct is
mutable and stores its dynamic values in reactive `Cell`s, `replace_selection!`
can move a caret by writing those cells in place rather than rebuilding the chain.

**Build paths with the `@reference` macro** (see
[§ Reference DSL](#reference-dsl-reference) below) — it is the canonical, most
capable way to construct a reference:

```julia
@reference items[1].name        # ElementReference(1) then FieldReference("name")
@reference()                    # the empty path (the whole element / root)
```

For programmatic construction from a list of steps, `ReferencePath(steps...)`
threads them into a path:

```julia
ReferencePath(ElementReference(1), FieldReference("name"))
```

You rarely construct the cons cells by hand; prefer `@reference` or
`ReferencePath`.

### Whole-element selection: the empty path

An **empty path** (`EmptyReferencePath()`, written `@reference()`, matched by
the `∅` pattern) means *the whole element at this level is selected* — there is
no sub-position within it. This is a first-class selection convention, not an
absence of selection (that is `nothing`).

Because an empty path has no steps to translate, it maps across any projection
**by identity**: the default `map_reference_forward` / `map_reference_backward`
return `@reference()` unchanged for it, so whole-element selections round-trip
through every projection for free.

## Resolving and validating a reference

`evaluate_reference(document, path)` is the inverse of building a path: it walks
`path` from `document` and returns the node (or value) it points at — unwrapping
cells, descending fields by `FieldReference` and elements by
`ElementReference` / `PositionReference`. It is the
`(document, reference) → node` function.

```julia
ref  = @reference entries[1].value
node = evaluate_reference(document, ref)   # the JsonString at that path
```

**To find a node by content** (and get a reference to it, or select it) rather
than knowing its path up front, use `search_references` / `search_documents` — see
the [finding-and-selecting guide](finding-and-selecting.md). Do not hand-walk
the document tree to locate a node.

`is_valid_reference` checks that an object is a valid reference step or path:

```julia
is_valid_reference(PositionReference(5))    # true
is_valid_reference(FieldReference("name"))  # true
is_valid_reference("not a reference")       # false
is_valid_reference(EmptyReferencePath())    # true
```

For a `ConcreteReferencePath` it recursively validates that the head cell holds
a valid `ReferenceStep` and the tail cell a valid `ReferencePath`, ensuring the
whole chain is well-formed. This one-argument form is a purely *structural*
check. The two-argument, document-aware method is described under
[Type checkpoints](#type-checkpoints-and-replay-validity).

## Type checkpoints and replay validity

A reference is often captured before an edit and replayed against the document
*after* it. If the document's structure changed underneath the stored path
(a `JsonString` swapped for a `JsonNumber`, a node retyped, …), the leftover
steps would silently mis-navigate or throw a bare `getfield` error.

Per-node **type checkpoints** guard against this. The type is **folded into
every path node**: each `ConcreteReferencePath` carries a `type` field recording
the Julia type of the node it stands on (the type its `head` step descends
*from*), and the terminal `EmptyReferencePath` records the type of the node the
path lands on. A node's `head` is therefore **always a navigation step** — there
is no separate interleaved `TypeReference` *step* and nothing to "skip". The
match rule is `node isa T`.

A `FieldReference` does not need two checkpoints (a start and an end): a step's
*start* type is its own node's `type`, its *end* type is its `tail` node's
`type`. The boundary type is stored once, on the downstream node, serving both
roles — so a k-step path has k+1 typed nodes (every boundary plus the terminal).

- `evaluate_reference(document, path)` throws `ReferenceTypeMismatch(expected,
  actual)` when a node's recorded type no longer matches the document reached.
  (It is the document-aware validator under the hood.)
- `get_valid_reference_prefix(document, path)` walks the path and returns the
  **longest prefix that still resolves** — it stops at the first node whose type
  mismatches (or an unfollowable structural step), dropping the invalid
  remainder.
- `is_valid_reference(document, path)` (the two-argument, document-aware method)
  is `true` iff every node type holds along the whole path.

Checkpoints are created programmatically, not by hand:

- `annotate_reference_types(document, path)` returns `path` with each node's
  `type` field filled in against `document` (a `{k}` cursor lands on no child,
  so the terminal after it stays untyped).
- `strip_reference_types(path)` blanks the node types again, recovering the
  plain navigation skeleton. The two are inverses on an unchanged document.
- `fold_reference_types(path)` converts a path that still carries transitional
  `TypeReference` *steps* (e.g. the ones `@reference ::T` builds, or those the
  generic `ProjectionTemplate` helpers prepend) into the folded node-type form.
  It is applied at construction so no stored or consumed path ever holds a
  checkpoint step.

### Where checkpoints live (canonical, folded, everywhere)

Folded node types are the **canonical form references are held in** — at rest
and in projected output alike:

- **Document-domain selections are canonical.** `set_selection!(document, path)`
  fills node types against `document` (it does
  `annotate_reference_types(document, strip_reference_types(path))`), so every
  document's `selection` cell holds the folded form. `search_references`
  likewise annotates its results, so search results are self-describing too.
- **Mappers and structure-creating printers emit the folded form.** Each printer
  that builds output structure types the output path it constructs; the generic
  `ProjectionTemplate` helpers (`_typed`, `_path`, `_prepend`) fold the type
  checkpoints they assemble. Consumers read `head`/`tail` directly — no path
  they see carries an interleaved checkpoint step.

The replay/validation primitives still apply when you hold a reference across an
edit:

```julia
annotated = annotate_reference_types(document, path)   # or just read a selection cell
# … document is edited …
live     = get_valid_reference_prefix(document, annotated)  # truncate at first mismatch
```

> **Implementation note.** `TypeReference(T)` survives only as an internal
> *build-time token*: the `@reference ::T` DSL and the `ProjectionTemplate`
> helpers emit it, and `fold_reference_types` immediately folds it into node
> `type` fields. It never appears as a step in a stored or consumed path.

## Input and output references

References are always interpreted relative to a particular document. When a
projection is involved, every reference falls into one of two roles:

- **Input reference** — steps understood starting from the *input* document of a
  projection.
- **Output reference** — steps understood starting from the *output* document of
  a projection.

`map_reference_forward` takes an input reference and returns an output
reference. `map_reference_backward` takes an output reference and returns an
input reference. These are the only two functions that translate between the two
roles, and each projection defines its own rules for how the translation works.

A `ProjectionReference(P, output_path)` *step* embeds an output reference inside
an input reference: it says "from this position, jump through projection `P`,
then continue with `output_path` in `P`'s output." This lets an input reference
point at structural elements (delimiters, separators, decorations) that only
exist in the output and have no direct counterpart in the input. Forward mapping
through `P` strips the `proj(P, …)` step; backward mapping through `P`, for an
output reference that has no pre-image in the input, can wrap the unmatched
suffix with a `proj(P, …)` step to round-trip cleanly.

## Reference DSL: `@reference`

The `@reference` macro turns compact source into the nested
`ConcreteReferencePath(…)` you would otherwise write by hand:

```julia
# Field references
@reference address.city
# → FieldReference("address") then FieldReference("city")

# Element references (1-based)
@reference items[i]                 # → ElementReference(i)

# Position references (0-based)
@reference items{i}                 # → PositionReference(i)

# Range references — explicit multi-element selection
@reference items{s:e}               # → RangeReference(s, e)
# Prefer this form over the older two-arg `items[s, e]`.

# Dynamic field names
@reference config.field(fname)      # → FieldReference(fname)

# Point references (2D coordinates)
@reference cursor.point(x, y)       # → PointReference(x, y)

# Projection references
@reference rendered.proj(projection, {0})
# → ProjectionReference(projection, the one-step path PositionReference(0))

# Complex paths
@reference items[1].name            # → ElementReference(1) then FieldReference("name")

# Path-tail splice
@reference value.^(tail)
# Concatenates the spliced ReferencePath (or single ReferenceStep) onto the
# prefix; useful for rebuilding paths like
#   ConcreteReferencePath(FieldReference("value"), tail)
# in projection mappers.

# Splice at the front
@reference ^(base).inner            # → _concat(base, @reference inner)

# Splice with a single step
let s = FieldReference("foo")
    @reference value.^(s)           # → FieldReference("value") then FieldReference("foo")
end
```

The `^()` operator accepts either a `ReferencePath` (concatenated) or a
`ReferenceStep` (wrapped into a one-step path then concatenated). It can appear
at the front of a chain (`^(base).rest`) or at the tail (`prefix.^(tail)`).
Mid-chain splices are not supported because the surrounding Julia surface syntax
does not parse `prefix.^(x).suffix` the way the DSL would need.

### Building single steps: `@step`

The `@step` macro builds a single `ReferenceStep`, useful for passing to
`append_reference` or any API that takes raw steps instead of full paths.

```julia
@step value              # FieldReference("value")
@step xs[i]              # ElementReference(i)
@step xs{k}              # PositionReference(k)
@step xs{s:e}            # RangeReference(s, e)
@step c.point(x, y)      # PointReference(x, y)
@step config.field(name) # FieldReference(name)
```

The leading identifier (`xs`, `c`, `config`) is a placeholder — only the
trailing operator determines the step's kind. For a bare symbol like
`@step value`, the symbol itself becomes the field name.

## Reference pattern matching: `@reference_case`

The `@reference_case` macro matches a path against `pattern => result` rules (à
la Julia's `match`), binding the variable parts (indices, field names, tails)
for the result expression:

```julia
@reference_case reference begin
    value{k}            => @reference value{k}   # cursor position (0-based)
    items{s:e}          => ("range", s, e)       # matches any RangeReference, binds boundaries
    items[i]            => ("item at", i)         # element access (1-based)
    items[1]            => "first item"           # literal element
    when(items[i], i>0) => ("later item", i)      # guarded pattern
    _                   => "default"              # wildcard
end
```

Pattern syntax:
- `_` — wildcard, matches anything
- `∅` — the **empty path** (`EmptyReferencePath`), i.e. a *whole-element*
  selection
- `i` — binder, captures the value
- `"name"` or `0` — literal, matches a specific value
- `i::Int` — typed binder, captures with a type check
- `path...` — matches prefix and binds the remaining tail
- `{s:e}` — range pattern, matches any `RangeReference` (positions are
  `RangeReference(k, k)`, so `{s:e}` will also match a position; list more
  specific `{k}` patterns first if both are interesting)

The `when(pattern, cond)` helper adds a guard; `prefix(pattern)` matches a
prefix rather than requiring an exact match. `@reference_case` is commonly used
in projection readers to translate output-domain references back to input-domain
references — for example, mapping the empty path by identity:

```julia
function map_reference_forward(::SomeProjection, iomap, reference)
    @reference_case reference begin
        ∅           => @reference()        # whole element — identity
        value{k}    => @reference value{k}
    end
end
```

### The two DSLs are surface-syntax siblings

`@reference` (construction) and `@reference_case` (destructuring) operate on the
same reference vocabulary. Domain code that both constructs and matches
references (every non-trivial `read_intent`) benefits from having them side by
side — a change to one DSL's syntax is a change to its twin's grammar.

## Mapping between document structs and reference steps

Reference paths mirror the struct field layout of documents. Every `.` in a
printed path corresponds to a `FieldReference`; every `[i]` corresponds to an
`ElementReference`; every `{i}` corresponds to a `PositionReference`. The core
rules used by `set_selection!`, `clear_selection!`, and `evaluate_reference`
are:

| Reference step | Navigation action |
|---|---|
| `FieldReference("f")` | `getfield(document, :f)` — unwrap Cell if needed |
| `ElementReference(i)` | `document[i]` — the i-th item (1-based); element in a collection or character in a string |
| `PositionReference(i)` | cursor at boundary `i` (0-based); between elements in a collection or between characters in a string |

### CellVector (used by arrays, objects, and other containers)

`CellVector` has `elements::Cell` (holding a `Vector{Cell}`) and
`selection::Cell`. As a sequence it supports both readings of the boundary axis:

| Step | Target |
|---|---|
| `ElementReference(i)` | `elements[i]` — the i-th element (1-based) |
| `PositionReference(i)` | cursor between elements (0-based); useful as an insertion point |

### JSON domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **JsonObject** | `entries` | `FieldReference("entries")` | the CellVector of entries |
| **JsonArray** | `elements` | `FieldReference("elements")` | the CellVector of elements |
| **JsonObjectEntry** | `value` | `FieldReference("value")` | the value document (Cell) |
| **JsonObjectEntry** | `key` | `FieldReference("key")` | the key string |
| **JsonString** | `value` | `FieldReference("value")` | the String cell |
| **JsonNumber** | `value` | `FieldReference("value")` | the Number cell |
| **JsonBool** | `value` | `FieldReference("value")` | the Bool cell |
| *any CellVector or String* | `[i]` | `ElementReference(i)` | the i-th item (1-based) — element or character |
| *any CellVector or String* | `{k}` | `PositionReference(k)` | cursor at boundary `k` (0-based) — between elements or characters |

**Full path example** — character 3 of `"Alice"` in `{"name": "Alice"}`:

```
@reference entries[1].value.value{3}
           ───────     FieldReference("entries")
                  ───  ElementReference(1)       → JsonObjectEntry
                       ─────                         FieldReference("value")  → JsonString
                             ─────                   FieldReference("value")  → String cell
                                  ───                PositionReference(3)     → char offset
```

### XML domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **XmlElement** | `attrs` | `FieldReference("attrs")` | CellVector of XmlAttribute |
| **XmlElement** | `cell` | `FieldReference("cell")` | CellVector of child nodes |
| **XmlText** | `cell` | `FieldReference("cell")` | the String cell |
| **XmlAttribute** | `cell` | `FieldReference("cell")` | the attribute value cell |
| *any CellVector or String* | `[i]` | `ElementReference(i)` | the i-th item (1-based) — element or character |
| *any CellVector or String* | `{k}` | `PositionReference(k)` | cursor at boundary `k` (0-based) — between elements or characters |

### Book domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **BookBook** | `elements` | `FieldReference("elements")` | CellVector of chapters |
| **BookChapter** | `elements` | `FieldReference("elements")` | CellVector of children |
| **BookList** | `elements` | `FieldReference("elements")` | CellVector of items |
| **BookParagraph** | `content` | `FieldReference("content")` | the text content |
| **BookPicture** | `content` | `FieldReference("content")` | the image content |

### FileSystem domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **FileSystemDirectory** | `elements` | `FieldReference("elements")` | CellVector of children |

### Selection-path forms by domain

The tables above list the fields; the forms below name the common *cursor* path
shapes those fields produce as a selection (`[i]` is the i-th item, 1-based;
`{k}` is the cursor at boundary `k`, 0-based).

| Domain | Path form | Meaning |
|---|---|---|
| `Text` | `{k}` | cursor at offset `k` in the flat span sequence |
| `SyntaxLeaf` | `.value + {k}` | cursor at offset `k` in the value span |
| `SyntaxLeaf` | `.open + {k}` / `.close + {k}` | cursor in the opening / closing delimiter |
| `SyntaxNode` | `[i] + <child path>` | into child `i` |
| `SyntaxNode` | `.open + {k}` / `.close + {k}` | cursor in delimiter span |
| `SyntaxNode` | `ProjectionReference(p, {k})` | projection-introduced whitespace |
| `JsonString` | `.value + {k}` | cursor in the string value |
| `JsonString` | `ProjectionReference(p, .open + {k})` | cursor on `"` opening quote |
| `JsonString` | `ProjectionReference(p, .close + {k})` | cursor on `"` closing quote |
| `JsonArray` | `[i] + <element path>` | into element `i` |
| `JsonObject` | `[i] + .value + <value path>` | into the value of entry `i` |
| `JsonObject` | `[i] + .key + {k}` | cursor in the key string of entry `i` |

### General pattern

The pattern is consistent across all domains:

1. **Struct fields** → `FieldReference("field_name")` — descend into a named
   field; if the field is a `Cell`, it is automatically unwrapped.
2. **i-th item** → `ElementReference(i)` — descend into the i-th item of a
   sequence (1-based); same step whether the sequence holds elements (CellVector,
   JsonArray, …) or characters (String).
3. **Boundary between items** → `PositionReference(k)` — cursor at the k-th
   boundary of a sequence (0-based); same step whether between elements
   (insertion point) or between characters (text cursor).

A reference path is always a chain of these step types (plus `ProjectionReference`
for projection-introduced elements like delimiters and brackets).

## Finding references: `search_references`

To find every path to a matching node, use `search_references(document, query)`
— it takes a predicate, a substring `String`, or a `Regex`, and returns a
`Vector{ReferencePath}` whose results are annotated with type checkpoints (so
they are self-describing and replay-safe):

```julia
for ref in search_references(editor.document, "John")   # or r"TODO", or a predicate
    value = evaluate_reference(document, ref)
    println("Found at $ref: $value")
end
```

`search_references` lives in the **reference layer**: it *produces* reference
paths, so it belongs with the machinery that expresses them. Its object-valued
sibling `search_documents` (below) needs no reference machinery, so it lives one
layer down in the **document layer** — the two walks are structurally parallel
and kept in sync. Both stay free of higher-layer types through two Holy traits
they dispatch on but do not own, each a document-layer default: `is_element_collection`
(`CellVector` opts in, so a positional collection emits `[i]` element paths) and
`is_opaque` (the agent layer's `Llm` opts in, so the walk never descends into
assistant configuration). Higher layers register their document types by adding
methods, never by the walker naming them. See the
[finding-and-selecting guide](finding-and-selecting.md).

To collect the matching **document nodes** themselves (each once) rather than their
paths, use `search_documents(document, query)` — same predicate/`String`/`Regex`
query, returning a `Vector` of the matched document nodes (scalar leaf matches are
folded up to their enclosing `Document`; pass `raw=true` to return the exact matched value).

## The opaque-payload pattern

`ProjectionReference` stores its projection as an **untyped `Any` payload** — the
reference layer defines only the step's shape and never imports `Projection`.
Only higher layers (the projection layer) construct and interpret the payload.
So the only edge between projection and reference is `projection → reference`
(for `PrinterContext`, reference mapping, and similar), and it points down. This
is the same pattern `Intent` uses (the reader's backward-flowing type), and it
is the kernel's answer to "you'd think this needs a cycle" cases: mention the
higher type opaquely, never call into it. The `Reference.jl` fragment documents
this at the type declaration.

## Testing

`test/reference/` migrates ProjecturedTest's `ReferenceBuilderTest.jl` verbatim
(rewritten to `using ProjecturedKernel.ReferenceModule` — no umbrella needed)
and adds `ReferenceEvalTest.jl` which walks `evaluate_reference` over a
test-local `@document struct ToyBranch`. No concrete engine document is imported;
the reference DSLs must stand on their own.

## Why references matter

References enable cursor navigation across domain transformations, selection
preservation through projections, bidirectional mapping between input and output
domains, and reactive updates when document structure changes. The projection
system translates references between domains, allowing the cursor to be
positioned on elements that may not exist in the underlying document (like
delimiters). How that stored selection is propagated and forward-projected is
the subject of the [selection guide](selection.md).
