# The views of tasks, with plain shell commands as the work: the pane of a group
# draws the columns that every task has and the columns of its kind, the detail
# shows the facts and the buttons of the kind, a press of a button of the kind
# calls it with the task, the tab says how far the group is, and the Tasks pane
# has a row for each group. The probe task of a kind that adds nothing is the
# one of `TaskGroupTest.jl`.

# A kind of task that adds a column, its facts and a button.
struct _TaskViewProbeTask <: AbstractTask
    name::String
    script::String
end
TaskModule.get_result_codes(::_TaskViewProbeTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::_TaskViewProbeTask) = task.name
TaskModule.get_task_columns(::_TaskViewProbeTask) = ["name" => 2]
# The count of the rows that a pane built: each row reads the name column once.
const _TASK_VIEW_NAME_READS = Ref(0)
TaskModule.format_task_column(task::_TaskViewProbeTask, column::AbstractString) =
    column == "name" ? (_TASK_VIEW_NAME_READS[] += 1; task.name) : ""
TaskModule.format_task_details(task::_TaskViewProbeTask, result) =
    String["script: " * task.script; result === nothing ? String[] : ["ended: " * result.result]]
const _TASK_VIEW_PRESSES = String[]
TaskModule.get_task_actions(::_TaskViewProbeTask) =
    ["Note" => (editor, task) -> push!(_TASK_VIEW_PRESSES, task.name)]
TaskModule.start_task(task::_TaskViewProbeTask; on_finish = nothing) =
    TaskModule.start_task(_TaskGroupProbeTask(task.name, task.script); on_finish)

# Each text of a drawn pane with its place on the canvas.
function _collect_task_view_texts(node, x = 0, y = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            link = elements
            while link !== nothing
                _collect_task_view_texts(link.value, x + Int(node.x), y + Int(node.y), found)
                link = link.next
            end
        else
            for element in elements
                _collect_task_view_texts(element, x + Int(node.x), y + Int(node.y), found)
            end
        end
    elseif node isa GraphicsViewport
        _collect_task_view_texts(node.content, x + Int(node.x), y + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (x + Int(node.x), y + Int(node.y), String(node.text)))
    end
    found
end

# A pane as a tab draws it: the row that the slice registers for its document,
# at the size of a window.
function _print_task_view(document; width = 1200, height = 900)
    rows = build_task_graphics_entry(; measure = FixedMeasure(10, 18, 6, 0))
    projection = only(row.second for row in rows if document isa row.first)
    context = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                              height = Cell(Int32(height)))
    (projection, print_document(projection, nothing, document, context))
end

_collect_task_view_words(document) =
    [text for (_, _, text) in _collect_task_view_texts(last(_print_task_view(document)).output)]

# The texts that a window of `height` shows, as a renderer reaches them: a list
# of the canvas is read only down to the bottom of the window, so the rows below
# it are not built.
function _collect_task_view_window_texts(node, height, x = 0, y = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        elements = node.elements
        top = y + Int(node.y)
        if elements isa ListNode
            link = elements
            while link !== nothing
                element = link.value
                hasproperty(element, :y) && top + Int(element.y) > height && break
                _collect_task_view_window_texts(element, height, x + Int(node.x), top, found)
                link = link.next
            end
        else
            for element in elements
                _collect_task_view_window_texts(element, height, x + Int(node.x), top, found)
            end
        end
    elseif node isa GraphicsViewport
        _collect_task_view_window_texts(node.content, height, x + Int(node.x), y + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (x + Int(node.x), y + Int(node.y), String(node.text)))
    end
    found
end

function test_task_views()
    @testset "task views" begin
        @testset "a kind that adds nothing shows the columns of every task" begin
            document = wrap_task_group_document(
                TaskGroup(_make_task_group_probe_tasks(0.0); name = "probe", jobs = 4))
            wait_task_group_document(start_task_group_document!(document))
            words = _collect_task_view_words(document)
            @test all(header -> header in words,
                      ("state", "progress", "elapsed", "process", "processor", "memory", "result"))
            @test !("directory" in words) && !("configuration" in words)
            @test "4 DONE" in words && "1 ERROR unexpected" in words
            @test "Press › on a row to see its task here." in words
        end

        @testset "a kind adds its columns, its facts and its buttons" begin
            tasks = [_TaskViewProbeTask(name, "exit $(name == "fail" ? 1 : 0)")
                     for name in ("alpha", "fail")]
            document = wrap_task_group_document(TaskGroup(tasks; name = "views", jobs = 2))
            wait_task_group_document(start_task_group_document!(document))
            texts = _collect_task_view_texts(last(_print_task_view(document)).output)
            header = only(t for t in texts if t[3] == "name")
            state = only(t for t in texts if t[3] == "state" && t[2] == header[2])
            progress = only(t for t in texts if t[3] == "progress" && t[2] == header[2])
            @test state[1] < header[1] < progress[1]
            @test sort([t[3] for t in texts if t[1] == header[1] && t[2] > header[2]]) ==
                  ["alpha", "fail"]

            select_task_document!(document, 2)
            projection, iomap = _print_task_view(document)
            texts = _collect_task_view_texts(iomap.output)
            words = [t[3] for t in texts]
            @test "script: exit 1" in words && "ended: ERROR" in words
            @test "Stop" in words && "Run again" in words && "Note" in words

            note = only(t for t in texts if t[3] == "Note")
            operation = read_intent(projection, iomap,
                MouseClick(:left, note[1] + 2, note[2] + 2, ModifierKeys(); time = 0.0))
            @test operation isa InvokeActionOperation
            empty!(_TASK_VIEW_PRESSES)
            operation.action.callback(nothing)
            @test _TASK_VIEW_PRESSES == ["fail"]

            # A run again of the failed task: the detail lists its first
            # execution, with its verdict, under the current one.
            @test !("Earlier executions" in words)
            wait_task_group_document(rerun_task_group_document!(document, [2]))
            words = _collect_task_view_words(document)
            @test "Earlier executions" in words
            @test any(w -> occursin(r"^1\. started \d\d:\d\d:\d\d — ERROR", w), words)
        end

        @testset "the progress of a task that runs is a ring" begin
            running = TaskDocument(_TaskGroupProbeTask("r", "exit 0"); status = :running, progress = 0.45)
            ring = TaskModule._make_task_progress_ring(running)
            @test ring isa WidgetProgressRing && ring.visible && ring.value == 0.45
            waiting = TaskModule._make_task_progress_ring(TaskDocument(_TaskGroupProbeTask("w", "exit 0")))
            @test !waiting.visible && waiting.value === nothing
        end

        @testset "the row of an inner group shows its pane in the detail" begin
            phases = [TaskGroup(_make_task_group_probe_tasks(0.0); name = "phase $i", jobs = 2)
                      for i in 1:2]
            document = wrap_task_group_document(TaskGroup(phases; name = "build", jobs = 1))
            wait_task_group_document(start_task_group_document!(document))
            texts = _collect_task_view_texts(last(_print_task_view(document)).output)
            header = only(t for t in texts if t[3] == "group")
            @test sort([t[3] for t in texts if t[1] == header[1] && t[2] > header[2]]) ==
                  ["phase 1", "phase 2"]
            @test "8 DONE" in [t[3] for t in texts]
            select_task_document!(document, 1)
            words = _collect_task_view_words(document)
            # The card of the phase, under the card of the build, with no actions
            # of its own.
            @test "phase 1" in words && "4 DONE" in words && "1 ERROR unexpected" in words
            @test count(==("Run all"), words) == 1
        end

        @testset "the card shows the preparation, and the detail its pane" begin
            build = TaskGroup([_TaskGroupProbeTask("compile", "exit 2")]; name = "stub", action = "Building")
            document = wrap_task_group_document(TaskGroup(_make_task_group_probe_tasks(0.0); jobs = 1,
                                                          preparation = build))
            wait_task_group_document(start_task_group_document!(document))
            words = _collect_task_view_words(document)
            @test any(startswith("Before the tasks: building stub — ERROR"), words)
            @test "Show" in words && "5 CANCEL unexpected" in words
            select_task_document!(document, -1)
            words = _collect_task_view_words(document)
            # The card of the build, under the card of the group, with no actions
            # of its own.
            @test "stub" in words && "1 ERROR unexpected" in words
            @test count(==("Run all"), words) == 1
        end

        @testset "the tab and the Tasks pane follow the group" begin
            document = wrap_task_group_document(
                TaskGroup(_make_task_group_probe_tasks(0.0); name = "tabbed", jobs = 4))
            title = make_task_group_tab_title(document)
            @test title.icon === :circle && only(title.badges).content == "5"
            wait_task_group_document(start_task_group_document!(document))
            @test title.icon === :x && title.icon_role === :error
            @test [badge.content for badge in title.badges] == ["1 ERROR"]
            words = _collect_task_view_words(get_session_task_group_list())
            @test getfield(document, :identifier)[] in words && "tabbed" in words
        end
    end
end

"""
    test_task_group_scale(; task_count = 20_000, jobs = 16)

A group of `task_count` process tasks (P7 of the catalog of legacy documents):
the pane draws a window of rows before and after the run, and a drain while the
group runs costs no walk of every task. It starts `task_count` processes, so
`test_platform` does not call it.
"""
function test_task_group_scale(; task_count::Integer = 20_000, jobs::Integer = 16)
    @testset "a group of $task_count process tasks draws a window of rows" begin
        tasks = AbstractTask[_TaskViewProbeTask("t$i", "exit 0") for i in 1:task_count]
        document = wrap_task_group_document(TaskGroup(tasks; name = "scale", jobs = jobs))
        # A print and a window of 900 pixels: the rows that the window shows, and
        # the rows that the pane built for it, both a few dozen.
        function draw()
            _TASK_VIEW_NAME_READS[] = 0
            output = last(_print_task_view(document)).output
            shown = count(((_, _, text),) -> occursin(r"^t\d+$", text),
                          _collect_task_view_window_texts(output, 900))
            (shown, _TASK_VIEW_NAME_READS[])
        end
        printed = @elapsed (shown, built) = draw()
        @test 0 < shown < 100 && built < 200
        start_task_group_document!(document)
        drains = Float64[]
        deadline = time() + 900
        while get_task_group_document_status(document) !== :finished && time() < deadline
            push!(drains, @elapsed drain_task_feed!())
            sleep(0.05)
        end
        wait_task_group_document(document)
        counts = get_task_group_document_counts(document)
        @test counts.finished == task_count && counts.running == 0 && counts.pending == 0
        @test length(drains) > 1
        (shown, built) = draw()
        @test 0 < shown < 100 && built < 200
        @info "a group of $task_count process tasks" printed drains = length(drains) slowest = maximum(drains) total = sum(drains)
    end
end
