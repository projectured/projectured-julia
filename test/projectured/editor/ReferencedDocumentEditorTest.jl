# A referenced document in the application window: a tab found by its title, the
# data a file tab shows reached through the file and its history, and a read into
# that data that still knows where it is.

using Test

function _make_referenced_application(directory)
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}]")
    measure = measure_truetype_text
    document, projection = make_application_window([joinpath(directory, "people.json")];
                                                    root = directory, assistant = nothing,
                                                    measure = measure)
    editor = make_editor(document, projection, "ProjecturEd"; backend = HeadlessBackend(),
                         width = 1280, height = 720,
                         opened_window_projections = make_opened_window_projections(;
                             content = make_application_content_projections(measure = measure),
                             measure = measure))
    start_application!(editor, false, :none, "")
    run_frame!(editor)
    editor
end

function test_referenced_document_editor()
@testset "ReferencedDocument in the application" begin
    directory = mktempdir()
    editor = _make_referenced_application(directory)

    @testset "find_pane answers the tab and where it is" begin
        people_tab = find_pane(editor, "people.json")
        @test people_tab isa ReferencedDocument
        @test get_document(people_tab) isa PaneTab
        @test evaluate_reference(editor.document, get_reference(people_tab)) === get_document(people_tab)
        @test find_pane(editor, "no such tab") === nothing
    end

    @testset "get_edited_document reaches the data through the file and its history" begin
        people_tab = find_pane(editor, "people.json")
        people = get_edited_document(people_tab)
        @test people isa ReferencedDocument
        @test get_document(people) isa JsonArray
        @test evaluate_reference(editor.document, get_reference(people)) === get_document(people)
        # A document that is not referenced answers the document.
        @test get_edited_document(get_document(people_tab).content) === get_document(people)
        @test get_edited_document(get_document(people)) === get_document(people)
    end

    @testset "a read into the data keeps its reference" begin
        people = get_edited_document(find_pane(editor, "people.json"))
        first_person = people.elements[1]
        @test get_document(first_person) isa JsonObject
        @test evaluate_reference(editor.document, get_reference(first_person)) === get_document(first_person)
        @test [entry.key for entry in first_person.entries] == ["name", "age"]
    end

    @testset "a tab that shows a widget answers the widget" begin
        open_pane!(editor, WidgetLabel("hello"); title = "Hello")
        hello = get_edited_document(find_pane(editor, "Hello"))
        @test get_document(hello) isa WidgetLabel
    end
end
end # test_referenced_document_editor
