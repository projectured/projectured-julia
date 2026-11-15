# Who started each row of the task list, and a task alone as a row. A starter is a
# plain value that the evaluation binds; the start of a row records it. A task
# with no group is a row of its own: it stops, runs again with no group, closes and
# keeps its place and its identifier. The code of a call that goes to a running
# loop keeps its starter there, and a press that a frame reads names the person.
# The Tasks pane is an arrangement of a roster of the rows, which filters and sorts
# by who started them, and one line of buttons acts on the selected row.

# A program that prints its name, or runs `script`.
_work_item_program(name, script = "echo $name") =
    ProgramTask(["sh", "-c", script]; working_directory = tempdir(), name)

# The starter of an assistant of the test, with the id of a tool call.
const _WORK_ITEM_ASSISTANT = WorkStarter(:assistant; identifier = "A9", name = "Assistant 9", tool_call = "tu_7")

# An editor that shows the Tasks pane in a tab, so the list of its session is the
# list of that tab, and the list.
function _work_item_editor()
    list = TaskGroupList()
    editor = Editor(PaneTree(PaneGroup(PaneTab[PaneTab("Tasks", list)])),
                    NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)); backend = HeadlessBackend(),
                    devices = Device[])
    @assert get_session_task_group_list(; editor) === list
    (editor, list)
end

# An operation that records the starter of the evaluation that applies it.
struct _WorkItemStarterProbe <: Operation
    seen::Base.RefValue{Any}
end

ProjecturedKernel.OperationModule.evaluate_operation(::Any, probe::_WorkItemStarterProbe) =
    (probe.seen[] = find_evaluation_starter(); nothing)

# Run the loop of `editor` on this task while `driver` runs on a task of its own,
# then quit the loop; answer what `driver` answered.
function _work_item_run_loop(driver, editor)
    answer = Ref{Any}(nothing)
    task = @async try
        # The driver calls the loop that runs, so its calls are posts.
        timedwait(() -> is_editor_loop_running(editor), 30.0; pollint = 0.01)
        answer[] = driver()
    finally
        post_operation!(editor, QuitEditorOperation())
    end
    run_editor!(editor)
    wait(task)
    answer[]
end

function test_task_work_item()
    @testset "who started a row, and a task alone" begin
        @testset "a starter is a plain value that the evaluation binds" begin
            person = WorkStarter(:person)
            @test person == WorkStarter(:person, "", "", "")
            @test_throws ArgumentError WorkStarter(:robot)
            @test describe_work_starter(person) == "the person"
            @test describe_work_starter(_WORK_ITEM_ASSISTANT) == "Assistant 9"
            @test describe_work_starter(WorkStarter(:client; name = "MCP client")) == "MCP client"
            @test describe_work_starter(nothing) == ""
            # A table shows the words, and its filter and its sort read them.
            @test format_roster_value(_WORK_ITEM_ASSISTANT) == "Assistant 9"
            @test get_arrangement_value(_WORK_ITEM_ASSISTANT) == "Assistant 9"
            # With no starter bound, the work is the work of the person.
            @test find_evaluation_starter() === nothing
            @test get_work_starter() == person
            @test run_with_evaluation_starter(get_work_starter, _WORK_ITEM_ASSISTANT) == _WORK_ITEM_ASSISTANT
            # A task that the code starts keeps the starter.
            @test run_with_evaluation_starter(() -> fetch(Threads.@spawn get_work_starter()),
                                              _WORK_ITEM_ASSISTANT) == _WORK_ITEM_ASSISTANT
        end

        @testset "a task alone is a row: it stops, runs again, closes and keeps its identifier" begin
            editor, list = _work_item_editor()
            task = run_with_evaluation_starter(_WORK_ITEM_ASSISTANT) do
                run_tasks!(_work_item_program("alpha"); editor)
            end
            identifier = get_work_item_identifier(task)
            @test occursin(r"^T\d+$", identifier)
            @test describe_work_item_kind(task, 1) == "task" && describe_work_item_kind(task, 2) == "tasks"
            @test get_document_title(task) == "alpha"
            @test find_task_document_group(task) === nothing
            @test only(collect_work_items(list)) === task
            @test get_work_item_starter(task) == _WORK_ITEM_ASSISTANT
            @test startswith(string(wait_for_tasks!(task; timeout = 20, editor)), "Ended: DONE")
            @test string(get_task_output(task; editor)) == "alpha"
            @test startswith(describe_work_item(task), "alpha — DONE")
            @test occursin(identifier * " · alpha · task", string(list_task_groups(; editor)))
            @test find_task_group(identifier; editor) === task
            @test find_navigator_address(list, task) == extend_reference(EmptyReference(),
                FieldReferenceStep("groups"), RangeReferenceStep(0, 1))

            # A row that the person starts names the person, and a stop ends it.
            slow = run_tasks!(_work_item_program("slow", "sleep 30"); editor)
            @test get_work_item_starter(slow) == WorkStarter(:person)
            @test get_work_item_identifier(slow) != identifier
            @test string(stop_tasks!(slow; editor)) == "Stopping the task " * get_work_item_identifier(slow) * "."
            @test occursin("CANCEL", string(wait_for_tasks!(slow; timeout = 20, editor)))

            # A close keeps the place and the identifier of the row.
            @test string(close_task_group!(task; editor)) == "Closed the task " * identifier * "."
            @test list.groups[1] isa ClosedTaskGroup
            @test get_work_item_identifier(list.groups[1]) == identifier
            @test !any(item -> item === task, collect_work_items(list))

            # A run again has no group: the row comes back into its place, with its
            # identifier and the starter of its first start.
            @test rerun_tasks!(task; editor) === task
            @test list.groups[1] === task
            @test get_work_item_identifier(task) == identifier
            @test get_work_item_starter(task) == _WORK_ITEM_ASSISTANT
            wait_for_tasks!(task; timeout = 20, editor)
            @test length(getfield(task, :executions)[]) == 2

            # A program that can not start adds no row.
            count = length(list.groups)
            @test_throws Exception run_tasks!(ProgramTask(["true"]; working_directory = "/no/such/folder"); editor)
            @test length(list.groups) == count
        end

        @testset "the page of a task alone runs it again with no group, and the Tasks pane names who started it" begin
            editor, list = _work_item_editor()
            task = run_with_evaluation_starter(() -> run_tasks!(_work_item_program("beta"); editor),
                                               _WORK_ITEM_ASSISTANT)
            wait_for_tasks!(task; timeout = 20, editor)
            projection, iomap = _print_task_view(task)
            words = [t[3] for t in _collect_task_view_texts(iomap.output)]
            @test get_work_item_identifier(task) in words
            @test "started by Assistant 9" in words
            operation = _press_task_page(projection, iomap, _find_task_page_text(iomap, "Run again"))
            operation.action.callback(editor)
            wait_for_tasks!(task; timeout = 20, editor)
            @test length(getfield(task, :executions)[]) == 2
            @test only(collect_work_items(list)) === task

            # The pane has a column of who started each row.
            group = wrap_task_group_document(TaskGroup([_work_item_program("gamma")]; name = "pressed", jobs = 1))
            run_with_evaluation_editor(() -> start_task_group_document!(group), editor)
            wait_for_task_group!(editor, group)
            @test get_work_item_starter(group) == WorkStarter(:person)
            words = [t[3] for t in _collect_task_view_texts(last(_print_task_view(list; height = 600)).output)]
            @test "started by" in words && "Assistant 9" in words && "the person" in words

            # An arrangement of the rows filters and sorts them by who started them.
            items = collect_work_items(list)
            key = extend_reference(EmptyReference(), FieldReferenceStep("started_by"))
            kept = compute_filter_rows(ArrangementFilter(Any[ArrangementCondition(key, :equal, "the person")]), items)
            @test [items[i] for i in kept] == Any[group]
            order = compute_sort_rows(ArrangementSort(Any[ArrangementSortKey(key, :descending)]), items)
            @test [items[i] for i in order] == Any[group, task]
        end

        @testset "a press that a frame reads names the person, whatever the code that drives the frame" begin
            group = wrap_task_group_document(TaskGroup([_work_item_program("delta")]; name = "press", jobs = 1);
                                             title = "the press")
            backend = HeadlessBackend()
            editor = build_editor(group, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                  backend, devices = Device[Keyboard(), Mouse(), Display()],
                                  window = false, tabs = false, appearance = false, settings = false)
            run_frame!(editor)
            texts = _collect_task_view_texts(last(rendered_output(backend)))
            index = findfirst(entry -> entry[3] == "Run all", texts)
            @test index !== nothing
            (x, y, _) = texts[index]
            push_event!(backend, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0))
            run_with_evaluation_starter(() -> run_frame!(editor), _WORK_ITEM_ASSISTANT)
            @test get_work_item_starter(group) == WorkStarter(:person)
            wait_for_task_group!(editor, group)
        end

        @testset "the code of a call that goes to a running loop keeps its starter there" begin
            editor, list = _work_item_editor()
            probe = _WorkItemStarterProbe(Ref{Any}(:unset))
            outer = WorkStarter(:client; name = "the caller of the loop")
            (group, posted) = run_with_evaluation_starter(outer) do
                _work_item_run_loop(editor) do
                    group = run_with_evaluation_starter(_WORK_ITEM_ASSISTANT) do
                        run_tasks!(TaskGroup([_work_item_program("epsilon")]; name = "posted", jobs = 1); editor)
                    end
                    post_operation!(editor, probe)
                    (group, run_on_editor_task!(find_evaluation_starter, editor))
                end
            end
            # The group that the call started in the drain names the starter of the call.
            @test group isa TaskGroupDocument
            @test get_work_item_starter(group) == _WORK_ITEM_ASSISTANT
            @test any(item -> item === group, collect_work_items(list))
            # A call keeps the starter of the code that posted it; the loop binds none
            # for an operation that it applies itself.
            @test posted == outer
            @test probe.seen[] === nothing
            wait_task_group(get_task_group(group))
        end
    end
end

# The pane of `list` printed alone, and the place of each word that it draws.
function _work_item_list_view(list)
    projection, iomap = _print_task_view(list; height = 600)
    (projection, iomap, _collect_task_view_texts(iomap.output))
end

# What a press on the first drawn `text` of the pane of `list` answers.
function _work_item_list_press(list, text; count = 1)
    projection, iomap, texts = _work_item_list_view(list)
    (x, y, _) = first(t for t in texts if t[3] == text)
    read_intent(projection, iomap, MouseClick(:left, x + 2, y + 2, count, ModifierKeys(); time = 0.0))
end

# The items of the rows of the table of `list` that its arrangement shows, in order.
function _work_item_shown_items(list)
    found = find_arranged_collection(list, extend_reference(EmptyReference(), FieldReferenceStep("table"),
                                                            FieldReferenceStep("document"), FieldReferenceStep("rows")))
    Any[peek(getfield(row, :item)) for row in collect_shown_items(found.entry, found.items) if row isa RosterRow]
end

# The table of `list` with one entry of an arrangement at its rows.
function _work_item_arrange!(list; options...)
    entries = list.table.entries
    foreach(_ -> pop!(entries), 1:length(entries))
    push!(entries, make_arrangement_entry(extend_reference(EmptyReference(), FieldReferenceStep("rows")); options...))
    list
end

# The operations inside `operation`, a compound or one.
_work_item_operations(operation) =
    operation isa CompoundOperation ? reduce(vcat, map(_work_item_operations, operation.operations); init = Any[]) :
    Any[operation]

function test_task_list_pane()
    @testset "the Tasks pane is an arrangement of a roster of its rows" begin
        editor, list = _work_item_editor()
        assistant_task = run_with_evaluation_starter(() -> run_tasks!(_work_item_program("alpha"); editor),
                                                     _WORK_ITEM_ASSISTANT)
        person_group = wrap_task_group_document(TaskGroup([_work_item_program("beta", "exit 1")]; name = "pressed",
                                                          jobs = 1); title = "the group of the person")
        run_with_evaluation_editor(() -> start_task_group_document!(person_group), editor)
        slow = run_tasks!(_work_item_program("slow", "sleep 30"); editor)
        wait_for_tasks!(assistant_task; timeout = 20, editor)
        wait_for_task_group!(editor, person_group)

        @testset "the rows are the open rows, newest first, and the title of a row opens its page" begin
            @test _work_item_shown_items(list) == Any[slow, person_group, assistant_task]
            words = [t[3] for t in last(_work_item_list_view(list))]
            @test all(in(words), ("title", "identifier", "started by", "state", "the group of the person",
                                  "Assistant 9", "the person", "task", "pressed"))
            # The title is the link of the row: it opens the item at its place in the list.
            opened = _work_item_list_press(list, "the group of the person")
            @test typeof(opened) == OpenPageOperation
            @test opened.document === nothing
            @test evaluate_reference(list, opened.reference) === person_group
        end

        @testset "the filter keeps only the rows of the person, and a sort orders by who started them" begin
            _work_item_arrange!(list; filter = ["started_by" => ==("the person")])
            @test _work_item_shown_items(list) == Any[slow, person_group]
            words = [t[3] for t in last(_work_item_list_view(list))]
            @test "the group of the person" in words && !("Assistant 9" in words)
            _work_item_arrange!(list; sort = ["started_by" => :descending, "identifier"])
            shown = _work_item_shown_items(list)
            @test shown[3] === assistant_task && Set(shown[1:2]) == Set(Any[slow, person_group])
            _work_item_arrange!(list; sort = ["started_by"])
            @test first(_work_item_shown_items(list)) === assistant_task
            foreach(_ -> pop!(list.table.entries), 1:length(list.table.entries))
        end

        @testset "a press on a row selects it, and the line of buttons stops, runs again and closes it" begin
            identifier = get_work_item_identifier(slow)
            pressed = _work_item_list_press(list, identifier)
            writes = [get_wrapped_operation(operation) for operation in _work_item_operations(pressed)
                      if operation isa ReplaceViewStateOperation]
            @test any(write -> write isa ReplaceReferencedValueOperation && write.value == identifier, writes)
            foreach(write -> evaluate_operation(nothing, write), writes)
            @test getfield(list, :selected)[] == identifier
            @test list.table.document.marked === slow
            # Stop stops the selected row, and its row stays.
            _work_item_list_press(list, "Stop").action.callback(editor)
            @test occursin("CANCEL", string(wait_for_tasks!(slow; timeout = 20, editor)))
            # Run again runs the selected task alone again, with no group.
            _work_item_list_press(list, "Run again").action.callback(editor)
            @test length(getfield(slow, :executions)[]) == 2
            stop_work_item!(slow)
            wait_for_tasks!(slow; timeout = 20, editor)
            # Close closes it: its closed row keeps its place, and no row is selected.
            _work_item_list_press(list, "Close").action.callback(editor)
            closed = list.groups[findfirst(item -> get_work_item_identifier(item) == identifier, collect(list.groups))]
            @test closed isa ClosedTaskGroup && getfield(closed, :kind)[] == "task"
            @test !any(item -> item === slow, _work_item_shown_items(list))
            @test list.table.document.marked === nothing
            # The page of the closed task says that a task closed.
            words = [t[3] for t in _collect_task_view_texts(last(_print_task_view(closed)).output)]
            @test "This task is closed. Its output is gone." in words
            # The selected group runs its unexpected tasks again.
            list.selected = get_work_item_identifier(person_group)
            _work_item_list_press(list, "Run again").action.callback(editor)
            wait_for_task_group!(editor, person_group)
            @test length(getfield(person_group.tasks[1], :executions)[]) == 2
        end

        @testset "the :tasks source of a roster lists a task alone too" begin
            roster = Roster(StoreRecords(:tasks); columns = ["name", "within.title"])
            link_roster!(roster, editor.document)
            items = run_with_evaluation_editor(() -> [peek(getfield(row, :item)) for row in roster.rows], editor)
            @test any(item -> item === assistant_task, items)
            @test any(item -> item === person_group.tasks[1], items)
        end
    end
end
