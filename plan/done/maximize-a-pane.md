# Maximize a pane

> **Status (2026-11-03):** done, on the branch `maximize-pane`. The owner answered
> the three questions of what the person sees (Q1 to Q3) and approved the plan
> with D1 to D6. D3 changed its place during step 2; the reason is under D3.

## The goal

Ctrl+M in a window of panes makes the focused group fill the window. Ctrl+M again
gives back the layout as it was: the same splits, the same sizes, the same tabs.

An example. The window has three groups, and the focus is on `a.json`:

```
before Ctrl+M                      after Ctrl+M
┌──────────┬──────────────────┐    ┌──────────────────────────┐
│ Explorer │ a.json* | b.json │    │ a.json* | b.json         │
│          │ { "items": … }   │    │ { "items": [ … ] }       │
│          ├──────────────────┤    │                          │
│          │ Assistant        │    │                          │
└──────────┴──────────────────┘    └──────────────────────────┘
```

## The questions and the answers

- **Q1. What fills the window?** The focused group, with its tab strip.
  Ctrl+PageDown shows `b.json`, and the window stays maximized. (The owner,
  2026-11-03.)
- **Q2. What happens when the focus goes to a different group?** The layout comes
  back. Examples are Ctrl+Tab, Ctrl+Alt+arrow, and a file that opens from the
  Explorer into the documents group. (The owner, 2026-11-03.)
- **Q3. Does a saved layout remember the maximize?** No. A `.pred` file holds
  the layout only, and a load shows all groups. (The owner, 2026-11-03.)
- **The key.** Ctrl+M, in the key table of `PaneTree`, as the owner proposed. No
  code in projectured-julia or omnet-julia binds Ctrl+M. Two facts that the owner
  knows:
  - A terminal sends the same byte for Ctrl+M and Return, so the console backend
    reads Ctrl+M as Return. The SDL window and the web backend tell them apart.
  - `documentation/design/interface-composition.md` §4.2 of omnet-julia plans
    Ctrl+M for "mark the focused subject". That plan needs a different key.

## The design

**D1. The state is a field of the tree.** `PaneTree` gets the field `maximized`:
`nothing`, or the `PaneGroup` object that fills the window. `drag` holds groups
by object in the same way, and the surgery reuses group objects, so the field
stays correct when a split or a move changes the paths. The write is view state
(`ReplaceViewStateOperation`), as the write of `drag` is, so an undo records no
maximize. `pred_arguments` of `PaneTree` writes only `root`, so a save drops the
field (Q3) with no change.

**D2. One function says what shows.** `find_pane_maximized_group(tree)` answers
the group that fills the window, or `nothing`. It answers the group of the field
only when the tree holds that group and the focus is in that group or outside the
tree. Every view reads this function and not the field. So a view never hides
the group that has the focus, also after a focus move that D3 does not see. A
focus outside the tree, such as in a menu of the shell, keeps the maximize.

**D3. A focus move to a different group ends the maximize.** The operation that
moves the focus into a different group also writes `nothing` into the field.
Each builder of the surgery that moves the focus to a group gives its operation to
one helper, `_with_focus_restore(tree, group, operation)`, with the group that
takes the focus as an object. The helper adds the write when a different group is
maximized. Every focus move to a group comes from such a builder: the keys, the
press on the empty space of a pane, and the verbs, such as `focus_pane!` and an
open with `focus = true`. A builder that keeps the focus where it is, along a new
path, such as an open with `focus = false`, does not call the helper.

D2 alone shows the layout after such a move, but the field stays. Then the
maximize comes back when the focus comes back to the group, and Q2 does not
allow that.

*Changed during step 2 (2026-11-03).* The plan first put the check in two places
that see each finished operation: the reader of `PaneTreeToWidget` and
`_make_rooted_pane_operation`. That check must find the group from the path of
the last selection, against the tree as it is before the operation. One operation
can change the structure and move the focus, so the path is wrong in two cases: a
split of the maximized group names the new group through the old path of the
group, and a program that opens a pane beside the maximized group gives the same
focus a new path. The kernel has no function that maps a path through an edit.
The builders know the group by object, so the test there has neither fault.

**D4. A split pane gives no room to a slot that can have none.** The widget split
pane gives no extent to a slot whose maximum extent on the main axis is 0, and
it draws no splitter and no grab band beside that slot. This is a general rule
of the widget slice, with the fields that `LayoutConstraint` has now.
`PaneSplitToWidgetSplitPane` makes the maximum extent of each slot a computed
cell: 0 when `get_pane_maximized_group` answers a group that the slot does not
hold, else `nothing`. The split pane reads the maximum in its allocation and in
its list of graphics, and not in its list of slots. So no tab prints again: the
carets, the scroll positions and the IO maps stay, and a toggle costs one layout.

Two other ways, which I reject:

- Put the widget of the group into slot 1 of the composite of the tree. Each
  toggle then prints every group and every tab content again.
- Give the other slots a weight of 0 only. The splitters then stay visible at
  the edge, and a drag of one writes wrong weights into the layout.

**D5. The geometry has two views.** The functions of a point (the group at a
point, the drop zone of a tab drag, and the rectangle of the drop indicator) use
what shows: while a group fills the window, that group is the unit square and no
other group has a rectangle. The functions of a direction (the neighbour group
and the next group) use the layout. So Ctrl+Alt+Right goes to the group to the
right in the layout, and D3 then ends the maximize.

**D6. Ctrl+M does nothing when it has nothing to do.** It answers `nothing` when
the root of the tree is a group, because no other group exists, and when the
focus is not in a group.

## The steps

1. ✅ **The state and the key.** The field `maximized` of `PaneTree` (D1), with
   `is_field_walked(::PaneTree, :maximized) = false`, so a search finds the
   group only under `root`. `find_pane_maximized_group` (D2; `find_`, because it
   searches the tree and can answer `nothing`), `make_pane_maximize_operation` and
   `make_pane_restore_operation` in `PaneSurgery.jl`, and the rule
   `KeyDown(:m; ctrl)` "Maximize the focused group, or give back the layout" in
   `PaneGestures.jl` (D6). Tests in `test_pane_gestures`: the toggle, the two
   cases of D6, one search result, and a save that drops the field.
2. ✅ **The end of the maximize (D3).** `_with_focus_restore` and the builders that
   call it: the focus, the open of a tab with the focus, the close of a tab and of
   a group, the split with the focus, the move of a tab, and the drop on an edge.
   Tests in `test_pane_gestures`: Ctrl+Tab, Ctrl+Alt+arrow, a split, Ctrl+W of the
   last tab, a program focus and a program open with the focus clear the field;
   Ctrl+Tab back to the group does not maximize it again; Ctrl+T and
   Ctrl+PageDown, an open with `focus = false` and a split beside the group with
   `focus = false` keep it; a selection made by another way shows the layout and
   keeps the field; a selection outside the layout keeps the maximize. Steps 1
   and 2 are one commit, because both change the same parts of `PaneSurgery.jl`.
   `test_pane_gestures` passes: 117.
3. ✅ **The split pane rule (D4)** in `WidgetToGraphics.jl`:
   `_get_split_open_slots` and `_has_split_gap`. A cell of the build reads the
   maximum of each slot; the allocation divides the extent among the open slots,
   less one splitter for each pair of open neighbours, and the positions, the
   drawing, the grab bands and the measured sizes of a drag skip a closed slot.
   Two open slots with a closed slot between them touch with no splitter, because
   a drag of a splitter resizes two neighbours by index. Test in
   `test_split_pane_drag`: a slot with a maximum of 0 gets no extent, no splitter
   and no grab band, and a close and an open print no child again. It passes: 41
   and the 5 broken assertions that main has.
4. ✅ **The view (D4)** in `PaneToWidget.jl`. The split printer has no tree, so
   the tree printer gives it the tree in the print property `:pane_tree`, as the
   roster gives its document to its columns. `_get_pane_slot_maximum` computes the
   maximum of each slot. Test in `test_pane_construct`: after Ctrl+M the standing
   render equals a fresh print, the widget of each group is the same object, and
   a press where the left group stood lands in the maximized group; after the
   second Ctrl+M the same press lands in the left group. It passes: 62.
5. ✅ **The geometry (D5)** in `PaneGeometry.jl`. `get_pane_rectangles` answers
   what the window shows, so `get_pane_rectangle`, `get_pane_group_at_point`,
   `get_pane_drop_zone` and the drop indicator follow it; the neighbour search
   reads `_get_layout_rectangles`. Tests in `test_pane_geometry` (43) and
   `test_pane_drag` (259): a point and a drop zone in the maximized group, the
   neighbours in the layout, and a tab drag whose target and indicator cover the
   whole window. The other pane suites pass: surgery 122, reader 89, rename 38,
   to widget 44, tabs wrapper 15, window shell 145, drag tracking 60, window
   wrappers 58.
6. ✅ **The documents.** `pane.md`: the field in the table of documents, the key
   in the table of keys, the geometry, a section "Maximize a group", a design
   decision, and the three limits below. `widget.md`: the rule of D4. The data
   frame suite passes: 603. The naming guard passes. `test_platform_layering`
   fails 1 of 7, as on main: its list names files of the filechange, roster and
   shell slices, and none of this plan.
7. ✅ **A pixel check.** A real window takes the keyboard focus from the desktop
   of the owner, so the check ran with the offscreen SDL driver instead: one
   standing print of a window of three groups (Explorer; `a.json` and `b.json`
   over Assistant), the keys read through that print, and after each key a frame
   from the SDL renderer (`write_offscreen_frames!`). Ctrl+M: the group of
   `a.json` fills the window, with no divider. Ctrl+PageDown: `b.json` shows, and
   the window stays maximized. Ctrl+M: the layout comes back with its sizes.
   Ctrl+M and Ctrl+Tab: the layout comes back, and the focus is on Assistant. A
   Ctrl chord of a letter arrives as `KeyDown(:m)`, not as a `KeyPress`, because
   `find_typed_character` gives a character only for Return and Tab. No press of
   a real keyboard in a real window was made.

## Limits

- The console backend can not see Ctrl+M (see the key, above).
- A press on a link that selects a document in a different group by identity
  (`SelectDocumentOperation`) finds its place only when it is evaluated, so D3
  does not see it. D2 shows the layout, but the field stays until the next
  Ctrl+M, so the maximize comes back if the focus comes back to that group.
- The window shows no sign that a group fills it, other than the absence of the
  other groups.
