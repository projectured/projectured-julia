# The forward image of a part

> **Status:** pending. The owner chose this way on 2026-09-28 (way (c) of the
> question about where a tooltip that a command opens goes). Nothing is built.

## 1. The purpose

A person runs "Show the tooltip" from the command palette on the selection, or
an agent runs it. The answer has no point, because no pointer rested. The
tooltip window must open beside the part, in screen coordinates.

D73 of [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md)
says how: at the forward image of the part. The tooltip wrapper already asks
for it (`_find_part_point` in `source/tooltip/TooltipWindow.jl`). But no widget
path has a forward image today, so the window opens at the corner of the
screen, and one assertion of `test_tooltip_window()` is `@test_broken`.

The same map serves every follower that must stand at a part with no pointer:
the context menu from the palette (D73 too), and later a scroll into view.

## 2. The model exists

The kernel contract of `map_reference_forward`
(`source/kernel/projection/ProjectionInterface.jl`, the docstring) already
defines the forward image in graphics:

- At the bottom of a render chain the output is coordinates, and the image of a
  positioned element is a `PointReferenceStep`, its place.
- A container that places a child at an offset adds only its own offset to the
  child's point, and passes a structural path unchanged: "coordinates
  accumulate, paths stay paths".
- There must be no second function that resolves a position. Every wrapper
  already composes the one map.
- A projection answers `nothing` for a place that it does not show.

So this plan builds no new model. It completes the one that exists.

## 3. What is wrong today

Facts from a search on 2026-09-28, with the two central ones read again:

1. **Three higher-order wrappers stop the forward map.** `RecursiveProjection`
   (`source/projection/higherorder/Recursive.jl`), `PredicateDispatchingProjection`
   and `SwitchingProjection` answer `nothing` for every forward map. Each maps
   backward through its child, which step 4b of the plan of the pointer added.
   `TypeDispatching`, `ReferenceDispatching`, `Nesting` and `Chaining` delegate
   forward. The stub matters where a caller holds the wrapper itself: a stage
   of a chain (`make_widget_projection_example` is a chain whose stage holds a
   `RecursiveProjection`), and the screen (`make_window_scene_projection` is a
   `RecursiveProjection`). The selection wiring of the printer calls the map on
   the projection of an IO map, and a recursive projection answers the IO map of
   its child, so the wiring does not meet the stub.
2. **Many widget containers answer `nothing` forward** although they map a point
   backward: the split pane, the tabbed pane, the title pane, the scroll pane,
   the transform pane, the toolbar, the context menu, the dialog, the menu item,
   the select and the status bar (`source/widget/WidgetToGraphics.jl`). The
   composite, the menu and the card map forward with `descend_reference_forward`
   and `shift_child_image` (`source/layout/LayoutToGraphics.jl`).
3. **Leaves:** the button, the option, the spin box and the list answer
   `PointReferenceStep(0, 0)` for themselves (`_self_point`). Which other leaves
   do is not yet listed.
4. **The layouts map forward.** The horizontal, vertical, grid, stack and
   anchored layouts accumulate the offsets of their children.
5. **The screen maps forward.** `ScreenToScreen` adds the origin of the window to
   the point of its content (`_map_window`, `_map_screen`), but the recursive
   stub around it hides this.
6. **Text and charts do not.** `TextToGraphics`, the chart and the sequence chart
   answer `nothing` forward. Step 4d of the plan of the pointer left the chart
   so on purpose. The math projection maps forward.
7. **The child offsets are kept.** A `ChildrenIoMap` holds `(x, y, child_iomap)`
   for each child, and the backward map already reads them. A scrolling
   viewport puts its scroll in the origin of its content; a transform pane has an
   affine `transform`.

## 4. The steps

- [ ] 1. **The three wrappers map forward through their child**, as they map
  backward. Test first what this changes: the tests that print and read, and a
  probe of the selection wiring, because a forward map that answered nothing
  now answers.
- [ ] 2. **Each widget container maps its own step and adds its own offset**, the
  way the composite does, from the child entries of its IO map. The scroll pane
  and the transform pane move the point by the scroll and the transform. A part
  that is not shown answers `nothing` (Q1, Q2).
- [ ] 3. **Each widget leaf answers its own point** for the empty path.
- [ ] 4. **The tooltip opens at the part.** `_find_part_point` then works, and the
  `@test_broken` of `test_tooltip_window()` becomes `@test`. The placement of
  the window relative to the image is Q3.
- [ ] 5. **Text and syntax, if Q4 takes them in.**
- [ ] 6. **A round trip test over the widget gallery.** For each part of each
  example: the forward image is a point, and the backward map of that point
  names the part or a part inside it. This is the property that ties the two
  maps together, so a later change that breaks one of them fails it.
- [ ] 7. The documents: [reference.md](../../documentation/package/kernel/reference.md)
  and the widget and layout documents say which projections map forward.

## 5. Open questions

- **Q1. A part that is scrolled out of view.** Its point is outside the clip box
  of the viewport. Does it have an image? Claude's recommendation: `nothing`,
  because the contract says a projection answers `nothing` for a place it does
  not show, and a tooltip at a place the person can not see helps no one.
- **Q2. A part on a hidden tab, in a closed card, or under a closed tree node.**
  Claude's recommendation: `nothing`, for the same reason. This follows from the
  contract, so it needs only a confirmation.
- **Q3. Where the window stands relative to the image.** The image is the top left
  point of the part. A tooltip at that point plus the offset of the pointer
  covers the part. Claude's recommendation: the wrapper keeps the point, and
  the size of the part is not in the image, because the contract gives a point;
  the tooltip opens at the point plus the offset, as today. The other way is an
  image that is a box, which changes the contract.
- **Q4. The scope.** The palette runs the tooltip on the selection, and in a
  Julia pane the selection is in a syntax tree drawn as text. `TextToGraphics`
  maps nothing forward, so steps 1 to 4 do not reach it. Claude's
  recommendation: steps 1 to 4 and 6 first, on the branch `gesture-type`
  before step 9d, and the text chain as step 5 in the same plan, after the
  widgets work.
- **Q5. Where it is built.** On the branch `gesture-type`, as a part of step 9 of
  the plan of the pointer, or on a branch of its own after that plan. Claude's
  recommendation: on `gesture-type`, because step 9d (the context menu from the
  palette) needs it too.
