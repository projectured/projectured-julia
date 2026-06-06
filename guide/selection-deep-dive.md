# Reference and Selection — Deep Dive

This document explains the full reference/selection mechanism: what a reference
is, how it is stored recursively across document nodes, how the printer projects
it forward, and how the reader translates it backward. For a gentler
introduction see [§4 Selection in the concepts guide](concepts.md).

---

## 1. What a reference is

A **reference** is a path-like pointer into a document tree — a sequence of
typed *steps*, each one descending one level. A reference may identify a cursor
position for editing, a highlighted region, a focused sub-document, or any
other designated point of interest.

A **selection** is a specific use of a reference: the path stored in a
document's `selection::Cell` that identifies the currently focused position.

Reference steps:

| Type | Meaning |
|---|---|
| `ElementReference(k)` | Alias for `RangeReference(k-1, k)` — descend to the k-th child (1-based) |
| `PositionReference(k)` | Alias for `RangeReference(k, k)` — zero-width cursor at boundary k (0-based) |
| `FieldReference(name)` | Descend into the named field of the current node |
| `ProjectionReference(p, inner)` | Points to something introduced by projection `p`; `inner` locates it within `p`'s output |

Paths are represented as an immutable linked list so that sharing and extending
a path costs no copying:

```julia
abstract type ReferencePath end
struct EmptyReferencePath <: ReferencePath end
struct ConcreteReferencePath <: ReferencePath
    head::Cell   # holds a ReferenceStep
    tail::Cell   # holds the next ReferencePath
end
```

`EmptyReferencePath` terminates the list. Both fields of
`ConcreteReferencePath` are `Cell`s so the path is reactive — a computed cell
can depend on a path's content.

---

## 2. The document contract

Only types that subtype `Document` participate in the selection mechanism.
Every concrete `Document` **must** carry a `selection::Cell` field that holds
the `ReferencePath` *relative to this node* — the suffix of the full path
starting at this level.

The invariant: **every child reached by a step in the path must itself be a
`Document`**. Collections that appear in a document tree must be wrapped in a
`Document` type with their own `selection` field.

---

## 3. Recursive storage: `set_selection!`

When the editor applies a `ReplaceSelectionOperation` it calls:

```julia
set_selection!(document, new_path)
```

The generic implementation in `Reference.jl` walks the path step by step:

1. If `path` is `EmptyReferencePath`, stop.
2. Read the head step `h = path.head[]`.
3. Navigate to the child document:
   - `FieldReference(name)` → `getfield(document, Symbol(name))`, unwrapping a `Cell` transparently.
   - `ElementReference(k)` → `document[k]` (1-based).
   - `PositionReference(k)` → cursor position, does not navigate into a child.
   - `ProjectionReference` → stop; does not navigate into a child.
4. Write `path.tail[]` into the child's `selection` cell.
5. Recurse: `set_selection!(child, path.tail[])`.

`SyntaxNode` provides a specialised override that additionally clears the
`selection` on every *other* child before setting the selected one, ensuring
stale selection state does not linger on siblings.

**Example** — `JsonObject` with path `[1] + .value + .value + {3}` (first
entry's value string, cursor at offset 3):

```
JsonObject.selection[]              ← [1] + .value + .value + {3}
  └─ entries[1] (JsonObjectEntry).selection[]  ← .value + .value + {3}
       └─ value (JsonString).selection[]       ← .value + {3}
```

---

## 4. Selection stored in each domain type

| Type | `selection` meaning |
|---|---|
| `JsonNull` / `JsonBool` / `JsonNumber` / `JsonString` | Path within this primitive — typically `.value + {k}` for cursor at offset `k` in the value |
| `JsonArray` | `[i] + <child path>` — into element `i` (1-based) |
| `JsonObjectEntry` | `.key + {k}` (cursor in key) or `.value + <child path>` |
| `JsonObject` | `[i] + <entry path>` — into entry `i` (1-based) |
| `SyntaxLeaf` | `.open/.value/.close + {k}` — cursor at offset `k` in the named span |
| `SyntaxNode` | `[i] + <child path>` — into child `i`; or `.open/.close + {k}` for delimiter |
| `Text` | `{k}` — flat cursor at offset `k` in the concatenated spans |

`GraphicsText`, `GraphicsRect`, and `GraphicsCanvas` are **not** selectable
containers. They are terminal output; the selection mechanism does not enter them.

---

## 5. How the printer projects the selection

Every `projection_print` method maps both the input *content* and the input
*selection* forward. The selection mapping is expressed as a **computed cell**
so it updates reactively whenever the input selection changes:

```julia
# SyntaxLeafToText — excerpt
function projection_print(::SyntaxLeafToText, leaf::SyntaxLeaf, ...)
    sel = Cell(() -> begin
        c = _leaf_cursor(leaf)   # reads leaf.selection[] as a dependency
        c < 0 ? nothing : ConcreteReferencePath(PositionReference(c))
    end)
    SimpleIoMap(p, leaf, Text(Cell(...spans...), sel))
end
```

`_leaf_cursor` translates a `SyntaxLeaf`-domain path into a flat character
offset:

| Leaf selection | Flat offset |
|---|---|
| `.open + {k}` | `k` |
| `.value + {k}` | `open_len + k` |
| `.close + {k}` | `open_len + value_len + k` |
| `ProjectionReference(p, .open + {k})` | `k` |
| `ProjectionReference(p, .close + {k})` | `open_len + value_len + k` |

The key point: **the selection is not passed as a parameter through
`projection_print`** — it is wired reactively. The output document's
`selection` cell reads from the input document's `selection` cell as a computed
dependency.

---

## 6. How the reader translates the selection

The reader chain walks right-to-left, translating a `ReplaceSelectionOperation`
from the output domain back to the input domain at each step.

**`TextToGraphics`** (outermost reader):
- Receives a raw key event (`KeyDown(:right, ...)`).
- Reads the current flat cursor offset from `iomap.input.selection[]`.
- Produces `ReplaceSelectionOperation({new_pos})` in Text domain.

**`SyntaxLeafToText`**:
- Receives `ReplaceSelectionOperation({pos})`.
- Partitions `pos` against `open_len` and `open_len + value_len`.
- Returns one of `.open + {pos}`, `.value + {pos - open_len}`, or `.close + {pos - close_start}`.

**`SyntaxNodeToText`**:
- Receives `ReplaceSelectionOperation({flat_pos})`.
- Calls `_pos_to_selection` which walks the tree accounting for all structural
  characters to locate the owning child and its local offset.
- Returns `[child_i] + <recursive child path>`. Positions on structural
  characters become `ProjectionReference(p, {flat_pos})`.

**`JsonStringToSyntaxLeaf`** (innermost reader):
- `.value + {k}` → passes through as `{k}`.
- `.open + {k}` / `.close + {k}` → wraps in `ProjectionReference` (delimiter
  has no counterpart in the JSON domain).

The final operation is applied by the editor:
```julia
clear_selection!(document)
set_selection!(document, op.path)
```

---

## 7. The shared-cell shortcut

For a simple single-leaf pipeline (`JsonString → SyntaxLeaf → Text`), the
printer passes the *same* `selection::Cell` object through all three levels.
All three objects reference the same `Cell` instance. Writing
`doc.selection[] = op.path` is immediately visible at every level — the cursor
redraws on the next frame without any additional wiring.

This shortcut is valid only for *leaf-to-leaf* projections where the input and
output selection formats are identical. For compound projections that recurse
into children the formats differ across domains (see §8 below).

---

## 8. Selection projection under recursion

When a compound projection recurses into children (calling
`projection_print(recursion, child, recursion)` for each element), the output
document's selection must be computed via a three-step algorithm, not by passing
the input suffix directly:

**Step 1 — Recurse first, collect child IO maps.**
```julia
child_iomaps = Cell(() -> [projection_print(recursion, child, recursion)
                            for child in elements])
```

**Step 2 — Find the child pointed to by the input selection.**
Inspect the head of `input.selection[]` to determine which child (index `i`)
the input selection designates. Strip the projection-owned prefix steps.

**Step 3 — Extend the child's output selection.**
```julia
sel = Cell(() -> begin
    path = input.selection[]
    # strip projection-owned prefix steps → extract child index i
    iomaps = child_iomaps[]
    (i + 1 > length(iomaps)) && return nothing
    child_sel = iomaps[i + 1].output.selection[]
    child_sel === nothing && return nothing
    ConcreteReferencePath(ElementReference(Cell(i)), child_sel)
end)
```

**Why the naïve approach is wrong.**
A naïve implementation strips the projection's prefix and passes the remaining
tail as the output selection:
```julia
sel = Cell(() -> input.selection[].tail[])   # ← WRONG
```
This is incorrect because the tail is a path in the **input domain** (e.g.
`{3}` for a `JsonString` cursor offset). The output child lives in the
**output domain** (e.g. a `SyntaxLeaf`) and its `selection` must hold an
output-domain path (e.g. `.value + {3}`). Passing the input tail bypasses the
child projection's selection mapping entirely.

**Why child IO maps must be shared.**
Both the children `Cell` and the selection `Cell` must call
`projection_print` on the same children. Computing them in two separate cells
would instantiate different output document objects, breaking the identity
invariant that the selection cell reads from the same document the children
cell exposes. The child IO maps must be computed in a single shared reactive
`Cell`.

**Concrete example — `JsonArrayToSyntaxNode`.**
Input: `JsonArray` with `selection[] = .elements + [2] + .value + {5}`.

1. Recurse → `child_iomaps[2]` holds the projected second element.
2. Strip `.elements`, read `[2]` → child index `i = 2`; element selection `.value + {5}`.
3. Map the element forward → `.value + {5}` (Syntax domain).
4. Prepend `[2]` → output selection = `[2] + .value + {5}`.

**Concrete example — `JsonObjectToSyntaxNode`.**
Input: `JsonObject` with `selection[] = .entries + [1] + .value + .value + {4}`.

1. Recurse per-entry → `pair_iomaps[1]` holds the projected first entry's pair node.
2. Strip `.entries`, read `[1]` → entry index `i = 1`; entry selection `.value + .value + {4}`.
3. Map the entry forward → `[2] + .value + {4}` (Syntax domain, value child is index 2).
4. Prepend `[1]` → output selection = `[1] + [2] + .value + {4}`.

---

## 9. Selection path conventions by domain

`[i]` is the i-th item (1-based), `{k}` is the cursor at boundary `k`
(0-based). See [the reference guide](editor/reference.md) for the full
reference grammar.

| Domain | Path form | Meaning |
|---|---|---|
| `Text` | `{k}` | cursor at offset `k` in the flat span sequence |
| `SyntaxLeaf` | `.value + {k}` | cursor at offset `k` in the value span |
| `SyntaxLeaf` | `.open + {k}` | cursor in the opening delimiter |
| `SyntaxLeaf` | `.close + {k}` | cursor in the closing delimiter |
| `SyntaxNode` | `[i] + <child path>` | into child `i` |
| `SyntaxNode` | `.open + {k}` / `.close + {k}` | cursor in delimiter span |
| `SyntaxNode` | `ProjectionReference(p, {k})` | projection-introduced whitespace |
| `JsonString` | `.value + {k}` | cursor in the string value |
| `JsonString` | `ProjectionReference(p, .open + {k})` | cursor on `"` opening quote |
| `JsonString` | `ProjectionReference(p, .close + {k})` | cursor on `"` closing quote |
| `JsonArray` | `[i] + <element path>` | into element `i` |
| `JsonObject` | `[i] + .value + <value path>` | into the value of entry `i` |
| `JsonObject` | `[i] + .key + {k}` | cursor in the key string of entry `i` |
