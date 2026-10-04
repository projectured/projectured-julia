# Fragment of `GestureHelpModule`.
#
# The decorator that opens the **command palette** over a content pipeline, modelled
# on [`GestureHelpDecoratorProjection`](GestureHelpDecorator.jl).
#
# **Printer** — the inner output, with the palette drawn over it. The output is
# always one wrapping `GraphicsCanvas` whose first element is the inner output, open
# or closed, so a mapped reference always gains the same one step.
#
# **Reader** — while the palette is closed the inner reader has priority, and the
# palette gesture is considered only after it declines. While the palette is open the
# decorator reads first and swallows every event: the keys build the query, move the
# selection, run the chosen command, or close the palette. The content therefore
# never sees a keystroke meant for the palette, and its selection does not move while
# the user types.
#
# **Why a decorator and not a window.** `ScreenToScreen` prefixes
# `windows[i].content` to every operation that leaves a window's chain. A command
# edits the *content* document, so an operation returned from a palette window would
# carry the palette window's path and land in the wrong place. Here the operation is
# this decorator's own reader result, and every stage above reroots it exactly as if
# a key had fired the binding.
#
# **Which bindings it lists.** `collect_gesture_rows` walks the whole
# `CollectedIntentsOperation`, so a row's binding can come from any stage of
# the reader chain, not only this decorator's own input document. Every row's
# operation is already rooted back through every stage above, the same route a
# real keystroke takes, so choosing a row runs it exactly as if a key had
# fired the binding. A row whose collected intent carried no operation — not
# applicable to the current selection — prints "(not now)" instead.
"""
    COMMAND_PALETTE_GESTURE

The gesture that summons the palette: Ctrl+Shift+P. F1 already opens the help
window, which is the palette's read-only twin.
"""
const COMMAND_PALETTE_GESTURE = KeyDownPattern(:p; modifiers = [:ctrl, :shift])

"""
    is_command_palette_gesture(event) -> Bool

True when `event` is the gesture that summons the palette.
"""
is_command_palette_gesture(event) = matches_gesture_pattern(COMMAND_PALETTE_GESTURE, event)

"""
    ToggleCommandPaletteOperation()

Open the palette, or close it when it is open: what the palette gesture does, for a
command that has no key. The command sends it with a route into the content of
the decorator, as `read_rooted_operation` sends an operation, and the decorator
finds it in the answer of its inner reader. It names no place, so it travels up a
chain as it is.
"""
struct ToggleCommandPaletteOperation <: Operation end

OperationModule.is_self_contained_operation(::ToggleCommandPaletteOperation) = true
OperationModule.describe_operation(::ToggleCommandPaletteOperation) = "open or close the command palette"

"""
    CommandPaletteState()

The palette's own state: one `CommandPalette` document, reused for the life of the
editor, and an `open` flag.

The flag is a `Cell` because the printer reads it inside a reactive thunk. A plain
`Bool` would freeze the render at whatever it was when the projection printed.

The document is created once and mutated on open, rather than replaced, so the
sub-iomap the printer built for it stays valid.
"""
struct CommandPaletteState
    palette::CommandPalette
    open::Cell
end

CommandPaletteState() = CommandPaletteState(CommandPalette(), Cell(false))

"""
    CommandPaletteDecoratorProjection(; inner, measure, state=CommandPaletteState(),
                              theme=nothing, syntax_theme=nothing, text_theme=nothing,
                              x=60, y=60)

Decorator over `inner`, a content pipeline that prints down to graphics. The
palette gesture opens a type-in field at `(x, y)` listing the commands available
where the user is. `measure` is the `TextMeasure` the palette's own rendering
chain needs, the same one the content pipeline uses. `theme` is a
[`GestureHelpTheme`](@ref), scaled or not, or `nothing` for the default styles of
the palette's rows and its panel; `syntax_theme` and `text_theme` reach the
syntax-to-text and the text-to-graphics stages of the palette's own chain.

Pass a shared `state` to keep one palette across the rebuilt decorators an example
pipeline creates per dispatch.
"""
struct CommandPaletteDecoratorProjection <: Projection
    inner::Any
    state::CommandPaletteState
    projection::Any
    style::Any
    x::Int
    y::Int
end

"""
    make_command_palette_projection(measure; theme=nothing, syntax_theme=nothing, text_theme=nothing)
        -> Projection

The palette's own rendering chain: the type-in lines down to graphics, through the
same stages the help window uses. `theme` is a [`GestureHelpTheme`](@ref), a
scaled one, or `nothing` for the default styles; `syntax_theme` and `text_theme`
style the syntax-to-text and the text-to-graphics stages.
"""
make_command_palette_projection(measure::TextMeasure; theme = nothing, syntax_theme = nothing,
                                text_theme = nothing) =
    ChainingProjection(make_command_palette_syntax_projection(; theme),
                       RecursiveProjection(SyntaxToText(; theme = syntax_theme)),
                       WordWrapping(measure=measure),
                       TextToGraphics(; measure, theme = text_theme))

CommandPaletteDecoratorProjection(; inner, measure::TextMeasure,
                           state::CommandPaletteState = CommandPaletteState(),
                           theme = nothing, syntax_theme = nothing, text_theme = nothing,
                           projection = make_command_palette_projection(measure; theme, syntax_theme,
                                                                       text_theme),
                           x::Integer = 60, y::Integer = 60) =
    CommandPaletteDecoratorProjection(inner, state, projection,
                                      make_theme_values_field(GestureHelpTheme, theme),
                                      Int(x), Int(y))

@iomap struct CommandPaletteDecoratorIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    palette_iomap::Any
end

# ── Printer ────────────────────────────────────────────────────────────────

function print_document(p::CommandPaletteDecoratorProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    palette_iomap = print_document(p.projection, nothing, p.state.palette, ctx)
    # One wrapping canvas, built once. Its element list is the reactive part: the
    # inner output alone while the palette is closed, and the inner output plus the
    # placed palette while it is open. The wrapper itself never changes, so the
    # inner output is always element 1 and a mapped reference always gains the same
    # one step.
    elements = CellVector(@computation(
        p.state.open[] ?
            Any[inner_iomap.output, _placed_palette(p, palette_iomap)] :
            Any[inner_iomap.output]))
    output = GraphicsCanvas(elements, layout_none)
    CommandPaletteDecoratorIoMap(p, input, Cell(output), inner_iomap, palette_iomap)
end

# The palette on its own panel, at (p.x, p.y). Without the panel the type-in lines
# paint straight over the document and neither can be read.
#
# The panel is sized from what the palette measured, so it grows and shrinks with
# the list. Reading `w`/`h` here makes the enclosing thunk re-run per keystroke,
# which is what keeps the panel around the text rather than behind where the text
# used to be.
function _placed_palette(p::CommandPaletteDecoratorProjection, palette_iomap)
    content = palette_iomap.output
    t = unwrap_cell(p.style)
    pad = t.palette_padding
    panel = GraphicsRect(0, 0, content.w + 2 * pad, content.h + 2 * pad;
                         color = t.palette_background, radius = t.palette_radius,
                         border_width = t.palette_border_width, border_color = t.palette_border)
    GraphicsCanvas(Any[panel, GraphicsCanvas(Any[content]; x = pad, y = pad)];
                   x = p.x, y = p.y)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::CommandPaletteDecoratorProjection, recursion, change::Intent,
                     iomap::CommandPaletteDecoratorIoMap)
    if p.state.open[] && change.route === nothing
        # The palette owns every event while it is open. Nothing reaches the content,
        # so its selection stays where the user left it. An operation with a route
        # is not an event, and goes to the content.
        return Intent(change.gesture, _read_open(p, iomap, change.gesture))
    end
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    # A command that asks for the palette comes up from the content as an answer.
    child.operation isa ToggleCommandPaletteOperation &&
        return Intent(change.gesture, _toggle!(p, recursion, iomap))
    child.operation isa Operation && return child
    is_command_palette_gesture(change.gesture) &&
        return Intent(change.gesture, _toggle!(p, recursion, iomap))
    return child
end

# Open the palette, or close it when it is open. While it is open, the palette
# takes its own gesture in `_read_open`, so only a routed command reaches it here
# open.
function _toggle!(p::CommandPaletteDecoratorProjection, recursion, iomap::CommandPaletteDecoratorIoMap)
    p.state.open[] ? _close!(p) : _open!(p, recursion, iomap)
    DoNothingOperation()
end

read_intent(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Fill the palette from the context the user is in, and open it.
#
# The rows come from the reader, asked where a keystroke would go. Every operation
# in them was built by the binding that owns it and rooted by every stage on the
# way back, so it applies at this decorator's input whatever wraps the content and
# however deep the binding lives.
function _open!(p::CommandPaletteDecoratorProjection, recursion, iomap::CommandPaletteDecoratorIoMap)
    answer = read_intent(p.inner, recursion, Intent(CollectIntents()), iomap.inner_iomap)
    palette = p.state.palette
    palette.rows = collect_gesture_rows(answer isa Intent ? answer.operation : answer)
    palette.query = ""
    palette.selection = get_command_palette_settled_selection(palette)
    p.state.open[] = true
end

_close!(p::CommandPaletteDecoratorProjection) = (p.state.open[] = false)

# Every event while the palette is open. An event the palette has no use for is
# still swallowed: the palette is a modal type-in, and a stray key must not edit the
# document behind it.
function _read_open(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, event)
    palette = p.state.palette
    # The summoning gesture dismisses it too, so the key toggles the palette the way
    # F1 toggles the help window.
    is_command_palette_gesture(event) && (_close!(p); return DoNothingOperation())
    if event isa KeyDown
        event.key === :escape && (_close!(p); return DoNothingOperation())
        event.key === :return && return _run(p)
        event.key === :up && return _step!(palette, -1)
        event.key === :down && return _step!(palette, 1)
        event.key === :backspace && return _type!(palette, chop(palette.query))
    elseif event isa KeyPress && isprint(event.char)
        return _type!(palette, string(palette.query, event.char))
    end
    return DoNothingOperation()
end

# A query edit re-settles the selection: the chosen row stays chosen while it still
# matches, and the first match takes over once it does not.
function _type!(palette::CommandPalette, query::AbstractString)
    palette.query = String(query)
    palette.selection = get_command_palette_settled_selection(palette)
    DoNothingOperation()
end

function _step!(palette::CommandPalette, delta::Integer)
    next = compute_command_palette_step(palette, delta)
    next === nothing || (palette.selection = next)
    DoNothingOperation()
end

# Run the chosen row and close the palette. A row with no operation cannot run —
# its precondition failed, or it needs a keystroke to carry its argument — so the
# palette stays open and the user can pick another.
#
# There is nothing to look up here. Returning the operation is the whole of running
# it, because the reader already rooted it where this decorator's own result is
# expected.
function _run(p::CommandPaletteDecoratorProjection)
    row = get_command_palette_row(p.state.palette)
    (row === nothing || row.operation === nothing) && return DoNothingOperation()
    _close!(p)
    row.operation
end

# ── Reference mapping ──────────────────────────────────────────────────────
# The output is the inner output inside one wrapping canvas, so a forward-mapped
# reference gains `elements[1]` and a backward-mapped one gives it up.

function map_reference_forward(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, reference)
    inner = map_reference_forward(p.inner, iomap.inner_iomap, reference)
    inner === nothing && return nothing
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(ElementReferenceStep(1), inner))
end

function map_reference_backward(p::CommandPaletteDecoratorProjection, iomap::CommandPaletteDecoratorIoMap, reference)
    # A point maps into the content in the same frame, as a pointer event reaches
    # it. While the palette is open it owns every event, so no point reaches the
    # content.
    if find_reference_point(reference) !== nothing
        p.state.open[] && return nothing
        return map_reference_backward(p.inner, iomap.inner_iomap, reference)
    end
    inner = _strip_wrapper(reference)
    inner === nothing && return nothing
    map_reference_backward(p.inner, iomap.inner_iomap, inner)
end

# Drop the `elements[1]` the printer added; anything else names the palette itself
# or nothing at all, and does not map back into the content.
function _strip_wrapper(reference)
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == "elements") || return nothing
    tail = reference.tail
    tail isa ConcreteReference || return nothing
    step = tail.head
    step == ElementReferenceStep(1) || return nothing
    tail.tail
end

# ── Collection ─────────────────────────────────────────────────────────────
# Nothing to do. While the palette is closed the reader delegates every payload it
# does not claim to the content, and a `CollectIntents` payload is one of those —
# so the help window sees exactly what it would see without the palette in the
# chain. While the palette is open it swallows everything, itself included.

"""
    command_palette = true | (; measure)

The wrapper of `build_editor` that makes Ctrl+Shift+P open a field over the
window: typing narrows the commands that work here, Enter runs the selected one
and Escape closes it. `measure` measures its text, `FontFileMeasure()` by
default. The palette takes its theme and the syntax and the text themes from the
`Appearance` of the `appearance` wrapper. It is off by default. It acts around the
help of F1.
"""
function wrap_editor!(::Val{:command_palette}, layer::Symbol, argument, parts::EditorParts)
    options = argument === true ? (;) : argument
    parts.projection = CommandPaletteDecoratorProjection(; inner = parts.projection,
                                                         measure = get(options, :measure, FontFileMeasure()),
                                                         _get_gesture_help_themes(parts)...)
    parts
end

get_wrapper_layers(::Val{:command_palette}) = (:container => 50,)
