# Pane layout: tab groups, splits, and drag and drop

> **Status: DONE.** Implemented on branch `pane-layout`, one commit per step. The
> slice is `package/visual/main/pane/`; the guide is
> [package/visual/doc/pane.md](../../package/visual/doc/pane.md). Eight test
> functions cover it, ending with `test_pane_construct`, which builds a
> two-by-two layout from the empty group with nothing but real gestures through
> one standing iomap. What the implementation changed about this plan is recorded
> step by step below.

A generic way to organize documents on the screen. The user starts with one
empty tab group. The user then opens tabs, splits groups, closes tabs, moves the
focus with the cursor keys, renames a tab in place, and drags a tab from one
group into another or onto the edge of a group to split it.

## Goal

The system must support these operations, from the keyboard and from the mouse:

1. Create a new tab in the focused tab group.
2. Split the focused tab group vertically. The new pane lands on the right.
3. Split the focused tab group horizontally. The new pane lands below.
4. Close a tab in a tab group.
5. Move the focus between tab groups with the cursor keys, in graphical
   directions. Traverse the tab groups in order with a Tab chord.
6. Rename a tab in place.
7. Drag a tab from one tab group into another tab group.
8. Drop a tab on the edge of a tab group. The drop splits that group.

## Vocabulary

The words below are the only words the code uses for these things.

| Word | Meaning |
| --- | --- |
| pane tree | The whole layout. One document. |
| split | An inner node. It holds an orientation, two or more children, and one weight per child. |
| group | A leaf node. It holds an ordered list of tabs. A group is a tab group. |
| tab | A title and a content document. |
| focus | The selection. There is no second field for it. |
| zone | A part of a group that a drop lands in: the strip, the center, or one of the four edge bands. |

**Vertical and horizontal.** A vertical split has a vertical divider, so the two
panes sit side by side. A horizontal split has a horizontal divider, so one pane
sits above the other. This is the Vim meaning. The orientation symbol that goes
to `WidgetSplitPane` is the opposite word, because that symbol names the axis the
children lay out along: a vertical split prints `WidgetSplitPane(:horizontal, …)`.
The projection is the one place that translates between the two.

## Where the code lives

A new slice `package/visual/main/pane/`, between `widget/` and `syntax/` in the
visual slice order:

```
style → screen → graphics → layout → text → widget → pane → syntax → …
```

```
package/visual/main/pane/
    Pane.jl            # PaneTree, PaneSplit, PaneGroup, PaneTab + the operations
    PaneSurgery.jl     # the tree edits: open, close, split, move, collapse
    PaneGeometry.jl    # normalized rectangles, direction search, traversal order
    PaneToWidget.jl    # the projection to WidgetSplitPane / WidgetTabbedPane
    PaneGestures.jl    # the @gestures tables
```

### Why a document slice and not more widgets

The question is fair, because a widget tree here **is** a document
(`WidgetDocument <: Document`), and a splitter drag already edits a widget in
place. So this is not a rule, it is a trade. Three facts decide it.

1. **A tab holds a foreign document.** A `WidgetTabbedPane` holds widgets, so
   every tab must be projected to a widget before it goes in. A `PaneTab` holds
   the raw document — a JSON file, a chart, a workbench panel — and the recursion
   picks its projection, one per tab. The strip can then read the content (its
   name, whether it changed) because the content is still itself.
2. **The invariants belong to this pattern, not to the primitive.** "A split has
   two or more children", "an empty group collapses out of its parent", "two
   nested splits with the same orientation flatten into one" are rules of a pane
   layout. `WidgetSplitPane` must stay a primitive that any projection can use
   without inheriting them.
3. **The small tree is what you navigate, test, and save.** Directional
   navigation and drop-target arithmetic run on four node kinds with no font, no
   measure, and no backend. The render tree is the same shape plus title bars,
   strips, buttons, scroll panes, and drop indicators.

The precedent is `screen/`, already a slice in visual: `ScreenDocument` and
`WindowDocument` organize windows, carry structural operations
(`OpenWindowOperation`, `CloseWindowOperation`, `ResizeWindowOperation`), and
project through widgets. A pane tree organizes panes inside one window. It is the
same shape, one level down, so it sits in the same package.

The slice stays in visual, not in domain, so a visual-level application can use
it. The workbench, which is above it, can adopt it later.

## Document model

```julia
abstract type PaneDocument <: Document end

@document struct PaneTab <: PaneDocument
    title::Any                    # a PrimitiveString — editable in place
    content::Any                  # any Document
    icon::Any = nothing
end

@document struct PaneGroup <: PaneDocument
    tabs::CellVector              # PaneTab
end

@document struct PaneSplit <: PaneDocument
    orientation::Symbol           # :vertical (side by side) | :horizontal (stacked)
    elements::CellVector          # PaneGroup | PaneSplit
    weights::CellVector = CellVector()   # one Float64 per element, sum 1.0
end

@document struct PaneTree <: PaneDocument
    root::Any                     # PaneGroup | PaneSplit
    drag::Any = nothing           # transient drag state, not serialized
end
```

There is **no `active` field**. The selection decides which tab a group shows.
See the next section.

Every struct keeps at least one required field, so `@document` gives the
positional constructors. Do not add a default to `title`, `content`, `tabs`,
`orientation`, `elements`, or `root`.

### Invariants

1. `PaneTree.root` is a `PaneGroup` or a `PaneSplit`.
2. A `PaneSplit` holds two or more elements. A split that falls to one element is
   replaced by that element.
3. A `PaneGroup` can be empty. An empty group is removed from its parent split.
   An empty root group stays — it is the start state.
4. `weights` has one entry per element and sums to 1.0. An empty `weights` means
   equal weights.
5. A split never holds a child split of the same orientation. The surgery
   flattens it, because `WidgetSplitPane` is n-way.

`PaneSurgery.jl` holds one function per edit, and each function restores every
invariant before it returns. The projection and the reader never edit the tree
by hand.

## Focus is the selection

There is no `focused` field. The tree's `selection` names the focused tab:

```
root.elements[2].tabs[3]      # the third tab of the second element
root.elements[2]              # an empty group: the group itself, an ∅ selection
```

Three rules follow.

- The focused group is the group on the selection path.
- The tab a group shows is the tab its own `selection` names. `@document` injects
  that field into every node, so no field is added for it. This is what
  `WorkbenchPageToWidgetTabbedPane` already does: it answers a tab click with a
  plain `ReplaceSelectionOperation` and forwards the page selection onto
  `WidgetTabbedPane.selection`, with no write to the widget.
- Every focus move, and every tab switch, is one `ReplaceSelectionOperation`.

**The consequence to accept.** `_sync_selection!` clears the divergent branch when
the selection moves, so a group that loses the focus loses its own selection, and
`WidgetTabbedPane` then falls back to its first tab. An unfocused group therefore
shows its first tab. If that turns out to look wrong in use, two remedies need no
document field: latch the last in-group value in the printer's selection cell,
which is view state at the view layer, or move the focused tab to the front of
the group. Do not add a field back without trying those.

## Operations

**This slice declares no operation of its own.** Every edit is a generic
operation, or a `CompoundOperation` of two of them. The operation guide states
the rule: reach for `ReplaceReferencedValueOperation` or one of its builders
before you write a new operation struct.

The reason is re-rooting. A generic write with `document === nothing` carries a
reference that every container re-roots as the operation bubbles up. So a pane
tree keeps working when it sits **inside** another document — a tab of one pane
tree that holds a workbench that holds another pane tree. A bespoke operation
that carries a group by identity would bubble up unchanged, which looks simpler
and then breaks the moment the tree is nested or the same group object appears
twice.

`PaneSurgery.jl` therefore holds **operation builders**, not operation types.
Each one takes the tree, the target, and the reference of the target, and returns
the generic operation to emit.

| Edit | Generic form |
| --- | --- |
| Open a tab | `insert_elements(path_to(group) ⧺ tabs, i, [tab], sel)` — a zero-width splice plus the focus move |
| Close a tab, others remain | `delete_elements(path_to(group) ⧺ tabs, i)` plus a `ReplaceSelectionOperation` to the neighbour tab |
| Close the last tab, the parent split holds three or more | `delete_elements(path_to(parent) ⧺ elements, k)` plus the same on `weights`, plus the focus move |
| Close the last tab, the parent split holds two | `replace_document(path_to(parent), sibling)` plus the focus move |
| Split a group | `replace_document(path_to(group), PaneSplit(orientation, [group, new_group], [0.5, 0.5]))` plus the focus move |
| Move a tab between groups | `MoveRangeOperation(source.tabs, a, b, target.tabs, i)` plus the focus move |
| Drop a tab on a group's edge | the split write, the move, and the focus move — `pane_drop_split_operation`, added during step 8 |
| Resize a split | one `ReplaceReferencedValueOperation` per changed weight, in a `CompoundOperation` |
| Move the focus, switch the tab | `ReplaceSelectionOperation` |
| Rename a tab | `ReplaceStringRangeOperation`, from the existing text gestures |

Three notes on the table.

- **The surgery reuses node objects. It never rebuilds a subtree.** A split puts
  the *existing* group object in the new split, and a collapse writes the
  *existing* sibling at the parent's path. Only the node that goes away is
  dropped. A rebuilt subtree would drop the iomaps below it, so every tab would
  re-print and lose its scroll position and its caret.
- `MoveRangeOperation` already exists for this exact job: it relocates
  `CellVector` elements across two vectors and preserves cell identity, so the
  moved tab keeps its content iomap. It carries the two vectors, which is correct
  here — a vector is not addressed by a path.
- A split gives the new split the weight the group had, and gives the two
  children 0.5 each, so the rest of the layout does not move.

### The widget layer reports, it does not decide

Three event-like operations are added in step 3, beside the `SelectTabOperation`
that exists today. They are not writes and can not be generic: the widget knows
that a button was pressed, and nothing about what it means. The operation guide
already lists `SelectTabOperation` as legitimately distinct for this reason. Each
one travels exactly one stage, from `WidgetToGraphics` to the pane reader, which
answers with a generic operation from the table above.

| Operation | Reported when |
| --- | --- |
| `SelectTabOperation(pane, index)` | exists today; a click on a tab |
| `CloseTabRequestOperation(pane, index)` | a click on a tab's close button |
| `NewTabRequestOperation(pane)` | a click on the strip's new-tab button |
| `DragTabOperation(pane, index)` | a mouse button goes down on a tab |

## Geometry and navigation

`PaneGeometry.jl` computes a normalized rectangle for every group by one walk of
the tree with the weights. The result is in the unit square. No pixel and no font
takes part, so the arithmetic is testable on its own.

**Direction search.** To move right from group `g`, take the groups whose left
edge is at or past `g`'s right edge, keep the ones whose vertical span overlaps
`g`'s span, and pick the nearest one. Break a tie by the larger overlap, then by
the higher top edge. The other three directions are the same with the axes
exchanged.

**Traversal order.** The groups in the order a depth-first walk of the tree
reaches them. The traversal wraps around at both ends.

## Keyboard

The tables live in `PaneGestures.jl` as `@gestures PaneTree`. The pane
projection calls `read_gesture(tree, event)` and the table fires.

Every binding needs a modifier, because the plain keys belong to the content of
the focused tab.

| Gesture | Effect |
| --- | --- |
| `Ctrl+T` | Open a new tab in the focused group. |
| `Ctrl+W` | Close the focused tab. |
| `Ctrl+\` | Split vertically. The new pane lands on the right. |
| `Ctrl+Shift+\` | Split horizontally. The new pane lands below. |
| `Alt+Left/Right/Up/Down` | Move the focus to the group in that direction. |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Traverse the groups forward and backward. |
| `Ctrl+PageDown` / `Ctrl+PageUp` | Focus the next and the previous tab of the focused group, which is what shows it. |
| `F2` | Put the caret in the focused tab's title. |
| `Escape` | Put the selection back in the tab content. |

The content of a tab reads an event first, and the pane table fires only when the
content claimed nothing. If a chord above turns out to be claimed by a content
domain, wrap that one rule in `override(…)`. Test each chord inside a text
document before you accept it.

The user asked for the Tab key. Plain `Tab` can not do this work, because a text
document takes it. `Ctrl+Tab` is the traversal.

## Mouse

| Gesture | Effect |
| --- | --- |
| Click a tab | Focus that tab. `SelectTabOperation` becomes one `ReplaceSelectionOperation`. |
| Click a tab's close button | The close builder. |
| Click the new-tab button | The open builder. |
| Click inside a pane | Focus that group, then route the click into the content. |
| Double-click a tab title | Put the caret in the title. |
| Drag a splitter | Write the weights of the `PaneSplit`. |
| Drag a tab onto a strip | Move the tab into that group at the drop index. |
| Drag a tab onto a center zone | Move the tab into that group, at the end. |
| Drag a tab onto an edge band | Split that group and put the tab in the new pane. |

The splitter drag already works at the widget level, but it writes `sizes` on the
widget. The pane reader must catch `ResizeSplitPaneOperation` and write the
`weights` of the matching `PaneSplit` instead. Without this the drag is lost on
the next print.

## Drag and drop

The state machine lives on `PaneTree.drag`, which is transient and is not
serialized:

```
nothing
  → (source_group, source_index, x, y)          on DragTabOperation
  → …, target_group, zone                       on each MouseMove
  → nothing, and one operation                  on MouseUp
```

**How a drop target is found.** The pane readers hit-test the pointer against
their own children. They can, because they printed those children and hold the
child iomaps with their offsets — this is what `_route_active_tab` already does
inside `WidgetTabbedPaneToGraphicsCanvas`. Do not synthesize a `MousePress` at
the drop point, as `DraggingProjection` does: a press inside a pane's content
answers with a content operation, which says nothing about which group it landed
in.

**Zones inside the landing group.** The strip gives an insert index. Below the
strip, an edge band of 20 percent on each of the four sides gives a split; the
center 60 percent by 60 percent gives a plain move. A band wins over the center.

**Feedback.** The printer reads `drag` and draws a translucent rectangle over the
target zone. Put it in a z-stack over the tree with `StackLayout(children;
active=0)`. Read `drag` **inside** a cell, or the indicator freezes — see
`documentation` on reactive printers.

**Backend facts that this relies on.** SDL sends `MouseDown` on the press,
`MouseMove` with the held button during the drag, and `MouseUp` on the release.
It synthesizes a `MousePress` only for a click. So a drag never produces a
`MousePress`, and a click never produces a spurious drag.

## Widget layer additions

These land in `package/visual/main/widget/Widget.jl` and
`WidgetToGraphics.jl`. Every consumer of `WidgetTabbedPane` gets them, the
workbench included.

1. **A document selector.** `WidgetTabPage.selector` may be a `Document`. The
   printer prints it as a child widget instead of `string(pair.selector)`. This
   is what makes the in-place rename possible.
2. **A close button per tab.** A `closable` flag on the pane. The printer draws
   the `:close` icon at the tab's right edge and the reader answers a click on it
   with `CloseTabRequestOperation`.
3. **A new-tab button.** A `new_tab` flag on the pane. The printer draws the
   `:plus` icon after the last tab; a click answers `NewTabRequestOperation`.
4. **The strip claims a mouse button down.** Today `MouseDown`, `MouseUp`, and
   `MouseMove` always route to the active tab's content. The strip must answer a
   `MouseDown` on a tab with `DragTabOperation` instead. The strip must not claim
   `MouseMove` when no drag runs, or hover feedback stops.

`_tab_strip_geometry` is the one place that computes the tab boxes, and both the
printer and the reader read it. Extend that function, not its two callers, or the
drawn tab and the hit-tested tab drift apart.

## The empty start

`PaneTree(PaneGroup(PaneTab[]))` is the start state. An empty group has no tab to
select, so the selection is the group itself, as a whole-element `∅` selection.
The empty group must:

- draw a strip that holds only the new-tab button,
- draw a muted hint in the pane body,
- accept the focus, so `Ctrl+T` reaches the table.

## Steps

Do the work in a dedicated git worktree. Make one commit per step. Mark each step
here when it is done, and record what the implementation changed about the design.

1. **Done. Add the documents and the surgery builders.** `Pane.jl` and
   `PaneSurgery.jl`: the four document types, and one builder per edit that
   returns a generic operation. No operation struct. Register the slice in
   `ProjecturedVisual.jl` and in the visual slice order.
   *Done when* `test_pane_surgery()` evaluates each builder's operation and
   covers open, close, split, move, the collapse of an empty group, the collapse
   of a one-element split, and the flatten of same-orientation splits — and
   asserts that the surviving nodes are the same objects (`===`).

2. **Done. Add the geometry.** `PaneGeometry.jl`: the rectangles, the direction search,
   and the traversal order.
   *Done when* the tests cover a three-way and a nested layout, all four
   directions, the no-neighbour case, and the wrap-around of the traversal.

3. **Done, in part. Extend the widget layer.** Three of the four additions
   landed: the close button, the new-tab button, and the grab, each behind an
   opt-in flag (`closable`, `new_tab`, `draggable`) and each answering an
   event-like report. `test_widget_tab_strip` sweeps the strip and asserts which
   report appears where, so it fixes no pixel.

   **The document selector moved to step 7 and then turned out to be
   unnecessary.** Printing the title as a child document would have needed the
   selector's iomaps stored in the tabbed pane's own iomap — its `child_iomaps`
   holds `(x, y, iomap)` triples by a convention several widgets share — and the
   rename works without it (see step 7). What is lost is the caret *drawn* in the
   strip; the name still changes as you type.

4. **Done. Print the tree.** `PaneToWidget.jl`: a split prints a `WidgetSplitPane` with
   the translated orientation and the weights, a group prints a
   `WidgetTabbedPane`, a tab's content recurses. Map the references both ways.
   Print the empty state.
   *Done when* `test_printer(pane_example)` passes and the selection maps forward
   and backward through both node kinds.

5. **Done. Read the mouse.** Tab click, close, new tab, a click in a pane body,
   and the splitter drag that writes the weights.

   Two things the implementation found:

   - **The tree is transparent, so it shares its root's widget.** The search that
     answers "which pane node printed this widget" must look at the children
     *before* itself, or every group's report is answered by the tree.
   - **A click in a pane's empty space hit nothing at all.** A pane's content is
     a document that ends where its text ends, so most of a pane is not an
     element. The reader now falls back: a press that nothing claimed focuses the
     group it landed in, resolved through the same rectangles the drag uses.

6. **Done. Add the keyboard.** The `@gestures PaneTree` table, and the three key
   symbols it needs added to the SDL vocabulary (`:t`, `:w`, `:backslash`).

   **The directional chord became `Ctrl+Alt`+arrow, not `Alt`+arrow.** Plain
   `Alt`+arrow is the structural navigation of a document — `@gestures
   SyntaxCompound` binds it — so the pane layer takes the next chord out rather
   than fighting a content domain for it. `Ctrl+Tab` is declared `override`,
   because the widget split pane answers every `Tab` with its own traversal.

7. **Done, by a shorter route. Rename in place.** The title is a
   `PrimitiveString` and `F2`/`Escape` only move the selection, exactly as
   planned — but the strip does **not** print it through a `WidgetText`. Instead
   the pane's own table hands each keystroke to `read_gesture(title, …)`, whose
   `@gestures PrimitiveString` rules insert and delete, and re-roots the answer
   onto the tree. So the editing code is still not written twice, and the widget
   layer needed no change at all.

   Two things this route costs: the caret is not drawn in the strip (the name
   changes as you type, with no visible cursor), and the rule bodies do their own
   guarding, because a `when(…)` guard sees the event's fields and not `doc`.

8. **Done, without the indicator. Add drag and drop.** The state machine lives on
   `PaneTree.drag` and runs in a four-argument reader, because a drag needs the
   raw gesture even when the layers below already turned it into an operation.

   **The pointer is resolved against the layout tree, not the printed canvas.**
   The pane stage prints *widgets*, so it holds no coordinates at all; the groups
   divide the available extent in proportion to their weights, so a group's
   unit-square rectangle is where it is drawn. The strip is the one part with a
   fixed height rather than a share, so its band is converted from pixels.

   Two things are not done:

   - **The drop indicator.** Drawing it needs an overlay layer of constant shape
     over the root widget, so the tree does not change shape mid-drag; that is a
     reference-mapping change, not a drawing one.
   - **A split-drop that would empty its source group is declined.** The collapse
     of the emptied group and the split of the target are two structural writes
     whose paths would each be named against the tree the other leaves behind. A
     drop in the target's middle handles that case, and does collapse the source.

9. **Done. Add the example and the guide.** `pane_example` and
   `empty_pane_example`, `make_pane_projection_example`, a new
   [pane.md](../../package/visual/doc/pane.md), and the widget and architecture
   guides updated. The example projection landed early, in step 6: a fresh tab
   holds an empty text document, so the tests needed a renderer that knows one.

10. **Done. Build the layout from empty.** `test_pane_construct` starts from
    `PaneTree(PaneGroup(PaneTab[]))` and uses **one projection and one iomap** for
    the whole sequence, as a live editor would: 39 assertions covering the first
    focus, four named tabs, a two-by-two layout, a drag between groups that
    collapses the emptied one, a click to focus, and a close. It is what found
    the two faults recorded in step 5.

## Traps

These come from earlier work in this repository. Each one has cost a debug
session before.

- **Print inside a cell.** A printer that reads a cell outside a cell freezes the
  render. The drag indicator and the tab strip both read state that changes
  during one gesture.
- **A pass-through reader must return only operations.** If the pane reader
  returns a raw gesture, `SequentialProjection` loses its first say. Write
  `op isa Operation ? op : nothing`.
- **Test in a real editor, not only by direct read.** A reuse fault in the iomap
  passes a direct read and a fresh re-print, and still fails live. Step 10 is
  what catches it.
- **Leave `document` at `nothing`.** A generic write that carries a root bubbles
  up unchanged and is never re-rooted. That is right for a widget's own field and
  wrong for every edit of this slice, which must survive a nested pane tree.
- **The type checkpoint is a field of the node.** Build a reference with
  `@reference` or with `reference_node_type(doc)`, never with `typeof`.
- **Do not truncate a selection to its head.** `elements[i]` is two nodes. Keep
  both, or the routing loses the index.

## Deferred

These are out of the scope of this plan, or fell out of it. Record them so the
design leaves room.

- The **drop indicator**, and the **caret in a tab name** — both need the widget
  tree to gain a layer without changing shape (step 8 and step 7).
- A **split-drop that empties its source group** (step 8).
- **Reorder tabs inside a group by dragging.** The strip's drop zone means "into
  this group, at the end"; the insert index a drop between two tabs implies needs
  the strip's own geometry, which lives in the widget layer.

- Detach a tab into its own window. A drop outside the tree becomes an
  `OpenWindowOperation` of the `screen/` slice.
- Save and restore a layout. The tree is a document, so this is serialization
  work, plus a rule that `drag` stays out.
- Maximize one group, and equalize the weights of a split.
- A most-recently-used focus order as an alternative to the geometric search.
- Move the workbench onto the pane tree. The workbench keeps its four fixed pages
  until a later plan replaces them with one `PaneTree`.
