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
    # The second window draws its tab and its bands.
    texts = _ww_drawn_texts(_cm_drawn_window(editor, screen, second.id))
    @test "world" in texts
    @test "File" in texts
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

end # @testset
end # test_tab_window
