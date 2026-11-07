# The verbs of tasks over a group of plain shell commands: a group is listed,
# found, described with its tasks and its facts, read, stopped, run again and
# closed, and a model may call each verb. The editor is headless and runs no
# loop, so each verb runs at once on the calling task, and the group starts in an
# evaluation of that editor, so it joins the list of its session. The probe tasks
# are those of `TaskGroupTest.jl` and `TaskGroupToWidgetTest.jl`.

# An editor that records the operations of a group that it evaluates, and
# evaluates them as the editor it holds.
struct _TaskOperationSpy
    editor::Any
    seen::Vector{Any}
end

for operation_type in (StartTaskGroupOperation, StopTaskGroupOperation, StopTaskOperation,
                       RerunTaskGroupOperation, CloseTaskGroupOperation)
    @eval ProjecturedKernel.OperationModule.evaluate_operation(spy::_TaskOperationSpy, operation::$operation_type) =
        (push!(spy.seen, operation); evaluate_operation(spy.editor, operation))
end

# Press the first button `label` of the pane of `document`, or the last when
# `last_one`, which `spy` evaluates.
function _press_task_button(document, label, spy; last_one = false)
    projection, iomap = _print_task_view(document; height = 1200)
    texts = [t for t in _collect_task_view_texts(iomap.output) if t[3] == label]
    text = last_one ? last(texts) : first(texts)
    operation = read_intent(projection, iomap,
        MouseClick(:left, text[1] + 2, text[2] + 2, ModifierKeys(); time = 0.0))
    operation.action.callback(spy)
end

function test_task_group_verbs()
    @testset "task group verbs" begin
        tasks = [_TaskViewProbeTask(name, name == "fail" ? "echo oops >&2; exit 1" : "echo $name")
                 for name in ("alpha", "fail")]
        group = wrap_task_group_document(TaskGroup(tasks; name = "verbs", jobs = 2);
                                         title = "the verbs")
        editor = Editor(PaneTree(PaneGroup(PaneTab[PaneTab("verbs", group)])),
                        NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)); backend = HeadlessBackend(),
                        devices = Device[])
        run_with_evaluation_editor(() -> start_task_group_document!(group), editor)
        @test wait_for_task_group!(editor, group) === group
        identifier = getfield(group, :identifier)[]

        @testset "a stop of the code unit ends the wait for a group" begin
            slow = wrap_task_group_document(
                TaskGroup([_TaskViewProbeTask("slow", "sleep 30")]; name = "slow", jobs = 1))
            start_task_group_document!(slow)
            tools = ProjecturedKernel.ToolModule
            unit = tools.CodeUnit(["wait for the group"])
            waiter = Threads.@spawn tools.run_as_code_unit(unit) do
                try
                    wait_for_task_group!(editor, slow)
                    :waited
                catch exception
                    exception isa InterruptException ? :stopped : rethrow()
                end
            end
            sleep(0.3)
            started = time()
            tools.stop_code_unit!(unit)
            @test fetch(waiter) === :stopped
            @test time() - started < 2
            stop_task_group!(get_task_group(slow))
            wait_task_group(get_task_group(slow))
        end

        @testset "a wait with a deadline ends before the group, and the group goes on" begin
            slow = wrap_task_group_document(
                TaskGroup([_TaskViewProbeTask("slow", "sleep 2")]; name = "slow", jobs = 1))
            start_task_group_document!(slow)
            started = time()
            @test wait_for_task_group!(editor, slow; timeout = 0.3) === slow
            @test time() - started < 1.5
            @test is_task_group_running(slow)
            answer = string(wait_for_tasks!(slow; timeout = 0.2, editor))
            @test startswith(answer, "Still running after ")
            answer = string(wait_for_tasks!(slow; timeout = 10, editor))
            @test startswith(answer, "Ended: ")
            @test !is_task_group_running(slow)
        end

        @testset "a group is listed and found" begin
            line = only(l for l in split(string(list_task_groups(; editor)), "\n")
                        if startswith(l, identifier * " "))
            @test occursin("the verbs", line) && occursin("2/2", line)
            @test find_task_group(identifier; editor) === group
            @test find_task_group("the verbs"; editor) === group
            @test find_task_group("no such group"; editor) === nothing
        end

        @testset "a group and a task are described with the facts of their kind" begin
            summary = compute_task_group_summary(get_task_group(group)).summary
            text = string(describe_task_group(group; editor))
            @test startswith(text, summary)
            @test occursin("2. fail — ERROR (unexpected)", text) && !occursin("1. alpha", text)
            @test occursin("1. alpha — DONE", string(describe_task_group(group; tasks = :all, editor)))
            detail = string(describe_task(group, 2; editor))
            # The line of the task has its result and its reason; the process and
            # the streams follow; the facts of the kind are the result and the page.
            @test startswith(detail, "2. fail — ERROR (unexpected) (Non-zero exit code: 1)")
            @test occursin(r"process: \d+", detail) && occursin(r"elapsed: ", detail)
            @test !occursin("script:", detail) && !occursin("ended:", detail)
            failed = group.tasks[2]
            @test get_task_document_result(failed).result == "ERROR"
            @test failed.kind_document === nothing
            @test occursin("stderr:\noops", detail)
            @test occursin("executions: 1", detail) && !occursin("earlier", detail)
            @test string(get_task_output(group, 1; editor)) == "alpha"
            @test string(get_task_output(group, 2; stream = :stderr, editor)) == "oops"
        end

        @testset "the actions of a group are operations that the editor evaluates" begin
            spy = _TaskOperationSpy(editor, Any[])
            document = wrap_task_group_document(
                TaskGroup([_TaskViewProbeTask("fail", "exit 1"), _TaskViewProbeTask("ok", "exit 0")];
                          name = "operations", jobs = 1); title = "the operations")
            counts() = build_task_group_document_counts(document)

            # The press of Run all makes the start, and the group joins the list.
            _press_task_button(document, "Run all", spy)
            @test only(spy.seen) isa StartTaskGroupOperation && only(spy.seen).document === document
            wait_for_task_group!(editor, document)
            @test any(g -> g === document, collect_work_items(get_session_task_group_list(; editor)))
            @test counts()[:done] == 1 && counts()[:error] == 1

            # The press of Run unexpected again makes the rerun of `:unexpected`.
            empty!(spy.seen)
            _press_task_button(document, "Run unexpected again", spy)
            @test only(spy.seen) isa RerunTaskGroupOperation && only(spy.seen).which === :unexpected
            wait_for_task_group!(editor, document)
            @test counts()[:error] == 1

            # The press of Run again on a task makes the rerun of its place.
            empty!(spy.seen)
            select_task_document!(document, 2)
            _press_task_button(document, "Run again", spy)
            @test only(spy.seen) isa RerunTaskGroupOperation && only(spy.seen).which == [2]
            wait_for_task_group!(editor, document)

            # The press of Stop on the group, and of Stop on a task, make their stops.
            slow = wrap_task_group_document(
                TaskGroup([_TaskViewProbeTask("one", "sleep 30"), _TaskViewProbeTask("two", "sleep 30")];
                          name = "slow operations", jobs = 2); title = "the slow operations")
            evaluate_operation(editor, StartTaskGroupOperation(slow))
            deadline = time() + 10
            while build_task_group_document_counts(slow)[:running] < 2 && time() < deadline
                drain_task_feed!(; editor)
                sleep(0.02)
            end
            empty!(spy.seen)
            select_task_document!(slow, 1)
            _press_task_button(slow, "Stop", spy; last_one = true)
            @test only(spy.seen) isa StopTaskOperation && only(spy.seen).index == 1
            empty!(spy.seen)
            _press_task_button(slow, "Stop", spy)
            @test only(spy.seen) isa StopTaskGroupOperation
            wait_for_task_group!(editor, slow)
            @test build_task_group_document_counts(slow)[:cancelled] == 2

            # An operation names its documents, says what it does, and has no inverse
            # that undoes it: a process that ran can not be undone.
            operations = (StartTaskGroupOperation(document), StopTaskGroupOperation(document),
                          StopTaskOperation(document, 1), RerunTaskGroupOperation(document, :failed),
                          CloseTaskGroupOperation(get_session_task_group_list(; editor), document))
            for operation in operations
                @test make_inverse_operation(document, operation) isa DoNothingOperation
                @test is_self_contained_operation(operation)
                @test !isempty(describe_operation(operation))
            end
            before = (counts(), getfield(document, :status)[])
            evaluate_operation(editor, make_inverse_operation(document, operations[2]))
            @test (counts(), getfield(document, :status)[]) == before

            # The verbs make the same operations: a stop of one task, a stop of the group.
            evaluate_operation(editor, StartTaskGroupOperation(slow))
            deadline = time() + 10
            while any(isnothing, get_task_group(slow).runs) && time() < deadline
                sleep(0.02)
            end
            @test string(stop_task!(slow, 1; editor)) == "Stopping task 1."
            @test string(stop_tasks!(slow; editor)) == "Stopping the group " * getfield(slow, :identifier)[] * "."
            wait_for_task_group!(editor, slow)
            @test build_task_group_document_counts(slow)[:cancelled] == 2
        end

        @testset "a verb starts a group of programs, and its answer goes to the other verbs" begin
            folder = mktempdir()
            program(script, name) = ProgramTask(`sh -c $script`; working_directory = folder, name)
            chain = TaskGroup([program("echo one", "one"), program("exit 4", "two"),
                               program("echo three", "three")];
                              name = "chain", jobs = 1, stop_at_failure = true)
            tabs_before = length(get_pane_groups(editor.document)[1].tabs)
            selection_before = string(strip_reference_types(get_selection(editor.document)))
            answer = run_tasks!(chain; title = "the chain", editor)
            @test answer isa TaskGroupDocument && get_task_group(answer) === chain
            @test any(g -> g === answer, collect_work_items(get_session_task_group_list(; editor)))
            @test occursin("the chain", string(list_task_groups(; editor)))
            @test length(get_pane_groups(editor.document)[1].tabs) == tabs_before
            @test string(strip_reference_types(get_selection(editor.document))) == selection_before
            @test startswith(string(wait_for_tasks!(answer; timeout = 20, editor)), "Ended: ")
            text = string(describe_task_group(answer; tasks = :all, editor))
            @test occursin("1. one — DONE", text) && occursin("2. two — ERROR (unexpected)", text)
            @test occursin("3. three — CANCEL (unexpected) (Not started: two ended ERROR)", text)
            @test string(get_task_output(answer, 1; editor)) == "one"
            @test_throws ArgumentError run_tasks!(chain; editor)

            slow = run_tasks!(TaskGroup([program("sleep 30", "sleep")]; name = "slow"); editor)
            started = time()
            @test occursin("Stopping", string(stop_tasks!(slow; editor)))
            wait_for_task_group!(editor, slow)
            @test time() - started < 5
            @test occursin("Closed the group", string(close_task_group!(slow; editor)))
            @test length(get_pane_groups(editor.document)[1].tabs) == tabs_before
        end

        @testset "a group is stopped, run again and closed" begin
            @test string(stop_task!(group, 1; editor)) == "Stopping task 1."
            @test rerun_tasks!(group; which = :all, wait = true, editor) === group
            @test build_task_group_document_counts(group)[:done] == 1
            detail = string(describe_task(group, 2; editor))
            @test occursin("executions: 2", detail)
            @test occursin(r"earlier 1: started \d\d:\d\d:\d\d — ERROR", detail)
            @test occursin("Closed the group " * identifier, string(close_task_group!(group; editor)))
            @test isempty(get_pane_groups(editor.document)[1].tabs)
            # The closed group keeps its place in the list, as a closed group.
            groups = collect(get_session_task_group_list(; editor).groups)
            @test !any(g -> g === group, groups)
            @test any(g -> g isa ClosedTaskGroup && getfield(g, :identifier)[] == identifier, groups)
            @test find_task_group(identifier; editor) === nothing
        end

        @testset "another work item is listed, found, described, stopped and closed" begin
            item = _TaskViewProbeItem("S1", "a probe item")
            add_task_group!(get_session_task_group_list(; editor), item)
            lines = split(string(list_task_groups(; editor)), "\n")
            @test first(lines) == "S1 · a probe item · probe · running · found 3"
            @test find_task_group("S1"; editor) === item && find_task_group("a probe item"; editor) === item
            @test string(describe_task_group(item; editor)) == "running\nfound 3"
            @test string(describe_task_group(item; limit = 1, editor)) == "running"
            @test string(stop_tasks!(item; editor)) == "Stopping the probe S1." && item.stopped
            @test string(close_task_group!(item; editor)) == "Closed the probe S1."
            @test find_task_group("S1"; editor) === nothing
        end

        @testset "a model may call every verb" begin
            names = ProjecturedKernel.ToolModule.get_api_entry_names(
                only(entry for entry in ProjecturedKernel.ToolModule.collect_marked_api()
                     if entry.module_ === TaskModule))
            @test :describe_task_group in names && :close_task_group! in names
            @test :run_tasks! in names && :ProgramTask in names && :TaskGroup in names
            @test all(name -> isdefined(TaskModule, name), names)
        end
    end
end
