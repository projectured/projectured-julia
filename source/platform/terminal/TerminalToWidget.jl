# Fragment of `TerminalModule` — a terminal drawn as widgets: the command, the
# status and a stop button above the lines, the lines in a pane that follows the
# end, and the input line below them.

"""
    TerminalToWidget(; theme styles…)

Draw a [`TerminalDocument`](@ref): a row with the command, the status and a stop
button; the lines that the program wrote and the person sent, each in the style
of its kind, in a pane that follows the end; and the input line, the
`PrimitiveString` of the document, which the text layer edits.

A key reaches the input line by selection: a click on it puts the caret there,
and the containers carry that selection down. The projection reads Return
itself when the caret is in the input line, and sends the line.
"""
@projection UntrackedCell struct TerminalToWidget <: Projection
    output_text::StyleText = get_terminal_style(nothing, :output_text)
    error_text::StyleText = get_terminal_style(nothing, :error_text)
    input_text::StyleText = get_terminal_style(nothing, :input_text)
    status_text::StyleText = get_terminal_style(nothing, :status_text)
    lines_height::Int = get_terminal_style(nothing, :lines_height)
    input_height::Int = get_terminal_style(nothing, :input_height)
    gap::Int = get_terminal_style(nothing, :gap)
end

"""
    make_terminal_projection(; theme = nothing) -> TerminalToWidget

The projection of a terminal with the styles of `theme`: a `TerminalTheme`,
scaled or not, or the default styles for `nothing`.
"""
function make_terminal_projection(; theme = nothing)
    get_style(name) = get_terminal_style(theme, name)
    TerminalToWidget(; output_text = get_style(:output_text), error_text = get_style(:error_text),
                     input_text = get_style(:input_text), status_text = get_style(:status_text),
                     lines_height = get_style(:lines_height), input_height = get_style(:input_height),
                     gap = get_style(:gap))
end

function _get_terminal_line_style(p::TerminalToWidget, kind::Symbol)
    kind === :error && return p.error_text
    kind === :input && return p.input_text
    kind === :status && return p.status_text
    p.output_text
end

function _format_terminal_status(status)
    status === :new && return "not started"
    status === :running && return "running: type a line below and press Return"
    status === :failed && return "could not start"
    "ended with the status $(status)"
end

# Where the input line sits in the output: the content of the third child of the
# column.
const _TERMINAL_INPUT_PREFIX = Any[FieldReferenceStep("children"), RangeReferenceStep(2, 3),
                                   FieldReferenceStep("content")]

function print_document(p::TerminalToWidget, recursion, terminal::TerminalDocument, ctx)
    status = WidgetLabel(() -> _format_terminal_status(terminal.status); text_style = p.status_text)
    stop = WidgetButton("Stop"; tooltip = "Interrupt the program, and end it at a second press.",
                        action = _ -> stop_terminal!(terminal))
    set_cell_computation!(getfield(stop, :enabled), () -> is_terminal_running(terminal))
    header = HorizontalLayout(Any[WidgetLabel(format_terminal_command(terminal.command); text_style = p.status_text),
                                  status, stop];
                              vertical_align = :center, gap = 2 * p.gap)
    lines = VerticalLayout(Any[]; horizontal_align = :left, child_width = Fill)
    set_cell_computation!(getfield(lines.children, :elements), () ->
        Cell[Cell(WidgetLabel(isempty(line.text) ? " " : line.text; text_style = _get_terminal_line_style(p, line.kind)))
             for line in terminal.lines])
    lines_pane = WidgetScrollPane(lines; follow_end = true, size = Point2D(0, p.lines_height))
    input_pane = WidgetScrollPane(terminal.input; size = Point2D(0, p.input_height))
    column = VerticalLayout(Any[header, lines_pane, input_pane]; horizontal_align = :left, gap = p.gap,
                            child_width = Fill)
    iomap = SimpleIoMap(p, terminal, column)
    # A key is routed by selection, so the column and the pane of the input line
    # each carry the path of the selection, with their own prefix spent.
    image(path) = map_reference_forward(p, iomap, path)
    set_output_path_computations!(column, terminal, image; dormant = false)
    set_output_path_computations!(input_pane, terminal, path -> begin
        reference = image(path)
        reference === nothing && return nothing
        steps = get_reference_steps(reference)
        length(steps) > 2 && steps[1:2] == _TERMINAL_INPUT_PREFIX[1:2] || return nothing
        Reference(steps[3:end]...)
    end; dormant = false)
    iomap
end

# `input.<rest>` → the pane of the input line, and `<rest>` in it. A part that the
# view drew is the path that its introduced reference holds.
function map_reference_forward(p::TerminalToWidget, iomap::SimpleIoMap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep && head.name == "input" || return nothing
    Reference(_TERMINAL_INPUT_PREFIX..., get_reference_steps(reference.tail)...)
end

# And back: a click in the input line is a click in the `PrimitiveString`, so the
# caret lands where it was aimed. A click on the pane of the input line beside its
# text, or on the string as a whole, puts the caret at the end of the line. Any
# other part, such as a bar of a pane, is a part that the view drew.
function map_reference_backward(p::TerminalToWidget, iomap::SimpleIoMap, reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(reference)
    prefix = _TERMINAL_INPUT_PREFIX
    if length(steps) >= 2 && steps[1:2] == prefix[1:2]
        (length(steps) == 2 || (length(steps) == 3 && steps[3] == prefix[3])) &&
            return _make_terminal_input_caret(iomap.input)
        steps[3] == prefix[3] && return Reference(FieldReferenceStep("input"), steps[4:end]...)
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# The caret at `index` of the input line, by default at its end.
function _make_terminal_input_caret(terminal::TerminalDocument,
                                    index::Integer = length(something(terminal.input.value, "")))
    ConcreteReference(FieldReferenceStep("input"), ConcreteReference(FieldReferenceStep("value"),
                      ConcreteReference(RangeReferenceStep(index, index), EmptyReference())))
end

# A click that named no input line is still a click on the terminal, and the
# terminal takes it rather than the document that holds the terminal.
function read_intent(p::TerminalToWidget, iomap::SimpleIoMap, operation::ReplacePathOperation)
    inner = map_reference_backward(p, iomap, operation.path)
    make_path_operation(operation, inner === nothing ? EmptyReference() : inner)
end

# A press that nothing in the terminal took, on its lines or beside its input
# line, puts the caret at the end of the input line, as a press in a terminal
# gives it the keys.
function read_intent(::TerminalToWidget, iomap::SimpleIoMap, click::MouseClick)
    terminal = iomap.input
    terminal isa TerminalDocument && click.button === :left || return nothing
    ReplaceSelectionOperation(_make_terminal_input_caret(terminal))
end

_is_terminal_input_selected(terminal::TerminalDocument) =
    (path = terminal.selection; path isa ConcreteReference && path.head == FieldReferenceStep("input"))

# Return with no modifier sends the input line while the caret is in it and the
# program runs, and puts the caret at the start of the empty line. Every other
# key goes on.
function read_intent(::TerminalToWidget, iomap::SimpleIoMap, key::KeyPress)
    terminal = iomap.input
    terminal isa TerminalDocument || return nothing
    key.char == '\n' || return nothing
    modifiers = key.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta || modifiers.shift) && return nothing
    _is_terminal_input_selected(terminal) && is_terminal_running(terminal) || return nothing
    CompoundOperation(Any[SendTerminalInputOperation(terminal),
                          ReplaceSelectionOperation(_make_terminal_input_caret(terminal, 0))])
end

"""
    SendTerminalInputOperation(terminal)

Send the input line of `terminal` to its program, and empty the line. An undo
puts the line back in the input line; it does not take it back from the
program, which read it already, and a redo empties the line and sends nothing.
"""
struct SendTerminalInputOperation <: Operation
    terminal::TerminalDocument
end

make_inverse_operation(document, operation::SendTerminalInputOperation) =
    ReplaceReferencedValueOperation(operation.terminal.input, "value", operation.terminal.input.value)

function evaluate_operation(editor, operation::SendTerminalInputOperation)
    terminal = operation.terminal
    send_terminal_input!(terminal, something(terminal.input.value, "")) && (terminal.input.value = "")
    nothing
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab, or a card that embeds a terminal, draw it.

# The exit of the process ends the groups of the programs that still run.

function __init__()
    register_natural_graphics!(:terminal, (; measure, appearance) -> Pair{Type,Any}[
        TerminalDocument => ChainingProjection(make_terminal_projection(; theme = get_scaled_theme!(appearance, TerminalTheme)),
                                               VerticalLayoutToGraphicsCanvas())])
    atexit(_end_running_groups!)
end
