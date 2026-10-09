# Fragment of `TerminalModule` — the program of a terminal: its start with pipes
# in a process group of its own, the readers of its two output streams, the line
# that the person sends, its stop, and its end.

"""
    start_terminal!(editor, terminal) -> TerminalDocument

Start the program of `terminal` with pipes for its standard input, output and
error, in a process group of its own. Two reader tasks read what the program
writes, as soon as it writes it and not line by line, and post it to the
editor; the end of the program posts its exit status and calls `on_exit`. A
terminal whose program runs stays as it is. A program that can not start gives
a status line and the status `:failed`.

It runs on the editor task, as an operation or an action does. The reader tasks
keep `editor` to post their writes; the document does not keep it.
"""
function start_terminal!(editor, terminal::TerminalDocument)
    is_terminal_running(terminal) && return terminal
    errors = Pipe()
    process = try
        open(pipeline(Cmd(terminal.command; detach = true); stderr = errors), "r+")
    catch exception
        exception isa Base.IOError || rethrow()
        add_terminal_line!(terminal, :status, "The program can not start: " * _format_start_error(exception))
        terminal.status = :failed
        return terminal
    end
    close(errors.in)
    terminal.control = TerminalControl(process, false)
    terminal.status = :running
    post(write) = run_on_editor_task!(write, editor; wait = false)
    errormonitor(@async begin
        error_reader = @async _read_terminal_stream(errors, text -> post(() -> add_terminal_text!(terminal, :error, text)))
        _read_terminal_stream(process.out, text -> post(() -> add_terminal_text!(terminal, :output, text)))
        wait(error_reader)
        wait(process)
        post(() -> _finish_terminal!(editor, terminal, process))
    end)
    terminal
end

# The error of the system, not the command line that the message of the exception
# quotes.
_format_start_error(exception::Base.IOError) =
    exception.code < 0 ? Libc.strerror(-exception.code) : "error $(exception.code)"

# Read `stream` until it ends, and give each piece of text to `add`. A character
# that a read cuts in two waits for the rest of its bytes.
function _read_terminal_stream(stream, add::Function)
    pending = UInt8[]
    try
        while !eof(stream)
            append!(pending, readavailable(stream))
            text = _take_whole_characters!(pending)
            isempty(text) || add(text)
        end
    catch exception
        exception isa Union{Base.IOError,EOFError} || rethrow()
    end
    isempty(pending) || add(String(pending))
    nothing
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
    terminal.control = nothing
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
    control = terminal.control
    control === nothing && return false
    try
        write(control.process, text, '\n')
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
    control = terminal.control
    control === nothing && return terminal
    signal = control.is_stopping ? Base.SIGKILL : Base.SIGINT
    control.is_stopping = true
    _signal_process_group(control.process, signal)
    terminal
end

function _signal_process_group(process::Base.Process, signal::Integer)
    if Sys.isunix()
        process_id = try
            Int(getpid(process))
        catch
            nothing
        end
        process_id === nothing || ccall(:kill, Cint, (Cint, Cint), -process_id, signal) == 0 ||
            kill(process, signal)
    else
        kill(process)
    end
    nothing
end

# The tab of a terminal closes: its program ends. An undo of the close brings
# the document back with the program ended; a person starts it again.
function release_document!(editor, terminal::TerminalDocument)
    control = terminal.control
    control === nothing || _signal_process_group(control.process, Base.SIGTERM)
    nothing
end
