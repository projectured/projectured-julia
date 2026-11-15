"""
    test_workflow_file()

A workflow saved as a `.pred` file. Alone, it writes as its constructor and reads
back to the same text. In a project with a Markdown page and a JSON file, an
element that is a paragraph of the page and an element that is a record of the
JSON file write as markers into those files, and the load puts the same objects
back into the elements. An element of a format that no file of the set writes is
written in the text of its format.
"""
function test_workflow_file()
@testset "Workflow file" begin

    @testset "a workflow alone writes as its constructor and reads back" begin
        workflow = make_workflow_document_example()
        text = print_pred_text(workflow)
        @test startswith(text, "WorkflowStep(")
        @test occursin("time = \"2026-10-09T14:02:00\"", text)
        @test occursin("state = :rejected", text)
        loaded = parse_pred_text(text)
        @test loaded isa WorkflowStep
        @test print_pred_text(loaded) == text
        decision = loaded.children[2]
        @test decision isa WorkflowDecision
        @test decision.options[1].reason.value == "Not diffable, and it breaks across Julia versions."
        @test decision.journal[1].author === :assistant
        @test loaded.children[3].elements[1].value == "A node holds a document of any domain as an element."
    end

    @testset "an element in a page and a record saves as markers, and loads as the same objects" begin
        paragraph = MarkdownParagraph([MarkdownText("The design of the view.")])
        page = MarkdownRoot([MarkdownParagraph([MarkdownText("Notes")]), paragraph])
        record = JsonObject("port" => JsonNumber(5000))
        data = JsonObject("record" => record)
        workflow = WorkflowStep(
            title = PrimitiveString("Ship the view"),
            elements = Any[paragraph, record])
        directory = mktempdir()
        project = FileProject(directory, Any[PredFile("work.pred", workflow),
                                             MarkdownFile("page.md", page),
                                             JsonFile("data.json", data)])
        @test save_project!(project) === true
        text = read(joinpath(directory, "work.pred"), String)
        @test occursin("node(file(\"page.md\")", text)
        @test occursin("node(file(\"data.json\")", text)
        @test !occursin("The design of the view.", text)
        @test occursin("The design of the view.", read(joinpath(directory, "page.md"), String))

        loaded = load_project(directory, ["work.pred", "page.md", "data.json"])
        loaded_workflow = get_file_content(loaded.files[1])
        loaded_page = get_file_content(loaded.files[2])
        loaded_data = get_file_content(loaded.files[3])
        @test loaded_workflow isa WorkflowStep
        @test loaded_workflow.elements[1] === loaded_page.elements[2]
        @test loaded_workflow.elements[2] === loaded_data.entries[1].value

        stamp = mtime(joinpath(directory, "work.pred"))
        sleep(0.01)
        @test save_project!(loaded) === true
        @test mtime(joinpath(directory, "work.pred")) == stamp
    end

    @testset "an element of a format that no file writes saves in the text of its format" begin
        # A `.pred` file writes a document that has no file format of its own, such
        # as a primitive, as its constructor. A JSON object and a Markdown page that
        # no file of the set writes are written as the text of their format, and the
        # load reads them with it. One that the workflow holds at two places is one
        # object again.
        record = JsonObject("port" => JsonNumber(5000), "name" => JsonString("say \"hi\""))
        page = MarkdownRoot([MarkdownParagraph([MarkdownText("The design of the view.")])])
        workflow = WorkflowStep(elements = Any[PrimitiveString("a note"), record, page],
                                children = Any[WorkflowStep(elements = Any[record])])
        directory = mktempdir()
        @test save_file!(PredFile("work.pred", workflow), directory)
        text = read(joinpath(directory, "work.pred"), String)
        @test occursin("json\"\"\"", text)
        @test occursin("md\"\"\"", text)
        @test occursin("The design of the view.", text)
        # The record is written once, where the walk meets it first, and a marker
        # into the file stands at the other place.
        @test count("5000", text) == 1
        @test occursin("node(file(\"work.pred\"), ", text)
        loaded = get_file_content(load_file(directory, "work.pred"))
        @test loaded.elements[1].value == "a note"
        @test loaded.elements[2] isa JsonObject
        @test loaded.elements[2].entries[1].value.value == 5000
        @test loaded.elements[2].entries[2].value.value == "say \"hi\""
        @test loaded.elements[3] isa MarkdownRoot
        @test loaded.children[1].elements[1] === loaded.elements[2]
        stamp = mtime(joinpath(directory, "work.pred"))
        sleep(0.01)
        @test save_file!(PredFile("work.pred", loaded), directory)
        @test mtime(joinpath(directory, "work.pred")) == stamp
    end
end
end
