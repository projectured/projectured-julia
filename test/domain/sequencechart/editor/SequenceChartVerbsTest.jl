# The verbs of a sequence chart in an application window, as the assistant meets
# one: an insert and a delete of events, and a move and a removal of a lane, each
# one step of the undo.

using Test

# An application window with `document` in the tab `title`.
function _make_sequence_chart_verbs_application(document, title)
    window, projection = make_application_window(String[]; root = mktempdir(), assistant = nothing)
    editor = build_editor(window, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    open_pane!(document; title, editor)
    run_frame!(editor)
    editor
end

_undo_sequence_chart_verb!(editor) =
    (call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor); run_frame!(editor))

"""
    test_sequencechart_verbs()

`insert_events!`, `delete_events!`, `move_axis!` and `delete_axis!` change a
sequence chart of the window as an edit of the editor, which one undo takes
back, and refuse a lane that the chart does not have.
"""
function test_sequencechart_verbs()
@testset "the verbs of a sequence chart are edits of the editor" begin
    axes = Any[SequenceChartAxis("client"), SequenceChartAxis("server"), SequenceChartAxis("cache")]
    events = SequenceChartEvents([0.0, 1.0, 5.0], [1, 2, 3]; labels = ["send", "recv", "look"])
    arrows = SequenceChartArrows([1, 2], [2, 3]; labels = ["req", "lookup"])
    editor = _make_sequence_chart_verbs_application(SequenceChart("trace", axes; events, arrows), "Trace")
    part = get_edited_document(find_pane("Trace"; editor))
    chart() = get_document(part)

    @test insert_events!(part, 1; times = [-1.0], axes = [1], editor) === part
    @test get_event_count(chart().events) == 4
    @test get_arrow_count(chart().arrows) == 2
    _undo_sequence_chart_verb!(editor)
    @test get_event_count(chart().events) == 3

    # The arrow that ends at the deleted event goes with it.
    @test delete_events!(part, [3]; editor) === part
    @test get_event_count(chart().events) == 2
    @test get_arrow_count(chart().arrows) == 1
    _undo_sequence_chart_verb!(editor)
    @test get_event_count(chart().events) == 3
    @test get_arrow_count(chart().arrows) == 2

    @test move_axis!(part, 3, 1; editor) === part
    @test get_axis_display_order(chart()) == [3, 1, 2]
    _undo_sequence_chart_verb!(editor)
    @test get_axis_display_order(chart()) == [1, 2, 3]

    @test delete_axis!(part, 3; editor) === part
    @test length(chart().axes) == 2
    @test get_event_count(chart().events) == 2
    _undo_sequence_chart_verb!(editor)
    @test length(chart().axes) == 3

    @test_throws ArgumentError move_axis!(part, 1, 9; editor)
    @test_throws ArgumentError delete_axis!(part, 9; editor)
end
end
