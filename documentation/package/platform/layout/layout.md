# Layout

> **Kind:** design · **Status:** current · **Stands on:** [graphics.md](../graphics/graphics.md), [cell.md](../../kernel/cell.md), [layout-rules.md](../../../rule/layout-rules.md)

The layout slice of `ProjecturedPlatform` places documents of any kind next to each other: in a row, a column, a grid, a flow, a stack, relative to an anchor, or by constraints. This document says how a layout measures and places its children with reactive cells, how the available size from a parent reaches a child, and how a press reaches the right child.

<img width="396" alt="Layout example" src="../../../asset/image/example/layout.png">

## How it works

| Document | What it places |
| --- | --- |
| `HorizontalLayout`, `VerticalLayout` | a row or a column, with `gap` and alignment; a row can align its children on the baseline of their first line |
| `GridLayout`, `FormLayout` | cells in `columns`, with a size policy for each column and row; a form is a two-column grid |
| `FlowLayout` | a row that wraps at the edge of its range, or at `max_width` when that is less; it is as wide as its widest line, or as the edge of an exact range, but not wider than `max_width` unless one child is |
| `StackLayout` | children on top of each other, the last on top |
| `AnchoredLayout` | a `content`, and children placed next to parts of it |
| `ScrollLayout` | a `center`, and up to four edges and four corners around it |
| `ConstraintLayout` | children placed by linear relations between their edges |

A child is any document that has a projection to a `GraphicsCanvas`. The package names no widget and no domain.

### Measure and place with cells

Each layout projection works in two phases. It first prints each child through the outer `recursion` and gets a canvas. It then makes computed cells for the `x` and `y` of each child and for the size of the whole canvas, from the sizes that the children report. No layout cache exists apart from these cells: the reactive engine computes a cell once and again only when a cell it read changes.

The whole placement is in one outer computed cell, which reads `doc.children`. So a structural change, a child added or removed, builds the layout again. A child that only changes its size changes only the position cells that read that size.

A `HorizontalLayout` places its children with `vertical_align ∈ (:top, :center, :bottom, :baseline)`. At `:baseline`, each child stands so that the baseline of its first line of text, `find_first_baseline` of the [graphics package](../graphics/graphics.md), meets the lowest baseline of the row; a child with no text, such as an image, stands on its bottom edge instead, as CSS takes it. So a label beside a text of another font or of another line spacing reads on one line.

A layout that can hold a selection draws the ring around a whole-selected child with the values of a `GraphicsTheme`: the color, the width and the corner radius come from the theme of the appearance that `LayoutToGraphics(; theme)` is built with, or from the default theme with no `theme`; [graphics.md](../graphics/graphics.md#selection-and-clicks) describes it.

### The size that a parent offers

A layout sizes itself to its content by default. A parent gives a range on each axis through the printer context: an exact range, a slot (`with_exact_size`); a bounded range, an edge with no slot (`with_bounded_size`, or `with_size_range` with a minimum); or a free axis (`with_free_axis`). If a layout has an edge on its main axis, exact or bounded, and at least one child has a weight, the layout divides the edge among the weighted children:

- `SizePolicy(min, preferred, max, weight)` describes a child on one axis. The named forms are `Fixed(n)`, `Content` (the default), `Relative(w)` and `Fill`, which is `Relative(1.0)`.
- `allocate_axis` is the one allocator for rows, columns, grids and the split pane. It gives each child its preferred size, then gives the rest to the weighted children in proportion to their weights, and repeats while a child reaches its minimum or maximum.
- A child without a weight gets the room the others leave, as a bounded range: the edge, less the gaps, less what the children before it drew, less the minimums of the others. It reads only children that come before it, so no cell reads its own result. So a child that reflows takes the room before the children after it; give it a weight to leave them their size.
- On the cross axis, a weighted child gets the layout's edge exactly, a `Fixed` child its number, and a `Content` child a bounded range: its content, up to the layout's edge and its placement maximum, and at least its placement minimum. So a label keeps its size in a column, and a long text wraps at the column's edge.

The policy is a property of the placement, not of the child: `child_width` and `child_height` on the layout, or a `LayoutConstraint` around one child. So the same card fills a column in one place and is as wide as its content in a toolbar.

A grid column that is offered a size must not read its cells to find its own width, or the cell graph has a cycle. `column_offers` lets a caller keep the offer from a sized column; the column then clips its cells with `clip_child_to_slot` instead of making them flow again. `row_offers` does the same for a sized row. A table uses both: the cells of a table clip, and the header column measures its headers in rows whose heights the cells decide. A column or a row is never narrower than the `min` nor wider than the `max` of its policy, whether a weight shares the offer or not. `GridLayoutIoMap` also gives the column and row positions as cells, so a table can draw its lines over a grid that has no code for tables. A cell wider than its column, or taller than its row, starts at the left or the top edge of its slot whatever its alignment, so a slot that clips it shows its start; the grid of a list does the same.

A weighted column or row that the grid itself was offered no extent on has no share to take: it acts as `Content` instead, and keeps its minimum, its maximum and the width or the height of its cells, as a weighted child of a stack does. So a `Fill` column fills the pane that offers the grid a width, and is as wide as its cells where the grid is offered none, such as inside a form that a walker prints with no width.

A child of a grid takes more than one column with `LayoutConstraint(child; column_span = n)` (`get_column_span`). The grid fills its rows in order; a spanning child starts a new row when its row has fewer columns left, and a span past the number of columns takes the whole row. A spanning child widens no column. When every column it spans hands out its extent, it gets their width with the gaps; otherwise it may reach from its first column to the edge that the grid was offered, so a text in it breaks there, and the grid is as wide as such a child. A grid that was offered no width gives it no edge, and it draws as wide as it measures. The settings tab and the appearance tab use it for the description of a field, under the row of its name and its control. A grid of a list takes no span.

`row_gaps` holds the gap above each row, by the index of the row; an entry past its end, or `nothing`, is `vertical_gap`. A weighted row shares what the gaps leave. The two tabs put no gap above the description of a field and a larger one above the next field, so a description reads as a part of the field above it.

The grid reads the kind of a policy, `Fixed`, a weight or `Content`, when it prints, with no dependency, because the kind decides what each cell is offered. It reads the numbers of a policy inside its extent cells. So a policy can be a computed cell: the header row of a table takes the widths of the grid of its cells as `Fixed`, and a new width does not print the header row again.

### Children in a list

The `children` of a `VerticalLayout` or a `HorizontalLayout` can be a `ListNode`, and so can the rows of a `GridLayout`, each row a vector of the cells of its columns. The layout walks the list from its head in both directions and builds only the children that a viewport shows, each after its neighbour; a `WidgetScrollPane` around it stops at the ends of the list. `children[k]` counts from the head, and a child before the head has an index of 0 or less. A grid whose `children` are `nothing` is a list with no rows: it is printed in the list form, so it draws the rows of a list that its children hold later, because a grid takes its form from the type of `children` at its first print. A list has no count, so its axis takes no weight: a child along a list is `Fixed` or its content, and a column of a grid of a list is `Fixed` or a weight of an offered width, because a column that is its content would read rows that are never built. `GridLayoutListIoMap` gives the edges of the columns as cells, `get_grid_list_head` gives the list of the row canvases that the grid placed, and `find_grid_list_row` gives one row and its cells, so a container can draw graphics around the rows and route a press to a cell.

### The constraint layout

`ConstraintLayout` takes relations built with `make_layout_anchor(child, edge)` and `constrain(lhs, op, rhs; strength)`. Child `0` is the container. It solves in two passes:

1. **Measure.** Each child prints with no offer, to get its own size. The solve cell reads these sizes, and it must never read a size that comes from its own result.
2. **Arrange.** Only a child whose width or height a relation constrains prints again, with the solved size as its offer.

`solve_constraint_layout(solver, …)` is the seam for the solver. The default, `FallbackConstraintSolver`, places every child at the origin. The real solver, `TulipConstraintSolver`, is in the opt-in package `ProjecturedTulip`; see [tulip.md](../../adapter/tulip/tulip.md).

### The anchored layout

`AnchoredLayout` prints its `content` exactly as it prints alone, and then places each `AnchoredEntry` next to a target: a child document, or a reference into the content that the content's IO map maps to a graphics node. `compute_anchored_positions` tries the preferred side, then the opposite side, then the two other sides, and clamps into the region if no side fits. Children that still overlap stack downward.

### The scroll layout

`ScrollLayout` holds a `center` and up to four edges (`top`, `bottom`, `left`, `right`) and four corners (`top_left`, `top_right`, `bottom_left`, `bottom_right`), each any document or `nothing`. Printed on its own, by `ScrollLayoutToGraphicsCanvas`, it puts its parts in three columns and three rows: a column is as wide as its widest part and a row as high as its highest part (`compute_scroll_layout_extents`). The edges and the corners get a free range, and the center gets the range of the layout less the left and the right column and the top and the bottom row, so a text in the center wraps at what is left and no edge reads the range of the center. A `WidgetScrollPane` takes the same document apart instead and keeps its edges in view while the center scrolls.

The parts are fields, so a reference into a part begins with its name, `.center…` or `.left…`, and a click goes to the part at its point and comes back re-rooted into that field. The functions that find a part by its index in `SCROLL_LAYOUT_PARTS` (`get_scroll_layout_place`, `find_scroll_layout_part_at`) are the ones that the scroll pane and the content that made the parts use too, so they agree on where each part is.

### Events

Every layout reader goes through one router:

- A mouse event goes to the child under the pointer. The router translates the point into the frame of the child, limits the hit to the box of the child, and confirms it with `hit_element_at`. The box matters: a `GraphicsText` has no width of its own, so without the box a text on the left of a row would take clicks meant for its right neighbour. Stack, constraint and anchored layouts try the topmost child first, because their children can overlap. A child that is a bare graphics document, such as a circle laid out directly, has no canvas to hit: it is hit anywhere in the box of its size, `get_graphics_size`, the same box that sizes it.
- A key goes only to the child that the selection of the layout names. There is no broadcast.
- Tab goes to the selected child first; if it returns nothing, the focus moves to the next focusable sibling with the functions of the focus slice.
- An Alt+press selects the innermost document under the pointer as a whole (`read_child_event`).
- A left button down with no modifier on a focusable child that answers nothing selects that child as a whole, so a key after the click goes to it (`read_child_event`).
- A move with no button held goes first to the child that the mouse target of the layout names, when the point is not on that child, and then to the child under the pointer, which names the part under it (`read_child_event`, [graphics.md](../graphics/graphics.md#the-part-under-the-pointer)).

The router roots the operation of a child under `children[i]` and adds the type checkpoints of the path, so a container above can use the reference.

### References

A layout maps a part forward by index (`descend_reference_forward`): `children[i]` maps to the node of the child's slot, `make_slot_reference`, which is `elements[slot].elements[1]`, one `content` step deeper when a viewport clips the slot, followed by what the child's own map answers. The empty reference is the layout itself, and its image is its own canvas. A child that is not drawn has no image. The backward map of a point is the mirror: the child's slot at the point, in the child's frame, and on into the child.

`CellVectorToVerticalLayout` turns a plain `CellVector` into a `VerticalLayout` of the same cells. The general renderer uses it, so each element of a list of mixed domains draws in its own domain.

## How it fits

The layout slice depends on the graphics, focus, projection and collection slices. The widget, pane, natural and file-format slices, and the page domains, use it. It registers nothing; a caller composes `RecursiveProjection(LayoutToGraphics())` into its chain.

## Design decisions

- **A layout positions and draws nothing.** A layout places its children and reports where it placed them; it has no color, no line and no background. The appearance of a widget has many styles and states, and a layout that drew some of it would take that complexity in. A container that needs graphics around its children, such as a table with its rules and bands, draws them itself, relative to the places that the layout reports: the edges of the columns and rows of a grid, or the list of rows that a lazy grid placed.
- **The cells are the layout cache.** A layout adds no cache of its own on top of the reactive engine. See [plan/done/layout-documents.md](../../../../plan/done/layout-documents.md).
- **The container sets the size of a child.** A `SizePolicy` states a relation between a container and a child, so it is on the layout. See [plan/done/widget-layout.md](../../../../plan/done/widget-layout.md) and [layout-rules.md](../../../rule/layout-rules.md).
- **A container that bounds a child clips it.** On the axis of the offer the slot clips the child; on the other axis the child sets the size. `clip_child_to_slot` holds the rule. See [plan/done/widget-sizing-rules.md](../../../../plan/done/widget-sizing-rules.md).
- **An annotation does not move what it annotates.** The anchored layout never feeds its children back into the layout of the content. See [plan/done/anchored-layout.md](../../../../plan/done/anchored-layout.md).
- **The solver is a separate package.** Tulip through MathOptInterface solves the relations as goal programming with a slack variable for each relation, weighted by its strength. No maintained Julia binding of Cassowary exists, and Tulip is pure Julia. The core layout package keeps no solver dependency. See [plan/done/constraint-layout.md](../../../../plan/done/constraint-layout.md).

## Usage

```julia
row  = HorizontalLayout([a, b, c]; gap = 8, child_width = Fill)
form = FormLayout([(name_label, name_field), (age_label, age_field)])
grid = GridLayout([a, b, c, d], 2)
tied = ConstraintLayout([a, b], [
    constrain(make_layout_anchor(2, :left), :(==), make_layout_anchor(1, :right) + 8),
])
projection = RecursiveProjection(LayoutToGraphics())
```

- Examples: `layout_example` and `constraint_layout_example` in `example/platform/`; `example/adapter/tulip/LayoutProjectionExample.jl` uses the Tulip solver.
- Tests: `test_graphics_layout()`, `test_layout_allocator()`, `test_layout_closeout()`, `test_anchored_layout()` and `test_layout_list()` in `test/platform/`.

## Limits

- A `ConstraintLayout` with the default solver ignores its relations. Pass `ConstraintLayoutToGraphicsCanvas(solver = TulipConstraintSolver())` to solve them.
- The anchored layout maps no reference back: its `map_reference_backward` returns `nothing`.
- `StackLayout.active` is a field for the caller. The printer draws every child.
- A layout of a list maps no reference back, and a grid of a list has no lazy columns yet: the cells of a row are a vector.
- The widget and table projections still place their parts with their own arithmetic instead of these layouts. [plan/tentative/layout-extensions.md](../../../../plan/tentative/layout-extensions.md) lists this.
