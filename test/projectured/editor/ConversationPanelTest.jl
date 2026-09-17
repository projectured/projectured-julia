# Stage 6 — the composer wired into the live Assistant panel.
# Submitting the draft turn (ENTER on a text typein → SubmitDraftTurnOperation)
# pushes it into the conversation, resets the draft in place, and streams a reply.


function _panel_wait_idle!(a; timeout_seconds = 3.0)
    deadline = time() + timeout_seconds
    while a.status === :streaming && time() < deadline
        yield(); sleep(0.005)
    end
    a.status
end

function test_assistant_composer_panel()
    @testset "Assistant composer panel (Stage 6)" begin
        @testset "panel renders, and a key goes to the draft where the selection points" begin
            a = Assistant(; llm = FakeLlm("ok"))
            proj = make_assistant_projection_example()
            iom = print_document(proj, a)
            @test iom.output isa GraphicsCanvas
            # No selection in the draft: the key is no edit of it.
            @test !(read_intent(proj, iom, KeyPress('h')) isa ReplaceStringRangeOperation)
            # A caret in the draft: the text layer edits the draft's value.
            set_selection!(a, @reference(a, draft.^(make_draft_caret_reference(a.draft))))
            op = read_intent(proj, iom, KeyPress('h'))
            @test op isa ReplaceStringRangeOperation
            @test op.replacement == "h"
            @test first(get_reference_steps(strip_reference_types(op.reference))) ==
                  FieldReferenceStep("draft")
            @test read_intent(proj, iom, KeyDown(:return, ModifierKeys())) isa SubmitDraftTurnOperation
        end

        @testset "submit pushes the draft, resets it, and streams a reply" begin
            a = Assistant(; llm = FakeLlm("hello there"))
            for ch in "hi assistant"
                evaluate_operation(nothing, ComposerInputOperation(a.draft, string(ch)))
            end
            @test length(a.conversation.turns) == 0

            evaluate_operation(nothing, SubmitDraftTurnOperation(a))
            _panel_wait_idle!(a)

            # User turn submitted, plus a streamed assistant reply.
            @test length(a.conversation.turns) >= 1
            @test a.conversation.turns[1].role == :user
            @test any(t -> t.role == :assistant, a.conversation.turns)

            # Draft reset in place to a single empty text typein.
            @test length(a.draft.parts) == 1
            @test a.draft.parts[1].content isa PrimitiveString
            @test isempty(something(a.draft.parts[1].content.value, ""))
        end

        @testset "empty draft does not submit" begin
            a = Assistant(; llm = FakeLlm("x"))
            evaluate_operation(nothing, SubmitDraftTurnOperation(a))
            @test length(a.conversation.turns) == 0
            @test a.status === :idle
        end

        @testset "ENTER submits through the nested full workbench" begin
            # Regression: in the full workbench the panel reader isn't reached, so
            # the composer must convert ENTER's submit via the draft's assistant.
            ex   = workbench_example
            doc  = ex.make_document()
            proj = ex.make_projection()
            iom  = print_document(proj, doc)
            a = nothing
            for p in (:navigation_page, :editing_page, :information_page, :control_page)
                for e in getfield(doc, p)[].elements
                    e isa Assistant && (a = e)
                end
            end
            @test a !== nothing
            @test doc.control_page.elements[1] === a
            set_selection!(doc, @reference(doc, control_page.elements[1].draft.^(
                make_draft_caret_reference(a.draft))))
            @test read_intent(proj, iom, KeyPress('h')) isa ReplaceStringRangeOperation
            @test read_intent(proj, iom, KeyDown(:return, ModifierKeys())) isa SubmitDraftTurnOperation
        end

        @testset "an assistant card takes the keys where its selection points" begin
            a = Assistant(; llm = FakeLlm("ok"))
            # The chain a page draws an assistant with: the card, and the natural
            # renderer for what it holds, as the omnet catalog builds it.
            measure = measure_truetype_text
            base = Pair{Type,Any}[PrimitiveDocument => ChainingProjection(
                RecursiveProjection(PrimitiveToText()), TextToGraphics(measure = measure))]
            natural(extra) = NaturalToGraphics(measure = measure,
                                               font = font_ubuntu_monospace_regular_20, extra = extra)
            chat = Pair{Type,Any}[
                ConversationDraft => ChainingProjection(
                    RecursiveProjection(ConversationComposerToWidget()), natural(base)),
                ConversationDocument => ChainingProjection(
                    RecursiveProjection(ConversationToWidget()), natural(base))]
            card = ChainingProjection(RecursiveProjection(AssistantToWidgetCard()),
                                      natural(vcat(chat, base)))
            (editor, backend) = _tr_editor(a, card)
            press(event) = _tr_press!(editor, backend, event)
            none = ModifierKeys()
            # The card selected as a whole takes no key.
            press(KeyPress('z'))
            @test something(a.draft.parts[end].content.value, "") == ""
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> occursin("type here", t[3]), texts)]
            press(MousePress(:left, x + 30, y + 8, none))
            foreach(c -> press(KeyPress(c)), "hi")
            @test a.draft.parts[end].content.value == "hi"
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            @test (last(steps).start, last(steps).stop) == (2, 2)
            press(KeyDown(:return, none))
            @test length(a.conversation.turns) >= 1
            @test something(a.draft.parts[end].content.value, "") == ""
            _panel_wait_idle!(a)
        end

        @testset "a click and the keys keep one selection in the draft" begin
            a = Assistant(; llm = FakeLlm("ok"))
            (editor, backend) = _tr_editor(a, make_assistant_projection_example())
            active() = a.draft.parts[end].content
            ends(path) = (steps = get_reference_steps(strip_reference_types(path));
                          (last(steps).start, last(steps).stop))
            # The window's path and the string's own selection name one range.
            function at(value, range)
                @test something(active().value, "") == value
                @test ends(editor.document.selection) == range
                @test ends(getfield(active(), :selection)[]) == range
            end
            press(event) = _tr_press!(editor, backend, event)
            none = ModifierKeys()
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> occursin("type here", t[3]), texts)]
            press(MousePress(:left, x + 30, y + 8, none))
            at("", (0, 0))
            foreach(c -> press(KeyPress(c)), "hello")
            at("hello", (5, 5))
            press(KeyDown(:left, none))
            at("hello", (4, 4))
            press(KeyPress('X'))
            at("hellXo", (5, 5))
            press(KeyDown(:left, ModifierKeys(shift = true)))
            press(KeyDown(:left, ModifierKeys(shift = true)))
            at("hellXo", (3, 5))
            press(KeyDown(:backspace, none))
            at("helo", (3, 3))
            press(KeyDown(:return, ModifierKeys(shift = true)))
            at("hel\no", (4, 4))

            # A click inside the text lands where it was aimed.
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> t[3] == "hel", texts)]
            press(MousePress(:left, x + first(measure_truetype_text("h", font_ubuntu_monospace_regular_20)),
                             y + 8, none))
            at("hel\no", (1, 1))

            # Return submits, and the fresh draft holds the selection.
            press(KeyDown(:return, none))
            @test length(a.conversation.turns) >= 1
            at("", (0, 0))
            press(KeyPress('q'))
            at("q", (1, 1))

            # A structured part: the kind chooser takes the selection.
            press(KeyDown(:tab, none))
            @test active() isa DocumentInsertion
            at("", (0, 0))
            foreach(c -> press(KeyPress(c)), "jul")
            at("jul", (3, 3))
            # The caret does not enter the chooser's own words.
            foreach(_ -> press(KeyDown(:left, none)), 1:5)
            at("jul", (0, 0))
            press(KeyDown(:backspace, none))
            at("jul", (0, 0))
            # A range that would leave the value declines.
            press(KeyDown(:end, ModifierKeys(ctrl = true)))
            press(KeyDown(:right, ModifierKeys(shift = true)))
            at("jul", (3, 3))
            _panel_wait_idle!(a)
        end
    end
end
