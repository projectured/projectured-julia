# The menu of a graph switches its edges

Status: DONE, 2026-10-22, on the branch `graph-edge-menu`, in the worktree
`projectured-julia-graph-edge-menu`. Not landed on `main`. The owner asked for it
on 2026-10-22.

## The ask

The owner, 2026-10-22: "can the user switch via context menu?" I answered that
the shape of the edges is a keyword of the drawing, and that a switch needs a
field of view state and an entry of the context menu. The owner: "yes, do it".

## The problem

The facts at `main` `69f4e7dc1`. Find each function by its name.

1. `edge_shape` is a field of `GraphLayoutToGraphicsCanvas`, set by its keyword
   when the view is built. Nothing in the window changes it.
2. A type adds a context menu with `get_document_gesture_bindings_own(::Type{T})`
   and `make_context_menu_binding(compute; description)` (`context-menu.md`). A
   right click goes to the part at its point, and the parts around it add their
   menus as outer layers (`read_container_gesture`). The drawing of a graph reads
   the tables of its input, the `GraphLayout`, in `_route_outward`.
3. A `WidgetMenuItem` can hold an `operation`. One that names its own document
   passes up as it is.
4. `GraphLayout` holds the drag and the zoom as view state.
5. The binding gets the document only, not the projection, so the menu does not
   know which shape the keyword gave.

## The decision

- **The shape is view state of the drawing.** `GraphLayout.edge_shape` is
  `nothing`, which keeps the keyword of the drawing, or `:straight` or
  `:curved`, which overrides it. It is view state, as the zoom is: no undo
  records it, and a new print of the graph starts from the keyword.
- **The menu of the graph offers both shapes.** `GraphLayout` has the binding
  "Show the menu of the graph", with the items "Straight edges" and "Curved
  edges". Each item writes the field. Both items are always there, because the
  menu does not know the shape that the keyword gave (fact 5).

## Steps

Do the work in the worktree. Commit each step. Do not land on `main` before the
owner approves.

1. **The field, the drawing and the menu.** Add `GraphLayout.edge_shape`, let the
   drawing read the shape from it before the keyword, and give `GraphLayout`
   the binding. A new `GraphContextMenuTest.jl` asserts these facts:
   - in a real editor with the context menu window, a right click on the graph
     opens a menu that holds "Straight edges" and "Curved edges";
   - a choice of "Curved edges" draws each edge as a curve, and a choice of
     "Straight edges" draws them straight again;
   - a right click on the content of a vertex gives the menu of the graph too,
     as an outer layer.

   **Done.** The binding and the menu are in `GraphLayout.jl`, beside the field;
   `_get_edge_shape` of the drawing reads the field before the keyword. The
   tests pass with the layering guard (19). A render of the example with real
   fonts shows the menu with both items, and after "Curved edges" each edge is a
   curve, the menu is closed, and no fault occurs.
2. **The guide.** Write the menu in
   [graph.md](../../documentation/package/domain/graph/graph.md) and in the table
   of [context-menu.md](../../documentation/package/platform/widget/context-menu.md).
   Move this plan to `plan/done/`.

   **Done.** `graph.md` says what the menu does, and the table of
   `context-menu.md` has a row for `GraphLayout`.
