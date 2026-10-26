# The object that the verbs evaluate an operation against: a workflow that no
# view shows, so each verb evaluates its operation directly.
mutable struct _WorkflowTestEditor
    document::Any
end

# The conversation of a test window is the group with a tab of this title.
const _WORKFLOW_CONVERSATION_TITLE = "Test conversation"

function ProjecturedPlatform.PaneModule.pane_group_to_avoid(tree::PaneTree)
    index = findfirst(group -> any(tab -> tab.title.name.value == _WORKFLOW_CONVERSATION_TITLE, group.tabs),
                      get_pane_groups(tree))
    index === nothing ? nothing : get_pane_groups(tree)[index]
end

const _WORKFLOW_TEST_TIME = "2026-10-09T15:00:00"

"""
    test_workflow_edits()

The edits of a workflow: each operation, the way back through a history, and the
verbs of the assistant.
"""
function test_workflow_edits()
    @testset "WorkflowEdits" begin
        @testset "a change of state writes the state and a :state entry" begin
            step = WorkflowStep(title = PrimitiveString("Write the tests"))
            operation = make_workflow_state_operation(step, :done; author = :assistant,
                                                      time = _WORKFLOW_TEST_TIME)
            evaluate_operation(nothing, operation)
            @test step.state === :done
            @test length(step.journal) == 1
            entry = step.journal[1]
            @test entry.kind === :state
            @test entry.author === :assistant
            @test entry.time == _WORKFLOW_TEST_TIME
            @test entry.text.value == "done"
            @test_throws ArgumentError make_workflow_state_operation(step, :chosen)
            @test_throws ArgumentError make_workflow_state_operation(WorkflowOption(), :done)
        end

        @testset "a history takes a change of state back as one step" begin
            step = WorkflowStep(title = PrimitiveString("Goal"))
            buffer = UndoBuffer(step)
            projection = UndoBufferToAnyProjection()
            iomap = print_document(projection, IdentityProjection(), buffer, PrinterContext())
            editor = _WorkflowTestEditor(buffer)
            operation = read_intent(projection, iomap,
                                    make_workflow_state_operation(step, :active; time = _WORKFLOW_TEST_TIME))
            @test operation isa RecordUndoOperation
            evaluate_operation(editor, operation)
            @test step.state === :active
            @test length(step.journal) == 1
            evaluate_operation(editor, UndoOperation(buffer))
            @test step.state === :open
            @test length(step.journal) == 0
            evaluate_operation(editor, RedoOperation(buffer))
            @test step.state === :active
            @test length(step.journal) == 1
        end

        @testset "the next state goes around the states" begin
            @test get_next_workflow_state(WorkflowStep()) === :active
            @test get_next_workflow_state(WorkflowStep(state = :dropped)) === :open
            @test get_next_workflow_state(WorkflowOption(state = :chosen)) === :rejected
        end

        @testset "a node goes only where its kind belongs" begin
            step = WorkflowStep()
            evaluate_operation(nothing, make_insert_workflow_node_operation(step, 1, WorkflowStep(title = PrimitiveString("b"))))
            evaluate_operation(nothing, make_insert_workflow_node_operation(step, 1, WorkflowStep(title = PrimitiveString("a"))))
            evaluate_operation(nothing, make_insert_workflow_node_operation(step, 3, WorkflowDecision()))
            @test [child isa WorkflowStep ? child.title.value : "?" for child in step.children] == ["a", "b", "?"]
            decision = step.children[3]
            evaluate_operation(nothing, make_insert_workflow_node_operation(decision, 1, WorkflowOption()))
            @test length(decision.options) == 1
            @test_throws ArgumentError make_insert_workflow_node_operation(decision, 1, WorkflowStep())
            @test_throws ArgumentError make_insert_workflow_node_operation(step, 1, WorkflowOption())
            @test_throws ArgumentError make_insert_workflow_node_operation(step, 1, WorkflowEntry())
            evaluate_operation(nothing, make_delete_workflow_node_operation(step, 1))
            @test [child isa WorkflowStep ? child.title.value : "?" for child in step.children] == ["b", "?"]
        end

        @testset "an element is added and removed" begin
            step = WorkflowStep()
            element = PrimitiveString("text")
            evaluate_operation(nothing, make_add_element_operation(step, element))
            @test length(step.elements) == 1
            @test step.elements[1] === element
            evaluate_operation(nothing, make_remove_element_operation(step, 1))
            @test length(step.elements) == 0
        end

        @testset "a decision with a chosen option records the choice" begin
            decision = make_workflow_decision("Which format", ["binary", "text"]; chosen = 2,
                                              reason = "it diffs", author = :assistant,
                                              time = _WORKFLOW_TEST_TIME)
            @test decision.question.value == "Which format"
            @test [option.state for option in decision.options] == [:open, :chosen]
            @test decision.options[2].reason.value == "it diffs"
            @test length(decision.journal) == 1
            @test decision.journal[1].kind === :decision
            @test decision.journal[1].author === :assistant
            @test decision.journal[1].text.value == "Chose text: it diffs"
            @test length(make_workflow_decision("Open", ["a", "b"]).journal) == 0
            @test_throws ArgumentError make_workflow_decision("Q", ["a"]; chosen = 2)
        end

        @testset "to choose an option writes its state, its reason and an entry" begin
            decision = make_workflow_decision("Which format", ["binary", "text"])
            evaluate_operation(nothing, make_choose_workflow_option_operation(decision, 1;
                                                                              reason = "it is fast"))
            @test decision.options[1].state === :chosen
            @test decision.options[1].reason.value == "it is fast"
            @test decision.options[2].state === :open
            @test decision.journal[end].text.value == "Chose binary: it is fast"
        end

        @testset "a new choice opens the option chosen before, and no reason keeps the reason" begin
            decision = make_workflow_decision("Which format", ["binary", "text"]; chosen = 1, reason = "fast")
            evaluate_operation(nothing, make_choose_workflow_option_operation(decision, 2))
            @test [option.state for option in decision.options] == [:open, :chosen]
            @test decision.options[1].reason.value == "fast"
            @test decision.journal[end].text.value == "Chose text."
            @test_throws ArgumentError make_workflow_state_operation(decision, :done)
            editor = _WorkflowTestEditor(decision)
            reject_workflow_option!(decision, 1; editor)
            @test decision.options[1].state === :rejected
            @test decision.options[1].reason.value == "fast"
        end

        @testset "the text of an entry that is a document is found by its words" begin
            step = WorkflowStep(journal = [make_workflow_entry(TextBlock(TextLine(TextString("a rich finding"))))])
            @test length(collect_workflow_entries(step; text = "RICH")) == 1
        end

        @testset "an entry says a string or a document, and checks its author and kind" begin
            entry = make_workflow_entry("a fact"; time = _WORKFLOW_TEST_TIME)
            @test entry.text isa PrimitiveString
            @test entry.text.value == "a fact"
            @test entry.author === :person
            @test entry.kind === :comment
            text = TextBlock(TextLine(TextString("rich")))
            @test make_workflow_entry(text).text === text
            @test_throws ArgumentError make_workflow_entry("x"; author = :robot)
            @test_throws ArgumentError make_workflow_entry("x"; kind = :rumour)
        end

        @testset "the verbs of the assistant write entries by the assistant" begin
            workflow = make_workflow_document_example()
            editor = _WorkflowTestEditor(workflow)
            decision = record_workflow_decision!(workflow, "Where the view lives",
                                                 ["a widget view", "a syntax view"];
                                                 chosen = 1, reason = "it mixes any views",
                                                 editor)
            @test decision === workflow.children[end]
            @test decision.journal[1].author === :assistant
            @test decision.options[1].state === :chosen
            reject_workflow_option!(decision, 2; reason = "it can not hold a widget", editor)
            @test decision.options[2].state === :rejected
            @test decision.options[2].reason.value == "it can not hold a widget"
            @test decision.options[2].journal[end].author === :assistant
            step = add_workflow_step!(workflow, "Write the view"; editor)
            @test step isa WorkflowStep
            @test step.title.value == "Write the view"
            change_workflow_state!(step, :active; editor)
            @test step.state === :active
            add_workflow_entry!(step, "The view embeds an element through the renderer."; editor)
            @test step.journal[end].kind === :comment
            @test step.journal[end].author === :assistant
            add_element!(step, PrimitiveString("a note"); editor)
            @test step.elements[end].value == "a note"
        end

        @testset "a workflow that the assistant starts opens with its steps and joins the explorer" begin
            editor = Editor(PaneTree(PaneGroup(PaneTab[PaneTab("start", PrimitiveString("x"))])),
                            NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                            backend = HeadlessBackend(), devices = Device[])
            plan = run_with_evaluation_editor(editor) do
                start_workflow!("A study of the Aloha sample"; steps = ["Read the model", "Run the sweep"])
            end
            root = get_document(plan)
            @test root isa WorkflowStep && root.state === :active
            @test root.title.value == "A study of the Aloha sample"
            @test [child.title.value for child in root.children] == ["Read the model", "Run the sweep"]
            @test all(child -> child.state === :open, root.children)
            entries = get_session_explorer_content(; editor).entries
            @test any(entry -> get_document(entry) === root, entries)
            @test find_pane("A study of the Aloha sample"; editor) !== nothing
            @test :start_workflow! in WORKFLOW_ASSISTANT_API
        end

        @testset "a workflow opens above the conversation, and a second joins it" begin
            conversation = PaneGroup(PaneTab[PaneTab(_WORKFLOW_CONVERSATION_TITLE, PrimitiveString("talk"))])
            files = PaneGroup(PaneTab[PaneTab("files", PrimitiveString("f"))])
            tree = PaneTree(PaneSplit(:vertical, Any[files, conversation]; weights = [0.5, 0.5]))
            editor = Editor(tree, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                            backend = HeadlessBackend(), devices = Device[])
            run_with_evaluation_editor(editor) do
                start_workflow!("First plan"; steps = ["a"])
            end
            column = tree.root.elements[2]
            @test column isa PaneSplit && column.orientation === :horizontal
            @test column.elements[2] === conversation
            @test column.elements[1].tabs[1].content isa WorkflowStep
            @test get_pane_normalized_weights(get_pane_weights(column)) ≈ [1 / 3, 2 / 3]
            run_with_evaluation_editor(editor) do
                start_workflow!("Second plan")
            end
            column = tree.root.elements[2]
            @test length(column.elements) == 2 && column.elements[2] === conversation
            @test length(column.elements[1].tabs) == 2
        end

        @testset "a verb answers a node as a referenced document when it gets one" begin
            workflow = make_workflow_document_example()
            editor = _WorkflowTestEditor(workflow)
            node = ReferencedDocument(workflow, EmptyReference())
            step = add_workflow_step!(node, "Referenced"; editor)
            @test step isa ReferencedDocument
            @test get_document(step) === workflow.children[end]
            @test get_document(step).title.value == "Referenced"
        end

        @testset "the entries of a tree are collected in the order of time" begin
            workflow = make_workflow_document_example()
            all = collect_workflow_entries(workflow)
            @test [last(pair).time for pair in all] ==
                  ["2026-10-09T13:00:00", "2026-10-09T13:40:00", "2026-10-09T14:02:00"]
            @test first(all[3]) === workflow.children[2]
            @test length(collect_workflow_entries(workflow; author = :assistant)) == 1
            @test length(collect_workflow_entries(workflow; kind = :comment)) == 1
            @test length(collect_workflow_entries(workflow; text = "PRED")) == 1
            @test isempty(collect_workflow_entries(workflow; text = "nowhere"))
        end
    end
end
