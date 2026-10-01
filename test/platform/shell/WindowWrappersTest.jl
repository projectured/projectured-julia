# The features of a window as wrappers of `build_editor`: each is a keyword, and
# each test builds an editor with it, presses real keys through the headless
# backend and runs real frames.

# An editor on `document` with the wrappers of `keywords`, after its first frame.
# With no window and no appearance, the root is the document that the wrappers of
# the container make.
function _ww_editor(document; window = false, appearance = false, keywords...)
    backend = HeadlessBackend()
    editor = build_editor(document, NaturalToGraphics(measure = FontFileMeasure());
                          backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
                          window, appearance, keywords...)
    run_frame!(editor)
    (editor, backend)
end

_ww_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

_ww_ctrl(key; shift = false) = KeyDown(key, ModifierKeys(ctrl = true, shift = shift); time = 0.0)

_ww_tabs(editor) = sum(length(group.tabs) for group in get_pane_groups(get_window_tree(editor)))

_ww_selection(editor) = repr(strip_reference_types(get_selection(editor.document)))

# Give the focus to the first tab of the window.
function _ww_focus_first_tab!(editor)
    group = first(get_pane_groups(get_window_tree(editor)))
    focus_pane!(editor, find_pane_reference(editor, get_pane_tab_title_string(group.tabs[1])))
end

function test_window_wrappers()
@testset "the features of a window as wrappers of build_editor" begin

@testset "undo: the tabs are in a buffer of the window, and Ctrl+Z takes back a tab that opened" begin
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true)
    buffer = editor.document
    @test buffer isa UndoBuffer && buffer.content isa PaneTree
    steps = length(buffer.undo_entries)
    open_pane!(editor, PrimitiveString("hello"); title = "Hello")
    @test _ww_tabs(editor) == 2
    @test length(buffer.undo_entries) == steps + 1
    _ww_press!(editor, backend, _ww_ctrl(:z))
    @test _ww_tabs(editor) == 1
end

@testset "focus_cycling: on by default, Tab starts over at the end of the window" begin
    fields() = VerticalLayout(Any[WidgetText("a"), WidgetText("b")])
    tab = KeyDown(:tab, ModifierKeys(); time = 0.0)
    places(editor, backend) = [(_ww_press!(editor, backend, tab); _ww_selection(editor)) for _ in 1:3]
    editor, backend = _ww_editor(fields(); tabs = false)
    first_place, second_place, third_place = places(editor, backend)
    @test first_place != second_place
    @test third_place == first_place
    editor, backend = _ww_editor(fields(); tabs = false, focus_cycling = false)
    first_place, second_place, third_place = places(editor, backend)
    @test third_place != first_place
end

end # @testset
end
