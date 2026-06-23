# References

References are path-like pointers into document trees. They enable the editor to represent cursor positions, selections, and navigation through structured data across domain transformations.

## What is a Reference?

A reference is a sequence of typed steps that descend through a document tree. Each step specifies how to navigate from the current node to a child or attribute. References are implemented as immutable linked lists so that extending a path reuses the existing tail — no copying required.

## Reference Steps

- `ElementReference(index::Cell)` — constructor alias for `RangeReference(index-1, index)`; selects the i-th element (1-based)
- `PositionReference(index::Cell)` — constructor alias for `RangeReference(index, index)`; zero-width cursor at boundary `index` (0-based)
- `RangeReference(start::Cell, stop::Cell)` — the underlying type; `ElementReference` and `PositionReference` are both shorthands that produce a `RangeReference`
- `FieldReference(name::Cell)` — named struct field
- `ProjectionReference(projection, output_path)` — projection-introduced element (e.g. delimiters)
- `PointReference(x::Cell, y::Cell)` — pixel coordinates for hit-testing
- `TypeReference(type)` — non-navigating type checkpoint (asserts the current node `isa type`; see [Type checkpoints](#type-checkpoints-and-replay-validity))
- `FunctionReference(f)` — element produced by applying a function

### The boundary axis

`ElementReference` and `PositionReference` are two readings of the *same* axis. Any sequence — array elements, object entries, child nodes, string characters — has `n` items and `n+1` boundaries between them:

```
        {0}     {1}     {2}     {3}     {4}
         │   a   │   b   │   c   │   d   │
            [1]     [2]     [3]     [4]
```

- `{i}` is the boundary at offset `i` — a zero-width cursor.
- `[i]` is the item between boundaries `i-1` and `i` — the i-th element (1-based).

Both are encoded as the same underlying `RangeReference(start, stop)`: `[i]` is `RangeReference(i-1, i)` (one-wide), `{i}` is `RangeReference(i, i)` (zero-wide). A multi-item selection `{i:j}` is `RangeReference(i, j)`.

The same convention applies regardless of what the items are. In an array, `[1]` is the first element and `{0}` is the cursor before it. In a string, `[1]` is the first character and `{0}` is the cursor before it. In an object, `[1]` is the first entry and `{0}` is the cursor before it.

### ElementReference

Descend to the i-th element (1-based). Used for array element index, child node position, accessing elements in collections, the i-th character in a string.

```julia
ElementReference(1)   # first item
ElementReference(3)   # third item
```

### PositionReference

Cursor at the i-th boundary (0-based). Position 0 is before the first item, position n is after the n-th item. Used for the cursor between array elements (insertion point), between object entries, or between characters in a string.

```julia
PositionReference(0)  # cursor before first item
PositionReference(3)  # cursor after third item
```

### FieldReference

Descend into a named field. Used for object keys in JSON, struct field names, attribute names in XML.

```julia
FieldReference("name")
FieldReference("value")
```

### ProjectionReference

Points to elements introduced by a projection (e.g. delimiters, brackets).

```julia
ProjectionReference(projection,
    ConcreteReferencePath(FieldReference("open"),
        ConcreteReferencePath(PositionReference(0))))
```

## Input and Output References

References are always interpreted relative to a particular document. When a projection is involved, every reference falls into one of two roles:

- **Input reference** — a reference whose steps are to be understood starting from the *input* document of a projection.
- **Output reference** — a reference whose steps are to be understood starting from the *output* document of a projection.

`map_reference_forward` takes an input reference and returns an output reference. `map_reference_backward` takes an output reference and returns an input reference. These are the only two functions that translate between the two roles, and each projection defines its own rules for how the translation works.

A `ProjectionReference(P, output_path)` *step* embeds an output reference inside an input reference: it says "from this position, jump through projection `P`, then continue with `output_path` in `P`'s output." This lets an input reference point at structural elements (delimiters, separators, decorations) that only exist in the output and have no direct counterpart in the input. Forward mapping through `P` strips the `proj(P, …)` step; backward mapping through `P`, for an output reference that has no pre-image in the input, can wrap the unmatched suffix with a `proj(P, …)` step to round-trip cleanly.

## Reference Paths

**Build paths with the `@reference` macro** (see [§ Reference DSL](#reference-dsl-reference)
below) — it is the canonical, most capable way to construct a reference:

```julia
@reference items[1].name        # ElementReference(1) then FieldReference("name")
@reference()                    # the empty path (the whole element / root)
```

For programmatic construction from a list of steps, `ReferencePath(steps...)`
threads them into a path:

```julia
ReferencePath(ElementReference(1), FieldReference("name"))
```

Under the hood a path is an immutable linked list — `EmptyReferencePath()`
terminates it and `ConcreteReferencePath(head, tail)` is one cons cell — but you
rarely construct those cells by hand; prefer `@reference` or `ReferencePath`.

## Resolving a reference to a node

`evaluate_reference(document, path)` is the inverse of building a path: it walks
`path` from `document` and returns the node (or value) it points at — unwrapping
cells, descending fields by `FieldReference` and elements by
`ElementReference` / `PositionReference`. It is the `(document, reference) → node`
function.

```julia
ref  = @reference entries[1].value
node = evaluate_reference(document, ref)   # the JsonString at that path
```

(`evaluate_reference` is also the document-aware validator under the hood — see
[§ Type checkpoints](#type-checkpoints-and-replay-validity) for how it reports a
structure mismatch when a stored path no longer fits the document.)

**To find a node by content** (and get a reference to it, or select it) rather
than knowing its path up front, use `search_references` / `search_objects` — see
the [finding-and-selecting guide](finding-and-selecting.md). Do not hand-walk the
document tree to locate a node.

## Mapping Between Document Structs and Reference Steps

Reference paths mirror the struct field layout of documents. The two core
rules used by `set_selection!`, `clear_selection!`, and `evaluate_reference`
are:

| Reference step | Navigation action |
|---|---|
| `FieldReference("f")` | `getfield(document, :f)` — unwrap Cell if needed |
| `ElementReference(i)` | `document[i]` — the i-th item (1-based); element in a collection or character in a string |
| `PositionReference(i)` | cursor at boundary `i` (0-based); between elements in a collection or between characters in a string |

Every `.` in a printed path corresponds to a `FieldReference`; every `[i]`
corresponds to an `ElementReference`; every `{i}` corresponds to a `PositionReference`.

### CellVector (used by arrays, objects, and other containers)

`CellVector` has `elements::Cell` (holding a `Vector{Cell}`) and `selection::Cell`. As a sequence it supports both readings of the boundary axis:

| Step | Target |
|---|---|
| `ElementReference(i)` | `elements[i]` — the i-th element (1-based) |
| `PositionReference(i)` | cursor between elements (0-based); useful as an insertion point |

### JSON Domain

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

### XML Domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **XmlElement** | `attrs` | `FieldReference("attrs")` | CellVector of XmlAttribute |
| **XmlElement** | `cell` | `FieldReference("cell")` | CellVector of child nodes |
| **XmlText** | `cell` | `FieldReference("cell")` | the String cell |
| **XmlAttribute** | `cell` | `FieldReference("cell")` | the attribute value cell |
| *any CellVector or String* | `[i]` | `ElementReference(i)` | the i-th item (1-based) — element or character |
| *any CellVector or String* | `{k}` | `PositionReference(k)` | cursor at boundary `k` (0-based) — between elements or characters |

### Book Domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **BookBook** | `elements` | `FieldReference("elements")` | CellVector of chapters |
| **BookChapter** | `elements` | `FieldReference("elements")` | CellVector of children |
| **BookList** | `elements` | `FieldReference("elements")` | CellVector of items |
| **BookParagraph** | `content` | `FieldReference("content")` | the text content |
| **BookPicture** | `content` | `FieldReference("content")` | the image content |

### FileSystem Domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **FileSystemDirectory** | `elements` | `FieldReference("elements")` | CellVector of children |

### General Pattern

The pattern is consistent across all domains:

1. **Struct fields** → `FieldReference("field_name")` — descend into a named field; if the field is a `Cell`, it is automatically unwrapped.
2. **i-th item** → `ElementReference(i)` — descend into the i-th item of a sequence (1-based); same step whether the sequence holds elements (CellVector, JsonArray, …) or characters (String).
3. **Boundary between items** → `PositionReference(k)` — cursor at the k-th boundary of a sequence (0-based); same step whether between elements (insertion point) or between characters (text cursor).

A reference path is always a chain of these step types (plus `ProjectionReference` for projection-introduced elements like delimiters and brackets).

## Validating References

Use `is_valid_reference` to check if an object is a valid reference step or path:

```julia
is_valid_reference(PositionReference(5))  # true
is_valid_reference(FieldReference("name"))  # true
is_valid_reference("not a reference")  # false
is_valid_reference(EmptyReferencePath())  # true
```

For `ConcreteReferencePath`, recursively validates head and tail cells.

## Type checkpoints and replay validity

A reference is often captured before an edit and replayed against the document
*after* it. If the document's structure changed underneath the stored path
(a `JsonString` swapped for a `JsonNumber`, a node retyped, …), the leftover
steps would silently mis-navigate or throw a bare `getfield` error.

`TypeReference(T)` guards against this. It is **not** a navigation step: it
asserts that the node reached so far is a `T` and then continues on the *same*
node. The match rule is `node isa T`.

- `evaluate_reference(document, path)` throws `ReferenceTypeMismatch(expected,
  actual)` when a checkpoint's recorded type no longer matches.
- `valid_reference_prefix(document, path)` walks the path and returns the
  **longest prefix that still resolves** — it stops at the first failing
  checkpoint (or unfollowable structural step), so the invalid remainder is
  dropped.
- `is_valid_reference(document, path)` (the two-argument, document-aware method)
  is `true` iff every checkpoint holds along the whole path. The one-argument
  `is_valid_reference(obj)` remains a purely *structural* check and is unchanged.

Checkpoints are created programmatically, not by hand:

- `annotate_reference_types(document, path)` returns `path` interleaved with a
  `TypeReference(typeof(node))` before each navigation step.
- `strip_reference_types(path)` removes them again, recovering the plain
  navigation-only path. The two are inverses on an unchanged document.

### Where checkpoints live (canonical at rest, stripped at the boundary)

Checkpoints are now the **canonical form references are held in at rest** —
*not* an opt-in annotation applied just before replay:

- **Document-domain selections are canonical.** `set_selection!(document, path)`
  annotates the path against `document` (it does
  `annotate_reference_types(document, strip_reference_types(path))`), so every
  document's `selection` cell holds the canonical form. `collect_references`
  likewise annotates its results, so search results are self-describing too.
- **The projection boundary strips on entry.** Type checkpoints record an
  *input-domain* type and are meaningless once a path crosses a projection, so
  the public `map_reference_forward` / `map_reference_backward` wrappers
  `strip_reference_types` the incoming path before handing it to the
  per-projection mapper (the bespoke mappers stay navigation-only). Operation
  evaluators that navigate by a selection-derived path strip likewise.
- **`strip_reference_types` is the internal boundary tool**, not a step callers
  run before applying a path. You normally hand `set_selection!` a plain skeleton
  (built with `@reference`) and it becomes canonical for you.

The replay/validation primitives are unchanged and still useful when you hold a
reference across an edit:

```julia
annotated = annotate_reference_types(document, path)   # or just read a selection cell
# … document is edited …
live     = valid_reference_prefix(document, annotated)  # truncate at first mismatch
```

> **Projected output selections are currently plain**, not canonical: re-typing
> them against each render domain (Option B "output residency") is deferred —
> see `plan/pending/type-reference-everywhere.md`. The boundary wrapper has a
> one-line switch to enable it once the render/layout selection consumers are
> made checkpoint-tolerant.

## Reference DSL: `@reference`

The `@reference` macro provides a convenient DSL for building reference paths:

```julia
# Field references
@reference address.city
# Equivalent to the path: FieldReference("address") then FieldReference("city")

# Element references (1-based)
@reference items[i]
# Equivalent to: ElementReference(i)

# Position references (0-based)
@reference items{i}
# Equivalent to: PositionReference(i)

# Dynamic field names
@reference config.field(fname)
# Equivalent to: FieldReference(fname)

# Point references (for 2D coordinates)
@reference cursor.point(x, y)
# Equivalent to: PointReference(x, y)

# Projection references
@reference rendered.proj(projection, {0})
# Equivalent to: ProjectionReference(projection, the one-step path PositionReference(0))

# Complex paths
@reference items[1].name
# Equivalent to the path: ElementReference(1) then FieldReference("name")

# Range references — explicit multi-element selection
@reference items{s:e}
# Equivalent to: RangeReference(s, e)
# Prefer this form over the older two-arg `items[s, e]`.

# Path-tail splice
@reference value.^(tail)
# Concatenates the spliced `ReferencePath` (or single `ReferenceStep`) onto
# the prefix; useful for rebuilding paths like
#   ConcreteReferencePath(FieldReference("value"), tail)
# in projection mappers.

# Splice at the front
@reference ^(base).inner
# Equivalent to: `_concat(base, @reference inner)`

# Splice with a single step
let s = FieldReference("foo")
    @reference value.^(s)
end
# Equivalent to the path: FieldReference("value") then FieldReference("foo")
```

The `^()` operator accepts either a `ReferencePath` (concatenated) or a
`ReferenceStep` (wrapped into a one-step path then concatenated). It can
appear at the front of a chain (`^(base).rest`) or at the tail
(`prefix.^(tail)`). Mid-chain splices are not supported because the
surrounding Julia surface syntax does not parse `prefix.^(x).suffix` the
way the DSL would need.

## Building Single Steps: `@step`

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

## Reference Pattern Matching: `@reference_case`

The `@reference_case` macro provides pattern matching for reference paths:

```julia
@reference_case reference begin
    # Cursor position pattern (0-based)
    value{k} => @reference value{k}

    # Range pattern (matches any RangeReference and binds boundaries)
    items{s:e} => ("range", s, e)

    # Wildcard pattern (matches anything)
    _ => "default"

    # Element access pattern (1-based)
    items[i] => ("item at", i)

    # Literal element pattern
    items[1] => "first item"

    # Guarded pattern with `when`
    when(items[i], i > 0) => ("later item", i)
end
```

Pattern syntax:
- `_` — wildcard, matches anything
- `∅` — the **empty path** (`EmptyReferencePath`), i.e. a *whole-element*
  selection (see below)
- `i` — binder, captures the value
- `"name"` or `0` — literal, matches specific value
- `i::Int` — typed binder, captures with type check
- `path...` — matches prefix and binds remaining tail
- `{s:e}` — range pattern, matches any `RangeReference` (positions are
  `RangeReference(k, k)`, so `{s:e}` will also match a position; list
  more specific `{k}` patterns first if both are interesting)

The `@reference_case` macro is commonly used in projection readers to translate output-domain references back to input-domain references.

## Whole-element selection: the empty path

An **empty path** (`EmptyReferencePath()`, written `@reference()`, matched by the
`∅` pattern) means *the whole element at this level is selected* — there is no
sub-position within it. This is a first-class selection convention, not an
absence of selection (that is `nothing`).

Because an empty path has no steps to translate, it maps across any projection
**by identity**: the default `map_reference_forward` / `map_reference_backward`
return `@reference()` unchanged for it, so whole-element selections round-trip
through every projection for free.

```julia
function map_reference_forward(::SomeProjection, iomap, reference)
    @reference_case reference begin
        ∅           => @reference()        # whole element — identity
        value{k}    => @reference value{k}
    end
end
```

## Collecting References: `collect_references`

The `collect_references` function searches a document tree for all occurrences of a specific value and returns their reference paths.

```julia
result = collect_references(editor.document, "John")
# Returns a Vector{ReferencePath}, e.g.:
# [entries[1].value, entries[3].value.name.value]  (printed with [i] for elements)

for ref in result
    value = evaluate_reference(document, ref)
    println("Found at $ref: $value")
end
```

## Why References Matter

References enable:
- **Cursor navigation** across domain transformations
- **Selection preservation** through projections
- **Bidirectional mapping** between input and output domains
- **Reactive updates** when document structure changes

The projection system translates references between domains, allowing the cursor to be positioned on elements that may not exist in the underlying document (like delimiters).

## Key Features

- Immutable linked list for efficient path extension
- All steps are reactive Cells
- ProjectionReference enables cursor on delimiters
- Shared selection cells propagate changes automatically
