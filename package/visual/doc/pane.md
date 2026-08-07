# Pane Domain

The pane tree is the generic way to organize documents on the screen: tab groups,
splits between them, and the gestures that rearrange the lot. It is implemented in
[package/visual/main/pane/](../../../package/visual/main/pane/) and rendered by

```
PaneTree ──PaneToWidget──► WidgetSplitPane / WidgetTabbedPane ──WidgetToGraphics──► GraphicsCanvas
```

A fresh layout starts as one empty tab group. Everything else — tabs, splits,
names, the arrangement — the user builds from there with the keyboard and the
mouse.

## Document types

All subtype `PaneDocument` (`<: Document`), defined in
[pane/Pane.jl](../../../package/visual/main/pane/Pane.jl).

| Type | Role |
|---|---|
| `PaneTab(title, content[, icon])` | One tab: a title document and a content document of any domain. `PaneTab("name", doc)` wraps the title in a `PrimitiveString`. |
| `PaneGroup(tabs)` | A tab group. It can be empty — `PaneGroup(PaneTab[])` is the start state. |
| `PaneSplit(orientation, elements; weights)` | Two or more children and one weight each. |
| `PaneTree(root)` | The whole layout, plus the transient `drag` state. |

### Vertical and horizontal

A `:vertical` split has a vertical divider, so its children sit **side by side**;
a `:horizontal` split stacks them. This is the Vim meaning of the two words.

`WidgetSplitPane`'s own `orientation` names the opposite thing — the axis its
children lay out along — so a `:vertical` `PaneSplit` prints a
`WidgetSplitPane(:horizontal, …)`. `pane_split_axis` is that translation, and
`PaneToWidget` is the only place it is applied.

### Focus is the selection

No node carries a focus field or an active-tab field. The tree's `selection`
names the focused tab:

```
root.elements[2].tabs[3]      # the third tab of the second element
root.elements[2]              # an empty group: the group itself
```

The tab a group *shows* is the tab its own injected `selection` names, so every
focus move and every tab switch is one `ReplaceSelectionOperation` and nothing
else. This is what `WorkbenchPageToWidgetTabbedPane` already does for a page.

**The consequence:** `_sync_selection!` clears the divergent branch when the
selection moves, so a group that loses the focus loses its own selection, and the
tabbed pane falls back to its first tab. An unfocused group therefore shows its
first tab. Two remedies need no document field, if that ever matters: latch the
last in-group value in the printer's selection cell, or move the focused tab to
the front of its group.

## The edits are generic operations

`PaneSurgery.jl` declares **no operation type**. Each builder answers with a
generic operation, and every write leaves `document` at `nothing`, so the
reference re-roots as the operation bubbles up — which is what lets a pane tree
sit inside another document.

| Edit | Generic form |
|---|---|
| `pane_open_tab_operation` | `insert_elements` plus the focus move |
| `pane_close_tab_operation` | `delete_elements`, or a collapse write, plus the focus move |
| `pane_split_operation` | `ReplaceReferencedValueOperation` writing a new `PaneSplit` at the group's slot |
| `pane_move_tab_operation` | `MoveRangeOperation` plus the focus move |
| `pane_drop_split_operation` | the split write, the move, and the focus move |
| `pane_resize_operation` | one write of the weights |
| `pane_focus_operation` | `ReplaceSelectionOperation` |
| `pane_retarget_title_operation` | `ReplaceStringRangeOperation`, re-rooted |

Two rules hold across all of them:

- **The surgery reuses node objects; it never rebuilds a subtree.** A split puts
  the *existing* group in the new split, and a collapse writes the *existing*
  sibling at the parent's slot. A rebuilt subtree would drop the iomaps below it,
  and every tab would re-print and lose its scroll position and caret.
- **Paths carry their node types as they are built.** Each `(node, step)` pair
  records the document its step descends from. That is what lets a builder name a
  slot the edit is *about to* create — a fresh tab, a collapsed sibling — which
  `annotate_reference_types` can not do, because it resolves against the tree as
  it stands now.

## Geometry

[PaneGeometry.jl](../../../package/visual/main/pane/PaneGeometry.jl) gives every
group a rectangle in the unit square by one walk of the tree with its weights. No
font, no measurement, and no backend takes part.

- `pane_rectangles(tree)` / `pane_rectangle(tree, group)` / `pane_group_at(tree, x, y)`
- `pane_neighbour_group(tree, group, direction)` — the group in `:left`,
  `:right`, `:up`, or `:down`. A candidate must lie wholly past the edge and
  overlap on the other axis; the nearest wins, then the one that overlaps most.
- `pane_next_group(tree, group; backward)` — the depth-first traversal order,
  wrapping at both ends.
- `pane_drop_zone(tree, x, y; strip, band)` — the group under a point and which
  part of it: `:strip`, `:center`, or one of the four edge bands.

The rectangles are **proportional**: they ignore the few pixels a border and a
splitter take. That is exact enough to decide a direction, a drop zone, or which
pane a click landed in, and it is not a pixel-accurate model of the drawing.

## Keyboard

The table is `@gestures PaneTree` in
[PaneGestures.jl](../../../package/visual/main/pane/PaneGestures.jl).

| Gesture | Effect |
|---|---|
| `Ctrl+T` | Open a new tab in the focused group |
| `Ctrl+W` | Close the focused tab |
| `Ctrl+\` | Split vertically — the new pane on the right |
| `Ctrl+Shift+\` | Split horizontally — the new pane below |
| `Ctrl+Alt+Left/Right/Up/Down` | Move the focus to the group in that direction |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Traverse the groups |
| `Ctrl+PageDown` / `Ctrl+PageUp` | Focus the next / previous tab |
| `F2` | Put the caret in the tab's name |
| `Escape` | Leave the name |

Every chord carries a modifier, because the plain keys belong to the content of
the focused tab. Two need more than that:

- **`Ctrl+Alt` and the arrows.** Plain `Alt`+arrow is the structural navigation
  of a document — a syntax tree binds it — so the pane layer takes the next chord
  out rather than fighting it.
- **`Ctrl+Tab`** is declared `override`, because the widget split pane answers
  every `Tab` with its own focus traversal. Plain `Tab` can not do this work at
  all: a text document takes it.

## Mouse

| Gesture | Effect |
|---|---|
| Click a tab | Focus that tab |
| Click a tab's close button | Close it |
| Click the new-tab button | Open a tab |
| Click anywhere in a pane | Focus that group |
| Drag a splitter | Write the split's weights |
| Drag a tab onto a group's strip or middle | Move it into that group |
| Drag a tab onto a group's edge band | Split that group, the tab in the new pane |

A click in a pane's empty space focuses it. Without that, most of a pane would be
dead: its content is a document that ends where its text ends, so a press beside
the text hits no element at all.

## Every edit is reactive

A split, a collapse, a tab opened or closed all reach the screen through the
IoMaps that are already standing — no re-print, and no drop of `editor.iomap`.
Both containers follow their own child lists: `WidgetTabbedPane` always did, and
`WidgetSplitPane` re-derives its layout when its slot list changes (see
[widget.md](widget.md#a-split-pane-follows-its-slots)).

`test_pane_construct` asserts it the only way that works: after every structural
edit it compares the standing render against a fresh print of the same tree. A
test that asserts on the tree alone passes while the screen is stale.

## Renaming is not a mode

A tab's title is a text document. Putting the caret in it **is** the editing
state, so `F2` and `Escape` only move the selection, and the editing itself is
the title document's own business: each keystroke is handed to
`read_gesture(title, …)`, whose `@gestures PrimitiveString` table inserts and
deletes, and the answer is re-rooted onto the tree. This slice writes no editing
code, and declares no rename operation.

*(v1: the name changes as you type, but the caret is not drawn in the strip — the
strip prints the title as a label. Drawing it needs the strip to print the title
as a child document, which is follow-up work.)*

## The widget layer reports; the pane decides

`WidgetTabbedPane` grew three opt-in flags and three event-like operations for
this domain, and every other consumer can use them too:

| Flag | Draws | Reports |
|---|---|---|
| `closable` | a close button on each tab | `CloseTabRequestOperation(pane, index)` |
| `new_tab` | a button after the last tab | `NewTabRequestOperation(pane)` |
| `draggable` | nothing | `DragTabOperation(pane, index)` on a button down |

None of them decides what the gesture *means* — the strip knows a button was
pressed and nothing about tabs of a layout. `PaneTreeToWidget`'s reader answers
each report by finding the pane node that printed that widget and calling a
surgery builder. An unclaimed report is inert.

## The projection

`PaneToWidget()` is the first of two stages:

```julia
ChainingProjection(
    RecursiveProjection(PaneToWidget(; new_tab = my_factory)),
    renderer,
)
```

A tab's content passes through the first stage untouched, so `renderer` decides
how each content document is drawn — exactly as the workbench composes its own.
`make_pane_projection_example` builds one that knows widgets, layouts, and
primitive documents.

Each split slot is wrapped in a `LayoutConstraint` whose weight on the split axis
is the element's share. Where the parent seeded an available extent the slot also
takes a preferred extent of 0, so the allocator hands out the whole extent in
proportion to the weights and nothing else; where it did not, the slots fall back
to their intrinsic sizes.

## Try it

```julia
run_example(pane_example)         # three groups, four tabs
run_example(empty_pane_example)   # one empty group — build the rest yourself
```

The tests are `test_pane_surgery`, `test_pane_geometry`, `test_pane_to_widget`,
`test_pane_reader`, `test_pane_gestures`, `test_pane_drag`, `test_pane_rename`,
and `test_pane_construct` — the last builds a two-by-two layout from the empty
group with nothing but real gestures, through one standing iomap.
