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
    measure = (text, font) -> (length(text) * 8, font_logical_size(font))
    recursion = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_regular_20; measure = measure).dispatch))
    bar = make_window_status_bar(PrimitiveString("x"); extra = ["ready"])
    output = print_document(recursion, nothing, bar, PrinterContext()).output
    value(v) = v isa Cell ? v[] : v
    texts = [value(e) for e in output.elements if value(e) isa GraphicsText]
    ready = only(t for t in texts if value(t.text) == "ready")
    # The line is as tall as the font the bar draws its text with.
    line = font_logical_size(value(ready.font))
    # Four pixels above and below the text, and eight before it.
    @test Int(value(ready.y)) == 4
    @test Int(value(ready.x)) >= 8
    @test Int(value(output.h)) == line + 8
end

@testset "the shell is a document, and the fold puts the window inside it" begin
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false,
        selection = false,
        shell = document -> (make_window_menu_bar(), make_window_toolbar(),
                             make_window_status_bar(document), nothing,
                             Point2D(400, 300)))(PrimitiveString("x"),
                                                 make_layout_projection_example())
    # The chrome is structured data, so it can be reached like anything else.
    @test document isa WidgetShell
    @test document.content isa PrimitiveString
    @test document.menu_bar isa WidgetMenu
    @test Int(document.size.x[]) == 400 && Int(document.size.y[]) == 300
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
                                       size = Point2D(400, 300))
    directory = mktempdir()
    save_user_interface(_ShellFakeEditor(shell), joinpath(directory, "session.pred"))
    @test isfile(joinpath(directory, "session.pred"))
    again = load_user_interface(joinpath(directory, "session.pred"))
    @test again isa WidgetShell
    @test again.content isa PrimitiveString
    # The bands are the binary's, built fresh at every start, so the file holds
    # none of them. The fold fills them into the shell that comes back, and the
    # wrapper is idempotent so nothing is wrapped twice.
    @test again.menu_bar === nothing
    filled = make_window_shell_document(again; menu_bar = make_window_menu_bar())
    @test filled === again
    @test filled.menu_bar isa WidgetMenu
end

end # @testset
end # function
