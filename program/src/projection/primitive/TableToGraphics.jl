"""
    TableToGraphicsModule

Table → Graphics projection. Lays out a TableTable as a grid of
content-sized cells, drawing border rectangles and recursing into
each cell's content. Column widths and row heights are derived from
the `w`/`h` fields of each cell's projected `GraphicsCanvas`.
"""
module TableToGraphicsModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TableModule: TableDocument, TableTable, TableCell, TableRow, TableColumn
import ..GraphicsModule: GraphicsDocument, GraphicsCanvas, GraphicsRect, layout_none
import ..ColorModule: StyleColor, color_default, color_solarized_gray
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference, RangeReference, ReferencePath, append_reference
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..OperationModule: ReplaceSelectionOperation
export TableTableToGraphicsCanvas, TableToGraphics

# ── TableTableToGraphicsCanvas ──────────────────────────────────────────

struct TableTableToGraphicsCanvas <: Projection
    border_width::Int
    border_r::UInt8
    border_g::UInt8
    border_b::UInt8
    border_a::UInt8
end

function TableTableToGraphicsCanvas(;
        border_width::Int = 1,
        border_r::Integer = 128, border_g::Integer = 128,
        border_b::Integer = 128, border_a::Integer = 255)
    TableTableToGraphicsCanvas(border_width,
                               UInt8(border_r), UInt8(border_g), UInt8(border_b), UInt8(border_a))
end

function map_reference_forward(::TableTableToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::TableTableToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::TableTableToGraphicsCanvas, iomap::ChildrenIoMap, event)
    iomaps = iomap.child_iomaps[]
    for idx in 1:length(iomaps)
        child_im = iomaps[idx]
        child_im === nothing && continue
        op = projection_read(child_im.projection, child_im, event)
        if op isa ReplaceSelectionOperation
            return ReplaceSelectionOperation(@reference cells[idx].content.^(op.path))
        end
    end
    return nothing
end

# Helper: read w/h from an iomap's output GraphicsCanvas, defaulting to 0
_output_w(im) = im === nothing ? 0 : (let o = im.output; o isa GraphicsCanvas ? Int(o.w) : 0 end)
_output_h(im) = im === nothing ? 0 : (let o = im.output; o isa GraphicsCanvas ? Int(o.h) : 0 end)

function projection_print(p::TableTableToGraphicsCanvas, table::TableTable, recursion, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> begin
        nrows = length(table.rows)
        ncols = length(table.columns)
        ncells = length(table.cells)
        iomaps = []
        for idx in 1:ncells
            cell = table.cells[idx]
            if cell isa TableCell && cell.content !== nothing
                content_ref = @reference ^(reference).cells[idx].content
                push!(iomaps, projection_print(recursion, cell.content, recursion, child_context(ctx, content_ref)))
            else
                push!(iomaps, nothing)
            end
        end
        iomaps
    end)
    col_header_iomaps = Cell(() -> begin
        ncols = length(table.columns)
        iomaps = []
        for idx in 1:ncols
            col = table.columns[idx]
            if col isa TableColumn && col.content !== nothing
                col_ref = @reference ^(reference).columns[idx].content
                push!(iomaps, projection_print(recursion, col.content, recursion, child_context(ctx, col_ref)))
            else
                push!(iomaps, nothing)
            end
        end
        iomaps
    end)
    row_header_iomaps = Cell(() -> begin
        nrows = length(table.rows)
        iomaps = []
        for idx in 1:nrows
            row = table.rows[idx]
            if row isa TableRow && row.content !== nothing
                row_ref = @reference ^(reference).rows[idx].content
                push!(iomaps, projection_print(recursion, row.content, recursion, child_context(ctx, row_ref)))
            else
                push!(iomaps, nothing)
            end
        end
        iomaps
    end)
    elements = CellVector(() -> begin
        nrows = length(table.rows)
        ncols = length(table.columns)
        ncells = length(table.cells)
        bw = p.border_width
        br, bg, bb, ba = p.border_r, p.border_g, p.border_b, p.border_a
        pad = table.padding
        iomaps = child_iomaps[]
        col_ims = col_header_iomaps[]
        row_ims = row_header_iomaps[]
        has_col_headers = !isempty(col_ims) && any(im -> im !== nothing, col_ims)
        has_row_headers = !isempty(row_ims) && any(im -> im !== nothing, row_ims)
        row_offset = has_col_headers ? 1 : 0
        col_offset = has_row_headers ? 1 : 0
        grid_rows = nrows + row_offset
        grid_cols = ncols + col_offset
        # compute column widths from content
        col_widths = fill(0, grid_cols)
        for c in 1:ncols
            gc = c + col_offset
            # column header
            if has_col_headers && c <= length(col_ims)
                col_widths[gc] = max(col_widths[gc], _output_w(col_ims[c]))
            end
            # data cells in this column
            for r in 1:nrows
                idx = (r - 1) * ncols + c
                if idx <= length(iomaps)
                    col_widths[gc] = max(col_widths[gc], _output_w(iomaps[idx]))
                end
            end
        end
        # row header column width
        if has_row_headers
            for r in 1:nrows
                if r <= length(row_ims)
                    col_widths[1] = max(col_widths[1], _output_w(row_ims[r]))
                end
            end
        end
        # add padding to widths
        for c in 1:grid_cols
            col_widths[c] += 2 * pad
        end
        # compute row heights from content
        row_heights = fill(0, grid_rows)
        for r in 1:nrows
            gr = r + row_offset
            # row header
            if has_row_headers && r <= length(row_ims)
                row_heights[gr] = max(row_heights[gr], _output_h(row_ims[r]))
            end
            # data cells in this row
            for c in 1:ncols
                idx = (r - 1) * ncols + c
                if idx <= length(iomaps)
                    row_heights[gr] = max(row_heights[gr], _output_h(iomaps[idx]))
                end
            end
        end
        # column header row height
        if has_col_headers
            for c in 1:ncols
                if c <= length(col_ims)
                    row_heights[1] = max(row_heights[1], _output_h(col_ims[c]))
                end
            end
        end
        # add padding to heights
        for r in 1:grid_rows
            row_heights[r] += 2 * pad
        end
        # cumulative positions (1-indexed, length grid_cols+1 / grid_rows+1)
        col_x = cumsum([0; col_widths])
        row_y = cumsum([0; row_heights])
        total_w = col_x[end]
        total_h = row_y[end]
        result = Any[]
        # horizontal lines (grid_rows+1 lines)
        for r in 1:grid_rows+1
            push!(result, GraphicsRect(0, row_y[r], total_w, bw, br, bg, bb, ba))
        end
        # vertical lines (grid_cols+1 lines)
        for c in 1:grid_cols+1
            push!(result, GraphicsRect(col_x[c], 0, bw, total_h, br, bg, bb, ba))
        end
        # column header contents
        if has_col_headers
            for idx in 1:ncols
                im = idx <= length(col_ims) ? col_ims[idx] : nothing
                if im !== nothing
                    gc = idx + col_offset
                    x = col_x[gc] + bw + pad
                    y = bw + pad
                    header_canvas = GraphicsCanvas(x, y,
                        CellVector(Cell[Cell(im.output)]),
                        layout_none, true)
                    push!(result, header_canvas)
                end
            end
        end
        # row header contents
        if has_row_headers
            for idx in 1:nrows
                im = idx <= length(row_ims) ? row_ims[idx] : nothing
                if im !== nothing
                    gr = idx + row_offset
                    x = bw + pad
                    y = row_y[gr] + bw + pad
                    header_canvas = GraphicsCanvas(x, y,
                        CellVector(Cell[Cell(im.output)]),
                        layout_none, true)
                    push!(result, header_canvas)
                end
            end
        end
        # cell contents
        for idx in 1:ncells
            row = div(idx - 1, ncols)
            col = mod(idx - 1, ncols)
            im = idx <= length(iomaps) ? iomaps[idx] : nothing
            if im !== nothing
                gc = col + 1 + col_offset
                gr = row + 1 + row_offset
                x = col_x[gc] + bw + pad
                y = row_y[gr] + bw + pad
                content_canvas = GraphicsCanvas(x, y,
                    CellVector(Cell[Cell(im.output)]),
                    layout_none, true)
                push!(result, content_canvas)
            end
        end
        result
    end)
    canvas = GraphicsCanvas(elements, layout_none)
    ChildrenIoMap(p, table, canvas, child_iomaps)
end

# ── Compound convenience constructor ────────────────────────────────────

function TableToGraphics()
    TypeDispatchingProjection(
        TableTable  => TableTableToGraphicsCanvas(),
        TableCell   => CopyingProjection(),
        TableRow    => CopyingProjection(),
        TableColumn => CopyingProjection(),
    )
end

end # module
