# A second window of tabs, through the loop of a real editor: it opens with the
# layers of the first window, it draws as the first window, a key of the menus fires
# in it, it has an undo history of its own, and one clipboard serves both windows.

# An editor on the text `hello` in one tab of a window, with an undo history, the
# bands of a window and the clipboard, as the application has them.
_tw_editor() = _ww_editor(PrimitiveString("hello"); window = (; width = 800, height = 600),
                          undo = true, shell = true, clipboard = true)

_tw_screen(editor) = get_wrapped_document(editor.document)

_tw_key(id, key; ctrl = false, alt = false) =
    WindowInput(id, KeyDown(key, ModifierKeys(ctrl = ctrl, alt = alt); time = 0.0))

# The documents from the root of `editor` down to its screen, the root first.
function _tw_root_chain(editor)
    chain = Any[]
    node = editor.document
    while true
        push!(chain, node)
        node isa ScreenDocument && return chain
        hasproperty(node, :content) || return chain
        node = node.content
    end
end

# The clipboard of `editor`, the one that wraps its screen.
_tw_clipboard(editor) = only(node for node in _tw_root_chain(editor) if node isa ClipboardSlice)

# Open the window `second` with the tab of the text `world`, and give it a frame.
function _tw_open_second!(editor)
    evaluate_operation(editor, OpenPaneWindowOperation(PaneTab("second", PrimitiveString("world"));
                                                       x = 900, y = 0, width = 600, height = 400))
    run_frame!(editor)
    _tw_screen(editor).windows[end]
end

# A held move and a release of the pointer in the window `id`, as a person drags.
_tw_held!(editor, backend, id, x, y, time) =
    _ww_press!(editor, backend, WindowInput(id, MouseMove(x, y, MouseButtons(:left), ModifierKeys(); time)))
_tw_down!(editor, backend, id, x, y, time) =
    _ww_press!(editor, backend, WindowInput(id, MouseDown(:left, x, y, ModifierKeys(); time)))
_tw_up!(editor, backend, id, x, y, time) =
    _ww_press!(editor, backend, WindowInput(id, MouseUp(:left, x, y, ModifierKeys(); time)))

# An editor whose window, at (0, 0), holds the tab of the text `hello` and the tab
# `two` of the text `zwei`.
function _tw_two_tab_editor()
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    screen.windows[1].x = 0
    screen.windows[1].y = 0
    open_pane!(PrimitiveString("zwei"); title = "two", editor)
    run_frame!(editor)
    (editor, backend, screen)
end

# Press on the header of the tab `name` in the window `id` and start its drag.
function _tw_grab!(editor, backend, screen, id, name)
    place = _cm_place_of(_cm_drawn_window(editor, screen, id), name)
    place === nothing && return nothing
    x, y = place[1] + 3, place[2] + 4
    _ww_press!(editor, backend, WindowInput(id, MouseMove(x, y; time = 0.9)))
    _tw_down!(editor, backend, id, x, y, 1.0)
    _tw_held!(editor, backend, id, x + 12, y, 1.1)
    (x, y)
end

_tw_has_label(screen) = any(window -> window.id === :pane_tab_label, screen.windows)

function test_tab_window()
@testset "a second window of tabs" begin

@testset "a window of tabs opens with the layers of the first window" begin
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    first = screen.windows[1]
    second = _tw_open_second!(editor)
    @test length(screen.windows) == 2
    @test second.id === Symbol("tabs-2")
    @test second.title == "second"
    @test second.style === :normal
    @test (second.x, second.y, second.width, second.height) == (900, 0, 600, 400)
    # The bands around an undo history around the tabs, as in the first window.
    @test first.content isa WidgetShell && second.content isa WidgetShell
    @test first.content.content isa UndoBuffer && second.content.content isa UndoBuffer
    tree = second.content.content.content
    @test tree isa PaneTree
    @test get_pane_tab_title_string(tree.root.tabs[1]) == "second"
    @test second.content.menu_bar !== first.content.menu_bar
    @test second.content.toolbar !== first.content.toolbar
    # The second window draws its tab, what the tab shows, and its bands.
    drawn = _cm_drawn_window(editor, screen, second.id)
    @test _cm_place_of(drawn, "second") !== nothing
    @test _cm_place_of(drawn, "world") !== nothing
    @test _cm_place_of(drawn, "File") !== nothing
    # One clipboard, around the screen; no window holds one of its own.
    @test count(node -> node isa ClipboardSlice, _tw_root_chain(editor)) == 1
    @test !(first.content isa ClipboardSlice)
end

@testset "a key of the menus fires in the second window" begin
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    second = _tw_open_second!(editor)
    _ww_press!(editor, backend, _tw_key(second.id, :o; ctrl = true))
    @test any(window -> window.id === :file_dialog, screen.windows)
end

@testset "a copy in the first window pastes in the second, and each window has its own undo" begin
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    first = screen.windows[1]
    second = _tw_open_second!(editor)
    tab = second.content.content.content.root.tabs[1]
    # Ctrl+C on the tab of the first window stores its text.
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _tw_key(first.id, :c; ctrl = true))
    clipboard = _tw_clipboard(editor)
    @test clipboard.slice isa PrimitiveString && clipboard.slice.value == "hello"
    # Ctrl+V on the content of the tab of the second window puts it there.
    focus_pane!(find_pane_reference("second"; editor); editor)
    _ww_press!(editor, backend, _tw_key(second.id, :down; alt = true))
    _ww_press!(editor, backend, _tw_key(second.id, :v; ctrl = true))
    @test tab.content.value == "hello"
    first_steps = length(first.content.content.undo_entries)
    @test length(second.content.content.undo_entries) == 1
    # Ctrl+Z in the second window undoes the paste there, and the first window keeps
    # its own history.
    _ww_press!(editor, backend, _tw_key(second.id, :z; ctrl = true))
    @test tab.content.value == "world"
    @test length(first.content.content.undo_entries) == first_steps
    # A copy in the second window replaces what the clipboard holds.
    _ww_press!(editor, backend, _tw_key(second.id, :c; ctrl = true))
    @test clipboard.slice isa PrimitiveString && clipboard.slice.value == "world"
end

@testset "the shared clipboard offers no toggle" begin
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _tw_key(screen.windows[1].id, :slash; ctrl = true))
    @test get_wrapped_document(editor.document) isa ScreenDocument
    @test length(screen.windows) >= 1
    @test _tw_clipboard(editor).slice === nothing
end

@testset "a tab dragged outside every window goes to a new window at the pointer" begin
    editor, backend, screen = _tw_two_tab_editor()
    first = screen.windows[1]
    tree = get_window_tree(first.content)
    group = only(get_pane_groups(tree))
    @test length(group.tabs) == 2 && get_pane_tab_title_string(group.tabs[2]) == "two"
    kept, moved = group.tabs
    steps = length(first.content.content.undo_entries)
    grabbed = _tw_grab!(editor, backend, screen, first.id, "two")
    @test grabbed !== nothing
    grabbed === nothing && return
    # Outside the window, the label of the tab follows the pointer.
    _tw_held!(editor, backend, first.id, 1000, 300, 1.2)
    @test _tw_has_label(screen)
    _tw_held!(editor, backend, first.id, 1010, 310, 1.3)
    label = only(window for window in screen.windows if window.id === :pane_tab_label)
    @test label.style === :tooltip
    @test (label.x, label.y) == (1010 + 16, 310 + 12)
    # Back over the window the label goes; outside again it comes back.
    _tw_held!(editor, backend, first.id, 400, 300, 1.4)
    @test !_tw_has_label(screen)
    _tw_held!(editor, backend, first.id, 1000, 300, 1.5)
    @test _tw_has_label(screen)
    # The release outside opens a window with the tab, its corner at the pointer.
    _tw_up!(editor, backend, first.id, 1000, 300, 1.6)
    @test !_tw_has_label(screen)
    windows = [window for window in screen.windows if window.style === :normal]
    @test length(windows) == 2
    second = windows[2]
    @test (second.x, second.y) == (1000, 300)
    @test second.title == "two"
    # The size of the pane that the tab came from, at least 400 by 300.
    @test 400 <= second.width <= 800 && 300 <= second.height <= 600
    new_tree = get_window_tree(second.content)
    @test only(only(get_pane_groups(new_tree)).tabs) === moved      # the same tab
    @test length(group.tabs) == 1 && group.tabs[1] === kept
    # No history records the move.
    @test length(first.content.content.undo_entries) == steps
    @test length(second.content.content.undo_entries) == 0
end

@testset "the only tab of a window does not go out" begin
    editor, backend = _tw_editor()
    screen = _tw_screen(editor)
    screen.windows[1].x = 0
    screen.windows[1].y = 0
    first = screen.windows[1]
    grabbed = _tw_grab!(editor, backend, screen, first.id, "hello")
    @test grabbed !== nothing
    grabbed === nothing && return
    _tw_held!(editor, backend, first.id, 1000, 300, 1.2)
    @test !_tw_has_label(screen)
    _tw_up!(editor, backend, first.id, 1000, 300, 1.3)
    @test count(window -> window.style === :normal, screen.windows) == 1
    @test length(only(get_pane_groups(get_window_tree(first.content))).tabs) == 1
end

@testset "the menu of a tab moves it to a new window, and is off for the only tab" begin
    editor, backend, screen = _tw_two_tab_editor()
    tree = get_window_tree(screen.windows[1].content)
    group = only(get_pane_groups(tree))
    menu = ProjecturedPlatform.PaneModule._make_tab_menu(tree, group, 2)
    item = only(element for element in menu.elements
                if element isa WidgetMenuItem && string(element.action.label) == "Move to new window")
    @test item.enabled
    evaluate_operation(editor, item.operation)
    run_frame!(editor)
    @test count(window -> window.style === :normal, screen.windows) == 2
    @test length(group.tabs) == 1
    only_menu = ProjecturedPlatform.PaneModule._make_tab_menu(tree, group, 1)
    only_item = only(element for element in only_menu.elements
                     if element isa WidgetMenuItem && string(element.action.label) == "Move to new window")
    @test !only_item.enabled
end

# Whether `operation` is or holds an operation of type `T`.
_tw_holds(operation, T) =
    operation isa T ||
    (operation isa CompoundOperation && any(member -> _tw_holds(member, T), operation.operations)) ||
    (operation isa WrappingOperation && _tw_holds(get_wrapped_operation(operation), T))

@testset "a tab dragged into another window moves there, and the window it left closes" begin
    editor, backend, screen = _tw_two_tab_editor()
    first = screen.windows[1]
    second = _tw_open_second!(editor)                      # at (900, 0), with the tab `second`
    tree = get_window_tree(first.content)
    group = only(get_pane_groups(tree))
    kept, two = group.tabs
    moved = only(only(get_pane_groups(get_window_tree(second.content))).tabs)
    steps = length(first.content.content.undo_entries)
    grabbed = _tw_grab!(editor, backend, screen, second.id, "second")
    @test grabbed !== nothing
    grabbed === nothing && return
    # The moves come in the window of the press: the point in the frame of `second`
    # is the point of the strip of `first`, just left of the name `two`.
    header = _cm_place_of(_cm_drawn_window(editor, screen, first.id), "two")
    @test header !== nothing
    x, y = header[1] - 4, header[2] + 4
    _tw_held!(editor, backend, second.id, x - 900, y, 1.2)
    @test tree.drop !== nothing && tree.drop.target === group && tree.drop.place == 2
    _tw_up!(editor, backend, second.id, x - 900, y, 1.3)
    @test length(group.tabs) == 3
    @test group.tabs[1] === kept && group.tabs[2] === moved && group.tabs[3] === two
    @test tree.drop === nothing
    # The window that the last tab left closes, and no history records the move.
    @test count(window -> window.style === :normal, screen.windows) == 1
    @test !any(window -> window.id === second.id, screen.windows)
    @test length(first.content.content.undo_entries) == steps
end

@testset "the close of a window releases its tabs, and the close of the last window quits" begin
    editor, backend, screen = _tw_two_tab_editor()
    first = screen.windows[1]
    second = _tw_open_second!(editor)
    content = only(only(get_pane_groups(get_window_tree(second.content))).tabs).content
    @test ProjecturedPlatform.DomainModule.is_document_held(editor, content)
    _ww_press!(editor, backend, WindowInput(second.id, WindowClose(; time = 0.0)))
    @test !any(window -> window.id === second.id, screen.windows)
    @test !ProjecturedPlatform.DomainModule.is_document_held(editor, content)
    @test count(window -> window.style === :normal, screen.windows) == 1
    # The close of the last window answers the quit of the editor.
    answer = read_intent(editor.projection, nothing,
                         Intent(WindowInput(first.id, WindowClose(; time = 0.0)), nothing), editor.iomap)
    @test _tw_holds(answer isa Intent ? answer.operation : answer, QuitEditorOperation)
end

end # @testset
end # test_tab_window
