# The find and the filter of a tab that shows a JSON file through its views: Ctrl+F
# and the menu of a value put the arrangement around the view of the file, at the list
# of the views of the elements, where the caret is. The test asks for no more: the
# printer of a JSON array reads no arrangement, so the find shows no count and a
# filter hides no element, with views and with no view.

function test_json_tab_arrangement()
@testset "the find and the filter of a tab wrap the view of a JSON file" begin
    names = ["pear", "apple", "fig", "grape", "papaya"]
    file = JsonFile("a.json", parse_json("[" * join(repr.(names), ", ") * "]"))
    view = make_file_view(file)
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    backend = HeadlessBackend()
    editor = build_editor(view, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = true, appearance = false, settings = false)
    run_frame!(editor)
    tab = only(editor.document.root.tabs)
    frame!() = (drain_operations!(editor); run_frame!(editor))
    press!(events...) = (ProjecturedPlatformTest._arrangement_press!(editor, backend, events...); frame!())
    place(text) = ProjecturedPlatformTest._arrangement_place(backend, text)
    texts() = ProjecturedPlatformTest._arrangement_texts(backend)
    (x, y) = place("apple")
    press!(MouseMove(x, y; time = 0.0), MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0))
    # The caret is in the view of the second element.
    @test string(strip_reference_types(editor.document.selection)) ==
          ".root.tabs[1].content.content.elements[2].value{0}"

    @testset "Ctrl+F puts the first arrangement around the view, with a find at the list of the caret" begin
        press!(ProjecturedPlatformTest._arrangement_key_event(:f, ModifierKeys(; ctrl = true)))
        @test tab.content isa ArrangementDocument && tab.content.document === view
        @test is_in_find_field(tab.content)
        entry = only(tab.content.entries)
        # The entry names the list of the views of the elements.
        @test string(strip_reference_types(entry.at)) == ".content.elements"
        @test evaluate_reference(view, entry.at) isa CellVectorView
        @test only(entry.projections) isa ArrangementFind
        # The file and its elements are as they were.
        @test filter(in(names), texts()) == names
        @test [element.value for element in get_file_content(file).elements] == names
    end

    @testset "the menu of a value offers the filters and the sorts, and its choice arranges the tab" begin
        (x, y) = place("fig")
        ProjecturedPlatformTest._arrangement_press!(editor, backend, MouseMove(x, y; time = 0.0))
        click = MouseClick(:right, x, y, 1, ModifierKeys(); time = 0.0)
        open = read_intent(editor.projection, nothing, Intent(click), editor.iomap).operation
        open isa WrappingOperation && (open = get_wrapped_operation(open))
        @test open isa OpenContextMenuOperation
        labels = [item.action.label for (_, menu) in open.layers for item in menu.elements if item isa WidgetMenuItem]
        @test issubset(["Show only items like this", "Hide items like this", "Sort by this, ascending",
                        "Sort by this, descending", "Filter by text…", "Show all"], labels)
        item = only(item for (_, menu) in open.layers for item in menu.elements
                    if item isa WidgetMenuItem && item.action.label == "Hide items like this")
        part = annotate_reference_types(editor.document, find_menu_item_part(open, item.operation))
        @test string(strip_reference_types(part)) == ".root.tabs[1].content"
        rooted = read_rooted_operation(editor, part, item.operation)
        @test rooted isa Operation
        evaluate_operation(editor, rooted)
        frame!()
        @test tab.content isa ArrangementDocument
        @test [element.value for element in get_file_content(file).elements] == names
    end
end
end
