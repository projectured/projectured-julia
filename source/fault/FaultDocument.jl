# Fragment of `FaultViewModule` — what a fault looks like as data: the report
# that stands where a projection failed, and the log that collects them.

"""
    FaultReport(; site, origin, message)
    FaultReport(record)

One fault, as a document.

It is what `FaultCatchingProjection` puts in the output where a node failed. A
report keeps the slot the node had, so the parent's layout still places it and
every other node still draws.

A report is inert. Its projection declines every gesture and maps no reference,
so a person can not edit a mark and the selection does not walk into one.

The kernel's `FaultRecord` is the same fault as a value. This is the same fault
as a document: the kernel records, and this package shows.

# Example

    FaultReport(record)

See also `FaultCatchingProjection`, which is what makes one, and `FaultLog`.
"""
@document struct FaultReport
    site::String = "print"
    origin::String = "unknown"
    message::String = ""
end

# The keyword form, not the positional one: every field of this document
# declares a default, and `@document` emits no positional constructor for a
# struct whose required-field count is zero.
FaultReport(record::FaultRecord) =
    FaultReport(site = String(record.site), origin = String(record.origin),
                message = record.message)

"""
    format_fault_label(report) -> String

The one line a mark shows: what failed, and what it said.
"""
format_fault_label(report::FaultReport) = "⚠ $(report.origin): $(report.message)"

# ── The log ──────────────────────────────────────────────────────────────────

"""
    FaultLogEntry(index, site, origin, message, count)

One line of the log. A plain value: the buffer that keeps entries is the
document, and an entry is one of the things it holds.

`count` is how many places the fault was found in, which for one bug across a
large document is the number that matters.
"""
struct FaultLogEntry
    index::Int
    site::Symbol
    origin::Symbol
    message::String
    count::Int
end

"""
    FaultLog(; capacity = 50)

The message log: what failed, in the order it was first seen.

`entries` holds at most `capacity` entries, oldest first. A fault already in the
log takes its entry back rather than a second one, so one bug at three thousand
nodes is one line whose `count` says three thousand.

Attach one to an editor's store and the frame fills it:

    attach_fault_target!(editor.faults, log)

That is the whole wiring. The drain calls `append_fault!` on it once per frame,
from the editor's own task, which is the only place a document made of cells may
be written.

See also `FaultLogOverlayProjection`, which draws it, and `append_fault!`.
"""
@document struct FaultLog
    entries::CellVector = CellVector()
    capacity::Int = 50
end

"""
    append_fault!(log, record) -> log

Put one record in the log, or take back the line it already has.

This is the kernel's `append_fault!` seam, answered for `FaultLog`. The kernel
declares it and answers nothing, so the kernel never names this document.

It writes cells, so it must run outside every reactive thunk. `drain_faults!` is
what calls it, once per frame, on the editor's own task.
"""
function append_fault!(log::FaultLog, record::FaultRecord)
    position = _find_fault_line(log, record)
    if position === nothing
        push!(log.entries, FaultLogEntry(length(log.entries) + 1, record.site,
                                         record.origin, record.message, record.count))
    else
        # The same fault again, with a larger count. It takes its own line back
        # rather than a second one, which is what keeps one bug at three
        # thousand nodes to one line.
        known = log.entries[position]
        log.entries[position] = FaultLogEntry(known.index, record.site, record.origin,
                                              record.message, record.count)
    end
    while length(log.entries) > log.capacity
        deleteat!(log.entries, 1)
    end
    log
end

function _find_fault_line(log::FaultLog, record::FaultRecord)
    for index in 1:length(log.entries)
        known = log.entries[index]
        known isa FaultLogEntry || continue
        known.site === record.site && known.origin === record.origin && return index
    end
    nothing
end

"""
    clear_fault_log!(log) -> log

Delete every line.
"""
function clear_fault_log!(log::FaultLog)
    while length(log.entries) > 0
        deleteat!(log.entries, 1)
    end
    log
end

get_document_title(::FaultLog) = "Faults"
get_insertion_aliases(::Type{FaultLog}) = ["faults"]

# A saved window keeps where the log was and how much it holds, never what it
# held: the faults of one session say nothing about the next.
pred_arguments(log::FaultLog) = (), Pair{Symbol,Any}[:capacity => log.capacity]

# ── The session's log ────────────────────────────────────────────────────────

# One log for the session, because there is one editor and one program that
# fails in it. `FaultLog()` still builds an empty one, which a test and a
# gallery window want.
const _SESSION_FAULT_LOG = FaultLog()

"""
    get_session_fault_log() -> FaultLog

The one log of the session.

A window fills it once it is attached to the store of its editor:

    attach_fault_target!(editor.faults, get_session_fault_log())

Every fault log a person opens is this document, so two of them show the same
faults rather than two halves of them.
"""
get_session_fault_log() = _SESSION_FAULT_LOG

# A person who types `faults` into an empty tab gets the session's log, not a
# fresh empty one. A fresh one would never fill: what fills a log is the drain
# of the store it is attached to.
make_insertion_document(::Type{FaultLog}) = get_session_fault_log()
