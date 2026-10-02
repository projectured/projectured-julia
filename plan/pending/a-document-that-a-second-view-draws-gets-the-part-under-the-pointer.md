# A document that a second view draws gets the part under the pointer

> **Status (2026-10-02): decided, in work.** The owner chose (a) ("agreed", on
> Claude's recommendation). This is Q15 of
> [a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md),
> moved here when
> [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md)
> was done. No source changed yet.

## The fault

The reflected tree of the omnet inspector pane gets no mouse target: a row does
not light under the pointer.

## The cause (found 2026-10-02)

1. `SimulationInspectorToWidget` (omnet,
   `source/presentation/view/SimulationInspectorToWidget.jl`) puts its own input,
   the reflected shadow, into a `WidgetScrollPane` of its output, in a
   `WidgetCard`. A second view, `ReflectionToWidget`, draws the shadow later, in
   the stage from the widgets to the graphics.
2. A move on a row: the second view answers `proj(ReflectionToWidget, .roots[1])`,
   which is correct, and the structural maps of the scroll pane, the layout and
   the card carry it up as `.content.children[1].content.‹…›`.
3. The inspector has no `map_reference_backward` of its own, so the default of
   the kernel (`ProjectionDefaults.jl`) wraps that path again as a part of the
   inspector: `proj(SimulationInspectorToWidget, .content.children[1].content.‹…›)`.
   The path has a pre-image, because the node at `.content.children[1].content`
   is the input of the inspector, so the wrap breaks `PAR-CROSS-DOMAIN-LATE`.
4. The chain write (`replace_path_chain!`) stops at the shadow and gives it that
   path. `ReflectionToWidget` reads the mouse target of the shadow, finds no
   part of its own in it, and lights no row.

The case in projectured alone: a form view of the same shape as the inspector,
with a stage whose dispatch draws a reflected node with `ReflectionToWidget`.
Driven with `MttDriver`, the row does not light. A backward map that walks the
output path to the node that is the input of the view, and answers the rest of
the path, makes the row light, and a move off the rows clears it.

## The ways to fix it

- **(a) A backward map in each view that puts its input into a slot.** The
  inspector gets a `map_reference_backward` that answers the rest of a path
  through the slot, a forward map that adds the slot back, and an omnet test.
  A small helper of the platform does the walk to the input, so a view does not
  write its slot path by hand, as `CatalogShellToWidget` does now. Cost: one
  view now, about 10 lines, and each new view of this shape needs the same.
- **(b) The view prints the shadow itself** with `print_child` and keeps the IO
  map of the child. This moves the draw of the tree from the later stage into
  the form, and each view still needs a change. Cost: more than (a).
- **(c) The walk in the default `map_reference_backward` of the kernel.** No view
  needs code. Cost: the default changes for every projection and for the
  selection too, so the selection sweeps and a baseline diff must run; the walk
  covers only the whole input, not a part of it.

Claude's recommendation: (a), with the helper. It is local, it follows how the
omnet views map their slots now, and the default of the kernel stays.

## Also found

`SimulationTopologyToWidget` puts a graph that it makes itself into its output,
and its outer walk (`follow_output_mouse_target!` with `is_followed`) leaves the
graph out, so the graph gets no mouse target either. Found by reading, not
tested. The cause is different: the graph is a part of the output, not of the
input. It needs its own question after the choice above.

## Steps

- [x] 1. The owner chooses (a), (b) or (c). Decided (owner 2026-10-02, "agreed"):
  (a), with the helper. Rejected: (b), the view prints the shadow itself; (c),
  the walk in the default of the kernel.
- [ ] 2. The fix and its test, in the repository that the choice names.
  - [x] 2a. projectured: the helper in the focus slice, beside
    `follow_output_mouse_target!`. `find_output_node_path(root, node)` finds the
    path from the output of a view to a document that the output holds, by
    identity through the child documents (`_child_document_refs`);
    `map_held_node_forward(output, node, reference)` puts that path before a path
    of the node, and `map_held_node_backward(output, node, reference)` walks a
    path of the output and answers the rest of it after the node. A test with
    the shape of the inspector: a row that a second view draws lights.
    Built (2026-10-02): `OutputSelection.jl` of the focus slice, exported. The
    test in `MouseTargetMoveTest.jl` (a view `MtmHeldObjectView` and a stage
    that draws a reflected object with `ReflectionToWidget`) fails with the
    default backward map (no row lights) and passes with the helper (76 in
    `test_mouse_target_move`). `focus.md` and `mouse-target.md` describe the
    helper, and the limit of `mouse-target.md` names only the case of step 3.
  - [ ] 2b. omnet, after 2a is on main: `SimulationInspectorToWidget` maps a
    path of the shadow forward and back with the helper, and a test moves onto
    a row of the inspector.
- [ ] 3. The question of the topology graph.
- [ ] 4. The documents: `mouse-target.md` drops its limit, and the move of this
  plan to `plan/done/`.
