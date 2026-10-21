# Fragment of `FaultViewModule` — what a fault looks like as data: the log that
# collects the faults, and the gestures of the report that stands where a
# projection failed.

# What a mark says about itself when the pointer rests on it: the whole fault,
# as a note. The one line a mark draws is cut where the mark ends, and a message
# is the part worth reading. A right click
# opens its menu, which tries the part again, when the report came from a barrier.
get_document_gesture_bindings_own(::Type{FaultReport}) = GestureBinding[
    make_tooltip_binding(make_fault_report_note;
                         description = "Show the fault"),
    make_context_menu_binding(_make_fault_report_menu;
                              description = "Show the menu of the fault")]

# The menu of a mark: one command that tries the part again, or no menu for a
# report that no barrier made.
function _make_fault_report_menu(report::FaultReport)
    retry = report.retry
    retry === nothing && return nothing
    WidgetMenu(Any[WidgetMenuItem("Try again";
                                  action = Action("Try again";
                                                  callback = editor -> evaluate_operation(editor, retry)))])
end

# ── The log ──────────────────────────────────────────────────────────────────

"""
    FaultLogEntry(index, key, site, origin, message, count)

One line of the log. A plain value: the buffer that keeps entries is the
document, and an entry is one of the things it holds.

`key` is the key of the `FaultRecord` that the line shows, so one line is one
fault exactly as the store counts one. `count` is how many places the fault was
found in, which for one bug across a large document is the number that matters.
"""
struct FaultLogEntry
    index::Int
    key::UInt64
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
        push!(log.entries, FaultLogEntry(length(log.entries) + 1, record.key, record.site,
                                         record.origin, record.message, record.count))
    else
        # The same fault again, with a larger count. It takes its own line back
        # rather than a second one, which is what keeps one bug at three
        # thousand nodes to one line.
        known = log.entries[position]
        log.entries[position] = FaultLogEntry(known.index, record.key, record.site,
                                              record.origin, record.message, record.count)
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
        known.key == record.key && return index
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

# A file keeps that it shows the log of the session, and not what the log held:
# the faults of one session say nothing about the next, and only the log of the
# session fills. A load gives the log of the session of its editor, and a load with
# no editor a new log.
pred_arguments(::FaultLog) = (), Pair{Symbol,Any}[]

# ── The session's log ────────────────────────────────────────────────────────

"""
    get_session_fault_log(; editor = find_evaluation_editor()) -> FaultLog

The fault log of the session of `editor`: by default the editor of the
evaluation, or of the loop that runs the calling code. Each editor has its own.
With no editor, a new empty log, which nothing keeps and nothing fills.

A window fills it once it is attached to the store of its editor:

    attach_fault_target!(editor.faults, get_session_fault_log(; editor))

Every fault log that a person opens in a window of the editor is this document,
so two of them show the same faults rather than two halves of them.

Use it to read what failed in the window: `print_natural_text` prints one line
for each fault, with its place, its message and its count.

# Example

    println(print_natural_text(get_session_fault_log()))

See also `get_session_message_log`, `get_session_gesture_log`.
"""
function get_session_fault_log end

get_session_fault_log(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(FaultLog, editor, FaultLog) : FaultLog()

# A person who types `faults` into an empty tab gets the log of the editor, not a
# fresh empty one. A fresh one would never fill: what fills a log is the drain
# of the store it is attached to.
make_insertion_document(::Type{FaultLog}) = get_session_fault_log()
make_pred_document(::Type{<:FaultLog}, positional, keywords) = get_session_fault_log()

# ── The fault log of a window, as a wrapper of `build_editor` ────────────────

"""
    fault_log = true

The wrapper of `build_editor` that attaches the fault log of the session
([`get_session_fault_log`](@ref)) to the fault store of the editor in a start
step, so the log holds every fault that the editor catches. It is off by default.
"""
function wrap_editor!(::Val{:fault_log}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.start_steps, editor -> (attach_fault_target!(editor.faults, get_session_fault_log(; editor));
                                        nothing))
    parts
end

get_wrapper_layers(::Val{:fault_log}) = (:screen => 30,)

# The fault log fails while it holds a fault, and counts its lines, until the
# person clears it.
function get_document_decoration(log::FaultLog)
    faults = length(log.entries)
    DocumentDecoration(; icon = :warning,
                       conditions = faults == 0 ? DocumentCondition[] : [DocumentCondition(:failed; count = faults)],
                       tooltip = () -> _make_fault_log_note(log))
end

# What a row of the log says when the pointer rests on it: what it holds, and how
# many faults it keeps.
_make_fault_log_note(log::FaultLog) =
    TooltipNote(; title = "Faults", text = "What failed in this session, and how often.",
                facts = ["Faults" => string(length(log.entries)), "Capacity" => string(log.capacity)])

# The command of the log, with no key: a person runs it from the command palette
# or the menu of its row, and the count of the faults goes back to zero.
@gestures FaultLog begin
    nothing => "Clear the fault log" => ReplaceReferencedValueOperation(doc, "entries", CellVector())
end
