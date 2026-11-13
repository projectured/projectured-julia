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

    @testset "two equal records are one row" begin
        ledger = RecordTable("Ledger"; columns = ["state"],
                             records = [(state = "waiting",), (state = "waiting",)])
        @test length(ledger.records) == 2
        @test length(_record_table_rows(ledger)) == 1
    end
end
end
