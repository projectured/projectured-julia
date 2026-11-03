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

# The texts drawn in `node` and below it.
function _ww_drawn_texts(node, texts = String[])
    node = _cm_force(node)
    node === nothing && return texts
    hasproperty(node, :text) && push!(texts, String(_cm_force(node.text)))
    hasproperty(node, :elements) &&
        foreach(element -> _ww_drawn_texts(element, texts), _cm_force(node.elements))
    texts
end

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
    tab = KeyPress('\t'; time = 0.0)
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

@testset "command_palette: Ctrl+Shift+P opens the list of the commands in a window of its own" begin
    editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600),
                                 command_palette = true)
    screen = get_wrapped_document(editor.document)
    _ww_press!(editor, backend, WindowInput(screen.windows[1].id, _ww_ctrl(:p; shift = true)))
    lists = [window for window in screen.windows if window.content isa WidgetChoiceList]
    @test length(lists) == 1
    @test only(lists).content.prompt == "Command"
    @test only(lists).style === :popup
    @test is_window_placed(only(lists))
    # A bare Escape closes it, as every popup.
    _ww_press!(editor, backend, WindowInput(screen.windows[1].id, KeyDown(:escape, ModifierKeys(); time = 0.0)))
    @test !any(window -> window.content isa WidgetChoiceList, screen.windows)
end

@testset "gesture_log: an operation of the window is an entry of the gesture log" begin
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true, gesture_log = true)
    log = get_session_gesture_log(; editor)
    # `count` counts every entry recorded, also one that the bounded log dropped.
    recorded = log.count
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _ww_ctrl(:t))
    @test _ww_tabs(editor) == 2
    @test log.count > recorded
    @test last(log.entries).gesture == "Ctrl+T"
end

@testset "gesture_log: each editor records into a log of its own, or the one that its option gives" begin
    held = GestureLog()
    first_editor, first_backend = _ww_editor(PrimitiveString("x"); undo = true, gesture_log = true)
    second_editor, _ = _ww_editor(PrimitiveString("y"); undo = true, gesture_log = (; log = held))
    @test get_session_gesture_log(; editor = second_editor) === held
    first_log = get_session_gesture_log(; editor = first_editor)
    @test first_log !== held
    entries = length(first_log.entries)
    _ww_focus_first_tab!(first_editor)
    _ww_press!(first_editor, first_backend, _ww_ctrl(:t))
    @test length(first_log.entries) > entries
    @test isempty(held.entries)
end

@testset "gesture_log: with overlay, the newest gestures draw in a panel over the window" begin
    editor, backend = _ww_editor(PrimitiveString("x"); undo = true,
                                 gesture_log = (; overlay = true, lines = 3))
    log = get_session_gesture_log(; editor)
    @test "no gesture yet" in _shell_texts(last(rendered_output(backend)))
    recorded = log.count
    _ww_focus_first_tab!(editor)
    _ww_press!(editor, backend, _ww_ctrl(:t))
    # The log of the session of the editor records as before, and the panel draws
    # the gesture.
    @test log.count > recorded
    @test last(log.entries).gesture == "Ctrl+T"
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

@testset "fault_log: the log of the session of the editor on its fault store" begin
    editor, _ = _ww_editor(PrimitiveString("x"); fault_log = true)
    @test any(target -> target === get_session_fault_log(; editor), editor.faults.targets)
    @test get_session_fault_log(; editor) !== get_session_fault_log()
end

@testset "shell: a tool that shows what the window records is there when its wrapper is" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    recorded = (; message_log = true, gesture_log = true, fault_log = true, frame_statistics = true)
    editor, _ = _ww_editor(PrimitiveString("x"); shell = (; assistant = _ -> Assistant(),
                                                           status_bar = false), recorded...)
    try
        shell = editor.document
        @test shell isa WidgetShell
        @test labels(shell.toolbar) == ["Explorer", "Files", "Assistant", "Evaluator", "Message log", "Gesture log",
                                        "Fault log", "Frame statistics", "Frame times", "Selection", "Appearance",
                                        "Settings"]
        @test shell.status_bar === nothing
    finally
        foreach(step -> step(editor), editor.stop_steps)
    end
    editor, _ = _ww_editor(PrimitiveString("x"); shell = true, gesture_log = true)
    @test labels(editor.document.toolbar) ==
          ["Explorer", "Files", "Evaluator", "Gesture log", "Selection", "Appearance", "Settings"]
end

@testset "assistant_list: the Assistants button opens the list of the assistants of the tabs, and a stop unlinks it" begin
    labels(bar) = [String(string(item.action.label)) for item in bar.elements]
    one, two = Assistant(), Assistant()
    tree = PaneTree(PaneGroup([PaneTab("One", one), PaneTab("Notes", PrimitiveString("x")),
                               PaneTab("Two", two)]))
    editor, _ = _ww_editor(tree; shell = (; status_bar = false), assistant_list = true)
    list = get_session_assistant_list(; editor)
    try
        @test labels(editor.document.toolbar) ==
              ["Explorer", "Files", "Evaluator", "Selection", "Appearance", "Settings", "Assistants"]
        @test length(list.assistants) == 2
        @test list.assistants[1] === one && list.assistants[2] === two
        # A tool opens in the focused group. The button posts its pane edit, and
        # the drain applies what was posted.
        _ww_focus_first_tab!(editor)
        button = only(item for item in editor.document.toolbar.elements
                      if string(item.action.label) == "Assistants")
        evaluate_operation(editor, InvokeActionOperation(button.action))
        drain_operations!(editor)
        @test only(collect_pane_tab_contents(tree, AssistantList)) === list
    finally
        foreach(step -> step(editor), editor.stop_steps)
    end
    @test isempty(list.assistants) && list.opener === nothing
    editor, _ = _ww_editor(PrimitiveString("x"); shell = true)
    @test !("Assistants" in labels(editor.document.toolbar))
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

@testset "shell: the help window draws its rows through its own row, not the shell's row for any document" begin
    editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600),
                                 shell = true, gesture_help = true)
    screen = get_wrapped_document(editor.document)
    _ww_press!(editor, backend, WindowInput(screen.windows[1].id, KeyDown(:f1, ModifierKeys(); time = 0.0)))
    help = only(window for window in screen.windows if window.content isa GestureMap)
    texts = _ww_drawn_texts(_cm_drawn_window(editor, screen, help.id))
    @test any(description -> any(text -> occursin(description, text), texts), _ww_help_rows(screen))
    # The row for any document draws a row as a reflected value, by its type name.
    @test !any(==("GestureRow"), texts)
end

@testset "shell: Ctrl+P finds a file of the Explorer by its name and opens it; Ctrl+O opens the Open dialog" begin
    mktempdir() do root
        mkpath(joinpath(root, "source"))
        write(joinpath(root, "source", "alpha.json"), "{\"a\": 1}")
        write(joinpath(root, "notes.txt"), "x")
        editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600), shell = true)
        screen = get_wrapped_document(editor.document)
        id = screen.windows[1].id
        push!(get_session_explorer_content(; editor).entries, Workspace([WorkspaceFolder("work", root)]))
        tabs = _ww_tabs(editor)
        # The command posts the open of the list, and the loop applies a post; a
        # test that runs the frames applies it by hand.
        _ww_press!(editor, backend, WindowInput(id, _ww_ctrl(:p)))
        drain_operations!(editor)
        wait_for_cell!(get_session_workspace_file_list(; editor).files; editor)
        run_frame!(editor)
        list = only(window.content for window in screen.windows if window.content isa WidgetChoiceList)
        @test list.prompt == "Go to file"
        @test sort([choice.label for choice in list.find("")]) == ["alpha.json", "notes.txt"]
        for c in "alp"
            _ww_press!(editor, backend, WindowInput(id, KeyPress(c; time = 0.0)))
        end
        @test [choice.label for choice in list.find(list.query)] == ["alpha.json"]
        @test only(list.find(list.query)).note == "source"
        _ww_press!(editor, backend, WindowInput(id, KeyPress('\n'; time = 0.0)))
        drain_operations!(editor)
        run_frame!(editor)
        @test !any(window -> window.content isa WidgetChoiceList, screen.windows)
        @test _ww_tabs(editor) == tabs + 1
        # The open file comes first in the list of the next search.
        _ww_press!(editor, backend, WindowInput(id, _ww_ctrl(:p)))
        drain_operations!(editor)
        run_frame!(editor)
        list = only(window.content for window in screen.windows if window.content isa WidgetChoiceList)
        @test first(list.find("")).label == "alpha.json"
        _ww_press!(editor, backend, WindowInput(id, KeyDown(:escape, ModifierKeys(); time = 0.0)))
        _ww_press!(editor, backend, WindowInput(id, _ww_ctrl(:o)))
        @test any(window -> window.id === :file_dialog, screen.windows)
    end
end

@testset "shell: Command palette in the Help menu does what Ctrl+Shift+P does" begin
    editor, backend = _ww_editor(PrimitiveString("x"); window = (; width = 800, height = 600),
                                 shell = true, command_palette = true)
    screen = get_wrapped_document(editor.document)
    id = screen.windows[1].id
    list_window() = only(window for window in screen.windows if window.content isa WidgetChoiceList)
    _ww_press!(editor, backend, WindowInput(id, _ww_ctrl(:p; shift = true)))
    by_key = [choice.label for choice in list_window().content.find("")]
    @test !isempty(by_key)
    _ww_press!(editor, backend, WindowInput(id, KeyDown(:escape, ModifierKeys(); time = 0.0)))
    @test !any(window -> window.content isa WidgetChoiceList, screen.windows)
    # The menu opens the same list, below the bands of the window.
    _ww_click_help_item!(editor, backend, screen, id, "Command palette", 1.0)
    drain_operations!(editor)
    run_frame!(editor)
    @test [choice.label for choice in list_window().content.find("")] == by_key
    @test is_window_placed(list_window())
    # It stands 8 below the toolbar of the shell, 480 wide, in the middle of the
    # window of 800.
    popup = _cm_output_window(editor, screen, :widget_popup)
    main = _cm_output_window(editor, screen, id)
    toolbar = find_part_place(editor.projection, editor.iomap,
                              extend_reference(ProjecturedPlatform.ShellModule._find_shell_reference(editor.document),
                                               FieldReferenceStep("toolbar")))
    @test popup.y == toolbar[2] + 8
    @test popup.maximum_size[1] == 480
    @test popup.x == Int(main.x) + (800 - 480) ÷ 2
end

end # @testset
end
