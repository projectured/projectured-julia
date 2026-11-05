# The verb of a table of a data frame in an application window, as the assistant
# meets one: a jump to a row, which moves the view and changes no data.

using Test

# An application window with `document` in the tab `title`.
function _make_data_frame_verbs_application(document, title)
    window, projection = make_application_window(String[]; root = mktempdir(), assistant = nothing)
    editor = build_editor(window, projection; backend = _ColumnWidthBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    open_pane!(document; title, editor)
    run_frame!(editor)
    editor
end

"""
    test_data_frame_verbs()

`jump_to_row!` shows a row of a table of the window at its top, and changes no
data.
"""
function test_data_frame_verbs()
@testset "the verb of a table of a data frame moves its view" begin
    frame = DataFrame(id = 101:600, price = collect(1.0:500.0))
    editor = _make_data_frame_verbs_application(DataFrameView(frame), "Prices")
    part = get_edited_document(find_pane("Prices"; editor))
    @test jump_to_row!(part, 120; editor) === part
    @test get_document(part).anchor == 120
    @test jump_to_row!(part, 9999; editor) === part
    @test get_document(part).anchor == 500
    @test frame[1, :id] == 101
end
end
