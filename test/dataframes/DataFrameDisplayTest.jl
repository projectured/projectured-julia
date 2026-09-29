# Fragment of `ProjecturedDataFramesTest` — a data frame shown in an editor that
# runs beside the caller, with a backend that has no window.

# A backend with no window and no input: its wait is a short sleep, so the loop
# turns and answers the calls that are posted to it.
struct _DisplayProbeBackend <: Backend
    writes::Threads.Atomic{Int}
end
_DisplayProbeBackend() = _DisplayProbeBackend(Threads.Atomic{Int}(0))
BackendModule.initialize_backend!(::_DisplayProbeBackend) = nothing
BackendModule.wait_for_input(::_DisplayProbeBackend, devices, timeout_seconds) =
    (sleep(0.002); nothing)
BackendModule.read_from_devices(::_DisplayProbeBackend, devices) = nothing
BackendModule.write_to_devices(backend::_DisplayProbeBackend, devices, output) =
    (Threads.atomic_add!(backend.writes, 1); nothing)
BackendModule.quit_backend!(::_DisplayProbeBackend) = nothing

_display_session() = ProjecturedDataFrames.DataFramesModule._SESSION[]

"""
    test_data_frame_display()

`display_in_editor` starts an editor on a thread of its own, pinned to it, shows
each frame in a tab of its own, and shows a frame that has a tab in that tab.
The pinning call is internal to Julia, so its test fails when a release changes
it.
"""
function test_data_frame_display()
    @testset "a data frame shown in an editor beside the caller" begin
        @testset "a pinned task stays on its thread" begin
            thread = last(Threads.threadpooltids(:default))
            seen = Int[]
            task = ProjecturedDataFrames.DataFramesModule._spawn_pinned(thread) do
                for _ in 1:50
                    push!(seen, Threads.threadid())
                    yield()
                end
            end
            wait(task)
            @test task.sticky
            @test all(==(thread), seen)
        end

        close_data_frame_editor!()
        backend = _DisplayProbeBackend()
        first_frame = make_data_frame_example(rows = 3)
        try
            view = display_in_editor(first_frame; backend)
            @test view isa DataFrameView
            @test view.frame === first_frame
            session = _display_session()
            @test session !== nothing
            editor = session.editor
            threads = [run_on_editor_task!(() -> Threads.threadid(), editor) for _ in 1:5]
            @test all(==(first(threads)), threads)
            other_threads = [t for t in Threads.threadpooltids(:default) if t != Threads.threadid()]
            isempty(other_threads) || @test first(threads) != Threads.threadid()

            title = summary(first_frame)
            has_tab(name) = run_on_editor_task!(() -> find_pane(editor, name) !== nothing, editor)
            @test has_tab(title)

            # The same frame again: the same view, and no new tab.
            @test display_in_editor(first_frame; backend) === view
            @test !has_tab(string(title, " (2)"))

            # Another frame with the same summary: a new tab with a number.
            second_view = display_in_editor(make_data_frame_example(rows = 3); backend)
            @test second_view !== view
            @test has_tab(string(title, " (2)"))
            @test _display_session() === session

            # The window closes, as `WindowManagingProjection` closes it, and its
            # loop goes on with no window: the next display ends that loop and
            # starts a new editor.
            run_on_editor_task!(() -> deleteat!(editor.document.windows, 1), editor)
            display_in_editor(first_frame; backend)
            @test istaskdone(session.loop)
            @test _display_session() !== session
            @test _display_session() !== nothing
        finally
            close_data_frame_editor!()
        end
        @test _display_session() === nothing
    end
end
