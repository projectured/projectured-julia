# Fragment of `FaultViewModule`.
#
# A decorator that draws the [`FaultLog`](FaultDocument.jl) as a panel over the
# content of a window. It is tier 2 of the report ladder: the place a person
# reads a fault that has no room in the document itself.
#
# **Printer** — it projects the wrapped `inner`, projects the log through the
# `content` chain (Syntax → Text → Graphics), and answers a canvas holding the
# inner output at the origin and the panel at a corner. The inner output keeps
# the origin, so a pixel coordinate means the same thing above and below this
# decorator.
#
# **The panel is not there while the log is empty.** An empty panel is noise on
# every screen of a program that is working, so the decorator costs a pixel only
# once something has failed.
#
# **Reader** — a pure pass-through. The panel is not a hit target, so a click on
# it reaches the content below.
#
# The log chain is printed one time. It stays up to date because
# [`FaultLogToSyntax`](FaultLogToSyntax.jl) derives its lines from `log.entries`
# inside a cell: an append invalidates the lines, and the text and graphics
# stages below re-derive from there.

# Extra width of the panel, in pixels. It covers the small difference between
# the measure the printer used and the text metrics of the backend that
# draws. Without it the last characters of the longest line sit on the border.
const _FAULT_WIDTH_SLACK = 8

"""
    make_fault_log_panel_syntax_projection(; theme = make_fault_log_panel_theme()) -> FaultLogToSyntax

A `FaultLogToSyntax` with the styles of `theme`: by default the light text of the
panel theme, for the dark background of the panel.
"""
make_fault_log_panel_syntax_projection(; theme = make_fault_log_panel_theme()) =
    make_fault_log_projection(; theme)

"""
    make_fault_log_content_projection(; syntax = FaultLogToSyntax(),
                                        measure::TextMeasure = FontFileMeasure())

The chain that renders a `FaultLog` down to graphics. `syntax` is its first
step. The default has the colors for a light background.
"""
make_fault_log_content_projection(; syntax = FaultLogToSyntax(),
                                    measure::TextMeasure = FontFileMeasure()) =
    ChainingProjection(syntax,
                       RecursiveProjection(SyntaxToText()),
                       TextToGraphics(measure = measure))

"""
    FaultLogOverlayProjection(; inner, log, theme = make_fault_log_panel_theme(),
                                content = …, anchor = :bottom_left,
                                margin, padding, radius, background)

Decorator over `inner` (a content pipeline whose output is a `GraphicsCanvas`)
that draws `log` in the corner that `anchor` names: `:top_right`, `:top_left`,
`:bottom_right` or `:bottom_left`. The default corner is the bottom left, which
is the one the gesture log panel does not use. `theme` gives the texts of the
log and the margin, the padding, the radius and the background of the panel; a
keyword of the same name sets one of them as it is.

Nothing is drawn while `log` is empty.

Wire it with one line at the root of a pipeline, and one more to fill the log:

    attach_fault_target!(editor.faults, log)
    projection = FaultLogOverlayProjection(inner = root, log = log)

The panel needs the size of the window to reach a right or a bottom corner. The
printer takes it from the available size of the printer context, which the
window level sets. Without one the panel stays at the top left.
"""
struct FaultLogOverlayProjection <: Projection
    inner::Any
    log::FaultLog
    content::Any
    anchor::Symbol
    margin::Int
    padding::Int
    radius::Int
    background::StyleColor
end

function FaultLogOverlayProjection(; inner, log::FaultLog,
                                     theme = make_fault_log_panel_theme(),
                                     content = make_fault_log_content_projection(
                                         syntax = make_fault_log_panel_syntax_projection(; theme)),
                                     anchor::Symbol = :bottom_left,
                                     margin::Integer = get_theme_value(theme, :panel_margin),
                                     padding::Integer = get_theme_value(theme, :panel_padding),
                                     radius::Integer = get_theme_value(theme, :panel_radius),
                                     background::StyleColor = get_theme_value(theme, :panel_background))
    anchor in (:top_right, :top_left, :bottom_right, :bottom_left) ||
        error("FaultLogOverlayProjection: unknown anchor :$anchor")
    FaultLogOverlayProjection(inner, log, content, anchor, Int(margin), Int(padding),
                              Int(radius), background)
end

@iomap struct FaultLogOverlayIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    log_iomap::Any
end

# ── Printer ──────────────────────────────────────────────────────────────────

function print_document(p::FaultLogOverlayProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    # The log gets a context of its own: the panel takes the space it needs and
    # must not inherit the layout space of the content.
    log_iomap = print_document(p.content, nothing, p.log, PrinterContext())

    inner_output = Cell(@computation _force_fault_cell(inner_iomap.output))
    log_output = Cell(@computation _force_fault_cell(log_iomap.output))

    body_width() = _fault_width(log_output[])
    body_height() = _fault_height(log_output[])
    panel_width() = body_width() + 2 * p.padding + _FAULT_WIDTH_SLACK
    panel_height() = body_height() + 2 * p.padding

    body = GraphicsCanvas(CellVector(Cell[log_output]); x = p.padding, y = p.padding)
    set_cell_computation!(getfield(body, :w), () -> Int32(body_width()))
    set_cell_computation!(getfield(body, :h), () -> Int32(body_height()))

    background = GraphicsRect(0, 0, 0, 0; color = p.background, radius = p.radius)
    set_cell_computation!(getfield(background, :w), () -> Int32(panel_width()))
    set_cell_computation!(getfield(background, :h), () -> Int32(panel_height()))

    panel = GraphicsCanvas(CellVector(Cell[Cell(background), Cell(body)]))
    set_cell_computation!(getfield(panel, :x), () -> Int32(_fault_panel_x(p, ctx, panel_width())))
    set_cell_computation!(getfield(panel, :y), () -> Int32(_fault_panel_y(p, ctx, panel_height())))
    set_cell_computation!(getfield(panel, :w), () -> Int32(panel_width()))
    set_cell_computation!(getfield(panel, :h), () -> Int32(panel_height()))

    # The panel joins the canvas only once something has failed. The read of
    # `log.entries` is what subscribes this list to the log, so the first fault
    # brings the panel in by itself.
    children = CellVector(@computation(
        length(p.log.entries) == 0 ? Any[inner_output[]] : Any[inner_output[], panel]))

    # The inner output keeps the origin, so the coordinates the reader sees are
    # the coordinates the inner pipeline printed.
    output = GraphicsCanvas(children)
    set_cell_computation!(getfield(output, :w), function ()
        length(p.log.entries) == 0 && return Int32(_fault_width(inner_output[]))
        Int32(max(_fault_width(inner_output[]), panel.x + panel_width()))
    end)
    set_cell_computation!(getfield(output, :h), function ()
        length(p.log.entries) == 0 && return Int32(_fault_height(inner_output[]))
        Int32(max(_fault_height(inner_output[]), panel.y + panel_height()))
    end)

    FaultLogOverlayIoMap(p, input, output, inner_iomap, log_iomap)
end

_force_fault_cell(value) = value isa Cell ? value[] : value

# The size of a printed document, for the documents that carry one. A projection
# whose output names no size contributes nothing to the size of the panel.
_fault_width(document) = hasproperty(document, :w) ? Int(document.w) : 0
_fault_height(document) = hasproperty(document, :h) ? Int(document.h) : 0

# The maximum of the range is the edge that the window gives the content. It is
# a `Cell`, so the panel follows a resize of the window.
_fault_available(size::Cell) = Int(size[])
_fault_available(::Nothing) = 0

_fault_panel_x(p::FaultLogOverlayProjection, ctx, width::Integer) =
    _is_fault_right(p.anchor) ?
        max(p.margin, _fault_available(ctx.maximum_width) - width - p.margin) :
        p.margin

_fault_panel_y(p::FaultLogOverlayProjection, ctx, height::Integer) =
    _is_fault_bottom(p.anchor) ?
        max(p.margin, _fault_available(ctx.maximum_height) - height - p.margin) :
        p.margin

_is_fault_right(anchor::Symbol) = anchor === :top_right || anchor === :bottom_right
_is_fault_bottom(anchor::Symbol) = anchor === :bottom_right || anchor === :bottom_left

# ── Reader (pass-through) ────────────────────────────────────────────────────

read_intent(p::FaultLogOverlayProjection, recursion, change::Intent,
            iomap::FaultLogOverlayIoMap) =
    read_intent(p.inner, recursion, change, iomap.inner_iomap)

read_intent(p::FaultLogOverlayProjection, iomap::FaultLogOverlayIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ────────────────────────────────────────────────────────
#
# The panel adds one canvas level around the inner output, and the inner output
# keeps the origin. A coordinate therefore needs no change.

map_reference_forward(p::FaultLogOverlayProjection,
                      iomap::FaultLogOverlayIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::FaultLogOverlayProjection,
                       iomap::FaultLogOverlayIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

# ── The one call that makes a program fault tolerant ─────────────────────────

"""
    make_fault_tolerant_projection(inner; log = FaultLog(), measure = …, anchor = …)
        -> (projection, log)

Wrap a root projection so a fault in it shows on the screen instead of ending
the program, and answer the log to attach to the editor.

Use it where a program composes its root projection and starts its editor. It is
the two-line form of what the guide spells out: a barrier around the whole
pipeline, and the panel over it.

    projection, log = make_fault_tolerant_projection(composed)
    editor = make_editor(document, projection; backend, fault_policy = FaultPolicy())
    attach_fault_target!(editor.faults, log)
    run_editor!(editor)

The barrier goes **inside** the panel, not outside it. A fault in the pipeline
must not take the panel that would have reported it, and a fault in the panel
itself is what the editor's own frame barrier is for.

This is the root barrier alone. A pipeline that wants a fault contained to one
node rather than to the whole window puts a `FaultCatchingProjection` at each of
its own steps as well; the guide says why every one of them needs a
`substitute`.
"""
function make_fault_tolerant_projection(inner;
                                        log::FaultLog = FaultLog(),
                                        measure::TextMeasure = FontFileMeasure(),
                                        anchor::Symbol = :bottom_left)
    guarded = FaultCatchingProjection(inner = inner, substitute = FaultToGraphics())
    projection = FaultLogOverlayProjection(
        inner = guarded, log = log,
        content = make_fault_log_content_projection(
            syntax = make_fault_log_panel_syntax_projection(), measure = measure),
        anchor = anchor)
    (projection, log)
end
