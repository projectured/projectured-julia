# Fragment of `ProjecturedPlatformTest` — a value shown in an editor that runs
# beside the caller, with a backend that has no window.

# A value that this test gives a document, as a package does for its own type.
struct DisplayProbeValue
    text::String
end
WidgetModule.make_value_document(value::DisplayProbeValue) = PrimitiveString(value.text)

# A value whose document counts the times that the display reads it again.
@document struct DisplayRefreshProbe <: Document
    count::Int = 0
end
struct DisplayRefreshedValue
    document::DisplayRefreshProbe
end
WidgetModule.make_value_document(value::DisplayRefreshedValue) = value.document
WidgetModule.refresh_document!(document::DisplayRefreshProbe) = (document.count += 1; nothing)

# A backend with no window and no input: its wait is a short sleep, so the loop
# turns and answers the calls that are posted to it.
struct _DisplayProbeBackend <: Backend end
BackendModule.initialize_backend!(::_DisplayProbeBackend) = nothing
BackendModule.wait_for_input(::_DisplayProbeBackend, devices, timeout_seconds) =
    (sleep(0.002); nothing)
BackendModule.take_from_devices!(::_DisplayProbeBackend, devices) = nothing
BackendModule.write_to_devices!(::_DisplayProbeBackend, devices, output) = nothing
BackendModule.quit_backend!(::_DisplayProbeBackend) = nothing

_display_session() = ProjecturedPlatform.DisplayModule._SESSION[]

_count_tabs(editor) = run_on_editor_task!(() -> sum(length(group.tabs) for group in
    get_pane_groups(get_window_tree(; editor))), editor)
_count_windows(editor) = run_on_editor_task!(() -> length(get_wrapped_document(editor.document).windows), editor)

"""
    test_editor_display()

`display_in_editor` starts an editor on a thread of its own, shows each value in
a tab of its own, or in a window of its own without tabs, shows a value that it
shows already where it is, and raises an error for a value that no package
gives a document.
"""
function test_editor_display()
    @testset "a value shown in an editor beside the caller" begin
        @testset "a value that no package gives a document is an error" begin
            @test_throws "No loaded package shows a value of type Int64" display_in_editor(
                42; backend = _DisplayProbeBackend())
        end

        @testset "with tabs, each value is a tab of one window" begin
            close_display_editor!()
            process_logger = Base.CoreLogging.global_logger()
            backend = _DisplayProbeBackend()
            first_value = DisplayProbeValue("a")
            try
                document = display_in_editor(first_value; backend)
                @test document isa PrimitiveString
                session = _display_session()
                editor = session.editor
                threads = [run_on_editor_task!(() -> Threads.threadid(), editor) for _ in 1:5]
                @test all(==(first(threads)), threads)
                others = [t for t in Threads.threadpooltids(:default) if t != Threads.threadid()]
                isempty(others) || @test first(threads) != Threads.threadid()
                # The loop logs a warning and drops an info line.
                logger = run_on_editor_task!(() -> Base.CoreLogging.current_logger(), editor)
                @test Base.CoreLogging.min_enabled_level(logger) == Base.CoreLogging.Warn
                @test _count_tabs(editor) == 1
                # The tabs have the features of a window: the clipboard around the
                # chrome, around the undo, around the tabs, and the full toolbar
                # but the assistant.
                content = run_on_editor_task!(() -> get_wrapped_document(editor.document).windows[1].content,
                                              editor)
                @test content isa ProjecturedPlatform.ClipboardModule.ClipboardSlice
                shell = content.content
                @test shell isa WidgetShell && shell.status_bar isa WidgetStatusBar
                @test shell.content isa ProjecturedPlatform.UndoModule.UndoBuffer
                @test shell.content.content isa PaneTree
                @test [string(item.action.label) for item in shell.toolbar.elements] ==
                      ["Explorer", "Evaluator", "Message log", "Gesture log", "Fault log", "Statistics",
                       "Frame times", "Selection", "Appearance", "Settings"]

                # The same value again: the same document, and no new tab.
                @test display_in_editor(first_value; backend) === document
                @test _count_tabs(editor) == 1

                # Another value with the same summary: a new tab with a number.
                second = display_in_editor(DisplayProbeValue("b"); backend)
                @test second !== document
                @test _count_tabs(editor) == 2
                @test string(summary(first_value), " (2)") in session.titles

                # The window closes, and its loop goes on with no window: the
                # next display ends that loop and starts a new editor.
                run_on_editor_task!(() -> deleteat!(get_wrapped_document(editor.document).windows, 1), editor)
                display_in_editor(first_value; backend)
                @test istaskdone(session.loop)
                @test _display_session() !== session
            finally
                close_display_editor!()
            end
            @test _display_session() === nothing
            # The window put back the logger that its message log replaced.
            @test Base.CoreLogging.global_logger() === process_logger
        end

        @testset "without tabs, each value has a window of its own" begin
            close_display_editor!()
            backend = _DisplayProbeBackend()
            try
                display_in_editor(DisplayProbeValue("a"); backend, tabs = false)
                editor = _display_session().editor
                @test _count_windows(editor) == 1
                # A window of one value has no chrome.
                @test !(run_on_editor_task!(() -> get_wrapped_document(editor.document).windows[1].content,
                                            editor) isa WidgetShell)
                second_value = DisplayProbeValue("b")
                second = display_in_editor(second_value; backend)
                @test _count_windows(editor) == 2
                @test run_on_editor_task!(() -> get_wrapped_document(editor.document).windows[2].content, editor) ===
                      second
                display_in_editor(second_value; backend)
                @test _count_windows(editor) == 2
            finally
                close_display_editor!()
            end
        end

        @testset "a refresh reads each shown value again, at a call and at an interval" begin
            close_display_editor!()
            probe = DisplayRefreshProbe()
            try
                display_in_editor(DisplayRefreshedValue(probe); backend = _DisplayProbeBackend(),
                                  refresh_every = 0.05)
                count = probe.count
                refresh_display_editor!()
                @test probe.count > count
                # The timer reads the value again, within a bounded wait.
                count = probe.count
                deadline = time() + 5.0
                while probe.count == count && time() < deadline
                    sleep(0.02)
                end
                @test probe.count > count
            finally
                close_display_editor!()
            end
            # No editor runs: nothing happens.
            @test refresh_display_editor!() === nothing
        end
    end
end
