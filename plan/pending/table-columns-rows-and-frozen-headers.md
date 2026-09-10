# A table sizes by column and by row, and its headers stay put

> **Kind:** plan · **Status:** pending · **Stands on:**
> [layout-rules.md](../../documentation/rule/layout-rules.md),
> [widget-sizing-rules.md](widget-sizing-rules.md)

Three things, and the first one is a fault.

1. **`GridLayout` offers its children an extent it will not give them.** A cell
   with no authored size fills that offer, and the grid's row height is the
   tallest cell, so one row swallows the whole offer.
2. **A table cannot say what a column or a row is for.** Every column is content
   wide, whatever space the table was given.
3. **A header strip scrolls away with the body**, because both strips are cells
   of the same grid.

It completes, for `GridLayout`, what steps 3 and 4 of
[widget-sizing-rules.md](widget-sizing-rules.md) left: *"`GridLayout`,
`FlowLayout` and `StackLayout` do not carry a default yet … They follow when a
case needs them."* The run table of the campaign runner is that case.

## 1. What a table is today

`WidgetTable` carries **both** strips, and they are optional:

| field | what it is |
| --- | --- |
| `column_headers::CellVector` | the top strip — a header **row** |
| `row_headers::CellVector` | the left strip — a header **column** |
| `rows::CellVector` | each row a `CellVector` of cell documents |
| `column_count::Int` | how many body columns |

`_wt_grid_children` lays all of it out as **one** `GridLayout`: the column
headers take grid row 1, the row headers take grid column 1, and `row_offset` /
`col_offset` say whether each strip is there. The corner is an empty cell.

So a strip is a row of the grid and nothing more. It aligns with the body
because it is the same grid, and it scrolls with the body for the same reason.

`GridLayout` already has half of what this plan needs:

- `column_stretch::Vector{Int}` — weights. A column with a positive weight gets
  its content width **plus** a share of `available − Σcontent − gaps`.
- `column_align::Vector{Symbol}` — per-column alignment.

There is no row equivalent, and `WidgetTable` passes neither.

## 2. The fault, measured

`GridLayoutToGraphicsCanvas` recurses every child with the parent's own context:

```julia
cim = _recurse_child(recursion, doc.children[i], make_child_context(ctx, …))
```

That hands each cell the grid's whole offer on **both** axes. A `WidgetLabel`
authored no height, so `_resolve_size` gives it the offer.

Measured in the campaign runner, in the coordinates of the whole canvas, with a
scroll pane 538 pixels tall:

| | header | row 1 | row 2 | row 3 |
| --- | --- | --- | --- | --- |
| the table alone | 571 | 1126 | 1681 | 2236 |
| the table in a stack | 571 | 608 | 645 | 682 |

555 = 538 + 17, the offer plus the cell gap. Every run fell below the fold.

**The rule it breaks** is §3 of the layout rules: a container offers what it
will give. A grid's row height comes from its children, so on `:y` it must
offer nothing.

**The workaround that stands today.** `SimulationFilterToWidget` in `omnet-julia`
wraps the table in a `VerticalLayout` inside the pane. A stack that was offered a
height and holds no weighted child sums instead of distributing and offers that
height to nobody, so the table sizes to its rows. **Step 3 of this plan deletes
that wrapper**, and it is how the fix is checked from the outside.

## 3. The design

### One vocabulary, per column and per row

A column and a row take the same `SizePolicy` the stacks take:

| policy | a column | a row |
| --- | --- | --- |
| `Content` | as wide as its widest cell | as tall as its tallest cell |
| `Fixed(n)` | exactly `n` | exactly `n` |
| `Relative(w)` | a share of what is left | a share of what is left |
| `Fill` | `Relative(1.0)` | `Relative(1.0)` |

`column_stretch` is `Relative(w)` written a second way, so it folds into this
one and stops being its own field. That is the plan's own rule: one way to say
a size.

### The default is implicit, and it is `Content`

`GridLayout` carries `column_policy` and `row_policy` — one policy each, the
default for every column and every row — and a per-column or per-row vector
overrides it for the ones that differ. This is step 4's shape, which gave
`VerticalLayout` and `HorizontalLayout` a `child_width` and a `child_height`
default with a `LayoutConstraint` wrapper as the exception.

**Both default to `Content`**, which is what a grid has always meant, so no
existing caller changes.

`WidgetTable` takes the same two, and a table's own default is `Content` on both
axes. A table that says nothing draws exactly as it does today.

### What the grid may offer, and to whom

The stack's rule, applied per column (§4 of the layout rules):

- a **`Content` or `Fixed`** column keeps the withheld axis. Its extent does not
  depend on the allocation, so it is safe to read while computing one.
- a **weighted** column is offered its slot, and its cells are not read for the
  allocation.

That is what keeps it out of a cycle. Offering a stretched column its total —
content **plus** share, which is what `_gl_stretched_col_w_cell` computes —
would make a cell's size depend on its own content width through the offer.

The same holds per row, on `:y`.

## 4. The header strips stay put

Frozen panes is four regions and two offsets:

| | fixed on x | scrolls on x |
| --- | --- | --- |
| **fixed on y** | the corner | the column headers |
| **scrolls on y** | the row headers | the body |

The corner never moves. The column strip follows the body's `x` only. The row
strip follows the body's `y` only.

**The pane freezes, and the content declares.** `WidgetScrollPane` gains a
frozen extent, and holds that many pixels of its content still on each axis
while the rest travels.

Why there and not in the table:

- **One scroller.** A table that scrolled itself would need its own `size` and
  `scroll_position`, and a pane around it would then scroll a thing that
  scrolls. Every wheel and drag already reaches the pane.
- **It is not about tables.** A sequence chart, a spreadsheet and a log with a
  fixed first line all want it. The pane holds a prefix of *anything*.
- **The table already knows the number.** `_wt_geometry` computes `col_x` and
  `row_y`, the cumulative edges, so the frozen extent is `col_x[col_offset + 1]`
  by `row_y[row_offset + 1]` — zero on an axis with no strip.

So the content carries the extent it wants held, as a reactive pair, and the
pane reads it. A content that carries none freezes nothing, which is every
content today.

## 5. Steps

Each step keeps the 39 widget images green before the next begins, by
`tool/widget-images.jl` — the instrument step 0 of
[widget-sizing-rules.md](widget-sizing-rules.md) built.

1. **The grid withholds `:y`.** `withhold_offer(ctx, :y)` on the child context,
   which step 3 already wrote for the two stacks. Nothing else changes.

   **Check.** The runner's table, printed at 900×1100 with no wrapper: rows 37
   apart, not 555. Of the 39 images, only the table ones may change, and each
   must change by shrinking a row to its text.

2. **`GridLayout` carries a default policy and per-column and per-row vectors.**
   `column_stretch` folds into `Relative`. The grid offers a weighted column its
   slot and withholds from every other, per §4.

   **Check.** A grid of three columns, the middle one `Fill`, in a 600-wide
   offer: the outer two are content wide and the middle takes the rest. A grid
   that says nothing is unchanged, and the images say so.

3. **`WidgetTable` takes them, and the runner's table uses them.** The five
   columns of the campaign runner say what they are for: `configuration`
   `Content`, `run` `Fixed`, `iteration parameters` `Fill`, `INI file`
   `Content`, `directory` `Fill`.

   **Check.** The columns fill the pane's width, and the two `Fill` ones share
   what is left. **`SimulationFilterToWidget` in `omnet-julia` drops its
   `VerticalLayout` wrapper**, and its `test_filter_run_table_bounded` still
   passes — that test asserts the rows are 37 apart at a bounded height, and it
   is what says the fix landed in the right place.

4. **`WidgetScrollPane` freezes a prefix, and `WidgetTable` declares one.**

   **Check.** The runner's table scrolled to the bottom still shows the five
   column names and the ordinals beside the rows, and the corner does not move.
   A pane over any other content scrolls as it does today.

## 6. What this is not

| Out | Why |
| --- | --- |
| Column widths a person can drag | Later. A policy is where a drag would write, so this is what makes it possible |
| A sort | Not a sizing question |
| `FlowLayout` and `StackLayout` defaults | Step 4 of the sizing plan still says: when a case needs them |
| A second scroll position | §4 says why the pane keeps the only one |
