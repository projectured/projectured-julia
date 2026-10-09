"""
    test_workflow_assistant_api()

The workflow domain offers its documents and its verbs to the model of an
assistant. Code that a model writes, run as `execute_julia_code` runs it, records
a decision as the assistant, and an undo of the history that holds the workflow
takes it back as one step.
"""
function test_workflow_assistant_api()
    @testset "WorkflowAssistantApi" begin
        entries = [e for e in get_registered_assistant_api() if e isa Pair && first(e) === WorkflowModule]

        @testset "the domain offers its documents and its verbs" begin
            @test length(entries) == 1
            offered = collect(last(only(entries)))
            @test Set(offered) == Set(WORKFLOW_ASSISTANT_API)
            @test all(name -> isdefined(WorkflowModule, name), offered)
            set = declare_api!(ToolSet(), entries)
            @test occursin("record_workflow_decision!", search_api(set, "record_workflow_decision!"))
            @test occursin("add_workflow_entry!", search_api(set, "add_workflow_entry!"))
        end

        @testset "code of a model records a decision, and an undo takes it back" begin
            workflow = make_workflow_document_example()
            buffer = UndoBuffer(workflow)
            projection = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0),
                                           extra = Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()])
            editor = make_editor(buffer, projection; backend = HeadlessBackend())
            run_frame!(editor)
            set = declare_api!(ToolSet(), vcat(entries,
                Any[ReferenceModule => (:ReferencedDocument, :EmptyReference)]))
            answer = execute_julia_code!(set, editor, """
                workflow_1 = ReferencedDocument(editor.document, EmptyReference()).content
                tools_1 = workflow_1.children[4]
                decision_1 = record_workflow_decision!(tools_1, "Tools or verbs",
                    ["tools in the tool set", "verbs of the API"]; chosen = 2,
                    reason = "a domain offers its verbs with register_assistant_api!")
                reject_workflow_option!(decision_1, 1; reason = "no domain can add a tool")
                nothing
                """)
            @test answer == "Done."
            tools = workflow.children[4]
            @test length(tools.children) == 1
            decision = tools.children[1]
            @test decision isa WorkflowDecision
            @test decision.journal[1].author === :assistant
            @test [option.state for option in decision.options] == [:rejected, :chosen]
            @test decision.options[1].journal[end].author === :assistant
            @test length(buffer.undo_entries) == 2
            evaluate_operation(editor, UndoOperation(buffer))
            @test decision.options[1].state === :open
            evaluate_operation(editor, UndoOperation(buffer))
            @test length(tools.children) == 0
        end
    end
end
