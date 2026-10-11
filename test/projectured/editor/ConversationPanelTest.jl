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

# Every text a window drew, with its place, also inside a pane that scrolled.
function _panel_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    node isa Cell && return _panel_texts(node[], ox, oy, found)
    if node isa GraphicsCanvas
        for element in node.elements
            _panel_texts(element, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _panel_texts(node.content, ox + Int(node.x) + round(Int, node.transform.e),
                     oy + Int(node.y) + round(Int, node.transform.f), found)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), node.text))
    end
    found
end

# The chain a page draws an assistant with: the card, and the natural renderer for
# what it holds, as the omnet catalog builds it.
function _make_panel_card_projection()
    measure = FontFileMeasure()
    base = Pair{Type,Any}[PrimitiveDocument => ChainingProjection(
        RecursiveProjection(PrimitiveToText()), TextToGraphics(measure = measure))]
    natural(extra) = NaturalToGraphics(measure = measure,
                                       font = StyleFont("Ubuntu Mono", 20), extra = extra)
    chat = Pair{Type,Any}[
        ConversationDraft => ChainingProjection(
            RecursiveProjection(ConversationComposerToWidget()), natural(base)),
        ConversationDocument => ChainingProjection(
            RecursiveProjection(ConversationToWidget()), natural(base))]
    ChainingProjection(RecursiveProjection(AssistantToWidgetCard()), natural(vcat(chat, base)))
end

function test_assistant_composer_panel()
    @testset "Assistant composer panel (Stage 6)" begin
        @testset "panel renders, and a key goes to the draft where the selection points" begin
            a = Assistant(; llm = FakeLlm("ok"))
            proj = make_assistant_projection_example()
            iom = print_document(proj, a)
            @test iom.output isa GraphicsCanvas
            # No selection in the draft: the key is no edit of it.
            @test !(read_intent(proj, iom, KeyPress('h'; time = 0.0)) isa ReplaceStringRangeOperation)
            # A caret in the draft: the text layer edits the draft's value.
            set_selection!(a, @reference(a, draft.^(make_draft_caret_reference(a.draft))))
            op = read_intent(proj, iom, KeyPress('h'; time = 0.0))
            @test op isa ReplaceStringRangeOperation
            @test op.replacement == "h"
            @test first(get_reference_steps(strip_reference_types(op.reference))) ==
                  FieldReferenceStep("draft")
            @test read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0)) isa SubmitDraftTurnOperation
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

        @testset "an assistant card takes the keys where its selection points" begin
            a = Assistant(; llm = FakeLlm("ok"))
            (editor, backend) = _tr_editor(a, _make_panel_card_projection())
            press(event) = _tr_press!(editor, backend, event)
            none = ModifierKeys()
            # The card selected as a whole takes no key.
            press(KeyPress('z'; time = 0.0))
            @test something(a.draft.parts[end].content.value, "") == ""
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> occursin("type here", t[3]), texts)]
            press(MouseClick(:left, x + 30, y + 8, none; time = 0.0))
            foreach(c -> press(KeyPress(c; time = 0.0)), "hi")
            @test a.draft.parts[end].content.value == "hi"
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            @test (last(steps).start, last(steps).stop) == (2, 2)
            press(KeyDown(:return, none; time = 0.0))
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
            press(MouseClick(:left, x + 30, y + 8, none; time = 0.0))
            at("", (0, 0))
            foreach(c -> press(KeyPress(c; time = 0.0)), "hello")
            at("hello", (5, 5))
            press(KeyDown(:left, none; time = 0.0))
            at("hello", (4, 4))
            press(KeyPress('X'; time = 0.0))
            at("hellXo", (5, 5))
            press(KeyDown(:left, ModifierKeys(shift = true); time = 0.0))
            press(KeyDown(:left, ModifierKeys(shift = true); time = 0.0))
            at("hellXo", (3, 5))
            press(KeyDown(:backspace, none; time = 0.0))
            at("helo", (3, 3))
            press(KeyDown(:return, ModifierKeys(shift = true); time = 0.0))
            at("hel\no", (4, 4))

            # A click inside the text lands where it was aimed.
            texts = _tr_texts(_tr_window(backend))
            (x, y, _) = texts[findfirst(t -> t[3] == "hel", texts)]
            press(MouseClick(:left, x + first(compute_text_extent("h", StyleFont("Ubuntu Mono", 20))),
                             y + 8, none; time = 0.0))
            at("hel\no", (1, 1))

            # Return submits, and the fresh draft holds the selection.
            press(KeyDown(:return, none; time = 0.0))
            @test length(a.conversation.turns) >= 1
            at("", (0, 0))
            press(KeyPress('q'; time = 0.0))
            at("q", (1, 1))

            # A structured part: the kind chooser takes the selection.
            press(KeyDown(:tab, none; time = 0.0))
            @test active() isa DocumentInsertion
            at("", (0, 0))
            foreach(c -> press(KeyPress(c; time = 0.0)), "jul")
            at("jul", (3, 3))
            # The caret does not enter the chooser's own words.
            foreach(_ -> press(KeyDown(:left, none; time = 0.0)), 1:5)
            at("jul", (0, 0))
            press(KeyDown(:backspace, none; time = 0.0))
            at("jul", (0, 0))
            # A range that would leave the value declines.
            press(KeyDown(:end, ModifierKeys(ctrl = true); time = 0.0))
            press(KeyDown(:right, ModifierKeys(shift = true); time = 0.0))
            at("jul", (3, 3))
            _panel_wait_idle!(a)
        end

        # The transcript is read, but the terminal of a sign-in is a place where a
        # person works: a press there puts the caret in its input line, the keys
        # type there, and Return sends the line to the program.
        @testset "a person types the code of a sign-in into its terminal in the transcript" begin
            script = raw"""printf 'Code > '; read code; test "$code" = right"""
            method = AgentSignInMethod("code", "Sign in with a code", "", `sh -c $script`)
            connection = ScriptedAgentConnection(Any[]; is_signed_in = false, sign_in_methods = [method])
            a = Assistant(; backend = :acp, agent_session = ExternalAgentSession(connection))
            (editor, backend) = _tr_editor(a, _make_panel_card_projection())
            press(event) = _tr_press!(editor, backend, event)
            none = ModifierKeys()
            frames_until(condition) =
                timedwait(() -> (run_frame!(editor); condition()), 10.0; pollint = 0.02) === :ok
            requests() = [part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                          if part.content isa ConversationSignInRequest]
            drawn() = _panel_texts(_tr_window(backend))
            find_drawn(text) = (found = [entry for entry in drawn() if entry[3] == text]; isempty(found) ? nothing : first(found))
            evaluate_operation(editor, StartExternalAgentOperation(a))
            @test frames_until(() -> length(requests()) == 1)
            request = only(requests())
            # The button of the method starts the sign-in, in the card.
            @test frames_until(() -> find_drawn("Sign in with a code") !== nothing)
            (x, y, _) = find_drawn("Sign in with a code")
            press(MouseClick(:left, x + 4, y + 6, none; time = 0.0))
            @test request.terminal isa TerminalDocument
            @test frames_until(() -> find_drawn("Code > ") !== nothing)
            # A press in the terminal puts the caret in its input line.
            (x, y, _) = find_drawn("Code > ")
            press(MouseClick(:left, x + 4, y + 6, none; time = 0.0))
            steps = get_reference_steps(strip_reference_types(editor.document.selection))
            @test any(step -> step == FieldReferenceStep("terminal"), steps)
            foreach(c -> press(KeyPress(c; time = 0.0)), "right")
            @test request.terminal.input.value == "right"
            connection.is_signed_in = true
            press(KeyDown(:return, none; time = 0.0))
            @test frames_until(() -> request.state == "Signed in.")
            @test "right" in [line.text for line in request.terminal.lines]
            @test frames_until(() -> length(connection.sessions) == 1)
        end
    end
end
