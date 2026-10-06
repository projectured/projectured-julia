# The page of a row: the form of its columns, and a navigator over the view of a
# frame, where a person opens a row from the table and goes back to the table with
# the row still selected. With no navigator, the menu of a row opens a tab with a
# navigator on the row.

import ProjecturedKernel.EditorModule: read_rooted_operation, drain_operations!

function test_data_frame_row_page()
@testset "the page of a row" begin
    make_frame() = DataFrame(id = [101, 102, 103], name = ["a", "b", "c"])
    natural() = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    force(value) = value isa AbstractCell ? force(value[]) : value
    # An editor in a window of a fixed size, which the table of a frame needs for
    # its height, after its first frame.
    function open_editor(document; tabs = false)
        backend = _ColumnWidthBackend()
        editor = build_editor(document, natural(); backend, devices = Device[Keyboard(), Mouse(), Display()],
                              tabs, appearance = false, settings = false,
                              window = (; title = "W", width = 700, height = 400,
                                        opened_window_projections = Pair{Type,Any}[Document => natural()]))
        run_frame!(editor)
        (editor, backend)
    end
    windows(editor) = collect(force(force(get_iomap_output(editor.iomap)).windows))
    window(editor) = first(windows(editor))
    texts(editor) = _data_frame_texts(force(window(editor).content); limit = 1000)
    shows(editor, text) = any(t -> t[3] == text, texts(editor))
    input(editor, event) = WindowInput(window(editor).id, event)
    press!(editor, backend, event) = (push!(backend.events, input(editor, event)); run_frame!(editor))
    key(k; ctrl = false) = KeyDown(k, ModifierKeys(; ctrl); time = 0.0)
    # The header of row `r`: the lowest drawn text `string(r)`, below the corner.
    function header(editor, r)
        (x, y) = last(sort([(t[1], t[2]) for t in texts(editor) if t[3] == string(r)]; by = last))
        (x + 2, y + 2)
    end
    click(place; count = 1, button = :left) = MouseClick(button, place..., count, ModifierKeys(); time = 0.0)
    steps(reference) = get_reference_steps(strip_reference_types(reference))
    # The menu in the answer of a right click, inside a compound or a wrapper.
    find_menu(operation::OpenContextMenuOperation) = operation
    find_menu(operation::WrappingOperation) = find_menu(get_wrapped_operation(operation))
    function find_menu(operation::CompoundOperation)
        for member in operation.operations
            found = find_menu(member)
            found === nothing || return found
        end
        nothing
    end
    find_menu(operation) = nothing
    whole_row(r) = Reference(FieldReferenceStep("rows"), RangeReferenceStep(r - 1, r))

    @testset "the form shows the name and the value of each column, and follows the frame" begin
        view = DataFrameView(make_frame())
        row = view.rows[2]
        p = make_data_frame_row_projection()
        iomap = print_document(p, nothing, row, nothing)
        form = iomap.output.children[1].content
        @test [label.content for label in form.children] == ["id", "102", "name", "b"]
        # The cell of column 2 is the value of the name, and a press there selects it.
        image = map_reference_forward(p, iomap, Reference(RangeReferenceStep(1, 2)))
        @test is_fully_typed_reference(image)
        @test evaluate_reference(iomap.output, image) === form.children[4]
        @test steps(map_reference_backward(p, iomap, image)) == [RangeReferenceStep(1, 2)]
        @test map_reference_backward(p, iomap, EmptyReference()) isa EmptyReference
        # A write of the frame shows on the page.
        evaluate_operation(nothing, SetDataFrameValueOperation(view, 2, "name", "z"))
        @test [label.content for label in iomap.output.children[1].content.children][4] == "z"
        @test get_document_title(row) == "row 2"
    end

    @testset "the table, a row as a page, and Back to the table with the row selected" begin
        view = DataFrameView(make_frame())
        navigator = Navigator(view)
        editor, backend = open_editor(navigator)
        @test shows(editor, "102")
        # A press on the header of row 2 selects the row, and Ctrl+Return opens it.
        press!(editor, backend, click(header(editor, 2)))
        @test steps(navigator.selection) == [FieldReferenceStep("content"), steps(whole_row(2))...]
        press!(editor, backend, key(:return; ctrl = true))
        @test get_navigator_page(navigator) === view.rows[2]
        @test shows(editor, "name") && shows(editor, "b") && shows(editor, "row 2")
        @test !shows(editor, "rows")
        @test !shows(editor, "103")
        # Back returns to the table, with the row selected as before.
        press!(editor, backend, key(:left_bracket; ctrl = true))
        @test get_navigator_page(navigator) === view
        @test steps(navigator.selection) == [FieldReferenceStep("content"), steps(whole_row(2))...]
        @test shows(editor, "103")
        # Forward opens the row again; Parent returns to the table.
        press!(editor, backend, key(:right_bracket; ctrl = true))
        @test get_navigator_page(navigator) === view.rows[2]
        press!(editor, backend, key(:up; ctrl = true))
        # Parent passes over the rows of the view, to the table.
        @test get_navigator_page(navigator) === view
    end

    @testset "a double click on a row header opens the row" begin
        view = DataFrameView(make_frame())
        navigator = Navigator(view)
        editor, backend = open_editor(navigator)
        press!(editor, backend, click(header(editor, 3); count = 2))
        @test get_navigator_page(navigator) === view.rows[3]
    end

    # A right press on the header of row `r` opens the menu of the row in a window
    # of its own, and a press on its item `label` chooses it.
    function choose!(editor, backend, r, label)
        main = window(editor).id
        send!(event, id) = (push!(backend.events, WindowInput(id, event)); run_frame!(editor))
        function click!(button, (x, y), time, id)
            send!(MouseDown(button, x, y, ModifierKeys(); time), id)
            send!(MouseUp(button, x, y, ModifierKeys(); time = time + 0.05), id)
        end
        click!(:right, header(editor, r), 1.0, main)
        menu = only(w for w in windows(editor) if w.id !== main)
        (x, y) = only((t[1], t[2]) for t in _data_frame_texts(force(menu.content); limit = 1000)
                      if t[3] == label)
        click!(:left, (x + 2, y + 2), 1.5, menu.id)
    end

    @testset "in a tab, an item of the menu of a row reaches the row" begin
        view = DataFrameView(make_frame())
        editor, backend = open_editor(view; tabs = true)
        choose!(editor, backend, 2, "Insert row above")
        @test nrow(view.frame) == 4
    end

    @testset "with no navigator, the menu of a row opens a tab with a navigator on the row" begin
        view = DataFrameView(make_frame())
        editor, backend = open_editor(view; tabs = true)
        choose!(editor, backend, 2, "Open as a page")
        drain_operations!(editor)
        run_frame!(editor)
        tabs = get_window_tree(; editor).root.tabs
        @test length(tabs) == 2
        @test tabs[2].content isa Navigator
        @test tabs[2].content.content === view
        @test get_navigator_page(tabs[2].content) === view.rows[2]
    end
end
end
