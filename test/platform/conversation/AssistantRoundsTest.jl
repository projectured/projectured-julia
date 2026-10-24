# A turn of a model has a budget of rounds, a setting of its assistant. A turn
# that uses it ends with a note under the answer, and the button of the note
# sends "Go on." as the person.

# A tool set with one tool, `probe`, that answers "ran".
function _make_rounds_tools()
    set = register_default_tools!(ToolSet())
    register_tool!(set, Tool("probe"; description = "a tool of the test", parameters = NamedTuple[],
                             handler = (target, arguments) -> "ran"))
    set
end

# A round in which the model calls `probe`, and one in which it answers `text`.
_make_rounds_call_round() =
    make_scripted_turn(make_scripted_run(""; tool_id = "tu_1", tool_name = "probe");
                       stop_reason = "tool_use")
_make_rounds_answer_round(text) =
    make_scripted_turn(make_scripted_say(text; delay = 0); stop_reason = "end_turn")

# The notes of the parts of `turn`.
_collect_turn_notes(turn) =
    [part.content for part in collect(turn.parts) if part.content isa ConversationNote]

function test_assistant_rounds()
    @testset "the budget of rounds of a turn" begin
        @testset "an assistant keeps its budget and its wake in its file" begin
            a = Assistant()
            @test a.max_rounds == DEFAULT_ASSISTANT_ROUNDS == 8
            @test a.wake === false
            @test !occursin(r"\b(max_rounds|wake) =", print_pred_text(a))
            @test_throws ArgumentError Assistant(; max_rounds = 0)
            a = Assistant(; max_rounds = 40, wake = true)
            loaded = parse_pred_text(print_pred_text(a))
            @test (loaded.max_rounds, loaded.wake) == (40, true)
        end

        @testset "a turn that uses its rounds ends with a note that offers to go on" begin
            llm = ScriptedLlm([_make_rounds_call_round(), _make_rounds_call_round(),
                               _make_rounds_call_round(), _make_rounds_answer_round("Done.")])
            a = Assistant(; llm, max_rounds = 2)
            editor = (document = a, tools = _make_rounds_tools())
            a.input.value = "Probe it."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test timedwait(() -> a.status !== :streaming, 30.0; pollint = 0.01) === :ok
            question, answer = collect(a.conversation.turns)
            @test answer.stop_reason === :round_limit
            notes = _collect_turn_notes(answer)
            @test length(notes) == 1
            note = only(notes)
            @test note.kind === :round_limit
            @test note.text == "The turn reached its 2 rounds."
            @test note.action_label == "Go on"
            # The model does not read the note as text of its own answer.
            messages = build_messages(a.conversation)
            @test !any(message -> occursin("rounds.", string(message.content)), messages)

            # The button sends the words as the person and starts a turn with them.
            note.action(editor)
            @test timedwait(() -> length(a.conversation.turns) == 4 && a.status !== :streaming,
                            30.0; pollint = 0.01) === :ok
            turns = collect(a.conversation.turns)
            @test turns[3].role === :user
            @test AssistantModule._text_to_string(only(collect(turns[3].parts)).content) == GO_ON_PROMPT
            @test turns[4].stop_reason !== :round_limit
            @test isempty(_collect_turn_notes(turns[4]))
        end

        @testset "a note writes its text and kind, and no button" begin
            note = ConversationNote("The task group ended."; kind = :wake, action_label = "Look",
                                    action = editor -> nothing)
            loaded = parse_pred_text(print_pred_text(note))
            @test (loaded.text, loaded.kind) == ("The task group ended.", :wake)
            @test loaded.action === nothing && loaded.action_label == ""
            # A transcript in text marks a note.
            conversation = ConversationConversation([
                ConversationTurn(:user, [ConversationPart(note)])])
            @test occursin("※ The task group ended.", format_conversation(conversation))
            @test is_note_turn(only(collect(conversation.turns)))
        end
    end
end
