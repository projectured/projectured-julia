# A referenced document in the application window: a tab found by its title, the
# data a file tab shows reached through the file and its history, and a read into
# that data that holds the reference to its place.

using Test

function _make_referenced_application(directory)
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}]")
    measure = measure_truetype_text
    document, projection = make_application_window([joinpath(directory, "people.json")];
                                                    root = directory, assistant = nothing,
                                                    measure = measure)
    editor = make_editor(document, projection, "ProjecturEd"; backend = HeadlessBackend(),
                         width = 1280, height = 720,
                         opened_window_projections = make_opened_window_projections(;
                             content = make_application_content_projections(measure = measure),
                             measure = measure))
    start_application!(editor, false, :none, "")
    run_frame!(editor)
    editor
end

function test_referenced_document_editor()
@testset "ReferencedDocument in the application" begin
    directory = mktempdir()
    editor = _make_referenced_application(directory)

    @testset "find_pane answers the tab and where it is" begin
        people_tab = find_pane(editor, "people.json")
        @test people_tab isa ReferencedDocument
        @test get_document(people_tab) isa PaneTab
        @test evaluate_reference(editor.document, get_reference(people_tab)) === get_document(people_tab)
        @test find_pane(editor, "no such tab") === nothing
    end

    @testset "get_edited_document reaches the data through the file and its history" begin
        people_tab = find_pane(editor, "people.json")
        people = get_edited_document(people_tab)
        @test people isa ReferencedDocument
        @test get_document(people) isa JsonArray
        @test evaluate_reference(editor.document, get_reference(people)) === get_document(people)
        # A document that is not referenced answers the document.
        @test get_edited_document(get_document(people_tab).content) === get_document(people)
        @test get_edited_document(get_document(people)) === get_document(people)
    end

    @testset "a read into the data keeps its reference" begin
        people = get_edited_document(find_pane(editor, "people.json"))
        first_person = people.elements[1]
        @test get_document(first_person) isa JsonObject
        @test evaluate_reference(editor.document, get_reference(first_person)) === get_document(first_person)
        @test [entry.key for entry in first_person.entries] == ["name", "age"]
    end

    @testset "an array iterates and an object reads by key, keeping references" begin
        people = get_edited_document(find_pane(editor, "people.json"))
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
        open_pane!(editor, WidgetLabel("hello"); title = "Hello")
        hello = get_edited_document(find_pane(editor, "Hello"))
        @test get_document(hello) isa WidgetLabel
    end

    history = only(search_documents(editor.document,
                                    node -> node isa UndoBuffer && node.content isa PaneTree))
    tree = history.content
    focused_title() = let (group, index) = get_pane_focus(tree)
        get_pane_tab_title_string(group.tabs[index])
    end

    @testset "open_pane! puts a tab before a tab, at the end of a group, and beside it" begin
        people_tab = get_document(find_pane(editor, "people.json"))
        group = only(g for g in get_pane_groups(tree) if any(t -> t === people_tab, g.tabs))
        index = findfirst(t -> t === people_tab, collect(group.tabs))

        before = open_pane!(editor, PrimitiveString("before"); title = "Before",
                            target = find_pane(editor, "people.json"))
        @test group.tabs[index] === get_referenced_value(editor, before)
        @test before isa ReferencedDocument && get_document(before) === group.tabs[index]
        @test is_fully_typed_reference(get_reference(before))
        @test group.tabs[index + 1] === people_tab

        group_reference = concat_references(find_pane_tree_reference(editor),
                                            only(search_references(tree, node -> node === group)))
        last_tab = open_pane!(editor, PrimitiveString("last"); title = "Last", target = group_reference)
        @test group.tabs[end] === get_referenced_value(editor, last_tab)

        groups = length(get_pane_groups(tree))
        steps = length(history.undo_entries)
        beside = open_pane!(editor, PrimitiveString("beside"); title = "Beside",
                            target = find_pane(editor, "people.json"), side = :right)
        @test length(get_pane_groups(tree)) == groups + 1
        @test !any(t -> t === get_referenced_value(editor, beside), group.tabs)
        @test focused_title() == "Beside"
        @test length(history.undo_entries) == steps + 1

        @test_throws ArgumentError open_pane!(editor, PrimitiveString("x");
                                              target = find_pane(editor, "Last"), side = :middle)
        @test_throws ArgumentError open_pane!(editor, PrimitiveString("x"); group = group,
                                              target = find_pane(editor, "Last"))
    end

    @testset "the pane verbs take a referenced document" begin
        focus_pane!(editor, find_pane(editor, "Before"))
        @test focused_title() == "Before"
        move_pane!(editor, find_pane(editor, "Before"), find_pane(editor, "Beside"))
        beside_group = only(g for g in get_pane_groups(tree)
                            if any(t -> get_pane_tab_title_string(t) == "Beside", g.tabs))
        @test get_pane_tab_title_string(first(beside_group.tabs)) == "Before"
        copy = duplicate_pane!(editor, find_pane(editor, "Last"))
        @test copy isa ReferencedDocument
        @test get_referenced_value(editor, copy) === get_document(copy)
        @test startswith(get_pane_tab_title_string(get_referenced_value(editor, copy)), "Last")
        close_pane!(editor, find_pane(editor, "Last"))
        @test find_pane(editor, "Last") === nothing
        beside = find_pane(editor, "Beside")
        @test get_referenced_value(editor, beside) === get_document(beside)
        @test describe_document(beside) == describe_document(get_document(beside))
    end

    @testset "the application declares the new names, and a search finds them" begin
        set = ToolSet(; api = make_application_api())
        register_default_tools!(set)
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
        people_tab = find_pane(editor, "people.json")
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
        again = open_pane!(editor, people; title = "People again")
        @test get_referenced_value(editor, again).content === get_document(people)
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
        people = get_edited_document(find_pane(editor, "people.json"))
        @test get_referenced_value(editor, people[1]) === get_document(people[1])
        tree_1 = find_referenced_document(DocumentLocator(editor.document, find_pane_tree_reference(editor)))
        people_group_1 = only(group for group in groups_of(tree_1.root)
                              if any(tab -> title_of(tab) == "people.json", group.tabs))
        open_pane!(editor, PrimitiveString("closable"); title = "Closable", target = people_group_1)
        closable = only(tab for tab in people_group_1.tabs if title_of(tab) == "Closable")
        close_pane!(editor, closable)
        @test find_pane(editor, "Closable") === nothing
    end

    @testset "open_pane! beside a group keeps a split from holding a split of its orientation" begin
        tree_1 = find_referenced_document(DocumentLocator(editor.document, find_pane_tree_reference(editor)))
        people_group_1 = only(group for group in groups_of(tree_1.root)
                              if any(tab -> title_of(tab) == "people.json", group.tabs))
        open_pane!(editor, PrimitiveString("left"); title = "Left",
                   target = find_pane(editor, "people.json"), side = :left)
        open_pane!(editor, PrimitiveString("above"); title = "Above", target = people_group_1, side = :above)
        @test find_pane(editor, "Left") !== nothing && find_pane(editor, "Above") !== nothing
        @test !is_nested_alike(tree.root)
        operation = make_open_pane_operation(editor, PrimitiveString("by operation");
                                             title = "By operation", target = find_pane(editor, "people.json"))
        evaluate_operation(editor, operation)
        @test find_pane(editor, "By operation") !== nothing
    end

    @testset "get_parent of an editor reads its document, and a locator can start at the editor" begin
        people_tab = find_pane(editor, "people.json")
        group = get_parent(editor, people_tab)
        @test get_document(group) isa PaneGroup
        @test any(tab -> tab === get_document(people_tab), get_document(group).tabs)
        @test get_document(get_parent(editor, get_reference(people_tab))) === get_document(group)
        people = get_edited_document(people_tab)
        @test get_document(get_parent(editor, people[1])) === get_document(people)
        last_tab = open_pane!(editor, PrimitiveString("end"); title = "At the end", target = group)
        @test get_document(group).tabs[end] === get_referenced_value(editor, last_tab)
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

    @testset "a text file answers the document of its text" begin
        path = joinpath(directory, "notes.txt")
        write(path, "hello")
        text = get_edited_document(make_file_tab(path))
        @test text isa PrimitiveString
        @test occursin("hello", repr(text))
    end
end
end # test_referenced_document_editor
