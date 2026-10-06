# The documents of tasks, with plain shell commands as the work: a document
# follows its execution only through a drain, a feed copies at most once in an
# interval, and a group document keeps its counts, its summary and its status
# through a run, a run again and a stop. The probe task is the one of
# `TaskGroupTest.jl`.

const _TaskDocumentFeed = ProjecturedKernel.FeedModule

function test_task_document()
    @testset "task document" begin
        @testset "a document follows its execution through a drain" begin
            # The task lives a moment, so its process has an identifier to ask for.
            document = TaskDocument(_TaskGroupProbeTask("echo",
                "sleep 0.2; echo one; echo two >&2; exit 0"))
            @test getfield(document, :status)[] === :pending
            start_task!(document)
            @test getfield(document, :status)[] === :running
            wait_task_execution(getfield(document, :running)[])
            # Until a drain, the document says what it said when the task started.
            @test isempty(getfield(document, :output)[])
            wait_task_document(document)
            @test getfield(document, :status)[] === :done
            @test getfield(document, :output)[] == ["one"]
            @test getfield(document, :error_output)[] == ["two"]
            @test getfield(document, :result)[].result == "DONE"
            @test getfield(document, :process_id)[] !== nothing
            @test getfield(document, :end_time)[] >= getfield(document, :start_time)[]

            failed = TaskDocument(_TaskGroupProbeTask("fail", "exit 3"))
            wait_task_document(start_task!(failed))
            @test getfield(failed, :status)[] === :error
            @test getfield(failed, :result)[].reason == "Non-zero exit code: 3"

            # A start again begins from nothing.
            start_task!(failed)
            @test getfield(failed, :status)[] === :running
            @test getfield(failed, :result)[] === nothing
            wait_task_document(failed)
        end

        @testset "a feed copies at most once in an interval" begin
            task = _TaskGroupProbeTask("one", "exit 0")
            store = TaskFeedStore()
            clock = Ref(10.0)
            feed = TaskFeed(; store = store, flush_interval = 0.25, now = () -> clock[])
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) === nothing
            execution = TaskExecution(task)
            writes = Ref(0)
            register_task_execution!(store, execution, snapshot -> (writes[] += 1))
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) == 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            update_task_execution!(e -> (e.progress = 0.5), execution)
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 0     # the same moment
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 0     # nothing changed
            @test writes[] == 2
            finish_task_execution!(execution,
                _TaskGroupProbeResult(task, "DONE", "DONE", nothing, 0.1))
            clock[] += 0.25
            @test _TaskDocumentFeed.drain_changes!(feed, nothing) == 1
            # The end is copied, so the execution is let go and no frame is asked for.
            @test !has_task_feed_entries(store)
            @test _TaskDocumentFeed.compute_wake_deadline(feed, nothing) === nothing
        end

        @testset "a group document keeps its counts and its summary" begin
            document = wrap_task_group_document(
                TaskGroup(_make_task_group_probe_tasks(0.0); name = "probe", jobs = 2))
            other = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0)))
            @test startswith(getfield(document, :identifier)[], "T")
            @test getfield(document, :identifier)[] != getfield(other, :identifier)[]
            @test get_task_group_document_status(document) === :pending
            @test build_task_group_document_counts(document)[:pending] == 5
            start_task_group_document!(document)
            @test first(get_session_task_group_list().groups) === document
            wait_task_group_document(document)
            @test get_task_group_document_status(document) === :finished
            counts = build_task_group_document_counts(document)
            @test counts[:done] == 4 && counts[:error] == 1 && counts[:total] == 5
            # The tally that each write keeps agrees with a count of the documents.
            tally = getfield(document, :tally)[]
            @test all(tally[state] == counts[state] for state in keys(tally))
            @test measure_task_group_document_progress(document) == 1.0
            summary = getfield(document, :summary)[]
            @test summary.finished == 5
            @test ("DONE", 4, 0) in summary.counts && ("ERROR", 0, 1) in summary.counts
            @test getfield(document, :counts)[].result == "ERROR"

            documents = collect(getfield(document, :tasks)[])
            failed = only(i for (i, d) in enumerate(documents) if getfield(d, :status)[] === :error)
            kept = first(i for i in eachindex(documents) if i != failed)
            before = getfield(documents[kept], :result)[]
            rerun_task_group_document!(document, :failed)
            wait_task_group_document(document)
            @test getfield(documents[kept], :result)[] === before
            @test getfield(documents[failed], :status)[] === :error
            @test build_task_group_document_counts(document)[:done] == 4
            @test get_task_group_document_status(document) === :finished
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
            @test getfield(document, :counts)[].result == "CANCEL"
        end
    end
end
