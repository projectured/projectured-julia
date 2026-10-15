# Fragment of `SystemProcessModule` — a signal to a process that a document shows.
# The system gives a process id again once its process ended, so each signal reads
# the start of the process id first, and goes only to the process that the
# document shows.

"""
    interrupt_system_process!(process; root = "/proc") -> Bool

Send `SIGINT` to `process`, as Ctrl+C in its terminal does, and answer whether
it went. It goes only when the process id still names the process that the
document shows: `root` holds the start of the process id now, and when it is
not the start of the document, the process id is another process, and nothing
is sent. A process that ended answers `false` too.

See also `stop_system_process!`, which asks the process to end.
"""
interrupt_system_process!(process::SystemProcess; root::AbstractString = "/proc") =
    _send_system_process_signal!(process, Base.SIGINT, root)

"""
    stop_system_process!(process; root = "/proc") -> Bool

Send `SIGTERM` to `process`, which asks it to end, and answer whether it went.
It goes only when the process id still names the process that the document
shows, as for [`interrupt_system_process!`](@ref).
"""
stop_system_process!(process::SystemProcess; root::AbstractString = "/proc") =
    _send_system_process_signal!(process, Base.SIGTERM, root)

function _send_system_process_signal!(process::SystemProcess, signal::Integer, root)
    process_id = process.process_id
    parsed = _parse_stat(_read_text(joinpath(root, string(process_id), "stat")))
    (parsed === nothing || parsed.start_ticks != process.start_ticks) && return false
    ccall(:kill, Cint, (Cint, Cint), process_id, signal) == 0
end
