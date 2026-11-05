# The verbs that the assistant of a window shares with every other window, in the
# application: what the person selected and points at, what changed, the logs and
# the text of any part.

using Test
import ProjecturedKernel, ProjecturedPlatform

# The names that only the person calls, each in the module that defines it. The
# assistant acts at the person's request, so it never selects, clears the undo
# history, opens a file dialog or answers a request that an agent made.
const _PERSON_OWN_NAMES = [
    (ProjecturedKernel.SelectionModule, :set_selection!),
    (ProjecturedKernel.SelectionModule, :replace_selection!),
    (ProjecturedKernel.SelectionModule, :clear_selection!),
    (ProjecturedPlatform.UndoModule, :clear_undo_history!),
    (ProjecturedPlatform.ShellModule, :make_file_dialog),
    (ProjecturedPlatform.ShellModule, :open_file_dialog!),
    (ProjecturedPlatform.ShellModule, :save_file_dialog!),
    (ProjecturedPlatform.ConversationModule, :answer_permission_request!),
    (ProjecturedPlatform.ConversationModule, :answer_question_request!),
]

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
        @test run_command!(people, "Insert a new element"; editor) isa String
        run_frame!(editor)
        @test length(people) == count + 1
        # The part is read again at each call, so a second call sees the first.
        @test run_command!(people, "Insert a new element"; editor) isa String
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
        @test run_command!(content.entries[k], "Move the entry later"; editor) isa String
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

    @testset "tell: a part opens as a page in a new tab with a navigator, and the focus stays" begin
        is_page(node) = node isa Navigator
        before = length(search_documents(editor.document, is_page))
        selected = repr(get_selection(editor.document))
        page_tab = open_page!(people[2]; editor)
        tab = get_document(page_tab)
        @test tab isa PaneTab
        @test get_navigator_page(tab.content) === get_document(people[2])
        @test length(search_documents(editor.document, is_page)) == before + 1
        run_frame!(editor)
        @test repr(get_selection(editor.document)) == selected
        # The page goes behind the tab that its group shows, and `show_pane!` shows it.
        group = only(g for g in get_pane_groups(get_window_tree(editor.document))
                     if any(t -> t === tab, g.tabs))
        @test group.tabs[get_pane_shown_tab_index(group)] !== tab
        show_pane!(page_tab; editor)
        run_frame!(editor)
        @test group.tabs[get_pane_shown_tab_index(group)] === tab
        nowhere = extend_reference(get_reference(people[2]), FieldReferenceStep("missing"))
        @test_throws ArgumentError open_page!(ReferencedDocument(nothing, nowhere); editor)
    end

    @testset "tell: a page shows in the explorer, its row shows, and the selection stays" begin
        content = find_explorer_content(; editor)
        explorer = get_document(get_edited_document(find_pane("Explorer"; editor)))
        navigator = getfield(explorer, :navigator)[]
        selected = get_selection(editor.document)
        titles = [format_tree_node_label(get_document(entry)) for entry in content.entries]
        section = content.entries[findfirst(==("Editor"), titles)]
        @test open_explorer_page!(section; editor) isa String
        run_frame!(editor)
        @test get_navigator_page(navigator) === get_document(section)
        # A node below an entry: the row of its section opens, so its row shows.
        below = section.entries[1]
        open_explorer_page!(below; editor)
        run_frame!(editor)
        @test get_navigator_page(navigator) === get_document(below)
        @test any(document -> document === get_document(section),
                  collect_open_tree_documents(getfield(explorer, :tree)[]))
        @test get_selection(editor.document) == selected
        # A part of a document that an entry holds, reached through another tab.
        open_pane!(get_document(section); title = "Editor section", editor)
        run_frame!(editor)
        held = get_edited_document(find_pane("Editor section"; editor)).entries[1]
        open_explorer_page!(section; editor)
        run_frame!(editor)
        open_explorer_page!(held; editor)
        run_frame!(editor)
        @test get_navigator_page(navigator) === get_document(below)
        @test get_selection(editor.document) == selected
        close_pane!(find_pane("Editor section"; editor); editor)
        # A document that the explorer does not hold is refused.
        open_pane!(WidgetCheckbox(true); title = "Box", editor)
        run_frame!(editor)
        @test_throws ArgumentError open_explorer_page!(get_edited_document(find_pane("Box"; editor)); editor)
        close_pane!(find_pane("Box"; editor); editor)
        @test occursin("The explorer shows", _run_assistant_code(editor,
            "open_explorer_page!(find_explorer_content().entries[1])"))
    end

    @testset "tell: a shape that reads the clock moves with it" begin
        circle = GraphicsCircle(() -> 50 + 30 * cos(get_reactive_clock_time(editor.clock)), 50, 5)
        set_clock_time!(editor.clock, 0.0)
        @test circle.cx == 80
        set_clock_time!(editor.clock, Float64(pi))
        @test circle.cx == 20
        @test occursin("() -> 100 * get_reactive_clock_time(editor.clock)",
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

# The names of a guide: each name in backticks in its prose, and each function that
# its code calls.
function _collect_guide_names(guide::AbstractString)
    names = String[]
    fenced = false
    for line in split(guide, '\n')
        if startswith(strip(line), "```")
            fenced = !fenced
        elseif fenced
            for found in eachmatch(r"(?<![\w.:])(@?[A-Za-z_][A-Za-z0-9_]*!?)\(", line)
                push!(names, String(found.captures[1]))
            end
        else
            for found in eachmatch(r"`([^`]+)`", line)
                head = match(r"^(@?[A-Za-z_][A-Za-z0-9_]*!?)(\(.*\))?$", found.captures[1])
                head === nothing || push!(names, String(head.captures[1]))
            end
        end
    end
    unique(names)
end

"""
    test_assistant_documentation(api = make_editor_api())

Every name of `api` from a package of the editor carries what a model reads to use
it: a "Use it to" line, an example that parses, and a "See also" line, which names
only what the model can write. Every name that `APPLICATION_SYSTEM` and the paragraph of
the loaded domains write in backticks is a name that the model can write, or a tool
or an argument of a tool, and so is every name of the orientation guide, which the
text names. The names
that only the person calls are not offered, and a function of `api` that takes a
document takes a part of that document too.
"""
function test_assistant_documentation(api = make_editor_api())
@testset "the names that only the person calls carry no mark and are not offered" begin
    set = declare_api!(ToolSet(), api)
    offered = Set{String}()
    for entry in set.api
        union!(offered, String.(get_api_entry_names(entry)))
    end
    for (module_, name) in _PERSON_OWN_NAMES
        @test isdefined(module_, name)
        @test !ToolModule.has_assistant_mark(ToolModule._binding_doc(module_, name)) ||
              error(string(nameof(module_), ".", name, " carries the mark, but only the person calls it"))
        @test !(String(name) in offered) ||
              error(string(nameof(module_), ".", name, " is offered, but only the person calls it"))
    end
end
@testset "a function that the assistant calls takes each document also as a part" begin
    # A read of the window answers a part, a document with its place, so each
    # parameter of a document type takes a part of that type too.
    set = declare_api!(ToolSet(), api)
    checked = Set{Any}()
    for entry in set.api, (name, _) in get_api_entry_bindings(entry)
        value = getfield(entry.module_, name)
        (value isa Function && !(value isa Type)) || continue
        value in checked && continue
        push!(checked, value)
        for method in methods(value)
            parameters = Any[parameter isa TypeVar ? parameter.ub : parameter
                             for parameter in Base.unwrap_unionall(method.sig).parameters[2:end]]
            # A method with a trailing Vararg takes the call that gives it no value.
            !isempty(parameters) && last(parameters) isa Core.TypeofVararg && pop!(parameters)
            all(parameter -> parameter isa Type, parameters) || continue
            for (position, parameter) in enumerate(parameters)
                parameter !== Union{} && parameter <: Document || continue
                types = copy(parameters)
                types[position] = ReferencedDocument{parameter}
                @test hasmethod(value, Tuple{types...}) ||
                      error(string(nameof(entry.module_), ".", name, " takes a ", parameter, " as argument ",
                                   position, " and no part: ", method))
            end
        end
    end
end
@testset "every declared name carries its use, an example and its neighbours" begin
    set = register_editor_tools!(register_default_tools!(declare_api!(ToolSet(), api)))
    writable = Set{String}(["editor"])
    for entry in set.api
        push!(writable, String(nameof(entry.module_)))
        union!(writable, String.(get_api_entry_names(entry)))
    end
    union!(writable, [tool.name for tool in list_tools(set)])
    words = union(writable, [String(parameter.name) for tool in list_tools(set)
                                                    for parameter in tool.parameters])
    for entry in set.api, (name, _) in get_api_entry_bindings(entry)
        _is_documented_module(entry.module_) || continue
        doc = ToolModule._binding_doc(entry.module_, name)
        # A type that a mark on its supertype offers needs no form of its own.
        ToolModule.has_assistant_mark(doc) || continue
        example = _documented_example(doc)
        complete = occursin("\nUse it to ", doc) && occursin("\nSee also ", doc) &&
                   !isempty(example) && !_has_example_parse_error(Meta.parseall(example))
        @test complete || error(string(nameof(entry.module_), ".", name,
                                       " lacks a \"Use it to\" line, a \"See also\" line or an example that parses"))
        # The example is what a model copies, so each function that it calls is one
        # that the model can write, a function of Base, or one that the example defines.
        for found in eachmatch(r"(?<![\w.])(@?[A-Za-z_][A-Za-z0-9_]*!?)\(", example)
            called = String(found.captures[1])
            is_binding = any(entry -> isdefined(entry.module_, Symbol(called)), set.api)
            @test called in writable || isdefined(Base, Symbol(called)) || !is_binding ||
                  error(string(nameof(entry.module_), ".", name, " calls `", called,
                               "` in its example, which no model can write"))
        end
        for paragraph in split(doc, "\n\n"), found in eachmatch(r"`(@?[A-Za-z_][A-Za-z0-9_]*!?)", paragraph)
            startswith(paragraph, "See also ") || continue
            neighbour = String(found.captures[1])
            # A word in backticks that no module of the editor defines, such as a
            # keyword argument, names nothing to call.
            is_binding = any(entry -> isdefined(entry.module_, Symbol(neighbour)), set.api)
            @test neighbour in writable || isdefined(Base, Symbol(neighbour)) || !is_binding ||
                  error(string(nameof(entry.module_), ".", name, " names `", neighbour,
                               "` in its \"See also\" line, which no model can write"))
        end
        # A function that the assistant calls carries its docstring on the generic
        # function, which the search answers. A macro has no generic form.
        value = getfield(entry.module_, name)
        (value isa Function && !(value isa Type) && !startswith(String(name), "@")) || continue
        generic = any(doc -> first(doc) === Union{}, ToolModule._collect_binding_docs(entry.module_, name))
        @test generic || error(string(nameof(entry.module_), ".", name,
                                      " has no docstring on its generic function"))
    end
    for found in eachmatch(r"`([^`]+)`", APPLICATION_SYSTEM * make_domain_system())
        head = match(r"^(@?[A-Za-z_][A-Za-z0-9_]*!?)(\(.*\))?$", found.captures[1])
        head === nothing && continue
        name = String(head.captures[1])
        @test name in words || error("the system text names `" * name * "`, which no model can write")
    end
    # The guide that the text names. A name that no declared module defines, such as
    # a variable of an example or a keyword, is no name of the editor.
    for name in _collect_guide_names(ToolModule.read_guide("guide/orientation"))
        is_binding = any(entry -> isdefined(entry.module_, Symbol(name)), set.api)
        @test name in words || isdefined(Base, Symbol(name)) || !is_binding ||
              error("the orientation guide names `" * name * "`, which no model can write")
    end
end
end
