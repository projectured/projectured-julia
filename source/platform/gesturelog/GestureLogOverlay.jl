# Fragment of `GestureLogModule`.
#
# A decorator that draws the [`GestureLog`](GestureLogDocument.jl) as a panel over the
# content of a window.
#
# **Printer** — it projects the wrapped `inner`, projects the log through the
# `content` chain (Syntax → Text → Graphics), and returns a canvas with two
# elements: the inner output at the origin, and the panel at a corner. The inner
# output keeps the origin, so a pixel coordinate means the same thing above and
# below this decorator.
#
# **Reader** — a pure pass-through. The panel is not a hit target, so a click on
# the panel reaches the content below it.
#
# The log chain is printed one time. It stays up to date because
# [`GestureLogToSyntax`](GestureLogToSyntax.jl) derives its lines from
# `log.entries` inside a cell: an append invalidates the lines, and the text and
# graphics stages below re-derive from there.
# Extra width of the panel, in pixels. See `panel_width` below.
const _WIDTH_SLACK = 8

"""
    make_gesture_log_panel_syntax_projection(; operation_width = typemax(Int),
                                               theme = make_gesture_log_panel_theme()) -> GestureLogToSyntax

A `GestureLogToSyntax` with the styles of `theme`: by default the light text of
the panel theme, for the dark background of the panel. `operation_width` is the
most characters of an operation that a line shows.
"""
make_gesture_log_panel_syntax_projection(; operation_width::Integer = typemax(Int),
                                           theme = make_gesture_log_panel_theme()) =
    make_gesture_log_projection(; theme, operation_width)

"""
    make_gesture_log_content_projection(; measure::TextMeasure = FontFileMeasure(),
                                          operation_width = typemax(Int),
                                          theme = make_gesture_log_panel_theme())

The chain that renders a `GestureLog` down to graphics, with the texts of `theme`,
by default the panel theme. `operation_width` limits the operation of a line, and
so the width of the panel, which follows its longest line.
"""
make_gesture_log_content_projection(; measure::TextMeasure = FontFileMeasure(),
                                      operation_width::Integer = typemax(Int),
                                      theme = make_gesture_log_panel_theme()) =
    ChainingProjection(make_gesture_log_panel_syntax_projection(; operation_width, theme),
                       RecursiveProjection(SyntaxToText()),
                       TextToGraphics(measure = measure))

"""
    GestureLogOverlayProjection(; inner, log, theme = make_gesture_log_panel_theme(),
                                  content = …, anchor = :top_right,
                                  margin, padding, radius, background)

Decorator over `inner` (a content pipeline whose output is a `GraphicsCanvas`)
that draws `log` in the corner that `anchor` names: `:top_right`, `:top_left`,
`:bottom_right` or `:bottom_left`. `margin` is the distance from the edges of
the window, `padding` the distance between the panel border and the text.
`theme` gives the texts of the log and the margin, the padding, the radius and
the background of the panel; a keyword of the same name sets one of them as it
is.

The panel needs the size of the window to reach a right or a bottom corner. The
printer takes it from the available size of the printer context, which the
window level sets. Without an available size the panel stays at the top left
corner.
"""
struct GestureLogOverlayProjection <: Projection
    inner::Any
    log::GestureLog
    content::Any
    anchor::Symbol
    margin::Int
    padding::Int
    radius::Int
    background::StyleColor
end

function GestureLogOverlayProjection(; inner, log::GestureLog,
                                       theme = make_gesture_log_panel_theme(),
                                       content = make_gesture_log_content_projection(; theme),
                                       anchor::Symbol = :top_right,
                                       margin::Integer = get_theme_value(theme, :panel_margin),
                                       padding::Integer = get_theme_value(theme, :panel_padding),
                                       radius::Integer = get_theme_value(theme, :panel_radius),
                                       background::StyleColor = get_theme_value(theme, :panel_background))
    anchor in (:top_right, :top_left, :bottom_right, :bottom_left) ||
        error("GestureLogOverlayProjection: unknown anchor :$anchor")
    GestureLogOverlayProjection(inner, log, content, anchor, Int(margin), Int(padding),
                                Int(radius), background)
end

@iomap struct GestureLogOverlayIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    log_iomap::Any
end

# ── Printer ────────────────────────────────────────────────────────────────

function print_document(p::GestureLogOverlayProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    # The log gets a context of its own: the panel takes the space it needs and
    # must not inherit the layout space of the content.
    log_iomap = print_document(p.content, nothing, p.log, PrinterContext())

    inner_output = Cell(@computation _force(inner_iomap.output))
    log_output = Cell(@computation _force(log_iomap.output))

    body_width() = _width(log_output[])
    body_height() = _height(log_output[])
    # The slack covers the small difference between the measure that the
    # printer used and the text metrics of the backend that draws. Without
    # it the last characters of the longest line sit on the panel border.
    panel_width() = body_width() + 2 * p.padding + _WIDTH_SLACK
    panel_height() = body_height() + 2 * p.padding

    # The body sits inside the panel, one padding from the corner of the panel.
    body = GraphicsCanvas(CellVector(Cell[log_output]); x = p.padding, y = p.padding)
    set_cell_computation!(getfield(body, :w), () -> Int32(body_width()))
    set_cell_computation!(getfield(body, :h), () -> Int32(body_height()))

    background = GraphicsRect(0, 0, 0, 0; color = p.background, radius = p.radius)
    set_cell_computation!(getfield(background, :w), () -> Int32(panel_width()))
    set_cell_computation!(getfield(background, :h), () -> Int32(panel_height()))

    panel = GraphicsCanvas(CellVector(Cell[Cell(background), Cell(body)]))
    set_cell_computation!(getfield(panel, :x),
                          () -> Int32(_panel_x(p, ctx, panel_width())))
    set_cell_computation!(getfield(panel, :y),
                          () -> Int32(_panel_y(p, ctx, panel_height())))
    set_cell_computation!(getfield(panel, :w), () -> Int32(panel_width()))
    set_cell_computation!(getfield(panel, :h), () -> Int32(panel_height()))

    # The inner output keeps the origin, so the coordinates the reader sees are
    # the coordinates the inner pipeline printed.
    output = GraphicsCanvas(CellVector(Cell[inner_output, Cell(panel)]))
    set_cell_computation!(getfield(output, :w),
                       () -> Int32(max(_width(inner_output[]), panel.x + panel_width())))
    set_cell_computation!(getfield(output, :h),
                       () -> Int32(max(_height(inner_output[]), panel.y + panel_height())))

    GestureLogOverlayIoMap(p, input, output, inner_iomap, log_iomap)
end

_force(value) = value isa Cell ? value[] : value

# The size of a printed document, for the documents that carry one. A projection
# whose output names no size contributes nothing to the size of the panel.
_width(document) = hasproperty(document, :w) ? Int(document.w) : 0
_height(document) = hasproperty(document, :h) ? Int(document.h) : 0

# The maximum of the range is the edge that the window gives the content. It is
# a `Cell`, so the panel follows a resize of the window.
_available(size::Cell) = Int(size[])
_available(::Nothing) = 0

function _panel_x(p::GestureLogOverlayProjection, ctx, width::Integer)
    return _is_right(p.anchor) ?
        max(p.margin, _available(ctx.maximum_width) - width - p.margin) :
        p.margin
end

function _panel_y(p::GestureLogOverlayProjection, ctx, height::Integer)
    return _is_bottom(p.anchor) ?
        max(p.margin, _available(ctx.maximum_height) - height - p.margin) :
        p.margin
end

_is_right(anchor::Symbol) = anchor === :top_right || anchor === :bottom_right
_is_bottom(anchor::Symbol) = anchor === :bottom_right || anchor === :bottom_left

# ── Reader (pass-through) ──────────────────────────────────────────────────

read_intent(p::GestureLogOverlayProjection, recursion, change::Intent,
            iomap::GestureLogOverlayIoMap) =
    read_intent(p.inner, recursion, change, iomap.inner_iomap)

read_intent(p::GestureLogOverlayProjection, iomap::GestureLogOverlayIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ──────────────────────────────────────────────────────
#
# The panel adds one canvas level around the inner output, and the inner output
# keeps the origin. A coordinate therefore needs no change. A structural
# graphics path is not mapped through this seam today: `TextToGraphics` and
# `WidgetToGraphics` both answer `nothing` for a graphics reference, so there is
# no path to lengthen.

map_reference_forward(p::GestureLogOverlayProjection,
                      iomap::GestureLogOverlayIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::GestureLogOverlayProjection,
                       iomap::GestureLogOverlayIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)
