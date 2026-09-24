# Selection

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Selection is the mechanism that tracks the current cursor position or focused
region within a document — kernel layer 12, `SelectionModule`. A **selection**
is a specific use of a *reference*: the [`Reference`](reference.md) stored in
a document's `selection` cell that identifies the currently focused position.
Every `Document` carries a `selection` field, and the writers canonicalize and
validate every path they store there, so a document's `selection` cell always
holds a path that matches the live document or is empty.

This page is the single home for how selection is **stored, read, written, and
projected**: the selection contract, the read/set/clear/replace operations and
the atomicity and canonicalization they share, dormant selections, how the
printer forward-projects the selection, how the reader translates it backward,
and the recursion algorithm that ties them together. For the reference
*grammar* — step types, the boundary axis, the `@reference` /
`@reference_case` DSLs, type checkpoints — see the sibling
[reference guide](reference.md); this page cross-links to it rather than
restating the vocabulary. For a gentler introduction see
[§4 Selection in the concepts guide](../../design/concepts.md).

## The selection layer

`SelectionModule` ([source/kernel/selection/](../../../source/kernel/selection/))
is two fragments that share its namespace: `SelectionInterface.jl` declares the
generics documents override and callers dispatch on, and `SelectionDefaults.jl`
holds their default implementations — reading and writing the conventional
`document.selection` field — plus the private path-walking helpers
(`_selection_child`, `_set_selection_walk!`, `_sync_selection!`,
`_mutate_terminal_step!`) they share. It sits above the reference layer (8) and
the document layer (7): a selection's payload is a `Reference` stored on a
`Document`.

## The document contract

Only types that subtype `Document` participate in the selection mechanism.
Every concrete `Document` **must** carry a `selection` field. The field holds
either a `Reference` *relative to this node* — the suffix of the full path
starting at this level — or, on a document that keeps a selection it is not
currently acting on, a [`SelectionDocument`](#dormant-selections) wrapping one.
`@document` injects this field automatically; see [macros.md](macros.md#document).

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

## Reading, setting, and clearing selection

### Reading selection

`get_selection(document)` answers the document's current selection — a
`Reference`, or `nothing` when the document holds none. It reads the
conventional `selection` field; a document that stores its selection
unconventionally overrides it. It answers `nothing` for a *dormant* selection
(see below) — a caller that must see a dormant path too calls
`get_stored_selection` instead.

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
path = Reference(FieldReferenceStep("name"), PositionReferenceStep(5))
set_selection!(document, path)
```

`set_selection!` first **canonicalizes** `path` against `document`: it strips
the path to its plain navigation skeleton and re-annotates it so every node
records the `typeof` of the document it stands on (see
[type checkpoints](reference.md#type-checkpoints-and-replay-validity)). It then
**validates** the canonical path — every field, element index, and folded node
type along the way must still resolve — before writing anything. A path that
does not match `document` throws [`SelectionMismatchException`](#dormant-selections)
and leaves the stored selection untouched: a selection either matches and
applies, or fails without a half-written cell. On a match, the writer descends
the path, storing each suffix into the matching child's `selection` field.

**Important:** `set_selection!` does *not* clear the old selection first. If the
old selection path branches from the new one, selection fragments may be left
behind in parts of the document tree, leaving multiple selections alive
simultaneously — usually not what you want. Use `replace_selection!` when that
matters.

**Example** — `JsonObject` with path `[1] + .value + .value + {3}` (first
entry's value string, cursor at offset 3):

```
JsonObject.selection[]                         ← [1] + .value + .value + {3}
  └─ entries[1] (JsonObjectEntry).selection[]  ← .value + .value + {3}
       └─ value (JsonString).selection[]       ← .value + {3}
```

### Replacing selection

To change the selection from one location to another without leaving fragments
behind, use `replace_selection!`. Like `set_selection!`, it canonicalizes and
validates `path` first, atomically. Where `set_selection!` leaves the old
branch in place, `replace_selection!` also removes it — but not by clearing
every selection cell and rebuilding them: it writes the new path into the
**shared selection chain in place**, touching only the cells whose content
actually changed.

```julia
replace_selection!(document, new_path)
```

A caret move within one leaf mutates only that step's `start`/`stop` cells (the
terminal `RangeReferenceStep`'s bounds are themselves cells, shared across every
level the path passes through), leaving every routing ancestor's `selection`
cell untouched — so redrawing after a caret move repaints only the caret, not
every node between it and the root. Where the new path structurally diverges
from the old one, the old branch below the divergence is cleared — or, on a
document that keeps a dormant selection (see below), marked dormant instead —
and the new suffix is installed from the divergence point down. Use it when the
user navigates to a new location, or when the document structure has changed
and old selection paths may no longer be valid.

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

### Writing from outside a gesture

`PAR-SELECTION-WRITTEN-AT-ROOT` in
[architecture-invariants.md](../../rule/architecture-invariants.md#par-selection-written-at-root)
says that every write of the live selection starts at the root document, and
that a reader reads only its own `selection`, never searching the documents
below it for one. A gesture already reaches the root this way: each reader on
the way out lifts the operation, rerooting it or mapping an index back, as it
carries an answer up the chain.

Code that changes the selection without a gesture reaches the root in one of
two ways:

- **A verb** makes its edit where it already stands, at the document it
  holds — a pane tree, say — and carries the edit to the root through the
  readers of the editor with `read_rooted_operation`, which returns the
  operation rooted at the editor's document without evaluating it; see
  [editor.md](editor.md#an-operation-from-a-place-not-a-gesture).
- **A builder that wraps a document in a new root** lifts the selection the
  inner document already holds onto the wrapper, so the new root holds the
  same path the old one did: it reads the inner selection with
  `get_selection`, prepends the wrapper's own field step to it with
  `concat_references`, and writes the result with `replace_selection!` on the
  wrapper. `make_clipboard_document`, `make_window_shell_document` and
  `make_window_scene` each do this for the document they wrap.

A dormant selection is not the live selection, so this rule does not apply to
it: the document that keeps one off the live path keeps it where it is.

## Dormant selections

A document normally holds either a live selection or none. Some documents —
`PaneGroup`/`PaneTab`/`PaneSplit`, `WidgetTabbedPane`/`WidgetTabPage`/`WidgetSplitPane`
— hold their alternatives as siblings and show only one at a time; the tab or
pane a document is *not* currently showing would otherwise forget what was
selected in it every time the focus moves away. `has_dormant_selection(document)`
answers `true` for such a document (`false` by default), and asks the writers to
**keep** the losing branch's selection instead of clearing it, marked
**dormant**: still stored, still drawable, but not acted on. A `ConversationDraft`
answers `true` too, so a person who leaves the draft finds its caret where it was.

The kept path is wrapped in a `SelectionDocument(primary; live)`, the value a
`selection` field holds when it is dormant. Reading the field the ordinary way
(`document.selection`) answers `nothing` while it is dormant — every reader
written against a bare reference stays correct without change, and only code
that reads the document itself directly sees the dormant state:

- `get_stored_selection(document)` — the path, live or dormant.
- `is_live_selection(document)` — whether the stored path (if any) is the live one.
- `map_selection_forward(source, map)` — a printer's forward-projection helper
  (see below): maps the stored path through `map` and carries the live/dormant
  state onto the image, so a projected output node can draw a dormant selection
  pale instead of dropping it.

When the focus returns to a document with a dormant selection, the next
`set_selection!`/`replace_selection!` through it makes the branch live again by
extending the incoming path with the dormant one it finds at the point the two
diverge.

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
| `TextBlock` | `{k}` — flat cursor at offset `k` in the concatenated spans |

`GraphicsText`, `GraphicsRect`, and `GraphicsCanvas` are **not** selectable
containers. They are terminal output; the selection mechanism does not enter
them. The full per-domain path/step tables live in the
[reference guide](reference.md#mapping-between-document-structs-and-reference-steps).

## Forward-projecting selection

The selection lives on the **document root** as a complete path from that root
(e.g. `.editing_page.elements[3].content.entries[1].value.value{2}`).
`set_selection!` stores the suffix of that path at every node along the way, so
each *domain* node holds where the selection is relative to itself.

A projection's **printer** carries that knowledge across into the projected
(output) tree. Every `print_document` method maps both the input *content* and
the input *selection* forward, and the selection mapping is expressed as a
**computed cell** so it updates reactively whenever the input selection changes:
when the printer builds an output node, it wires the node's `selection` cell to
`map_selection_forward(input, path -> ...)`, not to a bare property read — a
property read answers `nothing` for a [dormant](#dormant-selections) selection,
so a bare read would silently drop the dormant state at the first hop.
`map_selection_forward` reads the stored path (live or dormant) and passes it
through the supplied `map` (normally built from `map_reference_forward`),
carrying the live/dormant flag onto the result. Do this at every level and the
whole projected tree carries the forward-projected selection, exactly
mirroring how `set_selection!` distributes it across the domain tree.

The key point: **the selection is not passed as a parameter through
`print_document`** — it is wired reactively. `CopyingProjection` does this
generically; compound projections that introduce structure (e.g.
`PaneToWidget`, whose tree stage wraps the printed layout in a `WidgetComposite`
that has no domain counterpart) wire the selection cells explicitly in
`print_document`.

A leaf printer illustrates the reactive wiring (`source/syntax/SyntaxToText.jl`,
the projection from a `SyntaxLeaf` to a `TextBlock`):

```julia
# The printer is always 4-arg: print_document(projection, recursion, input, ctx::PrinterContext)
function print_document(p::SyntaxLeafToText, recursion, leaf::SyntaxLeaf, ctx)
    sel = Cell(@computation(map_selection_forward(leaf, path -> begin
        leaf_sel = strip_reference_types(path)
        leaf_sel isa EmptyReference && return @reference()
        c = _leaf_cursor(leaf)                          # leaf-domain path → flat offset
        c < 0 ? nothing : _flat_to_text_elem_path(_leaf_spans(leaf), c)   # flat offset → TextBlock path
    end)))
    SimpleIoMap(p, leaf, TextBlock(CellVector(@computation _leaf_spans(leaf)), sel))
end
```

`_leaf_cursor` translates a `SyntaxLeaf`-domain path into a flat character
offset:

| Leaf selection | Flat offset |
|---|---|
| `.open + {k}` | `k` |
| `.value + {k}` | `open_len + k` |
| `.close + {k}` | `open_len + value_len + k` |
| `ProjectionReferenceStep(p, .open + {k})` | `k` |
| `ProjectionReferenceStep(p, .close + {k})` | `open_len + value_len + k` |

`_flat_to_text_elem_path` then turns that flat offset into the `TextBlock`-domain
path (which of the concatenated spans, and the offset inside it) that
`{k}` addresses. The output document's `selection` cell reads from the input
document's `selection` cell as a computed dependency, so an edit that moves the
caret propagates without either side polling the other.

### Selection-directed event routing

Once every output node carries the forward-projected selection, a **reader** can
consult its node's `selection` to decide which child to forward an event to —
instead of broadcasting to every child and hoping the focused one answers. This
is the usual desired behavior: a key event should be delivered to the child the
selection points at.

For example, in the widget tree the pane tree projects to:

- a `WidgetSplitPane` reads its `selection` head (`elements[slot].child.…`) and
  forwards a keystroke only into `slot` (`_selected_split_slot` /
  `_forward_split_event_slot`);
- a `WidgetTabbedPane` makes its *active tab* the one the selection names
  (`selector_element_pairs[i].…`), so the focused document tab follows the
  selection and receives key events (`_tab_index_from_selection`).

A node with no selection (e.g. a split pane built outside the pane tree, where
nothing forward-projects onto it) falls back to forwarding to each child in
turn. Mouse events still hit-test by coordinate rather than following the
selection — the selection only directs *coordless* events such as keystrokes.

## How the reader translates the selection backward

The reader chain walks right-to-left, threading an
[`Intent`](projection-system.md#the-intent-the-reader-threads) (gesture +
operation) and translating its `ReplaceSelectionOperation` from the output
domain back to the input domain at each step. Each reader is the 4-arg
`read_intent(p, recursion, change::Intent, iomap) → Intent`; the `gesture` passes
through unchanged while the `operation` is re-mapped one domain inward. Most steps
need no `read_intent` method at all: the default re-targets a
`ReplaceSelectionOperation`'s path via `map_reference_backward`. The steps below
spell out the path translation each one's mapper performs.

**`TextToGraphics`** (outermost reader):
- The `Intent.gesture` is a raw key event (`KeyDown(:right, ...)`).
- Reads the current flat cursor offset from `iomap.input.selection[]`.
- Produces `ReplaceSelectionOperation({new_pos})` in `TextBlock` domain.

**`SyntaxLeafToText`**:
- Receives `ReplaceSelectionOperation({pos})`.
- Partitions `pos` against `open_len` and `open_len + value_len`.
- Returns one of `.open + {pos}`, `.value + {pos - open_len}`, or `.close + {pos - close_start}`.

**`SyntaxCompoundToText`**:
- Receives `ReplaceSelectionOperation({flat_pos})`.
- Its `map_reference_backward` locates the output element the flat offset lands
  on and classifies it into a zone: inside a child's own rendered range, on the
  node's open/close delimiter, or on other own chrome (a separator, an indent,
  an ellipsis).
- A child-zone position delegates to that child's own mapper and prepends
  `.children[i]`; a delimiter position becomes `.open + {k}` / `.close + {k}`;
  any other own-chrome position becomes a projection-introduced
  `ProjectionReferenceStep(p, {flat_pos})`, since it has no counterpart in the
  input domain.

**`JsonStringToSyntaxLeaf`** (innermost reader):
- `.value + {k}` → passes through as `{k}`.
- `.open + {k}` / `.close + {k}` → wraps in `ProjectionReferenceStep` (the delimiter
  has no counterpart in the JSON domain).

The final, fully backward-mapped `ReplaceSelectionOperation` reaches the input
document unchanged (`evaluate_operation(editor, op::ReplaceSelectionOperation)`
calls `replace_selection!(editor.document, op.path)`) — the same atomic,
in-place writer described above.

## The shared-cell shortcut

For a simple single-leaf pipeline (`JsonString → SyntaxLeaf → TextBlock`), the
printer passes the *same* `selection::Cell` object through all three levels. All
three objects reference the same `Cell` instance, so writing
`doc.selection[] = op.path` is immediately visible at every level — the cursor
redraws on the next frame without any additional wiring.

This shortcut is valid only for *leaf-to-leaf* projections where the input and
output selection formats are identical. For compound projections that recurse
into children the formats differ across domains, and the three-step algorithm
below is required.

## Selection projection under recursion

A projection written with [`@projection_template`](macros.md#projection_template)
gets this for free: its `collection(:field)` and `project(:field)` markers wire
the child recursion and the selection mapping together generically. What
follows is the algorithm every such marker runs, needed by hand only for a
projection the template does not fit.

When a compound projection recurses into children (calling
`print_child(recursion, child, child_ctx)` for each element), the output
document's selection must be computed via a three-step algorithm, not by passing
the input suffix directly:

**Step 1 — Recurse first, collect child IO maps.**

```julia
child_iomaps = Cell(@computation([print_child(recursion, child,
                                        make_child_context(ctx, ElementReferenceStep(i)))
                            for (i, child) in enumerate(elements)]))
```

**Step 2 — Find the child pointed to by the input selection.**
Inspect the head of `input.selection[]` to determine which child (index `i`) the
input selection designates. Strip the projection-owned prefix steps.

**Step 3 — Extend the child's output selection.**

```julia
sel = Cell(@computation(begin
    path = input.selection[]
    # strip projection-owned prefix steps → extract child index i
    iomaps = child_iomaps[]
    (i + 1 > length(iomaps)) && return nothing
    child_sel = iomaps[i + 1].output.selection[]
    child_sel === nothing && return nothing
    ConcreteReference(ElementReferenceStep(i), child_sel)
end))
```

**Why the naïve approach is wrong.** A naïve implementation strips the
projection's prefix and passes the remaining tail as the output selection:

```julia
sel = Cell(@computation input.selection[].tail[])   # ← WRONG
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

**Concrete example — `JsonArrayToSyntaxNode`** (written with
`@projection_template` as `SyntaxNode(collection(:elements); …)`; the steps
below are what the `collection` marker runs for it).
Input: `JsonArray` with `selection[] = .elements + [2] + .value + {5}`.

1. Recurse → `child_iomaps[2]` holds the projected second element.
2. Strip `.elements`, read `[2]` → child index `i = 2`; element selection `.value + {5}`.
3. Map the element forward → `.value + {5}` (Syntax domain).
4. Prepend `[2]` → output selection = `[2] + .value + {5}`.

**Concrete example — `JsonObjectToSyntaxNode`** (likewise template-driven).
Input: `JsonObject` with `selection[] = .entries + [1] + .value + .value + {4}`.

1. Recurse per-entry → `pair_iomaps[1]` holds the projected first entry's pair node.
2. Strip `.entries`, read `[1]` → entry index `i = 1`; entry selection `.value + .value + {4}`.
3. Map the entry forward → `[2] + .value + {4}` (Syntax domain, value child is index 2).
4. Prepend `[1]` → output selection = `[1] + [2] + .value + {4}`.

## ProjectionReferenceStep in selection

When the cursor is on a projection-introduced element (like a quote delimiter),
the selection path includes a `ProjectionReferenceStep` step. This lets the editor
represent positions that do not exist in the underlying document. See
[input and output references](reference.md#input-and-output-references) for how
that step embeds an output-domain path inside an input-domain reference.

## Key features

- Recursive storage, one path suffix per node, so every level holds its own
  selection without walking from the root.
- Canonicalization and atomic validation on every write: a stale or
  cross-domain path throws `SelectionMismatchException` before any cell changes.
- An in-place writer (`replace_selection!`) that repaints only what changed,
  down to mutating a caret's own start/stop cells for a same-leaf move.
- Dormant selections, so a tab or pane not currently shown keeps what was
  selected in it.
- Domain-specific path semantics over one common `[i]` / `{k}` / `.field` grammar.
- Support for projection-introduced elements, via `ProjectionReferenceStep`.
