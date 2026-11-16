# Fragment of `RosterModule` — a table of records that a file keeps: the records,
# one in each plain cell, and an arrangement of a roster of them, which the page of
# the table shows.

"""
    RecordTable(title; columns, records = [])

A table of records that a file keeps. `records` holds one record in each plain
cell: a named tuple, such as `(number = 12, commit = "fd436d7", state = "waiting")`,
or any document. `columns` names a field of the records for each column, as a key
of a roster does. `table` is what the page of the table shows: an arrangement
around a roster of `records`, with the record table as the link of the roster, so
a person filters, sorts and groups the rows in its bar and under its headers.

A new record is a new row at once, and a write of one field of a record makes a new
row for that record only. Each record needs a field that no other record has, such
as `number`: two equal records are one row, because a row follows its record by
its identity. A file keeps the title, the columns and the records, and no
arrangement, so a sort is made again after a load.

Use it to keep a table of records that grows while a long work runs, and to change
one value of a record later.

# Example

    path_1 = joinpath(mktempdir(), "ledger.pred")
    write_document_file!(RecordTable("Ledger"; columns = ["number", "commit", "state"]), path_1)
    tab_1 = open_file!(path_1)
    ledger_1 = get_edited_document(tab_1)
    insert_elements!(ledger_1.records, 1, [(number = 1, commit = "fd436d7", state = "waiting")])
    replace_referenced_value!(ledger_1.records[1], :state, "equal")
    save_file_to_disk!(tab_1)
    sort_collection!(ledger_1, "number")

See also `show_roster!`, `sort_collection!` and `filter_collection!`.

For the assistant.
"""
@document struct RecordTable <: Document
    title::String
    columns::Any
    records::CellVector
    table::Any
end

# The typed title keeps this method apart from the constructors that `@document`
# makes.
function RecordTable(title::AbstractString; columns = String[], records = Any[])
    cells = Cell[Cell(get_stored_value(record)) for record in records]
    record_table = RecordTable(String(title), collect(String, columns), CellVector(cells), nothing, nothing)
    roster = Roster(CollectionItems(extend_reference(EmptyReference(), FieldReferenceStep("records")));
                    columns = record_table.columns, title = record_table.title)
    link_roster!(roster, record_table)
    record_table.table = ArrangementDocument(roster, ArrangementEntry[])
    record_table
end

get_document_title(record_table::RecordTable) = record_table.title

# The pill of the table counts its records.
function get_document_decoration(record_table::RecordTable)
    count = length(record_table.records)
    DocumentDecoration(; icon = :list, counts = [DocumentCount(string(count, count == 1 ? " record" : " records"))])
end

# A verb of the arrangement that is given a record table arranges the rows of its
# roster: the collection at `table.document.rows`.
get_arranged_collection_steps(::RecordTable) =
    (FieldReferenceStep("table"), FieldReferenceStep("document"), FieldReferenceStep("rows"))

# A file keeps the title, the columns and the records; the arrangement and the
# roster are made again by the constructor.
pred_arguments(record_table::RecordTable) =
    (record_table.title,), Pair{Symbol,Any}[:columns => collect(String, record_table.columns),
                                            :records => Any[record for record in record_table.records]]
make_pred_document(::Type{<:RecordTable}, positional, keywords) = RecordTable(positional...; keywords...)
