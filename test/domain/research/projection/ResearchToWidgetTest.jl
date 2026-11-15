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

# Every text that the output of `editor` draws, at any depth.
function _collect_research_texts(node, found = String[])
    node = node isa Cell ? node[] : node
    if node isa GraphicsText
        push!(found, String(node.text))
    elseif node isa GraphicsViewport
        _collect_research_texts(node.content, found)
    elseif node isa GraphicsCanvas
        foreach(element -> _collect_research_texts(element, found), node.elements)
    end
    found
end

# Whether `operation` writes into `item` at any depth of its compounds.
_holds_research_status(operation, item) =
    operation isa ReplaceReferencedValueOperation ? operation.document === item :
    operation isa CompoundOperation && any(o -> _holds_research_status(o, item), operation.operations)

# Whether `operation` closes the panel of a decision of `study` and writes nothing else.
_closes_research_draft(operation, study) =
    operation isa ReplaceViewStateOperation && operation.operation isa ReplaceReferencedValueOperation &&
    operation.operation.document === study && operation.operation.value === nothing

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

# The menu that a press on the view opens, the first that `accept` takes of the
# menus of the rows, as `(x, y, menu)`, or `nothing`.
function _find_research_menu(editor, accept)
    hit = _find_research_click(editor, operation ->
        operation isa ReplaceViewStateOperation && operation.operation isa OpenContextMenuOperation &&
        accept(operation.operation.layers[1][2]))
    hit === nothing ? nothing : (hit[1], hit[2], hit[3].operation.layers[1][2])
end

# The operation of the item of `menu` whose label is `label`, or `nothing`.
function _find_research_menu_item(menu, label)
    for element in menu.elements
        element isa WidgetMenuItem && string(element.action.label) == label && return element.operation
    end
    nothing
end

_has_research_menu_item(label) = menu -> _find_research_menu_item(menu, label) !== nothing

"""
    test_research_to_widget()

The row of an item and the outline of a study in an editor: a click names the
place it lands on, a key types into a statement, the menu of a row records a
decision of the person and adds an item linked to it, the fold shows the first
line only, a statement can be a Markdown paragraph, and a row shows the links
into its item beside the links out of it.
"""
function test_research_to_widget()
    @testset "ResearchToWidget" begin
        @testset "a click in a text of a row names it" begin
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

        @testset "a press on a chip selects the item it names" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> operation isa ShowSelectionOperation)
            @test hit !== nothing
            path = strip_reference_types(hit[3].operation.path)
            target = evaluate_reference(study, path)
            # The chip of the hypothesis names its question; the question names the
            # hypothesis back. Either is selected where its section holds it.
            @test target === study.questions[1] || target === study.hypotheses[1]
            @test length(collect(get_reference_steps(path))) == 2
            _apply_research_operation!(editor, hit[3])
            @test evaluate_reference(study, strip_reference_types(get_selection(study))) === target
        end

        @testset "Accept… in the menu of a row opens a panel, and Record records a decision of the person" begin
            study = _make_small_research_study()
            hypothesis = study.hypotheses[1]
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, _has_research_menu_item("Accept H1…"))
            @test found !== nothing
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Accept H1…"))
            @test study.deciding isa ResearchDecisionDraft
            @test study.deciding.item === hypothesis && study.deciding.verdict === :accepted
            @test hypothesis.status === :open
            # Cancel closes the panel and records nothing.
            cancel = _find_research_click(editor, operation -> _closes_research_draft(operation, study))
            @test cancel !== nothing
            _apply_research_operation!(editor, cancel[3])
            @test study.deciding === nothing && isempty(study.decisions)
            # Record writes the decision, the status and the reason in one edit.
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Accept H1…"))
            study.deciding.reason.value = "The sweep shows it."
            record = _find_research_click(editor, operation -> _holds_research_status(operation, hypothesis))
            @test record !== nothing
            _apply_research_operation!(editor, record[3])
            @test hypothesis.status === :accepted
            @test study.deciding === nothing
            @test length(study.decisions) == 1
            decision = study.decisions[1]
            @test decision.id == "D1"
            @test decision.author === :person
            @test decision.accepts[1] === hypothesis
            @test decision.reason.value == "The sweep shows it."
        end

        @testset "the basis of the panel is the evidence that bears on the item, and a press on a chip changes it" begin
            study = _make_small_research_study()
            hypothesis = study.hypotheses[1]
            evidence = make_research_item(study, ResearchEvidence; time = "2026-10-22T07:03:00Z",
                                          statement = "At K = 13 it holds.", supports = Any[hypothesis])
            push!(study.evidence, evidence)
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, _has_research_menu_item("Accept H1…"))
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Accept H1…"))
            draft = study.deciding
            @test collect(draft.basis) == Any[evidence]
            toggles(operation) = operation isa ReplaceReferencedValueOperation && operation.document === draft &&
                                 startswith(string(strip_reference_types(operation.reference)), ".basis")
            chip = _find_research_click(editor, toggles)
            @test chip !== nothing
            _apply_research_operation!(editor, chip[3])
            @test isempty(draft.basis)
            _apply_research_operation!(editor, _find_research_click(editor, toggles)[3])
            @test collect(draft.basis) == Any[evidence]
            record = _find_research_click(editor, operation -> _holds_research_status(operation, hypothesis))
            _apply_research_operation!(editor, record[3])
            @test collect(only(study.decisions).basis) == Any[evidence]
        end

        @testset "the menu of a section adds an item of its kind, folds its items and switches the view" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            section(label) = _find_research_menu(editor, menu -> _find_research_menu_item(menu, label) !== nothing &&
                                                                 _find_research_menu_item(menu, "Add a hypothesis") !== nothing)
            found = section("Fold all")
            @test found !== nothing
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Add a hypothesis"))
            @test length(study.hypotheses) == 2
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[2].statement.value{0}"
            _apply_research_operation!(editor, _find_research_menu_item(section("Fold all")[3], "Fold all"))
            @test Set(study.folded) == Set(["H1", "H2"])
            unfold = section("Unfold all")
            @test unfold !== nothing
            _apply_research_operation!(editor, _find_research_menu_item(unfold[3], "Unfold all"))
            @test isempty(study.folded)
            by_time = _find_research_menu_item(section("View by time")[3], "View by time")
            @test !is_undo_step(nothing, by_time)
            _apply_research_operation!(editor, by_time)
            @test study.view === :time
            # A section of a day has no add, and switches back by kind.
            day = _find_research_menu(editor, _has_research_menu_item("View by kind"))
            @test day !== nothing && _find_research_menu_item(day[3], "Add a hypothesis") === nothing
        end

        @testset "the menu of a row copies the id and shows the item in the map, and an element opens in a tab" begin
            study = _make_small_research_study()
            hypothesis = study.hypotheses[1]
            push!(hypothesis.elements, PrimitiveString("K from 1 to 20"))
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, _has_research_menu_item("Accept H1…"))
            copied = _find_research_menu_item(found[3], "Copy the id")
            @test copied isa WriteOsClipboardOperation && copied.text == "H1"
            element = _find_research_menu(editor, _has_research_menu_item("Open in a tab"))
            @test element !== nothing
            tab = _find_research_menu_item(element[3], "Open in a tab")
            @test tab isa OpenPageOperation && tab.document === hypothesis.elements[1] && tab.place === :new_tab
            # Open in the map shows the map in place of the rows, with the item selected,
            # and is no edit.
            opened = _find_research_menu_item(found[3], "Open in the map")
            @test !is_undo_step(nothing, opened)
            _apply_research_operation!(editor, opened)
            @test study.view === :map
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[1]"
            output = editor.iomap.output
            shown = output isa Cell ? output[] : output
            @test any(text -> text == "H1", _collect_research_texts(shown))
            # A path into the study is a path into the study of the map, and back.
            projection = ResearchStudyToWidget()
            iomap = print_document(projection, nothing, study, nothing)
            forward = map_reference_forward(projection, iomap,
                                            Reference(FieldReferenceStep("hypotheses"), RangeReferenceStep(0, 1)))
            @test string(strip_reference_types(forward)) == ".children[4].study.hypotheses[1]"
            @test string(strip_reference_types(map_reference_backward(projection, iomap, forward))) == ".hypotheses[1]"
            @test iomap.output.children[4] isa ResearchMap && iomap.output.children[4].study === study
        end

        @testset "Add an element puts the caret in its type-in, and Escape there removes it" begin
            study = _make_small_research_study()
            hypothesis = study.hypotheses[1]
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, _has_research_menu_item("Accept H1…"))
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Add an element"))
            @test only(hypothesis.elements) isa DocumentInsertion
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[1].elements[1].value{0}"
            escape = read_intent(editor.projection, editor.iomap, KeyDown(:escape, ModifierKeys(); time = 0.0))
            _apply_research_operation!(editor, escape)
            @test isempty(hypothesis.elements)
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[1]"
        end

        @testset "a vertex of the map is the row of its item: a press, its menu and its keys act on the item" begin
            study = _make_small_research_study()
            study.view = :map
            hypothesis = study.hypotheses[1]
            editor = _make_research_view_editor(study)
            # A press on the text of a vertex puts the caret in the text of the item.
            @test _find_research_click(editor, operation ->
                _is_research_selection(operation, ".hypotheses[1].statement.value{2}")) !== nothing
            # The menu of a vertex is the menu of the item on the map.
            found = _find_research_menu(editor, _has_research_menu_item("Accept H1…"))
            @test found !== nothing
            labels = [string(element.action.label) for element in found[3].elements if element isa WidgetMenuItem]
            @test "Show in the outline" in labels && !("Fold" in labels) && !("Open in the map" in labels)
            # Accept… opens the panel in the vertex, and Record decides.
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Accept H1…"))
            @test study.deciding isa ResearchDecisionDraft
            record = _find_research_click(editor, operation -> _holds_research_status(operation, hypothesis))
            @test record !== nothing
            _apply_research_operation!(editor, record[3])
            @test hypothesis.status === :accepted && length(study.decisions) == 1
            # A key types into the text of a vertex, and Return at its end adds an
            # item of the same kind with the caret in its text.
            count = length(hypothesis.statement.value)
            replace_selection!(study, extend_reference(EmptyReference(), FieldReferenceStep("hypotheses"),
                                                       RangeReferenceStep(0, 1), FieldReferenceStep("statement"),
                                                       FieldReferenceStep("value"), RangeReferenceStep(count, count)))
            _apply_research_operation!(editor, DoNothingOperation())
            press_key(char) = _apply_research_operation!(editor, read_intent(editor.projection, editor.iomap,
                                                                             KeyPress(char; time = 0.0)))
            press_key('!')
            @test hypothesis.statement.value == "Thirteen.!"
            press_key('\n')
            @test length(study.hypotheses) == 2
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[2].statement.value{0}"
            # Show in the outline switches the study to its outline.
            shown = _find_research_menu(editor, _has_research_menu_item("Show in the outline"))
            _apply_research_operation!(editor, _find_research_menu_item(shown[3], "Show in the outline"))
            @test study.view === :kind
        end

        @testset "the switch shows the study by time and its report, and no history records it" begin
            study = make_research_study_document_example()
            editor = _make_research_view_editor(study)
            @test "QUESTIONS" in _collect_research_texts(editor.iomap.output) ||
                  "Questions" in _collect_research_texts(editor.iomap.output)
            pick(view) = _find_research_click(editor, operation -> operation isa ReplaceReferencedValueOperation &&
                                                                   operation.document === study && operation.value === view)
            by_time = pick(:time)
            @test by_time !== nothing
            @test !is_undo_step(nothing, by_time[3])
            _apply_research_operation!(editor, by_time[3])
            @test study.view === :time
            texts = _collect_research_texts(editor.iomap.output)
            # The header says the question, and its answer after it.
            @test any(text -> startswith(text, "Q1 Which queue"), texts)
            @test occursin("A1", ResearchModule._describe_study_question(study))
            @test !("Questions" in texts) && !("QUESTIONS" in texts)
            @test any(text -> occursin("Oct", text) || occursin("OCT", text), texts)
            # Each item still has its row, in the order of the time.
            @test _find_research_click(editor, operation -> _is_research_selection(operation, ".questions[1].statement.value{2}")) !== nothing
            report = pick(:report)
            @test report !== nothing
            _apply_research_operation!(editor, report[3])
            @test study.view === :report
            @test print_pred_text(study) == print_pred_text(make_research_study_document_example())
        end

        @testset "an empty study shows a quiet row, and the first key makes the first question" begin
            study = ResearchStudy(title = PrimitiveString("Empty"), author = :person, time = "2026-10-22T07:00:00Z")
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> _is_research_selection(operation, ".first_text.value{0}"))
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            typed = read_intent(editor.projection, editor.iomap, KeyPress('W', ModifierKeys(); time = 0.0))
            @test typed !== nothing
            _apply_research_operation!(editor, typed)
            @test length(study.questions) == 1
            @test study.questions[1].statement.value == "W"
            @test isempty(study.first_text.value)
            @test string(strip_reference_types(get_selection(study))) == ".questions[1].statement.value{1}"
            # The next key types into the question.
            _apply_research_operation!(editor, read_intent(editor.projection, editor.iomap,
                                                           KeyPress('h', ModifierKeys(); time = 0.0)))
            @test study.questions[1].statement.value == "Wh"
        end

        @testset "the keys of a row add an item of the same kind and move it" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            question = study.questions[1]
            count = length(question.statement.value)
            replace_selection!(study, extend_reference(EmptyReference(), FieldReferenceStep("questions"),
                                                       RangeReferenceStep(0, 1), FieldReferenceStep("statement"),
                                                       FieldReferenceStep("value"), RangeReferenceStep(count, count)))
            _apply_research_operation!(editor, DoNothingOperation())
            press(key) = _apply_research_operation!(editor, read_intent(editor.projection, editor.iomap, key))
            press(KeyPress('\n'; time = 0.0))
            @test length(study.questions) == 2
            @test study.questions[2].id == "Q2"
            @test string(strip_reference_types(get_selection(study))) == ".questions[2].statement.value{0}"
            press(KeyDown(:up, ModifierKeys(alt = true); time = 0.0))
            @test study.questions[1].id == "Q2" && study.questions[2] === question
            @test string(strip_reference_types(get_selection(study))) == ".questions[1].statement.value{0}"
        end

        @testset "Edit all fields shows the empty fields and the links while the caret is in the row" begin
            study = _make_small_research_study()
            question = study.questions[1]
            hypothesis = study.hypotheses[1]
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, menu -> _find_research_menu_item(menu, "Edit all fields") !== nothing &&
                                                        _find_research_menu_item(menu, "Add a hypothesis for Q1") !== nothing)
            @test found !== nothing
            @test !("Criterion" in _collect_research_texts(editor.iomap.output))
            _apply_research_operation!(editor, _find_research_menu_item(found[3], "Edit all fields"))
            @test study.editing == "Q1"
            @test string(strip_reference_types(get_selection(study))) == ".questions[1].statement.value{15}"
            texts = _collect_research_texts(editor.iomap.output)
            @test "Criterion" in texts && "Purpose" in texts
            # The "+" of a link field opens the list of the items, and a choice links one.
            plus = _find_research_click(editor, operation -> operation isa ReplaceViewStateOperation &&
                                                             operation.operation isa OpenContextMenuOperation &&
                                                             operation.operation.layers[1][2] isa WidgetChoiceList)
            @test plus !== nothing
            list = plus[3].operation.layers[1][2]
            @test [choice.value for choice in list.find("thir")] == Any[hypothesis]
            _apply_research_operation!(editor, list.choose(hypothesis))
            @test question.parent === hypothesis
            # The caret leaves the row, and the row shows only what was written.
            replace_selection!(study, extend_reference(EmptyReference(), FieldReferenceStep("hypotheses"),
                                                       RangeReferenceStep(0, 1)))
            _apply_research_operation!(editor, DoNothingOperation())
            @test !("Criterion" in _collect_research_texts(editor.iomap.output))
        end

        @testset "the menu of a row adds an item linked to it" begin
            study = _make_small_research_study()
            question = study.questions[1]
            editor = _make_research_view_editor(study)
            found = _find_research_menu(editor, _has_research_menu_item("Add a hypothesis for Q1"))
            @test found !== nothing
            add = _find_research_menu_item(found[3], "Add a hypothesis for Q1")
            @test add isa CompoundOperation && _is_research_write(add.operations[1], study, ".hypotheses{1}")
            _apply_research_operation!(editor, add)
            @test length(study.hypotheses) == 2
            added = study.hypotheses[2]
            @test added.id == "H2"
            @test added.author === :person
            @test added.question === question
            # The caret is in the new statement, so the person types it in place.
            @test string(strip_reference_types(get_selection(study))) == ".hypotheses[2].statement.value{0}"
            @test _find_research_click(editor, operation -> _is_research_selection(operation, ".hypotheses[2].statement.value{0}")) !== nothing
        end

        @testset "a right click and Shift+F10 open the menu of a row" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            hit = _find_research_click(editor, operation -> _is_research_selection(operation, ".hypotheses[1].statement.value{3}"))
            _apply_research_operation!(editor, hit[3])
            opened = read_intent(editor.projection, editor.iomap, KeyDown(:f10, ModifierKeys(shift = true); time = 0.0))
            @test opened isa ReplaceViewStateOperation && opened.operation isa OpenContextMenuOperation
            @test opened.operation.layers[1][1] == "H1"
            right = read_intent(editor.projection, editor.iomap,
                                MouseClick(:right, hit[1], hit[2], 1, ModifierKeys(); time = 0.0))
            @test right isa ReplaceViewStateOperation && right.operation isa OpenContextMenuOperation
        end

        @testset "the fold shows the first line of a row, and is not an edit" begin
            study = _make_small_research_study()
            editor = _make_research_view_editor(study)
            folds_h1(operation) = operation isa ReplaceViewStateOperation &&
                                      operation.operation isa ReplaceReferencedValueOperation &&
                                      "H1" in operation.operation.value
            hit = _find_research_click(editor, folds_h1)
            @test hit !== nothing
            _apply_research_operation!(editor, hit[3])
            @test study.folded == ["H1"]
            # The folded row keeps its text, and drops the links under it.
            @test _find_research_click(editor, operation -> _is_research_selection(operation, ".hypotheses[1].statement.value{2}")) !== nothing
            @test !occursin("folded", print_pred_text(study))
        end

        @testset "a row maps to its item, and so does a part of it that the view drew" begin
            study = _make_small_research_study()
            projection = ResearchStudyToWidget()
            iomap = print_document(projection, nothing, study, nothing)
            whole = Reference(FieldReferenceStep("hypotheses"), RangeReferenceStep(0, 1))
            row = map_reference_forward(projection, iomap, whole)
            @test row !== nothing
            @test string(strip_reference_types(map_reference_backward(projection, iomap, row))) == ".hypotheses[1]"
            facts = extend_reference(strip_reference_types(row), FieldReferenceStep("content"),
                                     FieldReferenceStep("children"), RangeReferenceStep(0, 1))
            @test string(strip_reference_types(map_reference_backward(projection, iomap, facts))) == ".hypotheses[1]"
            statement = map_reference_forward(projection, iomap,
                Reference(FieldReferenceStep("hypotheses"), RangeReferenceStep(0, 1), FieldReferenceStep("statement")))
            @test statement !== nothing
            @test string(strip_reference_types(map_reference_backward(projection, iomap, statement))) ==
                  ".hypotheses[1].statement"
            # A key in a text draws the text and builds no outline.
            output = iomap.output
            evaluate_operation(nothing, ReplaceReferencedValueOperation(study.hypotheses[1].statement, "value", "Twelve."))
            @test iomap.output === output
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
