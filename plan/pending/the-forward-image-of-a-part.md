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
path has a forward image today, so the window opens at the corner of the
screen, and one assertion of `test_tooltip_window()` is `@test_broken`.

The same map serves every follower that must stand at a part with no pointer:
the context menu from the palette (D73 too), and later a scroll into view.

## 2. The model

- **A forward map takes a path and returns a path** (Q6). It answers from its
  input and its own mapping, which is usually an index mapping, and it does not
  depend on what the printer computed or on what a lazy printer left out. It may
  read the output when it must, but most of the time it does not. So every part
  has a forward path: also a part that is scrolled out of view (Q1), and a part
  on a closed tab or in a closed card (Q2).
- **In graphics, the image of a part is the path of the node that draws it**,
  for example `.windows[1].content.elements[2]`, and not a point.
- **A caller that needs a place on the screen reads it from the printed
  output.** It evaluates the forward path in the output of the screen and adds
  the places of the nodes on the path and the origin of the window, which gives
  the box of the part: its place and its size. A path that reaches no printed
  node gives no box.
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
   helpers. They change to paths.
4. **Text and charts map nothing forward.** `TextToGraphics`, the chart and the
   sequence chart answer `nothing`. The math projection maps forward.
5. **No function gives the place of an output path.** The SDL and web backends
   and `get_canvas_content_bounds` walk a printed canvas and add offsets, for
   drawing and for bounds, and not for a path.

## 4. The steps

- [ ] 1. **The contract.** The docstring of `map_reference_forward` and
  [reference.md](../../documentation/package/kernel/reference.md) say the model
  of section 2.
- [ ] 2. **The three wrappers map forward through their child**, as they map
  backward. Test first what this changes: the tests that print and read, and
  the selection wiring, because a map that answered nothing now answers.
- [ ] 3. **The widgets, the layouts and the screen map by index.** A container
  maps its own step to the path of its child's node in its output, and a leaf
  answers the empty path for itself. The helpers that add points
  (`shift_child_image`, `_self_point`, the point in `_map_window`) change to
  paths. A part that is not printed still has its path (Q2).
- [ ] 4. **The place of a part.** A function reads the box of the printed node
  at a forward path, with the origin of the window, and `find_part_point`
  becomes the place below that box (Q3). The tooltip window and the context
  menu window use it, and the `@test_broken` of `test_tooltip_window()` becomes
  `@test`.
- [ ] 5. **Text** (Q4). `TextToGraphics` maps a text path to the path of the
  printed line or segment, so a window opens below a part of a Julia or JSON
  pane too.
- [ ] 6. **A round trip test over the widget gallery.** For each part of each
  example: the forward path reaches a printed node, and a point inside its box
  maps backward to the part or to a part inside it. This ties the two maps
  together, so a later change that breaks one of them fails it.
- [ ] 7. **The documents:** the widget, layout, screen and text documents say
  which projections map forward, and how a caller finds the place of a part.

## 5. Open questions

- ~~**Q1. A part that is scrolled out of view.**~~ **Settled with Q6.** It has a
  forward path, as every part has.
- ~~**Q2. A part on a hidden tab, in a closed card, or under a closed tree
  node.**~~ **Settled with Q6.** It has a forward path too, although the printer
  did not print it.
- ~~**Q6. What the forward map answers.**~~ **Settled.** The forward map takes a
  path and returns a path. It works independently of what the printer computed
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
  image is a path into the output. A caller that needs a place on the screen,
  such as `find_part_point`, reads the positions of the printed nodes on that
  path and the origin of the window; a node that is not printed gives no place.
- ~~**Q3. Where the window stands relative to the image.**~~ **Settled:** below
  the part. The caller reads the box of the printed node at the forward path of
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
