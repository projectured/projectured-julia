# Fragment of `GestureHelpModule`.
#
# A content-level decorator that opens the **gesture-help window** on the help
# gesture (F1), modelled on [`TooltipDecoratorProjection`](TooltipDecorator.jl).
#
# **Printer** — transparent: projects the wrapped `inner` and returns its output
# unchanged, so the content window looks exactly as it did without the decorator.
#
# **Reader** — the inner reader has priority (it is the real editor). When the
# inner declines and the event is the help gesture, the decorator asks the reader
# what is available — the same route a keystroke takes, so the answer is rooted where
# this decorator can use it — builds a snapshot `GestureMap`, and emits an `OpenWindowOperation` whose
# `content` is that map. The op bubbles up to `WindowManagingProjection`, which opens
# a real sibling window beside the content (the same rail tooltips ride). A second
# help gesture emits `CloseWindowOperation`, so F1 toggles the window.
#
# Open/closed state lives in a shared `GestureHelpState` (not on the projection
# instance) because the example pipeline rebuilds the decorator per dispatch — the
# caller threads one state object through every decorator so the toggle is stable.
"""
    HELP_GESTURE

The gesture that summons the help window: F1, with any modifiers. It is an ordinary
reified pattern, owned here rather than by the input vocabulary — an event carries no
intent, so "F1 means help" is this projection's decision and no one else's.

Lisp binds help to Ctrl-H; F1 is unambiguous here, where Ctrl-? would need
`Ctrl+Shift+/` handling. A key chord would work too, once a chord table entry and a
chord pattern exist.
"""
const HELP_GESTURE = KeyDownPattern(:f1)

"""
    is_help_gesture(event) -> Bool

True when `event` is the gesture that summons the help window.
"""
is_help_gesture(event) = matches_gesture_pattern(HELP_GESTURE, event)

"""
    ToggleGestureHelpOperation()

Open the help window, or close it when it is open: what the help gesture does, for
a command that has no key. The command sends it with a route into the content of
the decorator, as `read_rooted_operation` sends an operation, and the decorator
finds it in the answer of its inner reader. It names no place, so it travels up a
chain as it is.
"""
struct ToggleGestureHelpOperation <: Operation end

OperationModule.is_self_contained_operation(::ToggleGestureHelpOperation) = true
OperationModule.describe_operation(::ToggleGestureHelpOperation) = "open or close the gesture help"

"""
    GestureHelpState(open=false)

Mutable open/closed flag for the gesture-help window, shared across the
(per-dispatch, transient) `GestureHelpDecoratorProjection` instances that wrap each
content window, so F1 toggles the same window.
"""
mutable struct GestureHelpState
    open::Bool
end
GestureHelpState() = GestureHelpState(false)

"""
    GestureHelpDecoratorProjection(; inner, state=GestureHelpState(), id=:gesture_help,
                            title="Gestures", x=100, y=100, width=1000, height=1400)

Decorator over `inner` (a content pipeline). On the help gesture it opens/closes a
window of id `id` carrying the collected `GestureMap`. Pass a shared `state` to
keep the toggle stable when the decorator is rebuilt each frame.
"""
struct GestureHelpDecoratorProjection <: Projection
    inner::Any
    state::GestureHelpState
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
end

GestureHelpDecoratorProjection(; inner, state::GestureHelpState = GestureHelpState(),
                        id::Symbol = :gesture_help, title::AbstractString = "Gestures",
                        x::Integer = 100, y::Integer = 100,
                        width::Integer = 1000, height::Integer = 1400) =
    GestureHelpDecoratorProjection(inner, state, id, String(title), Int(x), Int(y), Int(width), Int(height))

"""
    make_gesture_map_projection(measure; theme=nothing, syntax_theme=nothing, text_theme=nothing)
        -> Projection

What draws the help window's content: the gesture rows down to graphics, through
the same stages the command palette uses. A screen that lets the decorator open
its window names it for `GestureMap`. `theme` is a [`GestureHelpTheme`](@ref), a
scaled one, or `nothing` for the default styles; `syntax_theme` and `text_theme`
style the syntax-to-text and the text-to-graphics stages.
"""
make_gesture_map_projection(measure::TextMeasure; theme = nothing, syntax_theme = nothing,
                            text_theme = nothing) =
    ChainingProjection(make_gesture_map_syntax_projection(; theme),
                       RecursiveProjection(SyntaxToText(; theme = syntax_theme)),
                       WordWrapping(measure=measure),
                       TextToGraphics(; measure, theme = text_theme))

# Transparent: `output` forwards the inner output through a cell so the IoMap
# keeps its identity while the inner projection re-derives (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct GestureHelpDecoratorIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (transparent) ──────────────────────────────────────────────────

function print_document(p::GestureHelpDecoratorProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    GestureHelpDecoratorIoMap(p, input, Cell(@computation inner_iomap.output), inner_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::GestureHelpDecoratorProjection, recursion, change::Intent, iomap::GestureHelpDecoratorIoMap)
    # The wrapped editor has priority: if it produced an operation, that wins and
    # the help gesture (if any) is reconsidered next event.
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    # A command that asks for the help comes up from the content as an answer.
    child.operation isa ToggleGestureHelpOperation &&
        return Intent(change.gesture, _toggle!(p, recursion, iomap))
    child.operation isa Operation && return child
    is_help_gesture(change.gesture) && return Intent(change.gesture, _toggle!(p, recursion, iomap))
    return child
end

# Open the help window, or close it when it is open.
function _toggle!(p::GestureHelpDecoratorProjection, recursion, iomap::GestureHelpDecoratorIoMap)
    if p.state.open
        p.state.open = false
        return CloseWindowOperation(p.id)
    end
    # Ask the reader what is available, exactly where a keystroke would go.
    # What comes back is already rooted at this decorator's input, so the rows
    # carry runnable operations rather than rules someone still has to resolve.
    answer = read_intent(p.inner, recursion, Intent(CollectIntents()), iomap.inner_iomap)
    gm = make_gesture_map(answer isa Intent ? answer.operation : answer)
    p.state.open = true
    OpenWindowOperation(id = p.id, title = p.title,
                        x = p.x, y = p.y, width = p.width, height = p.height,
                        style = :normal, content = gm)
end

read_intent(p::GestureHelpDecoratorProjection, iomap::GestureHelpDecoratorIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping (transparent — output is the inner's output) ──────────

map_reference_forward(p::GestureHelpDecoratorProjection, iomap::GestureHelpDecoratorIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::GestureHelpDecoratorProjection, iomap::GestureHelpDecoratorIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

"""
    gesture_help = true | (; measure)

The wrapper of `build_editor` that makes F1 open a window that lists the
gestures that work where the person is, and F1 again close it. It adds the row
that draws that window to the windows that open later, measured with `measure`,
`FontFileMeasure()` by default, in the themes of the `Appearance` of the
`appearance` wrapper. It is off by default. It acts around the
clipboard, so the list names the gestures of the walk and of the clipboard too.
"""
function wrap_editor!(::Val{:gesture_help}, layer::Symbol, argument, parts::EditorParts)
    options = argument === true ? (;) : argument
    parts.projection = GestureHelpDecoratorProjection(inner = parts.projection, state = GestureHelpState())
    push!(parts.opened_window_projections,
          GestureMap => make_gesture_map_projection(get(options, :measure, FontFileMeasure());
                                                    _get_gesture_help_themes(parts)...))
    parts
end

get_wrapper_layers(::Val{:gesture_help}) = (:container => 40,)
