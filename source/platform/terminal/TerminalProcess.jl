# Fragment of `TerminalModule` — the program of a terminal: its start with pipes
# in a process group of its own, the readers of its two output streams, the line
# that the person sends, its stop, its end, and the end of the groups that still
# run when the editor process ends.

"""
    start_terminal!(editor, terminal) -> TerminalDocument

Start the program of `terminal` with pipes for its standard input, output and
error, in a process group of its own, with `TERM=dumb` so that it writes no
colours. Two reader tasks read what the program writes, as soon as it writes it
and not line by line, and post it to the editor. When the program ends, its
group ends too, the last text arrives, and the terminal posts the exit status
and calls `on_exit`. A terminal whose program runs stays as it is. A program
that can not start gives a status line and the status `:failed`.

It runs on the editor task, as an operation or an action does. The reader tasks
keep `editor` to post their writes; the document does not keep it.
"""
function start_terminal!(editor, terminal::TerminalDocument)
    is_terminal_running(terminal) && return terminal
    errors = Pipe()
    command = addenv(Cmd(terminal.command; detach = true), "TERM" => "dumb")
    process = try
        open(pipeline(command; stderr = errors), "r+")
    catch exception
        exception isa Base.IOError || rethrow()
        close(errors)
        add_terminal_line!(terminal, :status, "The program can not start: " * _format_start_error(exception))
        terminal.status = :failed
        return terminal
    end
    # The id of the group, read before the first yield: the leader can end and be
    # reaped at any yield, and then its id can not be read.
    group_id = try
        Int(getpid(process))
    catch
        nothing
    end
    close(errors.in)
    control = TerminalControl(process, group_id, false)
    terminal.control = control
    terminal.status = :running
    _add_running_group!(group_id)
    post(write) = run_on_editor_task!(write, editor; wait = false)
    errormonitor(@async begin
        error_reader = @async _read_terminal_stream(errors, text -> post(() -> add_terminal_text!(terminal, :error, text)))
        output_reader = @async _read_terminal_stream(process.out, text -> post(() -> add_terminal_text!(terminal, :output, text)))
        wait(process)
        _end_terminal_group!(control, (output_reader, error_reader), errors)
        post(() -> _finish_terminal!(editor, terminal, process))
    end)
    terminal
end

# The error of the system, not the command line that the message of the exception
# quotes.
_format_start_error(exception::Base.IOError) =
    exception.code < 0 ? Libc.strerror(-exception.code) : "error $(exception.code)"

# The program ended. A child that it left in its group can hold the streams open,
# so the group gets SIGTERM, and SIGKILL when the text has not ended two seconds
# later; then the streams close, and the readers end.
function _end_terminal_group!(control::TerminalControl, readers::Tuple, errors::Pipe)
    is_read() = all(istaskdone, readers)
    if !is_read()
        _signal_process_group!(control, Base.SIGTERM)
        if timedwait(is_read, 2.0) !== :ok
            _signal_process_group!(control, Base.SIGKILL)
            close(control.process.out)
            close(errors)
        end
    end
    foreach(wait, readers)
    _remove_running_group!(control.group_id)
    nothing
end

# Read `stream` until it ends, and give each piece of text to `add`. A character
# that a read cuts in two waits for the rest of its bytes. A carriage return at
# the end, which the next read can follow with a line end, and an escape sequence
# that has not ended wait for the next read too.
function _read_terminal_stream(stream, add::Function)
    bytes = UInt8[]
    held = ""
    try
        while !eof(stream)
            append!(bytes, readavailable(stream))
            text, held = _split_unfinished_text(held * _take_whole_characters!(bytes))
            isempty(text) || add(text)
        end
    catch exception
        exception isa Union{Base.IOError,EOFError} || rethrow()
    end
    rest = held * String(bytes)
    isempty(rest) || add(rest)
    nothing
end

# An escape sequence at the start of a text, as a whole.
const _ESCAPE_SEQUENCE_AT_START = Regex("^(?:" * _ESCAPE_SEQUENCE.pattern * ")")

# `text` as the part that is whole and the end that the next read can change: an
# escape sequence that has not ended, at most 64 characters long, or a carriage
# return.
function _split_unfinished_text(text::AbstractString)
    index = findlast('\e', text)
    if index !== nothing && length(text, index, lastindex(text)) <= 64 &&
       match(_ESCAPE_SEQUENCE_AT_START, SubString(text, index)) === nothing
        return String(SubString(text, 1, prevind(text, index))), String(SubString(text, index))
    end
    endswith(text, '\r') && return String(chop(text)), "\r"
    String(text), ""
end

# The text of `bytes` up to the last whole UTF-8 character; the bytes of a cut
# character stay in `bytes`.
function _take_whole_characters!(bytes::Vector{UInt8})
    count = length(bytes)
    cut = count
    for back in 0:min(3, count - 1)
        byte = bytes[count - back]
        byte & 0xc0 == 0x80 && continue
        if byte >= 0xc0
            size = byte >= 0xf0 ? 4 : byte >= 0xe0 ? 3 : 2
            back + 1 < size && (cut = count - back - 1)
        end
        break
    end
    text = String(bytes[1:cut])
    deleteat!(bytes, 1:cut)
    text
end

# The program ended: its status, a line that says it, and `on_exit`. A program
# that a signal ended has the status 128 and the number of the signal, as a shell
# says it.
function _finish_terminal!(editor, terminal::TerminalDocument, process::Base.Process)
    status = process.termsignal > 0 ? 128 + process.termsignal : process.exitcode
    terminal.status = status
    add_terminal_line!(terminal, :status, "The program ended with the status $(status).")
    on_exit = terminal.on_exit
    on_exit === nothing || on_exit(editor, status)
    nothing
end

"""
    send_terminal_input!(terminal, text) -> Bool

Send `text` and a line end to the standard input of the program, and add `text`
as a line of the kind `:input`, because a program with no terminal device does
not echo it. Answers `false` when no program runs.
"""
function send_terminal_input!(terminal::TerminalDocument, text::AbstractString)
    is_terminal_running(terminal) || return false
    try
        write(terminal.control.process, text, '\n')
    catch exception
        exception isa Base.IOError || rethrow()
        return false
    end
    add_terminal_line!(terminal, :input, text)
    true
end

"""
    stop_terminal!(terminal) -> TerminalDocument

Stop the program: the first stop sends SIGINT to its process group, as Ctrl+C
in a terminal does, and a second stop sends SIGKILL. On Windows, which has no
such group, a stop ends the process.
"""
function stop_terminal!(terminal::TerminalDocument)
    is_terminal_running(terminal) || return terminal
    control = terminal.control
    signal = control.is_stopping ? Base.SIGKILL : Base.SIGINT
    control.is_stopping = true
    _signal_process_group!(control, signal)
    terminal
end

# Send `signal` to the process group of the program, or end the process where no
# group is known.
function _signal_process_group!(control::TerminalControl, signal::Integer)
    if Sys.isunix() && control.group_id !== nothing
        ccall(:kill, Cint, (Cint, Cint), -control.group_id, signal)
    elseif process_running(control.process)
        kill(control.process)
    end
    nothing
end

# The tab of a terminal closes: its program ends, with SIGTERM, and SIGKILL three
# seconds later when it still runs. An undo of the close brings the document back
# with the program ended.
function release_document!(editor, terminal::TerminalDocument)
    is_terminal_running(terminal) || return nothing
    control = terminal.control
    _signal_process_group!(control, Base.SIGTERM)
    Timer(_ -> is_terminal_running(terminal) && _signal_process_group!(control, Base.SIGKILL), 3.0)
    nothing
end

# ── The groups that run ─────────────────────────────────────────────────────
# A program runs in a session of its own, so it does not end with the editor
# process. The ids of the groups that run are kept until their end, and the exit
# of the process sends SIGKILL to each.

const _RUNNING_GROUPS = Set{Int}()
const _RUNNING_GROUPS_LOCK = ReentrantLock()

_add_running_group!(group_id) =
    group_id === nothing || lock(() -> push!(_RUNNING_GROUPS, group_id), _RUNNING_GROUPS_LOCK)

_remove_running_group!(group_id) =
    group_id === nothing || lock(() -> delete!(_RUNNING_GROUPS, group_id), _RUNNING_GROUPS_LOCK)

function _end_running_groups!()
    Sys.isunix() || return nothing
    for group_id in lock(() -> collect(_RUNNING_GROUPS), _RUNNING_GROUPS_LOCK)
        ccall(:kill, Cint, (Cint, Cint), -group_id, Base.SIGKILL)
    end
    nothing
end
