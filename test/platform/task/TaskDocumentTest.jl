# The documents of tasks, with plain shell commands as the work: a document
# follows its execution only through a drain, a feed syncs at most once in an
# interval, and a group document keeps its counts, its summary and its status
# through a run, a run again and a stop. The probe task is the one of
# `TaskGroupTest.jl`.

const _TaskDocumentFeed = ProjecturedKernel.FeedModule

# An owner of an execution that keeps what each sync told it.
struct _TaskDocumentFeedOwner
    syncs::Vector{Tuple{Symbol,Bool}}
end
TaskModule.record_task_execution_sync!(owner::_TaskDocumentFeedOwner, execution, shadow,
                                       before::Symbol, made::Bool) =
    (push!(owner.syncs, (before, made)); nothing)

# An operation that notes that it ran, as the end of a group posts it.
struct _TaskEndProbe <: ProjecturedKernel.OperationModule.Operation
    ran::Vector{Int}
end
ProjecturedKernel.OperationModule.evaluate_operation(editor, operation::_TaskEndProbe) =
    (push!(operation.ran, 1); nothing)

# A content that holds the list of groups in a field, as a workspace does.
@document struct TaskTestListHolder
    groups::Any
end

function test_task_document()
    @testset "task document" begin
        @testset "a document follows its execution through a drain" begin
            # The task lives a moment, so its process has an identifier to ask for.
            document = TaskDocument(_TaskGroupProbeTask("echo",
                "sleep 0.2; echo one; echo two >&2; exit 0"))
            @test get_task_document_status(document) === :pending
            @test isempty(getfield(document, :executions)[])
            @test get_current_task_execution(document) === nothing
            start_task!(document)
            @test get_task_document_status(document) === :running
            wait_task_execution(getfield(document, :running)[])
            # Until a drain, the shadow says what the execution said when it started.
            @test isempty(collect_task_document_lines(document))
            wait_task_document(document)
            current = get_current_task_execution(document)
            @test get_task_document_status(document) === :done
            @test collect_task_document_lines(document) == ["one"]
            @test collect_task_document_lines(document, :error_output) == ["two"]
            @test get_task_document_result(document).result == "DONE"
            @test current.process_id !== nothing
            @test current.end_time >= current.start_time

            failed = TaskDocument(_TaskGroupProbeTask("fail", "exit 3"))
            wait_task_document(start_task!(failed))
            @test get_task_document_status(failed) === :error
            @test get_task_document_result(failed).reason == "Non-zero exit code: 3"

            # A start again begins from nothing, and keeps the first execution
            # with its result: the document holds both, the newest last.
            start_task!(failed)
            @test get_task_document_status(failed) === :running
            @test get_task_document_result(failed) === nothing
            wait_task_document(failed)
            executions = getfield(failed, :executions)[]
            @test length(executions) == 2
            @test get_current_task_execution(failed) === executions[2]
            @test get_earlier_task_executions(failed) == executions[1:1]
            (text, result) = describe_task_execution(executions[1])
            @test result.reason == "Non-zero exit code: 3"
            @test occursin(r"^started \d\d:\d\d:\d\d — ERROR", text)
        end

        @testset "a feed syncs at most once in an interval" begin
            task = _TaskGroupProbeTask("one", "exit 0")
            store = TaskFeedStore()
            clock = Ref(10.0)
            feed = TaskFeed(; store = store, flush_interval = 0.25, now = () -> clock[])
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) === nothing
            execution = TaskExecution(task)
            owner = _TaskDocumentFeedOwner(Tuple{Symbol,Bool}[])
            register_task_execution!(store, execution, owner)
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) == 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            update_task_execution!(e -> (e.progress = 0.5), execution)
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 0     # the same moment
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 0     # nothing changed
            # The first drain made the shadow, the second synced it.
            @test owner.syncs == [(:pending, true), (:pending, false)]
            finish_task_execution!(execution,
                _TaskGroupProbeResult(task, "DONE", "DONE", nothing, 0.1))
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            # The end is synced, so the execution is let go and no frame is asked for.
            @test !has_task_feed_entries(store)
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) === nothing
        end

        @testset "a drain syncs only the executions that changed" begin
            store = TaskFeedStore()
            first_execution = TaskExecution(_TaskGroupProbeTask("one", "exit 0"))
            second_execution = TaskExecution(_TaskGroupProbeTask("two", "exit 0"))
            first_owner = _TaskDocumentFeedOwner(Tuple{Symbol,Bool}[])
            second_owner = _TaskDocumentFeedOwner(Tuple{Symbol,Bool}[])
            register_task_execution!(store, first_execution, first_owner)
            register_task_execution!(store, second_execution, second_owner)
            @test drain_task_feed!(store) == 2
            update_task_execution!(e -> (e.progress = 0.5), second_execution)
            @test drain_task_feed!(store) == 1
            @test length(first_owner.syncs) == 1 && length(second_owner.syncs) == 2
            @test drain_task_feed!(store) == 0
        end

        @testset "a group document keeps its counts and its summary" begin
            document = wrap_task_group_document(
                TaskGroup(_make_task_group_probe_tasks(0.0); name = "probe", jobs = 2))
            other = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0)))
            @test startswith(getfield(document, :identifier)[], "T")
            @test getfield(document, :identifier)[] != getfield(other, :identifier)[]
            @test get_task_group_document_status(document) === :pending
            @test build_task_group_document_counts(document)[:pending] == 5
            # A group that starts in an evaluation of an editor joins the end of the
            # list of its session; a group that starts outside every editor joins
            # no list.
            editor = Editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                            backend = HeadlessBackend(), devices = Device[])
            earlier = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0); name = "earlier"))
            add_task_group!(get_session_task_group_list(; editor), earlier)
            run_with_evaluation_editor(() -> start_task_group_document!(document), editor)
            @test collect(get_session_task_group_list(; editor).groups) == [earlier, document]
            start_task_group_document!(other)
            @test !any(g -> g === other, get_session_task_group_list(; editor).groups)
            wait_task_group_document(other)
            # A start that names its editor, as a verb does, joins the list of that
            # editor also outside an evaluation.
            named = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0); name = "named"))
            start_task_group_document!(named; editor)
            @test last(get_session_task_group_list(; editor).groups) === named
            wait_task_group_document(named)
            # The end of a group posts its end operation to its editor.
            ended = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0); name = "ended"))
            probe = _TaskEndProbe(Int[])
            start_task_group_document!(ended; editor, end_operation = probe)
            wait_task_group_document(ended)
            deadline = time() + 10
            while isempty(probe.ran) && time() < deadline
                drain_operations!(editor)
                sleep(0.02)
            end
            @test probe.ran == [1]
            # The editor of a window takes the list that a tab shows, or that the
            # content of a tab holds a few documents down, such as a navigator.
            for wrap in (list -> list, list -> Navigator(TaskTestListHolder(list)))
                shown = TaskGroupList()
                window = build_editor(wrap(shown), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                                      backend = HeadlessBackend(), devices = Device[], window = false,
                                      tabs = true, appearance = false, settings = false)
                @test get_session_task_group_list(; editor = window) === shown
            end
            wait_task_group_document(document)
            @test get_task_group_document_status(document) === :finished
            counts = build_task_group_document_counts(document)
            @test counts[:done] == 4 && counts[:error] == 1 && counts[:total] == 5
            # The facets of a task that ended: its code, and whether it was expected.
            failed = only(d for d in getfield(document, :tasks)[] if get_task_document_result(d).result == "ERROR")
            @test compute_item_facet(failed, Val(:result)) == "ERROR"
            @test compute_item_facet(failed, Val(:expected)) === false
            done = first(d for d in getfield(document, :tasks)[] if get_task_document_result(d).result == "DONE")
            @test compute_item_facet(done, Val(:expected)) === true
            # The counts of the shadow, which the tally of the scheduler makes,
            # agree with a count of the documents.
            synced = get_task_group_document_counts(document)
            @test synced.finished == counts[:done] + counts[:error]
            @test synced.running == counts[:running] && synced.pending == counts[:pending]
            @test measure_task_group_document_progress(document) == 1.0
            summary = get_task_group_document_summary(document)
            @test summary.finished == 5
            @test ("DONE", 4, 0) in summary.counts && ("ERROR", 0, 1) in summary.counts
            @test get_task_group_document_counts(document).result == "ERROR"

            documents = collect(getfield(document, :tasks)[])
            failed = only(i for (i, d) in enumerate(documents) if get_task_document_status(d) === :error)
            kept = first(i for i in eachindex(documents) if i != failed)
            before = get_task_document_result(documents[kept])
            rerun_task_group_document!(document, :failed)
            # The task waits to start again: it has no current execution, and its
            # first one is earlier.
            @test getfield(documents[failed], :running)[] === nothing
            @test length(get_earlier_task_executions(documents[failed])) == 1
            wait_task_group_document(document)
            @test get_task_document_result(documents[kept]) === before
            @test get_task_document_status(documents[failed]) === :error
            # The run again added an execution and kept the first; the task that
            # did not run again has its one execution.
            @test length(getfield(documents[failed], :executions)[]) == 2
            @test only(get_earlier_task_executions(documents[failed])).result.result == "ERROR"
            @test length(getfield(documents[kept], :executions)[]) == 1
            @test build_task_group_document_counts(document)[:done] == 4
            @test get_task_group_document_status(document) === :finished
        end

        @testset "a document of a group of groups holds a document for each inner group" begin
            phases = [TaskGroup(_make_task_group_probe_tasks(0.0); name = "phase $i", jobs = 2)
                      for i in 1:2]
            document = wrap_task_group_document(TaskGroup(phases; name = "build", jobs = 1))
            identifier = getfield(document, :identifier)[]
            inner = find_task_group_document(document, 1)
            @test inner isa TaskGroupDocument && get_task_group(inner) === phases[1]
            @test getfield(inner, :identifier)[] == identifier * ".1"
            # The task of an inner group holds it, so it has a path under the outer
            # group.
            @test evaluate_reference(document, Reference(FieldReferenceStep("tasks"), RangeReferenceStep(0, 1),
                                                         FieldReferenceStep("inner_group"))) === inner
            @test find_task_group_document(document, 3) === nothing && find_task_group_document(document, 0) === nothing
            editor = Editor(PrimitiveString("x"), NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                            backend = HeadlessBackend(), devices = Device[])
            run_with_evaluation_editor(() -> start_task_group_document!(document), editor)
            wait_task_group_document(document)
            @test get_task_group_document_status(document) === :finished
            @test get_task_group_document_summary(document).total == 10
            @test get_task_group_document_counts(document).finished == 10
            for index in 1:2
                counts = build_task_group_document_counts(find_task_group_document(document, index))
                @test counts[:done] == 4 && counts[:error] == 1
                @test get_task_group_document_status(find_task_group_document(document, index)) === :finished
            end
            # Only the outer group has a row in the Tasks pane.
            groups = collect(get_session_task_group_list(; editor).groups)
            @test any(g -> g === document, groups) && !any(g -> g === inner, groups)
            # In a tree, the group has its tasks under its node, and a task that is a
            # group the tasks of its inner group; the text of the group is its name,
            # and its decoration says what came back unexpected.
            @test get_tree_children_steps(document) == ((FieldReferenceStep("tasks"),),)
            phase = getfield(document, :tasks)[][1]
            @test get_tree_children_steps(phase) == ((FieldReferenceStep("inner_group"), FieldReferenceStep("tasks")),)
            @test get_tree_children_steps(first(getfield(inner, :tasks)[])) == ()
            @test format_tree_node_label(inner) == identifier * ".1 phase 1"
            decoration = get_document_decoration(inner)
            @test decoration.icon === :x && [count.text for count in decoration.counts] == ["1 ERROR"]
            @test find_decoration_tint(decoration) === :error
            list = get_session_task_group_list(; editor)
            @test get_tree_children_steps(list) == ((FieldReferenceStep("groups"),),)
            closed = ClosedTaskGroup(Cell("T9"), Cell("gone"), Cell("smoke test"))
            @test format_tree_node_label(closed) == "T9 gone"
            @test get_document_decoration(closed).icon === :minus && get_document_decoration(closed).detail == "closed"
            # A run again of a phase puts its tasks back to waiting, and they
            # report again.
            rerun_task_group_document!(document, [1])
            wait_task_group_document(document)
            counts = build_task_group_document_counts(inner)
            @test counts[:done] == 4 && counts[:error] == 1 && counts[:pending] == 0
        end

        @testset "a document of a group follows its preparation, which it does not count" begin
            tasks = [_TaskGroupProbeTask("a", "exit 0"), _TaskGroupProbeTask("b", "exit 0")]
            build(code) = TaskGroup([_TaskGroupProbeTask("compile", "exit $code")]; name = "stub",
                                    action = "Building")
            document = wrap_task_group_document(TaskGroup(tasks; jobs = 1, preparation = build(0)))
            preparation = get_task_group_preparation(document)
            @test preparation isa TaskGroupDocument
            @test getfield(preparation, :identifier)[] == getfield(document, :identifier)[] * ".0"
            @test describe_task_group_preparation(document) == ("Before the tasks: building stub — waiting", :waiting, true)
            wait_task_group_document(start_task_group_document!(document))
            @test get_task_group_document_summary(document).total == 2
            @test build_task_group_document_counts(document)[:done] == 2
            @test build_task_group_document_counts(preparation)[:done] == 1
            @test describe_task_group_preparation(document) == ("Before the tasks: building stub — DONE", "DONE", true)

            failing = wrap_task_group_document(TaskGroup(tasks; jobs = 1, preparation = build(2)))
            wait_task_group_document(start_task_group_document!(failing))
            (text, state, expected) = describe_task_group_preparation(failing)
            @test startswith(text, "Before the tasks: building stub — ERROR") && state == "ERROR" && !expected
            @test build_task_group_document_counts(failing)[:cancelled] == 2
            @test get_task_group_document_status(failing) === :finished
            @test occursin(text, string(TaskModule._describe_task_group(failing, :all, 20)))

            # A preparation that is one task has the document of a task.
            single = wrap_task_group_document(TaskGroup(tasks; jobs = 1,
                                                        preparation = _TaskGroupProbeTask("prepare", "exit 0")))
            @test get_task_group_preparation(single) isa TaskDocument
            wait_task_group_document(start_task_group_document!(single))
            @test describe_task_group_preparation(single) == ("Before the tasks: prepare — DONE", "DONE", true)
            # A run again runs the preparation again, and its document keeps the
            # first execution.
            wait_task_group_document(rerun_task_group_document!(single, :all))
            prepare = get_task_group_preparation(single)
            @test length(getfield(prepare, :executions)[]) == 2
            @test length(get_earlier_task_executions(prepare)) == 1
            @test describe_task_group_preparation(single) == ("Before the tasks: prepare — DONE", "DONE", true)
        end

        @testset "a stop finishes the group" begin
            document = wrap_task_group_document(
                TaskGroup(_make_task_group_probe_tasks(30); jobs = 5))
            start_task_group_document!(document)
            group = get_task_group(document)
            deadline = time() + 10
            while build_task_group_summary(group).running < 5 && time() < deadline
                sleep(0.02)
            end
            # The status of a group follows its documents, so they must say that
            # the tasks run before the stop.
            drain_task_feed!()
            stop_task_group_document!(document)
            @test get_task_group_document_status(document) === :stopping
            wait_task_group_document(document)
            @test get_task_group_document_status(document) === :finished
            @test build_task_group_document_counts(document)[:cancelled] == 5
            @test get_task_group_document_counts(document).result == "CANCEL"
        end
    end
end
