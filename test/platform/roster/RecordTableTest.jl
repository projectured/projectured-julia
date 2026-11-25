# A table of records that a file keeps: a new record is a new row, a write of one
# field makes a new row for that record only, a `.pred` file keeps the title, the
# columns and the records, and two equal records are one row.

using Test

_record_table_rows(record_table) = collect(record_table.table.document.rows)

function test_record_table()
@testset "RecordTable" begin

    @testset "a new record is a new row, with the values of its columns" begin
        ledger = RecordTable("Ledger"; columns = ["number", "state"],
                             records = [(number = 1, state = "waiting"), (number = 2, state = "waiting")])
        @test get_document_title(ledger) == "Ledger"
        @test length(_record_table_rows(ledger)) == 2
        push!(ledger.records, (number = 3, state = "waiting"))
        rows = _record_table_rows(ledger)
        @test length(rows) == 3
        @test [row.values[1] for row in rows] == [1, 2, 3]
        @test rows[3].item == (number = 3, state = "waiting")
        @test only(get_document_decoration(ledger).counts).text == "3 records"
    end

    @testset "a write of one field makes a new row for that record only" begin
        ledger = RecordTable("Ledger"; columns = ["number", "state"],
                             records = [(number = 1, state = "waiting"), (number = 2, state = "waiting")])
        before = _record_table_rows(ledger)
        evaluate_operation((; document = ledger),
            ReplaceReferencedValueOperation(nothing, @reference(ledger, records[2].state), "equal"))
        @test ledger.records[2] == (number = 2, state = "equal")
        after = _record_table_rows(ledger)
        @test after[1] === before[1]
        @test after[2] !== before[2]
        @test after[2].values == Any[2, "equal"]
    end

    @testset "a file keeps the title, the columns and the records" begin
        ledger = RecordTable("Measured commits"; columns = ["number", "commit", "state"],
                             records = [(number = 1, commit = "fd436d7", state = "waiting"),
                                        (number = 2, commit = "0f21330", state = "event")])
        loaded = parse_pred_text(print_pred_text(ledger))
        @test loaded isa RecordTable
        @test loaded.title == "Measured commits"
        @test loaded.columns == ["number", "commit", "state"]
        @test collect(loaded.records) == collect(ledger.records)
        # The loaded table makes its roster again, linked to itself.
        @test length(_record_table_rows(loaded)) == 2
    end

    @testset "a verb of the arrangement finds the rows of the roster" begin
        ledger = RecordTable("Ledger"; columns = ["number"], records = [(number = 1,)])
        @test get_arranged_collection_steps(ledger) ==
            (FieldReferenceStep("table"), FieldReferenceStep("document"), FieldReferenceStep("rows"))
        @test evaluate_reference(ledger, extend_reference(EmptyReference(), get_arranged_collection_steps(ledger)...)) ===
            ledger.table.document.rows
    end

    @testset "the page of a table in an editor" begin
        ledger = RecordTable("Ledger"; columns = ["number", "state"],
                             records = [(number = 1, state = "waiting"), (number = 2, state = "event"),
                                        (number = 3, state = "event")])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(ledger, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        # The line counts the records, and the header names the columns.
        texts = _arrangement_texts(backend)
        @test "3 records" in texts
        @test all(text -> text in texts, ["number", "state", "1", "2", "3", "waiting", "event"])

        # A click on the first cell of a row opens the record at its place in the table.
        (x, y) = _arrangement_place(backend, "2")
        _arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
        click = MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0)
        opened = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
        opened isa WrappingOperation && (opened = get_wrapped_operation(opened))
        @test opened isa OpenPageOperation
        steps = get_reference_steps(strip_reference_types(opened.reference))
        @test steps[end - 1:end] == [FieldReferenceStep("records"), ElementReferenceStep(2)]

        # The write of one field of a record replaces the record in its slot, the row
        # shows it, and one undo puts it back.
        buffer = find_undo_buffer(editor.document)
        part = get_edited_document(ReferencedDocument(editor.document, EmptyReference()))
        @test get_document(part) === ledger
        before = length(buffer.undo_entries)
        replace_referenced_value!(part.records[2], :state, "equal"; editor)
        frame!()
        @test ledger.records[2] == (number = 2, state = "equal")
        @test "equal" in _arrangement_texts(backend)
        @test length(buffer.undo_entries) == before + 1
        evaluate_operation(editor, UndoOperation(buffer))
        frame!()
        @test ledger.records[2] == (number = 2, state = "event")

        # A filter keeps the rows of the events, and the line still counts every record.
        filter_collection!(part, "state" => ==("event"); editor)
        frame!()
        texts = _arrangement_texts(backend)
        @test !("waiting" in texts) && "event" in texts
        @test "3 records" in texts
    end

    @testset "a date in a record shows, changes, sorts and saves" begin
        Dates = ProjecturedKernel.DocumentModule.load_standard_library!(:Dates)
        ledger = RecordTable("Defects"; columns = ["number", "repaired_on"],
                             records = [(number = 21, repaired_on = Dates.Date(2026, 11, 25)),
                                        (number = 23, repaired_on = nothing),
                                        (number = 24, repaired_on = Dates.Date(2026, 11, 24)),
                                        (number = 25, repaired_on = nothing)])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(ledger, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = false, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        @test all(text -> text in _arrangement_texts(backend), ["2026-11-25", "2026-11-24"])

        # The date of a record changes as any other value does, and its row shows it.
        part = get_edited_document(ReferencedDocument(editor.document, EmptyReference()))
        replace_referenced_value!(part.records[2], :repaired_on, Dates.Date(2026, 12, 1); editor)
        frame!()
        @test ledger.records[2].repaired_on == Dates.Date(2026, 12, 1)
        @test "2026-12-01" in _arrangement_texts(backend)

        # A sort orders the drawn rows by their dates, and a record with no date
        # goes last.
        sort_collection!(part, "repaired_on"; editor)
        frame!()
        texts = _arrangement_texts(backend)
        places = [findfirst(==(string(number)), texts) for number in (24, 21, 23, 25)]
        @test all(!isnothing, places) && issorted(places)

        # The file keeps each date with the name of its module.
        text = print_pred_text(ledger)
        @test occursin("repaired_on = Dates.Date(\"2026-12-01\")", text)
        @test collect(parse_pred_text(text).records) == collect(ledger.records)
    end

    @testset "two equal records are one row" begin
        ledger = RecordTable("Ledger"; columns = ["state"],
                             records = [(state = "waiting",), (state = "waiting",)])
        @test length(ledger.records) == 2
        @test length(_record_table_rows(ledger)) == 1
    end
end
end
