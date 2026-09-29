# The forward image of a part

> **Status:** pending; every open point is settled (2026-09-29). The owner chose
> this way on 2026-09-28 (way (c) of the question about where a tooltip that a
> command opens goes). Nothing is built. It comes before the mouse target of
> [a-document-knows-the-part-under-the-pointer.md](a-document-knows-the-part-under-the-pointer.md).

## 1. The purpose

A person runs "Show the tooltip" from the command palette on the selection, or
an agent runs it. The answer has no point, because no pointer rested. The
tooltip window must open beside the part, in screen coordinates.

D73 of [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md)
says how: at the forward image of the part. The tooltip wrapper already asks
for it (`find_part_point` in `source/screen/WindowLayers.jl`). But no widget
reference has a forward image today, so the window opens at the corner of the
screen, and one assertion of `test_tooltip_window()` is `@test_broken`.

The same map serves every follower that must stand at a part with no pointer:
the context menu from the palette (D73 too), and later a scroll into view.

## 2. The model

- **A forward map takes an input reference and returns an output reference** (Q6). It answers from its
  input and its own mapping, which is usually an index mapping, and it does not
  depend on what the printer computed or on what a lazy printer left out. It may
  read the output when it must, but most of the time it does not. So every part
  has a forward reference: also a part that is scrolled out of view (Q1), and a part
  on a closed tab or in a closed card (Q2).
- **In graphics, the image of a part is the reference of the node that draws
  it**, for example `.windows[1].content.elements[2]`, and not a point.
- **A caller that needs a place on the screen reads it from the printed
  output.** It evaluates the forward reference in the output of the screen and
  adds the places of the nodes that it reaches and the origin of the window,
  which gives the box of the part: its place and its size. A reference that
  reaches no printed node gives no box.
- **A window that a command opens stands below the part** (Q3): under its box,
  with the left edges aligned.
- The contract text of `map_reference_forward`
  (`source/kernel/projection/ProjectionInterface.jl`, not sealed) says today
  that the image in graphics is a `PointReferenceStep` and that "coordinates
  accumulate". It changes to this model. Its sentence that a popup is not placed
  by a reference stays: a popup that a press opens moves its point up with
  `map_operation_position`.

## 3. What is wrong today

Facts from a search on 2026-09-28, with the two central ones read again:

1. **Three higher-order wrappers stop the forward map.** `RecursiveProjection`
   (`source/projection/higherorder/Recursive.jl`), `PredicateDispatchingProjection`
   and `SwitchingProjection` answer `nothing` for every forward map, although
   each maps backward through its child. `TypeDispatching`, `ReferenceDispatching`,
   `Nesting` and `Chaining` delegate forward. The stub matters where a caller
   holds the wrapper itself: a stage of a chain, and the screen
   (`make_window_scene_projection` is a `RecursiveProjection`). The selection
   wiring calls the map on the projection of an IO map, which a recursive
   projection answers with the IO map of its child, so the wiring does not meet
   the stub.
2. **Many widget containers answer `nothing` forward**, although they map a
   point backward: the split pane, the tabbed pane, the title pane, the scroll
   pane, the transform pane, the toolbar, the context menu, the dialog, the menu
   item, the select and the status bar (`source/widget/WidgetToGraphics.jl`).
3. **The forward maps that exist answer points.** The composite, the menu, the
   card and the five layouts map forward with `descend_reference_forward` and
   `shift_child_image` (`source/layout/LayoutToGraphics.jl`), which add offsets
   to a point; the button, the option, the spin box and the list answer
   `PointReferenceStep(0, 0)` for themselves (`_self_point`); the screen adds the
   origin of the window to a point (`_map_window`, `_map_screen` in
   `source/screen/ScreenToScreen.jl`). There are 21 uses of these three
   helpers. They change to references.
4. **Text and charts map nothing forward.** `TextToGraphics`, the chart and the
   sequence chart answer `nothing`. The math projection maps forward.
5. **No function gives the place of an output reference.** The SDL and web backends
   and `get_canvas_content_bounds` walk a printed canvas and add offsets, for
   drawing and for bounds, and not for a reference.

## 4. The steps

- [x] 1. **The contract.** The docstring of `map_reference_forward` and
  [reference.md](../../documentation/package/kernel/reference.md) say the model
  of section 2.
- [x] 2. **The three wrappers map forward through their child**, as they map
  backward. Test first what this changes: the tests that print and read, and
  the selection wiring, because a map that answered nothing now answers.
  Done: `RecursiveProjection`, `PredicateDispatchingProjection` and
  `SwitchingProjection` delegate forward as they delegate backward. The wide
  sweep has the counts of the sweep of 9b/9c in every suite.
- [x] 3. **The widgets, the layouts and the screen map by index.** A container
  maps its own step to the step of its child's node in its output, and a leaf
  answers the empty reference for itself. The helpers that add points
  (`shift_child_image`, `_self_point`, the point in `_map_window`) change to
  references. A part that a lazy printer did not compute yet still has its
  output reference; a part that the projection does not display, such as the
  content of a tab that is not open, maps to `nothing` (Q2). Found in the work:
  - **The layouts map by index.** `make_slot_reference` gives a drawn child its
    slot, `elements[slot].elements[1]`, one `content` step deeper when a viewport
    clips it, which the node of the slot shows; it is the mirror of
    `_backward_descend`.
  - **The widget containers find a child by identity**, as their backward maps
    do (`_map_point_to_child`): a widget puts parts of its own before its
    children, such as the parts of its box, whose number varies. The child is
    the one whose input the reference reaches, and its canvas is found in the
    container's canvas by `find_node_reference` of the graphics package, which
    searches level by level through canvases and viewports and never into a
    linked list. Every widget forward method calls `_map_child_forward`; with no
    child IO maps it answers the empty reference for the widget itself.
  - **Some containers re-host their child's elements**, so the child's canvas is
    not in the output: the scroll pane shows the elements of its content in a
    canvas of its own, moved by the scroll, and maps `content` to the content of
    its viewport. The table list mirrors its rows, node for node, in a list of
    row canvases, and maps a row and a cell by index, also a row that the walk
    did not build yet. The eager table delegates to its grid layout and adds the
    steps to the grid's canvas. The math boxes and the graph layout add the
    steps to their children's canvases too.
  - **The forward helpers strip the node types first**, because a selection is
    a typed reference, whose type steps are no steps of the mapping.
  - **The rows of a list and the headers of an accordion had no node of their
    own**: the list drew the texts and the panels of its rows straight into its
    canvas, and the accordion its titles and chevrons. A row needs a canvas of
    its own to have an image. (The tree was thought to be the same, but it
    already makes a canvas per row of the open tree, when the renderer first
    reads it; it lacked only the forward map.) **Settled:** each row gets a canvas of its own, which
    holds the panels and the text of the row, and a row maps to its canvas
    (Claude's recommendation; owner 2026-09-29: "I agree"). The backward maps
    keep finding a row from its place. Until it is built, the round trip test
    marks these cases `@test_broken`.
  - **Tests of the point model change to the reference model.** The anchor test
    (`test_anchor_point`), a case of the table list and the round trip case of
    math asserted that a forward map answers a `PointReferenceStep`; they read
    the box of the forward reference now, with the same claims.
  - Checks: the wide sweep has the counts of step 2, except the substrate
    (86217 passed: +15 of the round trip test, −1 of the table list case; the 3
    failures and 4 errors of the baseline; 7 broken: +6 row cases) and math (173,
    as before) after the tests of the point model changed; the naming guard and
    the documentation check pass; the omnet tests of step 8 pass (186 in 8).
  Committed without the rows. 3b: the list and the accordion give each row
  and each header a canvas of its own, at its place, with the parts of the row
  inside it; `items[k]` maps to that canvas, found by identity after the parts
  of the box. The tree maps a node by its index in the open tree to its row
  canvas, the last of its elements, and a node under a closed one to `nothing`.
  Checks of 3b: the round trip test passes in full (22); the substrate suite has
  the failures and errors of the baseline, and 91 more passes in the sweeps over
  the examples, which assert per output node and now meet a canvas per row; the
  shell and application suites have their counts; the omnet tests of step 8
  pass (186 in 8).
- [x] 4. **The place of a part.** `find_part_place` of the screen package
  (`source/screen/PartPlace.jl`) maps the part forward from the input of a
  wrapper at the screen, reads the box of the node with `find_reference_box`,
  in screen coordinates, and answers its bottom left corner. The tooltip window
  opens a window that has no point there, 4 pixels lower (`_PART_GAP`), and the
  `@test_broken` of `test_tooltip_window()` is a test again, with the exact
  place below a button of 80 by 24. The context menu window uses the same
  function when step 9d goes on; the parked code of 9d has a point version
  (`find_part_point` in `WindowLayers.jl`), which this replaces. Found in the
  work: a `WidgetComposite` offers each child the whole window as its size, so
  a label in a composite has a canvas as large as the window (400 by 300 in the
  test) while the composite reports 62 by 63; a window below such a label
  stands at the bottom of the window. That is how the composite sizes its
  children, not a fault of the forward map. **Settled** (owner 2026-09-29):
  "Label size: should fit the content by default." Step 5c changes it.
- [x] 5. **Text** (Q4). `TextToGraphics` maps a text reference as specifically as
  possible. Decided with the owner (2026-09-29):
  - **Q7. A text part is the segment that draws it** (way (a)), "but even more
    specifically. If it's a range and there's a range in the graphics text then
    use that. The mapping should be as specific as possible." A caret, and a
    range that one segment holds, map to that segment's `GraphicsText` followed
    by `text{a:b}`, the characters in it; a caret is a range of no width.
  - **Q8. A part across segments is a region under the smallest node that holds
    it.** "I think we can map that to a region in the graphics language that is
    artificial, just like a point is. It's like a box under the smallest
    graphics node that covers the whole image. This is the most specific
    reference." `RegionReferenceStep(x, y, width, height)` of the graphics
    package (Claude's name) is a box in the frame of the node before it. A range
    across segments maps to the canvas of its line, or the stack of lines, and
    the region of its rows, the same rows that its highlight draws.
  Built: `find_reference_box` measures a text node and a range of it with a
  `TextMeasure` (the font files by default, as every backend draws) and reads a
  region; the text printer finds a segment's text node in its line by its place
  and its text, because a fill comes before some texts; the span bases of both
  spaces are counted once (`_compute_span_bases`), for the highlight and the
  forward map. Found in the work: **a rule projection did not follow a route.**
  `RuleIoMap` held its children but named none (`get_child_iomaps`), and the
  reader that `@projection_template` emits read a change with a route at the top
  of the rule, so an operation that a command carried to a Julia function came
  back rooted at the whole document. Both now follow the route as every
  container does; this also lets a routed gesture reach the part it names in a
  Julia or JSON pane. The lazy printer of a `ListNode` text keeps no line stack,
  so its forward map answers `nothing`. The command palette test now maps the
  empty reference of its content forward, because the text answers the empty
  reference for it, and so it reached a check that was always wrong:
  `_strip_wrapper` asked `isa ElementReferenceStep`, a function that makes a
  `RangeReferenceStep`, not a type. It now compares the step with
  `ElementReferenceStep(1)`. The sweep matches the step 4 sweep, and the omnet
  tests match their baseline.
- [x] 5b. **A lazy list maps forward** (owner 2026-09-29): "ListNode can also be
  forward mapped, I don't know the particular example, but there's no reason
  not to, especially if the output is also lazy list, the indices count from
  the head." `[k]` of a `ListNode` is `RangeReferenceStep(k - 1, k)`, and
  `getindex` reads it from the head: 1 is the head, 0 the node before it. Today
  all three stages of a lazy list answer `nothing` in both directions, so a
  part of the lazy primes example (`lazy_example`) has no image. The forward
  maps of the three stages:
  - `CollectionListNodeToSyntax`: `[k].rest` maps to `[k]` of the output list
    followed by the forward map of the child of `k`. The IO map keeps the child
    IO maps by index, as the printer builds them.
  - `SyntaxListToText`: `[k]` maps to the spans of element `k` in the output
    list of spans, `elements{i-1:j}`, counted from the head of that list; a
    reference inside the element maps through the child's forward map, moved by
    the index of the element's first span.
  - `TextToGraphics`, list path: a span `elements[i]`, or characters of it
    (`elements[i].content{a:b}`), map to the text node of that span in its
    paragraph canvas, followed by `text{a:b}`. A range of spans maps to the
    paragraph canvas, or to the list canvas when it crosses paragraphs,
    followed by the region of its pieces. A paragraph counts from the head
    paragraph, the one that holds the head span.
  The backward maps of the three stages stay as they are.
  Built: `find_list_node(head, index)` of the collection package reaches the
  node of an index, as `getindex` counts, and reads the links on the way, so a
  lazy chain builds the nodes up to it. `CollectionListNodeToSyntaxIoMap` keeps
  the IO map of each printed element by its index; an element that the printer
  did not reach yet is printed by reading the output list up to it.
  `SyntaxListToTextIoMap` keeps, per input node, the first output span, the
  number of spans, the spans and the IO map of the element; the index of the
  first span is found by reading the output list from its head to that node. A
  flat caret or range of the element's text maps to the characters of one span
  when one span holds it, and else to the spans. The text printer finds the
  paragraph of a span by the newlines between the head and the span: a newline
  ends a paragraph, the head paragraph starts at the head, and the paragraph
  before it ends at the span before the head, as `_build_paragraph_node` and
  `_build_paragraph_node_prev` build them. The text node is found by its number
  among the texts of the paragraph canvas, because a fill comes before the text
  of a span that has one. Tests: the list path alone (9) and the chain of
  `lazy_example` and `lazy_bidirectional_example` (5), where element 40 of the
  primes reaches its line 39 lines down, and element -2 three lines up.
  Checks: the wide sweep has the counts of step 5, with 18 more passes in the
  substrate suite (the 14 new ones, and 4 in the sweep over the examples, which
  meets forward answers for the two lazy examples); the palette error of step 5
  is gone; the naming guard passes, the documentation check has the notes of
  step 5, and the omnet tests have their results.
- [ ] 5c. **A label fits its content by default** (owner 2026-09-29). Open
  question Q9 below.
- [ ] 6. **A round trip test over the widget gallery.** For each part of each
  example: the forward reference reaches a printed node, and a point inside its box
  maps backward to the part or to a part inside it. This ties the two maps
  together, so a later change that breaks one of them fails it.
- [ ] 7. **The documents:** the widget, layout, screen and text documents say
  which projections map forward, and how a caller finds the place of a part.
  The feature "the place of a part" gets its design and user interface
  documents as step 11 of
  [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md) lists
  them.

## 5. Open questions

- ~~**Q1. A part that is scrolled out of view.**~~ **Settled with Q6.** It has a
  forward reference, as every part has.
- ~~**Q2. A part on a hidden tab, in a closed card, or under a closed tree
  node.**~~ **Settled.** A tab that is not displayed has no output image, so it
  maps forward to `nothing`: "For the tabbed pane question, when mapping forward
  a tab which is not displayed. That legitimately does not have an output image
  independently of laziness, so it maps forward to nothing." (Owner
  2026-09-29.) The difference is between a part that the projection does not
  display, which has no image, and a part that a lazy printer did not compute
  yet, which has its output reference. A closed card and a closed tree node are
  the first kind, as a closed tab is (Claude's reading; owner 2026-09-29:
  "closed parts: yes"). The name `RegionReferenceStep` is confirmed too
  ("RegionReferenceStep is fine").
- **Q9. How a label fits its content.** Owner 2026-09-29: "Label size: should
  fit the content by default." Today a widget with no size of its own takes the
  minimum of the range that its parent gives, and a `WidgetComposite` gives each
  child its own range, which at the root of a window is exact: the size of the
  window. Two ways: (a) the composite gives each child a bounded range, because
  it puts each child at the child's own position and has no slot to stretch a
  child into; every child with no size of its own then fits its content, also
  a button, and a child that must fill the window, such as a split pane, must
  get the fill from somewhere else. (b) The label alone takes the size of its
  content and ignores the minimum of the range, as an overlay does; a label in
  a grid cell of `Fill` then draws its box at the size of its text, not of the
  cell. A search of the 52 composites of the repository (none in omnet-julia)
  found two that need the stretch of (a) today: the root of the pane tree
  (`PaneToWidget.jl`), whose comment says that the composite "hands each child
  the extent it was given itself, so the panes still divide the whole window",
  and the file chooser in a dialog, whose scroll pane takes the extent that it
  gets. Six other widgets give a child their own range too: the document
  content of `WidgetText` and `WidgetTextarea`, `WidgetTooltip`,
  `WidgetContextMenu`, `WidgetTitlePane` and `WidgetDialog`. Open.
- ~~**Q6. What the forward map answers.**~~ **Settled.** The forward map takes an
  input reference and returns an output reference (owner 2026-09-29: "The
  mapper functions work with references, that's the correct terminology"). It
  works independently of what the printer computed
  and of what a lazy printer left out. It may read the output when it must, but
  most of the time it does not; an index mapping is the usual case. (Owner
  2026-09-28: "you can map forward if you can without looking at the output and
  usually you can. For example, index mapping"; "The map forward should work
  independently of what is printed"; "The map may read the output if needed,
  but most of the time it is not. The map forward takes a path and returns a
  path. It should work independently of what the printer actually computed and
  what's left out due to being lazy.") Claude's recommendation of `nothing` for
  a part out of view, and its reading of a point as the image in graphics, are
  dropped. So the contract text of `map_reference_forward` that makes the image
  in graphics a `PointReferenceStep` ("coordinates accumulate") changes: the
  image is a reference into the output. A caller that needs a place on the screen,
  such as `find_part_point`, reads the positions of the printed nodes that the
  reference reaches and the origin of the window; a node that is not printed
  gives no place.
- ~~**Q3. Where the window stands relative to the image.**~~ **Settled:** below
  the part. The caller reads the box of the printed node at the forward reference of
  the part, and a window that a command opens (a tooltip or a context menu with
  no point) stands under the part, with the left edges aligned, so the part
  stays visible. (Claude's recommendation; owner 2026-09-29: "It is option a".)
- ~~**Q4. The scope.**~~ **Settled:** text is in this plan, as its last step.
  Syntax to text already maps the selection forward; only `TextToGraphics`
  maps nothing, and only a window placed at a text part needs it, such as the
  signature of a Julia function that the palette shows. (Claude's
  recommendation; owner 2026-09-29: "Option a, I agree".)
- ~~**Q5. Where it is built.**~~ **Settled** (owner 2026-09-29): on the branch
  `gesture-type`, before the mouse target of
  [a-document-knows-the-part-under-the-pointer.md](a-document-knows-the-part-under-the-pointer.md),
  because a widget that a view makes gets its mouse target by the forward map.
