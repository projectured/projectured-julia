# The table of the pane of a group: an arrangement of a roster of its tasks, held in
# the field `table` of the group. A press on a row writes `selected`, the row of the
# task at `selected` is marked, the list starts at `anchor`, the choice of rows says
# which tasks the roster lists, and the header filters and sorts as every roster table
# does.

# A kind of task with two columns of its own, which are values of the task.
struct _TaskTableProbeTask <: AbstractTask
    name::String
    configuration::String
    script::String
end
TaskModule.get_result_codes(::_TaskTableProbeTask) = RUN_RESULT_CODES
TaskModule.format_task_parameters(task::_TaskTableProbeTask) = task.name
TaskModule.get_task_columns(::_TaskTableProbeTask) = ["test" => 2, "configuration" => 1]
TaskModule.format_task_column(task::_TaskTableProbeTask, column::AbstractString) =
    column == "test" ? task.name : column == "configuration" ? task.configuration : ""
TaskModule.start_task(task::_TaskTableProbeTask; on_finish = nothing) =
    TaskModule.start_task(_TaskGroupProbeTask(task.name, task.script); on_finish)

function test_task_group_table()
@testset "the table of the pane of a group is a roster in an arrangement" begin
    # Five tasks that run one at a time: three end, the fourth runs and the fifth waits.
    function make_group()
        tasks = [_TaskTableProbeTask("alpha", "debug", "sleep 0.1; exit 0"),
                 _TaskTableProbeTask("beta", "release", "sleep 0.3; exit 1"),
                 _TaskTableProbeTask("gamma", "debug", "sleep 0.2; exit 0"),
                 _TaskTableProbeTask("delta", "release", "sleep 60"),
                 _TaskTableProbeTask("epsilon", "debug", "exit 0")]
        group = wrap_task_group_document(TaskGroup(tasks; name = "table", jobs = 1); title = "table group")
        start_task_group_document!(group)
        deadline = time() + 60
        while get_task_document_status(getfield(group, :tasks)[][4]) !== :running && time() < deadline
            drain_task_feed!()
            sleep(0.05)
        end
        drain_task_feed!()
        group
    end
    function make_editor(group; height = 900)
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = true, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        show_pane!(open_pane!(group; title = "table", editor); editor)
        drain_operations!(editor)
        run_frame!(editor)
        (editor, backend, first(editor.iomap.output.windows))
    end
    frame!(editor) = (drain_operations!(editor); run_frame!(editor))
    function press!(editor, backend, window, x, y; count = 1, ctrl = false, shift = false, button = :left)
        push_event!(backend, WindowInput(window.id, MouseMove(x, y; time = 0.0)))
        push_event!(backend, WindowInput(window.id, MouseClick(button, x, y, count, ModifierKeys(; ctrl, shift); time = 0.0)))
        frame!(editor)
    end
    drawn(window) = _arrangement_drawn(window.content)
    place(window, text) = (entries = drawn(window); entry = entries[findlast(e -> e[1] == text, entries)];
                           (entry[2] + 2, entry[3] + 2))
    texts(window) = first.(drawn(window))
    tasks_of(group) = collect(getfield(group, :tasks)[])
    names_of(rows) = [format_task_parameters(getfield(peek(getfield(row, :item)), :task)[]) for row in rows]
    roster_of(group) = group.table.document
    key_of(column) = extend_reference(EmptyReference(), FieldReferenceStep(column))
    table_of(editor) = _find_roster_iomap_of(editor.iomap, RosterRowsToWidgetIoMap)
    @testset "the roster lists the tasks of the group, with the shares and the columns of the group" begin
        group = make_group()
        roster = roster_of(group)
        @test roster.link === group
        @test names_of(roster.rows) == ["alpha", "beta", "gamma", "delta", "epsilon"]
        @test roster.columns == ["state", "test", "configuration", "progress", "elapsed", "process", "processor",
                                 "memory", "result", "expected", "reason"]
        @test roster.shares == [1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 4]
        @test getfield(group, :shown)[] === getfield(group, :tasks)[]
        stop_task_group_document!(group)
    end

    @testset "the filter field of a column is as wide as the column, so the shares show" begin
        group = make_group()
        # A window of 2400 px holds the 11 columns above their minimum, so each takes its share.
        canvas = last(_print_task_view(group; width = 2400)).output
        entries = _arrangement_drawn(canvas)
        label_x(label) = entries[findfirst(e -> e[1] == label, entries)][2]
        label_y = entries[findfirst(e -> e[1] == "state", entries)][3]
        # The drawn boxes of the fields: the rounded boxes with a border in the band under the labels.
        function boxes(canvas, ox = 0, oy = 0, found = Tuple{Int,Int,Int}[])
            x, y = ox + Int(canvas.x), oy + Int(canvas.y)
            for element in canvas.elements
                element = element isa Cell ? element[] : element
                element = element isa ListNode ? element.value : element
                if element isa GraphicsRect && element.border_width > 0 && element.radius_tl > 0 &&
                   label_y + 8 <= y + Int(element.y) <= label_y + 40 && element.w > 20
                    push!(found, (x + Int(element.x), Int(element.w), y + Int(element.y)))
                elseif element isa GraphicsCanvas
                    boxes(element, x, y, found)
                elseif element isa GraphicsViewport
                    boxes(element.content, x + Int(element.x) + round(Int, element.transform.e),
                          y + Int(element.y) + round(Int, element.transform.f), found)
                end
            end
            found
        end
        fields = sort(unique(boxes(canvas)))
        @test length(fields) >= 4
        width_of(label) = fields[findfirst(f -> abs(f[1] - label_x(label)) <= 12, fields)][2]
        # The drawn pitch of a column is its width and the padding of its cell.
        pitch_state = label_x("test") - label_x("state")
        pitch_test = label_x("configuration") - label_x("test")
        @test pitch_test > pitch_state
        @test pitch_state - width_of("state") == pitch_test - width_of("test")
        @test 0 <= pitch_state - width_of("state") <= 40
        @test width_of("test") > width_of("state")
        stop_task_group_document!(group)
    end

    @testset "the choice of rows chooses the tasks that the roster lists" begin
        group = make_group()
        roster = roster_of(group)
        choice = getfield(group, :row_filter)[]
        choice.value = "running"
        @test names_of(roster.rows) == ["delta"]
        choice.value = "unexpected"
        @test names_of(roster.rows) == ["beta"]
        choice.value = "all"
        @test names_of(roster.rows) == ["alpha", "beta", "gamma", "delta", "epsilon"]
        @test getfield(group, :shown)[] === getfield(group, :tasks)[]
        stop_task_group_document!(group)
    end

    @testset "a press on a row writes selected, and the row of selected is marked" begin
        group = make_group()
        (editor, backend, window) = make_editor(group)
        @test all(text -> text in texts(window), ["state", "test", "configuration", "reason", "alpha", "gamma"])
        roster = roster_of(group)
        @test roster.marked === nothing
        press!(editor, backend, window, place(window, "gamma")...)
        @test getfield(group, :selected)[] == 3
        @test roster.marked === tasks_of(group)[3]
        table = table_of(editor).table
        @test get_widget_table_selected_row(table) == 3
        press!(editor, backend, window, place(window, "alpha")...)
        @test getfield(group, :selected)[] == 1 && get_widget_table_selected_row(table) == 1
        stop_task_group_document!(group)
    end

    # The answer of the pane, printed as a tab prints it, to a click on the drawn text `text`.
    function click_answer(group, text; count = 1, ctrl = false)
        projection, iomap = _print_task_view(group)
        row = only(t for t in _collect_task_view_texts(iomap.output) if t[3] == text)
        operation = read_intent(projection, iomap,
                                MouseClick(:left, row[1] + 2, row[2] + 2, count, ModifierKeys(; ctrl); time = 0.0))
        operation isa WrappingOperation ? get_wrapped_operation(operation) : operation
    end

    @testset "a double press opens the page of the task, and Ctrl+press opens it in a new tab" begin
        group = make_group()
        opened = click_answer(group, "gamma"; count = 2)
        @test opened isa OpenPageOperation && opened.document === group && opened.place === :here
        @test evaluate_reference(group, opened.reference) === tasks_of(group)[3]
        @test click_answer(group, "gamma"; ctrl = true).place === :new_tab
        answer = click_answer(group, "gamma")
        written = get_wrapped_operation(answer.operations[1])
        @test written isa ReplaceReferencedValueOperation && written.value == 3
        @test answer.operations[2] isa ReplaceSelectionOperation
        stop_task_group_document!(group)
    end

    @testset "the roster of a running choice opens a task at its place in the group" begin
        group = make_group()
        getfield(group, :row_filter)[].value = "running"
        opened = click_answer(group, "delta"; count = 2)
        @test opened isa OpenPageOperation && evaluate_reference(group, opened.reference) === tasks_of(group)[4]
        @test get_reference_steps(strip_reference_types(opened.reference))[1] == FieldReferenceStep("tasks")
        stop_task_group_document!(group)
    end

    @testset "a filter typed under test keeps its task, and one undo takes it back" begin
        group = make_group()
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(PrimitiveString("start"), natural; backend,
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false, undo = true)
        run_frame!(editor)
        show_document!(group; title = "table", editor)
        frame!(editor)
        # The first text of a field makes the arrangement its first entry; a later run of
        # typing in another field is one step of undo.
        function type_in!(label, text)
            (x, y) = _arrangement_place(backend, label)
            _arrangement_press!(editor, backend, MouseMove(x + 10, y + 30; time = 0.0),
                                MouseClick(:left, x + 10, y + 30, 1, ModifierKeys(); time = 0.0))
            frame!(editor)
            for char in text
                _arrangement_press!(editor, backend, KeyPress(char; time = 0.0))
                frame!(editor)
            end
        end
        type_in!("configuration", "debug")
        @test names_of(table_of(editor).input) == ["alpha", "gamma", "epsilon"]
        type_in!("test", "gam")
        entry = only(group.table.entries)
        @test [(c.key, c.operator, c.value) for c in only(entry.projections).conditions] ==
              [(key_of("configuration"), :matches, "debug"), (key_of("test"), :matches, "gam")]
        @test names_of(table_of(editor).input) == ["gamma"]
        _arrangement_press!(editor, backend, KeyDown(:z, ModifierKeys(; ctrl = true); time = 0.0))
        frame!(editor)
        @test names_of(table_of(editor).input) == ["alpha", "gamma", "epsilon"]
        stop_task_group_document!(group)
    end

    @testset "Return shows the detail alone, Up and Down follow the order of the table, Escape shows the table" begin
        group = make_group()
        (editor, backend, window) = make_editor(group)
        key!(event) = (push_event!(backend, WindowInput(window.id, event)); frame!(editor))
        # The filter keeps the debug tasks, and the sort puts their names in the reverse order.
        (x, y) = place(window, "configuration")
        press!(editor, backend, window, x + 10, y + 30)
        for char in "debug"
            key!(KeyPress(char; time = 0.0))
        end
        push!(only(group.table.entries).projections,
              ArrangementSort(Any[ArrangementSortKey(key_of("test"), :descending)]))
        frame!(editor)
        @test names_of(table_of(editor).input) == ["gamma", "epsilon", "alpha"]
        # While the detail is not alone, Up and Down are not the group's: they do not change the task.
        press!(editor, backend, window, place(window, "gamma")...)
        @test getfield(group, :selected)[] == 3 && !getfield(group, :is_detail_alone)[]
        key!(KeyDown(:down, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 3 && !getfield(group, :is_detail_alone)[]
        key!(KeyPress('\n'; time = 0.0))
        @test getfield(group, :is_detail_alone)[] && getfield(group, :selected)[] == 3
        @test !("configuration" in texts(window)) && !("alpha" in texts(window))
        @test any(startswith("gamma"), texts(window))
        key!(KeyDown(:down, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 5 && getfield(group, :is_detail_alone)[]
        @test any(startswith("epsilon"), texts(window))
        key!(KeyDown(:down, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 1 && any(startswith("alpha"), texts(window))
        key!(KeyDown(:down, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 1
        key!(KeyDown(:up, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 5 && getfield(group, :is_detail_alone)[]
        key!(KeyDown(:up, ModifierKeys(); time = 0.0))
        key!(KeyDown(:up, ModifierKeys(); time = 0.0))
        @test getfield(group, :selected)[] == 3 && getfield(group, :is_detail_alone)[]
        key!(KeyDown(:escape, ModifierKeys(); time = 0.0))
        @test !getfield(group, :is_detail_alone)[] && "configuration" in texts(window)
        @test names_of(table_of(editor).input) == ["gamma", "epsilon", "alpha"]
        @test getfield(group, :selected)[] == 3
        stop_task_group_document!(group)
    end

    @testset "the group reads Return, Escape, Up and Down only, and the others pass" begin
        patterns = [string(binding.pattern) for binding in collect_document_gesture_bindings(TaskGroupDocument)]
        @test length(patterns) == 4 && !any(occursin("left", lowercase(p)) || occursin("right", lowercase(p)) for p in patterns)
        group = make_group()
        (editor, backend, window) = make_editor(group)
        key!(event) = (push_event!(backend, WindowInput(window.id, event)); frame!(editor))
        press!(editor, backend, window, place(window, "gamma")...)
        key!(KeyPress('\n'; time = 0.0))
        @test getfield(group, :is_detail_alone)[]
        for event in (KeyDown(:left, ModifierKeys(); time = 0.0), KeyDown(:right, ModifierKeys(); time = 0.0),
                      KeyPress('x'; time = 0.0))
            key!(event)
            @test getfield(group, :is_detail_alone)[] && getfield(group, :selected)[] == 3
        end
        stop_task_group_document!(group)
    end

    @testset "a click on the sort glyph of elapsed sorts the rows" begin
        group = make_group()
        (editor, backend, window) = make_editor(group)
        glyphs = sort([(x, y) for (text, x, y) in drawn(window) if text in string.(Char.((0xe37d, 0xe04a, 0xe042)))])
        names = [text for (text, _, _) in drawn(window)]
        elapsed = findfirst(==("elapsed"), [text for (text, _, _) in sort(filter(e -> e[1] in ("state", "test",
            "configuration", "progress", "elapsed", "process", "processor", "memory", "result", "expected", "reason"),
            drawn(window)); by = e -> e[2])])
        @test elapsed == 5 && length(glyphs) >= 5
        press!(editor, backend, window, glyphs[elapsed][1] + 2, glyphs[elapsed][2] + 2)
        entry = only(group.table.entries)
        @test [(k.key, k.direction) for k in only(entry.projections).keys] == [(key_of("elapsed"), :ascending)]
        shown = names_of(table_of(editor).input)
        @test length(shown) == 5 && Set(shown) == Set(["alpha", "beta", "gamma", "delta", "epsilon"])
        stop_task_group_document!(group)
    end

    @testset "the choice running with a filter lists the running tasks that the filter keeps" begin
        group = make_group()
        (editor, backend, window) = make_editor(group)
        getfield(group, :row_filter)[].value = "running"
        frame!(editor)
        (x, y) = place(window, "test")
        press!(editor, backend, window, x + 10, y + 30)
        for char in "delta"
            push_event!(backend, WindowInput(window.id, KeyPress(char; time = 0.0)))
            frame!(editor)
        end
        @test names_of(table_of(editor).input) == ["delta"]
        getfield(group, :row_filter)[].value = "unexpected"
        frame!(editor)
        @test isempty(table_of(editor).input)
        getfield(group, :row_filter)[].value = "all"
        frame!(editor)
        @test names_of(table_of(editor).input) == ["delta"]
        stop_task_group_document!(group)
    end

    @testset "the arrangement stays when its last description goes" begin
        group = make_group()
        (editor, backend, window) = make_editor(group)
        (x, y) = place(window, "test")
        press!(editor, backend, window, x + 10, y + 30)
        push_event!(backend, WindowInput(window.id, KeyPress('a'; time = 0.0)))
        frame!(editor)
        @test length(group.table.entries) == 1
        push_event!(backend, WindowInput(window.id, KeyDown(:backspace, ModifierKeys(); time = 0.0)))
        frame!(editor)
        @test group.table isa ArrangementDocument && isempty(group.table.entries)
        @test names_of(table_of(editor).input) == ["alpha", "beta", "gamma", "delta", "epsilon"]
        # The next filter has an arrangement to go to.
        (x, y) = place(window, "test")
        press!(editor, backend, window, x + 10, y + 30)
        push_event!(backend, WindowInput(window.id, KeyPress('g'; time = 0.0)))
        frame!(editor)
        @test names_of(table_of(editor).input) == ["gamma"]
        stop_task_group_document!(group)
    end

    @testset "the list starts at the anchor of the group, and a scroll far from the head writes it" begin
        tasks = AbstractTask[_TaskTableProbeTask(string("task ", k), "debug", "exit 0") for k in 1:400]
        group = wrap_task_group_document(TaskGroup(tasks; name = "long", jobs = 1))
        (editor, backend, window) = make_editor(group)
        table = table_of(editor)
        @test table.head == 1
        set_cell_value!(getfield(group, :anchor), 120)
        frame!(editor)
        @test table.head == 120 && "task 120" in texts(window)
        # The head is the first row after the anchor that the choice shows.
        (x, y) = place(window, "task 121")
        for _ in 1:300
            push_event!(backend, WindowInput(window.id, MouseScroll(0, -10, x, y; time = 0.0)))
            frame!(editor)
            getfield(group, :anchor)[] > 200 && break
        end
        @test getfield(group, :anchor)[] > 200
        @test getfield(group, :table)[].document.anchor === tasks_of(group)[getfield(group, :anchor)[]]
    end
end
end
