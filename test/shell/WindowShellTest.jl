# The chrome a window is drawn in, and the rule that keeps it honest.

mutable struct _ShellFakeEditor; document::Any; end

function test_window_shell()
@testset "the window shell" begin

_labels(menu) = [String(string(item.action.label)) for item in menu.elements]
_submenu(menu, name) = begin
    found = [item for item in menu.elements if string(item.action.label) == name]
    isempty(found) ? nothing : first(found).submenu
end

@testset "a menu item names a gesture the window answers" begin
    # A shortcut and a gesture binding carry the same pattern shape, so the two
    # compare directly: the key and the modifiers it asks for.
    # A pattern that names no key constrains the key with a guard instead — the
    # four arrow keys share one rule — so it carries no signature to compare.
    names_key(pattern) = pattern isa EventPattern{KeyDown} && haskey(pattern.fields, :key)
    signature(pattern) = (pattern.fields.key, Set(pattern.modifiers))
    bound = Set(signature(binding.pattern)
                for binding in get_document_gesture_bindings(PaneTree)
                if names_key(binding.pattern))

    bar = make_window_menu_bar()
    for name in ("File", "View")
        for item in _submenu(bar, name).elements
            shortcut = item.action.shortcut
            (shortcut === nothing || !names_key(shortcut)) && continue
            # Every shortcut on the menu belongs to something. These four
            # belong to a wrapper or a tab rather than to the pane tree:
            #   Ctrl+S, Ctrl+O   a file tab, through its own gesture table
            #   F1               the gesture help wrapper
            #   Ctrl+Shift+P     the command palette wrapper
            # The rest must be the pane tree's own, or the menu promises what
            # nothing answers.
            shortcut.fields.key in (:s, :o, :f1, :p) && continue
            @test signature(shortcut) in bound
        end
    end
end

@testset "a window without the clipboard gets no Edit menu" begin
    @test "Edit" in _labels(make_window_menu_bar(; clipboard = true))
    @test !("Edit" in _labels(make_window_menu_bar(; clipboard = false)))
end

@testset "the status bar says where the person is" begin
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("a.json", PrimitiveString("x"))]))
    apply_pane_operation!(tree, make_pane_focus_operation(tree, first(get_pane_groups(tree)), 1))
    bar = make_window_status_bar(tree; extra = String["Ready"])
    segments = [string(bar.elements[i]) for i in 1:length(bar.elements)]
    @test segments[1] == "a.json"        # the focused tab
    @test last(segments) == "Ready"      # what the host appended
end

@testset "a window with no tree still has a status bar" begin
    bar = make_window_status_bar(PrimitiveString("x"))
    @test string(bar.elements[1]) == ""
end

@testset "the shell is a document, and the fold puts the window inside it" begin
    document, projection = make_window_wrap(;
        gesture_help = false, command_palette = false, gesture_log = false,
        selection = false,
        shell = () -> (make_window_menu_bar(), make_window_toolbar(),
                       make_window_status_bar(PrimitiveString("x")), nothing,
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
