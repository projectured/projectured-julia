"""
    test_workflow_file()

A workflow saved as a `.pred` file. Alone, it writes as its constructor and reads
back to the same text. In a project with a Markdown page and a JSON file, a card
that holds a paragraph of the page and a card that holds a record of the JSON
file write as markers into those files, and the load puts the same objects back
into the cards. A card that holds a document of a domain with a file format needs
a file of that format.
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
        @test loaded.children[3].cards[1].content.value == "A card holds a document of any domain."
    end

    @testset "a card into a page and a record saves as markers, and loads as the same objects" begin
        paragraph = MarkdownParagraph([MarkdownText("The design of the view.")])
        page = MarkdownRoot([MarkdownParagraph([MarkdownText("Notes")]), paragraph])
        record = JsonObject("port" => JsonNumber(5000))
        data = JsonObject("record" => record)
        workflow = WorkflowStep(
            title = PrimitiveString("Ship the view"),
            cards = [WorkflowCard(title = PrimitiveString("Design"), content = paragraph),
                     WorkflowCard(title = PrimitiveString("Settings"), content = record)])
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
        @test loaded_workflow.cards[1].content === loaded_page.elements[2]
        @test loaded_workflow.cards[2].content === loaded_data.entries[1].value

        stamp = mtime(joinpath(directory, "work.pred"))
        sleep(0.01)
        @test save_project!(loaded) === true
        @test mtime(joinpath(directory, "work.pred")) == stamp
    end

    @testset "a card of a domain with a file format needs a file of that format" begin
        # A `.pred` file writes a document that has no file format of its own, such
        # as a primitive. A JSON object belongs in a JSON file, so the save refuses
        # it and writes nothing.
        workflow = WorkflowStep(cards = [WorkflowCard(content = PrimitiveString("a note")),
                                         WorkflowCard(content = JsonObject("k" => JsonString("v")))])
        directory = mktempdir()
        project = FileProject(directory, Any[PredFile("work.pred", workflow)])
        @test (@test_logs (:error, r"JsonObject at cards\[2\]\.content") save_project!(project)) === false
        @test !isfile(joinpath(directory, "work.pred"))
        workflow.cards = Any[workflow.cards[1]]
        @test save_project!(project) === true
        loaded = get_file_content(load_project(directory, ["work.pred"]).files[1])
        @test loaded.cards[1].content.value == "a note"
    end
end
end
