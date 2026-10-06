# The features of a window as wrappers of `build_editor`: each is a keyword, and
# each test builds an editor with it, presses real keys through the headless
# backend and runs real frames.

# An editor on `document` with the wrappers of `keywords`, after its first frame.
# With no window and no appearance, the root is the document that the wrappers of
# the container make.
function _ww_editor(document; window = false, appearance = false, settings = false, keywords...)
    backend = HeadlessBackend()
    editor = build_editor(document, NaturalToGraphics(measure = FontFileMeasure());
                          backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
                          window, appearance, settings, keywords...)
    run_frame!(editor)
    (editor, backend)
end

_ww_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

_ww_ctrl(key; shift = false) = KeyDown(key, ModifierKeys(ctrl = true, shift = shift); time = 0.0)

_ww_tabs(editor) = sum(length(group.tabs) for group in get_pane_groups(get_window_tree(; editor)))

_ww_selection(editor) = repr(strip_reference_types(get_selection(editor.document)))

# Give the focus to the first tab of the window.
function _ww_focus_first_tab!(editor)
    group = first(get_pane_groups(get_window_tree(; editor)))
    focus_pane!(find_pane_reference(get_pane_tab_title_string(group.tabs[1]); editor); editor)
end

# The labels of the Help menu of `shell`.
_ww_help_labels(shell) =
    [String(string(item.action.label))
     for item in only(item for item in shell.menu_bar.elements
                      if string(item.action.label) == "Help").submenu.elements]

# A click on "Help" in the bar of the window `id`, and a click on `label` in the
# menu that opens, both with the pointer, as a person does it.
function _ww_click_help_item!(editor, backend, screen, id, label, time)
    help = _cm_place_of(_cm_drawn_window(editor, screen, id), "Help")
    _cm_click!(editor, backend, :left, help[1] + 2, help[2] + 2, time; window = id)
    menu = only(window for window in screen.windows if window.style === :popup)
    item = _cm_place_of(_cm_drawn_window(editor, screen, menu.id), label)
    _cm_click!(editor, backend, :left, item[1] + 2, item[2] + 2, time + 1; window = menu.id)
end

# The descriptions of the rows of the help window of `screen`.
_ww_help_rows(screen) =
    [row.description for row in only(window.content for window in screen.windows
                                     if window.content isa GestureMap).rows]

function test_window_wrappers()
@testset "the features of a window as wrappers of build_editor" begin

@testset "undo: the tabs are in a buffer of the window, and Ctrl+Z takes back a tab that opened" begin
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true)
    buffer = editor.document
    @test buffer isa UndoBuffer && buffer.content isa PaneTree
    steps = length(buffer.undo_entries)
    open_pane!(PrimitiveString("hello"); title = "Hello", editor)
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

@testset "clipboard: the window is in a clipboard, and Ctrl+C copies the tab that has the focus" begin
    editor, backend = _ww_editor(PrimitiveString("hello"); clipboard = true)
    @test editor.document isa ClipboardSlice
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _ww_ctrl(:c))
    @test editor.document.slice isa PrimitiveString && editor.document.slice.value == "hello"
end

@testset "gesture_help: F1 opens the list of the gestures in a window, and F1 closes it" begin
    editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600),
                                 gesture_help = true)
    screen = get_wrapped_document(editor.document)
    id = screen.windows[1].id
    f1 = WindowInput(id, KeyDown(:f1, ModifierKeys(); time = 0.0))
    _ww_press!(editor, backend, f1)
    @test length(screen.windows) == 2
    @test any(window -> window.content isa GestureMap, screen.windows)
    _ww_press!(editor, backend, f1)
    @test length(screen.windows) == 1
end

@testset "command_palette: Ctrl+Shift+P opens the palette over the window" begin
    editor, backend = _ww_editor(PrimitiveString("x"); command_palette = true)
    before = Set(_shell_texts(last(rendered_output(backend))))
    _ww_press!(editor, backend, _ww_ctrl(:p; shift = true))
    @test !issubset(Set(_shell_texts(last(rendered_output(backend)))), before)
end

@testset "gesture_log: an operation of the window is an entry of the gesture log" begin
    log = get_session_gesture_log()
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true, gesture_log = true)
    entries = length(log.entries)
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _ww_ctrl(:t))
    @test _ww_tabs(editor) == 2
    @test length(log.entries) > entries
end

@testset "gesture_log: with overlay, the newest gestures draw in a panel over the window" begin
    log = get_session_gesture_log()
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true,
                                 gesture_log = (; overlay = true, lines = 3))
    @test "no gesture yet" in _shell_texts(last(rendered_output(backend)))
    entries = length(log.entries)
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _ww_ctrl(:t))
    # The log of the session records as before, and the panel draws the gesture.
    @test length(log.entries) > entries
    texts = _shell_texts(last(rendered_output(backend)))
    @test !("no gesture yet" in texts)
    @test any(text -> strip(text) == "Ctrl+T", texts)
end

@testset "message_log: a capture of the logger while the loop runs, and a feed" begin
    replaced = Base.CoreLogging.global_logger()
    editor, _ = _ww_editor(PrimitiveString("x"); message_log = true)
    try
        @test Base.CoreLogging.global_logger() isa MessageLogLogger
        @test any(feed -> feed isa MessageLogFeed, editor.feeds)
    finally
        foreach(step -> step(editor), editor.stop_steps)
    end
    @test Base.CoreLogging.global_logger() === replaced
end

@testset "frame_statistics: a feed of the frames" begin
    editor, _ = _ww_editor(PrimitiveString("x"); frame_statistics = true)
    @test any(feed -> feed isa FrameStatisticsFeed, editor.feeds)
end

@testset "fault_log: the session log on the fault store of the editor" begin
    editor, _ = _ww_editor(PrimitiveString("x"); fault_log = true)
    @test any(target -> target === get_session_fault_log(), editor.faults.targets)
end

@testset "shell: a tool that shows what the window records is there when its wrapper is" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    recorded = (; message_log = true, gesture_log = true, fault_log = true, frame_statistics = true)
    editor, _ = _ww_editor(PrimitiveString("x"); shell = (; assistant = _ -> Assistant(),
                                                           status_bar = false), recorded...)
    try
        shell = editor.document
        @test shell isa WidgetShell
        @test labels(shell.toolbar) == ["Explorer", "Assistant", "Evaluator", "Message log", "Gesture log",
                                        "Fault log", "Statistics", "Frame times", "Selection", "Appearance",
                                        "Settings"]
        @test shell.status_bar === nothing
    finally
        foreach(step -> step(editor), editor.stop_steps)
    end
    editor, _ = _ww_editor(PrimitiveString("x"); shell = true, gesture_log = true)
    @test labels(editor.document.toolbar) ==
          ["Explorer", "Evaluator", "Gesture log", "Selection", "Appearance", "Settings"]
end

@testset "shell: the Help menu offers the gesture help and the palette when their wrappers are on" begin
    editor, _ = _ww_editor(PrimitiveString("x"); shell = true)
    @test _ww_help_labels(editor.document) == ["Documents", "Projections", "About"]
    editor, _ = _ww_editor(PrimitiveString("x"); shell = true, gesture_help = true, command_palette = true)
    @test _ww_help_labels(editor.document) ==
          ["Gestures", "Command palette", "Documents", "Projections", "About"]
end

@testset "shell: Gestures in the Help menu does what F1 does, with panes and without" begin
    for tabs in (true, false)
        editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600),
                                     shell = true, gesture_help = true, tabs)
        screen = get_wrapped_document(editor.document)
        id = screen.windows[1].id
        tabs && (_ww_focus_first_tab!(editor); run_frame!(editor))
        selection = _ww_selection(editor)
        # F1 still reaches the wrapper through the shell.
        f1 = WindowInput(id, KeyDown(:f1, ModifierKeys(); time = 0.0))
        _ww_press!(editor, backend, f1)
        by_key = _ww_help_rows(screen)
        _ww_press!(editor, backend, f1)
        @test length(screen.windows) == 1
        # The menu opens the same help: the click leaves the selection where it
        # was, so the rows are the rows of the content.
        _ww_click_help_item!(editor, backend, screen, id, "Gestures", 1.0)
        @test length(screen.windows) == 2
        @test _ww_help_rows(screen) == by_key
        @test _ww_selection(editor) == selection
        _ww_click_help_item!(editor, backend, screen, id, "Gestures", 5.0)
        @test length(screen.windows) == 1
    end
end

@testset "shell: Command palette in the Help menu does what Ctrl+Shift+P does" begin
    editor, backend = _ww_editor(PrimitiveString("x"); shell = true, command_palette = true)
    closed = Set(_shell_texts(last(rendered_output(backend))))
    _ww_press!(editor, backend, _ww_ctrl(:p; shift = true))
    by_key = Set(_shell_texts(last(rendered_output(backend))))
    @test !issubset(by_key, closed)
    _ww_press!(editor, backend, _ww_ctrl(:p; shift = true))
    help = only(item for item in editor.document.menu_bar.elements if string(item.action.label) == "Help")
    item = only(item for item in help.submenu.elements if string(item.action.label) == "Command palette")
    evaluate_operation(editor, InvokeActionOperation(item.action))
    run_frame!(editor)
    @test Set(_shell_texts(last(rendered_output(backend)))) == by_key
    evaluate_operation(editor, InvokeActionOperation(item.action))
    run_frame!(editor)
    @test Set(_shell_texts(last(rendered_output(backend)))) == closed
end

end # @testset
end
