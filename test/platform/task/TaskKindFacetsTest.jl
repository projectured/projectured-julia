# The columns of the kind of a task as values of the task in a roster of tasks:
# a filter and a sort by a column of the kind, `expected_result` before and after
# a task ends, and the label of a header with a space for each underscore.

# A kind of task with columns: the suite and the test it runs, and the code that
# its result is expected to take.
struct _KindFacetTask <: AbstractTask
    suite::String
    test::String
    script::String
end
TaskModule.get_result_codes(::_KindFacetTask) = TEST_RESULT_CODES
TaskModule.format_task_parameters(task::_KindFacetTask) = task.suite * "/" * task.test
TaskModule.get_task_columns(::_KindFacetTask) = ["suite" => 1, "test" => 2, "expected_result" => 1]
TaskModule.format_task_column(task::_KindFacetTask, column::AbstractString) =
    column == "suite" ? task.suite : column == "test" ? task.test : column == "expected_result" ? "PASS" : ""

struct _KindFacetResult <: TaskResult
    task::_KindFacetTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

function TaskModule.start_task(task::_KindFacetTask; on_finish = nothing)
    execution = TaskExecution(task)
    finish = function (process, cancelled, elapsed)
        code = cancelled ? "CANCEL" : process.exitcode == 0 ? "PASS" : "FAIL"
        finish_task_execution!(execution, _KindFacetResult(task, code, "PASS", nothing, elapsed); finish = on_finish)
    end
    start_process_task!(execution, `sh -c $(task.script)`; finish, on_finish)
end

function test_task_kind_facets()
@testset "the columns of the kind of a task are values of the task" begin
    make_documents() = [TaskDocument(_KindFacetTask("net", "queue2", "exit 0")),
                        TaskDocument(_KindFacetTask("net", "queue10", "exit 1")),
                        TaskDocument(_KindFacetTask("disk", "alpha", "exit 0"))]
    function make_editor()
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        (editor, backend)
    end
    # The names of the tasks that the roster shows, in their order.
    shown(rows) = [first(split(line, " | ")) for line in split(string(describe_roster(rows)), '\n')[3:end]]
    show_tasks(documents; columns = ["name", "test", "expected_result", "expected"], kwargs...) =
        show_roster!(CollectionItems(CellVector(Cell[Cell(document) for document in documents]));
                     title = "Tasks", columns, kwargs..., editor = first(make_editor()))

    @testset "a kind column is a facet, a declared facet wins, and a field wins over a column" begin
        documents = make_documents()
        task = getfield(documents[1], :task)[]
        @test has_item_facet(documents[1], "test") && has_item_facet(documents[1], "expected_result")
        @test !has_item_facet(documents[1], "missing") && !has_item_facet(TaskDocument(_TaskGroupProbeTask("a", "exit 0")), "test")
        @test get_item_facet_type(documents[1]) === TaskModule.TaskKindFacets{_KindFacetTask}
        @test get_item_facet_type(TaskDocument(_TaskGroupProbeTask("a", "exit 0"))) !== get_item_facet_type(documents[1])
        @test compute_item_facet(documents[1], Val(:test)) == "queue2"
        @test compute_item_facet(documents[1], Val(:type)) == "TaskDocument"
        @test compute_item_facet(documents[1], Val(:expected_result)) == "PASS"
        @test compute_item_facet(documents[1], Val(:expected)) === nothing
        # A column named as a field of the document is the field, not a facet.
        @test !has_item_facet(TaskDocument(TaskGroup([task]; name = "g")), "group")
    end

    @testset "a filter and a sort by a column of the kind" begin
        documents = make_documents()
        rows = show_tasks(documents; filter = Any["test" => "= queue2"])
        @test shown(rows) == ["net/queue2"]
        rows = show_tasks(documents; sort = Any["test"])
        @test shown(rows) == ["disk/alpha", "net/queue10", "net/queue2"]
    end

    @testset "expected_result holds before and after a task ends, and expected is true or false" begin
        documents = make_documents()
        rows = show_tasks(documents; filter = Any["expected_result" => "= PASS"])
        @test length(shown(rows)) == 3
        @test all(document -> compute_item_facet(document, Val(:state)) == "pending", documents)
        foreach(document -> wait_task_document(start_task!(document)), documents)
        @test length(shown(rows)) == 3
        @test [compute_item_facet(document, Val(:state)) for document in documents] == ["PASS", "FAIL", "PASS"]
        @test [compute_item_facet(document, Val(:expected)) for document in documents] == [true, false, true]
        @test all(document -> compute_item_facet(document, Val(:expected_result)) == "PASS", documents)
        @test all(document -> compute_item_facet(document, Val(:elapsed)) >= 0, documents)
        @test any(document -> compute_item_facet(document, Val(:process)) !== nothing, documents)
        fails = show_tasks(documents; filter = Any["expected" => "= false"])
        @test shown(fails) == ["net/queue10"]
    end

    @testset "elapsed is nothing before a task ends" begin
        document = TaskDocument(_KindFacetTask("net", "slow", "sleep 5"))
        start_task!(document)
        @test compute_item_facet(document, Val(:elapsed)) === nothing
        @test compute_item_facet(document, Val(:state)) == "running"
        stop_task!(document)
        wait_task_document(document)
    end

    @testset "the header shows the key with a space for each underscore" begin
        @test format_roster_column_label("expected_result") == "expected result"
        @test format_roster_column_label("process_id") == "process id"
        @test format_roster_column_label("name") == "name"
        (editor, backend) = make_editor()
        rows = show_roster!(CollectionItems(CellVector(Cell[Cell(document) for document in make_documents()]));
                            title = "Tasks", columns = ["name", "expected_result"], editor)
        run_frame!(editor)
        texts = _arrangement_texts(backend)
        @test "expected result" in texts && !("expected_result" in texts)
        arranged = show_roster!(CollectionItems(CellVector(Cell[Cell(document) for document in make_documents()]));
                                title = "Arranged", columns = ["name", "expected_result"],
                                filter = Any["name" => "/net/"], editor)
        drain_operations!(editor); run_frame!(editor)
        @test "expected result" in _arrangement_texts(backend)
    end
end
end
