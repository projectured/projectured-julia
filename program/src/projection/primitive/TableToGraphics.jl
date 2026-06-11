"""
    TableToGraphicsModule

Table → Graphics projection. Lays out a TableTable as a grid of
content-sized cells, drawing border rectangles and recursing into
each cell's content. Column widths and row heights are derived from
the `w`/`h` fields of each cell's projected `GraphicsCanvas`.

The projection also owns **whole cell / row / column / table selection**
(see `plan/pending/table-selection.md`). A whole-element selection is just a
path terminating at the element (`∅`); the projection — which is the one place
that has the grid geometry — turns a 1-D axis handle (`.rows[r]∅` /
`.columns[c]∅`) into a 2-D highlight band, exactly as `SyntaxNodeToText` turns a
nested `∅` child selection into a `TextRectangularReference` box. The grid
geometry is persisted in the iomap so the gesture-aware reader can hit-test
pointer clicks and resolve keyboard navigation against the live table.
"""
module TableToGraphicsModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change
import ..TableModule: TableDocument, TableTable, TableCell, TableRow, TableColumn
import ..GraphicsModule: GraphicsDocument, GraphicsCanvas, GraphicsRect, layout_none
import ..ColorModule: StyleColor, color_default, color_solarized_gray
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference, RangeReference, ReferencePath, EmptyReferencePath, append_reference, is_element_reference
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..OperationModule: ReplaceSelectionOperation
import ..MouseModule: MousePress
import ..KeyboardModule: KeyDown
import ..ModifiersModule: Modifiers
export TableTableToGraphicsCanvas, TableToGraphics, TableTableToGraphicsCanvasIoMap

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

# Translucent selection accent (same blue the syntax-text highlight uses).
const _HL_R = 0x88
const _HL_G = 0xbb
const _HL_B = 0xee
const _HL_A = 0x40
const _HL_RADIUS = 4

# ── Grid geometry ───────────────────────────────────────────────────────
# The cumulative pixel layout of the grid, persisted in the iomap. The reader
# uses it to hit-test pointer clicks; the highlight layer uses it to compute
# band extents. `col_x` / `row_y` are cumulative left/top edges in *grid*
# coordinates (header strips occupy grid row/column 1 when present), each of
# length grid_cols+1 / grid_rows+1 so that `col_x[gc+1]` is the right edge.
struct TableGeometry
    nrows::Int
    ncols::Int
    row_offset::Int          # 1 when a column-header strip occupies grid row 1
    col_offset::Int          # 1 when a row-header strip occupies grid column 1
    grid_rows::Int
    grid_cols::Int
    has_row_headers::Bool
    has_col_headers::Bool
    col_x::Vector{Int}
    row_y::Vector{Int}
    total_w::Int
    total_h::Int
    bw::Int                  # border width
    pad::Int                 # inner padding
end

# ── IoMap ───────────────────────────────────────────────────────────────
# Like ChildrenIoMap (the content iomaps live in `child_iomaps`) plus the
# persisted grid `geometry`, the table analog of TextToGraphics's char_to_coord.
struct TableTableToGraphicsCanvasIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
    geometry::Cell
end

# A GraphicsCanvas is not a selectable container, so we never forward-project a
# selection onto it — the table draws its band in place during print (just as
# SyntaxNodeToText computes its box in place). The in-cell cursor continues to
# be forward-projected by the cell's own sub-pipeline.
function map_reference_forward(::TableTableToGraphicsCanvas, iomap, reference)
    return nothing
end

function map_reference_backward(::TableTableToGraphicsCanvas, iomap, reference)
    return nothing
end

# Helper: read w/h from an iomap's output GraphicsCanvas, defaulting to 0
_output_w(im) = im === nothing ? 0 : (let o = im.output; o isa GraphicsCanvas ? Int(o.w) : 0 end)
_output_h(im) = im === nothing ? 0 : (let o = im.output; o isa GraphicsCanvas ? Int(o.h) : 0 end)

# Compute the grid geometry from the table dimensions and the projected
# content / header sizes. Mirrors the width/height accumulation the element
# builder used to do inline.
function _compute_geometry(table, p::TableTableToGraphicsCanvas, iomaps, col_ims, row_ims)
    nrows = length(table.rows)
    ncols = length(table.columns)
    pad = table.padding
    bw = p.border_width
    has_col_headers = !isempty(col_ims) && any(im -> im !== nothing, col_ims)
    has_row_headers = !isempty(row_ims) && any(im -> im !== nothing, row_ims)
    row_offset = has_col_headers ? 1 : 0
    col_offset = has_row_headers ? 1 : 0
    grid_rows = nrows + row_offset
    grid_cols = ncols + col_offset
    # column widths from content
    col_widths = fill(0, grid_cols)
    for c in 1:ncols
        gc = c + col_offset
        if has_col_headers && c <= length(col_ims)
            col_widths[gc] = max(col_widths[gc], _output_w(col_ims[c]))
        end
        for r in 1:nrows
            idx = (r - 1) * ncols + c
            if idx <= length(iomaps)
                col_widths[gc] = max(col_widths[gc], _output_w(iomaps[idx]))
            end
        end
    end
    if has_row_headers
        for r in 1:nrows
            if r <= length(row_ims)
                col_widths[1] = max(col_widths[1], _output_w(row_ims[r]))
            end
        end
    end
    for c in 1:grid_cols
        col_widths[c] += 2 * pad
    end
    # row heights from content
    row_heights = fill(0, grid_rows)
    for r in 1:nrows
        gr = r + row_offset
        if has_row_headers && r <= length(row_ims)
            row_heights[gr] = max(row_heights[gr], _output_h(row_ims[r]))
        end
        for c in 1:ncols
            idx = (r - 1) * ncols + c
            if idx <= length(iomaps)
                row_heights[gr] = max(row_heights[gr], _output_h(iomaps[idx]))
            end
        end
    end
    if has_col_headers
        for c in 1:ncols
            if c <= length(col_ims)
                row_heights[1] = max(row_heights[1], _output_h(col_ims[c]))
            end
        end
    end
    for r in 1:grid_rows
        row_heights[r] += 2 * pad
    end
    col_x = Vector{Int}(cumsum([0; col_widths]))
    row_y = Vector{Int}(cumsum([0; row_heights]))
    TableGeometry(nrows, ncols, row_offset, col_offset, grid_rows, grid_cols,
                  has_row_headers, has_col_headers, col_x, row_y,
                  col_x[end], row_y[end], bw, pad)
end

# Pixel rect (x, y, w, h) of a data cell, a row band (full width), a column
# band (full height), or the whole table, in table-canvas coordinates.
function _cell_rect(geom::TableGeometry, r::Int, c::Int)
    gc = c + geom.col_offset
    gr = r + geom.row_offset
    (geom.col_x[gc], geom.row_y[gr], geom.col_x[gc+1] - geom.col_x[gc], geom.row_y[gr+1] - geom.row_y[gr])
end

function _row_band_rect(geom::TableGeometry, r::Int)
    gr = r + geom.row_offset
    (0, geom.row_y[gr], geom.total_w, geom.row_y[gr+1] - geom.row_y[gr])
end

function _col_band_rect(geom::TableGeometry, c::Int)
    gc = c + geom.col_offset
    (geom.col_x[gc], 0, geom.col_x[gc+1] - geom.col_x[gc], geom.total_h)
end

_table_rect(geom::TableGeometry) = (0, 0, geom.total_w, geom.total_h)

# ── Selection-shape recognition ─────────────────────────────────────────
# Decode a table-domain selection path into the whole-element shape it names,
# or `nothing` when it is an in-cell cursor (`.cells[idx].content.…`) or
# unrecognised. The flat cell index ↔ (r,c) conversion is the only place that
# knows the row-major layout (kept isolated for a future TabularGrid migration).

# `.<field>[index]∅` → (field_name, 1-based index), else nothing.
function _field_element_terminal(sel)
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference || return nothing
    t = sel.tail
    t isa ConcreteReferencePath || return nothing
    r = t.head
    (r isa RangeReference && is_element_reference(r)) || return nothing
    t.tail isa EmptyReferencePath || return nothing
    (h.name, r.start + 1)
end

# Leading `.cells[idx]` index (whole cell *or* an in-cell cursor), else nothing.
function _selection_cell_index(sel)
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    (h isa FieldReference && h.name == "cells") || return nothing
    t = sel.tail
    t isa ConcreteReferencePath || return nothing
    r = t.head
    (r isa RangeReference && is_element_reference(r)) || return nothing
    r.start + 1
end

# (:table,_,_) | (:row,r,_) | (:col,c,_) | (:cell,r,c) | nothing
function _selection_shape(sel, geom::TableGeometry)
    sel isa EmptyReferencePath && return (:table, 0, 0)
    fe = _field_element_terminal(sel)
    fe === nothing && return nothing
    field, idx = fe
    if field == "rows"
        (1 <= idx <= geom.nrows) || return nothing
        return (:row, idx, 0)
    elseif field == "columns"
        (1 <= idx <= geom.ncols) || return nothing
        return (:col, idx, 0)
    elseif field == "cells"
        (1 <= idx <= geom.nrows * geom.ncols) || return nothing
        r = div(idx - 1, geom.ncols) + 1
        c = mod(idx - 1, geom.ncols) + 1
        return (:cell, r, c)
    end
    return nothing
end

# Translucent highlight rect(s) for the current selection shape, drawn behind
# the grid and content. An in-cell cursor (`.cells[idx].content.…`) yields none
# here — the cursor is drawn by the cell's own sub-pipeline.
function _highlight_rects(sel, geom::TableGeometry)
    shape = _selection_shape(sel, geom)
    shape === nothing && return GraphicsRect[]
    kind = shape[1]
    rect = if kind === :table
        _table_rect(geom)
    elseif kind === :row
        _row_band_rect(geom, shape[2])
    elseif kind === :col
        _col_band_rect(geom, shape[2])
    elseif kind === :cell
        _cell_rect(geom, shape[2], shape[3])
    else
        return GraphicsRect[]
    end
    x, y, w, h = rect
    GraphicsRect[GraphicsRect(x, y, w, h, _HL_R, _HL_G, _HL_B, _HL_A, _HL_RADIUS)]
end

# ── Printing ────────────────────────────────────────────────────────────

function projection_print(p::TableTableToGraphicsCanvas, recursion, table::TableTable, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> begin
        ncells = length(table.cells)
        iomaps = []
        for idx in 1:ncells
            cell = table.cells[idx]
            if cell isa TableCell && cell.content !== nothing
                content_ref = @reference ^(reference).cells[idx].content
                push!(iomaps, projection_print(recursion, recursion, cell.content, child_context(ctx, content_ref)))
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
                push!(iomaps, projection_print(recursion, recursion, col.content, child_context(ctx, col_ref)))
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
                push!(iomaps, projection_print(recursion, recursion, row.content, child_context(ctx, row_ref)))
            else
                push!(iomaps, nothing)
            end
        end
        iomaps
    end)
    geometry = Cell(() -> _compute_geometry(table, p, child_iomaps[], col_header_iomaps[], row_header_iomaps[]))
    elements = CellVector(() -> begin
        geom = geometry[]
        iomaps = child_iomaps[]
        col_ims = col_header_iomaps[]
        row_ims = row_header_iomaps[]
        bw = geom.bw
        pad = geom.pad
        br, bg, bb, ba = p.border_r, p.border_g, p.border_b, p.border_a
        col_x = geom.col_x
        row_y = geom.row_y
        total_w = geom.total_w
        total_h = geom.total_h
        nrows = geom.nrows
        ncols = geom.ncols
        grid_rows = geom.grid_rows
        grid_cols = geom.grid_cols
        row_offset = geom.row_offset
        col_offset = geom.col_offset
        has_col_headers = geom.has_col_headers
        has_row_headers = geom.has_row_headers
        ncells = length(iomaps)
        result = Any[]
        # selection highlight, behind everything (glyphs/lines stay on top)
        for hr in _highlight_rects(table.selection, geom)
            push!(result, hr)
        end
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
                    push!(result, GraphicsCanvas(x, y,
                        CellVector(Cell[Cell(im.output)]), layout_none, true))
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
                    push!(result, GraphicsCanvas(x, y,
                        CellVector(Cell[Cell(im.output)]), layout_none, true))
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
                push!(result, GraphicsCanvas(x, y,
                    CellVector(Cell[Cell(im.output)]), layout_none, true))
            end
        end
        result
    end)
    canvas = GraphicsCanvas(elements, layout_none)
    TableTableToGraphicsCanvasIoMap(p, table, canvas, child_iomaps, geometry)
end

# ── Reading (gestures) ──────────────────────────────────────────────────
# Gesture-aware 4-arg reader, parallel to SyntaxNodeToText's. Unlike the
# syntax layer (which sits mid-pipeline and sees an already-mapped operation),
# the table is the *outer* projection, so it sees the raw gesture and both
# hit-tests and routes from here, where it owns the grid geometry and the live
# TableTable. Left clicks resolve entirely here (header/corner pick row/column/
# table, Alt+click promotes a data cell to a whole-cell pick, a plain click is
# routed into the cell's own content with translated coordinates). Keyboard
# navigation (Alt+arrows, Ctrl+Alt+Home, Shift/Ctrl+Space, Enter) is recognised
# and resolved against the live table — no courier operation needed, exactly as
# the syntax plan deleted its TreeNavigateOperation.
function projection_read(p::TableTableToGraphicsCanvas, recursion, change::Change, iomap::TableTableToGraphicsCanvasIoMap)
    g = change.gesture
    if change.operation === nothing && g isa MousePress && g.button === :left
        # Left clicks are resolved here in full; never fall through to the
        # untranslated per-child routing below.
        return Change(g, _mouse_select(iomap, g))
    end
    if change.operation === nothing && g isa KeyDown
        op = _key_navigate(iomap, g, iomap.geometry[])
        op === nothing || return Change(g, op)
    end
    # Fall through: plain editing keys route into the active cell's content as
    # before; an already-produced operation passes straight through.
    payload = change.operation === nothing ? g : change.operation
    return Change(g, projection_read(p, iomap, payload))
end

# Resolve a left click into a selection operation (or nothing).
function _mouse_select(iomap::TableTableToGraphicsCanvasIoMap, g::MousePress)
    geom = iomap.geometry[]
    hit = _hit_test(geom, g.x, g.y)
    kind = hit[1]
    if kind === :corner
        return ReplaceSelectionOperation(EmptyReferencePath())
    elseif kind === :row
        r = hit[2]
        return ReplaceSelectionOperation(@reference rows[r])
    elseif kind === :col
        c = hit[2]
        return ReplaceSelectionOperation(@reference columns[c])
    elseif kind === :cell
        r, c = hit[2], hit[3]
        idx = (r - 1) * geom.ncols + c
        if g.modifiers.alt
            return ReplaceSelectionOperation(@reference cells[idx])
        else
            return _route_cell_click(iomap, geom, r, c, idx, g)
        end
    end
    return nothing
end

# Classify a click point: :corner | (:row,r) | (:col,c) | (:cell,r,c) | :outside.
# Header / corner results only arise where the table actually renders those
# strips; otherwise that pixel region doesn't exist and the click lands on a
# data cell.
function _hit_test(geom::TableGeometry, x::Int, y::Int)
    (0 <= x < geom.total_w && 0 <= y < geom.total_h) || return (:outside, 0, 0)
    gc = 0
    for c in 1:geom.grid_cols
        if geom.col_x[c] <= x < geom.col_x[c+1]
            gc = c
            break
        end
    end
    gr = 0
    for r in 1:geom.grid_rows
        if geom.row_y[r] <= y < geom.row_y[r+1]
            gr = r
            break
        end
    end
    (gc == 0 || gr == 0) && return (:outside, 0, 0)
    header_col = geom.has_row_headers && gc == 1
    header_row = geom.has_col_headers && gr == 1
    if header_col && header_row
        return (:corner, 0, 0)
    elseif header_row
        return (:col, gc - geom.col_offset, 0)
    elseif header_col
        return (:row, gr - geom.row_offset, 0)
    else
        return (:cell, gr - geom.row_offset, gc - geom.col_offset)
    end
end

# Route a plain click into a data cell's content sub-pipeline with the click
# translated into the cell's local coordinate frame, then wrap the operation
# the content reader returns back into the table domain.
function _route_cell_click(iomap::TableTableToGraphicsCanvasIoMap, geom::TableGeometry,
                           r::Int, c::Int, idx::Int, g::MousePress)
    iomaps = iomap.child_iomaps[]
    (1 <= idx <= length(iomaps)) || return nothing
    child_im = iomaps[idx]
    child_im === nothing && return nothing
    gc = c + geom.col_offset
    gr = r + geom.row_offset
    cell_x = geom.col_x[gc] + geom.bw + geom.pad
    cell_y = geom.row_y[gr] + geom.bw + geom.pad
    canvas = child_im.output
    ox = canvas isa GraphicsCanvas ? Int(canvas.x) : 0
    oy = canvas isa GraphicsCanvas ? Int(canvas.y) : 0
    local_evt = MousePress(g.button, g.x - cell_x - ox, g.y - cell_y - oy, g.modifiers)
    op = projection_read(child_im.projection, child_im, local_evt)
    op isa ReplaceSelectionOperation || return nothing
    ReplaceSelectionOperation(@reference cells[idx].content.^(op.path))
end

# ── Reading (keyboard navigation) ───────────────────────────────────────
# Resolve a navigation chord against the live table and its selection. Returns
# a ReplaceSelectionOperation or nothing (decline → fall through to per-cell
# editing). Plain unmodified arrows drive the grid only when a whole cell / row
# / column is already selected; on an in-cell character cursor they are *not*
# consumed here, so they keep editing cell text via the existing per-child
# routing.
function _key_navigate(iomap::TableTableToGraphicsCanvasIoMap, evt::KeyDown, geom::TableGeometry)
    nrows, ncols = geom.nrows, geom.ncols
    (nrows == 0 || ncols == 0) && return nothing
    sel = iomap.input.selection

    # Ctrl+Alt+Home → whole table
    if evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt
        return ReplaceSelectionOperation(EmptyReferencePath())
    end

    shape = _selection_shape(sel, geom)
    cell_idx = _selection_cell_index(sel)

    # Enter: drop a row/column selection to its first cell, or a whole cell into
    # its content (a real character cursor obtained from the content pipeline).
    if evt.key === :return
        if shape !== nothing && shape[1] === :row
            idx = (shape[2] - 1) * ncols + 1
            return ReplaceSelectionOperation(@reference cells[idx])
        elseif shape !== nothing && shape[1] === :col
            idx = shape[2]
            return ReplaceSelectionOperation(@reference cells[idx])
        elseif cell_idx !== nothing
            return _enter_cell_content(iomap, cell_idx)
        end
        return nothing
    end

    # Shift+Space / Ctrl+Space widen the active cell to its row / column.
    if evt.key === :space && (evt.modifiers.shift ⊻ evt.modifiers.ctrl)
        cell_idx === nothing && return nothing
        r = div(cell_idx - 1, ncols) + 1
        c = mod(cell_idx - 1, ncols) + 1
        if evt.modifiers.shift
            return ReplaceSelectionOperation(@reference rows[r])
        else
            return ReplaceSelectionOperation(@reference columns[c])
        end
    end

    # Arrow grid navigation. Once a whole cell / row / column is already
    # selected (structural mode) plain unmodified arrows drive the grid — no Alt
    # needed. Alt is only required to *enter* grid mode from a character cursor
    # inside cell text (it promotes the cursor to its whole cell, then moves);
    # without it a plain arrow on an in-cell cursor keeps editing the text.
    # Whole row / column step along their axis or narrow to a cell; a whole cell
    # (or an Alt-promoted cursor) moves one step with edge clamping.
    if (evt.modifiers.alt || shape !== nothing) && evt.key in (:up, :down, :left, :right)
        if shape !== nothing && shape[1] === :row
            r = shape[2]
            if evt.key === :up
                return ReplaceSelectionOperation(@reference rows[max(1, r - 1)])
            elseif evt.key === :down
                return ReplaceSelectionOperation(@reference rows[min(nrows, r + 1)])
            elseif evt.key === :right
                return ReplaceSelectionOperation(@reference cells[(r - 1) * ncols + 1])
            else  # :left
                return nothing
            end
        elseif shape !== nothing && shape[1] === :col
            c = shape[2]
            if evt.key === :left
                return ReplaceSelectionOperation(@reference columns[max(1, c - 1)])
            elseif evt.key === :right
                return ReplaceSelectionOperation(@reference columns[min(ncols, c + 1)])
            elseif evt.key === :down
                return ReplaceSelectionOperation(@reference cells[c])
            else  # :up
                return nothing
            end
        else
            cell_idx === nothing && return nothing
            r = div(cell_idx - 1, ncols) + 1
            c = mod(cell_idx - 1, ncols) + 1
            if evt.key === :up
                r = max(1, r - 1)
            elseif evt.key === :down
                r = min(nrows, r + 1)
            elseif evt.key === :left
                c = max(1, c - 1)
            elseif evt.key === :right
                c = min(ncols, c + 1)
            end
            return ReplaceSelectionOperation(@reference cells[(r - 1) * ncols + c])
        end
    end

    return nothing
end

# Place a character cursor at the start of a cell's content by asking the
# content pipeline where Ctrl+Home lands, then wrap it into the table domain.
function _enter_cell_content(iomap::TableTableToGraphicsCanvasIoMap, idx::Int)
    iomaps = iomap.child_iomaps[]
    (1 <= idx <= length(iomaps)) || return nothing
    child_im = iomaps[idx]
    child_im === nothing && return nothing
    op = projection_read(child_im.projection, child_im, KeyDown(:home, Modifiers(ctrl=true)))
    op isa ReplaceSelectionOperation || return nothing
    ReplaceSelectionOperation(@reference cells[idx].content.^(op.path))
end

# ── Per-child fall-through (plain editing keys) ─────────────────────────
# Dispatch a non-navigation event to every cell's content reader; the active
# cell (the one whose content carries the selection) is the one that answers.
# Mirrors the original table routing and is reached only after the gesture
# reader above has declined.
function projection_read(::TableTableToGraphicsCanvas, iomap::TableTableToGraphicsCanvasIoMap, event)
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
