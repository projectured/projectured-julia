# Fragment of `TextModule`.
#
# The content of a text drawn as graphics: the runs of each line, laid out as
# `TextToGraphics` lays them out, and no caret. A view of the text draws its caret
# over this canvas (`TextViewToGraphicsCanvas`), so the lines of a text and the
# caret of a view are drawn by two projections.

"""
    TextBlockToGraphicsCanvas(; measure, theme = nothing, start_x = 0, start_y = 0,
                              line_spacing = SingleSpacing())

Draw the lines of a `TextBlock` as a `GraphicsCanvas`, with no caret and no band
under a selection: the text as content, which every view of it shares. The lines
are laid out as `TextToGraphics` lays them out: at the line spacing of the printer
context where it sets one, else at `line_spacing`, and inside the space that the
slot gives. A run of the colour `color_default` takes the colour of plain text of
`theme`, a `TextTheme`, scaled or not, or of the default theme.

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
    plain_color::StyleColor
end

TextBlockToGraphicsCanvas(; start_x::Int = 0, start_y::Int = 0, measure::TextMeasure,
                          line_spacing = SingleSpacing(), theme = nothing) =
    TextBlockToGraphicsCanvas(start_x, start_y, measure, line_spacing, _get_plain_text_color(theme))

"""
    TextBlockToGraphicsCanvasIoMap

IoMap for `TextBlockToGraphicsCanvas`: the line spacing of the print, the segments
of the drawn text with their characters and pixel places (`char_to_coord`), the
line groups and their cells, the places of the lines, the baseline of the first
line, the space around the text, the height that shows, and the font of a line
that has no font of its own.
"""
@iomap struct TextBlockToGraphicsCanvasIoMap
    projection::Any
    input::TextBlock
    output::GraphicsCanvas
    line_spacing::LineSpacing
    char_to_coord::Cell     # Cell{Vector{SegmentCoordinate}}
    first_baseline::Cell    # Cell{Union{Int,Nothing}}
    lines::Cell             # Cell{Vector} — the line groups (`_line_groups`)
    line_cells::Any         # L -> the cells of line group L
    space::NTuple{4, Int}   # the space around the text, `(left, top, right, bottom)`
    places::Any             # the places of the lines (`_TextPlaces`)
    visible_height::Any     # the height that shows (`get_visible_height`), or `nothing`
    block_font::Cell        # the font of a line with no font of its own
end

find_first_baseline(iomap::TextBlockToGraphicsCanvasIoMap) = unwrap_cell(iomap.first_baseline)

function print_document(p::TextBlockToGraphicsCanvas, recursion, text::TextBlock, ctx)
    text.elements isa ListNode && throw(ArgumentError(
        "TextBlockToGraphicsCanvas draws a text of a vector of lines; " *
        "a text whose lines are a lazy list prints with TextToGraphics"))
    spacing = _get_line_spacing(p, ctx)
    space = ctx === nothing ? (0, 0, 0, 0) : ctx.space
    lines = _print_text_lines(p, spacing, text, space)
    elements = CellVector(Cell[Cell(lines.stack), Cell(lines.ibeam), Cell(lines.span_shapes)])
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), lines.width, lines.height,
                            elements, layout_none, true, Cell(nothing))
    TextBlockToGraphicsCanvasIoMap(p, text, canvas, spacing, lines.char_to_coord, lines.first_baseline,
                                   lines.groups, lines.line_cells, space, lines.places,
                                   get_visible_height(ctx), lines.block_font)
end

map_reference_forward(p::TextBlockToGraphicsCanvas, iomap::TextBlockToGraphicsCanvasIoMap, reference) =
    _map_text_forward(p, iomap, reference)

# A point of the canvas maps to the caret nearest to it.
map_reference_backward(p::TextBlockToGraphicsCanvas, iomap::TextBlockToGraphicsCanvasIoMap, reference) =
    _map_text_backward(p, iomap, reference)

# Where the caret and the band of `selection`, a place in the text that `iomap`
# drew, are in the frame of its stack of lines: `(cursor = (x, y, height) or
# nothing, highlight = rows (x, y, width, height))`. It lays the line of the caret
# out as the print laid it out, so the caret stands where the glyph beside it is
# drawn.
_compute_selection_marks(iomap::TextBlockToGraphicsCanvasIoMap, selection) =
    _layout_overlay(iomap.projection, iomap.line_spacing, iomap.input, selection,
                    getfield(iomap, :block_font), iomap.places)
