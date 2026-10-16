# The pages of a task, of an execution and of a stream, with a plain shell
# command as the work: the page of a task shows its facts, its acts and its
# executions, each a link, and its group; the page of an execution links to its
# streams; and the page of a stream shows the lines of the file of the stream that
# fit, follows the end, keeps the lines that hold a text, finds a text, goes to the
# first error and scrolls. The drawing helpers are those of
# `TaskGroupToWidgetTest.jl`, and the holder of an operation that of
# `NavigatorVisitsTest.jl`.

# A kind of task that shows its name in a column and marks its lines: an error
# line and a progress line.
struct _TaskPageProbeTask <: AbstractTask
    name::String
    script::String
end

struct _TaskPageProbeResult <: TaskResult
    task::_TaskPageProbeTask
    result::String
    expected_result::String
    reason::Union{String,Nothing}
    elapsed_wall_time::Union{Float64,Nothing}
end

TaskModule.get_result_codes(::_TaskPageProbeTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::_TaskPageProbeTask) = task.name
TaskModule.get_task_columns(::_TaskPageProbeTask) = ["name" => 2]
TaskModule.format_task_column(task::_TaskPageProbeTask, column::AbstractString) = column == "name" ? task.name : ""

# A part that the kind of the probe links to among its facts.
const _TASK_PAGE_LINKED = PrimitiveString("the linked part")
TaskModule.get_task_links(task::_TaskPageProbeTask) =
    [(label = "linked", text = "the part of " * task.name, document = _TASK_PAGE_LINKED, reference = EmptyReference())]
TaskModule.find_task_output_mark(::_TaskPageProbeTask, stream::Symbol, line::AbstractString) =
    startswith(line, "error") ? :error : startswith(line, "progress") ? :progress : nothing

function TaskModule.start_task(task::_TaskPageProbeTask; on_finish = nothing)
    execution = TaskExecution(task)
    finish = function (process, cancelled, elapsed)
        code = cancelled ? "CANCEL" : process.exitcode == 0 ? "DONE" : "ERROR"
        finish_task_execution!(execution, _TaskPageProbeResult(task, code, "DONE", nothing, elapsed);
                               finish = on_finish)
    end
    start_process_task!(execution, `sh -c $(task.script)`; finish)
end

# A group of two tasks, run to the end: the first prints 300 lines, an error line
# and a progress line.
function _make_task_page_group()
    tasks = [_TaskPageProbeTask("printer", "seq 1 300 | sed 's/^/line /'; echo 'error here'; echo 'progress 5'"),
             _TaskPageProbeTask("quiet", "exit 0")]
    document = wrap_task_group_document(TaskGroup(tasks; name = "pages", jobs = 2); title = "page tasks")
    wait_task_group_document(start_task_group_document!(document))
    document
end

_press_task_page(projection, iomap, t; ctrl = false) = read_intent(projection, iomap,
    MouseClick(:left, t[1] + 2, t[2] + 2, 1, ModifierKeys(ctrl = ctrl); time = 0.0))

_find_task_page_text(iomap, text) = only(t for t in _collect_task_view_texts(iomap.output) if t[3] == text)

function test_task_pages()
    @testset "task pages" begin
        group = _make_task_page_group()
        document = getfield(group, :tasks)[][1]

        @testset "a task knows its group and has a title" begin
            @test find_task_document_group(document) == (group, 1)
            @test get_document_title(document) == "printer"
            @test get_document_title(group) == "page tasks"
            @test find_task_document_group(TaskDocument(_TaskPageProbeTask("alone", "exit 0"))) === nothing
        end

        @testset "the page of a task links to its group, its executions and its streams" begin
            projection, iomap = _print_task_view(document)
            words = [t[3] for t in _collect_task_view_texts(iomap.output)]
            @test "printer" in words && "Stop" in words && "Run again" in words && "Executions" in words
            @test "stdout · 302 lines" in words && "line 300" in words && "progress 5" in words
            opened = _press_task_page(projection, iomap, _find_task_page_text(iomap, "in page tasks"))
            @test opened isa OpenPageOperation && opened.document === group
            opened = _press_task_page(projection, iomap, _find_task_page_text(iomap, "1"))
            @test opened isa OpenPageOperation && opened.document === document
            @test evaluate_reference(document, opened.reference) === only(getfield(document, :executions)[])
            opened = _press_task_page(projection, iomap, _find_task_page_text(iomap, "Open stdout"); ctrl = true)
            @test opened.place === :new_tab
            @test evaluate_reference(document, opened.reference) isa TaskStream
            # The kind links to a part among the facts.
            @test "linked" in words && "the part of printer" in words
            opened = _press_task_page(projection, iomap, _find_task_page_text(iomap, "the part of printer"))
            @test opened isa OpenPageOperation && opened.document === _TASK_PAGE_LINKED
        end

        @testset "the page of an execution links to its streams" begin
            shadow = only(getfield(document, :executions)[])
            @test startswith(get_document_title(shadow), "execution ")
            projection, iomap = _print_task_view(shadow)
            words = [t[3] for t in _collect_task_view_texts(iomap.output)]
            @test "printer" in words && "stderr · 0 lines" in words && "the part of printer" in words
            opened = _press_task_page(projection, iomap, _find_task_page_text(iomap, "Open stderr"))
            @test opened isa OpenPageOperation && opened.document === shadow
            @test evaluate_reference(shadow, opened.reference) === shadow.stderr_page
        end

        @testset "the page of a stream shows the lines that fit, and follows the end" begin
            shadow = only(getfield(document, :executions)[])
            stream = shadow.stdout_page
            @test get_document_title(stream) == "stdout"
            lines = stream.lines
            @test collect_task_stream_rows(lines) == 1:302
            words = [t[3] for t in _collect_task_view_texts(last(_print_task_view(stream; height = 600)).output)]
            @test "302 lines · 1 error · 1 progress" in words
            @test "progress 5" in words && "302" in words && !("line 1" in words)
            # The lines that hold a text, and the count of them.
            lines.filter_text = "error"
            @test collect_task_stream_rows(lines) == [301]
            words = [t[3] for t in _collect_task_view_texts(last(_print_task_view(stream; height = 600)).output)]
            @test "error here" in words && !("line 300" in words) && any(w -> endswith(w, "1 shown"), words)
            lines.filter_text = ""
        end

        @testset "find, the first error and the wheel move the line at the top" begin
            lines = only(getfield(document, :executions)[]).stdout_page.lines
            holder = _NavHolder(lines)
            lines.find_text = "line 25"
            @test find_task_stream_matches(lines) == vcat(25, 250:259)
            _nav_apply!(holder, make_task_stream_find_operation(lines, 1))
            @test lines.found_line == 25 && lines.top_row == 22 && !lines.follow
            _nav_apply!(holder, make_task_stream_find_operation(lines, 1))
            @test lines.found_line == 250
            _nav_apply!(holder, make_task_stream_find_operation(lines, -1))
            @test lines.found_line == 25
            _nav_apply!(holder, make_task_stream_first_error_operation(lines))
            @test lines.found_line == 301 && lines.top_row == 298
            lines.find_text = "absent"
            @test make_task_stream_find_operation(lines, 1) === nothing
            # A notch of the wheel down moves the top by three lines, and at the last
            # lines the page follows the end again.
            stream = only(getfield(document, :executions)[]).stdout_page
            projection, iomap = _print_task_view(stream; height = 600)
            point = _find_task_page_text(iomap, "302")
            answer = read_intent(projection, iomap, MouseScroll(0, -1, point[1], point[2], ModifierKeys(), 0.0))
            @test answer isa Operation
            _nav_apply!(holder, answer)
            @test lines.follow
            _nav_apply!(holder, read_intent(projection, iomap, MouseScroll(0, 5, point[1], point[2], ModifierKeys(), 0.0)))
            @test !lines.follow && lines.top_row < 298
        end

        # The pages in a window, as a person reaches them: the page of the group in
        # a navigator, a double press on the row of a task, the link to its stdout,
        # and a key in the field of Find.
        @testset "in a window, a group opens a task, the task its stream, and a key reaches Find" begin
            navigator = Navigator(group)
            editor, backend = _nav_editor(navigator)
            row = _nav_click(backend, "printer")
            @test row !== nothing
            _nav_press!(editor, backend, MouseClick(:left, row.x, row.y, 1, ModifierKeys(); time = 0.0))
            @test getfield(group, :selected)[] == 1
            _nav_press!(editor, backend, MouseClick(:left, row.x, row.y, 2, ModifierKeys(); time = 0.0))
            @test get_navigator_page(navigator) === document
            link = _nav_click(backend, "Open stdout")
            @test link !== nothing
            _nav_press!(editor, backend, link)
            stream = only(getfield(document, :executions)[]).stdout_page
            @test get_navigator_page(navigator) === stream
            @test _nav_has_text(backend, "302 lines · 1 error · 1 progress")
            lines = stream.lines
            lines.find_text = "lin"
            run_frame!(editor)
            field = _nav_click(backend, "lin")
            @test field !== nothing
            _nav_press!(editor, backend, field)
            _nav_press!(editor, backend, KeyDown(:end, ModifierKeys(); time = 0.0))
            for character in "e 25"
                _nav_press!(editor, backend, KeyPress(character, string(character), ModifierKeys(); time = 0.0))
            end
            @test lines.find_text == "line 25"
            @test _nav_has_text(backend, "11 matches")
        end
    end
end
