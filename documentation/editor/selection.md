# Selection

Selection is the mechanism that tracks the current cursor position or focused region within a document. Every Document carries a `selection::Cell` that holds a ReferencePath relative to that node.

## The Selection Contract

Every concrete `Document` type must have a `selection::Cell` field. This cell holds the ReferencePath from the current node's perspective.

## Selection Storage

Selection is stored recursively along the path:

```julia
# For a JsonObject with path [1] + .value + {3}:
JsonObject.selection[]       ← [1] + .value + {3}   (full path)
  └─ entries[1].selection[]   ← .value + {3}        (relative)
       └─ value[].selection[] ← {3}                 (relative)
```

Each node stores only the suffix of the path starting at that level.

## Setting Selection

When working with selection, you'll typically use one of three functions depending on what you need to accomplish.

### Clearing Selection

To remove the current selection entirely, use `clear_selection!`. This function recursively walks through the document and sets all selection cells to `nothing`:

```julia
clear_selection!(document)
```

This is useful when you want to deselect everything—for example, when the user presses Escape or navigates away from a focused element.

### Setting a New Selection

To set the selection to a specific location, use `set_selection!` with a reference path:

```julia
path = ReferencePath(FieldReference("name"), PositionReference(5))
set_selection!(document, path)
```

The function recursively traverses the path, setting the appropriate selection cell at each level of the document hierarchy. For instance, if you're setting a selection deep within a nested structure, `set_selection!` will update the selection at each intermediate node so that the entire path is properly tracked.

**Important:** `set_selection!` does not clear the old selection first. If the old selection path branches from the new one, selection fragments may be left behind in parts of the document tree. This can lead to multiple selections existing simultaneously, which is usually not what you want.

### Replacing Selection

When you want to change the selection from one location to another without leaving fragments behind, use `replace_selection!`. This combines clearing and setting into a single atomic operation:

```julia
replace_selection!(document, new_path)
```

Under the hood, this calls `clear_selection!` followed by `set_selection!`, ensuring that any stale selection state is completely removed before applying the new selection. Use this when you need to guarantee that only one selection exists in the document—for example, when the user navigates to a new location or when the document structure has changed and old selection paths may no longer be valid.

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

## Validating References

Before setting a selection, you can validate that a reference is valid using `is_valid_reference`:

```julia
using Projectured

# Check if a reference step is valid
is_valid_reference(PositionReference(5))  # true
is_valid_reference(FieldReference("name"))  # true
is_valid_reference("not a reference")  # false

# Check if a reference path is valid (recursively validates head and tail)
path = ReferencePath(FieldReference("address"), FieldReference("city"))
is_valid_reference(path)  # true

is_valid_reference(EmptyReferencePath())  # true
```

For `ConcreteReferencePath`, the function recursively validates that the head cell contains a valid `ReferenceStep` and the tail cell contains a valid `ReferencePath`. This ensures the entire reference chain is well-formed.

This is useful for defensive programming when working with user-provided or dynamically generated references.

## Selection by Domain

Different domains interpret selection paths differently. Throughout: `[i]` is the i-th item (1-based) and `{k}` is the cursor at boundary `k` (0-based) — two readings of the same axis (see [the boundary axis](reference.md#the-boundary-axis)). Both apply wherever there is a sequence, whether the items are elements or characters. The lines below list the most common patterns; the alternate reading (e.g. `{k}` between elements as an insertion point, or `[i]` for the i-th character) is always available.

### JSON Domain
- Primitives: `.value{k}` — cursor position (0-based, PositionReference)
- Arrays: `.elements[i]` — element access (1-based, ElementReference)
- Objects: `.entries[i]` — entry access (1-based, ElementReference)
- Entries: `.key{k}` or `.value` — key cursor position (0-based, PositionReference) or value

### XML Domain
- Elements: `.attrs[i].cell{k}` or `.cell[i]` — attribute value or child (ElementReference for element access, PositionReference for cursor positions)
- Text: `.cell{k}` — cursor position (0-based, PositionReference)
- Attributes: `.cell{k}` — cursor position in value (0-based, PositionReference)

### Text Domain
- `.elements[i].content{k}` — element access (1-based, ElementReference) and cursor position (0-based, PositionReference)

### Syntax Domain
- Leaves: `.open{k}`, `.value{k}`, `.close{k}` — cursor position in delimiters or value (0-based, PositionReference)
- Nodes: `.children[i]` — child access (1-based, ElementReference), or delimiter paths

## Shared Selection Cells

When a document is projected through multiple domains, the selection cell is shared. Changes propagate automatically through the reactive cell system:

```julia
# JsonString.selection is shared with SyntaxLeaf.selection and Text.selection
# When editor.document.selection[] is updated, all projections see the change
```

## Forward-Projecting Selection

The selection lives on the **document root** as a complete path from that root
(e.g. `.editing_page.elements[3].content.entries[1].value.value{2}`).
`set_selection!` stores the suffix of that path at every node along the way, so
each *domain* node knows where the selection is relative to itself.

A projection's **printer** carries that knowledge across into the projected
(output) tree: when it builds an output node, it wires the node's `selection`
cell to `map_reference_forward(projection, iomap, input.selection)`. Because
`map_reference_forward` is the inverse of `map_reference_backward`, the output
node ends up holding the selection suffix *in its own (output-domain)
coordinates*. Do this at every level and the whole projected tree carries the
forward-projected selection, exactly mirroring how `set_selection!` distributes
it across the domain tree. `CopyingProjection` does this generically; compound
projections that introduce structure (e.g. `WorkbenchToWidget`, whose shell
inserts split panes that have no domain counterpart) wire the selection cells
explicitly in `print_document`.

### Selection-directed event routing

Once every output node carries the forward-projected selection, a **reader**
can consult its node's `selection` to decide which child to forward an event
to — instead of broadcasting to every child and hoping the focused one
answers. This is the usual desired behavior: a key event should be delivered
to the child the selection points at.

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

## ProjectionReference in Selection

When the cursor is on a projection-introduced element (like a quote delimiter), the selection path includes a `ProjectionReference` step. This allows the editor to represent positions that don't exist in the underlying document.

## Key Features

- Recursive storage for efficient updates
- Shared cells for automatic propagation
- Domain-specific path semantics
- Support for projection-introduced elements
