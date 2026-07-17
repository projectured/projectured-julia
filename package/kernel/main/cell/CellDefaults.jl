# Fragment of `CellModule` — the behaviour the cell contract supplies itself: the
# body for `unwrap_cell`, whose generic is declared in `CellInterface.jl`.

unwrap_cell(x) = x isa AbstractCell ? x[] : x
