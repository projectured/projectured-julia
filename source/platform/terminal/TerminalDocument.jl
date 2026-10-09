# Fragment of `TerminalModule` — the document of a terminal: the program that it
# runs, the lines that the program wrote and the person sent, the line that the
# person types, and the state of the program.

"""
    TerminalLine(text, kind)

One line of a terminal. `kind` is `:output` for the standard output of the
program, `:error` for its standard error, `:input` for a line that the person
sent, and `:status` for a line of the terminal itself, such as the exit status.
"""
struct TerminalLine
    text::String
    kind::Symbol
end

"""
    TerminalControl

What a terminal holds while its program runs: the process, and whether a stop
was asked. The document holds it, and no path reaches into it.
"""
mutable struct TerminalControl
    process::Base.Process
    is_stopping::Bool
end

"""
    TerminalDocument(command; on_exit = nothing, line_capacity = 2000)

A terminal that runs `command`, a `Cmd`, with pipes and no terminal device.

- `lines` — the [`TerminalLine`](@ref)s so far, at most `line_capacity`; the
  oldest go first. The last line stays open while the program writes it with no
  line end, so a prompt shows before the person answers it.
- `is_line_open` — whether the program can still add to the last line.
- `input` — the line that the person types, a `PrimitiveString`; Return sends it.
- `status` — `:new` before the start, `:running`, the exit status of the program
  when it ended, or `:failed` when it could not start.
- `control` — the [`TerminalControl`](@ref) while the program runs, else
  `nothing`.
- `on_exit` — `nothing`, or a function that the terminal calls on the editor
  task with the editor and the exit status when the program ends.

[`start_terminal!`](@ref) starts the program, [`send_terminal_input!`](@ref)
sends a line, [`stop_terminal!`](@ref) stops it, and the close of its tab ends
it.
"""
@document struct TerminalDocument <: Document
    command::Any
    lines::Any = TerminalLine[]
    is_line_open::Bool = false
    line_capacity::Int = 2000
    input::Any = PrimitiveString("")
    status::Any = :new
    control::Any = nothing
    on_exit::Any = nothing
end

TerminalDocument(command::Cmd; on_exit = nothing, line_capacity::Integer = 2000) =
    TerminalDocument(; command, on_exit, line_capacity = Int(line_capacity))

get_document_title(terminal::TerminalDocument) = "Terminal: " * format_terminal_command(terminal.command)

"""
    format_terminal_command(command) -> String

The program and the arguments of `command` as one line, for a person.
"""
format_terminal_command(command::Cmd) = join(command.exec, ' ')

"""
    is_terminal_running(terminal) -> Bool

Whether the program of `terminal` runs.
"""
is_terminal_running(terminal::TerminalDocument) = terminal.control !== nothing

# The escape sequences of colour and cursor (CSI) and of the title (OSC), which a
# terminal with no screen does not draw.
const _ESCAPE_SEQUENCE = r"\e\[[0-?]*[ -/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e[@-Z\\-_]"

"""
    add_terminal_text!(terminal, kind, text) -> TerminalDocument

Add what the program wrote on the stream `kind` (`:output` or `:error`). The
text goes on the open last line when that line has the same kind, a line end
closes a line, and the text after the last carriage return of a line replaces
the text before it, so a progress line does not repeat. Only the editor task
writes the document.
"""
function add_terminal_text!(terminal::TerminalDocument, kind::Symbol, text::AbstractString)
    text = replace(replace(text, _ESCAPE_SEQUENCE => ""), "\r\n" => "\n")
    isempty(text) && return terminal
    lines = copy(terminal.lines)
    # Whether the next piece goes on the last line: the line is open, and the
    # same stream wrote it.
    is_open = terminal.is_line_open && !isempty(lines) && last(lines).kind === kind
    pieces = split(text, '\n')
    for (index, piece) in enumerate(pieces)
        if is_open
            lines[end] = TerminalLine(_drop_overwritten_text(last(lines).text * piece), kind)
        elseif !isempty(piece) || index < length(pieces)
            push!(lines, TerminalLine(_drop_overwritten_text(piece), kind))
            is_open = true
        end
        # A line end follows each piece but the last, and closes the line.
        index < length(pieces) && (is_open = false)
    end
    terminal.lines = _keep_terminal_lines(lines, terminal.line_capacity)
    terminal.is_line_open = is_open
    terminal
end

# The text after the last carriage return: the program went back to the start of
# the line and wrote over it.
_drop_overwritten_text(text::AbstractString) =
    (index = findlast('\r', text); index === nothing ? String(text) : String(text[nextind(text, index):end]))

_keep_terminal_lines(lines::Vector{TerminalLine}, capacity::Int) =
    length(lines) <= capacity ? lines : lines[(end - capacity + 1):end]

"""
    add_terminal_line!(terminal, kind, text) -> TerminalDocument

Add a whole line of `kind` (`:input` or `:status`) after the lines so far. It
closes the open last line.
"""
function add_terminal_line!(terminal::TerminalDocument, kind::Symbol, text::AbstractString)
    terminal.lines = _keep_terminal_lines(vcat(terminal.lines, TerminalLine(String(text), kind)),
                                          terminal.line_capacity)
    terminal.is_line_open = false
    terminal
end
