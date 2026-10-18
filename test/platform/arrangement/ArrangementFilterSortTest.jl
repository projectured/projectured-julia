# The filter and the sort that a person places at a collection: the items that
# show, their order, the path of a shown item back to its item, and an entry
# inside an item of a filtered collection, by its path in the source and by a
# pattern.

using ProjecturedKernel.CellModule: Cell, mark_computation_provisional!
using ProjecturedPlatform.CollectionModule: CellVector

# A run of a study, a record whose events are a collection of their own.
@document struct _ArrangementRun
    id::Int
    status::String
    delay::Float64
    events::CellVector
end

# A study, a record whose runs are a collection.
@document struct _ArrangementStudy
    runs::CellVector
end

function test_arrangement_filter_sort()
@testset "a filter and a sort placed at a collection" begin
    rec = RecursiveProjection(make_arranged_dispatch(TypeDispatchingProjection(Pair{Type,Any}[
        ArrangementDocument => ArrangingProjection(),
        CellVector => CopyingProjection(),
        _ArrangementRun => CopyingProjection(),
        _ArrangementStudy => CopyingProjection(),
        Any => IdentityProjection()])))
    vector(values) = CellVector(Cell[Cell(v) for v in values])
    element(i) = extend_reference(EmptyReference(), ElementReferenceStep(i))
    field(name) = extend_reference(EmptyReference(), FieldReferenceStep(name))
    condition(key, operator, value) = ArrangementCondition(key, operator, value)
    filter_of(conditions...) = ArrangementFilter(Any[conditions...])
    sort_of(keys...) = ArrangementSort(Any[keys...])

    @testset "a vector of values" begin
        values = vector([3, 1, 4, 1, 5])
        arranged = ArrangementDocument(values, ArrangementEntry[])
        io = print_document(rec, nothing, arranged, PrinterContext())
        shown() = collect(io.output)
        push!(arranged.entries, ArrangementEntry(EmptyReference(),
            Any[filter_of(condition(EmptyReference(), :greater, 1)),
                sort_of(ArrangementSortKey(EmptyReference(), :descending))]))
        @test shown() == [5, 4, 3]
        # A value of a condition is a cell: an edit of it changes the items.
        filter = arranged.entries[1].projections[1]
        filter.conditions[1].value = 3
        @test shown() == [5, 4]
        # A shown item maps back to its item: 5 is the fifth value.
        backward = map_reference_backward(rec, io, element(1))
        @test strip_reference_types(backward) ==
              ConcreteReference(FieldReferenceStep("document"), element(5))
    end

    @testset "a sort keeps its last order while a key is still to come" begin
        # Each value is the answer of a task, or the default 0 while the task reads.
        answers = [Cell(value) for value in (3, 1, 2)]
        values = CellVector(Cell[Cell(@computation (given = answers[i][];
                                                     given === nothing ? (mark_computation_provisional!(); 0) :
                                                                         given))
                                 for i in 1:3])
        arranged = ArrangementDocument(values, ArrangementEntry[])
        io = print_document(rec, nothing, arranged, PrinterContext())
        shown() = collect(io.output)
        push!(arranged.entries, ArrangementEntry(EmptyReference(),
            Any[sort_of(ArrangementSortKey(EmptyReference(), :ascending))]))
        @test shown() == [1, 2, 3]
        # The first value is read again: its default 0 shows, in the last order.
        answers[1][] = nothing
        @test shown() == [1, 2, 0]
        # Its new answer comes, and the sort orders it.
        answers[1][] = 0
        @test shown() == [0, 1, 2]
    end

    runs = [_ArrangementRun(1, "done", 0.31, vector(["a", "b"])),
            _ArrangementRun(2, "failed", 0.12, vector(["c"])),
            _ArrangementRun(3, "done", 0.54, vector(["d", "e", "f"])),
            _ArrangementRun(4, "done", 0.08, vector(["g", "h"]))]
    @testset "a vector of records" begin
        # A copy of a record keeps the fields of its print, so each check prints
        # the arrangement again.
        study = _ArrangementStudy(Any[run for run in runs])
        arranged = ArrangementDocument(study, ArrangementEntry[])
        shown() = print_document(rec, nothing, arranged, PrinterContext()).output.runs
        ids() = [run.id for run in shown()]
        @test ids() == [1, 2, 3, 4]
        push!(arranged.entries, ArrangementEntry(field("runs"),
            Any[filter_of(condition(field("status"), :not_equal, "failed")),
                sort_of(ArrangementSortKey(field("delay"), :ascending))]))
        @test ids() == [4, 1, 3]
        # Two keys: the second orders the items that the first finds equal.
        arranged.entries[1].projections[2] = sort_of(ArrangementSortKey(field("status"), :ascending),
                                                     ArrangementSortKey(field("id"), :descending))
        @test ids() == [4, 3, 1]

        # An entry inside a picked item, by its path in the source: the events
        # of run 3, which shows second.
        events_of_3 = extend_reference(EmptyReference(), FieldReferenceStep("runs"), ElementReferenceStep(3),
                                       FieldReferenceStep("events"))
        push!(arranged.entries, ArrangementEntry(events_of_3,
            Any[filter_of(condition(EmptyReference(), :not_equal, "e"))]))
        events(run_id) = [e for e in only(run for run in shown() if run.id == run_id).events]
        @test events(3) == ["d", "f"]
        @test events(1) == ["a", "b"]
        # A pattern places a sort at the events of every run. A path wins over a
        # pattern, so run 3 keeps the filter of its own entry.
        push!(arranged.entries, ArrangementEntry(parse_reference_pattern("runs[*].events"),
            Any[sort_of(ArrangementSortKey(EmptyReference(), :descending))]))
        @test events(1) == ["b", "a"]
        @test events(4) == ["h", "g"]
        @test events(3) == ["d", "f"]
    end

    @testset "a table: the rows of a vector of named tuples, by a column" begin
        rows = CellVector(Cell[Cell((name = "pear", price = 3.0)), Cell((name = "apple", price = 1.0)),
                               Cell((name = "fig", price = 2.5))])
        @test is_table([row for row in rows])
        arranged = ArrangementDocument(rows, ArrangementEntry[])
        io = print_document(rec, nothing, arranged, PrinterContext())
        names() = [row.name for row in io.output]
        push!(arranged.entries, ArrangementEntry(EmptyReference(),
            Any[filter_of(condition(field("name"), :contains, "P")),
                sort_of(ArrangementSortKey(field("price"), :ascending))]))
        @test names() == ["apple", "pear"]
    end

    @testset "values of different kinds, and a missing value" begin
        values = vector(Any["b", 2, nothing, 1.5, "a"])
        arranged = ArrangementDocument(values, ArrangementEntry[])
        io = print_document(rec, nothing, arranged, PrinterContext())
        push!(arranged.entries, ArrangementEntry(EmptyReference(),
            Any[sort_of(ArrangementSortKey(EmptyReference(), :ascending))]))
        @test isequal(collect(io.output), Any[1.5, 2, "a", "b", nothing])
        arranged.entries[1].projections[1] = sort_of(ArrangementSortKey(EmptyReference(), :descending))
        @test isequal(collect(io.output), Any["b", "a", 2, 1.5, nothing])
    end
end
end
