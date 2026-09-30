# Fragment of `ProjecturedDataFramesTest` — a data frame shown through the seams:
# the display of a value makes its view, and the natural renderer draws it.

# A backend with no window and no input: its wait is a short sleep, so the loop
# turns and answers the calls that are posted to it.
struct _DisplayProbeBackend <: Backend end
BackendModule.initialize_backend!(::_DisplayProbeBackend) = nothing
BackendModule.wait_for_input(::_DisplayProbeBackend, devices, timeout_seconds) =
    (sleep(0.002); nothing)
BackendModule.read_from_devices(::_DisplayProbeBackend, devices) = nothing
BackendModule.write_to_devices(::_DisplayProbeBackend, devices, output) = nothing
BackendModule.quit_backend!(::_DisplayProbeBackend) = nothing

"""
    test_data_frame_display()

A data frame makes its view as the document of a value, the natural renderer
draws a `DataFrameView` through the seam, and the display of a value shows a
frame in an editor, once for one frame.
"""
function test_data_frame_display()
    @testset "a data frame shows as its view" begin
        frame = make_data_frame_example(rows = 3)
        @test make_value_document(frame) isa DataFrameView
        @test DataFrameView in collect_graphics_projection_types()
        close_display_editor!()
        try
            view = display_in_editor(frame; backend = _DisplayProbeBackend())
            @test view isa DataFrameView && view.frame === frame
            @test display_in_editor(frame; backend = _DisplayProbeBackend()) === view
        finally
            close_display_editor!()
        end
    end
end
