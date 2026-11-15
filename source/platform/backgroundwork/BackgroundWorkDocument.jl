# Fragment of `BackgroundWorkModule` — the log of the background work: a row for
# each work of a background cell of the editor, newest first, which the feed
# copies from the store of the kernel.

"""
    BackgroundWorkRow

One work of a background source, as a row of the log: `number`, its place in the
order of the works of the editor; `source`, the description of its source;
`values`, how many values it computes; `started`, the time of its start in hours,
minutes and seconds; `took`, its time, or "running"; `state`, "running", "done" or
"failed"; `failure`, the message of its first failure; and `inputs`, its first
inputs as text.
"""
@document struct BackgroundWorkRow
    number::Int
    source::String
    values::Int
    started::String
    took::String
    state::String
    failure::String
    inputs::String
end

# A row runs, ends, or failed, as the mark of its state says.
get_document_decoration(row::BackgroundWorkRow) =
    DocumentDecoration(; conditions = [DocumentCondition(row.state == "running" ? :running :
                                                         row.state == "failed" ? :failed : :done)],
                       work_item = true)

"""
    BackgroundWorkLog()

The log of the background work of a session: `rows` holds a
[`BackgroundWorkRow`](@ref) for each record of the store of the editor, newest
first, as the feed last copied them, and `change_count` is the count of changes of
the store that the rows show, or -1 before the first copy. `table` is the
arrangement of a roster of the rows, which the page draws, and a person filters
and sorts.

Use [`get_session_background_work_log`](@ref) for the log of an editor: a log
that no feed fills stays empty.
"""
@document struct BackgroundWorkLog
    rows::CellVector = CellVector()
    change_count::Int = -1
    table::Any = nothing
end

const _LOG_COLUMNS = ["number", "source", "values", "started", "took", "state", "failure", "inputs"]

# A log with its table: an arrangement of a roster of the rows, whose source is
# the collection at `rows` of the log.
function _make_background_work_log()
    log = BackgroundWorkLog()
    roster = Roster(CollectionItems(extend_reference(EmptyReference(), FieldReferenceStep("rows")));
                    columns = _LOG_COLUMNS, title = "Background work")
    link_roster!(roster, log)
    log.table = ArrangementDocument(roster, ArrangementEntry[])
    log
end

get_document_title(::BackgroundWorkLog) = "Background work"
get_insertion_aliases(::Type{BackgroundWorkLog}) = ["background"]

# A file keeps that it shows the log of the session, not the rows, which belong to
# the session; a load gives the log of the session of its editor.
pred_arguments(::BackgroundWorkLog) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:BackgroundWorkLog}, positional, keywords) = get_session_background_work_log()
make_insertion_document(::Type{BackgroundWorkLog}) = get_session_background_work_log()

"""
    get_session_background_work_log(; editor = find_evaluation_editor()) -> BackgroundWorkLog

The log of the background work of the session of `editor`: by default the editor
of the evaluation, or of the loop that runs the calling code. Each editor has its
own, and its [`BackgroundWorkFeed`](@ref) fills it while a view shows it. With no
editor, a new empty log, which nothing fills.

Use it to read which works the editor runs in the background, and which failed.

# Example

    [row.source for row in get_session_background_work_log().rows]

See also `get_background_work_store`.
"""
function get_session_background_work_log end

get_session_background_work_log(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(_make_background_work_log, editor, BackgroundWorkLog) :
                        _make_background_work_log()

# The log runs while a work runs, says how many, and fails while a row failed.
function get_document_decoration(log::BackgroundWorkLog)
    rows = collect(log.rows)
    running = count(row -> row.state == "running", rows)
    failed = count(row -> row.state == "failed", rows)
    conditions = DocumentCondition[]
    running > 0 && push!(conditions, DocumentCondition(:running))
    failed > 0 && push!(conditions, DocumentCondition(:failed; count = failed))
    counts = running > 0 ? [DocumentCount(string(running, " running"); role = :accent)] : DocumentCount[]
    DocumentDecoration(; icon = :loader, conditions, counts, tooltip = () -> _make_background_work_note(log))
end

# What a row of the log says when the pointer rests on it: what it holds, and how
# many rows it keeps, how many run and how many failed.
function _make_background_work_note(log::BackgroundWorkLog)
    rows = collect(log.rows)
    TooltipNote(; title = "Background work", text = "The background work of this session, and how each ended.",
                facts = ["Kept" => string(length(rows)),
                         "Running" => string(count(row -> row.state == "running", rows)),
                         "Failed" => string(count(row -> row.state == "failed", rows))])
end

"""
    flush_background_work_log!(log, store) -> Int

Write the records of `store` into `log`, newest first, and answer how many rows
it wrote. A record that the log shows already keeps its row, and the row gets only
the fields that changed, so the other cells keep their readers valid. A new record
gets a new row. Runs on the editor task only, because it writes cells.
"""
function flush_background_work_log!(log::BackgroundWorkLog, store::BackgroundWorkStore)
    known = Dict{Int,BackgroundWorkRow}(row.number => row for row in collect(log.rows))
    written = 0
    rows = BackgroundWorkRow[]
    for record in Iterators.reverse(store.records)
        row = get(known, record.number, nothing)
        if row === nothing
            row = BackgroundWorkRow(record.number, record.description, record.value_count,
                                    Libc.strftime("%H:%M:%S", record.started), _format_work_time(record),
                                    _format_work_state(record), record.failure, join(record.inputs, ", "))
            written += 1
        else
            for (name, value) in (("took", _format_work_time(record)), ("state", _format_work_state(record)),
                                  ("failure", record.failure))
                getproperty(row, Symbol(name)) == value && continue
                setproperty!(row, Symbol(name), value)
                written += 1
            end
        end
        push!(rows, row)
    end
    shown = collect(log.rows)
    (length(shown) == length(rows) && all(k -> shown[k] === rows[k], eachindex(rows))) ||
        (log.rows = CellVector(Any[rows...]))
    log.change_count = store.change_count
    written
end

_format_work_time(record::BackgroundWorkRecord) =
    record.finished === nothing ? "running" : string(round(record.finished - record.started; digits = 2), " s")

_format_work_state(record::BackgroundWorkRecord) =
    record.finished === nothing ? "running" : record.failure_count > 0 ? "failed" : "done"
