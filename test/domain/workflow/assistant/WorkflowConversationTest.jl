"""
    test_workflow_conversation()

A workflow and a conversation link either way. An entry of a workflow keeps the
turn of a conversation that it comes from, and an assistant keeps the workflow
that it records its work in. A `.pred` file keeps both links, and in a project the
file of the assistant names the file of the workflow.
"""
function test_workflow_conversation()
    @testset "WorkflowConversation" begin
        @testset "a tab of a workflow is named by its goal" begin
            workflow = make_workflow_document_example()
            @test get_document_title(workflow) == "Workflow domain"
            @test get_document_title(workflow.children[2]) == "How to store a workflow"
            @test get_document_title(make_workflow_journal_document_example()) == "Journal of Workflow domain"
        end

        @testset "an assistant keeps its workflow in its file" begin
            workflow = make_workflow_document_example()
            assistant = Assistant(workflow = workflow)
            @test assistant.workflow === workflow
            text = print_pred_text(assistant)
            @test occursin("workflow = WorkflowStep(", text)
            loaded = parse_pred_text(text)
            @test loaded isa Assistant
            @test loaded.workflow isa WorkflowStep
            @test loaded.workflow.title.value == "Workflow domain"
            @test !occursin("workflow", print_pred_text(Assistant()))
        end

        @testset "in a project the assistant names the file of the workflow, and an entry keeps its turn" begin
            turn = ConversationTurn(:assistant, [ConversationPart(PrimitiveString("Offer verbs, not tools."))])
            workflow = make_workflow_document_example()
            push!(workflow.journal, make_workflow_entry("Decided with the assistant."; author = :assistant,
                                                        kind = :decision, source = turn,
                                                        time = "2026-10-09T17:00:00"))
            assistant = Assistant(workflow = workflow)
            directory = mktempdir()
            project = FileProject(directory, Any[PredFile("work.pred", workflow),
                                                 PredFile("assistant.pred", assistant)])
            @test save_project!(project) === true
            @test occursin("file(\"work.pred\")", read(joinpath(directory, "assistant.pred"), String))
            loaded = load_project(directory, ["work.pred", "assistant.pred"])
            loaded_workflow = get_file_content(loaded.files[1])
            loaded_assistant = get_file_content(loaded.files[2])
            @test loaded_assistant.workflow === loaded_workflow
            source = loaded_workflow.journal[end].source
            @test source isa ConversationTurn
            @test source.role === :assistant
        end
    end
end
