# The chrome a window is drawn in, and the rule that keeps it honest.

mutable struct _ShellFakeEditor; document::Any; end

# Whether the tab at `index` of `group` has the focus. The group is compared by
# identity, because two groups can hold equal tabs.
_is_focused_at(tree, group, index) = begin
    focus = get_pane_focus(tree)
    focus !== nothing && focus[1] === group && focus[2] == index
end

# Every action the menu bar carries, at any depth.
function _menu_actions()
    found = Action[]
    walk(node) = begin
        node isa WidgetMenuItem && (push!(found, node.action);
                                    node.submenu isa WidgetDocument && walk(node.submenu))
        node isa WidgetMenu && foreach(walk, collect(node.elements))
    end
    walk(make_window_menu_bar())
    found
end

# A backend that declares no output, so the window wrapper of `build_editor` puts
# the root in a window.
struct _ShellProbeBackend <: ProjecturedKernel.BackendModule.Backend end
ProjecturedKernel.BackendModule.initialize_backend!(::_ShellProbeBackend) = nothing
ProjecturedKernel.BackendModule.quit_backend!(::_ShellProbeBackend) = nothing
ProjecturedKernel.BackendModule.take_from_devices!(::_ShellProbeBackend, devices) =
    nothing
ProjecturedKernel.BackendModule.write_to_devices!(::_ShellProbeBackend, devices, output) = nothing

# Every text that `node` draws, read through its cells.
function _shell_texts(node, found = String[])
    node isa AbstractCell && return _shell_texts(node[], found)
    node isa GraphicsText && push!(found, string(node.text))
    node isa GraphicsCanvas && foreach(element -> _shell_texts(element, found), node.elements)
    node isa GraphicsViewport && _shell_texts(node.content, found)
    found
end

function test_window_shell()
@testset "the window shell" begin

_labels(menu) = [String(string(item.action.label)) for item in menu.elements]
_submenu(menu, name) = begin
    found = [item for item in menu.elements if string(item.action.label) == name]
    isempty(found) ? nothing : first(found).submenu
end

@testset "a menu item performs its command" begin
    # `WidgetShell` fires a menu shortcut before the focused widget sees the key,
    # so an item that cannot perform its command takes the key from whatever
    # could have answered it. Every item on the bar must carry a callback.
    items = Action[]
    walk(node) = begin
        node isa WidgetMenuItem && (push!(items, node.action);
                                    node.submenu isa WidgetDocument && walk(node.submenu))
        node isa WidgetMenu && foreach(walk, collect(node.elements))
    end
    walk(make_window_menu_bar())
    for action in items
        action.shortcut === nothing && continue
        @test action.callback !== nothing
    end
    @test !isempty(items)
end

@testset "the bar holds one menu of each make function, in order" begin
    file, view, help = make_window_file_menu(), make_window_view_menu(), make_window_help_menu()
    @test string(file.action.label) == "File"
    @test _labels(file.submenu) == ["New tab", "Close tab"]
    @test string(view.action.label) == "View"
    @test _labels(view.submenu) ==
          ["Split vertically", "Split horizontally", "Gesture log", "Appearance", "Settings"]
    @test string(help.action.label) == "Help"
    @test _labels(help.submenu) == ["Documents", "Projections", "About"]
    @test _labels(make_window_menu_bar()) == ["File", "View", "Help"]
    # A host's own menus come after File and View, and Help is the last menu.
    extra = WidgetMenuItem("Run"; submenu = WidgetMenu(Any[make_window_command("Go", _ -> nothing)]))
    bar = make_window_menu_bar(; extra = [extra])
    @test _labels(bar) == ["File", "View", "Run", "Help"]
    @test bar.elements[3] === extra
end

@testset "the Help menu offers the tool of a wrapper only when the wrapper is on" begin
    @test _labels(make_window_help_menu(; gesture_help = true).submenu) ==
          ["Gestures", "Documents", "Projections", "About"]
    @test _labels(make_window_help_menu(; command_palette = true).submenu) ==
          ["Command palette", "Documents", "Projections", "About"]
    help = make_window_help_menu(; gesture_help = true, command_palette = true)
    @test _labels(help.submenu) == ["Gestures", "Command palette", "Documents", "Projections", "About"]
    # The key reaches the wrapper itself, so the item carries none, and its
    # tooltip names the key.
    for (item, key) in zip(collect(help.submenu.elements)[1:2], ("(F1)", "(Ctrl+Shift+P)"))
        @test item.action.shortcut === nothing
        @test endswith(item.tooltip, key)
    end
    bar = make_window_menu_bar(; gesture_help = true, command_palette = true)
    @test _labels(_submenu(bar, "Help"))[1:2] == ["Gestures", "Command palette"]
end

@testset "each Help item opens its tab, and a second use opens no other" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))]))
    group = first(get_pane_groups(tree))
    first_tab() = apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    first_tab()
    editor = _ShellFakeEditor(tree)
    # A host gives the page of its own program.
    page = AboutPage(; name = "Host", version = "2.0")
    help = make_window_help_menu(; about = _ -> page)
    # A list is longer than a pane, so it opens inside a scroll pane; the page
    # about the program is short and opens bare.
    shown(tab) = (document = get_wrapped_document(tab.content);
                  document isa WidgetScrollPane ? document.content : document)
    holding(type) = [shown(tab) for tab in group.tabs if shown(tab) isa type]
    for (item, type) in zip(help.submenu.elements, [DocumentTypeList, ProjectionList, AboutPage])
        evaluate_operation(editor, InvokeActionOperation(item.action))
        @test length(holding(type)) == 1
        first_tab()
        evaluate_operation(editor, InvokeActionOperation(item.action))
        @test length(holding(type)) == 1
        @test _is_focused_at(tree, group, findfirst(tab -> shown(tab) isa type, collect(group.tabs)))
    end
    @test only(holding(AboutPage)) === page
    @test length(group.tabs) == 4
    tab(type) = only(tab for tab in group.tabs if shown(tab) isa type)
    @test get_wrapped_document(tab(DocumentTypeList).content) isa WidgetScrollPane
    @test get_wrapped_document(tab(ProjectionList).content) isa WidgetScrollPane
    @test get_wrapped_document(tab(AboutPage).content) === page
    # The tab is titled by the list, not by the scroll pane.
    @test get_pane_tab_title_string(tab(DocumentTypeList)) == "Documents"
    @test get_pane_tab_title_string(tab(ProjectionList)) == "Projections"
    # A saved window keeps the list in its scroll pane, and where it was
    # scrolled.
    pane = get_wrapped_document(tab(DocumentTypeList).content)
    pane.scroll_position.y[] = 40
    text = print_pred_text(pane)
    again = parse_pred_text(text)
    @test again isa WidgetScrollPane
    @test again.content isa DocumentTypeList
    @test occursin("scroll_position = Point2D(x = 0, y = 40),", text)
    @test (again.scroll_position.x[], again.scroll_position.y[]) == (0, 40)
end

@testset "the shell prints what it holds with the step of its field" begin
    seen = String[]
    recording = ReferenceDispatchingProjection(reference -> begin
        push!(seen, repr(strip_reference_types(reference)))
        IdentityProjection()
    end)
    shell = WidgetShell(PrimitiveString("x"); size = Point2D(200, 100))
    iomap = print_document(make_window_shell_projection(recording), shell)
    collect(iomap.output.elements)     # the shell prints its bands when it draws
    @test seen == [".content"]
end

@testset "a menu command does what the key does" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))]))
    apply_pane_operation!(tree, make_pane_focus_operation(tree, first(get_pane_groups(tree)), 1))
    editor = _ShellFakeEditor(tree)
    before = sum(length(group.tabs) for group in get_pane_groups(tree))

    new_tab = only(a for a in _menu_actions() if string(a.label) == "New tab")
    evaluate_operation(editor, InvokeActionOperation(new_tab))
    @test sum(length(group.tabs) for group in get_pane_groups(tree)) == before + 1

    split = only(a for a in _menu_actions() if string(a.label) == "Split vertically")
    groups = length(get_pane_groups(tree))
    evaluate_operation(editor, InvokeActionOperation(split))
    @test length(get_pane_groups(tree)) == groups + 1
end

@testset "View opens the session's gesture log, and only once" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))]))
    first_tab() = apply_pane_operation!(tree,
        make_pane_focus_operation(tree, first(get_pane_groups(tree)), 1))
    first_tab()
    editor = _ShellFakeEditor(tree)
    log = get_session_gesture_log()
    holding() = [(group, index) for group in get_pane_groups(tree)
                 for (index, tab) in enumerate(group.tabs) if tab.content === log]
    open_log = only(a for a in _menu_actions() if string(a.label) == "Gesture log")

    evaluate_operation(editor, InvokeActionOperation(open_log))
    @test length(holding()) == 1
    # A second press gives the focus back to that tab and opens no other.
    first_tab()
    evaluate_operation(editor, InvokeActionOperation(open_log))
    @test length(holding()) == 1
    (group, index) = only(holding())
    focus = get_pane_focus(tree)
    @test focus[1] === group && focus[2] == index
end

@testset "a tool button reaches its tool, and opens one only when there is none" begin
    # Two groups, and the focus in the first one.
    left = PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))])
    right = PaneGroup(PaneTab[PaneTab("b", PrimitiveString("y"))])
    tree = PaneTree(PaneSplit(:vertical, Any[left, right]))
    focus(group, index) = apply_pane_operation!(tree, make_pane_focus_operation(tree, group, index))
    focus(left, 1)
    editor = _ShellFakeEditor(tree)
    given = Any[]
    make = editor_seen -> (push!(given, editor_seen); GestureLog())
    button = make_window_tool_command("Gesture log", GestureLog; icon = :keyboard, make = make)
    @test button isa WidgetToolbarItem
    press() = evaluate_operation(editor, InvokeActionOperation(button.action))
    holding() = [(group, index) for group in get_pane_groups(tree)
                 for (index, tab) in enumerate(group.tabs)
                 if get_wrapped_document(tab.content) isa GestureLog]
    tabs() = sum(length(group.tabs) for group in get_pane_groups(tree))

    # The first press makes one, with the editor, and gives it the focus.
    before = tabs()
    press()
    @test tabs() == before + 1
    @test length(holding()) == 1
    @test only(given) === editor
    (group, index) = only(holding())
    @test _is_focused_at(tree, group, index)

    # A second press, from elsewhere, makes none and reaches the same tab.
    focus(left, 1)
    press()
    @test tabs() == before + 1
    @test length(given) == 1
    @test _is_focused_at(tree, group, index)

    # The focused group is searched first: with a log in each group, the press
    # reaches the one beside the person.
    other = group === left ? right : left
    apply_pane_operation!(tree, make_pane_open_tab_operation(tree, other,
                                                             PaneTab("log", GestureLog())))
    focus(other, 1)
    press()
    @test get_pane_focus(tree)[1] === other
    @test get_wrapped_document(other.tabs[get_pane_focus(tree)[2]].content) isa GestureLog
end

@testset "a tool inside a wrapper counts as the tool" begin
    wrapped = ClipboardSlice(GestureLog(), EmptyReference())
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x")),
                                      PaneTab("log", wrapped)]))
    group = first(get_pane_groups(tree))
    apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    editor = _ShellFakeEditor(tree)
    button = make_window_tool_command("Gesture log", GestureLog)
    evaluate_operation(editor, InvokeActionOperation(button.action))
    @test length(group.tabs) == 2
    @test _is_focused_at(tree, group, 2)
end

@testset "the toolbar holds the tools of the window, as pictures" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    tools = ["Explorer", "Evaluator", "Message log", "Gesture log", "Fault log",
             "Statistics", "Frame times", "Selection", "Appearance", "Settings"]
    # With no assistant the window has none, and no button for one.
    @test labels(make_window_toolbar()) == tools
    bar = make_window_toolbar(; assistant = _ -> Assistant())
    @test labels(bar) == insert!(copy(tools), 2, "Assistant")
    @test all(item -> item isa WidgetToolbarItem, bar.elements)
    @test [item.action.icon for item in bar.elements] ==
          [:folder, :chat, :terminal, :list, :keyboard, :warning, :chart, :chart_line, :crosshair,
           :palette, :settings]
    # The tooltip names the tool first, because the picture does not.
    @test all(item -> startswith(item.tooltip, string(item.action.label, ":")), bar.elements)
    # What the band draws is pictures and no word.
    texts = Any[]
    walk(canvas) = for element in canvas.elements
        element = element isa Cell ? element[] : element
        element isa GraphicsText && push!(texts, element)
        element isa GraphicsCanvas && walk(element)
    end
    walk(print_document(make_widget_projection_example(), bar).output)
    # Every text is a glyph of the icon font, one for each tool, in the order of
    # the band.
    value(v) = v isa Cell ? v[] : v
    @test all(t -> compute_font_path(value(t.font)) == compute_font_path(StyleFont("Lucide", 20)), texts)
    @test [string(value(t.text)) for t in texts] ==
          [string(find_icon_character(item.action.icon)) for item in bar.elements]
    # A host's own buttons come after the tools.
    extra = make_window_command("Run", _ -> nothing)
    @test last(make_window_toolbar(; extra = [extra]).elements) === extra
end

@testset "each tool button opens its tool, and a second press opens no other" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))]))
    group = first(get_pane_groups(tree))
    first_tab() = apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    first_tab()
    editor = _ShellFakeEditor(tree)
    bar = make_window_toolbar(; assistant = _ -> Assistant())
    types = [Workspace, Assistant, EvaluatorToplevel, MessageLog, GestureLog, FaultLog,
             FrameStatistics, FrameTimeSeries, SelectionInspector]
    holding(type) = count(tab -> get_wrapped_document(tab.content) isa type, group.tabs)
    for (item, type) in zip(bar.elements, types)
        evaluate_operation(editor, InvokeActionOperation(item.action))
        @test holding(type) == 1
        first_tab()
        evaluate_operation(editor, InvokeActionOperation(item.action))
        @test holding(type) == 1
    end
    @test length(group.tabs) == 1 + length(types)
end

@testset "the explorer opens the folder the window names, else the working directory" begin
    folders(tree) = [get_wrapped_document(tab.content).folders[1].pathname
                     for group in get_pane_groups(tree) for tab in group.tabs
                     if get_wrapped_document(tab.content) isa Workspace]
    press_explorer(bar) = begin
        tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", PrimitiveString("x"))]))
        apply_pane_operation!(tree, make_pane_focus_operation(tree, first(get_pane_groups(tree)), 1))
        evaluate_operation(_ShellFakeEditor(tree), InvokeActionOperation(first(bar.elements).action))
        folders(tree)
    end
    @test press_explorer(make_window_toolbar()) == [pwd()]
    folder = mktempdir()
    named = make_window_toolbar(; explorer = _ -> Workspace([WorkspaceFolder("here", folder)]))
    @test press_explorer(named) == [folder]
end

@testset "the pointer lights what it is over, in the bands and in the content" begin
    # A window with a toolbar of its own and the tooltip window, because the moves
    # that the screen gives on must reach the bands, and the tooltip must not take
    # them. The wrappers of the window go around the shell.
    press = WidgetButton("Press"; size = Point2D(120, 40))
    command = make_window_command("Run", editor -> nothing)
    parts = make_editor_parts(make_window_shell_document(VerticalLayout(Any[press]);
                                                         toolbar = WidgetToolbar(Any[command])),
                              make_window_shell_projection(make_layout_projection_example());
                              tabs = false, appearance = false, gesture_log = true)
    document, projection = parts.document, parts.projection
    scene = make_window_scene(document, "shell"; width = 400, height = 300)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections())
    tracked, tracking = make_tracking_screen(scene, composed;
                                             inner_wrappers = [wrap_tooltip_window])
    backend = HeadlessBackend()
    editor = Editor(tracked, tracking; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    time = Ref(0.0)
    move!(x, y) = (push_event!(backend, WindowInput(:shell, MouseMove(x, y; time = time[] += 0.01)));
                   run_frame!(editor))
    value(v) = v isa Cell ? value(v[]) : v
    function place_of(text, node = print_document(composed, scene).output.windows[1].content,
                      ox = 0, oy = 0)
        node = value(node)
        node === nothing && return nothing
        x = hasproperty(node, :x) ? ox + Int(value(node.x)) : ox
        y = hasproperty(node, :y) ? oy + Int(value(node.y)) : oy
        hasproperty(node, :text) && value(node.text) == text && return (x, y)
        if hasproperty(node, :elements)
            for element in value(node.elements)
                found = place_of(text, element, x, y)
                found === nothing || return found
            end
        end
        nothing
    end
    (rx, ry) = place_of("Run")
    (px, py) = place_of("Press")
    move!(rx + 2, ry + 2)
    @test get_mouse_target(command) !== nothing
    move!(px + 2, py + 2)
    @test get_mouse_target(command) === nothing
    @test get_mouse_target(press) !== nothing
    move!(390, 290)
    @test get_mouse_target(press) === nothing
end

@testset "the status bar says where the person is" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a.json", PrimitiveString("x"))]))
    apply_pane_operation!(tree, make_pane_focus_operation(tree, first(get_pane_groups(tree)), 1))
    bar = make_window_status_bar(tree; extra = String["Ready"])
    segments = [string(bar.elements[i]) for i in 1:length(bar.elements)]
    @test segments[1] == "a.json"        # the focused tab
    @test last(segments) == "Ready"      # what the host appended

    # And it FOLLOWS the window: a second tab taking the focus changes what the
    # band says, without the band being rebuilt.
    apply_pane_operation!(tree, make_pane_open_tab_operation(
        tree, first(get_pane_groups(tree)), PaneTab("b.json", PrimitiveString("y"))))
    apply_pane_operation!(tree, make_pane_focus_operation(tree, first(get_pane_groups(tree)), 2))
    @test string(bar.elements[1]) == "b.json"
end

@testset "a window with no tree still has a status bar" begin
    bar = make_window_status_bar(PrimitiveString("x"))
    @test string(bar.elements[1]) == ""
end

@testset "the status line keeps its text off the edges" begin
    measure = FontFileMeasure()
    recursion = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = measure).dispatch))
    bar = make_window_status_bar(PrimitiveString("x"); extra = ["ready"])
    output = print_document(recursion, nothing, bar, PrinterContext()).output
    value(v) = v isa Cell ? v[] : v
    texts = [value(e) for e in output.elements if value(e) isa GraphicsText]
    ready = only(t for t in texts if value(t.text) == "ready")
    # The line is the line box of the text in the font the bar draws it with.
    line = compute_line_box(measure, "ready", value(ready.font)).height
    # Four pixels above and below the text, and eight before it.
    @test Int(value(ready.y)) == 4
    @test Int(value(ready.x)) >= 8
    @test Int(value(output.h)) == line + 8
end

@testset "a window that records nothing offers no tool and no item that stay empty" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    @test labels(make_window_toolbar(; recorded = ())) ==
          ["Explorer", "Evaluator", "Selection", "Appearance", "Settings"]
    @test "Gesture log" ∉ _labels(_submenu(make_window_menu_bar(; recorded = ()), "View"))
    @test "Gesture log" in _labels(_submenu(make_window_menu_bar(), "View"))
end

@testset "the status bar names the place in the document of the focused tab, and nothing above it" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a", WidgetLabel("x"))]))
    bar = make_window_status_bar(tree)
    shown() = string(bar.elements[2])
    set_selection!(tree, @reference(tree, root.tabs[1].content.content))
    found = find_pane_content_selection(tree)
    @test strip_reference_types(found) == ConcreteReference(FieldReferenceStep("content"), EmptyReference())
    @test shown() == sprint(show, found; context = :compact => true)
    @test !occursin("tabs", shown()) && !occursin("root", shown())
    # The whole document of the tab says nothing more than the title, and the
    # tab and the group name no place in a document.
    set_selection!(tree, @reference(tree, root.tabs[1].content))
    @test shown() == ""
    set_selection!(tree, @reference(tree, root.tabs[1]))
    @test find_pane_content_selection(tree) === nothing
    @test shown() == ""
end

@testset "the shell wrapper puts the tabs in the chrome of a window" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    editor = build_editor(WidgetLabel("hi"), NaturalToGraphics(measure = FontFileMeasure());
                          backend = _ShellProbeBackend(), devices = ProjecturedKernel.DeviceModule.Device[],
                          shell = true)
    shell = get_wrapped_document(editor.document).windows[1].content
    @test shell isa WidgetShell
    @test shell.content isa PaneTree
    @test shell.menu_bar isa WidgetMenu
    @test shell.status_bar isa WidgetStatusBar
    # It records nothing, so the toolbar has the tools that need nothing more.
    @test labels(shell.toolbar) == ["Explorer", "Evaluator", "Selection", "Appearance", "Settings"]
    # A command of a band finds the tree in the content of the shell.
    @test find_pane_tree_reference(; editor) !== nothing
    # The window draws the bands and the tab.
    texts = _shell_texts(get_iomap_output(editor.iomap).windows[1].content)
    @test "File" in texts && "hi" in texts
    @test string(find_icon_character(:folder)) in texts
    # A window that records its gestures has the gesture log.
    recorded = build_editor(WidgetLabel("hi"), NaturalToGraphics(measure = FontFileMeasure());
                            backend = _ShellProbeBackend(), devices = ProjecturedKernel.DeviceModule.Device[],
                            shell = true, gesture_log = true)
    @test "Gesture log" in labels(get_wrapped_document(recorded.document).windows[1].content.toolbar)
    # The shell is off by default.
    plain = build_editor(WidgetLabel("hi"), NaturalToGraphics(measure = FontFileMeasure());
                         backend = _ShellProbeBackend(), devices = ProjecturedKernel.DeviceModule.Device[])
    @test get_wrapped_document(plain.document).windows[1].content isa PaneTree
end

@testset "the shell is a document, and the wrapper puts the window inside it" begin
    parts = make_editor_parts(PrimitiveString("x"), make_layout_projection_example();
                              tabs = false, appearance = false, settings = false,
                              focus_cycling = false, shell = true)
    document, projection = parts.document, parts.projection
    # The chrome is structured data, so it can be reached like anything else.
    @test document isa WidgetShell
    @test document.content isa PrimitiveString
    @test document.menu_bar isa WidgetMenu
    @test !isempty(search_documents(document, node -> node isa WidgetToolbar))
    @test print_document(projection, document).output !== nothing
end

@testset "a window read back from a file is not wrapped twice" begin
    once = make_window_shell_document(PrimitiveString("x");
                                      menu_bar = make_window_menu_bar())
    twice = make_window_shell_document(once; toolbar = make_window_toolbar())
    @test twice === once
    @test twice.content isa PrimitiveString
    @test twice.menu_bar isa WidgetMenu     # what it was given first, kept
    @test twice.toolbar isa WidgetToolbar   # and what it was given after
end

@testset "a saved user interface holds the window, and the binary its bands" begin
    shell = make_window_shell_document(PrimitiveString("x");
                                       menu_bar = make_window_menu_bar(),
                                       toolbar = make_window_toolbar(),
                                       size = Point2D(400, 300))
    shell.margin = Inset(1, 2, 3, 4)
    directory = mktempdir()
    save_user_interface(joinpath(directory, "session.pred"); editor = _ShellFakeEditor(shell))
    @test isfile(joinpath(directory, "session.pred"))
    again = load_user_interface(joinpath(directory, "session.pred"))
    @test again isa WidgetShell
    @test again.content isa PrimitiveString
    # The window keeps the size and the margins that it had.
    @test (again.size.x[], again.size.y[]) == (400, 300)
    @test (again.margin.top[], again.margin.bottom[], again.margin.left[], again.margin.right[]) ==
          (1, 2, 3, 4)
    # The bands are the binary's, built fresh at every start, so the file holds
    # none of them. The fold fills them into the shell that comes back, and the
    # wrapper is idempotent so nothing is wrapped twice.
    @test again.menu_bar === nothing
    @test again.toolbar === nothing
    filled = make_window_shell_document(again; menu_bar = make_window_menu_bar())
    @test filled === again
    @test filled.menu_bar isa WidgetMenu
end

end # @testset
end # function
