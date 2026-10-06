# Fragment of `PivotModule`.
#
# The chart views of a cell: a bar chart, a line chart and a pie chart of the
# first measure over the values of the cell dimensions in the part of the cell.
# The first cell dimension gives the categories, or the x of a line, and the
# second the series. The data of every chart is computed in one pass over the
# parts, so every cell has the same categories and the same range of values,
# and the charts of the cells can be compared.

describe_pivot_cell_view(::Type{PivotBarChartView}) = "bar charts"
describe_pivot_cell_view(::Type{PivotLineChartView}) = "line charts"
describe_pivot_cell_view(::Type{PivotPieChartView}) = "pie charts"

const _PivotChartView = Union{PivotBarChartView,PivotLineChartView,PivotPieChartView}

get_pivot_cell_view_lines(::_PivotChartView) = 5

# A chart cell is made from the data of all the charts, so it depends on that
# data, which a change of the source, a zone or the measure computes again.
get_pivot_cell_key(pivot::PivotTable, ::_PivotChartView, ::Tuple, ::Tuple) =
    objectid(_get_pivot_chart_data(pivot))

# The data of the charts of a pivot: the categories, the values of the first cell
# dimension in their order; the series, the values of the second, or one series
# with no key; and for each cell that a row reaches, the value of the measure
# for each category and series, and whether any row has them. `low` and `high`
# are the range of every value of every cell, and of zero, so a bar starts at
# the axis. A mutable struct, so a new computation is a new object, which the
# keys of the cell documents follow.
mutable struct _PivotChartData
    categories::Vector{Any}
    series::Vector{Any}
    values::Dict{Tuple{Tuple,Tuple},Matrix{Float64}}
    present::Dict{Tuple{Tuple,Tuple},Matrix{Bool}}
    low::Float64
    high::Float64
end

# The value of `kind` in the memo of the cells of `pivot` while `key`, what it is
# computed from, stays the same; `compute` makes it again for a new key. The memo
# keeps one value for each kind, so an old value does not stay.
function _get_pivot_memo!(compute, pivot::PivotTable, kind, key)
    memo = pivot.cells.memo
    found = get(memo, kind, nothing)
    (found !== nothing && isequal(found[1], key)) && return found[2]
    value = compute()
    memo[kind] = (key, value)
    value
end

# The data of the charts, kept in the memo of the cells by what it is computed
# from: the cross table, the cell dimensions and the first measure.
function _get_pivot_chart_data(pivot::PivotTable)
    cross = pivot.cross_table
    dimensions = collect(pivot.cell_dimensions)
    measure = first(get_pivot_measures(pivot))
    key = (objectid(cross), String[dimension.column for dimension in dimensions], measure.column, measure.aggregate)
    _get_pivot_memo!(() -> _compute_pivot_chart_data(pivot, cross, dimensions, measure), pivot, :charts, key)
end

function _compute_pivot_chart_data(pivot::PivotTable, cross::PivotCrossTable, dimensions, measure)
    source = pivot.source
    isempty(dimensions) &&
        return _PivotChartData(Any[], Any[nothing], Dict{Tuple{Tuple,Tuple},Matrix{Float64}}(),
                               Dict{Tuple{Tuple,Tuple},Matrix{Bool}}(), 0.0, 1.0)
    category_dimension = dimensions[1:1]
    series_dimension = length(dimensions) >= 2 ? dimensions[2:2] : PivotDimension[]
    categories = Any[only(key) for key in compute_pivot_cross_table(source, category_dimension, PivotDimension[]).row_keys]
    series = isempty(series_dimension) ? Any[nothing] :
        Any[only(key) for key in compute_pivot_cross_table(source, series_dimension, PivotDimension[]).row_keys]
    category_index = Dict{Any,Int}(category => k for (k, category) in enumerate(categories))
    series_index = Dict{Any,Int}(value => k for (k, value) in enumerate(series))
    values = Dict{Tuple{Tuple,Tuple},Matrix{Float64}}()
    present = Dict{Tuple{Tuple,Tuple},Matrix{Bool}}()
    low, high = 0.0, 0.0
    for (r, row_key) in enumerate(cross.row_keys), (c, column_key) in enumerate(cross.column_keys)
        rows = find_pivot_part_rows(cross, r, c)
        rows === nothing && continue
        rows = collect(rows)
        inner = compute_pivot_cross_table(make_table_part(source, rows), category_dimension, series_dimension)
        cell_values = zeros(length(categories), length(series))
        cell_present = falses(length(categories), length(series))
        for (i, category_key) in enumerate(inner.row_keys), (j, series_key) in enumerate(inner.column_keys)
            part = find_pivot_part_rows(inner, i, j)
            part === nothing && continue
            value = compute_pivot_measure(source, rows[part], measure)
            (value isa Real && isfinite(value)) || continue
            k = category_index[only(category_key)]
            s = isempty(series_key) ? 1 : series_index[only(series_key)]
            cell_values[k, s] = Float64(value)
            cell_present[k, s] = true
            low, high = min(low, Float64(value)), max(high, Float64(value))
        end
        values[(row_key, column_key)] = cell_values
        present[(row_key, column_key)] = cell_present
    end
    high > low || (high = low + 1.0)
    _PivotChartData(categories, series, values, present, low, high)
end

# The count of the values of a dimension, kept in the memo of the cells for each
# column by the source and the dimension: for the automatic choice of a view,
# and for the warning of the bar about a dimension of many values.
function _count_pivot_categories(pivot::PivotTable, dimension)
    key = (pivot.source_version, dimension.bin, Tuple(dimension.hidden_values))
    _get_pivot_memo!(pivot, (:categories, dimension.column), key) do
        get_pivot_row_count(compute_pivot_cross_table(pivot.source, [PivotDimension(dimension.column;
            hidden_values = dimension.hidden_values, bin = dimension.bin)], PivotDimension[]))
    end
end

# The compact axes of a chart in a cell: no title, no labels and no grid.
_make_pivot_value_axis(data::_PivotChartData) =
    ChartAxis(; min = data.low, max = data.high, show_title = false, show_labels = false, grid = :none)

_make_pivot_category_axis(data::_PivotChartData) =
    ChartCategoryAxis(; categories = String[format_pivot_value(category) for category in data.categories],
                      show_title = false, show_labels = false)

_describe_pivot_series(value) = value === nothing ? "" : format_pivot_value(value)

_make_pivot_chart(series, x_axis, y_axis) =
    PivotChartCell(Chart("", series; x_axis, y_axis, legend = ChartLegend(; visible = false)))

function make_pivot_cell_document(pivot::PivotTable, ::PivotBarChartView, row_key::Tuple, column_key::Tuple)
    data = _get_pivot_chart_data(pivot)
    values = get(data.values, (row_key, column_key), nothing)
    values === nothing && return WidgetLabel("")
    series = Any[ChartBarSeries(_describe_pivot_series(data.series[s]), values[:, s]) for s in eachindex(data.series)]
    _make_pivot_chart(series, _make_pivot_category_axis(data), _make_pivot_value_axis(data))
end

function make_pivot_cell_document(pivot::PivotTable, ::PivotLineChartView, row_key::Tuple, column_key::Tuple)
    data = _get_pivot_chart_data(pivot)
    values = get(data.values, (row_key, column_key), nothing)
    values === nothing && return WidgetLabel("")
    present = data.present[(row_key, column_key)]
    numeric = all(category -> category isa Real, data.categories)
    x = Float64[numeric ? Float64(category) : k for (k, category) in enumerate(data.categories)]
    series = Any[]
    for s in eachindex(data.series)
        shown = findall(present[:, s])
        push!(series, ChartLineSeries(_describe_pivot_series(data.series[s]), x[shown], values[shown, s]))
    end
    x_axis = ChartAxis(; min = isempty(x) ? 0.0 : minimum(x), max = isempty(x) ? 1.0 : maximum(x),
                       show_title = false, show_labels = false, grid = :none)
    _make_pivot_chart(series, x_axis, _make_pivot_value_axis(data))
end

function make_pivot_cell_document(pivot::PivotTable, ::PivotPieChartView, row_key::Tuple, column_key::Tuple)
    data = _get_pivot_chart_data(pivot)
    values = get(data.values, (row_key, column_key), nothing)
    values === nothing && return WidgetLabel("")
    labels = String[format_pivot_value(category) for category in data.categories]
    _make_pivot_chart(Any[ChartPieSeries("", labels, vec(sum(values; dims = 2)))], ChartAxis(), ChartAxis())
end

# ── The projection of a chart cell ───────────────────────────────────────────

"""
    PivotChartCellToChart()

Projects a [`PivotChartCell`](@ref) to its chart, which the chain of the chart
domain draws.
"""
struct PivotChartCellToChart <: Projection end

print_document(p::PivotChartCellToChart, recursion, cell::PivotChartCell, ctx) = SimpleIoMap(p, cell, cell.chart)

"""
    make_pivot_chart_cell_projection(; measure, appearance = Appearance()) -> Projection

The projection that draws a [`PivotChartCell`](@ref): its chart through the chart
domain, at the size of its cell and at least 24 × 16 pixels, in the chart theme
of `appearance`.
"""
make_pivot_chart_cell_projection(; measure::TextMeasure, appearance::Appearance = Appearance()) =
    ChainingProjection(PivotChartCellToChart(), ChartToChartPlot(),
                       ChartPlotToGraphicsCanvas(; measure, width = 160, height = 90, minimum_width = 24,
                                                 minimum_height = 16,
                                                 theme = get_scaled_theme!(appearance, ChartTheme)))
