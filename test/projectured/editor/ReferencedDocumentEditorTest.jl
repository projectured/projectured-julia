# A referenced document in the application window: a tab found by its title, the
# data a file tab shows reached through the file and its history, and a read into
# that data that holds the reference to its place.

using Test

# A document whose slice gives its tab an icon and a tooltip.
@document struct ReferencedTitledNote
    text::Any
end

PaneModule.make_pane_tab_title(::ReferencedTitledNote, name::AbstractString) =
    PaneTabTitle(name; icon = :loader, tooltip = "a note")

function _make_referenced_application(directory; paths = nothing)
    if paths === nothing
        write(joinpath(directory, "people.json"),
              "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}]")
        paths = [joinpath(directory, "people.json")]
    end
    document, projection = make_application_window(paths; root = directory, assistant = nothing)
    editor = build_editor(document, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    editor
end

function test_referenced_document_editor()
@testset "ReferencedDocument in the application" begin
    directory = mktempdir()
    editor = _make_referenced_application(directory)

    @testset "find_pane answers the tab and where it is" begin
        people_tab = find_pane("people.json"; editor)
        @test people_tab isa ReferencedDocument
        @test get_document(people_tab) isa PaneTab
        @test evaluate_reference(editor.document, get_reference(people_tab)) === get_document(people_tab)
        @test find_pane("no such tab"; editor) === nothing
    end

    @testset "get_edited_document reaches the data through the file and its history" begin
        people_tab = find_pane("people.json"; editor)
        people = get_edited_document(people_tab)
        @test people isa ReferencedDocument
        @test get_document(people) isa JsonArray
        @test evaluate_reference(editor.document, get_reference(people)) === get_document(people)
        # A document that is not referenced answers the document.
        @test get_edited_document(get_document(people_tab).content) === get_document(people)
        @test get_edited_document(get_document(people)) === get_document(people)
    end

    @testset "a read into the data keeps its reference" begin
        people = get_edited_document(find_pane("people.json"; editor))
        first_person = people.elements[1]
        @test get_document(first_person) isa JsonObject
        @test evaluate_reference(editor.document, get_reference(first_person)) === get_document(first_person)
        @test [entry.key for entry in first_person.entries] == ["name", "age"]
    end

    @testset "an array iterates and an object reads by key, keeping references" begin
        people = get_edited_document(find_pane("people.json"; editor))
        @test [person["name"].value for person in people] == ["Cleo", "Ada"]
        @test [person["age"].value for person in people] == [29, 36]
        second_name = people[2]["name"]
        @test get_document(second_name) isa JsonString
        @test evaluate_reference(editor.document, get_reference(second_name)) === get_document(second_name)
        rows = [[person["name"].value, person["age"].value] for person in people]
        @test sort(rows; by = first) == [["Ada", 36], ["Cleo", 29]]
        first_person = people[1]
        for (key, value) in first_person
            @test key isa String
            @test evaluate_reference(editor.document, get_reference(value)) === get_document(value)
        end
        @test keys(first_person) == ["name", "age"]
        @test_throws KeyError first_person["nme"]
    end

    @testset "a tab that shows a widget answers the widget" begin
        open_pane!(WidgetLabel("hello"); title = "Hello", editor)
        hello = get_edited_document(find_pane("Hello"; editor))
        @test get_document(hello) isa WidgetLabel
    end

    history = only(search_documents(editor.document,
                                    node -> node isa UndoBuffer && node.content isa PaneTree))
    tree = history.content
    focused_title() = let (group, index) = get_pane_focus(tree)
        get_pane_tab_title_string(group.tabs[index])
    end

    @testset "open_pane! puts a tab before a tab, at the end of a group, and beside it" begin
        people_tab = get_document(find_pane("people.json"; editor))
        group = only(g for g in get_pane_groups(tree) if any(t -> t === people_tab, g.tabs))
        index = findfirst(t -> t === people_tab, collect(group.tabs))

        before = open_pane!(PrimitiveString("before"); title = "Before",
                            target = find_pane("people.json"; editor), editor)
        @test group.tabs[index] === get_referenced_value(before; editor)
        @test before isa ReferencedDocument && get_document(before) === group.tabs[index]
        @test is_fully_typed_reference(get_reference(before))
        @test group.tabs[index + 1] === people_tab

        group_reference = concat_references(find_pane_tree_reference(; editor),
                                            only(search_references(tree, node -> node === group)))
        last_tab = open_pane!(PrimitiveString("last"); title = "Last", target = group_reference, editor)
        @test group.tabs[end] === get_referenced_value(last_tab; editor)

        groups = length(get_pane_groups(tree))
        steps = length(history.undo_entries)
        beside = open_pane!(PrimitiveString("beside"); title = "Beside",
                            target = find_pane("people.json"; editor), side = :right, editor)
        @test length(get_pane_groups(tree)) == groups + 1
        @test !any(t -> t === get_referenced_value(beside; editor), group.tabs)
        @test focused_title() == "Beside"
        @test length(history.undo_entries) == steps + 1

        @test_throws ArgumentError open_pane!(PrimitiveString("x");
                                              target = find_pane("Last"; editor), side = :middle, editor)
        @test_throws ArgumentError open_pane!(PrimitiveString("x"); group = group,
                                              target = find_pane("Last"; editor), editor)
    end

    @testset "open_pane! takes a title with an icon, badges and a tooltip" begin
        finished = Cell(1)
        title = PaneTabTitle("Tasks"; icon = :loader, tooltip = "the tasks",
                             badges = () -> Any[WidgetBadge(string(finished[], "/3"))])
        first_tab = get_document(open_pane!(PrimitiveString("tasks"); title, editor))
        @test get_pane_tab_title_string(first_tab) == "Tasks"
        @test first_tab.title.icon === :loader && first_tab.title.tooltip == "the tasks"
        # A name already taken gets a number, and the parts still follow their cells.
        second_tab = get_document(open_pane!(PrimitiveString("more"); title, editor))
        @test get_pane_tab_title_string(second_tab) == "Tasks (2)"
        finished[] = 2
        @test only(second_tab.title.badges).content == "2/3"
        @test only(first_tab.title.badges).content == "2/3"
        # A title with no name takes the name of the document.
        unnamed = get_document(open_pane!(PrimitiveString("x"); title = PaneTabTitle(""; icon = :file), editor))
        @test !isempty(get_pane_tab_title_string(unnamed)) && unnamed.title.icon === :file
    end

    @testset "a plain title takes the title that the slice of the document makes" begin
        note = get_document(open_pane!(ReferencedTitledNote("n"); title = "Note", editor))
        @test get_pane_tab_title_string(note) == "Note"
        @test note.title.icon === :loader && note.title.tooltip == "a note"
        # A `PaneTabTitle` that the caller gives keeps its own parts.
        own = get_document(open_pane!(ReferencedTitledNote("m");
                                      title = PaneTabTitle("Own"; icon = :file), editor))
        @test own.title.icon === :file && own.title.tooltip === nothing
        close_pane!(find_pane("Note"; editor); editor)
        close_pane!(find_pane("Own"; editor); editor)
    end

    @testset "the answer of open_pane! with a table says how many rows it shows" begin
        table_tab = open_pane!(WidgetTable(["name", "age"], [["Ada", 36], ["Bob", 41]]);
                               title = "Table", editor)
        # What the REPL and the answer of `execute_julia_code!` show.
        shown = repr(MIME"text/plain"(), table_tab)
        @test startswith(shown, "ReferencedDocument{PaneTab} at ")
        @test endswith(shown, "PaneTab(\"Table\", WidgetTable(2 rows × 2 columns: name, age))")
        @test occursin("WidgetTable(2 rows × 2 columns: name, age)",
                       execute_julia_code!(editor.tools, editor, "find_pane(\"Table\")"))
        # The form a `print` and a `show` write is as it was.
        @test !occursin("rows ×", repr(table_tab))
        close_pane!(find_pane("Table"; editor); editor)
    end

    @testset "the pane verbs take a referenced document" begin
        focus_pane!(find_pane("Before"; editor); editor)
        @test focused_title() == "Before"
        move_pane!(find_pane("Before"; editor), find_pane("Beside"; editor); editor)
        beside_group = only(g for g in get_pane_groups(tree)
                            if any(t -> get_pane_tab_title_string(t) == "Beside", g.tabs))
        @test get_pane_tab_title_string(first(beside_group.tabs)) == "Before"
        copy = duplicate_pane!(find_pane("Last"; editor); editor)
        @test copy isa ReferencedDocument
        @test get_referenced_value(copy; editor) === get_document(copy)
        @test startswith(get_pane_tab_title_string(get_referenced_value(copy; editor)), "Last")
        close_pane!(find_pane("Last"; editor); editor)
        @test find_pane("Last"; editor) === nothing
        beside = find_pane("Beside"; editor)
        @test get_referenced_value(beside; editor) === get_document(beside)
        @test describe_document(beside) == describe_document(get_document(beside))
    end

    @testset "the application declares the new names, and a search finds them" begin
        set = ToolSet(; api = make_application_api())
        register_default_tools!(set)
        description = only([t for t in set.tools if t.name == "execute_julia_code"]).description
        @test occursin("replace_referenced_value!(part, new_value)", description)
        @test occursin("insert_elements!(collection, index, values)", description)
        @test occursin("delete_elements!(collection, index)", description)
        first_names(query; mode) = [m.captures[1] for m in eachmatch(r"^- `([^(`{]+)"m,
            string(search_api(set, query; mode = mode, detail = "names", limit = 3)))]
        @test first(first_names("edited document"; mode = "keywords")) == "get_edited_document"
        @test first(first_names("find pane"; mode = "keywords")) == "find_pane"
        @test "ReferencedDocument" in first_names("a document and where it is"; mode = "description")
        @test first(first_names("the address of a document"; mode = "description")) == "DocumentLocator"
        @test first(first_names("the fields of a JSON object"; mode = "description")) == "JsonObject"
        @test first(first_names("open a pane under another pane"; mode = "description")) == "open_pane!"
    end

    @testset "the document functions take a referenced document" begin
        people_tab = find_pane("people.json"; editor)
        people = get_edited_document(people_tab)
        @test print_natural_text(people) == print_natural_text(get_document(people))
        @test length(search_documents(people, node -> node isa JsonString)) == 2
        @test get_file_content(people_tab.content) === get_file_content(get_document(people_tab).content)
        @test get_wrapped_document(people_tab.content) === get_wrapped_document(get_document(people_tab).content)
        path = joinpath(directory, "copy.json")
        write_document_file(people, path)
        @test occursin("Cleo", read(path, String))
        exported = joinpath(directory, "exported.json")
        export_document(people, exported)
        @test occursin("Ada", read(exported, String))
        again = open_pane!(people; title = "People again", editor)
        @test get_referenced_value(again; editor).content === get_document(people)
    end

    # A referenced document that a read made, not only one that `find_pane` found,
    # goes to a verb that takes only a fully typed reference.
    groups_of(node) = get_document(node) isa PaneGroup ? Any[node] :
                      get_document(node) isa PaneSplit ?
                          reduce(vcat, [groups_of(element) for element in node.elements]; init = Any[]) :
                          Any[]
    is_nested_alike(node) = node isa PaneSplit &&
        any(element -> (element isa PaneSplit && element.orientation === node.orientation) ||
                       is_nested_alike(element), node.elements)
    title_of(tab) = get_pane_tab_title_string(get_document(tab))

    @testset "a pane verb takes a referenced document that a read made" begin
        people = get_edited_document(find_pane("people.json"; editor))
        @test get_referenced_value(people[1]; editor) === get_document(people[1])
        tree_1 = find_referenced_document(DocumentLocator(editor.document, find_pane_tree_reference(; editor)))
        people_group_1 = only(group for group in groups_of(tree_1.root)
                              if any(tab -> title_of(tab) == "people.json", group.tabs))
        open_pane!(PrimitiveString("closable"); title = "Closable", target = people_group_1, editor)
        closable = only(tab for tab in people_group_1.tabs if title_of(tab) == "Closable")
        close_pane!(closable; editor)
        @test find_pane("Closable"; editor) === nothing
    end

    @testset "open_pane! beside a group keeps a split from holding a split of its orientation" begin
        tree_1 = find_referenced_document(DocumentLocator(editor.document, find_pane_tree_reference(; editor)))
        people_group_1 = only(group for group in groups_of(tree_1.root)
                              if any(tab -> title_of(tab) == "people.json", group.tabs))
        open_pane!(PrimitiveString("left"); title = "Left",
                   target = find_pane("people.json"; editor), side = :left, editor)
        open_pane!(PrimitiveString("above"); title = "Above", target = people_group_1, side = :above, editor)
        @test find_pane("Left"; editor) !== nothing && find_pane("Above"; editor) !== nothing
        @test !is_nested_alike(tree.root)
        operation = make_open_pane_operation(PrimitiveString("by operation");
                                             title = "By operation", target = find_pane("people.json"; editor), editor)
        evaluate_operation(editor, operation)
        @test find_pane("By operation"; editor) !== nothing
    end

    @testset "get_parent of an editor reads its document, and a locator can start at the editor" begin
        people_tab = find_pane("people.json"; editor)
        group = get_parent(editor, people_tab)
        @test get_document(group) isa PaneGroup
        @test any(tab -> tab === get_document(people_tab), get_document(group).tabs)
        @test get_document(get_parent(editor, get_reference(people_tab))) === get_document(group)
        people = get_edited_document(people_tab)
        @test get_document(get_parent(editor, people[1])) === get_document(people)
        last_tab = open_pane!(PrimitiveString("end"); title = "At the end", target = group, editor)
        @test get_document(group).tabs[end] === get_referenced_value(last_tab; editor)
        found = find_referenced_document(DocumentLocator(editor, get_reference(people_tab)))
        @test get_document(found) === get_document(people_tab)
        @test find_referenced_document(DocumentLocator(editor, get_reference(people_tab))) isa ReferencedDocument
    end

    @testset "a value found by identity at two places has no reference" begin
        path = joinpath(directory, "nulls.json")
        write(path, "{\"a\": null, \"b\": null}")
        nulls = ReferencedDocument(get_edited_document(read_document_file(path)), EmptyReference())
        second = nulls["b"]
        @test !(second isa ReferencedDocument) ||
              occursin("[2]", repr(strip_reference_types(get_reference(second))))
    end

    # A route passes the pane stage and the widget containers down to a tab's
    # content, so the history of the file records the edit, and the window's
    # history records that the file's history took a step.
    @testset "an operation routed into a file tab is recorded in the file's history" begin
        people_tab = find_pane("people.json"; editor)
        people = get_edited_document(people_tab)
        file_history = get_document(people_tab).content.content.content   # the scroll pane, the file, its history
        steps = (length(history.undo_entries), length(file_history.undo_entries))
        name = extend_reference(EmptyReference(), ElementReferenceStep(2), FieldReferenceStep("entries"),
                                ElementReferenceStep(1), FieldReferenceStep("value"))
        operation = ReplaceReferencedValueOperation(nothing,
            annotate_reference_types(get_document(people), name), JsonString("Adele"))
        rooted = read_rooted_operation(editor, get_reference(people), operation)
        @test rooted isa RecordUndoOperation
        evaluate_operation(editor, rooted)
        @test get_document(people)[2]["name"].value == "Adele"
        @test (length(history.undo_entries), length(file_history.undo_entries)) == steps .+ 1
    end

    @testset "the editing verbs record an edit in the history of the file, and an undo takes it back" begin
        people_tab = find_pane("people.json"; editor)
        people = get_edited_document(people_tab)
        file_history = get_document(people_tab).content.content.content
        count = length(get_document(people))
        steps = (length(history.undo_entries), length(file_history.undo_entries))
        frank = JsonObject("name" => JsonString("Frank"), "age" => JsonNumber(30))
        answer = insert_elements!(people, count + 1, [frank]; editor)
        @test answer isa ReferencedDocument && get_document(answer) === get_document(people)
        @test length(get_document(people)) == count + 1
        @test get_document(people)[end]["name"].value == "Frank"
        @test (length(history.undo_entries), length(file_history.undo_entries)) == steps .+ 1
        evaluate_operation(editor, UndoOperation(file_history))
        @test length(get_document(people)) == count

        delete_elements!(people, 1; editor)
        @test length(get_document(people)) == count - 1
        evaluate_operation(editor, UndoOperation(file_history))
        @test length(get_document(people)) == count

        steps = length(file_history.undo_entries)
        replace_referenced_value!(people[1]["name"], JsonString("Cleopatra"); editor)
        @test get_document(people)[1]["name"].value == "Cleopatra"
        @test length(file_history.undo_entries) == steps + 1
        evaluate_operation(editor, UndoOperation(file_history))
        @test get_document(people)[1]["name"].value == "Cleo"
    end

    @testset "a text file answers the document of its text" begin
        path = joinpath(directory, "notes.txt")
        write(path, "hello")
        text = get_edited_document(make_file_tab(path))
        @test text isa PrimitiveString
        @test occursin("hello", repr(text))
    end

    # A file tab shows its file in a scroll pane, made where the tab is made.
    @testset "a long file tab scrolls, and an edit, a save and an open go through its scroll pane" begin
        long_directory = mktempdir()
        long_path = joinpath(long_directory, "long.json")
        write(long_path, "[" * join(("{\"n\": $i}" for i in 1:60), ", ") * "]")
        long_editor = _make_referenced_application(long_directory; paths = [long_path])
        long_tab = find_pane("long.json"; editor = long_editor)
        pane = get_document(long_tab).content
        @test pane isa WidgetScrollPane && is_file_document(pane.content)
        items = get_edited_document(long_tab)
        @test get_document(items) isa JsonArray
        # The path to a tab's text that the system text of the application names.
        @test startswith(print_natural_text(pane), "[")
        @test get_file_content(pane) === pane.content.content
        window_history = only(search_documents(long_editor.document,
                                               node -> node isa UndoBuffer && node.content isa PaneTree))
        steps = length(window_history.undo_entries)
        for _ in 1:10
            wheel = MouseScroll(0, -3, 700, 400; time = 0.0)
            change = read_intent(long_editor.projection, nothing,
                                 Intent(WindowInput(:ProjecturEd, wheel)), long_editor.iomap)
            operation = change isa Intent ? change.operation : change
            operation isa Operation && (evaluate_operation(long_editor, operation); drain_operations!(long_editor))
            run_frame!(long_editor)
        end
        @test pane.scroll_position.y[] > 0
        @test length(window_history.undo_entries) == steps       # a scroll is no edit

        file_history = pane.content.content
        insert_elements!(items, 61, [JsonObject("n" => JsonNumber(61))]; editor = long_editor)
        @test length(get_document(items)) == 61
        @test length(file_history.undo_entries) == 1
        save = read_intent(long_editor.projection, nothing,
                           Intent(WindowInput(:ProjecturEd, KeyDown(:s, ModifierKeys(; ctrl = true); time = 0.0))),
                           long_editor.iomap)
        operation = save isa Intent ? save.operation : save
        operation isa Operation && (evaluate_operation(long_editor, operation); drain_operations!(long_editor))
        @test occursin("61", read(long_path, String))

        other_path = joinpath(long_directory, "other.json")
        write(other_path, "[]")
        evaluate_operation(long_editor, OpenFileOperation(other_path))
        drain_operations!(long_editor)
        run_frame!(long_editor)
        tree = window_history.content
        @test any(group -> any(tab -> get_pane_tab_title_string(tab) == "long.json", group.tabs) &&
                           any(tab -> get_pane_tab_title_string(tab) == "other.json", group.tabs),
                  get_pane_groups(tree))
    end
end
end # test_referenced_document_editor
