"""
    test_workflow_document()

The documents of a workflow: what a new node holds, the tree that the example
builds, the time of an entry, and the helpers that read a node of any kind.
"""
function test_workflow_document()
    @testset "WorkflowDocument" begin
        @testset "a new step is open, empty and not collapsed" begin
            step = WorkflowStep()
            @test step.title isa PrimitiveString
            @test step.title.value == ""
            @test step.state === :open
            @test length(step.children) == 0
            @test length(step.journal) == 0
            @test length(step.cards) == 0
            @test step.collapsed === false
        end

        @testset "the example is a tree of steps, a decision and options" begin
            workflow = make_workflow_document_example()
            @test workflow isa WorkflowStep
            @test workflow.title.value == "Workflow domain"
            @test workflow.state === :active
            @test length(workflow.children) == 4
            decision = workflow.children[2]
            @test decision isa WorkflowDecision
            @test decision.question.value == "How to store a workflow"
            @test [option.state for option in decision.options] == [:rejected, :chosen, :parked]
            @test decision.options[1].reason.value ==
                  "Not diffable, and it breaks across Julia versions."
            @test decision.journal[1].author === :assistant
            @test decision.journal[1].kind === :decision
            @test workflow.children[3].cards[1] isa WorkflowCard
            @test workflow.children[3].cards[1].content.value ==
                  "A card holds a document of any domain."
        end

        @testset "a node of any kind gives its title and its children" begin
            workflow = make_workflow_document_example()
            decision = workflow.children[2]
            @test get_workflow_node_title(workflow) === workflow.title
            @test get_workflow_node_title(decision) === decision.question
            @test get_workflow_node_title(decision.options[2]) === decision.options[2].title
            @test get_workflow_node_children(workflow) === workflow.children
            @test get_workflow_node_children(decision) === decision.options
            @test all(is_workflow_node, (workflow, decision, decision.options[1]))
            @test !is_workflow_node(WorkflowEntry())
            @test !is_workflow_node(WorkflowCard())
            @test get_workflow_states(workflow) == WORKFLOW_STEP_STATES
            @test get_workflow_states(decision.options[1]) == WORKFLOW_OPTION_STATES
        end

        @testset "the time of an entry is a text that sorts in the order of time" begin
            @test format_workflow_time(Dates.DateTime(2026, 10, 9, 14, 2, 5)) == "2026-10-09T14:02:05"
            entry = WorkflowEntry(time = "2026-10-09T14:02:05")
            @test find_workflow_time(entry) == Dates.DateTime(2026, 10, 9, 14, 2, 5)
            @test find_workflow_time(WorkflowEntry()) === nothing
            @test find_workflow_time(WorkflowEntry(time = "yesterday")) === nothing
            now_text = get_workflow_time()
            @test occursin(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$", now_text)
            @test "2026-10-09T09:00:00" < "2026-10-09T14:02:05" < "2026-10-10T08:00:00"
        end
    end
end
