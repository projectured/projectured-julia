# An editor that shows `document` through the renderer of any document, with a font
# of fixed size, so the places of the parts are the same on every machine.
function _make_research_view_editor(document)
    projection = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0))
    editor = make_editor(document, projection; backend = HeadlessBackend())
    run_frame!(editor)
    editor
end

# The first click on the view, in reading order, whose answer `accept` takes, as
# `(x, y, operation)`, or `nothing`. It reads the IO map that the editor keeps, so
# a view that does not follow its document fails here.
function _find_research_click(editor, accept)
    for y in 0:6:1500, x in 0:6:1300
        operation = read_intent(editor.projection, editor.iomap, MouseClick(:left, x, y; time = 0.0))
        operation === nothing || accept(operation) && return (x, y, operation)
    end
    nothing
end

# One frame of the editor: evaluate `operation`, then print with the IO map that it
# keeps.
function _apply_research_operation!(editor, operation)
    editor.operation = operation
    run_evaluate_stage!(editor)
    run_print_stage!(editor)
end

_is_research_selection(operation, text) =
    operation isa ReplaceSelectionOperation && string(strip_reference_types(operation.path)) == text

_is_research_write(operation, document, text) =
    operation isa ReplaceReferencedValueOperation && operation.document === document &&
    string(strip_reference_types(operation.reference)) == text

_writes_research_status(operation, item) =
    operation isa CompoundOperation &&
    any(o -> o isa ReplaceReferencedValueOperation && o.document === item, operation.operations)

# A small study: a question and a hypothesis for it, both open.
function _make_small_research_study()
    study = ResearchStudy(title = PrimitiveString("Buffer"), author = :person,
                          time = "2026-10-22T07:00:00Z")
    question = make_research_item(study, ResearchQuestion; time = "2026-10-22T07:01:00Z",
                                  statement = "Which capacity?")
    push!(study.questions, question)
    hypothesis = make_research_item(study, ResearchHypothesis; author = :assistant,
                                    time = "2026-10-22T07:02:00Z",
                                    statement = "Thirteen.", question = question)
    push!(study.hypotheses, hypothesis)
    study
end

"""
    test_research_to_widget()

The card of an item and the outline of a study in an editor: a click names the
place it lands on, a key types into a statement, "Accept" records a decision of
the person, an add button adds an item linked to its card, the fold shows the
first line only, a statement can be a Markdown paragraph, and a link line follows
the item that it names.
"""
function test_research_to_widget()
    @testset "ResearchToWidget" begin
        @testset "a click in a text of a card names it" begin
            question = make_research_question_document_example()
            editor = _make_research_view_editor(question)
            for text in (".statement.value{2}", ".criterion.value{2}", ".purpose.value{2}")
                @test _find_research_click(editor, operation -> _is_research_selection(operation, text)) !== nothing
            end
        end

        @testset "a key types into the statement that holds the caret" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> _is_research_selection(operation, ".hypotheses[1].statement.value{3}"))
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            operation = read_intent(editor.projection, editor.iomap, KeyPress('X', ModifierKeys(); time = 0.0))
            @test operation !== nothing
            _apply_research_operation!(editor, operation)
            @test study.hypotheses[1].statement.value == "ThiXrteen."
        end

        @testset "Accept records a decision of the person that accepts the item" begin
            study = _make_small_research_study()
            hypothesis = study.hypotheses[1]
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> _writes_research_status(operation, hypothesis))
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            @test hypothesis.status === :accepted
            @test length(study.decisions) == 1
            decision = study.decisions[1]
            @test decision.id == "D1"
            @test decision.author === :person
            @test decision.accepts[1] === hypothesis
        end

        @testset "the add button of a card adds an item linked to it" begin
            study = _make_small_research_study()
            question = study.questions[1]
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> _is_research_write(operation, study, ".hypotheses{1}"))
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            @test length(study.hypotheses) == 2
            added = study.hypotheses[2]
            @test added.id == "H2"
            @test added.author === :person
            @test added.question === question
            @test _find_research_click(editor, operation -> _is_research_selection(operation, ".hypotheses[2].statement.value{0}")) !== nothing
        end

        @testset "the fold shows the first line of a card, and is not an edit" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            selects_statement(operation) = _is_research_selection(operation, ".hypotheses[1].statement.value{2}")
            @test _find_research_click(editor, selects_statement) !== nothing
            hit = _find_research_click(editor, operation -> operation isa ReplaceViewStateOperation)
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            @test study.folded == ["Q1"]
            hit = _find_research_click(editor, operation -> operation isa ReplaceViewStateOperation &&
                                                            "H1" in operation.operation.value)
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            @test study.folded == ["Q1", "H1"]
            @test _find_research_click(editor, selects_statement) === nothing
            @test !occursin("folded", print_pred_text(study))
        end

        @testset "a place inside a folded card is the item itself" begin
            study = _make_small_research_study()
            study.folded = ["H1"]
            projection = ResearchStudyToWidget()
            iomap = print_document(projection, nothing, study, nothing)
            whole = Reference(FieldReferenceStep("hypotheses"), RangeReferenceStep(0, 1))
            forward = map_reference_forward(projection, iomap,
                Reference(FieldReferenceStep("hypotheses"), RangeReferenceStep(0, 1), FieldReferenceStep("statement")))
            @test string(strip_reference_types(forward)) ==
                  string(strip_reference_types(map_reference_forward(projection, iomap, whole)))
            inside = extend_reference(strip_reference_types(forward), FieldReferenceStep("children"), RangeReferenceStep(1, 2),
                                      FieldReferenceStep("child"), FieldReferenceStep("content"))
            @test string(strip_reference_types(map_reference_backward(projection, iomap, inside))) == ".hypotheses[1]"
        end

        @testset "a statement that is a Markdown paragraph draws through its own view" begin
            hypothesis = ResearchHypothesis(id = "H1", time = "2026-10-22T07:02:00Z",
                                            statement = parse_markdown("A *capacity* of 13.\n").elements[1])
            editor = _make_research_view_editor(hypothesis)
            @test _find_research_click(editor, operation -> operation isa ReplaceSelectionOperation &&
                startswith(string(strip_reference_types(operation.path)), ".statement")) !== nothing
        end

        @testset "a link line follows the item that it names" begin
            study = make_research_study_document_example()
            evidence, hypothesis = study.evidence[1], study.hypotheses[1]
            @test describe_research_link(evidence, :supports, hypothesis) ==
                  "supports H1 A queue capacity of 13 is enough."
            evaluate_operation(nothing, ReplaceReferencedValueOperation(hypothesis.statement, "value", "Twelve."))
            @test describe_research_link(evidence, :supports, hypothesis) == "supports H1 Twelve."
            @test describe_research_link(hypothesis, :question, study.questions[1])[1:12] == "addresses Q1"
            @test describe_research_expectation(hypothesis.prediction) ==
                  "expects a value ≤ 0.01 of drop rate at K = 13"
        end
    end
end
