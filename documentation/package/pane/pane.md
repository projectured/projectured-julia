# Pane Domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The pane tree is the generic way to organize documents on the screen: tab groups,
splits between them, and the gestures that rearrange the lot. It is implemented in
[package/ProjecturedPane/](../../../package/ProjecturedPane/) and rendered by

```
PaneTree ──PaneToWidget──► WidgetSplitPane / WidgetTabbedPane ──WidgetToGraphics──► GraphicsCanvas
```

A fresh layout starts as one empty tab group. Everything else — tabs, splits,
names, the arrangement — the user builds from there with the keyboard and the
mouse.

## Document types

All subtype `PaneDocument` (`<: Document`), defined in
[pane/Pane.jl](../../../source/pane/Pane.jl).

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
`WidgetSplitPane(:horizontal, …)`. `get_pane_split_axis` is that translation, and
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
| `make_pane_open_tab_operation` | `insert_elements` plus the focus move |
| `make_pane_duplicate_tab_operation` | the open of a new tab that holds the duplicate, right after the original |
| `make_pane_close_tab_operation` | `delete_elements`, or a collapse write, plus the focus move |
| `make_pane_split_operation` | `ReplaceReferencedValueOperation` writing a new `PaneSplit` at the group's slot |
| `make_pane_move_tab_operation` | `MoveRangeOperation` plus the focus move |
| `make_pane_drop_split_operation` | the split write, the move, and the focus move |
| `make_pane_resize_operation` | one write of the weights |
| `make_pane_focus_operation` | `ReplaceSelectionOperation` |
| `make_pane_retarget_title_operation` | `ReplaceStringRangeOperation`, re-rooted |

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

[PaneGeometry.jl](../../../source/pane/PaneGeometry.jl) gives every
group a rectangle in the unit square by one walk of the tree with its weights. No
font, no measurement, and no backend takes part.

- `get_pane_rectangles(tree)` / `get_pane_rectangle(tree, group)` / `get_pane_group_at_point(tree, x, y)`
- `get_pane_neighbour_group(tree, group, direction)` — the group in `:left`,
  `:right`, `:up`, or `:down`. A candidate must lie wholly past the edge and
  overlap on the other axis; the nearest wins, then the one that overlaps most.
- `get_pane_next_group(tree, group; backward)` — the depth-first traversal order,
  wrapping at both ends.
- `get_pane_drop_zone(tree, x, y; strip, band)` — the group under a point and which
  part of it: `:strip`, `:center`, or one of the four edge bands.

The rectangles are **proportional**: they ignore the few pixels a border and a
splitter take. That is exact enough to decide a direction, a drop zone, or which
pane a click landed in, and it is not a pixel-accurate model of the drawing.

## Keyboard

The table is `@gestures PaneTree` in
[PaneGestures.jl](../../../source/pane/PaneGestures.jl).

| Gesture | Effect |
|---|---|
| `Ctrl+T` | Open a new tab in the focused group, and select its empty content |
| `Ctrl+W` | Close the focused tab |
| `Ctrl+Shift+D` | Duplicate the focused tab |
| `Ctrl+\` | Split vertically — the new pane on the right |
| `Ctrl+Shift+\` | Split horizontally — the new pane below |
| `Ctrl+Alt+Left/Right/Up/Down` | Move the focus to the group in that direction |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Traverse the groups |
| `Ctrl+PageDown` / `Ctrl+PageUp` | Focus the next / previous tab |
| `F2` | Put the caret in the tab's name |
| `Escape` | Leave the name |
| `Alt+Left` / `Alt+Right` | From a whole tab, select the previous / next tab of its group |
| `Alt+Down` | From a whole tab, select its content as a whole |

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
| Click a tab's close button, the `x` | Close it |
| Click the `+` above a tab's `x` | Duplicate it |
| Click the new-tab button | Open a tab, and select its empty content |
| Click a pane's content | Place the caret in the document the tab holds |
| Alt+click a pane's content | Select the object under the pointer, or the tab's content as a whole |
| Click anywhere else in a pane | Focus that group |
| Drag a splitter | Write the split's weights — at any depth, and from wherever the divider is now |
| Drag a tab onto a group's strip or middle | Move it into that group |
| Drag a tab onto a group's edge band | Split that group, the tab in the new pane |

A click in a pane's empty space focuses it. Without that, most of a pane would be
dead: its content is a document that ends where its text ends, so a press beside
the text hits no element at all.

A click ON the content is the other half, and it names a place inside that
document. The tabbed pane hands the press to the page and prefixes what comes
back with the tab, so the path that reaches the tree runs `tabs[i].content` and
then into the domain of the content. That is what puts a caret in a form field
that lives in a pane, and what gives the next key somewhere to go.

## A new tab is filled by a paste

A new tab holds the empty placeholder, `DocumentNothing`, and `Ctrl+T`, the
new-tab button and a split select that placeholder as a whole. A paste writes
where the selection is, so `Ctrl+V` fills the tab. A tab that `open_pane!`
opens with a real document keeps the selection on the tab.

A new tab has an empty name, and `get_pane_tab_title_string` calls a tab with an
empty name after its content: the content's `get_document_title`, and
"untitled" when there is none. A pasted object therefore names its tab. `F2`
still writes a name of the tab's own.

A paste never replaces a pane, and a pane is never pasted. When a whole tab
has the focus, a copy and a note take what the tab shows
(`find_clipboard_document`), so `Ctrl+C` after a click on a tab copies its
content. A group, a split and the tree give a copy nothing.

## Selecting inside a page

An Alt+click inside a page selects the object under the pointer (see
[widget.md](../widget/widget.md#selecting-a-whole-object)). When the content's
projection maps that object back to a whole document, the selection is that
document. When it answers a caret, or a place it introduced, the selection is
the innermost document on that path: the document that holds the caret, or the
one the place was printed for. When it maps nothing back, the selection is the
tab's content as a whole. So any tab's content can be selected, whatever its
projection maps.

The tabbed pane rings its page while the page's document is selected as a
whole. The tree's own widget, the composite that carries the drop indicator,
follows the tree's selection, so it names the pane layer only when the tree's
root is selected.

At a tab, the pane answers the Alt arrows itself: the generic walk would step
from a tab's content to the tab's title, which is not an object of the content.
The root of a tab's content has no sibling, and a whole tab is the top of the
walk.

A window whose content is wrapped in a clipboard still answers
`get_window_tree`: the tree inside the clipboard.

## Every edit is reactive

A split, a collapse, a tab opened or closed all reach the screen through the
IoMaps that are already standing — no re-print, and no drop of `editor.iomap`.
Both containers follow their own child lists: `WidgetTabbedPane` always did, and
`WidgetSplitPane` re-derives its layout when its slot list changes (see
[widget.md](../widget/widget.md#a-split-pane-follows-its-slots)).

`test_pane_construct` asserts it the only way that works: after every structural
edit it compares the standing render against a fresh print of the same tree. A
test that asserts on the tree alone passes while the screen is stale.

## A splitter drag, twice

The widget anchors a drag on its measured `sizes` and materializes them only when
they are empty. This projection answers every resize with a **weight** write and
never lets `sizes` be written, so after one drag they still hold what was measured
at that grab. The grab is therefore answered with a compound that **clears them
first**: each drag re-measures what is on screen, and the divider starts where it
is rather than jumping back to where the last drag began.

## Every drop lands

A drop on an edge band splits the landing group, and the tab that arrives may
have been the last one in the group it left — which then goes away, and takes its
parent split with it when that leaves one element. The drop is two structural
writes whose paths each have to be named against the tree the other leaves
behind, and `make_pane_drop_split_operation` names them by shape:

| The source's parent | The writes |
|---|---|
| — (the source keeps a tab) | the split, at the target's own slot |
| holds the source and the target, nothing else | one write: the new split replaces the parent |
| holds the source and one other element | the split first — a group's slot is one the collapse can not move — then the sibling takes the parent's slot |
| holds three or more | the split first, then the source is spliced out with its weight |

`test_pane_drag` walks all four shapes against a source that survives and one
that is emptied, in all four bands, and asserts each leaves a well-formed tree
with the tab in a pane of its own.

## The drop indicator

While a tab is held, one `WidgetHighlight` shows where it would land: the whole
of the target group for a drop that moves the tab into it, and the half a new
pane would take for a drop on an edge band.

It is **always in the widget tree**, in slot 2 of a `WidgetComposite` whose slot
1 is the layout — only its position, size and `visible` move. That is what keeps
the widget tree the same shape whether a tab is held or not, so showing the
indicator costs no re-print and changes no reference mapping.

A composite is what can carry the overlay: it hands each child the extent it was
given itself, so the panes still divide the whole window, and it places each
child at its own position, so the indicator can sit anywhere over them. A
`StackLayout` clears the available size for its children, which would collapse
the split panes to their intrinsic sizes.

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

## A duplicate is a pane of its own

A duplicate of a tab is a second pane that the person controls on its own. The
kind of the content decides how deep the copy goes, by three rules:

1. **The duplicate owns what the person controls in the pane**: the form fields
   of a runner, the transcript and the composer of an assistant, the title and
   the query of a plot. An edit in one pane does not change the other.
2. **The duplicate shares what the pane reads**: the project, the result files,
   a data frame, the model backend.
3. **The duplicate does not copy a process.** A run that goes on and a turn that
   streams stay with the original, and the duplicate starts idle.

The copy is `make_document_duplicate` (see
[document.md](../kernel/document.md#the-duplicate)). A tab whose content has no
duplicate shows no `+`, and `Ctrl+Shift+D` on it does nothing and logs the
reason. The duplicate is the next tab of the same group, with the focus, and its
title gets a number: the duplicate of "Runner" is "Runner (2)", and the
duplicate of "Runner (2)" is "Runner (3)".

**A duplicate is not a mirror.** A mirror is the same document in two panes. Each
document node stores its own `selection`, so two panes that hold one document
share one caret, and a mirror with two carets needs a view state apart from the
document.

The assistant duplicates a pane with `duplicate_pane!(editor, reference)`. It
places the duplicate as the gesture does, except in the group that
`pane_group_to_avoid` names: there it places it as `open_pane!` does, so the
conversation stays in view.

## The widget layer reports; the pane decides

`WidgetTabbedPane` has four opt-in flags and four event-like operations that
this domain uses, and every other consumer can use them too:

| Flag | Draws | Reports |
|---|---|---|
| `closable` | a close button on each tab | `CloseTabOperation(pane, index)` |
| `new_tab` | a button after the last tab | `OpenTabOperation(pane)` |
| `draggable` | nothing | `DragTabOperation(pane, index)` on a button down |
| `duplicable` | a `+` above the close button of each page that offers a duplicate | `DuplicateTabOperation(pane, index)` |

The pane printer sets `duplicable` on every group, and sets each page's own flag
from `has_document_duplicate` of the tab's content.

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
