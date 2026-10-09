# An editor that shows `document` through the renderer of any document, with a font
# of fixed size, so the places of the parts are the same on every machine.
function _make_workflow_view_editor(document)
    projection = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0))
    editor = make_editor(document, projection; backend = HeadlessBackend())
    run_frame!(editor)
    editor
end

# The first click on the view, in reading order, whose answer `accept` takes, as
# `(x, y, operation)`, or `nothing`. It reads the IO map that the editor keeps, so
# a view that does not follow its document fails here.
function _find_workflow_click(editor, accept)
    for y in 0:6:1500, x in 0:6:1100
        operation = read_intent(editor.projection, editor.iomap, MouseClick(:left, x, y; time = 0.0))
        operation === nothing || accept(operation) && return (x, y, operation)
    end
    nothing
end

# One frame of the editor: evaluate `operation`, then print with the IO map that it
# keeps.
function _apply_workflow_operation!(editor, operation)
    editor.operation = operation
    run_evaluate_stage!(editor)
    run_print_stage!(editor)
end

_is_workflow_selection(operation, text) =
    operation isa ReplaceSelectionOperation && string(strip_reference_types(operation.path)) == text

_is_workflow_write(operation, node, text) =
    operation isa ReplaceReferencedValueOperation && operation.document === node &&
    string(strip_reference_types(operation.reference)) == text

_writes_workflow_node(operation, node) =
    operation isa CompoundOperation &&
    any(o -> o isa ReplaceReferencedValueOperation && o.document === node, operation.operations)

"""
    test_workflow_to_widget()

The outline of a workflow in an editor: a click names the place it lands on, a key
types into a title, the buttons change a state, add a node and remove it, and fold
a node, and the view that the editor keeps follows each change.
"""
function test_workflow_to_widget()
    @testset "WorkflowToWidget" begin
        @testset "a click in a title, a question, a reason, an entry or a card names it" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            for text in (".title.value{2}", ".children[1].title.value{2}",
                         ".children[2].question.value{2}",
                         ".children[2].options[1].reason.value{2}",
                         ".children[1].journal[1].text.value{2}",
                         ".children[3].cards[1].title.value{2}",
                         ".children[3].cards[1].content.value{2}")
                @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, text)) !== nothing
            end
        end

        @testset "a key types into the title that holds the caret" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            hit = _find_workflow_click(editor, operation -> _is_workflow_selection(operation, ".children[4].title.value{3}"))
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            operation = read_intent(editor.projection, editor.iomap, KeyPress('X', ModifierKeys(); time = 0.0))
            @test operation !== nothing
            _apply_workflow_operation!(editor, operation)
            @test workflow.children[4].title.value == "AssXistant tools"
        end

        @testset "the state button steps the state and writes a :state entry" begin
            workflow = make_workflow_document_example()
            tools = workflow.children[4]
            editor = _make_workflow_view_editor(workflow)
            hit = _find_workflow_click(editor, operation -> _writes_workflow_node(operation, tools))
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            @test tools.state === :active
            @test length(tools.journal) == 1
            @test tools.journal[1].kind === :state
            @test tools.journal[1].author === :person
        end

        @testset "a step that a button adds shows at once, and its button removes it" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            hit = _find_workflow_click(editor, operation -> _is_workflow_write(operation, workflow, ".children{4}"))
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            @test length(workflow.children) == 5
            added = workflow.children[5]
            @test added isa WorkflowStep
            @test _find_workflow_click(editor, operation -> _writes_workflow_node(operation, added)) !== nothing
            hit = _find_workflow_click(editor, operation -> _is_workflow_write(operation, workflow, ".children[5]"))
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            @test length(workflow.children) == 4
            @test _find_workflow_click(editor, operation -> _writes_workflow_node(operation, added)) === nothing
        end

        @testset "an option, an entry and a card are added by the buttons of their node" begin
            workflow = make_workflow_document_example()
            decision = workflow.children[2]
            editor = _make_workflow_view_editor(workflow)
            for (node, text, count) in ((decision, ".options{3}", () -> length(decision.options)),
                                        (decision, ".journal{1}", () -> length(decision.journal)),
                                        (decision, ".cards{0}", () -> length(decision.cards)))
                before = count()
                hit = _find_workflow_click(editor, operation -> _is_workflow_write(operation, node, text))
                @test hit !== nothing
                hit === nothing || _apply_workflow_operation!(editor, hit[3])
                @test count() == before + 1
            end
            @test decision.options[end] isa WorkflowOption
            @test decision.journal[end].kind === :comment
            @test decision.cards[end] isa WorkflowCard
        end

        @testset "the fold button folds a node, and a folded node shows only its header" begin
            workflow = make_workflow_document_example()
            survey = workflow.children[1]
            editor = _make_workflow_view_editor(workflow)
            entry_text = ".children[1].journal[1].text.value{2}"
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, entry_text)) !== nothing
            hit = _find_workflow_click(editor, operation -> operation isa ToggleCollapseOperation && operation.target === survey)
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            @test survey.collapsed
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, entry_text)) === nothing
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, ".children[1].title.value{2}")) !== nothing
        end
    end
end
