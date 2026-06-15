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
- `TypeReference(type)` — element of a given type
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

Paths are immutable linked lists of steps:

- **EmptyReferencePath** — terminates the path (root)
- **ConcreteReferencePath** — holds a head step and tail path

```julia
# Empty path (root)
EmptyReferencePath()

# Single step
ConcreteReferencePath(
    ElementReference(5),
    EmptyReferencePath()
)

# Multiple steps (the tail must itself be a ReferencePath)
ConcreteReferencePath(
    ElementReference(1),
    ConcreteReferencePath(FieldReference("name"), EmptyReferencePath())
)
```

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
- `i` — binder, captures the value
- `"name"` or `0` — literal, matches specific value
- `i::Int` — typed binder, captures with type check
- `path...` — matches prefix and binds remaining tail
- `{s:e}` — range pattern, matches any `RangeReference` (positions are
  `RangeReference(k, k)`, so `{s:e}` will also match a position; list
  more specific `{k}` patterns first if both are interesting)

The `@reference_case` macro is commonly used in projection readers to translate output-domain references back to input-domain references.

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
