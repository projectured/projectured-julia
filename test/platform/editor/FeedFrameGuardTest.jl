# The frame guards of the feeds and the stores of the platform: the work that a
# feed moves into a frame keeps each frame flat at any size of its store, of its
# documents or of a burst. Each scene runs on a small headless editor with one feed,
# and its view shows one value, so the rest of a frame is the same at each size;
# the harness is `FrameGuard.jl` of the kernel tests.
#
# - The message log: a burst of lines while the log holds its capacity.
# - The log of background work: the flush with 1, 10 and 100 records.
# - Tasks: a change of one of many tasks.
# - File change: a change of one of many watched files of one folder.
# - The terminal: a burst of output chunks into a full terminal, through the door
#   of the editor, as the readers of a process write it.
# - Agent events: a burst of text of an external agent.
# - Frame statistics: the flush after many frames since the start.

using ProjecturedKernelExample: ScriptedAgentConnection

# A view of one value: `show()` computed, so a frame reads one value of the
# document whatever its size.
struct FeedFrameGuardProjection <: Projection
    show::Function
end

ProjectionModule.print_document(projection::FeedFrameGuardProjection, recursion, input, context) =
    SimpleIoMap(nothing, input, Cell(Computation(projection.show)))

function _make_feed_frame_guard_editor(document, show::Function; feeds::Vector{Feed} = Feed[])
    editor = Editor(document, FeedFrameGuardProjection(show); backend = HeadlessBackend(),
                    devices = Device[], feeds,
                    fault_policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false))
    run_print_stage!(editor)
    editor
end

# Whether this process can run a code unit on a thread other than the one of this
# task, which the door of the editor needs for a call of another task.
_has_feed_frame_guard_unit_thread() =
    EditorModule._find_code_unit_place(Threads.threadid()) !== nothing

# ── The message log ──

function _make_message_log_frame_guard_scene()
    store = Ref{Any}(nothing)
    FrameScene("a burst of lines in the message log"; sizes = [10, 100, 1_000], is_burst = true,
        make_editor = function (size)
            store[] = MessageLogStore()
            log = MessageLog()
            editor = _make_feed_frame_guard_editor(log, () -> length(log.entries);
                feeds = Feed[MessageLogFeed(store = store[], log = log)])
            # The log holds its capacity of lines, so the view and the log have the
            # same size at each size of a burst.
            foreach(i -> record_message!(store[], "Info", "a line before the burst $i"), 1:250)
            editor
        end,
        give_input! = (editor, size) ->
            foreach(i -> record_message!(store[], "Info", "a line of the burst $i"), 1:size))
end

# ── The log of background work ──

function _make_background_work_frame_guard_scene()
    clock = Ref(0.0)
    FrameScene("the flush of the log of background work"; sizes = [1, 10, 100],
        make_editor = function (size)
            log = BackgroundWorkModule._make_background_work_log()
            editor = _make_feed_frame_guard_editor(log, () -> length(log.rows);
                feeds = Feed[BackgroundWorkFeed(; log, now = () -> clock[])])
            store = EditorModule.get_background_work_store(editor)
            for i in 1:size
                push!(store.records, EditorModule.BackgroundWorkRecord(i, "work $i", 1, String[],
                                                                       time(), time(), 0, ""))
            end
            store.change_count += 1
            editor
        end,
        # Each frame flushes: the time of the flush has come, and the store changed.
        give_input! = function (editor, size)
            clock[] += 0.25
            EditorModule.get_background_work_store(editor).change_count += 1
            nothing
        end)
end

# ── Tasks ──

function _make_task_feed_frame_guard_scene()
    clock = Ref(10.0)
    executions = Ref{Any}(nothing)
    FrameScene("a change of one of many tasks"; sizes = [10, 100, 1_000],
        make_editor = function (size)
            store = TaskFeedStore()
            editor = _make_feed_frame_guard_editor(PrimitiveString("x"), () -> 0;
                feeds = Feed[TaskFeed(; store, flush_interval = 0.25, now = () -> clock[])])
            executions[] = [TaskExecution(_TaskGroupProbeTask("task $i", "exit 0")) for i in 1:size]
            foreach(execution -> register_task_execution!(store, execution, nothing), executions[])
            editor
        end,
        give_input! = function (editor, size)
            clock[] += 0.25
            update_task_execution!(execution -> (execution.progress = rand()), first(executions[]))
            nothing
        end)
end

# ── File change ──

# A receiver of a change of a file that takes it and does nothing more, so a frame
# measures the drain of the store and not the reload of a document.
struct FeedFrameGuardFileReceiver end
FileFormatModule.receive_file_change!(editor, ::FeedFrameGuardFileReceiver, file_hash, content) = true

function _make_file_change_frame_guard_scene()
    store = Ref{Any}(nothing)
    round = Ref(0)
    FrameScene("a change of one of many watched files"; sizes = [10, 100, 1_000],
        make_editor = function (size)
            store[] === nothing || close_file_change_store!(store[])
            folder = mktempdir()
            editor = _make_feed_frame_guard_editor(PrimitiveString("x"), () -> 0;
                                                   feeds = Feed[FileChangeFeed()])
            store[] = find_file_change_store(editor)
            for i in 1:size
                path = joinpath(folder, "file $i.txt")
                write(path, "text")
                watch_document_file!(TextFile(path, ""); store = store[],
                                     receiver = FeedFrameGuardFileReceiver())
            end
            editor
        end,
        # The watcher read one file again and found a new hash, as after a save of
        # another program.
        give_input! = function (editor, size)
            round[] += 1
            changed = store[]
            lock(changed.lock) do
                watched = first(changed.files)
                watched.prepared = FileChangeModule._PreparedFile(UInt64(round[]), nothing, nothing)
                push!(changed.changed, watched.path)
            end
            nothing
        end)
end

# ── The terminal ──

# Another task writes `size` chunks of output into `terminal` through the door of
# the editor, as the readers of a process do.
function _write_terminal_frame_guard_output(editor, terminal, size, counter)
    Threads.@spawn for i in 1:size
        run_on_editor_task!(editor; wait = false) do
            add_terminal_text!(terminal, :output, "a chunk of output $i\n")
            Threads.atomic_add!(counter, 1)
        end
    end
    nothing
end

function _make_terminal_frame_guard_scene()
    terminal = Ref{Any}(nothing)
    counter = Threads.Atomic{Int}(0)
    target = Ref(0)
    # A drain takes at most 64 calls into one code unit, so each size is above that.
    FrameScene("a burst of output into a full terminal"; sizes = [100, 1_000, 10_000], is_burst = true,
        make_editor = function (size)
            counter[] = 0
            target[] = 0
            terminal[] = TerminalDocument(`true`; line_capacity = 2000)
            editor = _make_feed_frame_guard_editor(terminal[], () -> length(terminal[].lines))
            # The terminal holds its capacity of lines, so each burst writes into a
            # full terminal.
            foreach(i -> add_terminal_text!(terminal[], :output, "a line before $i\n"), 1:2000)
            editor
        end,
        give_input! = function (editor, size)
            target[] += size
            _write_terminal_frame_guard_output(editor, terminal[], size, counter)
        end,
        is_input_done = editor -> counter[] >= target[])
end

# ── Agent events ──

function _make_agent_event_frame_guard_scene()
    queue = Ref{Any}(nothing)
    FrameScene("a burst of text of an external agent"; sizes = [10, 100, 1_000], is_burst = true,
        make_editor = function (size)
            session = ExternalAgentSession(ScriptedAgentConnection(Vector{Any}[]))
            assistant = Assistant(; backend = :acp, agent_session = session)
            queue[] = AgentEventQueue()
            session.events = queue[]
            _make_feed_frame_guard_editor(assistant, () -> 0;
                feeds = Feed[AgentEventFeed(Any[(assistant = assistant, session = session, queue = queue[])])])
        end,
        # A text block of `size` deltas of a word, with a line end after every 20th.
        give_input! = function (editor, size)
            put_agent_event!(queue[], LlmTextStart())
            for i in 1:size
                put_agent_event!(queue[], LlmTextDelta(i % 20 == 0 ? "word$i\n" : "word$i "))
            end
            put_agent_event!(queue[], LlmTextStop())
            nothing
        end)
end

# ── Frame statistics ──

function _make_frame_statistics_frame_guard_scene()
    clock = Ref(0.0)
    FrameScene("the flush of the frame statistics after many frames"; sizes = [1_000, 10_000, 100_000],
        make_editor = function (size)
            statistics = FrameStatistics()
            plot = FrameTimeSeries()
            editor = _make_feed_frame_guard_editor(statistics,
                () -> (statistics.frame_count, length(plot.names));
                feeds = Feed[FrameStatisticsFeed(statistics = statistics, plot = plot, now = () -> clock[])])
            foreach(_ -> EditorModule.record_frame_performance!(editor, 0.016), 1:size)
            editor
        end,
        give_input! = (editor, size) -> (clock[] += 0.25; nothing))
end

function test_feed_frame_guards()
@testset "the frame guards of the feeds" begin
    @testset "a burst of lines in the message log" begin
        scene = _make_message_log_frame_guard_scene()
        works = measure_frame_work(scene)
        growth = compute_frame_growth(works)
        @test all(work -> work.is_finished, works)
        # @broken: the drain copies every new line of the store into the log in one frame, up to the 1000 lines of the store; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.time_ratio <= FLAT_TIME_RATIO
        # @broken: the drain copies every new line of the store into the log in one frame, up to the 1000 lines of the store; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
        print_frame_work(scene.name, works)
    end

    @testset "the flush of the log of background work" begin
        scene = _make_background_work_frame_guard_scene()
        works = measure_frame_work(scene)
        growth = compute_frame_growth(works)
        @test growth.time_ratio <= FLAT_TIME_RATIO
        # @broken: a flush makes every row of the log again, also when one record changed, up to the 100 records of the store; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
        print_frame_work(scene.name, works)
    end

    @testset "a change of one of many tasks" begin
        check_frame_growth(_make_task_feed_frame_guard_scene())
    end

    @testset "a change of one of many watched files" begin
        scene = _make_file_change_frame_guard_scene()
        check_frame_growth(scene)
    end

    if _has_feed_frame_guard_unit_thread()
        @testset "a burst of output into a full terminal" begin
            check_frame_growth(_make_terminal_frame_guard_scene())
        end
    end

    @testset "a burst of text of an external agent" begin
        scene = _make_agent_event_frame_guard_scene()
        works = measure_frame_work(scene)
        growth = compute_frame_growth(works)
        @test all(work -> work.is_finished, works)
        # @broken: the feed applies every event that waits in the queue of a session in one frame, and that queue joins no text deltas; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.time_ratio <= FLAT_TIME_RATIO
        # @broken: the feed applies every event that waits in the queue of a session in one frame, and that queue joins no text deltas; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
        print_frame_work(scene.name, works)
    end

    @testset "the flush of the frame statistics after many frames" begin
        check_frame_growth(_make_frame_statistics_frame_guard_scene())
    end
end
end
