# Fragment of `TextModule`.
#
# The content of a text drawn as graphics: the runs of each line, laid out as
# `TextToGraphics` lays them out, and no caret. A view of the text draws its caret
# over this canvas (`TextViewToGraphicsCanvas`), so the lines of a text and the
# caret of a view are drawn by two projections.

"""
    TextBlockToGraphicsCanvas(; measure, start_x = 0, start_y = 0,
                              line_spacing = SingleSpacing())

Draw the lines of a `TextBlock` as a `GraphicsCanvas`, with no caret and no band
under a selection: the text as content, which every view of it shares. The lines
are laid out as `TextToGraphics` lays them out, and a container sets their spacing
with the property `:line_spacing` of the printer context in the same way.

The IO map answers where a place of the text is drawn: its forward map gives the
text node and the characters of a caret or a range, and its backward map gives the
caret at a point. A view asks it for the caret and the band of its own selection
(`_compute_selection_marks`). A text whose lines are a lazy list prints with
`TextToGraphics`.
"""
@projection UntrackedCell struct TextBlockToGraphicsCanvas
    start_x::Int
    start_y::Int
    measure::TextMeasure
    line_spacing::LineSpacing
end

TextBlockToGraphicsCanvas(; start_x::Int = 0, start_y::Int = 0, measure::TextMeasure,
                          line_spacing = SingleSpacing()) =
    TextBlockToGraphicsCanvas(start_x, start_y, measure, line_spacing)

"""
    TextBlockToGraphicsCanvasIoMap

IoMap for `TextBlockToGraphicsCanvas`: the segments of the drawn text with their
characters and pixel places (`char_to_coord`), the line groups and their cells, the
baseline of the first line, and the font of a line that has no font of its own.
"""
@iomap struct TextBlockToGraphicsCanvasIoMap
    projection::Any
    input::TextBlock
    output::GraphicsCanvas
    char_to_coord::Cell     # Cell{Vector{SegmentCoordinate}}
    first_baseline::Cell    # Cell{Union{Int,Nothing}}
    lines::Cell             # Cell{Vector} — the line groups (`_line_groups`)
    line_cells::Any         # L -> the cells of line group L
    block_font::Cell        # the font of a line with no font of its own
end

find_first_baseline(iomap::TextBlockToGraphicsCanvasIoMap) = unwrap_cell(iomap.first_baseline)

# `p` at the line spacing `spacing`, with the same cells for every other field.
_with_line_spacing(p::TextBlockToGraphicsCanvas, spacing::LineSpacing) =
    TextBlockToGraphicsCanvas(getfield(p, :start_x), getfield(p, :start_y), getfield(p, :measure), spacing)

function print_document(p::TextBlockToGraphicsCanvas, recursion, text::TextBlock, ctx)
    spacing = ctx === nothing ? nothing : get_property(ctx, :line_spacing, nothing)
    spacing === nothing || (p = _with_line_spacing(p, spacing))
    text.elements isa ListNode && throw(ArgumentError(
        "TextBlockToGraphicsCanvas draws a text of a vector of lines; " *
        "a text whose lines are a lazy list prints with TextToGraphics"))
    block_font = Cell(@computation _block_font(text))
    lines = _print_text_lines(p, text, block_font)
    elements = CellVector(Cell[Cell(lines.stack), Cell(lines.ibeam), Cell(lines.span_shapes)])
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), lines.width, lines.height,
                            elements, layout_none, true, Cell(nothing))
    TextBlockToGraphicsCanvasIoMap(p, text, canvas, lines.char_to_coord, lines.first_baseline,
                                   lines.groups, lines.line_cells, block_font)
end

map_reference_forward(p::TextBlockToGraphicsCanvas, iomap::TextBlockToGraphicsCanvasIoMap, reference) =
    _map_text_forward(p, iomap, reference)

# A point of the canvas maps to the caret nearest to it.
function map_reference_backward(p::TextBlockToGraphicsCanvas, iomap::TextBlockToGraphicsCanvasIoMap, reference)
    point = find_reference_point(reference)
    point === nothing ? nothing : _find_caret_at_point(p, iomap, point.x, point.y)
end

# Where the caret and the band of `selection`, a place in the text that `iomap`
# drew, are in the frame of its canvas: `(cursor = (x, y, height) or nothing,
# highlight = rows (x, y, width, height))`. It lays the lines out as the print laid
# them out, so the caret stands where the glyph beside it is drawn.
_compute_selection_marks(iomap::TextBlockToGraphicsCanvasIoMap, selection) =
    _layout_overlay(iomap.projection, iomap.input, selection, getfield(iomap, :block_font))
