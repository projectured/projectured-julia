"""
    CommandPaletteDecoratorProjectionModule

The decorator that opens the **command palette** over a content pipeline, modelled
on [`GestureHelpProjection`](GestureHelpDecorator.jl).

**Printer** — the inner output, with the palette drawn over it. The output is
always one wrapping `GraphicsCanvas` whose first element is the inner output, open
or closed, so a mapped reference always gains the same one step.

**Reader** — while the palette is closed the inner reader has priority, and the
palette gesture is considered only after it declines. While the palette is open the
decorator reads first and swallows every event: the keys build the query, move the
selection, run the chosen command, or close the palette. The content therefore
never sees a keystroke meant for the palette, and its selection does not move while
the user types.

**Why a decorator and not a window.** `ScreenToScreen` prefixes
`windows[i].content` to every operation that leaves a window's chain. A command
edits the *content* document, so an operation returned from a palette window would
carry the palette window's path and land in the wrong place. Here the operation is
this decorator's own reader result, and every stage above reroots it exactly as if
a key had fired the binding.

**Which bindings it runs.** Only the bindings of its own input document — the
per-instance table and the per-type table. Those build their operations in that
document's reference vocabulary, which is the vocabulary this reader returns. A
binding gathered from a deeper stage of the chain builds its operation against
*that* stage's document, and only the reader chain maps it back; the palette lists
such a row with its key and marks it "key only".
"""
module CommandPaletteDecoratorProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward,
                              map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap"
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: ComputedCellVector
import ..DocumentApiModule: Document
import ..OperationApiModule: Operation
import ..OperationModule: DoNothingOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, ElementReferenceStep
import ..EventModule: KeyDown, KeyPress
import ..EventPatternModule: KeyDownPattern, matches_event_pattern
import ..GestureBindingModule: GestureBinding, get_instance_gesture_bindings,
                               get_document_gesture_bindings, fire_named_gesture_binding
import ..ProjectionGestureBindingsModule: collect_gesture_bindings
import ..GestureMapModule: GestureRow, gesture_row
import ..CommandPaletteModule: CommandPalette, command_palette_row,
                               command_palette_step, command_palette_settled_selection
import ..CommandPaletteToSyntaxModule: CommandPaletteToSyntax
import ..ChainingProjectionModule: ChainingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..SyntaxToTextModule: SyntaxToText
import ..WordWrappingModule: WordWrapping
import ..TextToGraphicsModule: TextToGraphics
import ..GraphicsModule: GraphicsCanvas, layout_none

export CommandPaletteProjection, CommandPaletteState, CommandPaletteProjectionIoMap,
       COMMAND_PALETTE_GESTURE, is_command_palette_gesture, command_palette_projection

"""
    COMMAND_PALETTE_GESTURE

The gesture that summons the palette: Ctrl+Shift+P. F1 already opens the help
window, which is the palette's read-only twin.
"""
const COMMAND_PALETTE_GESTURE = KeyDownPattern(:p, [:ctrl, :shift])

"""
    is_command_palette_gesture(event) -> Bool

True when `event` is the gesture that summons the palette.
"""
is_command_palette_gesture(event) = matches_event_pattern(COMMAND_PALETTE_GESTURE, event)

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
    CommandPaletteProjection(; inner, measure, state=CommandPaletteState(), x=60, y=60)

Decorator over `inner`, a content pipeline that prints down to graphics. The
palette gesture opens a type-in field at `(x, y)` listing the commands available
where the user is. `measure` is the text measurement function the palette's own
rendering chain needs, the same one the content pipeline uses.

Pass a shared `state` to keep one palette across the rebuilt decorators an example
pipeline creates per dispatch.
"""
struct CommandPaletteProjection <: Projection
    inner::Any
    state::CommandPaletteState
    projection::Any
    x::Int
    y::Int
end

"""
    command_palette_projection(measure) -> Projection

The palette's own rendering chain: the type-in lines down to graphics, through the
same stages the help window uses.
"""
command_palette_projection(measure::Function) =
    ChainingProjection(CommandPaletteToSyntax(),
                       RecursiveProjection(SyntaxToText()),
                       WordWrapping(measure=measure),
                       TextToGraphics(measure=measure))

CommandPaletteProjection(; inner, measure::Function,
                           state::CommandPaletteState = CommandPaletteState(),
                           projection = command_palette_projection(measure),
                           x::Integer = 60, y::Integer = 60) =
    CommandPaletteProjection(inner, state, projection, Int(x), Int(y))

@iomap struct CommandPaletteProjectionIoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
    palette_iomap::Any
end

# ── Printer ────────────────────────────────────────────────────────────────

function print_document(p::CommandPaletteProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    palette_iomap = print_document(p.projection, nothing, p.state.palette, ctx)
    # One wrapping canvas, built once. Its element list is the reactive part: the
    # inner output alone while the palette is closed, and the inner output plus the
    # placed palette while it is open. The wrapper itself never changes, so the
    # inner output is always element 1 and a mapped reference always gains the same
    # one step.
    elements = ComputedCellVector(() ->
        p.state.open[] ?
            Any[inner_iomap.output, GraphicsCanvas(Any[palette_iomap.output]; x=p.x, y=p.y)] :
            Any[inner_iomap.output])
    output = GraphicsCanvas(elements, layout_none)
    CommandPaletteProjectionIoMap(p, input, Cell(output), inner_iomap, palette_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::CommandPaletteProjection, recursion, change::Intent,
                     iomap::CommandPaletteProjectionIoMap)
    if p.state.open[]
        # The palette owns every event while it is open. Nothing reaches the content,
        # so its selection stays where the user left it.
        return Intent(change.gesture, _read_open(p, iomap, change.gesture))
    end
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    child.operation isa Operation && return child
    if is_command_palette_gesture(change.gesture)
        _open!(p, recursion, iomap)
        return Intent(change.gesture, DoNothingOperation())
    end
    return child
end

read_intent(p::CommandPaletteProjection, iomap::CommandPaletteProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The bindings this decorator may RUN: the ones belonging to its own input document.
_run_bindings(input) = input isa Document ?
    vcat(get_instance_gesture_bindings(input), get_document_gesture_bindings(typeof(input))) :
    GestureBinding[]

# Fill the palette from the context the user is in, and open it. The run set comes
# first; every other binding the chain offers follows as a row that shows its key.
function _open!(p::CommandPaletteProjection, recursion, iomap::CommandPaletteProjectionIoMap)
    input = iomap.input
    selection = input isa Document ? getfield(input, :selection)[] : nothing
    run = _run_bindings(input)
    rows = GestureRow[gesture_row(b, input, selection; runnable=true) for b in run]
    # A binding is identified for this purpose by what it says it is: the same
    # (domain, description) pair the collector would show twice.
    shown = Set{Tuple{String,String}}((b.domain, b.description) for b in run)
    for b in collect_gesture_bindings(p.inner, recursion, iomap.inner_iomap)
        (b.domain, b.description) in shown && continue
        push!(shown, (b.domain, b.description))
        push!(rows, gesture_row(b, input, selection))
    end
    palette = p.state.palette
    palette.rows = rows
    palette.query = ""
    palette.selection = command_palette_settled_selection(palette)
    p.state.open[] = true
end

_close!(p::CommandPaletteProjection) = (p.state.open[] = false)

# Every event while the palette is open. An event the palette has no use for is
# still swallowed: the palette is a modal type-in, and a stray key must not edit the
# document behind it.
function _read_open(p::CommandPaletteProjection, iomap::CommandPaletteProjectionIoMap, event)
    palette = p.state.palette
    # The summoning gesture dismisses it too, so the key toggles the palette the way
    # F1 toggles the help window.
    is_command_palette_gesture(event) && (_close!(p); return DoNothingOperation())
    if event isa KeyDown
        event.key === :escape && (_close!(p); return DoNothingOperation())
        event.key === :return && return _run(p, iomap)
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
    palette.selection = command_palette_settled_selection(palette)
    DoNothingOperation()
end

function _step!(palette::CommandPalette, delta::Integer)
    next = command_palette_step(palette, delta)
    next === nothing || (palette.selection = next)
    DoNothingOperation()
end

# Run the chosen command against the input document and close the palette. A row
# the palette cannot run leaves it open, so the user can pick another.
function _run(p::CommandPaletteProjection, iomap::CommandPaletteProjectionIoMap)
    row = command_palette_row(p.state.palette)
    (row === nothing || !row.runnable || !row.applicable) && return DoNothingOperation()
    input = iomap.input
    selection = input isa Document ? getfield(input, :selection)[] : nothing
    operation = fire_named_gesture_binding(_run_bindings(input), input, selection, row.name)
    _close!(p)
    operation === nothing ? DoNothingOperation() : operation
end

# ── Reference mapping ──────────────────────────────────────────────────────
# The output is the inner output inside one wrapping canvas, so a forward-mapped
# reference gains `elements[1]` and a backward-mapped one gives it up.

function map_reference_forward(p::CommandPaletteProjection, iomap::CommandPaletteProjectionIoMap, reference)
    inner = map_reference_forward(p.inner, iomap.inner_iomap, reference)
    inner === nothing && return nothing
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(ElementReferenceStep(1), inner))
end

function map_reference_backward(p::CommandPaletteProjection, iomap::CommandPaletteProjectionIoMap, reference)
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
    (step isa ElementReferenceStep && step.index == 1) || return nothing
    tail.tail
end

# ── Collection ─────────────────────────────────────────────────────────────
# The decorator owns no gestures of its own that a listing should show: the palette
# gesture opens a view, and the help window is that view's twin. Delegate, so the
# help window shows exactly what it showed without the palette in the chain.

collect_gesture_bindings(p::CommandPaletteProjection, recursion, iomap::CommandPaletteProjectionIoMap) =
    collect_gesture_bindings(p.inner, recursion, iomap.inner_iomap)

end # module
