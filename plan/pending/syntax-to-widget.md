# SyntaxToWidget Projection

Replace the text-based rendering pipeline with a widget-based one so that
structured domains (DbCatalog, JSON, XML, …) gain per-element visual styling
and interactive affordances without reimplementing text layout.

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

| Syntax | Widget | Notes |
|--------|--------|-------|
| `SyntaxNode` (collapsible) | `WidgetTitlePane` or `WidgetComposite` | Title = open delimiter / label; content = children. Background color per node. |
| `SyntaxNode` children | `VerticalLayout` | Auto-stacked, indented by depth. |
| `SyntaxLeaf` | `WidgetLabel` | Styled text from the leaf's `value` TextString. |
| Collapse marker (▾/▸) | Part of the title pane's header | Click toggles `ToggleCollapseOperation`. |
| Separator (`sep`) | Implicit spacing or `WidgetSeparator` | Between children in the layout. |

### Per-element styling

Each `SyntaxNode`/`SyntaxLeaf` carries a font color in its `TextString` fields
(set by the domain-to-syntax projection, e.g. `DbCatalogToSyntax`). The
SyntaxToWidget printer can derive a background color as a brighter/lighter
version of the font color:

```julia
function _brighten(c::StyleColor, factor=0.85)
    StyleColor(1 - factor * (1 - c.red),
               1 - factor * (1 - c.green),
               1 - factor * (1 - c.blue),
               c.alpha)
end
```

This gives each catalog level a tinted background: red-tinted for RDBMS,
blue-tinted for Schema, green-tinted for Table, magenta-tinted for Column.

### Collapse / expand

- `SyntaxNode.collapsed` controls whether children are rendered.
- When collapsed: title pane shows the marker (▸) + open label + ellipsis.
  No children in the layout.
- When expanded: title pane shows the marker (▾) + open label. Children
  rendered in a `VerticalLayout` inside the content area.
- `ToggleCollapseOperation` passes through widget containers unchanged
  (same as the current text path).

### Selection and reference mapping

- Forward: bare syntax reference → prepend widget path
  (e.g. `elements[i].content.…`)
- Backward: strip widget path prefix → bare syntax reference
- `ReplaceSelectionOperation`: map path backward.
- `StringReplaceRangeOperation`: map reference backward.
- `ToggleCollapseOperation` / `ScrollWidgetOperation`: pass through.

### Layout

Use existing layout primitives (no new layout engine needed):

- `VerticalLayout` — stacks children top-to-bottom with gap.
  Already used by `ConversationToWidget`.
- `HorizontalLayout` — places items side-by-side (for node headers with
  marker + label + action buttons).
- Widget box model (`margin`, `border`, `padding` on `WidgetComposite`) —
  provides per-node visual frame when rendered by `_push_box_rects!`.

### Printer sketch

```julia
function projection_print(p::SyntaxNodeToWidget, recursion, node::SyntaxNode, ctx)
    font_color = node.open.font_color
    bg_color   = _brighten(font_color)

    # Header: marker + open label
    marker = node.collapsed ? p.collapsed_marker : p.expanded_marker
    header = HorizontalLayout(Any[
        WidgetLabel(Point2D(0,0), marker),
        WidgetLabel(Point2D(0,0), node.open.content),
    ]; gap=4)

    if node.collapsed
        # Collapsed: header + ellipsis, no children
        body = WidgetLabel(Point2D(0,0), "…")
    else
        # Expanded: recursively project children
        child_widgets = Any[]
        for child in node.children
            cim = projection_printer_recurse(recursion, child, ctx)
            push!(child_widgets, cim.output)
        end
        body = VerticalLayout(child_widgets; gap=2)
    end

    pane = WidgetTitlePane(header, body;
        padding=Inset(4,4,4,4),
        padding_color=bg_color)
    # ... build iomap, wire selection ...
end
```

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

### C1  Delegation principle — the plan's printer sketch violates it

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
container* and delegate each child through `recursion`. The
`RecursiveProjection` wrapper + `TypeDispatchingProjection` handles the
per-type dispatch, exactly as the Syntax → Text path does today.

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

### C4  WidgetLabel is not editable

The plan maps `SyntaxLeaf` → `WidgetLabel`, but `WidgetLabel` is
non-interactive (positioned, non-editable). If leaves need cursor placement,
text editing, or multi-span styling, they need `WidgetText` (which supports
cursor and editing) or `TextText` embedded inside a widget container.

If leaves use `TextText`, the "no Text in the widget path" principle breaks
— the widget tree would contain Text domain objects, requiring mixed
dispatch at the graphics layer (the same `WidgetAndTextToGraphics` pattern
the plan proposes to deprecate).

**Tension:** Pure widget path (no editing) vs. hybrid path (editable leaves
require Text inside widgets).

### C5  The "clean layer separation" argument is weaker than claimed

`ConversationToWidget` — the plan's own cited precedent — embeds `TextText`
inside `WidgetCard` content. The conversation part's document is a `TextText`
rendered by `TextToGraphics` *within* the widget tree. This is the same
hybrid dispatch that `WidgetAndTextToGraphics` provides.

The established pattern is: **widgets for structure, text for content.** The
plan frames this as a layer violation, but the codebase treats it as
intentional composition — widgets own the chrome, text owns the content
rendering. `TypeDispatchingProjection` exists precisely to support this.

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

The plan conflates indentation with nesting. They are orthogonal.

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

### Decision needed

| Path | Effort | Gain | Risk |
|------|--------|------|------|
| **Syntax → Widget → Graphics** (pure) | High (new projection, follows existing patterns) | Clean layers, no Text dependency | Duplicates SyntaxToText logic; loses editing if not careful |
| **Syntax → Text → Widget → Graphics** (hybrid) | Medium | Per-section widgets, reuses SyntaxToText | Three layers; "mixed dispatch" (but it's established pattern) |

---

## 9  Remaining Open Questions

(See also challenges C1–C10 above, each of which implies a design decision.)

1. **Which path?** Pure widget (Syntax → Widget → Graphics) or hybrid
   (Syntax → Text → Widget → Graphics)? See §8 for tradeoff table.

2. **Generic vs domain-specific?** A generic `SyntaxToWidget` handles any
   syntax tree. Domain-specific features (refresh button on tables) need
   either a styling/action callback, a domain-specific subclass, or a
   decorator pattern.

3. **Box model rendering prerequisite.** `_push_box_rects!` must be called
   by container widget printers for backgrounds to render. Fix first, or
   as part of this work?

4. **Coexistence with text path.** The text path should remain available.
   Pipeline choice should be per-example configuration, not a global switch.

---

## Files to Create / Modify

| File | Action |
|------|--------|
| `program/src/projection/primitive/SyntaxToWidget.jl` | **New** — the projection |
| `program/src/Projectured.jl` | Include, using, export |
| `example/src/projection/DbCatalog.jl` | Add widget-path examples using SyntaxToWidget |
| `example/src/Examples.jl` | Register new examples |
| `program/src/projection/primitive/WidgetToGraphics.jl` | Fix `_push_box_rects!` calls in WidgetComposite/WidgetTitlePane printers (prerequisite) |
