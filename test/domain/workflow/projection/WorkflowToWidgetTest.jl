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

# Every text that the output of a view draws, at any depth.
function _collect_workflow_texts(node, found = String[])
    node = node isa Cell ? node[] : node
    if node isa GraphicsText
        push!(found, String(node.text))
    elseif node isa GraphicsViewport
        _collect_workflow_texts(node.content, found)
    elseif node isa GraphicsCanvas
        foreach(element -> _collect_workflow_texts(element, found), node.elements)
    end
    found
end

_is_workflow_selection(operation, text) =
    operation isa ReplaceSelectionOperation && string(strip_reference_types(operation.path)) == text

# An add answers its write and the caret into the new node, so the write is the
# first part of a compound.
_is_workflow_write(operation, node, text) =
    operation isa CompoundOperation && !isempty(operation.operations) &&
    operation.operations[end] isa SelectDocumentOperation ? _is_workflow_write(operation.operations[1], node, text) :
    operation isa ReplaceReferencedValueOperation && operation.document === node &&
    string(strip_reference_types(operation.reference)) == text

_writes_workflow_node(operation, node) =
    operation isa CompoundOperation &&
    any(o -> o isa ReplaceReferencedValueOperation && o.document === node, operation.operations)

# The menu that a press on the view opens, the first that `accept` takes, as
# `(x, y, menu)`, or `nothing`. A left press opens the menu of a mark or of a
# "⋯", and a right press the menu of a row.
function _find_workflow_menu(editor, accept; button::Symbol = :left)
    opens(operation) = operation isa ReplaceViewStateOperation && operation.operation isa OpenContextMenuOperation &&
                       accept(operation.operation.layers[1][2])
    for y in 0:6:1500, x in 0:6:1100
        operation = read_intent(editor.projection, editor.iomap, MouseClick(button, x, y, 1, ModifierKeys(); time = 0.0))
        operation !== nothing && opens(operation) && return (x, y, operation.operation.layers[1][2])
    end
    nothing
end

# The operation of the item of `menu` whose label is `label` and whose operation
# `accept` takes, or `nothing`.
function _find_workflow_menu_item(menu, label, accept = operation -> true)
    for element in menu.elements
        element isa WidgetMenuItem && string(element.action.label) == label && element.operation !== nothing &&
            accept(element.operation) && return element.operation
    end
    nothing
end

"""
    test_workflow_to_widget()

The outline of a workflow in an editor: a click names the place it lands on, a key
types into a title, the mark of a step opens its states, the menu of a row adds a
node, an option, an entry and an element and removes a node, the fold folds a node,
and the view that the editor keeps follows each change.
"""
function test_workflow_to_widget()
    @testset "WorkflowToWidget" begin
        @testset "a click in a title, a question, a reason or an element names it" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            for text in (".title.value{2}", ".children[1].title.value{2}",
                         ".children[2].question.value{2}",
                         ".children[2].options[1].reason.value{2}",
                         ".children[3].elements[1].value{2}")
                @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, text)) !== nothing
            end
        end

        @testset "a node is its row, and an edit of a title builds no row" begin
            workflow = make_workflow_document_example()
            projection = WorkflowNodeToWidget()
            iomap = print_document(projection, nothing, workflow, nothing)
            child = Reference(FieldReferenceStep("children"), RangeReferenceStep(0, 1))
            row = map_reference_forward(projection, iomap, child)
            @test row !== nothing
            @test string(strip_reference_types(map_reference_backward(projection, iomap, row))) == ".children[1]"
            output = iomap.output
            evaluate_operation(nothing, ReplaceReferencedValueOperation(workflow.title, "value", "Renamed"))
            @test iomap.output === output
            evaluate_operation(nothing, make_insert_workflow_node_operation(workflow, 1, WorkflowStep()))
            @test iomap.output !== output
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

        @testset "the mark of a step opens its states, and a state writes a :state entry" begin
            workflow = make_workflow_document_example()
            tools = workflow.children[4]
            editor = _make_workflow_view_editor(workflow)
            sets_tools(operation) = _writes_workflow_node(operation, tools)
            found = _find_workflow_menu(editor, menu -> _find_workflow_menu_item(menu, "Active", sets_tools) !== nothing)
            @test found !== nothing
            _apply_workflow_operation!(editor, _find_workflow_menu_item(found[3], "Active", sets_tools))
            @test tools.state === :active
            @test length(tools.journal) == 1
            @test tools.journal[1].kind === :state
            @test tools.journal[1].author === :person
        end

        @testset "a step that the menu adds shows at once, and its menu removes it" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            adds_step(operation) = _is_workflow_write(operation, workflow, ".children{4}")
            found = _find_workflow_menu(editor, menu -> _find_workflow_menu_item(menu, "Add a step", adds_step) !== nothing)
            @test found !== nothing
            _apply_workflow_operation!(editor, _find_workflow_menu_item(found[3], "Add a step", adds_step))
            @test length(workflow.children) == 5
            added = workflow.children[5]
            @test added isa WorkflowStep
            # The caret is in the title of the new step, so the person types it in place.
            @test string(strip_reference_types(get_selection(workflow))) == ".children[5].title.value{0}"
            removes(operation) = _is_workflow_write(operation, workflow, ".children[5]")
            found = _find_workflow_menu(editor, menu -> _find_workflow_menu_item(menu, "Delete", removes) !== nothing;
                                        button = :right)
            @test found !== nothing
            _apply_workflow_operation!(editor, _find_workflow_menu_item(found[3], "Delete", removes))
            @test length(workflow.children) == 4
        end

        @testset "an option, an entry and an element are added by the menu of their node" begin
            workflow = make_workflow_document_example()
            decision = workflow.children[2]
            editor = _make_workflow_view_editor(workflow)
            for (label, text, count) in (("Add an option", ".options{3}", () -> length(decision.options)),
                                         ("Comment", ".journal{1}", () -> length(decision.journal)),
                                         ("Add an element", ".elements{0}", () -> length(decision.elements)))
                before = count()
                writes(operation) = _is_workflow_write(operation, decision, text)
                found = _find_workflow_menu(editor, menu -> _find_workflow_menu_item(menu, label, writes) !== nothing)
                @test found !== nothing
                found === nothing || _apply_workflow_operation!(editor, _find_workflow_menu_item(found[3], label, writes))
                @test count() == before + 1
            end
            @test decision.options[end] isa WorkflowOption
            @test decision.journal[end].kind === :comment
            @test decision.elements[end] isa DocumentInsertion
            # A comment shows the journal under the row, with the caret in the new entry.
            @test decision.journal_shown
            @test string(strip_reference_types(get_selection(workflow))) ==
                  ".children[2].journal[" * string(length(decision.journal)) * "].text.value{0}"
        end

        @testset "a press on the count of the journal shows its entries under the row" begin
            workflow = make_workflow_document_example()
            survey = workflow.children[1]
            editor = _make_workflow_view_editor(workflow)
            said = something(survey.journal[1].text.value, "")
            @test !any(text -> occursin(first(said, 12), text), _collect_workflow_texts(editor.iomap.output))
            show = _find_workflow_click(editor, operation -> operation isa ReplaceViewStateOperation &&
                                                             operation.operation isa ReplaceReferencedValueOperation &&
                                                             operation.operation.document === survey &&
                                                             operation.operation.value === true)
            @test show !== nothing
            _apply_workflow_operation!(editor, show[3])
            @test survey.journal_shown
            @test any(text -> occursin(first(said, 12), text), _collect_workflow_texts(editor.iomap.output))
        end

        @testset "an empty workflow shows a quiet row, and the first key makes the first step" begin
            workflow = WorkflowStep(title = PrimitiveString("Ship the view"))
            editor = _make_workflow_view_editor(workflow)
            hit = _find_workflow_click(editor, operation -> _is_workflow_selection(operation, ".first_text.value{0}"))
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            typed = read_intent(editor.projection, editor.iomap, KeyPress('S', ModifierKeys(); time = 0.0))
            @test typed !== nothing
            _apply_workflow_operation!(editor, typed)
            @test length(workflow.children) == 1
            @test workflow.children[1].title.value == "S"
            @test isempty(workflow.first_text.value)
            @test string(strip_reference_types(get_selection(workflow))) == ".children[1].title.value{1}"
            _apply_workflow_operation!(editor, read_intent(editor.projection, editor.iomap,
                                                           KeyPress('u', ModifierKeys(); time = 0.0)))
            @test workflow.children[1].title.value == "Su"
        end

        @testset "the keys of a row add a sibling, move a node, and indent and outdent it" begin
            workflow = make_workflow_document_example()
            editor = _make_workflow_view_editor(workflow)
            survey = workflow.children[1]
            caret(steps...) = extend_reference(EmptyReference(), steps...)
            at_title_end(index, node) = caret(FieldReferenceStep("children"), RangeReferenceStep(index - 1, index),
                                              FieldReferenceStep("title"), FieldReferenceStep("value"),
                                              RangeReferenceStep(length(node.title.value), length(node.title.value)))
            press(key) = _apply_workflow_operation!(editor, read_intent(editor.projection, editor.iomap, key))
            selected() = string(strip_reference_types(get_selection(workflow)))

            # Return at the end of a title adds a step after it, with the caret in it.
            replace_selection!(workflow, at_title_end(1, survey))
            _apply_workflow_operation!(editor, DoNothingOperation())
            @test read_intent(editor.projection, editor.iomap, KeyPress('\n'; time = 0.0)) isa CompoundOperation
            press(KeyPress('\n'; time = 0.0))
            @test length(workflow.children) == 5
            added = workflow.children[2]
            @test added isa WorkflowStep && isempty(added.title.value)
            @test selected() == ".children[2].title.value{0}"

            # Alt+Down moves the new step after the decision, and the caret goes with it.
            press(KeyDown(:down, ModifierKeys(alt = true); time = 0.0))
            @test workflow.children[3] === added
            @test selected() == ".children[3].title.value{0}"
            press(KeyDown(:up, ModifierKeys(alt = true); time = 0.0))
            @test workflow.children[2] === added

            # Tab makes it the last child of the step before it, and Shift+Tab takes it out again.
            press(KeyPress('\t'; time = 0.0))
            @test workflow.children[1].children[end] === added
            @test length(workflow.children) == 4
            press(KeyPress('\t', ModifierKeys(shift = true); time = 0.0))
            @test workflow.children[2] === added
            @test length(workflow.children) == 5
        end

        @testset "the fold folds a node, and a folded node shows only its row" begin
            workflow = make_workflow_document_example()
            outline_view = workflow.children[3]
            editor = _make_workflow_view_editor(workflow)
            element_text = ".children[3].elements[1].value{2}"
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, element_text)) !== nothing
            hit = _find_workflow_click(editor, operation -> operation isa ReplaceViewStateOperation &&
                                                           operation.operation isa ToggleCollapseOperation &&
                                                           operation.operation.target === outline_view)
            @test hit !== nothing
            _apply_workflow_operation!(editor, hit[3])
            @test outline_view.collapsed
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, element_text)) === nothing
            # A fold is state of the view: the file leaves it out.
            @test !occursin("collapsed", print_pred_text(workflow))
            @test _find_workflow_click(editor, operation -> _is_workflow_selection(operation, ".children[3].title.value{2}")) !== nothing
        end
    end
end
