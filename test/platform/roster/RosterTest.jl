# A roster gathers the items of a source into rows: the rows of a collection, a
# value cell for each column, a facet and a path as keys, the parts of the items
# inside other items, a filter and a sort of the rows, and the table that shows
# them.

using ProjecturedKernel.CellModule: Cell
using ProjecturedPlatform.CollectionModule: CellVector

# A run of a study: a record with a field that a facet reads.
@document struct _RosterRun
    id::Int
    status::String
    delay::Float64
end

# A study, which holds runs.
@document struct _RosterStudy
    name::String
    runs::CellVector
end

RosterModule.get_item_facets(::Type{_RosterRun}) = ["slow" => "whether the run took longer than 0.3"]
# A run that failed says so, and a count of failed runs takes its colour.
ProjecturedPlatform.DomainModule.get_document_decoration(run::_RosterRun) =
    DocumentDecoration(; conditions = run.status == "failed" ? [DocumentCondition(:failed)] : DocumentCondition[])
RosterModule.compute_item_facet(run::_RosterRun, ::Val{:slow}) = run.delay > 0.3

# A record that declares a facet with the name of one of its fields.
@document struct _RosterClash
    status::String
end
RosterModule.get_item_facets(::Type{_RosterClash}) = ["status" => "a facet that a field hides"]

# A source of the runs of studies, one part for each study, that counts how often
# it gathers the runs of each study.
struct _RosterCountingSource
    studies::Any
    gathered::Dict{String,Int}
end
RosterModule.collect_roster_parts(source::_RosterCountingSource, link) = Any[study for study in source.studies]
function RosterModule.collect_roster_items(source::_RosterCountingSource, link, study)
    source.gathered[study.name] = get(source.gathered, study.name, 0) + 1
    RosterItem[RosterItem(run, study) for run in study.runs]
end

function test_roster()
@testset "a roster gathers the items of a source into rows" begin
    make_runs() = CellVector(Cell[Cell(_RosterRun(1, "done", 0.31)), Cell(_RosterRun(2, "failed", 0.12)),
                                  Cell(_RosterRun(3, "done", 0.54))])

    @testset "the rows of a collection, and a value cell for each column" begin
        runs = make_runs()
        roster = Roster(CollectionItems(runs); columns = ["id", "status", "slow"], title = "Runs")
        @test get_document_title(roster) == "Runs"
        @test isempty(roster.rows)          # no link, no rows
        link_roster!(roster, runs)
        rows = roster.rows
        @test length(rows) == 3
        @test [row.values[1] for row in rows] == [1, 2, 3]
        @test [row.values[3] for row in rows] == [true, false, true]
        # A write of one item makes only the value cells of its row out of date.
        first_row, second_row = rows[1], rows[2]
        foreach(row -> foreach(c -> get_cell_at(row.values, c)[], 1:3), rows)
        runs[2].delay = 0.9
        @test !is_cell_valid(get_cell_at(second_row.values, 3))
        @test is_cell_valid(get_cell_at(first_row.values, 3))
        @test second_row.values[3] == true
        # An item that comes in gets a row, and the rows that stay keep theirs.
        push!(runs, _RosterRun(4, "done", 0.05))
        @test length(rows) == 4
        @test rows[1] === first_row && rows[2] === second_row
        @test rows[4].values[1] == 4
        # An item that goes out takes its row.
        deleteat!(runs, 1)
        @test [row.values[1] for row in rows] == [2, 3, 4]
        @test rows[1] === second_row
    end

    @testset "a key: a facet, a path of fields, and within" begin
        runs = make_runs()
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["status"]), runs)
        row = roster.rows[1]
        @test compute_roster_value(row, "slow") == true
        @test compute_roster_value(row, "delay") == 0.31
        @test compute_roster_value(row, "no_such_field") === nothing
        @test compute_roster_value(row, "within") === nothing
        @test first(collect_item_facets(_RosterRun)) == ("slow" => "whether the run took longer than 0.3")
        @test first.(collect_item_facets(_RosterRun)) == ["slow", "type"]
        @test_throws ArgumentError collect_item_facets(_RosterClash)
        # A key of an arrangement is a key of a column, or any other key.
        status = extend_reference(EmptyReference(), FieldReferenceStep("status"))
        slow = extend_reference(EmptyReference(), FieldReferenceStep("slow"))
        @test find_arrangement_key_value(row, status) == "done"
        @test find_arrangement_key_value(row, slow) == true
        @test find_arrangement_key_value(row, EmptyReference()) == Any["done"]
    end

    @testset "the items inside other items, one part for each" begin
        studies = CellVector(Cell[Cell(_RosterStudy("a", make_runs())), Cell(_RosterStudy("b", make_runs()))])
        source = _RosterCountingSource(studies, Dict{String,Int}())
        roster = link_roster!(Roster(source; columns = ["id", "within.name"]), studies)
        rows = roster.rows
        @test [(row.values[1], row.values[2]) for row in rows] ==
              [(1, "a"), (2, "a"), (3, "a"), (1, "b"), (2, "b"), (3, "b")]
        @test source.gathered == Dict("a" => 1, "b" => 1)
        # A run that comes into one study gathers that study again, and no other.
        push!(studies[2].runs, _RosterRun(4, "done", 0.2))
        @test length(rows) == 7
        @test source.gathered == Dict("a" => 1, "b" => 2)

        # ItemsWithin finds the documents of a type inside each item of a source.
        within = link_roster!(Roster(ItemsWithin(CollectionItems(studies), _RosterRun); columns = ["id", "within.name"]),
                              studies)
        @test length(within.rows) == 7
        @test within.rows[7].values[2] == "b"
        @test get_roster_item_type(ItemsWithin(CollectionItems(studies), _RosterRun)) === _RosterRun
    end

    @testset "a filter and a sort of the rows, and the table" begin
        runs = make_runs()
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status", "slow"]), runs)
        arranged = ArrangementDocument(roster, ArrangementEntry[])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        io = print_document(natural, nothing, arranged, PrinterContext())
        function texts(node, found = String[])
            if node isa GraphicsCanvas
                foreach(element -> texts(element, found), node.elements)
            elseif node isa GraphicsViewport
                texts(node.content, found)
            elseif node isa GraphicsText
                push!(found, string(node.text))
            end
            found
        end
        drawn = texts(io.output)
        @test all(header -> header in drawn, ["id", "status", "slow"])
        @test filter(t -> t in ("1", "2", "3"), drawn) == ["1", "2", "3"]
        rows_at = extend_reference(EmptyReference(), FieldReferenceStep("rows"))
        status = extend_reference(EmptyReference(), FieldReferenceStep("status"))
        slow = extend_reference(EmptyReference(), FieldReferenceStep("slow"))
        push!(arranged.entries, ArrangementEntry(rows_at,
            Any[ArrangementFilter(Any[ArrangementCondition(status, :equal, "done")]),
                ArrangementSort(Any[ArrangementSortKey(slow, :ascending), ArrangementSortKey(
                    extend_reference(EmptyReference(), FieldReferenceStep("id")), :descending)])]))
        drawn = texts(io.output)
        @test "2 of 3" in drawn
        @test filter(t -> t in ("1", "2", "3"), drawn) == ["3", "1"]
        # A change of an item reaches the table through its row.
        runs[3].status = "failed"
        drawn = texts(io.output)
        @test "1 of 3" in drawn
        @test filter(t -> t in ("1", "2", "3"), drawn) == ["1"]
    end

    @testset "a roster counts its rows, and an arrangement counts what it shows, in the colour they share" begin
        runs = make_runs()
        roster = Roster(CollectionItems(runs); columns = ["id", "status"], title = "Runs")
        counts(document) = [(count.text, count.role) for count in get_document_decoration(document).counts]
        # No link, no rows, and no count.
        @test isempty(counts(roster)) && get_document_decoration(roster).icon === :table
        link_roster!(roster, runs)
        # Two runs are done and one failed: the count has no colour of its own.
        @test counts(roster) == [("3", nothing)]
        status = extend_reference(EmptyReference(), FieldReferenceStep("status"))
        rows_at = extend_reference(EmptyReference(), FieldReferenceStep("rows"))
        failed = ArrangementDocument(roster, ArrangementEntry[ArrangementEntry(rows_at,
            Any[ArrangementFilter(Any[ArrangementCondition(status, :equal, "failed")])])])
        decoration = get_document_decoration(failed)
        @test counts(failed) == [("1", :error)]
        @test any(condition -> condition.name === :filtered, decoration.conditions)
        # The counts follow the items: a second failed run, then none.
        runs[1].status = "failed"
        @test counts(failed) == [("2", :error)]
        runs[1].status = "done"
        runs[2].status = "done"
        @test isempty(counts(failed)) && counts(roster) == [("3", nothing)]
        # An arrangement with no entry counts all the rows.
        @test counts(ArrangementDocument(roster, ArrangementEntry[])) == [("3", nothing)]
    end

    # The table reads the cell of each value when it prints. A value of text has a
    # cell that holds its label, so a new value draws only the text of its label.
    @testset "a new value of text draws its label again, and no other cell" begin
        runs = make_runs()
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"]), runs)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        io = print_document(natural, nothing, roster, PrinterContext())
        function texts(node, found = GraphicsText[])
            if node isa GraphicsCanvas
                foreach(element -> texts(element, found), node.elements)
            elseif node isa GraphicsViewport
                texts(node.content, found)
            elseif node isa GraphicsText
                push!(found, node)
            end
            found
        end
        find_text(text) = only(t for t in texts(io.output) if string(t.text) == text)
        id = find_text("1")
        @test string.(getproperty.(texts(io.output), :text)) == ["id", "status", "1", "done", "2", "failed", "3", "done"]
        runs[2].status = "stopped"
        @test string.(getproperty.(texts(io.output), :text)) == ["id", "status", "1", "done", "2", "stopped", "3", "done"]
        @test find_text("1") === id
    end
end
end
