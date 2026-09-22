# The chrome a window is drawn in, and the rule that keeps it honest.

mutable struct _ShellFakeEditor; document::Any; end

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

@testset "the shell is a document, and the fold puts the window inside it" begin
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false, gesture_log = false,
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
