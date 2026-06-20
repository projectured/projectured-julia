# SyntaxToWidget Projection

Replace the text-based rendering pipeline with a widget-based one so that
structured domains (DbCatalog, JSON, XML, …) gain per-element visual styling
and interactive affordances without reimplementing text layout.

---

## 0  Decision (refined)

This plan was reviewed and the gating questions in §9 are now resolved. The
chosen design:

- **Path:** `Syntax → Widget → Graphics` (the "pure" pipeline), but with one
  refinement that the original §8 binary missed — **structure as widgets, leaf
  content as `TextText`**. A `SyntaxNode` projects to a widget container; a
  `SyntaxLeaf` projects to an embedded `TextText` rendered by `TextToGraphics`
  *inside* the widget tree, exactly as `ConversationToWidget` embeds `TextText`
  in a `WidgetCard`. This is the "middle path": it keeps editable, multi-span
  leaf content (resolving **C4**) and is the codebase's established
  widgets-for-structure / text-for-content composition (resolving **C5**), not
  the layer violation §1 feared.
- **Collapse:** use the existing `ToggleCollapseOperation` + reader mechanism.
  **No command widget is required** — the marker-label-+-reader fallback in §3
  is the chosen approach, identical to `WidgetCard`'s header-click reader. A
  `WidgetCommand` remains an optional later enhancement, never a blocker.
- **Many domains:** strict **per-level delegation (C1)** is mandatory, because
  it is the only thing that lets different domains (a DbCatalog table vs a JSON
  array node) receive different widget treatment via interposed projections.
- **One true prerequisite:** `_push_box_rects!` must actually be called by the
  container printers, or per-node backgrounds/borders never render and the
  result looks identical to the text path.

The rest of this document is the original analysis; §3, §7, §8, and §9 are
annotated with how each point is resolved by the decision above.

---

## 1  Problem Statement

### TextToWidget wraps everything in one widget

`TextToWidget` takes the entire `TextText` (a flat list of spans) and puts it
inside a single `WidgetScrollPane`. Every element — RDBMS, Schema, Table,
Column — shares one background, one border, one padding. There is no way to
style individual elements differently or attach per-element behavior.

**File:** `program/src/projection/primitive/TextToWidget.jl`

### WidgetAndTextToGraphics mixes layers

The helper merges `WidgetToGraphics` dispatch with `TextText ⇒ TextToGraphics`
in one `TypeDispatchingProjection`. This means the final graphics step must
know about *both* the Widget and the Text domain — a layer violation. Adding a
third intermediate domain (e.g. Layout) would require yet another dispatch
entry, and the combinator keeps growing.

**File:** `program/src/projection/primitive/TextToWidget.jl` (lines 114–130)

### WidgetScrollPane box model doesn't render

`WidgetScrollPaneToGraphicsCanvas` never calls `_push_box_rects!`, so the
`border`, `border_color`, `padding`, `padding_color`, and `content_fill_color`
fields set on the scroll pane are silently ignored. The widget example looks
identical to the text example.

**File:** `program/src/projection/primitive/WidgetToGraphics.jl`
(WidgetScrollPaneToGraphicsCanvas printer, ~line 1906)

### No path to interactive affordances

The Text domain is flat spans with font/color/fill — it cannot host buttons,
tooltips, context menus, or drag handles. Any future feature requiring
per-element interactivity would have to bypass Text entirely. Building on
TextToWidget today means rebuilding on widgets tomorrow.

---

## 2  Current Pipelines

### Text path (works, but limited to flat rendering)

```
Domain → Syntax → Text → Graphics
         ^^^^^^   ^^^^   ^^^^^^^^
         DbCatalogToSyntax  SyntaxToText  TextToGraphics
```

### Widget path (current, broken by design)

```
Domain → Syntax → Text → Widget(one wrapper) → Graphics(mixed dispatch)
                          ^^^^^^^^^^^^^^^^^^    ^^^^^^^^^^^^^^^^^^^^^^^^
                          TextToWidget          WidgetAndTextToGraphics
```

Problems: single widget for all content, layer mixing, no box-model rendering.

### Proposed path

```
Domain → Syntax → Widget → Graphics
         ^^^^^^   ^^^^^^   ^^^^^^^^
         DbCatalogToSyntax  SyntaxToWidget  WidgetToGraphics
```

Each layer transforms completely into the next. No mixed dispatch, no layer
bleed. The text path remains available for domains that don't need widget
affordances.

---

## 3  SyntaxToWidget Design

### Structural mapping

Refined per the §0 decision. Two rules drive every row below:

- **Structure → widgets, content → `TextText`.** Containers, layout, and chrome
  are widgets; every run of editable/styled characters (leaf values *and* the
  delimiter/separator strings) is a `TextText` rendered by `TextToGraphics`
  inside the widget tree (resolves C4; matches `ConversationToWidget`).
- **One level only — delegate children (C1).** The `SyntaxNode` printer builds
  *its own* container and header and delegates each child through `recursion`;
  it never inspects a child's type or flattens a grandchild. `RecursiveProjection`
  + `TypeDispatchingProjection` dispatch each child, so a domain can interpose a
  different widget treatment per node type.

| Syntax | Widget | Notes |
|--------|--------|-------|
| `SyntaxNode` (collapsible) | a container with a **header line + body**: `WidgetCard` / `WidgetTitlePane` (header) wrapping a `WidgetComposite` body, with the box model for the per-node frame | Collapse is driven by the **graphics-layer header-click reader already in `WidgetCardToGraphicsCanvas`** (`WidgetToGraphics.jl:2314`) when the container is a `WidgetCard` with a `Document` title — SyntaxToWidget does not re-hit-test, it only supplies the retargeting reader (see "Collapse toggle"). Per-node background is a **test scaffold only** (`_brighten`, to be removed — see "Per-element styling"); the box-model frame itself requires the `_push_box_rects!` prerequisite. Real per-node styling is a deferred theme/domain concern. |
| `SyntaxNode` header | `HorizontalLayout` of: collapse marker · open-delimiter `TextText` · (optional domain action widgets) | The marker is static chrome (`WidgetLabel`); the open delimiter is `TextText` so its `open{k}` cursor stays addressable. Domain-specific header affordances (refresh button, badge) are added by the *interposed* per-type projection, not the generic one. |
| `SyntaxNode` body | `VerticalLayout` **of lines** | One entry per rendered line — see "Line model". Each line holds a **delegated** child widget, not a re-projected subtree. Empty when `collapsed`. |
| A single line | `HorizontalLayout` | Left-to-right inline pieces of one line: leading indent **spacer**, the delegated child/leaf widget, and any trailing separator. |
| `SyntaxLeaf` | **embedded `TextText`** (open · value · close spans) rendered by `TextToGraphics` | Leaves stay `TextText` so cursor placement / editing / multi-span styling are preserved (C4). Mirrors `SyntaxLeafToText`'s three-span output. |
| Delimiters (`open` / `close`) | `TextText` spans (header for `open`; trailing body line or header for `close`) | `TextString`s in the syntax node → `TextText`, keeping `open{k}` / `close{k}` selection parity with the text path. `WidgetLabel` only if a delimiter is purely decorative and never addressed. |
| Separator (`sep`) | `TextText` span (or layout gap) **within the line's** `HorizontalLayout` | Between two children sharing a line; `TextText` keeps `sep{k}` addressable, a layout gap if non-addressable. |
| Collapse toggle (▾/▸) | `WidgetLabel` marker in the header (reader-driven) | No command widget — the node reader maps a header/marker click to `ToggleCollapseOperation`. See "Collapse toggle". |

### Line model — the unit of layout is the *line*, not the *child*

The Syntax → Text path (`SyntaxToText.jl`, lines 108–110) is already
line-oriented, and the widget path should mirror it rather than invent a new
geometry:

```
indented node (indentation > 0):
    open_delim
    <indent> child₁ sep
    <indent> child₂ sep
    …
    close_delim

inline node (indentation == 0):
    open_delim child₁ sep child₂ … close_delim     (one line)
```

So the structural mapping is **two-dimensional**:

- **Vertical** (`VerticalLayout`) stacks the *lines* of a node top-to-bottom.
- **Horizontal** (`HorizontalLayout`) lays out the *inline pieces of one line*
  left-to-right.

An indented node produces one line per child (plus the open/close lines); an
inline node produces a single horizontal line containing all children. This is
exactly the line-break behaviour SyntaxToText derives from `indentation` and
the `\n`+indent spans — the widget path reproduces it as nested
`VerticalLayout(HorizontalLayout(...))` instead of `TextNewline` spans.

This also dissolves challenge **C8** (see §7): indentation is no longer "nesting
depth." It becomes a leading horizontal **spacer** (`depth × indent_size`) at
the start of a line's `HorizontalLayout`, while vertical nesting comes from the
node containment that already exists in the syntax tree.

### Per-element styling

**`_brighten` is a test scaffold, not a feature — and must be removed.** During
bring-up it is convenient to derive a per-node background by lightening the
leaf/node font color, so the box model is visibly rendering and each level reads
distinctly:

```julia
# TEST SCAFFOLD ONLY — delete before this lands as a feature.
function _brighten(c::StyleColor, factor=0.85)
    StyleColor(1 - factor * (1 - c.red),
               1 - factor * (1 - c.green),
               1 - factor * (1 - c.blue),
               c.alpha)
end
```

This is purely a development aid (it makes each catalog level a tinted box) and
carries no design meaning. It must not ship — remove it once the projection is
verified.

**The real path, later:** genuine per-element styling should be a
**theme/domain-driven** concern, not a color derived by arithmetic from the font
color. A node's visual treatment (background, accent, emphasis) should come from
a style intent the domain expresses and the theme resolves — consistent with the
widget theme being the single source of truth for colors. Deferred; out of scope
for the initial SyntaxToWidget.

> **Note — a widget-layer debug mode would be welcome.** Independently of
> SyntaxToWidget, a global debug-rendering mode at the `WidgetToGraphics` layer
> (toggleable at the factory) would be valuable for diagnosing **container
> overlap and alignment** issues — e.g. translucent per-widget bounds (so
> overlaps compound and show up) plus depth-tinted outlines. That belongs in the
> widget layer, applies to every widget consumer, and is the proper home for the
> kind of visualization `_brighten` is being abused for here. Tracked as a
> separate enhancement, not part of this plan.

### Collapse / expand

- `SyntaxNode.collapsed` controls whether children are rendered.
- When collapsed: title pane shows the toggle (▸) + open label + ellipsis.
  No line widgets in the body.
- When expanded: title pane shows the toggle (▾) + open label. The node's
  lines rendered as a `VerticalLayout` of `HorizontalLayout` lines (see
  "Line model") inside the content area.
- `ToggleCollapseOperation` passes through widget containers unchanged
  (same as the current text path).

#### Collapse toggle: reader-driven `ToggleCollapseOperation` (decided)

**Decision: use the marker-label-+-reader mechanism. No command widget.**

The toggle is a header element (a `WidgetLabel` marker `▾`/`▸`, or just the
header region itself). **The hit-test is not re-implemented in SyntaxToWidget.**
If the node container is a `WidgetCard` with a `Document` title,
`WidgetCardToGraphicsCanvas` (`WidgetToGraphics.jl:2314`) already hit-tests the
title region at the graphics layer and emits `ToggleCollapseOperation(card)`,
routing other clicks to children. SyntaxToWidget supplies only the *retargeting*
reader (verified pattern, `ConversationToWidget.jl:185-202`): a
`projection_read(::…, iomap, op::ToggleCollapseOperation)` that walks the
`ChildrenIoMap` (`_find_collapse_target`) to turn the widget target into the
owning `SyntaxNode`. The operation then:

1. propagates up through the widget containers,
2. is retargeted across the domain boundary by the producing projection's
   `projection_read(..., op::ToggleCollapseOperation)` overload — the same
   `_find_collapse_target` iomap walk `ConversationToWidget` uses
   (`_find_collapse_target` at `ConversationToWidget.jl:185`, invoked from the
   `projection_read` overload at `:197`) — so the *widget* target becomes the
   *syntax node* whose `collapsed` cell should flip, and
3. is applied by `evaluate_operation(editor, ::ToggleCollapseOperation)`
   (`common/Operation.jl:271`), which flips `node.collapsed`.

`SyntaxNode.collapsed` already exists and is already the collapse state in the
text path (`SyntaxToText.jl`), so no document change is needed.

**Why not a command widget?** A `WidgetCommand` (a widget carrying the operation
to dispatch directly) would add hover/focus/keyboard-activation affordances and
remove the hit-testing, but the reader fallback is fully functional today and is
the established widget-layer pattern. A command widget is an **optional later
enhancement**, explicitly *not* a prerequisite — it does not gate this work.
(Background: the toggle/command-widget design discussion concluded operations
should stay first-class domain objects routed through readers, not callbacks
stored on widgets; `ToggleCollapseOperation` already embodies that.)

### Selection and reference mapping

- Forward: bare syntax reference → prepend widget path
  (e.g. `elements[i].content.…`)
- Backward: strip widget path prefix → bare syntax reference
- `ReplaceSelectionOperation`: map path backward.
- `StringReplaceRangeOperation`: map reference backward.
- `ToggleCollapseOperation` / `ScrollWidgetOperation`: pass through.

### Layout

Use existing layout primitives (no new layout engine needed). The two combine to
realise the line model: vertical for lines, horizontal for a line's contents.

- `VerticalLayout` — stacks the node's **lines** top-to-bottom with gap.
  Already used by `ConversationToWidget`.
- `HorizontalLayout` — lays out the **inline pieces of one line** side-by-side
  (leading indent spacer, child/leaf widgets, separators; also the node header's
  toggle + label + action buttons).
- Widget box model (`margin`, `border`, `padding` on `WidgetComposite`) —
  provides per-node visual frame when rendered by `_push_box_rects!`.

### Printer sketch

The sketch below iterates `node.children` and calls
`projection_printer_recurse(recursion, child, …)` — which is the **correct**
delegation shape (it is exactly what `ConversationToWidget.jl:100-124` does:
loop, recurse each child, build the layout from each `child_iomap.output`, store
the child iomaps). Per C1 the only hard requirement is that each child go back
through `recursion` (so its type is independently dispatched) and that the child
iomaps be stored in the returned `ChildrenIoMap`. `RecursiveProjection` does not
build the lines for you — the printer assembles the `VerticalLayout` itself.

```julia
function projection_print(p::SyntaxNodeToWidget, recursion, node::SyntaxNode, ctx)
    font_color = node.open.font_color
    bg_color   = _brighten(font_color)   # TEST SCAFFOLD ONLY — remove (see "Per-element styling")

    # Toggle: a plain marker label; the reader maps a click on it (or the
    # header region) to ToggleCollapseOperation(node). See "Collapse toggle".
    marker = node.collapsed ? p.collapsed_marker : p.expanded_marker
    toggle = WidgetLabel(Point2D(0,0), marker)

    # Header line: toggle + open label, laid out horizontally.
    header = HorizontalLayout(Any[
        toggle,
        WidgetLabel(Point2D(0,0), node.open.content),
    ]; gap=4)

    if node.collapsed
        # Collapsed: header + ellipsis, no line widgets.
        body = HorizontalLayout(Any[WidgetLabel(Point2D(0,0), "…")])
    else
        # Expanded: one HORIZONTAL line per rendered line, stacked VERTICALLY.
        lines = Any[]
        for (i, child) in enumerate(node.children)
            cim   = projection_printer_recurse(recursion, child, ctx)  # see C1 caveat above
            line  = HorizontalLayout(Any[
                _indent_spacer(p, child_depth),       # leading indent = depth × indent_size
                cim.output,
                (i < length(node.children) ? WidgetLabel(Point2D(0,0), node.sep.content)
                                           : nothing),
            ]; gap=0)
            push!(lines, line)
        end
        body = VerticalLayout(lines; gap=2)           # the lines, stacked top-to-bottom
    end

    pane = WidgetTitlePane(header, body;
        padding=Inset(4,4,4,4),
        padding_color=bg_color)
    # ... build iomap, wire selection ...
end

# Collapse interactivity: DON'T hand-roll a MousePress hit-test here. If the
# container is a WidgetCard with a Document title, the header hit-test already
# lives at the graphics layer — WidgetCardToGraphicsCanvas (WidgetToGraphics.jl:2314)
# hit-tests the title region and emits ToggleCollapseOperation(card). SyntaxToWidget
# only needs the RETARGETING reader that turns that widget-targeted op into a
# syntax-node-targeted one, exactly like ConversationToWidget (ConversationToWidget.jl:185-202):
#
#   function projection_read(::SyntaxNodeToWidget, iomap, op::ToggleCollapseOperation)
#       op.target === nothing && return op
#       node = _find_collapse_target(iomap, op.target)   # walk ChildrenIoMap, widget → input node
#       node === nothing ? op : ToggleCollapseOperation(node)
#   end
```

For an **inline** node (`indentation == 0`) the body collapses to a single
`HorizontalLayout` holding the open delimiter, children, and separators — i.e.
one line — rather than a `VerticalLayout` of many.

---

## 4  Future Features Enabled

Once elements are individual widgets, each can independently gain:

| Feature | How | Dependency |
|---------|-----|------------|
| **Refresh button** on Tables node | `WidgetButton` in the `HorizontalLayout` header | None — WidgetButton already exists |
| **Tooltips** on hover | `TooltipSource` wrapping any widget | Tooltip system exists (`plan/pending/tooltip.md`) |
| **Context menu** on right-click | `WidgetMenu` + reader for right-click event | WidgetMenu exists; needs right-click routing |
| **Per-element background** | `padding_color` / `content_fill_color` on each widget | Box model rendering (`_push_box_rects!`) |
| **Drag-and-drop** | Drag handle widget in header | Not yet implemented (`plan/pending/dragging.md`) |
| **Hover highlighting** | Reader for `MouseMotion` updating a `hovered` cell | Not yet implemented (see `plan/pending/tooltip.md` §9) |
| **Inline badges** (row count, type info) | `WidgetBadge` in header layout | WidgetBadge already exists |

None of these are possible in the Text domain.

---

## 5  Existing Patterns to Follow

### ConversationToWidget (precedent)

**File:** `program/src/projection/primitive/ConversationToWidget.jl`

Maps a domain tree to nested widgets using the same structure proposed here:

- `ConversationConversation` → `VerticalLayout` of turn cards
- `ConversationTurn` → `WidgetCard` (title = avatar + role, content = parts)
- `ConversationPart` → `WidgetCard` (content = the part's document, recursed)
- Collapse: `WidgetScrollPane` clips to `_COLLAPSED_H` pixels
- Reactive children: `CellVector` thunk, so pushing a turn updates layout

This is the closest existing analogue to what SyntaxToWidget needs.

### Widget box model

**File:** `program/src/document/Widget.jl`

Every `WidgetDocument` subtype has: `margin`, `margin_color`, `border`,
`border_color`, `padding`, `padding_color` (each an `Inset` / `StyleColor`).
`_push_box_rects!` in `WidgetToGraphics.jl` (line 475) renders these as
nested `GraphicsRect` elements — but only for widgets whose printer calls it
(currently WidgetComposite does not, WidgetScrollPane does not — this should
be fixed as a prerequisite or as part of this work).

### Layout primitives

**File:** `program/src/document/Layout.jl`

- `VerticalLayout(elements; gap, horizontal_align)`
- `HorizontalLayout(elements; gap, vertical_align)`

Both produce auto-positioned widget trees. Already used by ConversationToWidget
and WidgetToolbar examples.

---

## 6  Impact on TextToWidget

| Item | Action |
|------|--------|
| `TextToWidget` struct | Keep for now — useful as a simple scroll-pane wrapper for pure-text content (e.g. plain text editor, log viewer) |
| `WidgetAndTextToGraphics` helper | **Deprecate** — it mixes layers. Domains using SyntaxToWidget go through `WidgetToGraphics` directly. Domains staying on text use `TextToGraphics` directly. |
| `_dbcatalog_widget()` helper | Remove — replaced by SyntaxToWidget styling |
| Widget DbCatalog examples | Rewrite to use `SyntaxToWidget` instead of `TextToWidget` + `WidgetAndTextToGraphics` |

---

## 7  Architectural Challenges

Issues surfaced by cross-referencing with the project's design guides and
pending plans.

### C1  Delegation principle — the plan's printer sketch violates it — RESOLVED (mandatory)

`guide/projection-system.md` requires: *"A projection should transform only
its own single level and delegate every child to `recursion`."*

The printer sketch (§3) iterates `node.children` and calls
`projection_printer_recurse` in a loop, collecting child widgets. This is
the *same mistake* that `syntaxtotext-delegation.md` documents as a known
violation in `SyntaxNodeToText` — it walks the subtree instead of projecting
one level and letting `RecursiveProjection` handle each child independently.

**Impact:** If the printer flattens children itself, domain-specific
projections cannot be interposed for individual children. A DbCatalog table
node and a JSON array node would need different widget treatments, but the
generic SyntaxToWidget would have already consumed them.

**Resolution:** SyntaxToWidget must project *one SyntaxNode* to *one widget
container* and delegate each child through `recursion`.

**Precedent — copy ConversationToWidget, not SyntaxToText.** Verified against
the code, the two relevant implementations sit on opposite sides of this rule:

- `ConversationToWidget` (`ConversationToWidget.jl:100-124`) does it **right**:
  its printer loops over `c.turns` / `t.parts`, calls
  `projection_print(rec, rec, child, …)` (i.e. `projection_printer_recurse`) on
  each, builds the `VerticalLayout` from each `child_iomap.output`, and stores
  the child iomaps in a `ChildrenIoMap`. Each child therefore re-enters the
  `RecursiveProjection`+`TypeDispatchingProjection` pipeline and is dispatched
  by its own type, so a domain can interpose a different per-type widget
  projection. This is the model to copy.
- `SyntaxToText` does it **wrong** (the documented violation): `SyntaxNodeToText`
  → `_collect_spans` → `_collect_child_spans` (`SyntaxToText.jl:899-906`)
  hard-dispatches on `SyntaxLeaf`/`SyntaxNode` by Julia method dispatch and
  recurses into the subtree itself; the `recursion` argument is threaded but
  never used to dispatch. **Do not** mirror this structure — it is the C1
  violation, not the precedent.

Mechanically (per `Projection.jl:111-117`): the parent printer builds the
container/layout *itself*, recurses each child via
`projection_printer_recurse(recursion, child, child_ctx)`, stores the returned
child iomaps, and builds the output's children from each `child_iomap.output`.
`RecursiveProjection` does **not** auto-build the layout — it only re-enters the
pipeline per child; assembling the lines is the printer's job.

### C2  Tree navigation is root-only and unaddressed

`syntaxtotext-delegation.md` §A6 documents that keyboard navigation
(`Ctrl+Alt+Home`, `Ctrl+Space`, arrow keys for tree navigation) is handled
**only at the root** `SyntaxNodeToText`, not delegated to children. The root
receives `KeyDown` events and walks the **input syntax tree** directly.

The plan does not mention keyboard navigation at all. SyntaxToWidget would
need equivalent root-level handlers, or the widget path would lose all
keyboard interactivity that the text path provides.

### C3  Alt+click tree selection is gesture-aware

`syntaxtotext-delegation.md` §A5 describes how `SyntaxNodeToText`'s reader
handles `Alt+click` to select entire structural elements (tree selection).
This is a **gesture-aware reader** — it interprets modifier keys and
produces selection paths that span an entire node.

SyntaxToWidget's reader must replicate this, or the widget path loses the
ability to select whole subtrees.

### C4  WidgetLabel is not editable — RESOLVED

The plan originally mapped `SyntaxLeaf` → `WidgetLabel`, but `WidgetLabel` is
non-interactive (positioned, non-editable). Leaves that need cursor placement,
text editing, or multi-span styling require `TextText` embedded inside a widget
container.

**Resolution (see §0):** leaves project to **embedded `TextText`**, rendered by
`TextToGraphics` within the widget tree. This deliberately keeps Text in the
widget path — which C5 establishes is *not* a violation but the codebase's
intended widgets-for-structure / text-for-content composition, dispatched
cleanly by `TypeDispatchingProjection` at the graphics step. `WidgetLabel` is
reserved for static chrome (e.g. the collapse marker). The
`WidgetAndTextToGraphics` *combinator* is still deprecated (§6); the graphics
step simply dispatches both Widget and Text types, as it must for
`ConversationToWidget` today.

### C5  The "clean layer separation" argument is weaker than claimed — ACCEPTED

`ConversationToWidget` — the plan's own cited precedent — embeds `TextText`
inside `WidgetCard` content. The conversation part's document is a `TextText`
rendered by `TextToGraphics` *within* the widget tree.

The established pattern is: **widgets for structure, text for content.** This is
not a layer violation; the codebase treats it as intentional composition —
widgets own the chrome, text owns the content rendering, and
`TypeDispatchingProjection` exists precisely to support this.

**This is now the chosen design (§0):** SyntaxToWidget adopts widgets-for-
structure + text-for-content directly, rather than the "pure, no Text" reading
the original §1/§8 leaned toward.

### C6  Tooltip positioning requires geometry metadata

`plan/pending/tooltip.md` §6 requires that tooltip decorators look up pixel
coordinates via the iomap chain (`TextToGraphicsIoMap.char_to_coord`).

If SyntaxToWidget → WidgetToGraphics replaces SyntaxToText → TextToGraphics,
the `char_to_coord` mapping disappears. SyntaxToWidget must provide
equivalent geometry metadata (widget-to-screen-coords) or tooltip placement
breaks.

### C7  Component layer overlap

`plan/pending/component-document.md` defines a Component layer between
Widget and Workbench. Components compose from widgets and project via
`ComponentToWidget`. If SyntaxToWidget also produces widget trees, the
relationship between these two projections needs clarification:

- Does SyntaxToWidget output feed into a Component?
- Or does a Component's content use SyntaxToWidget internally?
- Are they independent parallel paths?

### C8  Indentation ≠ widget nesting

Syntax `indentation` is a rendering hint: "prepend N×depth spaces before
each child." Widget nesting is structural: "this widget is a child of that
container." A flat syntax tree with `indentation=2` does not naturally map
to deeply nested widgets — the nesting depth would be 1 (one container with
all children), but with indentation-proportional left padding.

**Resolved by the line model (§3).** Indentation maps to a leading horizontal
**spacer** (`depth × indent_size`) at the start of each line's
`HorizontalLayout`, not to widget nesting. Vertical nesting comes only from the
syntax tree's actual node containment. Indentation and nesting stay orthogonal,
as they should.

### Minor concerns (not blockers)

**Selection mapping duplicates SyntaxToText logic.**
The three-step selection algorithm (shared `Cell`, parse head, extend child
output) and `ProjectionReference` wrapping for decoration elements must be
implemented from scratch. SyntaxToText's reference mapping is ~400 lines;
SyntaxToWidget would need comparable logic. This is manageable — it follows
well-documented patterns (`guide/selection-deep-dive.md`) and the
ConversationToWidget precedent — but it does duplicate structural
transformation logic that already exists in SyntaxToText.

**Overall logic duplication.**
Bypassing Text means SyntaxToWidget reimplements collapse rendering,
indentation, delimiter handling, tree navigation, gesture handling, and
reference mapping — roughly the same responsibilities as SyntaxToText,
adapted for widget output. Not a reason to avoid the approach, but worth
noting that both paths must be maintained if they coexist.

---

## 8  Revised Assessment

The plan's **motivation** is sound: per-element styling and interactive
affordances require widgets, and the current TextToWidget approach is
inadequate.

The pure Syntax → Widget → Graphics path duplicates SyntaxToText's
structural transformation logic, but this is manageable — the patterns are
well-documented and the implementation follows established precedent
(ConversationToWidget). The real architectural challenges are C1 (delegation
principle), C4 (editability), and C5 (the hybrid pattern is already
established and not a layer violation).

### Alternative worth considering: Syntax → Text → Widget (hybrid)

Keep SyntaxToText for linearization, cursor math, and keyboard navigation.
Then wrap *per-line or per-section* text output in individual widgets (not
one big scroll pane). This would:

- Reuse all of SyntaxToText's battle-tested logic
- Give each section its own widget container (background, buttons, tooltips)
- Avoid reimplementing flat ↔ structural path translation
- Follow the ConversationToWidget precedent (widgets for structure, text for
  content)

The cost is that it's a three-layer chain (Syntax → Text → Widget →
Graphics), which the plan criticizes. But depth is cheaper than
reimplementation, and `TypeDispatchingProjection` already handles mixed
dispatch cleanly.

### Decision made

Chosen: **`Syntax → Widget → Graphics`, structure-as-widgets + leaves-as-`TextText`**
(the ConversationToWidget composition). See §0.

| Path | Effort | Gain | Risk | Status |
|------|--------|------|------|--------|
| **Syntax → Widget → Graphics** (structure widgets + `TextText` leaves) | High (new projection, follows existing patterns) | Clean structural layers, per-element styling/affordances, **keeps editable leaves** | Duplicates SyntaxToText structural logic | **CHOSEN** |
| Syntax → Widget → Graphics (pure, no Text) | High | Zero Text dependency | Loses leaf editing/cursor (C4) | Rejected |
| Syntax → Text → Widget → Graphics (text-first hybrid) | Medium | Reuses SyntaxToText | Linearizes away the structure we want to enrich | Rejected |

The chosen path duplicates SyntaxToText's *structural* transformation
(collapse, indentation→spacer, delimiter placement, reference mapping) but
reuses `TextToGraphics` for all *leaf content* rendering. The structural
duplication is manageable — it follows documented patterns and the
ConversationToWidget precedent.

---

## 9  Resolved Questions

(See also challenges C1–C8 above, each of which implies a design decision.)

1. **Which path? — RESOLVED.** `Syntax → Widget → Graphics`, structure-as-
   widgets + leaves-as-`TextText`. See §0 and the §8 decision table.

2. **Generic vs domain-specific? — RESOLVED (generic core + per-level
   delegation).** A *generic* `SyntaxToWidget` projects one syntax level to one
   widget container and delegates each child through `recursion`. Because of
   strict per-level delegation (C1), domain-specific treatment is achieved by
   **interposing a domain-specific projection for that node type** in the
   `TypeDispatchingProjection`, not by a callback or subclass of the generic
   projection. Domain-specific header affordances (e.g. a refresh button on a
   Tables node) live in that interposed projection.

3. **Prerequisites — RESOLVED.**
   - *Box model rendering (REQUIRED, do first):* `_push_box_rects!` must be
     called by the container widget printers (`WidgetComposite`,
     `WidgetTitlePane`, `WidgetCard`) or per-node backgrounds/borders never
     render. This is the **one true prerequisite**.
   - *Command widget for the collapse toggle (NOT required):* the reader-driven
     `ToggleCollapseOperation` fallback (§3) is the chosen mechanism. A
     `WidgetCommand` is an optional later enhancement and does not gate this
     work.

4. **Coexistence with text path — RESOLVED.** The text path
   (`SyntaxToText → TextToGraphics`) remains available. Pipeline choice is
   per-example configuration, not a global switch. Existing `…ToSyntax`
   projections are untouched; a domain opts into the widget presentation by
   choosing `SyntaxToWidget` downstream.

---

## Files to Create / Modify

| File | Action |
|------|--------|
| `program/src/projection/primitive/SyntaxToWidget.jl` | **New** — the projection |
| `program/src/Projectured.jl` | Include, using, export |
| `example/src/projection/DbCatalog.jl` | Add widget-path examples using SyntaxToWidget |
| `example/src/Examples.jl` | Register new examples |
| `program/src/projection/primitive/WidgetToGraphics.jl` | **Prerequisite, do first** — call `_push_box_rects!` in the WidgetComposite / WidgetTitlePane / WidgetCard printers so per-node backgrounds/borders render; add the `SyntaxNode`/`SyntaxLeaf` reader path if leaves embed `TextText` |
