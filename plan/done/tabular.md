# Document Tabular

A minimal row-primary 2D document layer — rows own their cells, columns are derived views, no headers — intended as the foundation that domain-level table models are built on top of.

## Design Decisions

- **Row-primary** — `TabularRow` owns its `cells::CellVector`. Row insert, delete, reorder, and lazy population operate on the outer `CellVector` only; the flat alternative (`TableTable.cells`) requires shifting `ncols` slots per row operation.
- **Columns are derived, not stored** — a column view is computed on demand by collecting one raw `Cell` from each row. The same reactive `Cell` objects are shared, so mutations propagate in both directions without a copy.
- **No headers** — headers belong to a higher layer (`TableTable` or domain models). The foundation is pure coordinate data.
- **Nesting implicit** — `content::Document` on `TabularCell` accepts any `Document`, including another `TabularGrid`. No explicit nesting field needed; the recursive projection pattern handles rendering.
- **`col_count`** — integer field on `TabularGrid` recording the expected width of each row. Used for validation; avoids storing redundant column objects.
- **Multi-dimensional cube** — left as a separate future structure. `TabularGrid` is intentionally 2D only.

## Relation to Existing `TableModule`

`TableModule` stays unchanged — it is the mid-level layer above this foundation:

| Layer | Prefix | Adds |
|---|---|---|
| Foundation (this) | `Tabular` | rows, cells, coordinate access, lazy rows |
| Mid-level | `Table` | headers, padding, visual borders |
| Domain | free | semantic meaning, operations |

A future step can migrate `TableTable` to use `TabularGrid` internally for its cell storage.

---

## Phase 1 — Document Structure

### File: `program/src/document/Tabular.jl`

**Type hierarchy:**

```
TabularDocument (abstract)
├── TabularCell   — single data slot
├── TabularRow    — one row; owns its cells
└── TabularGrid   — the 2D grid; owns its rows
```

**Types:**

```julia
abstract type TabularDocument <: Document end

@document struct TabularCell <: TabularDocument
    content::Document        # any Document; TabularGrid nesting is free
    selection::Reference
end

TabularCell() = TabularCell(Cell(nothing), Cell(nothing))
TabularCell(content) = TabularCell(Cell(content), Cell(nothing))

@document struct TabularRow <: TabularDocument
    cells::CellVector        # cells in this row; elements are TabularCell
    selection::Reference
end

TabularRow() = TabularRow(CellVector(), Cell(nothing))
TabularRow(cells::CellVector) = TabularRow(cells, Cell(nothing))

@document struct TabularGrid <: TabularDocument
    rows::CellVector         # elements are TabularRow
    col_count::Int           # expected cell count per row
    selection::Reference
end

TabularGrid() = TabularGrid(CellVector(), Cell(0), Cell(nothing))
TabularGrid(rows::CellVector, col_count::Integer) =
    TabularGrid(rows, Cell(col_count), Cell(nothing))
```

### Exports

```julia
export TabularDocument, TabularCell, TabularRow, TabularGrid,
       ITabularCell, ITabularRow, ITabularGrid
```

### Integration into `Projectured.jl`

- `include("document/Tabular.jl")` — after `Collection.jl`, before `Table.jl`
- `using .TabularModule` with the exports above

### Dependencies

- `CollectionModule` (`CellVector`, `cell_at`) — must be loaded before this module.
- `DocumentModule` (`Document`, `@document`) — standard dependency.
- No projection dependency; `Tabular` is a pure document layer.

---

## Phase 2 — Functional and Semantic Support

### Accessors

```julia
tabular_cell(g::TabularGrid, r::Int, c::Int) = g.rows[r].cells[c]

function tabular_column(g::TabularGrid, c::Int)
    nrows = length(g.rows)
    shared = [cell_at(g.rows[r].cells, c) for r in 1:nrows]
    CellVector(shared)
end
```

`tabular_column` derives the column view by collecting the raw `Cell` at position `c` from each row — no copy, fully reactive. Mutating a cell via the column view or the row view hits the same `Cell` in the reactive graph.

### Mutation utilities

Row-level — only the outer `CellVector` changes:

```julia
insert_row!(g::TabularGrid, r::Int, row::TabularRow) = insert!(g.rows, r, Cell(row))
delete_row!(g::TabularGrid, r::Int) = deleteat!(g.rows, r)
```

Column-level — one cell per row, then update `col_count`:

```julia
function insert_column!(g::TabularGrid, c::Int, cells::Vector)
    length(cells) == length(g.rows) || error("cell count must equal row count")
    for r in 1:length(g.rows)
        insert!(g.rows[r].cells, c, Cell(cells[r]))
    end
    g.col_count = g.col_count + 1
end

function delete_column!(g::TabularGrid, c::Int)
    for r in 1:length(g.rows)
        deleteat!(g.rows[r].cells, c)
    end
    g.col_count = g.col_count - 1
end
```

### Cost comparison

| Operation | `TabularGrid` (row-primary) | `TableTable` (flat cells) |
|---|---|---|
| Insert row at index `r` | `insert!(grid.rows, r, row)` — touches outer CellVector only | Insert `ncols` cells at offset `r*ncols` — O(ncells) |
| Delete row `r` | `deleteat!(grid.rows, r)` | Delete `ncols` entries from flat array |
| Reorder rows | Reorder `grid.rows` elements | Reorder `ncols`-wide blocks |
| Lazy row | Assign `Cell(() -> compute_row())` to a `grid.rows` slot | Not possible; flat layout requires all cells present |
| Access cell (r, c) | 4 Cell dereferences | 2 Cell dereferences + multiply-add |

Cell-level content changes cost the same in both.

### Exports (additions from Phase 2)

```julia
export tabular_cell, tabular_column,
       insert_row!, delete_row!, insert_column!, delete_column!
```

---

## Phase 3 — Tests

### File: `test/src/document/TabularTest.jl`

**Fixture — 3 × 4 person grid** (name, age, city, email):

```julia
function make_person_grid()
    persons = [
        ("Alice", 30, "London", "alice@example.com"),
        ("Bob",   25, "Paris",  "bob@example.com"),
        ("Carol", 35, "Berlin", "carol@example.com"),
    ]
    rows = CellVector([
        Cell(TabularRow(CellVector([
            Cell(TabularCell(Cell(name))),
            Cell(TabularCell(Cell(age))),
            Cell(TabularCell(Cell(city))),
            Cell(TabularCell(Cell(email))),
        ])))
        for (name, age, city, email) in persons
    ])
    TabularGrid(rows, 4)
end
```

**T1 — Construction and direct access**
- `length(g.rows) == 3`, `g.col_count == 4`
- `tabular_cell(g, 1, 1) == "Alice"`, `tabular_cell(g, 2, 2) == 25`, `tabular_cell(g, 3, 3) == "Berlin"`

**T2 — Column view integrity**
- `col = tabular_column(g, 1)`; `length(col) == 3`
- `col[1] == "Alice"`, `col[2] == "Bob"`, `col[3] == "Carol"`

**T3 — Reactive sharing via column view**
- `c = cell_at(tabular_column(g, 1), 2)` — Bob's name raw `Cell`
- `c[] = TabularCell(Cell("Bobby"))`
- `tabular_cell(g, 2, 1) == "Bobby"` — same `Cell`, no copy

**T4 — Row insert**
- `insert_row!(g, 2, TabularRow(...))` with `("Dave", 28, "Rome", "dave@example.com")`
- `length(g.rows) == 4`
- Row 1: `"Alice"`, row 2: `"Dave"`, row 3: `"Bob"`, row 4: `"Carol"`

**T5 — Column view reflects row insert**
- `col = tabular_column(g, 1)`; `length(col) == 4`; `col[2] == "Dave"`

**T6 — Row delete**
- `delete_row!(g, 2)` — removes Dave
- `length(g.rows) == 3`; row 1: `"Alice"`, row 2: `"Bob"`, row 3: `"Carol"`

**T7 — Column insert**
- `insert_column!(g, 4, [TabularCell("+44"), TabularCell("+33"), TabularCell("+49")])` — phone before email
- `g.col_count == 5`
- `tabular_cell(g, 1, 4) == "+44"`, `tabular_cell(g, 1, 5) == "alice@example.com"` — email shifted right

**T8 — Column delete**
- `delete_column!(g, 2)` — removes age
- `g.col_count == 4`
- `tabular_cell(g, 1, 2) == "London"`, `tabular_cell(g, 2, 2) == "Paris"` — city now at col 2

**T9 — Nesting**
- Build a 1 × 2 inner grid; assign as content of cell (1, 1)
- `tabular_cell(g, 1, 1) isa TabularGrid`
- `tabular_cell(tabular_cell(g, 1, 1), 1, 1) == expected_value`

### Wiring into `test/src/ProjecturedTest.jl`

```julia
include("document/TabularTest.jl")   # in include block
test_tabular()                        # in test_documents()
export test_tabular                   # in export list
```
