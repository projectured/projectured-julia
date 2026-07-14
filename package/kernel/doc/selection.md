# Selection

Selection is the mechanism that tracks the current cursor position or focused
region within a document. A **selection** is a specific use of a *reference*:
the [`ReferencePath`](reference.md) stored in a document's `selection::Cell`
that identifies the currently focused position. Every `Document` carries a
`selection::Cell` holding the path relative to that node.

This page is the single home for how selection is **stored, propagated, and
projected**: the selection contract, the set/clear/replace operations, how the
printer forward-projects the selection, how the reader translates it backward,
and the recursion algorithm that ties them together. For the reference
*grammar* — step types, the boundary axis, the `@reference` /
`@reference_case` DSLs, type checkpoints — see the sibling
[reference guide](reference.md); this page cross-links to it rather than
restating the vocabulary. For a gentler introduction see
[§4 Selection in the concepts guide](../../../documentation/concepts.md).

## The document contract

Only types that subtype `Document` participate in the selection mechanism.
Every concrete `Document` **must** carry a `selection::Cell` field that holds the
`ReferencePath` *relative to this node* — the suffix of the full path starting
at this level.

The invariant: **every child reached by a step in the path must itself be a
`Document`**. Collections that appear in a document tree must be wrapped in a
`Document` type with their own `selection` field.

## Selection storage

Selection is stored **recursively** along the path: each node stores only the
suffix of the path starting at that level.

```julia
# For a JsonObject with path [1] + .value + {3}:
JsonObject.selection[]           ← [1] + .value + {3}   (full path)
  └─ entries[1].selection[]      ← .value + {3}         (relative)
       └─ value[].selection[]    ← {3}                  (relative)
```

## Setting selection

Three functions cover the common needs, depending on what you want to
accomplish.

### Clearing selection

To remove the current selection entirely, use `clear_selection!`. It recursively
walks the document and sets all selection cells to `nothing`:

```julia
clear_selection!(document)
```

Useful when you want to deselect everything — for example, when the user presses
Escape or navigates away from a focused element.

### Setting a new selection

To set the selection to a specific location, use `set_selection!` with a
reference path:

```julia
path = ReferencePath(FieldReference("name"), PositionReference(5))
set_selection!(document, path)
```

The generic implementation in `ReferenceEvaluation.jl` walks the path step by step:

1. If `path` is `EmptyReferencePath`, stop.
2. Read the head step `h = path.head[]`.
3. Navigate to the child document:
   - `FieldReference(name)` → `getfield(document, Symbol(name))`, unwrapping a
     `Cell` transparently.
   - `ElementReference(k)` → `document[k]` (1-based).
   - `PositionReference(k)` → cursor position, does not navigate into a child.
   - `ProjectionReference` → stop; does not navigate into a child.
4. Write `path.tail[]` into the child's `selection` cell.
5. Recurse: `set_selection!(child, path.tail[])`.

So the selection at each intermediate node is updated, and the entire path stays
properly tracked. `set_selection!` also fills type checkpoints against the
document (see [type checkpoints](reference.md#type-checkpoints-and-replay-validity)),
so a document's `selection` cell always holds the canonical, folded form.

`SyntaxNode` provides a specialised override that additionally clears the
`selection` on every *other* child before setting the selected one, ensuring
stale selection state does not linger on siblings.

**Important:** the generic `set_selection!` does *not* clear the old selection
first. If the old selection path branches from the new one, selection fragments
may be left behind in parts of the document tree, leaving multiple selections
alive simultaneously — usually not what you want. Use `replace_selection!` when
that matters.

**Example** — `JsonObject` with path `[1] + .value + .value + {3}` (first
entry's value string, cursor at offset 3):

```
JsonObject.selection[]                         ← [1] + .value + .value + {3}
  └─ entries[1] (JsonObjectEntry).selection[]  ← .value + .value + {3}
       └─ value (JsonString).selection[]       ← .value + {3}
```

### Replacing selection

To change the selection from one location to another without leaving fragments
behind, use `replace_selection!`. It combines clearing and setting into a single
atomic operation:

```julia
replace_selection!(document, new_path)
```

Under the hood this calls `clear_selection!` followed by `set_selection!`,
guaranteeing any stale selection state is completely removed before the new
selection is applied. Use it when the user navigates to a new location or when
the document structure has changed and old selection paths may no longer be
valid.

### Selecting by content

When you do not already know the path — e.g. "select the string 'Alice'" — find
it with `search_references` and select the result, instead of hand-walking the
document tree:

```julia
refs = search_references(editor.document, v -> v isa JsonString && v.value == "Alice")
isempty(refs) || replace_selection!(editor.document, first(refs))
```

See the [finding-and-selecting guide](finding-and-selecting.md) for the full
search → resolve → select workflow.

## Selection stored in each domain type

Different domains interpret selection paths differently, but always as the same
`[i]` / `{k}` / `.field` grammar (see [the boundary axis](reference.md#the-boundary-axis)).
`[i]` is the i-th item (1-based) and `{k}` is the cursor at boundary `k`
(0-based); both readings apply wherever there is a sequence, whether the items
are elements or characters.

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
containers. They are terminal output; the selection mechanism does not enter
them. The full per-domain path/step tables live in the
[reference guide](reference.md#mapping-between-document-structs-and-reference-steps).

## Forward-projecting selection

The selection lives on the **document root** as a complete path from that root
(e.g. `.editing_page.elements[3].content.entries[1].value.value{2}`).
`set_selection!` stores the suffix of that path at every node along the way, so
each *domain* node knows where the selection is relative to itself.

A projection's **printer** carries that knowledge across into the projected
(output) tree. Every `print_document` method maps both the input *content* and
the input *selection* forward, and the selection mapping is expressed as a
**computed cell** so it updates reactively whenever the input selection changes:
when the printer builds an output node, it wires the node's `selection` cell to
`map_reference_forward(projection, iomap, input.selection)`. Because
`map_reference_forward` is the inverse of `map_reference_backward`, the output
node ends up holding the selection suffix *in its own (output-domain)
coordinates*. Do this at every level and the whole projected tree carries the
forward-projected selection, exactly mirroring how `set_selection!` distributes
it across the domain tree.

The key point: **the selection is not passed as a parameter through
`print_document`** — it is wired reactively. `CopyingProjection` does this
generically; compound projections that introduce structure (e.g.
`WorkbenchToWidget`, whose shell inserts split panes that have no domain
counterpart) wire the selection cells explicitly in `print_document`.

A leaf printer illustrates the reactive wiring:

```julia
# SyntaxLeafToText — excerpt. The printer is always 4-arg:
# print_document(projection, recursion, input, ctx::PrinterContext)
function print_document(p::SyntaxLeafToText, recursion, leaf::SyntaxLeaf, ctx)
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

The output document's `selection` cell reads from the input document's
`selection` cell as a computed dependency.

### Selection-directed event routing

Once every output node carries the forward-projected selection, a **reader** can
consult its node's `selection` to decide which child to forward an event to —
instead of broadcasting to every child and hoping the focused one answers. This
is the usual desired behavior: a key event should be delivered to the child the
selection points at.

For example, in the widget tree the workbench projects to:

- a `WidgetSplitPane` reads its `selection` head (`elements[slot].child.…`) and
  forwards a keystroke only into `slot` (`_selected_split_slot` /
  `_forward_split_event_slot`);
- a `WidgetTabbedPane` makes its *active tab* the one the selection names
  (`selector_element_pairs[i].…`), so the focused document tab follows the
  selection and receives key events (`_tab_index_from_selection`).

A node with no selection (e.g. a split pane built outside the workbench, where
nothing forward-projects onto it) falls back to forwarding to each child in
turn. Mouse events still hit-test by coordinate rather than following the
selection — the selection only directs *coordless* events such as keystrokes.

## How the reader translates the selection backward

The reader chain walks right-to-left, threading an
[`Intent`](projection-system.md#the-change-the-reader-threads) (gesture +
operation) and translating its `ReplaceSelectionOperation` from the output
domain back to the input domain at each step. Each reader is the 4-arg
`read_intent(p, recursion, change::Intent, iomap) → Intent`; the `gesture` rides
along unchanged while the `operation` is re-mapped one domain inward. (Most steps
need no `read_intent` method at all — the default re-targets a
`ReplaceSelectionOperation`'s path via `map_reference_backward`. The steps below
spell out the path translation each one's mapper performs.)

**`TextToGraphics`** (outermost reader):
- The `Intent.gesture` is a raw key event (`KeyDown(:right, ...)`).
- Reads the current flat cursor offset from `iomap.input.selection[]`.
- Produces `ReplaceSelectionOperation({new_pos})` in Text domain.

**`SyntaxLeafToText`**:
- Receives `ReplaceSelectionOperation({pos})`.
- Partitions `pos` against `open_len` and `open_len + value_len`.
- Returns one of `.open + {pos}`, `.value + {pos - open_len}`, or `.close + {pos - close_start}`.

**`SyntaxCompoundToText`**:
- Receives `ReplaceSelectionOperation({flat_pos})`.
- Calls `_pos_to_selection` which walks the tree accounting for all structural
  characters to locate the owning child and its local offset.
- Returns `[child_i] + <recursive child path>`. Positions on structural
  characters become `ProjectionReference(p, {flat_pos})`.

**`JsonStringToSyntaxLeaf`** (innermost reader):
- `.value + {k}` → passes through as `{k}`.
- `.open + {k}` / `.close + {k}` → wraps in `ProjectionReference` (the delimiter
  has no counterpart in the JSON domain).

The final operation is applied by the editor:

```julia
clear_selection!(document)
set_selection!(document, op.path)
```

## The shared-cell shortcut

For a simple single-leaf pipeline (`JsonString → SyntaxLeaf → Text`), the
printer passes the *same* `selection::Cell` object through all three levels. All
three objects reference the same `Cell` instance, so writing
`doc.selection[] = op.path` is immediately visible at every level — the cursor
redraws on the next frame without any additional wiring.

This shortcut is valid only for *leaf-to-leaf* projections where the input and
output selection formats are identical. For compound projections that recurse
into children the formats differ across domains, and the three-step algorithm
below is required.

## Selection projection under recursion

When a compound projection recurses into children (calling
`print_child(recursion, child, child_ctx)` for each element), the output
document's selection must be computed via a three-step algorithm, not by passing
the input suffix directly:

**Step 1 — Recurse first, collect child IO maps.**

```julia
child_iomaps = Cell(() -> [print_child(recursion, child,
                                       make_child_context(ctx, ElementReference(i)))
                           for (i, child) in enumerate(elements)])
```

**Step 2 — Find the child pointed to by the input selection.**
Inspect the head of `input.selection[]` to determine which child (index `i`) the
input selection designates. Strip the projection-owned prefix steps.

**Step 3 — Extend the child's output selection.**

```julia
sel = Cell(() -> begin
    path = input.selection[]
    # strip projection-owned prefix steps → extract child index i
    iomaps = child_iomaps[]
    (i + 1 > length(iomaps)) && return nothing
    child_sel = iomaps[i + 1].output.selection[]
    child_sel === nothing && return nothing
    ConcreteReferencePath(ElementReference(i), child_sel)
end)
```

**Why the naïve approach is wrong.** A naïve implementation strips the
projection's prefix and passes the remaining tail as the output selection:

```julia
sel = Cell(() -> input.selection[].tail[])   # ← WRONG
```

This is incorrect because the tail is a path in the **input domain** (e.g. `{3}`
for a `JsonString` cursor offset). The output child lives in the **output
domain** (e.g. a `SyntaxLeaf`) and its `selection` must hold an output-domain
path (e.g. `.value + {3}`). Passing the input tail bypasses the child
projection's selection mapping entirely.

**Why child IO maps must be shared.** Both the children `Cell` and the selection
`Cell` must call `print_document` on the same children. Computing them in two
separate cells would instantiate different output document objects, breaking the
identity invariant that the selection cell reads from the same document the
children cell exposes. The child IO maps must be computed in a single shared
reactive `Cell`.

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

## Shared selection cells

When a document is projected through multiple domains, the selection cell is
shared. Changes propagate automatically through the reactive cell system:

```julia
# JsonString.selection is shared with SyntaxLeaf.selection and Text.selection
# When editor.document.selection[] is updated, all projections see the change
```

## ProjectionReference in selection

When the cursor is on a projection-introduced element (like a quote delimiter),
the selection path includes a `ProjectionReference` step. This lets the editor
represent positions that do not exist in the underlying document. See
[input and output references](reference.md#input-and-output-references) for how
that step embeds an output-domain path inside an input-domain reference.

## Key features

- Recursive storage for efficient updates
- Shared cells for automatic propagation across projections
- Domain-specific path semantics over one common grammar
- Support for projection-introduced elements
