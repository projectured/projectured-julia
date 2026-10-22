# The count of the parts of a workflow: each node, each entry and each element.
function _count_workflow_parts(node)
    count = 1 + length(node.journal) + length(node.elements)
    for child in get_workflow_node_children(node)
        count += _count_workflow_parts(child)
    end
    count
end

"""
    test_workflow_stage_examples()

The workflow "Ship the CSV importer" in its stages: each stage holds the feature
that it adds, and each one has more parts than the stage before it. Only the stage
of the journal shows the entries open.
"""
function test_workflow_stage_examples()
    @testset "WorkflowStageExamples" begin
        stages = [make_workflow_goal_document_example(), make_workflow_steps_document_example(),
                  make_workflow_substeps_document_example(), make_workflow_open_decision_document_example(),
                  make_workflow_explored_document_example(), make_workflow_recorded_document_example(),
                  make_workflow_elements_document_example()]
        goal, steps, substeps, decision, explored, recorded, elements = stages

        @testset "each stage adds to the stage before it" begin
            counts = [_count_workflow_parts(stage) for stage in stages]
            @test all(counts[i] < counts[i + 1] for i in 1:(length(counts) - 1))
            @test all(stage -> stage.title.value == "Ship the CSV importer", stages)
        end

        @testset "a goal, then steps, then sub-steps" begin
            @test goal.state === :open && length(goal.children) == 0
            @test [child.state for child in steps.children] == [:done, :active, :open, :open]
            @test length(steps.children[2].children) == 0
            @test [child.title.value for child in substeps.children[2].children] ==
                  ["Read the header", "Infer the column types", "Handle quoted fields"]
            @test length(substeps.children[4].children) == 2
        end

        @testset "an open decision, then the branches that were tried" begin
            question = decision.children[2].children[1]
            @test question isa WorkflowDecision
            @test all(option -> option.state === :open, question.options)
            settled = explored.children[2].children[1]
            @test [option.state for option in settled.options] == [:rejected, :chosen, :parked]
            @test all(option -> !isempty(option.reason.value), settled.options)
            @test settled.options[1].children[1].state === :done
            @test settled.options[2].children[1].state === :active
        end

        @testset "the journal records both authors in the order of time" begin
            @test isempty(collect_workflow_entries(explored))
            @test recorded.journal_shown && recorded.children[1].journal_shown
            @test !recorded.children[3].journal_shown
            entries = collect_workflow_entries(recorded)
            @test length(entries) == 6
            @test Set(last(pair).author for pair in entries) == Set([:person, :assistant])
            @test issorted([last(pair).time for pair in entries])
            @test length(collect_workflow_entries(recorded; kind = :decision)) == 1
        end

        @testset "elements keep a table and a note in view, and the journal folds again" begin
            @test elements.children[1].elements[1] isa WidgetTable
            @test elements.children[2].elements[1] isa TextBlock
            @test all(child -> length(child.elements) == 0, recorded.children)
            @test !elements.journal_shown && !elements.children[1].journal_shown
        end
    end
end
