# The verbs of a chart in an application window, as the assistant meets a chart:
# a move and a removal of a series, each one step of the undo.

using Test

# An application window with `document` in the tab `title`.
function _make_chart_verbs_application(document, title)
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

_undo_chart_verb!(editor) =
    (call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor); run_frame!(editor))

"""
    test_chart_verbs()

`move_series!` and `remove_series!` change a chart of the window as an edit of
the editor, which one undo takes back, and refuse a place outside the list.
"""
function test_chart_verbs()
@testset "the verbs of a chart are edits of the editor" begin
    chart = Chart("Sales", Any[ChartLineSeries("a", 1:3, [1.0, 2.0, 3.0]),
                               ChartLineSeries("b", 1:3, [3.0, 2.0, 1.0]),
                               ChartLineSeries("c", 1:3, [2.0, 2.0, 2.0])])
    editor = _make_chart_verbs_application(chart, "Sales")
    part = get_edited_document(find_pane("Sales"; editor))
    labels() = [series.label for series in get_document(part).series]
    @test labels() == ["a", "b", "c"]
    @test move_series!(part, 3, 1; editor) === part
    @test labels() == ["c", "a", "b"]
    _undo_chart_verb!(editor)
    @test labels() == ["a", "b", "c"]
    @test remove_series!(part, 2; editor) === part
    @test labels() == ["a", "c"]
    _undo_chart_verb!(editor)
    @test labels() == ["a", "b", "c"]
    @test startswith(repr(make_change(move_series!, part, 1, 2; editor)), "a change: Move the series 1")
    @test labels() == ["a", "b", "c"]
    @test_throws ArgumentError move_series!(part, 1, 4; editor)
    @test_throws ArgumentError remove_series!(part, 4; editor)
end
end
