# The walk-through of a workflow, from its empty document to its file, with the
# gestures of a person: the keys, the presses on the marks and the menus of the rows.

# Whether `operation` writes `value` into `node`, at any depth of its compounds.
_holds_workflow_write(operation, node, value) =
    operation isa ReplaceReferencedValueOperation ? operation.document === node && operation.value === value :
    operation isa CompoundOperation && any(o -> _holds_workflow_write(o, node, value), operation.operations)

"""
    test_workflow_walkthrough()

A person makes a workflow from the empty document: the goal, the first step from
the quiet row, the next step with Return and under the first with Tab, the state
of a step from its mark, a decision with two options and the choice of one from
its mark, a comment, and an element; the workflow saves as a `.pred` text and reads
back to the same text.
"""
function test_workflow_walkthrough()
@testset "a workflow from its empty document to its file" begin
    workflow = make_insertion_document(WorkflowStep)
    editor = _make_workflow_view_editor(workflow)
    press_key(char) = _apply_workflow_operation!(editor, read_intent(editor.projection, editor.iomap,
                                                                     KeyPress(char; time = 0.0)))
    type_text(text) = foreach(press_key, text)
    selected() = string(strip_reference_types(get_selection(workflow)))
    # A press that `accept` takes, and an item of a menu: each answers whether it
    # found one, and applies it.
    click(accept) = begin
        hit = _find_workflow_click(editor, accept)
        hit === nothing || _apply_workflow_operation!(editor, hit[3])
        hit !== nothing
    end
    pick(label, accept) = begin
        found = _find_workflow_menu(editor, menu -> _find_workflow_menu_item(menu, label, accept) !== nothing)
        found === nothing || _apply_workflow_operation!(editor, _find_workflow_menu_item(found[3], label, accept))
        found !== nothing
    end

    # The goal, with a word more at its end.
    count = length(workflow.title.value)
    replace_selection!(workflow, extend_reference(EmptyReference(), FieldReferenceStep("title"),
                                                  FieldReferenceStep("value"), RangeReferenceStep(count, count)))
    _apply_workflow_operation!(editor, DoNothingOperation())
    type_text(" of the view")
    @test workflow.title.value == "New workflow of the view"

    # The first step from the quiet row, the next one with Return, and Tab puts it
    # under the first.
    @test click(operation -> _is_workflow_selection(operation, ".first_text.value{0}"))
    type_text("Survey")
    @test length(workflow.children) == 1 && workflow.children[1].title.value == "Survey"
    press_key('\n')
    type_text("Read")
    @test [step.title.value for step in workflow.children] == ["Survey", "Read"]
    press_key('\t')
    survey = only(workflow.children)
    @test only(survey.children).title.value == "Read"

    # The mark of a step opens its states, and Active writes the state and an entry.
    @test pick("Active", operation -> _writes_workflow_node(operation, survey))
    @test survey.state === :active && survey.journal[end].kind === :state

    # A decision under the step, its question, two options, and the choice of one.
    @test pick("Add a decision", operation -> _is_workflow_write(operation, survey, ".children{1}"))
    decision = survey.children[end]
    @test decision isa WorkflowDecision
    @test selected() == ".children[1].children[2].question.value{0}"
    type_text("Which store")
    @test decision.question.value == "Which store"
    @test click(operation -> _is_workflow_selection(operation, ".children[1].children[2].options[1].title.value{0}"))
    type_text(".pred")
    press_key('\n')
    type_text("binary")
    @test [option.title.value for option in decision.options] == [".pred", "binary"]
    @test click(operation -> _holds_workflow_write(operation, decision.options[1], :chosen))
    @test decision.options[1].state === :chosen

    # A comment on the step, with the caret in it, and an element.
    entries = length(survey.journal)
    @test pick("Comment", operation -> _is_workflow_write(operation, survey, ".journal{" * string(entries) * "}"))
    type_text("Started")
    @test survey.journal[end].text.value == "Started"
    _apply_workflow_operation!(editor, make_add_element_operation(survey, PrimitiveString("a note")))
    @test survey.elements[end].value == "a note"

    # The file: the workflow as its `.pred` text, which reads back to the same text.
    text = print_pred_text(workflow)
    loaded = parse_pred_text(text)
    @test print_pred_text(loaded) == text
    @test loaded.children[1].children[2].options[1].state === :chosen
    @test loaded.children[1].elements[1].value == "a note"
end
end
