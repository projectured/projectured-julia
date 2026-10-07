# Fragment of `LayoutModule` — the layout document types: the abstract
# `LayoutDocument`, the size policy a child declares, and the containers that
# arrange children under it.

abstract type LayoutDocument <: Document end

# A layout arranges what it holds, so its duplicate arranges the duplicates.
has_document_duplicate(::LayoutDocument) = true

# ── Size policy ─────────────────────────────────────────────────────────────

"""
    SizePolicy(min, preferred, max, weight)

Where a child's size on one axis comes from. It is **not a fifth field**: a policy
is a way of writing the four that `LayoutConstraint` already has, so there is one
place a size is decided and one place to extend.

Four policies say everything:

| policy | means | written as |
| --- | --- | --- |
| `Fixed(n)` | that many pixels, whatever is offered | `min = max = preferred = n` |
| `Content` | grow with the content | `preferred = intrinsic`, no weight |
| `Relative(w)` | a share `w` of what is offered | `preferred = 0`, `weight = w` |
| `Fill` | all of what is offered | `Relative(1.0)` |

A policy is a statement about a **relationship**, which is why it lives here and
not on the widget: `Relative(1.0)` means nothing without a parent that divides,
and `Fill` means nothing without a parent that offers. A parent that is offered
no extent on an axis has nothing to divide there, so a weighted child, column or
row takes the extent of its content on that axis. The same card fills the
width in a conversation column and is content-wide in a toolbar, because the
container it is placed in says so and the card is placed twice, unchanged.
"""
struct SizePolicy
    min::Union{Nothing,Int}
    preferred::Union{Nothing,Int}
    max::Union{Nothing,Int}
    weight::Union{Nothing,Float64}
end

"""
    Fixed(n) -> SizePolicy

`n` pixels on this axis, whatever is offered.

Use it to give every child of a layout a fixed width or height: a label column
of 120 pixels, a row of buttons 32 pixels high. A layout takes it as
`child_width` or `child_height`; a `GridLayout` takes it per column or per row.

# Example

    open_pane!(VerticalLayout(Any[WidgetLabel("Runs"), WidgetLabel("Results")];
                                      gap = 4, child_width = Fixed(200));
               title = "Fixed width")

See also `Content`, `Relative` and `Fill`, the other three policies.
"""
Fixed(n::Integer) = SizePolicy(Int(n), Int(n), Int(n), 0.0)

"""
    Content -> SizePolicy

Grow with the content on this axis. The child keeps its intrinsic extent, and an
offer does not stretch it.

Use it to keep a child as wide or as tall as what it shows: a label, a badge, a
button beside a field that fills the rest. It is the default of every layout.

# Example

    open_pane!(GridLayout(Any[WidgetLabel("Filter"), WidgetText(""; width = 120)], 2;
                                  column_policies = [Content, Fill]);
               title = "Form")

See also `Fixed`, `Relative` and `Fill`.
"""
const Content = SizePolicy(nothing, nothing, nothing, 0.0)

"""
    Relative(weight) -> SizePolicy

A share of what the parent offers on this axis, in proportion to `weight` against
its siblings' weights.

Use it to divide a width or a height between children by ratio: a table that
takes two thirds beside a plot that takes one. `Fill` is `Relative(1.0)`.

# Example

    root = get_project_result_directory()
    table = make_result_table(get_simulation_scalar_results(root))
    plot = make_result_plot(get_simulation_vector_results(root))
    open_pane!(GridLayout(Any[table, plot], 2; column_policies = [Relative(2.0), Relative(1.0)]); title = "Two thirds")

See also `Fill`, `Fixed` and `Content`.
"""
Relative(weight::Real) = SizePolicy(0, 0, nothing, Float64(weight))

"""
    Fill -> SizePolicy

All of what the parent offers on this axis — `Relative(1.0)`. Two `Fill` siblings
share the offer equally, which is what a weight of one each means.

Use it to stretch a child to the width or the height of its layout: a table
that takes the whole pane, two plots that share a row equally.

# Example

    root = get_project_result_directory()
    table = make_result_table(get_simulation_scalar_results(root))
    open_pane!(VerticalLayout(Any[table]; child_width = Fill); title = "Wide")

See also `Relative`, `Fixed` and `Content`.
"""
const Fill = Relative(1.0)

# ── HorizontalLayout ────────────────────────────────────────────────────────

"""
    HorizontalLayout(children; vertical_align, gap)

A row of children. The projection places each child at an
increasing x cursor, with vertical alignment chosen by
`vertical_align ∈ (:top, :center, :bottom, :baseline)`. On `:baseline` each
child stands so that the baseline of its first line of text
(`find_first_baseline`) meets the lowest one of the row, and a child with no
text stands on its bottom edge, so a label beside a text of another size or
line spacing reads on one line. The outer canvas has
width = sum of child widths + gaps and height = the lowest point that a child
reaches.

Use it to put widgets or documents side by side in one row, from left to right.

# Example

    open_pane!(HorizontalLayout([table, plot]; gap = 8); title = "Side by side")

See also `VerticalLayout`, `GridLayout`.
"""
@document struct HorizontalLayout <: LayoutDocument
    children::CellVector = CellVector()
    vertical_align::Symbol = :top
    gap::Int = 0
    child_width::Any = nothing
    child_height::Any = nothing
end

function HorizontalLayout(children::Vector;
                          vertical_align::Symbol=:top,
                          gap::Integer=0,
                          child_width::Union{Nothing,SizePolicy}=nothing,
                          child_height::Union{Nothing,SizePolicy}=nothing)
    HorizontalLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                     Cell(vertical_align), Cell(Int(gap)),
                     Cell(child_width), Cell(child_height), Cell(nothing))
end

# A row of the children of a list, which it draws lazily: the children that a
# viewport shows, walked from the head. See `LayoutList.jl`.
function HorizontalLayout(children::ListNode;
                          vertical_align::Symbol=:top,
                          gap::Integer=0,
                          child_width::Union{Nothing,SizePolicy}=nothing,
                          child_height::Union{Nothing,SizePolicy}=nothing)
    HorizontalLayout(Cell(children), Cell(vertical_align), Cell(Int(gap)),
                     Cell(child_width), Cell(child_height), Cell(nothing))
end

# ── VerticalLayout ──────────────────────────────────────────────────────────

"""
    VerticalLayout(children; horizontal_align, gap)

A column of children. Symmetric to `HorizontalLayout`:
`horizontal_align ∈ (:left, :center, :right)`. Outer width = max
of child widths; outer height = sum of child heights + gaps.

Use it to put widgets or documents one under another in one column, from top to
bottom.

# Example

    open_pane!(VerticalLayout([plot, table]; gap = 8); title = "Stacked")

See also `HorizontalLayout`, `GridLayout`.
"""
@document struct VerticalLayout <: LayoutDocument
    children::CellVector = CellVector()
    horizontal_align::Symbol = :left
    gap::Int = 0
    child_width::Any = nothing
    child_height::Any = nothing
end

function VerticalLayout(children::Vector;
                        horizontal_align::Symbol=:left,
                        gap::Integer=0,
                        child_width::Union{Nothing,SizePolicy}=nothing,
                        child_height::Union{Nothing,SizePolicy}=nothing)
    VerticalLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                   Cell(horizontal_align), Cell(Int(gap)),
                   Cell(child_width), Cell(child_height), Cell(nothing))
end

# A column of the children of a list, which it draws lazily: the children that a
# viewport shows, walked from the head. See `LayoutList.jl`.
function VerticalLayout(children::ListNode;
                        horizontal_align::Symbol=:left,
                        gap::Integer=0,
                        child_width::Union{Nothing,SizePolicy}=nothing,
                        child_height::Union{Nothing,SizePolicy}=nothing)
    VerticalLayout(Cell(children), Cell(horizontal_align), Cell(Int(gap)),
                   Cell(child_width), Cell(child_height), Cell(nothing))
end

# ── GridLayout ──────────────────────────────────────────────────────────────

"""
    GridLayout(children, columns; horizontal_align, vertical_align,
               horizontal_gap, vertical_gap, column_align,
               column_policy, row_policy, column_policies, row_policies)

A grid of children in row-major order. `horizontal_align` / `vertical_align`
apply within each cell.

Use it to arrange widgets or documents in rows and columns — a table of cards, a
dashboard of plots, a form — as the content of a pane. `children` go row by row,
and `columns` says how many in a row.

# Example

    open_pane!(GridLayout([plot_a, plot_b, table_a, table_b], 2); title = "Overview")

See also `HorizontalLayout`, `VerticalLayout`, `FlowLayout`.

**A column and a row take the same `SizePolicy` a stack's children take.**
`column_policy` and `row_policy` say what every column and every row is, and
`column_policies` / `row_policies` name the ones that differ — the grid's shape
of the default constraint the stacks carry as `child_width` / `child_height`.
An entry past the end of a vector, or `nothing` in one, means the default.

| policy | a column | a row |
| --- | --- | --- |
| `Content` | as wide as its widest cell | as tall as its tallest cell |
| `Fixed(n)` | exactly `n` | exactly `n` |
| `Relative(w)` | a share of what is left, by weight | a share of what is left |
| `Fill` | `Relative(1.0)` | `Relative(1.0)` |

**Both default to `Content`**, which is what a grid has always meant.

A weighted column or row is given its share of what the parent offered, and its
cells are offered that share. A `Content` one keeps the axis withheld, because
its extent comes from those cells and offering it back would close a cycle.
Every column and row is at least the `min` and at most the `max` of its policy.

`column_offers` and `row_offers` are one `Bool` for each column and each row: a
`false` keeps the extent of a sized column or row from its cells, which it then
clips. A caller uses it to measure a cell at its own size in a column or a row
that another grid sizes.

`row_gaps` holds the gap above each row, by the index of the row: an entry past
its end, or `nothing`, is `vertical_gap`, and the entry of the first row is not
used. A form uses it to keep the description of a field close to the row of the
field, and the next field further away.
"""
@document struct GridLayout <: LayoutDocument
    children::CellVector
    columns::Int
    horizontal_align::Symbol
    vertical_align::Symbol
    horizontal_gap::Int
    vertical_gap::Int
    column_align::Any        # Vector{Symbol}; empty ⇒ use horizontal_align for every column
    column_policy::Any       # SizePolicy — what every column is
    row_policy::Any          # SizePolicy — what every row is
    column_policies::Any     # Vector{SizePolicy} — the columns that differ
    row_policies::Any        # Vector{SizePolicy} — the rows that differ
    # Vector{Bool}, one per column; a column past its end, or an empty vector,
    # hands its extent out. A column that was given an extent — `Fixed`, or a
    # weight — normally offers that extent to its cells, so a cell that breaks
    # its lines breaks them there. `false` withholds the offer while the column
    # keeps its extent and clips to it: the cell draws at the size it measures,
    # a label as one line, and the grid cuts it at the column's edge. That is
    # what a table means by a clipped cell, and it is said here because the
    # offer is the grid's to make.
    column_offers::Any
    # Vector{Bool}, one per row; the same for the height of a row.
    row_offers::Any
    # Vector, one per row: the gap above it, or `nothing` for `vertical_gap`.
    row_gaps::Any
end

function GridLayout(children::Vector, columns::Integer;
                    horizontal_align::Symbol=:left,
                    vertical_align::Symbol=:top,
                    horizontal_gap::Integer=0,
                    vertical_gap::Integer=0,
                    column_align=Symbol[],
                    column_policy::SizePolicy=Content,
                    row_policy::SizePolicy=Content,
                    column_policies=Any[],
                    row_policies=Any[],
                    column_offers=Bool[],
                    row_offers=Bool[],
                    row_gaps=Any[])
    columns >= 1 || error("GridLayout: columns must be >= 1")
    GridLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
               Cell(Int(columns)),
               Cell(horizontal_align), Cell(vertical_align),
               Cell(Int(horizontal_gap)), Cell(Int(vertical_gap)),
               Cell(collect(column_align)),
               Cell(column_policy), Cell(row_policy),
               Cell(collect(Any, column_policies)), Cell(collect(Any, row_policies)),
               Cell(collect(Bool, column_offers)), Cell(collect(Bool, row_offers)),
               Cell(collect(Any, row_gaps)), Cell(nothing))
end

# A grid of the rows of a list, which it draws lazily: the rows that a viewport
# shows, walked from the head. Each row is a vector of the documents of its
# cells, one for each column, or, when `column_policies` is a list, a list of
# them anchored with it, which the grid draws lazily as well. See `GridList.jl`
# and `GridColumnList.jl`.
function GridLayout(rows::ListNode, columns::Integer;
                    horizontal_align::Symbol=:left,
                    vertical_align::Symbol=:top,
                    horizontal_gap::Integer=0,
                    vertical_gap::Integer=0,
                    column_align=Symbol[],
                    column_policy::SizePolicy=Content,
                    row_policy::SizePolicy=Content,
                    column_policies=Any[],
                    column_offers=Bool[])
    columns >= 1 || error("GridLayout: columns must be >= 1")
    GridLayout(Cell(rows), Cell(Int(columns)),
               Cell(horizontal_align), Cell(vertical_align),
               Cell(Int(horizontal_gap)), Cell(Int(vertical_gap)),
               Cell(column_align isa ListNode ? column_align : collect(column_align)),
               Cell(column_policy), Cell(row_policy),
               Cell(column_policies isa ListNode ? column_policies : collect(Any, column_policies)),
               Cell(Any[]), Cell(collect(Bool, column_offers)), Cell(Bool[]),
               Cell(Any[]), Cell(nothing))
end

"""
    FormLayout(rows; label_align=:right, horizontal_gap=12, vertical_gap=8)

A two-column form (Qt's `QFormLayout`): each `row` is a `(label, field)` pair of
**documents** (wrap text labels in `WidgetLabel`). The label column hugs (its
width = the widest label) and is `label_align`-aligned; the field column fills the
available width. Sugar over `GridLayout(2; column_align=[label_align, :left],
column_policies=[Content, Fill])` — see the column policies there.
"""
function FormLayout(rows::Vector;
                    label_align::Symbol=:right,
                    horizontal_gap::Integer=12,
                    vertical_gap::Integer=8)
    children = Any[]
    for row in rows
        (row isa Tuple && length(row) == 2) ||
            error("FormLayout: each row must be a (label, field) pair")
        push!(children, row[1]); push!(children, row[2])
    end
    GridLayout(children, 2;
               horizontal_gap=horizontal_gap, vertical_gap=vertical_gap,
               column_align=[label_align, :left], column_policies=Any[Content, Fill])
end

# ── FlowLayout ──────────────────────────────────────────────────────────────

"""
    FlowLayout(children; max_width, horizontal_align, vertical_align,
               horizontal_gap, vertical_gap)

A row of children that wraps to a new line when the next child would push past
the edge of the range its parent gives, or past `max_width` when that is less;
with neither, it is one line. The flow is as wide as its widest line, and as
wide as the edge of an exact range, but not wider than `max_width` unless one
child is. Each line is laid out left-to-right;
line height = max `h` of children on that line. `horizontal_align`
controls intra-line justification (`:left`, `:center`, `:right`);
`vertical_align` controls cross-axis alignment within a line
(`:top`, `:center`, `:bottom`).

Use it to put many widgets in a row that wraps to the next line when it is full
— a gallery of cards, a set of badges — within `max_width`.

# Example

    open_pane!(FlowLayout(cards; max_width = 800); title = "Cards")

See also `GridLayout` for fixed columns.
"""
@document struct FlowLayout <: LayoutDocument
    children::CellVector = CellVector()
    max_width::Union{Nothing,Int} = nothing
    horizontal_align::Symbol = :left
    vertical_align::Symbol = :top
    horizontal_gap::Int = 0
    vertical_gap::Int = 0
end

function FlowLayout(children::Vector;
                    max_width::Union{Nothing,Integer}=nothing,
                    horizontal_align::Symbol=:left,
                    vertical_align::Symbol=:top,
                    horizontal_gap::Integer=0,
                    vertical_gap::Integer=0)
    FlowLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
               Cell(max_width === nothing ? nothing : Int(max_width)),
               Cell(horizontal_align), Cell(vertical_align),
               Cell(Int(horizontal_gap)), Cell(Int(vertical_gap)),
               Cell(nothing))
end

# ── StackLayout ────────────────────────────────────────────────────────────

"""
    StackLayout(children; horizontal_align, vertical_align)

A z-ordered stack of children. All children share the same origin;
child order is z-order (first = bottom, last = top). The outer
canvas has width = max of child widths and height = max of child
heights. Per-child `(x, y)` is derived from `horizontal_align` /
`vertical_align` against the outer extent. Used for overlays,
badges, and composing background / foreground layers.

Use it to put widgets one over another at the same place — a badge on a card, a
label over a plot — the last child on top.

# Example

    StackLayout([plot, badge])

See also `GridLayout`, `VerticalLayout`.
"""
@document struct StackLayout <: LayoutDocument
    children::CellVector = CellVector()
    horizontal_align::Symbol = :left
    vertical_align::Symbol = :top
    active::Int = 0
end

function StackLayout(children::Vector;
                     horizontal_align::Symbol=:left,
                     vertical_align::Symbol=:top,
                     active::Integer=0)
    StackLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                Cell(horizontal_align), Cell(vertical_align), Cell(Int(active)), Cell(nothing))
end

# ── LayoutConstraint ────────────────────────────────────────────────────────

"""
    LayoutConstraint(child; min_width, preferred_width, max_width, weight_width,
                            min_height, preferred_height, max_height, weight_height)

A wrapper document that attaches per-child layout policy to `child` without
polluting the child's own type with layout fields. A parent layout reads
these values to allocate available space across its children; a bare
(unwrapped) child uses the defaults (`min=0`, `preferred=intrinsic`,
`max=∞`, `weight=0`).

Each axis field is `nothing` by default. When `nothing`, the parent layout
falls back to the bare-child interpretation for that field.

Say it with a [`SizePolicy`](@ref) rather than four numbers wherever one fits:
`LayoutConstraint(card; width = Fill, height = Content)`. A field written beside a
policy wins over it.

`column_span` is the number of columns of a `GridLayout` that `child` takes, 1
by default; see [`get_column_span`](@ref). Every other layout ignores it.
"""
@document struct LayoutConstraint
    child::Document
    min_width::Any
    preferred_width::Any
    max_width::Any
    weight_width::Any
    min_height::Any
    preferred_height::Any
    max_height::Any
    weight_height::Any
    column_span::Any
end

function LayoutConstraint(child::Document;
                          width::Union{Nothing,SizePolicy}=nothing,
                          height::Union{Nothing,SizePolicy}=nothing,
                          min_width=nothing, preferred_width=nothing,
                          max_width=nothing, weight_width=nothing,
                          min_height=nothing, preferred_height=nothing,
                          max_height=nothing, weight_height=nothing,
                          column_span=nothing)
    # A policy writes the four fields; an explicit field beside it wins, so a
    # caller can say `width = Fill, min_width = 120` and mean both.
    if width !== nothing
        min_width       === nothing && (min_width       = width.min)
        preferred_width === nothing && (preferred_width = width.preferred)
        max_width       === nothing && (max_width       = width.max)
        weight_width    === nothing && (weight_width    = width.weight)
    end
    if height !== nothing
        min_height       === nothing && (min_height       = height.min)
        preferred_height === nothing && (preferred_height = height.preferred)
        max_height       === nothing && (max_height       = height.max)
        weight_height    === nothing && (weight_height    = height.weight)
    end
    LayoutConstraint(Cell(child),
                     Cell(min_width), Cell(preferred_width),
                     Cell(max_width), Cell(weight_width),
                     Cell(min_height), Cell(preferred_height),
                     Cell(max_height), Cell(weight_height),
                     Cell(column_span), Cell(nothing))
end

# ── Constraint reading helpers ───────────────────────────────────────────────

"""
    layout_min(doc, axis, intrinsic) -> Int

Per-child minimum on `axis` (`:x` or `:y`). Reads through the
`LayoutConstraint` wrapper when present; falls back to `0` for bare
children.
"""
function layout_min(doc, axis::Symbol, intrinsic::Integer; default=nothing)
    doc isa LayoutConstraint || return _policy_field(default, :min, 0)
    v = axis === :x ? doc.min_width : doc.min_height
    v === nothing ? _policy_field(default, :min, 0) : Int(v)
end

# One field of the layout's default policy for this axis, or the bare-child
# answer when the layout named none. A bare child means "use the container's
# default", not "policy lives somewhere else".
function _policy_field(default, field::Symbol, bare)
    default isa SizePolicy || return bare
    v = getfield(default, field)
    v === nothing ? bare : (field === :weight ? Float64(v) : Int(v))
end

"""
    layout_max(doc, axis, intrinsic) -> Int

Per-child maximum on `axis`. Falls back to `typemax(Int)` for bare children.
"""
function layout_max(doc, axis::Symbol, intrinsic::Integer; default=nothing)
    doc isa LayoutConstraint || return _policy_field(default, :max, typemax(Int))
    v = axis === :x ? doc.max_width : doc.max_height
    v === nothing ? _policy_field(default, :max, typemax(Int)) : Int(v)
end

"""
    layout_preferred(doc, axis, intrinsic) -> Int

Per-child preferred extent on `axis`. Falls back to the child's intrinsic
extent (`intrinsic`) when the constraint is absent or `nothing`.
"""
function layout_preferred(doc, axis::Symbol, intrinsic::Integer; default=nothing)
    doc isa LayoutConstraint || return _policy_field(default, :preferred, Int(intrinsic))
    v = axis === :x ? doc.preferred_width : doc.preferred_height
    v === nothing ? _policy_field(default, :preferred, Int(intrinsic)) : Int(v)
end

"""
    get_column_span(doc) -> Int

The number of columns of a `GridLayout` that the child `doc` takes: the
`column_span` of its `LayoutConstraint`, at least 1, and 1 for a bare child or a
constraint that names none.
"""
function get_column_span(doc)
    doc isa LayoutConstraint || return 1
    span = doc.column_span
    span === nothing ? 1 : max(1, Int(span))
end

"""
    layout_weight(doc, axis; default=nothing) -> Float64

Per-child weight on `axis`. Falls back to `0.0` for bare children.
"""
function layout_weight(doc, axis::Symbol; default=nothing)
    doc isa LayoutConstraint || return _policy_field(default, :weight, 0.0)
    v = axis === :x ? doc.weight_width : doc.weight_height
    v === nothing ? _policy_field(default, :weight, 0.0) : Float64(v)
end

# ── The bands of an axis ─────────────────────────────────────────────────────
#
# A grid's columns and a table's rules are one sum: the edge of every band,
# cumulative over the extents and a gap. It is written once here, beside the
# allocator every stack shares, and the inverse beside it.

"""
    compute_axis_offsets(extents, gap) -> Vector{Int}

The edge of every band on one axis: `n + 1` edges for `n` extents, the first
at zero and each next one an extent and a gap further on. The last edge is the
far side of the last band.
"""
function compute_axis_offsets(extents::AbstractVector{<:Integer}, gap::Integer)
    offsets = Vector{Int}(undef, length(extents) + 1)
    offsets[1] = 0
    for k in eachindex(extents)
        offsets[k + 1] = offsets[k] + Int(extents[k]) + Int(gap)
    end
    offsets
end

"""
    find_axis_band(offsets, position) -> Int or nothing

The band a coordinate falls in, given the edges `compute_axis_offsets`
answers: band `k` spans `offsets[k] <= position < offsets[k + 1]`, and a
coordinate before the first edge or past the last is in no band. A table
whose rows are a list has no edges to give; it walks its rows instead.
"""
function find_axis_band(offsets::AbstractVector{<:Integer}, position::Integer)
    for k in 1:(length(offsets) - 1)
        offsets[k] <= position < offsets[k + 1] && return k
    end
    nothing
end

"""
    compute_axis_extents(policies, gap, available) -> Vector{Int}

The extent of every band on one axis from its policies alone, with nothing
measured: a `Fixed` band is its number, a weighted band shares `available`
with its siblings through `allocate_axis`, and a band that is its content — a
`Content` policy — has no extent here at all, because nothing was measured.
It is the rule the grid applies to a column it does not read the cells of,
and a table whose rows are a list applies it to every column, because a cell
that is never built cannot be measured.
"""
function compute_axis_extents(policies::AbstractVector, gap::Integer, available)
    n = length(policies)
    mins = Vector{Int}(undef, n); maxs = Vector{Int}(undef, n)
    prefs = Vector{Int}(undef, n); weights = Vector{Float64}(undef, n)
    weighted = false
    for k in 1:n
        (mins[k], maxs[k], prefs[k], weights[k]) = _gl_axis_inputs(policies[k]::SizePolicy, 0)
        weights[k] > 0 && (weighted = true)
    end
    (available === nothing || !weighted) && return prefs
    allocate_axis(Int(available); mins, maxs, prefs, weights, gap = Int(gap), n)
end

# ── Allocation algorithm (per axis, one pass) ───────────────────────────────

"""
    allocate_axis(available; mins, maxs, prefs, weights, gap, n) -> Vector{Int}

Pure allocator: distributes `available` extent across `n` children whose
seed sizes are `prefs` clamped to `[mins, maxs]`. Inter-child `gap` is
subtracted first. Slack > 0 is distributed in proportion to `weights`,
each share capped at `maxs[i]`; slack < 0 is taken in proportion to
`weights`, each draw floored at `mins[i]`. Returns one `Int` per child.

Pixel rounding may leave ±1 px residual; the residual is absorbed by the
last weighted child if any.
"""
function allocate_axis(available::Int; mins::Vector{Int}, maxs::Vector{Int},
                       prefs::Vector{Int}, weights::Vector{Float64}, gap::Int, n::Int)
    actual = Vector{Int}(undef, n)
    for i in 1:n
        actual[i] = clamp(prefs[i], mins[i], maxs[i])
    end
    n == 0 && return actual
    gaps_total = n > 1 ? (n - 1) * gap : 0
    seed_total = sum(actual)
    remaining  = available - seed_total - gaps_total

    if remaining > 0
        active = [i for i in 1:n if weights[i] > 0 && actual[i] < maxs[i]]
        while !isempty(active) && remaining > 0
            wsum = sum(weights[i] for i in active)
            wsum > 0 || break
            slack_in_pass = remaining
            # Compute each child's tentative share against the slack at the
            # *start* of this pass, then apply caps; redistribute residual
            # in the next outer iteration. This gives proportional shares
            # independent of iteration order.
            shares = Dict{Int,Int}()
            for i in active
                shares[i] = Int(floor(slack_in_pass * weights[i] / wsum))
            end
            # Hand out the floored residual to the largest-weight child so
            # the pass actually empties the slack on average.
            assigned = sum(values(shares); init=0)
            residual = slack_in_pass - assigned
            if residual > 0
                # Largest-weight active child absorbs the floor residual.
                heaviest = active[1]
                for i in active
                    weights[i] > weights[heaviest] && (heaviest = i)
                end
                shares[heaviest] += residual
            end
            any_change = false
            for i in copy(active)
                room = maxs[i] - actual[i]
                give = min(shares[i], room, remaining)
                if give > 0
                    actual[i] += give
                    remaining -= give
                    any_change = true
                end
                actual[i] >= maxs[i] && deleteat!(active, findfirst(==(i), active))
                remaining <= 0 && break
            end
            any_change || break
        end
    elseif remaining < 0
        deficit = -remaining
        active = [i for i in 1:n if weights[i] > 0 && actual[i] > mins[i]]
        while !isempty(active) && deficit > 0
            wsum = sum(weights[i] for i in active)
            wsum > 0 || break
            deficit_in_pass = deficit
            shares = Dict{Int,Int}()
            for i in active
                shares[i] = Int(floor(deficit_in_pass * weights[i] / wsum))
            end
            assigned = sum(values(shares); init=0)
            residual = deficit_in_pass - assigned
            if residual > 0
                heaviest = active[1]
                for i in active
                    weights[i] > weights[heaviest] && (heaviest = i)
                end
                shares[heaviest] += residual
            end
            any_change = false
            for i in copy(active)
                room = actual[i] - mins[i]
                take = min(shares[i], room, deficit)
                if take > 0
                    actual[i] -= take
                    deficit   -= take
                    any_change = true
                end
                actual[i] <= mins[i] && deleteat!(active, findfirst(==(i), active))
                deficit <= 0 && break
            end
            any_change || break
        end
    end
    actual
end

# ── AnchoredLayout ───────────────────────────────────────────────────────────
#
# Everything else here positions children *with* one another. This one positions
# them **relative to something already placed**, and composites them over it: the
# content is laid out as it would be anyway, and each anchored child is put beside
# a target inside it.
#
# The distinction is the whole point. An annotation on a diagram — a count beside
# a node, a rate along a link — must not change what it annotates. Because an
# anchored child never enters the content's own layout, the content's geometry
# does not depend on it, and a diagram whose annotations change every frame keeps
# its nodes exactly where they were.

"""
    AnchoredEntry(child, target; placement, offset_x, offset_y)

One anchored child and what it is anchored to.

`target` names the element to sit beside, either directly (a graphics document
whose position cells are read) or as a `reference` into the content, resolved
through the content's own IoMap. `placement` is the preferred side — `:above`,
`:below`, `:left` or `:right` — which the placement algorithm may overrule to
stay inside the bounding region. `offset_x`/`offset_y` are applied afterwards.

Follows `LayoutConstraint`'s pattern: a wrapper that attaches positioning policy
to a child without the child having to know about it.
"""
@document struct AnchoredEntry <: Document
    child::Document
    target::Any = nothing          # a graphics document, or nothing
    reference::Any = nothing       # a Reference into the content, or nothing
    placement::Symbol = :right
    offset_x::Int = 0
    offset_y::Int = 0
end

# Typed first argument, so this is a NEW method rather than an overwrite of the
# macro's one-positional-argument form (which is `(::Any)`) — the same trick
# `GraphEdge` uses for its mixed positional/keyword constructor.
AnchoredEntry(child::Document; target = nothing, reference = nothing,
              placement::Symbol = :right, offset_x::Integer = 0, offset_y::Integer = 0) =
    AnchoredEntry(Cell(child), Cell(target), Cell(reference), Cell(placement),
                  Cell(Int(offset_x)), Cell(Int(offset_y)), Cell(nothing))

"""
    AnchoredLayout(content, children; bounding_width, bounding_height, stacking_gap)

`content` laid out as usual, with each [`AnchoredEntry`](@ref) in `children`
placed beside its target and drawn on top.

`bounding_width`/`bounding_height` bound the region placement may use (zero
means the content's own extent). `stacking_gap` is the space left between
entries that would otherwise overlap.
"""
@document struct AnchoredLayout <: LayoutDocument
    content::Document
    children::CellVector = CellVector()
    bounding_width::Int = 0
    bounding_height::Int = 0
    stacking_gap::Int = 4
end

function AnchoredLayout(content::Document, children::Vector;
                        bounding_width::Integer = 0, bounding_height::Integer = 0,
                        stacking_gap::Integer = 4)
    AnchoredLayout(Cell(content),
                   CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                   Cell(Int(bounding_width)), Cell(Int(bounding_height)),
                   Cell(Int(stacking_gap)), Cell(nothing))
end

"""
    compute_anchored_positions(entries, targets; bounding_w, bounding_h, stacking_gap)
        -> Vector{Tuple{Int,Int}}

Where each anchored child goes. Pure — no cells, no documents — so it can be
tested on numbers alone, the way `allocate_axis` is.

`entries` is one `(w, h, placement, offset_x, offset_y)` per child and `targets`
one `(x, y, w, h)` or `nothing`. An entry whose target could not be resolved is
placed at the origin and left out of the stacking pass: it is anchored to
nothing, so it can crowd nothing.

Placement tries the preferred side, then the opposite, then the two
perpendicular ones, and finally clamps — a child that fits nowhere is still
drawn, inside the region, rather than off the edge where nobody would see it.
Entries that still overlap are stacked downward in `stacking_gap` steps, first
one placed first.
"""
function compute_anchored_positions(entries, targets; bounding_w::Int, bounding_h::Int,
                                    stacking_gap::Int)
    n = length(entries)
    positions = Vector{Tuple{Int,Int}}(undef, n)
    anchored = Int[]
    for i in 1:n
        w, h, placement, dx, dy = entries[i]
        target = targets[i]
        if target === nothing
            positions[i] = (0, 0)
            continue
        end
        x, y = _anchored_place(target, w, h, placement, bounding_w, bounding_h)
        positions[i] = (x + dx, y + dy)
        push!(anchored, i)
    end
    _anchored_stack!(positions, entries, anchored, stacking_gap)
    positions
end

# The candidate position on one side of the target, with the child centred on
# the other axis.
function _anchored_side(target, w::Int, h::Int, side::Symbol)
    tx, ty, tw, th = target
    side === :right  && return (tx + tw, ty + (th - h) ÷ 2)
    side === :left   && return (tx - w,  ty + (th - h) ÷ 2)
    side === :below  && return (tx + (tw - w) ÷ 2, ty + th)
    side === :above  && return (tx + (tw - w) ÷ 2, ty - h)
    (tx + tw, ty)
end

_anchored_opposite(side::Symbol) =
    side === :right ? :left : side === :left ? :right :
    side === :below ? :above : :below

_anchored_perpendicular(side::Symbol) =
    (side === :left || side === :right) ? (:below, :above) : (:right, :left)

# Whether a candidate position is inside the region, per axis. An axis with no
# bound has no wall on either side — including at the origin, because content
# may legitimately extend to negative coordinates (a diagram whose node boxes
# are padded outward from the layout origin does), and an annotation refusing
# the side it was asked for merely because that side is negative would put it
# somewhere the reader has no reason to expect.
_anchored_fits(x::Int, y::Int, w::Int, h::Int, bw::Int, bh::Int) =
    (bw <= 0 || (x >= 0 && x + w <= bw)) && (bh <= 0 || (y >= 0 && y + h <= bh))

function _anchored_place(target, w::Int, h::Int, placement::Symbol,
                         bounding_w::Int, bounding_h::Int)
    for side in (placement, _anchored_opposite(placement),
                 _anchored_perpendicular(placement)...)
        x, y = _anchored_side(target, w, h, side)
        _anchored_fits(x, y, w, h, bounding_w, bounding_h) && return (x, y)
    end
    x, y = _anchored_side(target, w, h, placement)
    (_anchored_clamp(x, w, bounding_w), _anchored_clamp(y, h, bounding_h))
end

_anchored_clamp(v::Int, extent::Int, bound::Int) =
    bound <= 0 ? max(v, 0) : clamp(v, 0, max(bound - extent, 0))

# Two anchored children that landed on top of one another are both unreadable;
# the later one moves down. Earlier entries keep their place, so the order the
# caller gave is the order on screen.
function _anchored_stack!(positions, entries, anchored::Vector{Int}, gap::Int)
    for a in 1:length(anchored)
        i = anchored[a]
        for b in 1:(a - 1)
            j = anchored[b]
            _anchored_overlaps(positions[i], entries[i], positions[j], entries[j]) || continue
            positions[i] = (positions[i][1],
                            positions[j][2] + entries[j][2] + gap)
        end
    end
    positions
end

function _anchored_overlaps(pi, ei, pj, ej)
    (xi, yi), (xj, yj) = pi, pj
    wi, hi = ei[1], ei[2]
    wj, hj = ej[1], ej[2]
    xi < xj + wj && xj < xi + wi && yi < yj + hj && yj < yi + hi
end

# ── ScrollLayout ─────────────────────────────────────────────────────────────
#
# A center and the parts around it. On its own the layout puts the parts in a
# grid of three columns and three rows. A scroll pane that shows a
# `ScrollLayout` takes it apart, and gives each part a viewport of its own that
# moves with the one offset of the pane on the axes on which the part scrolls.

"""
    ScrollLayout(; center, top, bottom, left, right,
                 top_left, top_right, bottom_left, bottom_right)

A `center` and up to four edges and four corners around it, each any document
or `nothing`. On its own it puts its parts in three columns and three rows (see
[`compute_scroll_layout_extents`](@ref)). In a `WidgetScrollPane` the pane moves
the center on both axes, the top and the bottom edge left and right with it, the
left and the right edge up and down with it, and the corners not at all, so the
edges and the corners stay in view.

The content that makes the parts makes them agree: a left edge as high as the
center, with its rows beside the rows of the center, as a gutter stands beside
the lines of a text.
"""
@document struct ScrollLayout <: LayoutDocument
    center::Union{Document, Nothing} = nothing
    top::Union{Document, Nothing} = nothing
    bottom::Union{Document, Nothing} = nothing
    left::Union{Document, Nothing} = nothing
    right::Union{Document, Nothing} = nothing
    top_left::Union{Document, Nothing} = nothing
    top_right::Union{Document, Nothing} = nothing
    bottom_left::Union{Document, Nothing} = nothing
    bottom_right::Union{Document, Nothing} = nothing
end

"""
    SCROLL_LAYOUT_PARTS

The names of the parts of a `ScrollLayout`, row by row from the top left. Its
projection keeps and draws the parts in this order, and the functions of the
layout name a part by its index here.
"""
const SCROLL_LAYOUT_PARTS = (:top_left, :top, :top_right, :left, :center, :right,
                             :bottom_left, :bottom, :bottom_right)

# The column (1 left, 2 middle, 3 right) and the row (1 top, 2 middle, 3 bottom)
# of the part at `index` of `SCROLL_LAYOUT_PARTS`.
_get_scroll_part_column(index::Integer) = mod1(index, 3)
_get_scroll_part_row(index::Integer) = div(index - 1, 3) + 1

"""
    compute_scroll_layout_extents(sizes) -> (widths, heights)

The widths of the three columns and the heights of the three rows of a
`ScrollLayout`. `sizes` holds one `(w, h)` for each part of
[`SCROLL_LAYOUT_PARTS`](@ref), in that order, or `nothing` for a part that is
absent. A column is as wide as its widest part, and a row as high as its highest
part. Pure, so it is tested on numbers alone.
"""
function compute_scroll_layout_extents(sizes)
    widths = [0, 0, 0]
    heights = [0, 0, 0]
    for (index, size) in enumerate(sizes)
        size === nothing && continue
        column, row = _get_scroll_part_column(index), _get_scroll_part_row(index)
        widths[column] = max(widths[column], Int(size[1]))
        heights[row] = max(heights[row], Int(size[2]))
    end
    (Tuple(widths), Tuple(heights))
end

"""
    get_scroll_layout_place(index, widths, heights) -> (x, y)

Where the part at `index` of `SCROLL_LAYOUT_PARTS` stands in the layout that puts
the parts together: the left edge of its column and the top edge of its row.
"""
function get_scroll_layout_place(index::Integer, widths, heights)
    column, row = _get_scroll_part_column(index), _get_scroll_part_row(index)
    (sum(widths[1:column-1]; init = 0), sum(heights[1:row-1]; init = 0))
end

"""
    find_scroll_layout_part_at(x, y, widths, heights) -> index | nothing

The index in `SCROLL_LAYOUT_PARTS` of the cell of the three columns and the three
rows that holds the point `(x, y)` of the layout that puts the parts together, or
`nothing` for a point outside it. The cell can be the place of a part that is
absent. The layout, the scroll pane and the content that made the parts find a
part by this one function, so they agree.
"""
function find_scroll_layout_part_at(x::Integer, y::Integer, widths, heights)
    column = _find_scroll_band(x, widths)
    row = _find_scroll_band(y, heights)
    (column === nothing || row === nothing) ? nothing : (row - 1) * 3 + column
end

# The band of `extents` that holds `v`, or `nothing` when `v` is outside them all.
function _find_scroll_band(v::Integer, extents)
    v < 0 && return nothing
    edge = 0
    for (k, extent) in enumerate(extents)
        edge += extent
        v < edge && return k
    end
    nothing
end

# ── ConstraintLayout ─────────────────────────────────────────────────────────
#
# Free-form layout: children are positioned by *solving* a system of linear
# equality/inequality relations over their edges, rather than by a fixed
# positioning policy. The relations and their anchors are themselves documents
# so the constraint system is editable/projectable like everything else.
#
# `LayoutConstraint` (above) is a *different* concept — the per-child sizing
# policy wrapper used by the flex layouts. The names below (`LayoutRelation`,
# `LayoutAnchor`) are deliberately distinct to avoid the collision.

"""
    LayoutAnchor(child, edge)

A handle naming one solver variable: an `edge` of a child (or of the parent
container). `child` is the 1-based index into `ConstraintLayout.children`, or
`0` to denote the parent container itself. `edge` is one of `:left`, `:right`,
`:top`, `:bottom`, `:width`, `:height`, `:centerx`, `:centery` — the derived
edges (`:right`, `:bottom`, `:centerx`, `:centery`) are expanded during the
solve, they are not independent variables.
"""
@document struct LayoutAnchor <: Document
    child::Int                  # 0 = parent container
    edge::Symbol
end

LayoutAnchor(child::Integer, edge::Symbol) =
    LayoutAnchor(Cell(Int(child)), Cell(edge), Cell(nothing))

"""
    anchor(child, edge) -> LayoutAnchor

DSL convenience for [`LayoutAnchor`](@ref). `anchor(0, edge)` refers to the
parent container.
"""
make_layout_anchor(child::Integer, edge::Symbol) = LayoutAnchor(child, edge)

"""
    LayoutRelation(terms; op, constant, strength)

One linear relation in the normalized form the solver consumes:

    Σ coeffᵢ · anchorᵢ   (op)   constant

`terms` is a list of `(LayoutAnchor, coefficient::Float64)` tuples, `op` is one
of `:(==)`, `:(<=)`, `:(>=)`, and `strength` is one of `:required`, `:strong`,
`:medium`, `:weak`. A `:required` relation is a hard constraint; the others are
soft (least-violation, weighted by strength).

Prefer the [`anchor`](@ref) / [`constrain`](@ref) DSL to build these.
"""
@document struct LayoutRelation <: Document
    terms::CellVector           # of (LayoutAnchor, coefficient::Float64)
    op::Symbol                  # :(==), :(<=), :(>=)
    constant::Float64
    strength::Symbol            # :required, :strong, :medium, :weak
end

function LayoutRelation(terms::Vector;
                        op::Symbol=:(==), constant::Real=0.0,
                        strength::Symbol=:required)
    LayoutRelation(CellVector(Cell[t isa Cell ? t : Cell(t) for t in terms]),
                   Cell(op), Cell(Float64(constant)), Cell(strength), Cell(nothing))
end

"""
    ConstraintLayout(children, relations; bounding_width, bounding_height)

A free-form layout. `children` are positioned by solving `relations` (a list of
[`LayoutRelation`](@ref)) over their edges. `bounding_width` / `bounding_height`
fix the parent container's `:right` / `:bottom` (its `:left` / `:top` are pinned
to 0) so relations can reference the container via `anchor(0, …)`; pass `0` to
leave the container intrinsically sized (outer extent = max child extent).
"""
@document struct ConstraintLayout <: LayoutDocument
    children::CellVector        # of arbitrary Document (the positioned content)
    relations::CellVector       # of LayoutRelation
    bounding_width::Int         # parent container width  (parent :width)
    bounding_height::Int        # parent container height (parent :height)
end

function ConstraintLayout(children::Vector, relations::Vector;
                          bounding_width::Integer=0, bounding_height::Integer=0)
    ConstraintLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                     CellVector(Cell[r isa Cell ? r : Cell(r) for r in relations]),
                     Cell(Int(bounding_width)), Cell(Int(bounding_height)),
                     Cell(nothing))
end

ConstraintLayout(children::Vector; kwargs...) =
    ConstraintLayout(children, Any[]; kwargs...)

# ── Relation DSL ─────────────────────────────────────────────────────────────
#
# A small affine-expression layer so relations read well in examples/tests:
#
#     constrain(anchor(2, :left), :(==), anchor(1, :right) + 8)
#     constrain(anchor(1, :width), :(>=), 120)
#     constrain(anchor(3, :centerx), :(==), anchor(0, :centerx); strength=:weak)
#
# `LayoutExpr` is a *plain* struct (not a document); `anchor()` returns a
# `LayoutAnchor` and the `+ - *` operators promote it into a `LayoutExpr`. We
# deliberately do NOT overload `==`/`<=`/`>=` on these types — that would shadow
# the identity equality every `@document` relies on — so comparisons go through
# the `constrain` function instead.

"""
    LayoutExpr(terms, constant)

A plain affine expression `Σ coeffᵢ · anchorᵢ + constant` used by the relation
DSL. Built by applying `+`, `-`, `*` to [`LayoutAnchor`](@ref)s; consumed by
[`constrain`](@ref).
"""
struct LayoutExpr
    terms::Vector{Tuple{LayoutAnchor,Float64}}
    constant::Float64
end

const _Termish = Union{LayoutAnchor, LayoutExpr}

_expr(a::LayoutAnchor) = LayoutExpr(Tuple{LayoutAnchor,Float64}[(a, 1.0)], 0.0)
_expr(e::LayoutExpr)   = e
_expr(c::Real)         = LayoutExpr(Tuple{LayoutAnchor,Float64}[], Float64(c))

_scale(e::LayoutExpr, k::Float64) =
    LayoutExpr(Tuple{LayoutAnchor,Float64}[(a, k * c) for (a, c) in e.terms], k * e.constant)

_add(x, y) = (ex = _expr(x); ey = _expr(y);
              LayoutExpr(vcat(ex.terms, ey.terms), ex.constant + ey.constant))

Base.:*(k::Real, x::_Termish) = _scale(_expr(x), Float64(k))
Base.:*(x::_Termish, k::Real) = _scale(_expr(x), Float64(k))
Base.:+(x::_Termish, y::Union{_Termish,Real}) = _add(x, y)
Base.:+(x::Real, y::_Termish) = _add(x, y)
Base.:-(x::_Termish) = _scale(_expr(x), -1.0)
Base.:-(x::_Termish, y::Union{_Termish,Real}) = _add(x, -_expr(y))
Base.:-(x::Real, y::_Termish) = _add(x, -_expr(y))

"""
    constrain(lhs, op, rhs; strength=:required) -> LayoutRelation

Build a [`LayoutRelation`](@ref) from two affine expressions and a comparison
`op` (`:(==)`, `:(<=)`, `:(>=)`). `lhs` / `rhs` may be `LayoutAnchor`,
`LayoutExpr`, or a plain number. The relation is normalized to
`Σ coeff·anchor (op) constant`.
"""
function constrain(lhs, op::Symbol, rhs; strength::Symbol=:required)
    op in (:(==), :(<=), :(>=)) ||
        error("constrain: op must be :(==), :(<=) or :(>=), got $(op)")
    diff = _add(_expr(lhs), -_expr(rhs))     # Σ coeff·anchor + const (op) 0
    LayoutRelation(diff.terms; op=op, constant=-diff.constant, strength=strength)
end
