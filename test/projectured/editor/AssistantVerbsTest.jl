# The verbs that the assistant of a window shares with every other window, in the
# application: what the person selected and points at, what changed, the logs and
# the text of any part.

using Test

function _make_assistant_verbs_application(directory)
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}]")
    write(joinpath(directory, "notes.md"), "# Notes\n\nThe first line.\n")
    paths = [joinpath(directory, "people.json"), joinpath(directory, "notes.md")]
    document, projection = make_application_window(paths; root = directory, assistant = nothing)
    editor = build_editor(document, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    editor
end

# What `execute_julia_code` answers for `code` in the window of `editor`.
_run_assistant_code(editor, code) = execute_julia_code!(editor.tools, editor, code)

function test_assistant_verbs()
@testset "the verbs of the assistant of every window" begin
    directory = mktempdir()
    editor = _make_assistant_verbs_application(directory)
    people = get_edited_document(find_pane("people.json"; editor))
    ada_name = people[2]["name"]

    @testset "read: the part that the person selected, and its tab" begin
        evaluate_operation(editor, ReplaceSelectionOperation(get_reference(ada_name)))
        run_frame!(editor)
        part = find_selected_part(; editor)
        @test part isa ReferencedDocument
        @test get_document(part) === get_document(ada_name)
        @test print_natural_text(part) == "\"Ada\""
        tab = find_focused_pane(; editor)
        @test get_pane_tab_title_string(get_document(tab)) == "people.json"
        @test occursin("Ada", _run_assistant_code(editor, "print_natural_text(find_selected_part())"))
    end

    @testset "read: the part under the pointer" begin
        cleo_age = people[1]["age"]
        evaluate_operation(editor, ReplaceMouseTargetOperation(get_reference(cleo_age)))
        part = find_part_under_pointer(; editor)
        @test part isa ReferencedDocument
        @test get_document(part) === get_document(cleo_age)
    end

    @testset "read: what changed last" begin
        @test occursin("Nothing to take back", string(describe_undo_history(; editor)))
        replace_referenced_value!(people[1]["age"], parse_natural_text(:json, "30"); editor)
        run_frame!(editor)
        history = string(describe_undo_history(; editor))
        @test startswith(history, "To take back, newest last:")
        @test length(split(history, '\n')) == 2
        @test occursin("To take back", _run_assistant_code(editor, "describe_undo_history()"))
    end

    @testset "read: the logs of the session print as text" begin
        for log in (get_session_gesture_log(; editor), get_session_message_log(; editor),
                    get_session_fault_log(; editor))
            @test print_natural_text(log) isa String
        end
    end

    @testset "read: a part with no text of its own prints as its constructor" begin
        @test startswith(print_pred_text(WidgetLabel("hello")), "WidgetLabel(")
        @test startswith(print_pred_text(people[1]), "JsonObject(")
    end

    @testset "read: the formats that a model writes a document in" begin
        formats = string(describe_natural_formats())
        @test occursin(":json", formats) && occursin(":md", formats)
        @test occursin(":json", _run_assistant_code(editor, "describe_natural_formats()"))
    end

    @testset "control: a part is selected to show it to the person" begin
        cleo = people[1]
        @test select_part!(cleo; editor) === cleo
        run_frame!(editor)
        @test get_document(find_selected_part(; editor)) === get_document(cleo)
        # The selection is written at the root, and names the part from there.
        @test strip_reference_types(get_selection(editor.document)) ==
              strip_reference_types(get_reference(cleo))
    end

    @testset "control: a setting of the window changes and applies" begin
        settings = string(describe_settings(; editor))
        @test occursin("render.partial_render = ", settings)
        before = occursin("render.partial_render = true", settings)
        @test change_setting!(:partial_render, !before; editor) == !before
        @test occursin("render.partial_render = " * string(!before), string(describe_settings(; editor)))
        @test change_setting!(:partial_render, before; editor) == before
        @test_throws ArgumentError change_setting!(:no_such_setting, 1; editor)
        # Each group has the fields of a document too, and those are no setting.
        @test_throws ArgumentError change_setting!(:selection, nothing; editor)
        @test_throws ArgumentError change_setting!(:partial_render, "sometimes"; editor)
    end

    @testset "change: the commands of a part, and the selection stays" begin
        select_part!(people[2]["name"]; editor)
        run_frame!(editor)
        selected = get_selection(editor.document)
        @test occursin("Insert a new element", string(describe_commands(people; editor)))
        @test occursin("Sort the entries by key", string(describe_commands(people[1]; editor)))
        @test occursin("has no command", string(describe_commands(people[1]["name"]; editor)))
        @test get_selection(editor.document) == selected
        count = length(people)
        @test run_command!(people, "Insert a new element"; editor) isa Text
        run_frame!(editor)
        @test length(people) == count + 1
        # The part is read again at each call, so a second call sees the first.
        @test run_command!(people, "Insert a new element"; editor) isa Text
        run_frame!(editor)
        @test length(people) == count + 2
        for _ in 1:2
            call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor)
            run_frame!(editor)
        end
        @test length(people) == count
        @test_throws ArgumentError run_command!(people, "No such command"; editor)
        @test occursin("Insert a new element",
                       _run_assistant_code(editor, "describe_commands(get_edited_document(find_pane(\"people.json\")))"))
    end

    @testset "change: a plain field of a part, also one that holds nothing" begin
        open_pane!(WidgetCheckbox(true); title = "Box", editor)
        run_frame!(editor)
        box = get_edited_document(find_pane("Box"; editor))
        @test get_document(box).label === nothing
        @test replace_referenced_value!(box, :enabled, false; editor) === box
        @test replace_referenced_value!(box, :label, "Record vectors"; editor) === box
        run_frame!(editor)
        @test !get_document(box).enabled && get_document(box).label == "Record vectors"
        for _ in 1:2
            call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor)
            run_frame!(editor)
        end
        @test get_document(box).enabled && get_document(box).label === nothing
        @test_throws ArgumentError replace_referenced_value!(box, :colour, 1; editor)
        @test occursin("Record", _run_assistant_code(editor,
            "box_1 = get_edited_document(find_pane(\"Box\")); replace_referenced_value!(box_1, :label, \"Record\"); get_document(box_1).label"))
        close_pane!(find_pane("Box"; editor); editor)
    end

    @testset "change: a dashboard joins the explorer, and the selection stays" begin
        content = find_explorer_content(; editor)
        @test content isa ReferencedDocument
        @test get_document(content) === get_session_explorer_content(; editor)
        selected = get_selection(editor.document)
        count = length(content.entries)
        _run_assistant_code(editor, "content_1 = find_explorer_content(); " *
            "insert_elements!(content_1.entries, length(content_1.entries) + 1, " *
            "[Dashboard(\"Study\", [DashboardCard(\"Notes\", ExplorerSection(\"Notes\"))])])")
        run_frame!(editor)
        @test length(content.entries) == count + 1
        @test get_document(content.entries[count + 1]).title == "Study"
        @test get_selection(editor.document) == selected
        call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor)
        run_frame!(editor)
        @test length(content.entries) == count
    end

    @testset "change: the commands of a row of the explorer, and the selection stays" begin
        content = find_explorer_content(; editor)
        title_at(k) = format_tree_node_label(get_document(content.entries[k]))
        k = findfirst(==("Dashboards"), [title_at(index) for index in 1:length(content.entries)])
        selected = get_selection(editor.document)
        described = split(string(describe_commands(content.entries[k]; editor)), '\n')
        @test [first(split(line, ": ")) for line in described] ==
              ["Open in a new tab", "Remove from explorer", "Move the entry earlier", "Move the entry later",
               "New section"]
        @test run_command!(content.entries[k], "Move the entry later"; editor) isa Text
        run_frame!(editor)
        @test title_at(k + 1) == "Dashboards"
        @test get_selection(editor.document) == selected
        call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor)
        run_frame!(editor)
        @test title_at(k) == "Dashboards"
        count = length(content.entries)
        _run_assistant_code(editor, "run_command!(find_explorer_content().entries[$k], \"Remove from explorer\")")
        run_frame!(editor)
        @test length(content.entries) == count - 1
        @test get_selection(editor.document) == selected
        call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor)
        run_frame!(editor)
        @test title_at(k) == "Dashboards" && length(content.entries) == count
    end

    @testset "tell: a part opens as a page in a new tab with a navigator" begin
        is_page(node) = node isa Navigator
        before = length(search_documents(editor.document, is_page))
        @test open_page!(people[2]; editor) isa Text
        # The open posts the new tab, which the loop of a window drains.
        drain_operations!(editor)
        run_frame!(editor)
        pages = search_documents(editor.document, is_page)
        @test length(pages) == before + 1
        @test get_navigator_page(last(pages)) === get_document(people[2])
    end

    @testset "tell: a shape that reads the clock moves with it" begin
        circle = GraphicsCircle(() -> 50 + 30 * cos(get_reactive_clock_time(editor.clock)), 50, 5)
        set_clock_time!(editor.clock, 0.0)
        @test circle.cx == 80
        set_clock_time!(editor.clock, Float64(pi))
        @test circle.cx == 20
        @test occursin("2pi * get_reactive_clock_time",
                       _run_assistant_code(editor, "read_function_documentation(\"ClockModule\", \"get_reactive_clock_time\")"))
    end

    @testset "tell: a drawing, a chart and a graph draw in a tab" begin
        for (title, document) in (
                ("Sketch", GraphicsCanvas([GraphicsRect(10, 10, 120, 40; color = color_red),
                                           GraphicsText("drawn by hand", 20, 34;
                                                        font = StyleFont("DejaVu Sans", 14))];
                                          w = 200, h = 80)),
                ("Card", WidgetCard(; content = GraphicsCanvas([GraphicsCircle(40, 40, 30; color = color_blue),
                                                    GraphicsText("in a card", 10, 90;
                                                                 font = StyleFont("DejaVu Sans", 14))];
                                                   w = 120, h = 100))),
                ("Sales", Chart("sold in a month", [ChartLineSeries("lamps", collect(1.0:12.0),
                                                                    collect(2.0:2.0:24.0))])),
                ("Roads", let a = GraphVertex(PrimitiveString("Paris")), b = GraphVertex(PrimitiveString("Lyon"))
                     GraphGraph([a, b], [GraphEdge(a, b)])
                 end))
            open_pane!(document; title, editor)
            run_frame!(editor)
            focus_pane!(find_pane(title; editor); editor)
            run_frame!(editor)
            texts = _drawn_texts_of(editor)
            expected = Dict("Sketch" => "drawn by hand", "Card" => "in a card",
                            "Sales" => "sold in a month", "Roads" => "Lyon")[title]
            @test any(text -> occursin(expected, text), texts)
        end
    end
end
end

# Every text that the last frame of `editor` drew, in the order of the walk.
function _drawn_texts_of(editor)
    texts = String[]
    walk(node, depth) = begin
        depth > 200 && return
        node isa GraphicsText && push!(texts, String(node.text))
        node isa GraphicsCanvas && foreach(i -> walk(node.elements[i], depth + 1), 1:length(node.elements))
        node isa GraphicsViewport && walk(node.content, depth + 1)
        hasproperty(node, :windows) && foreach(window -> walk(window.content, depth + 1), node.windows)
    end
    walk(last(rendered_output(editor.backend)), 0)
    texts
end

# Whether `m` belongs to the editor, whose documentation this repository writes. A
# package such as DataFrames keeps its own.
_is_documented_module(m::Module) = startswith(String(nameof(Base.moduleroot(m))), "Projectured")

# The example of a docstring: every indented line under `# Example`, up to the
# next paragraph of prose.
function _documented_example(doc)
    lines = split(doc, '\n')
    start = findfirst(==("# Example"), lines)
    start === nothing && return ""
    code = String[]
    for line in lines[start + 1:end]
        if startswith(line, "    ")
            push!(code, strip(line))
        elseif !isempty(strip(line)) && !isempty(code)
            break
        end
    end
    join(code, '\n')
end

_has_example_parse_error(expression) =
    expression isa Expr && (expression.head in (:error, :incomplete) ||
                            any(_has_example_parse_error, expression.args))

"""
    test_assistant_documentation(api = make_editor_api())

Every name of `api` from a package of the editor carries what a model reads to use
it: a "Use it to" line, an example that parses, and a "See also" line. Every name
that `EDITOR_SYSTEM` and the paragraph of the loaded domains write in backticks is
a name that the model can write.
"""
function test_assistant_documentation(api = make_editor_api())
@testset "every declared name carries its use, an example and its neighbours" begin
    set = register_editor_tools!(register_default_tools!(declare_api!(ToolSet(), api)))
    for entry in set.api, (name, _) in get_api_entry_bindings(entry)
        _is_documented_module(entry.module_) || continue
        doc = ToolModule._binding_doc(entry.module_, name)
        example = _documented_example(doc)
        complete = occursin("\nUse it to ", doc) && occursin("\nSee also ", doc) &&
                   !isempty(example) && !_has_example_parse_error(Meta.parseall(example))
        @test complete || error(string(nameof(entry.module_), ".", name,
                                       " lacks a \"Use it to\" line, a \"See also\" line or an example that parses"))
        # A function that the assistant calls carries its docstring on the generic
        # function, which the search answers. A macro has no generic form.
        value = getfield(entry.module_, name)
        (value isa Function && !(value isa Type) && !startswith(String(name), "@")) || continue
        generic = any(doc -> first(doc) === Union{}, ToolModule._collect_binding_docs(entry.module_, name))
        @test generic || error(string(nameof(entry.module_), ".", name,
                                      " has no docstring on its generic function"))
    end
    writable = Set{String}(["editor"])
    for entry in set.api
        push!(writable, String(nameof(entry.module_)))
        union!(writable, String.(get_api_entry_names(entry)))
    end
    union!(writable, [tool.name for tool in list_tools(set)])
    for found in eachmatch(r"`([^`]+)`", EDITOR_SYSTEM * make_domain_system())
        head = match(r"^(@?[A-Za-z_][A-Za-z0-9_]*!?)(\(.*\))?$", found.captures[1])
        head === nothing && continue
        name = String(head.captures[1])
        @test name in writable || error("the system text names `" * name * "`, which no model can write")
    end
end
end
