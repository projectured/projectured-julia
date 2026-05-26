# JSON Domain

The JSON domain represents JSON data as a tree of reactive documents. Every JSON value is a Document with all mutable fields wrapped in reactive Cells for automatic change propagation.

**Indexing conventions**: paths use `[i]` for the i-th item (1-based) and `{k}` for the cursor at boundary `k` (0-based). The two are readings of the same axis — see [the boundary axis](../editor/reference.md#the-boundary-axis). In JSON the axis appears as array elements, object entries, *and* characters in strings/numbers; `[1]` is the first item in any of those, `{0}` the cursor before it.

## Types

- **Primitives**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString` — hold single values
- **Compounds**: `JsonArray`, `JsonObject`, `JsonObjectEntry` — hold collections of values

## Examples

```julia
# Create a JSON string
str = JsonString("hello")

# Create a JSON number
num = JsonNumber(42)

# Create a JSON array
arr = JsonArray([JsonString("a"), JsonNumber(1), JsonBool(true)])

# Create a JSON object
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))

# Access values
str.value[] = "world"  # reactive update
arr.elements[1][] = JsonString("b")
```

## Reference Paths

Reference paths point into specific locations within a JSON document tree. See @reference for the full type definitions. Each path is a linked list of `FieldReference`, `ElementReference` (1-based for element access), and `PositionReference` (0-based for cursor positions) steps that mirror the struct field layout.

### Primitives — cursor position (0-based)

```julia
# Cursor at position 3 inside JsonString("hello") (0-based)
@reference value{3}
```

### Arrays — element access (1-based)

```julia
arr = JsonArray([JsonString("a"), JsonNumber(42), JsonBool(true)])

# Element 2 (the JsonNumber) - 1-based indexing
@reference elements[2]

# Cursor at position 1 inside element 2's rendered value - 0-based
@reference elements[2].value{1}
```

### Objects — entry access (1-based)

```julia
obj = JsonObject("name" => JsonString("Alice"), "age" => JsonNumber(30))

# Entry 1 (the "name" entry) - 1-based indexing
@reference entries[1]

# Cursor at position 2 inside the key of entry 1 - 0-based
@reference entries[1].key{2}

# The value document of entry 1
@reference entries[1].value

# Cursor at position 4 inside the value of entry 1 - 0-based
@reference entries[1].value.value{4}
```

### Nested documents

```julia
# Given: {"people": [{"name": "Alice"}]}
# Point to cursor position 3 of "Alice":
@reference entries[1].value.elements[1].entries[1].value.value{3}
#          ──────────╴people entry (1-based)
#                     ─────╴the JsonArray element (1-based)
#                           ────────────╴{"name": "Alice"}
#                                        ──────────╴"name" entry (1-based)
#                                                    ─────╴JsonString("Alice")
#                                                          ────────╴cursor position 3 (0-based)
```

## Selection

Each JSON value has a `selection::Cell` that holds a ReferencePath. Both readings of the boundary axis are available everywhere: `.elements[i]` / `.entries[i]` / `.value[i]` selects the i-th item (1-based); `.elements{k}` / `.entries{k}` / `.value{k}` is the cursor at boundary `k` (0-based) — between elements/entries (an insertion point) or between characters.

## Collapsed and indentation fields

`JsonArray`, `JsonObject`, and `JsonObjectEntry` each carry a `collapsed::Bool` field (default `false`). When `true`, the projection renders the value on a single line instead of expanding it. This field is directly settable:

```julia
arr.collapsed = true   # render array inline
obj.collapsed = true   # render object inline
```

## Key Features

- All fields are reactive Cells for automatic dependency tracking
- Structural changes (insert/delete) only invalidate affected containers
- Selection mechanism works through the projection pipeline
