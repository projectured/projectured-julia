# SyntaxToWidget Projection

Render structured domains (DbCatalog, JSON, XML, …) through a widget-based
pipeline so each element gains per-element visual framing and interactive
affordances (collapse today; tooltips, buttons, badges later) without
reimplementing text layout.

```
Domain → Syntax → Widget → Graphics
         ^^^^^^   ^^^^^^   ^^^^^^^^
         …ToSyntax  SyntaxToWidget  Widget+Layout+Text → Graphics
```

The text path (`SyntaxToText → TextToGraphics`) remains available; pipeline
choice is per-example configuration. A domain opts into the widget presentation
by choosing `SyntaxToWidget` downstream of its existing `…ToSyntax` projection.

**Status: implemented.** Files:
`program/src/projection/primitive/SyntaxToWidget.jl` (projection),
`test/src/projection/SyntaxToWidgetTest.jl` (tests), and JSON / XML / catalog
widget examples that wire `…ToSyntax → SyntaxToWidget → graphics`.

---

## 1  Core design: structure as widgets, content as text

A `SyntaxNode` projects to a widget *container*; a `SyntaxLeaf` projects to an
embedded `TextText` rendered by `TextToGraphics` *inside* the widget tree —
exactly how `ConversationToWidget` embeds `TextText` in a `WidgetCard`. This is
the codebase's established **widgets-for-structure / text-for-content**
composition: widgets own the chrome and framing, the Text domain owns editable
leaf rendering (cursor placement, multi-span styling), and
`TypeDispatchingProjection` dispatches both at the graphics step.

| Syntax | Widget | Notes |
|--------|--------|-------|
| `SyntaxNode`, `indentation != 0` | a collapsible `WidgetCard`: header = fold marker + open delimiter; body = the children stacked in a `VerticalLayout`, then the close delimiter | The indented/structural case. |
| `SyntaxNode`, `indentation == 0` | a single `HorizontalLayout`: open · children interleaved with separators · close | The inline case (one line). |
| `SyntaxLeaf` | embedded `TextText` (open · value · close spans) | Leaves stay `TextText` so caret/edit/styling are preserved. |
| Delimiters (`open`/`close`) / separator (`sep`) | one-span `TextText` carrying their own font/color | Rendered by `TextToGraphics` in line. |
| Collapse marker (▾/▸) / collapsed ellipsis (…) | one-span chrome `TextText` in the DejaVu mono font (which carries the glyphs) | Projection-introduced chrome. |

### Line model

The unit of layout is the *line*, mirroring the line-oriented `SyntaxToText`:

- **Vertical** (`VerticalLayout`) stacks a node's lines top-to-bottom.
- **Horizontal** (`HorizontalLayout`) lays out the inline pieces of one line.

An indented node produces one line per child (plus open/close); an inline node
is a single horizontal line. Indentation is orthogonal to widget nesting:
vertical nesting comes from the syntax tree's node containment, not from the
`indentation` hint.

### Per-level delegation (mandatory)

`SyntaxNodeToWidget` projects *one* node to *one* container and recurses every
child through `recursion` (`projection_printer_recurse`), storing the child
iomaps in a `ChildrenIoMap` — the `ConversationToWidget` shape, **not** the
self-walking `SyntaxNodeToText` shape. Because each child re-enters the
`RecursiveProjection` + `TypeDispatchingProjection` pipeline and is dispatched
by its own type, a domain can interpose a different per-type widget treatment
(e.g. a Tables node with a refresh button) without the generic projection
having consumed it.

### Collapse / expand: reader-driven, no command widget

Collapse uses the existing `ToggleCollapseOperation` and the graphics-layer
header hit-test that already lives in `WidgetCardToGraphicsCanvas`: a click on a
`WidgetCard`'s `Document` title emits `ToggleCollapseOperation(card)`.
`SyntaxToWidget` supplies only the **retargeting reader** (the
`ConversationToWidget` pattern): a `projection_read(::SyntaxNodeToWidget, iomap,
op::ToggleCollapseOperation)` that walks the stored `ChildrenIoMap`
(`_find_collapse_target`) to turn the widget target back into the owning
`SyntaxNode`, whose `collapsed` cell `evaluate_operation` then flips. No
`WidgetCommand` is required.

When collapsed, the ellipsis (and close delimiter) are appended **inline to the
header** (`▸ { … }`) and the body is emptied — the fold reads on one line with
its parent rather than on a separate line.

### Selection

- **Leaves** wire their selection forward into the embedded `TextText`
  (`open{k}`/`value{k}`/`close{k}` → `elements[{1,2,3}].content{k}`), and the
  leaf reader maps `ReplaceSelectionOperation` / value-span
  `StringReplaceRangeOperation` back to the leaf domain — *in isolation*.
- **End-to-end selection is not wired** (see §3): `SyntaxNodeToWidget`'s
  reference maps return `nothing`, so a path produced deep in the widget tree
  (a click on a leaf, routed up through the cards/layouts) is not re-rooted
  across the node levels back to the domain. Caret placement and leaf editing
  therefore do not yet round-trip through the full pipeline.

---

## 2  What the widget/layout layer gives for free

A large simplification discovered during implementation: the existing
`*LayoutToGraphicsCanvas` / `Widget*ToGraphicsCanvas` projections already handle

- **rendering** of `VerticalLayout` / `HorizontalLayout` / `WidgetCard`,
- **event routing** (hit-testing clicks/scroll to the right child),
- **reference plumbing** — layouts forward `children[i]/…` references and
  re-root child operations by prepending `children[i]`.

So `SyntaxToWidget` only emits the widget/layout tree and the leaf
selection/collapse wiring; it does **not** reimplement routing or geometry. The
final graphics step is a single recursive `TypeDispatchingProjection` that
dispatches widgets (via `WidgetToGraphics.dispatch`), the two layouts, and
`TextText` (via `TextToGraphics`) — see `make_syntax_widget_graphics` in the
JSON example. The old `WidgetAndTextToGraphics` combinator is unnecessary here.

The box-model prerequisite the original plan worried about (`_push_box_rects!`
in container printers) turned out **not** to be needed: the `WidgetCard` border
is the per-node frame, and a per-node background tint was only ever a throwaway
debug scaffold, so it was dropped rather than shipped.

---

## 3  Deferred / not implemented

- **Keyboard tree navigation (Ctrl+Alt+Home, Ctrl+Space, arrow tree-move) and
  Alt+click whole-subtree selection.** `SyntaxNodeToText` handles these only at
  the root by walking the input tree; the widget/graphics layer does not route
  keyboard events to its children, so the widget examples are excluded from the
  keyboard-navigation test sweep (same as the bare widget examples). A
  widget-layer keyboard-routing mechanism would be the prerequisite.
- **End-to-end selection / reference mapping.** `SyntaxNodeToWidget` must map
  references forward (input selection → widget path, to display the caret) and
  backward (widget path → input selection, to retarget a click/edit), re-rooting
  across each node level — the way the existing `…ToSyntax` projections and
  `LayoutToGraphics` do via the `children[i]` prepend. **This is the prerequisite
  for editing leaf text:** without it a click on a leaf cannot be turned into a
  selection on the underlying domain leaf, so the caret cannot be placed and a
  keystroke has no target. (The leaf projection already maps its own three spans;
  what is missing is the node-level path plumbing above it.)
- **Node-level structural selection display** (highlighting a whole subtree).
- **Theme/domain-driven per-element styling** (accent, emphasis) — a style
  intent the domain expresses and the theme resolves, not arithmetic on the
  font color.
- **Geometry metadata for tooltips** — if a widget-rendered domain wants
  tooltips, it needs a widget-to-screen-coordinate equivalent of
  `TextToGraphics`'s `char_to_coord`.

These are independent enhancements; none gate the projection as it stands.

---

## 4  Lazy expansion

Collapse is also the lever for **lazy loading**: any domain whose syntax
children are computed on demand can defer that work until the node is expanded.
This is domain-agnostic — it works for any `…ToSyntax` producer, whether the
children are cheap in-memory values (JSON, XML) or expensive to materialize (a
remote/DB-backed tree, a large file, paginated data).

### SyntaxToWidget does not force collapsed children

A collapsed node renders only its header (and the inline ellipsis); its body
returns no children, so the node's child `CellVector` is **never read** while
collapsed. Combined with per-level delegation, this means a collapsed subtree's
descendants are not projected and their children are not forced. Expanding a
node flips its `collapsed` cell; the body then reads the children, which forces
the (possibly lazy) child `CellVector` → produces the child syntax → projects
into widgets. So expand is what pays for a level, and nothing below a collapsed
node costs anything.

### Driving initial collapse from child availability

A producing `…ToSyntax` projection decides each node's *initial* `collapsed`
state. The generic, lazy-friendly rule is **collapsed unless the node's child
collection is already materialized** — read *without forcing* via the backing
`Cell`'s `valid` flag (a lazy `CellVector` thunk is `valid` only after it has
been evaluated once):

- a fully-lazy tree starts entirely collapsed → the initial render forces
  **nothing** (zero queries / zero I/O);
- expanding a node loads exactly that one level on demand;
- a partially-walked tree (some children pre-materialized) renders expanded
  along the materialized path and collapsed off it.

Eager in-memory domains (JSON, XML) have their children already materialized, so
nodes simply render expanded — the same rule, no special-casing.

Caveat for producers: a "is this node collapsible?" predicate must **not**
inspect `node.children` length on a lazy node, since reading it would force the
collection. Key such predicates off cheap, non-forcing signals (e.g. the node's
own label/delimiters).

---

## 5  Precedents followed

- **`ConversationToWidget`** (`ConversationToWidgetModule`) — the model copied
  for delegation, the `ChildrenIoMap` of child iomaps, embedded `TextText`
  content, and the `_find_collapse_target` retargeting reader.
- **`LayoutToGraphics`** — the `children[i]` reference-prepend convention for
  routing and reference forwarding.
- **`WidgetCardToGraphicsCanvas`** — the header-click → `ToggleCollapseOperation`
  hit-test that drives collapse.

## 6  Tests

`test_syntax_to_widget` covers: indented node → `WidgetCard`, inline node →
`HorizontalLayout`, leaf → three-span `TextText`, leaf selection
forward/backward, collapse retargeting (including nested cards), and the inline
collapsed-ellipsis header. Lazy expansion is checked with a counting
fixture whose syntax children are lazy `CellVector`s recording a side effect
when forced: the initial projection forces nothing, expanding one node forces
exactly one level, and a pre-walked tree renders expanded along the
materialized path while off-path nodes stay collapsed and unforced.
