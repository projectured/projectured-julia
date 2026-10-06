# The whole editor saves to a `.pred` file and opens again from it: the same
# windows, panes and tabs. An open file tab — a `FileDocument` sitting in a
# pane's `content` — costs the save nothing extra, because the generic file cut
# already writes a `FileDocument` child as a `file("name")` reference and never
# a copy. A key must never reach the file, and a session's own log or gesture
# history is not something the next session should start with.

using Test

# `save_user_interface` reads the `document` field of an editor.
mutable struct _UiFileMockEditor; document::Any; end

function test_user_interface_file()
@testset "the editor saves to one file and opens back" begin

mktempdir() do dir
    log = GestureLog()
    record_gesture!(log, KeyDown(:t, ModifierKeys(ctrl = true); time = 0.0), DoNothingOperation())
    @test length(log.entries) == 1

    tree = PaneTree(PaneSplit(:vertical, [
        PaneGroup([PaneTab("empty", DocumentNothing()), PaneTab("gestures", log)]),
        PaneGroup([PaneTab("a.json", JsonFile("a.json", parse_json("{\"greeting\": \"hello\"}"))),
                   PaneTab("assistant", Assistant(api_key = "SECRETKEY"))]),
    ]))
    editor = _UiFileMockEditor(tree)
    path = joinpath(dir, "ui.pred")

    @testset "it saves" begin
        @test save_user_interface(path; editor) === true
        @test isfile(path)
        @test isfile(joinpath(dir, "a.json"))
    end

    text = read(path, String)

    @testset "the json file is a reference, not a copy" begin
        @test occursin("file(\"a.json\")", text)
        @test !occursin("greeting", text)
        @test occursin("hello", read(joinpath(dir, "a.json"), String))
    end

    @testset "no key reaches the file" begin
        @test !occursin("SECRETKEY", text)
    end

    @testset "it opens back to the same layout" begin
        loaded = load_user_interface(path)
        @test loaded isa PaneTree
        groups = get_pane_groups(loaded)
        @test length(groups) == 2
        @test length(groups[1].tabs) == 2
        @test length(groups[2].tabs) == 2
        @test get_pane_tab_title_string(groups[1].tabs[1]) == "empty"
        @test get_pane_tab_title_string(groups[1].tabs[2]) == "gestures"
        @test get_pane_tab_title_string(groups[2].tabs[1]) == "a.json"
        @test get_pane_tab_title_string(groups[2].tabs[2]) == "assistant"

        # The json tab's content is readable again — spliced back in from the
        # file the save wrote it to, not carried inline in `ui.pred`.
        json_back = groups[2].tabs[1].content
        @test json_back.entries[1].value.value == "hello"

        # Last session's gestures are not this one's: the log comes back empty.
        gestures_back = groups[1].tabs[2].content
        @test gestures_back isa GestureLog
        @test isempty(gestures_back.entries)

        # No key survived the round trip either.
        assistant_back = groups[2].tabs[2].content
        @test assistant_back isa Assistant
        @test assistant_back.api_key == ""
    end
end

end
end
