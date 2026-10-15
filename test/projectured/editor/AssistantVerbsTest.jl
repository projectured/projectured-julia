# The verbs that the assistant of a window shares with every other window, in the
# application: what the person selected and points at, what changed, the logs and
# the text of any part.

using Test

function _make_assistant_verbs_application(directory)
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}]")
    write(joinpath(directory, "notes.md"), "# Notes\n\nThe first line.\n")
    paths = [joinpath(directory, "people.json"), joinpath(directory, "notes.md")]
    document, projection = make_application_window(paths; root = directory, assistant = nothing)
    editor = build_editor(document, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    editor
end

# What `execute_julia_code` answers for `code` in the window of `editor`.
_run_assistant_code(editor, code) = execute_julia_code!(editor.tools, editor, code)

function test_assistant_verbs()
@testset "the verbs of the assistant of every window" begin
    directory = mktempdir()
    editor = _make_assistant_verbs_application(directory)
    people = get_edited_document(find_pane("people.json"; editor))
    ada_name = people[2]["name"]

    @testset "read: the part that the person selected, and its tab" begin
        evaluate_operation(editor, ReplaceSelectionOperation(get_reference(ada_name)))
        run_frame!(editor)
        part = find_selected_part(; editor)
        @test part isa ReferencedDocument
        @test get_document(part) === get_document(ada_name)
        @test print_natural_text(part) == "\"Ada\""
        tab = find_focused_pane(; editor)
        @test get_pane_tab_title_string(get_document(tab)) == "people.json"
        @test occursin("Ada", _run_assistant_code(editor, "print_natural_text(find_selected_part())"))
    end

    @testset "read: the part under the pointer" begin
        cleo_age = people[1]["age"]
        evaluate_operation(editor, ReplaceMouseTargetOperation(get_reference(cleo_age)))
        part = find_part_under_pointer(; editor)
        @test part isa ReferencedDocument
        @test get_document(part) === get_document(cleo_age)
    end

    @testset "read: what changed last" begin
        @test occursin("Nothing to take back", string(describe_undo_history(; editor)))
        replace_referenced_value!(people[1]["age"], parse_natural_text(:json, "30"); editor)
        run_frame!(editor)
        history = string(describe_undo_history(; editor))
        @test startswith(history, "To take back, newest last:")
        @test length(split(history, '\n')) == 2
        @test occursin("To take back", _run_assistant_code(editor, "describe_undo_history()"))
    end

    @testset "read: the logs of the session print as text" begin
        for log in (get_session_gesture_log(; editor), get_session_message_log(; editor),
                    get_session_fault_log(; editor))
            @test print_natural_text(log) isa String
        end
    end

    @testset "read: a part with no text of its own prints as its constructor" begin
        @test startswith(print_pred_text(WidgetLabel("hello")), "WidgetLabel(")
        @test startswith(print_pred_text(people[1]), "JsonObject(")
    end

    @testset "read: the formats that a model writes a document in" begin
        formats = string(describe_natural_formats())
        @test occursin(":json", formats) && occursin(":md", formats)
        @test occursin(":json", _run_assistant_code(editor, "describe_natural_formats()"))
    end
end
end
