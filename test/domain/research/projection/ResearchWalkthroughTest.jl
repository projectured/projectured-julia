# The walk-through of a study, from its empty document to its file, with the
# gestures of a person: the keys, the menus of the rows, the panel of a decision
# and the switch of the views.

"""
    test_research_walkthrough()

A person makes a study from the empty document: the title, the first question
from the quiet row, a hypothesis linked to it from its menu, an experiment that
tests the hypothesis with an element, evidence of the assistant, the acceptance of
the hypothesis with a reason in the panel of its row, an answer to the question,
and the view by time; the study saves as a `.pred` text and reads back to the
same text.
"""
function test_research_walkthrough()
@testset "a study from its empty document to its file" begin
    study = make_insertion_document(ResearchStudy)
    editor = _make_research_view_editor(study)
    press_key(char) = _apply_research_operation!(editor, read_intent(editor.projection, editor.iomap,
                                                                     KeyPress(char; time = 0.0)))
    type_text(text) = foreach(press_key, text)
    selected() = string(strip_reference_types(get_selection(study)))
    # A press that `accept` takes, and an item of a menu: each answers whether it
    # found one, and applies it.
    click(accept) = begin
        hit = _find_research_click(editor, accept)
        hit === nothing || _apply_research_operation!(editor, hit[3])
        hit !== nothing
    end
    pick(label) = begin
        found = _find_research_menu(editor, _has_research_menu_item(label))
        found === nothing || _apply_research_operation!(editor, _find_research_menu_item(found[3], label))
        found !== nothing
    end

    # The title, with a word more at its end.
    count = length(study.title.value)
    replace_selection!(study, extend_reference(EmptyReference(), FieldReferenceStep("title"),
                                               FieldReferenceStep("value"), RangeReferenceStep(count, count)))
    _apply_research_operation!(editor, DoNothingOperation())
    type_text(" of the router")
    @test study.title.value == "New study of the router"

    # The first question from the quiet row: Q1 exists from the first key, by the person.
    @test click(operation -> _is_research_selection(operation, ".first_text.value{0}"))
    type_text("Which capacity?")
    question = only(study.questions)
    @test question.id == "Q1" && question.author === :person
    @test question.statement.value == "Which capacity?"

    # A hypothesis for Q1 from its menu, with the caret in its text.
    @test pick("Add a hypothesis for Q1")
    hypothesis = only(study.hypotheses)
    @test hypothesis.question === question
    @test selected() == ".hypotheses[1].statement.value{0}"
    type_text("Thirteen.")
    @test hypothesis.statement.value == "Thirteen."

    # An experiment that tests H1, which holds an element.
    @test pick("Add an experiment that tests H1")
    experiment = only(study.experiments)
    type_text("Sweep K")
    @test experiment.title.value == "Sweep K" && experiment.tests[1] === hypothesis
    _apply_research_operation!(editor, make_add_element_operation(experiment, PrimitiveString("K from 1 to 20")))
    @test experiment.elements[1].value == "K from 1 to 20"

    # Evidence that the assistant adds, which supports H1.
    evidence = make_research_item(study, ResearchEvidence; author = :assistant, statement = "At K = 13 it holds.",
                                  supports = Any[hypothesis])
    _apply_research_operation!(editor, make_add_research_item_operation(study, evidence))
    @test only(study.evidence).author === :assistant

    # Accept… on H1 opens the panel; the reason, and Record writes the decision.
    @test pick("Accept H1…")
    @test study.deciding isa ResearchDecisionDraft
    study.deciding.reason.value = "E1 shows it."
    @test click(operation -> _holds_research_status(operation, hypothesis))
    @test hypothesis.status === :accepted
    decision = only(study.decisions)
    @test decision.accepts[1] === hypothesis && decision.reason.value == "E1 shows it."

    # An answer to Q1 from its menu.
    @test pick("Add an answer to Q1")
    type_text("A capacity of 13.")
    @test only(study.answers).question === question
    @test occursin("A1 A capacity of 13.", ResearchModule._describe_study_question(study))

    # The view by time, and back by kind.
    @test click(operation -> operation isa ReplaceReferencedValueOperation && operation.document === study &&
                            operation.value === :time)
    @test study.view === :time
    @test click(operation -> operation isa ReplaceReferencedValueOperation && operation.document === study &&
                            operation.value === :kind)

    # The file: the study as its `.pred` text, which reads back to the same text.
    text = print_pred_text(study)
    loaded = parse_pred_text(text)
    @test print_pred_text(loaded) == text
    @test loaded.hypotheses[1].status === :accepted
    @test loaded.experiments[1].elements[1].value == "K from 1 to 20"
end
end
