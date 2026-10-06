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
TaskModule.format_task_column(task::_TaskViewProbeTask, column::AbstractString) =
    column == "name" ? task.name : ""
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
