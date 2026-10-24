# An assistant whose wake is on starts a turn of its own when a group of tasks
# that one of its turns started ends, with a note that says why; three rules keep
# the word with the person.

# A group of one shell command that sleeps for `seconds`.
_make_wake_group(seconds) =
    wrap_task_group_document(TaskGroup([BuildCommandTask(; action = "Sleeping", subject = "wake",
                                                         working_directory = tempdir(),
                                                         arguments = ["sh", "-c", "sleep $(seconds)"],
                                                         input_files = String[], output_files = String[])];
                                       name = "sleep", jobs = 1); title = "the sleep")

# A tool set whose tool `start` starts `group` in the session of the editor.
function _make_wake_tools(group)
    set = register_default_tools!(ToolSet())
    register_tool!(set, Tool("start"; description = "a tool of the test", parameters = NamedTuple[],
                             handler = (editor, arguments) -> (start_task_group_document!(group; editor);
                                                               "started")))
    set
end

_make_wake_call_round() =
    make_scripted_turn(make_scripted_run(""; tool_id = "tu_1", tool_name = "start");
                       stop_reason = "tool_use")
_make_wake_answer_round(text) =
    make_scripted_turn(make_scripted_say(text; delay = 0); stop_reason = "end_turn")

# The kinds of the notes of the turns of `a`, one entry for each turn of notes.
_collect_wake_notes(a) =
    [only(collect(turn.parts)).content for turn in collect(a.conversation.turns) if is_note_turn(turn)]

function test_assistant_wake()
    @testset "the wake of an assistant" begin
        @testset "a group that a turn started wakes the assistant when it ends" begin
            group = _make_wake_group(1)
            llm = ScriptedLlm([_make_wake_call_round(), _make_wake_answer_round("It runs."),
                               _make_wake_answer_round("It ended.")])
            a = Assistant(; llm, wake = true)
            editor = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
                            tools = _make_wake_tools(group))
            a.input.value = "Start it."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test timedwait(() -> length(a.conversation.turns) >= 4 && a.status === :idle, 30.0;
                            pollint = 0.05) === :ok
            question, answer, wake, after = collect(a.conversation.turns)
            @test answer.stop_reason === :end_turn
            @test is_note_turn(wake) && wake.role === :user
            note = only(collect(wake.parts)).content
            @test note.kind === :wake
            @test startswith(note.text, "The task group \"the sleep\" ended: ")
            @test after.role === :assistant
            @test occursin("It ended.", AssistantModule._text_to_string(last(collect(after.parts)).content))
            # The model reads the note as the words of a turn of the person.
            messages = build_messages(a.conversation)
            @test any(message -> message.role === :user && occursin("ended: ", string(message.content)),
                      messages)
        end

        @testset "an assistant whose wake is off does not wake" begin
            group = _make_wake_group(0.2)
            llm = ScriptedLlm([_make_wake_call_round(), _make_wake_answer_round("It runs.")])
            a = Assistant(; llm)
            editor = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
                            tools = _make_wake_tools(group))
            a.input.value = "Start it."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test timedwait(() -> a.status === :idle && length(a.conversation.turns) == 2, 30.0;
                            pollint = 0.05) === :ok
            wait_task_group_document(group)
            sleep(0.3)
            @test length(a.conversation.turns) == 2
        end

        @testset "an external agent gets the note as the prompt of a turn" begin
            group = _make_wake_group(0)
            start_task_group_document!(group)
            wait_task_group_document(group)
            connection = ScriptedAgentConnection([Any[LlmTextStart(), LlmTextDelta("Seen."), LlmTextStop()]])
            a = Assistant(; backend = :acp, agent_session = ExternalAgentSession(connection), wake = true,
                          conversation = ConversationConversation([
                              ConversationTurn(:user, [ConversationPart("Run it.")]),
                              ConversationTurn(:assistant, [ConversationPart("It runs.")])]))
            wake_assistant!((document = a,), a, group)
            @test timedwait(() -> a.status !== :streaming && length(a.conversation.turns) == 4, 10.0;
                            pollint = 0.01) === :ok
            prompt = only(connection.prompts)
            @test length(prompt) == 1 && startswith(only(prompt).text, "The task group \"the sleep\" ended: ")
        end

        @testset "the person keeps the word" begin
            group = _make_wake_group(0)
            start_task_group_document!(group)
            wait_task_group_document(group)
            editor = (document = nothing, tools = register_default_tools!(ToolSet()))
            person = ConversationTurn(:user, [ConversationPart("Run it.")])

            # A stop of the person: the note shows, and no turn starts.
            stopped = ConversationTurn(:assistant, [ConversationPart("Half")]; stop_reason = :cancelled)
            a = Assistant(; llm = FakeLlm("no"), wake = true,
                          conversation = ConversationConversation([person, stopped]))
            wake_assistant!(editor, a, group)
            @test length(_collect_wake_notes(a)) == 1 && a.status === :idle
            @test length(a.conversation.turns) == 3

            # A message that the person types.
            a = Assistant(; llm = FakeLlm("no"), wake = true,
                          conversation = ConversationConversation([
                              ConversationTurn(:user, [ConversationPart("Run it.")])]))
            a.draft.parts[1] = ConversationPart(PrimitiveString("I am typing"))
            wake_assistant!(editor, a, group)
            @test length(a.conversation.turns) == 2 && a.status === :idle

            # The limit of wakes after one turn of the person.
            turns = Any[ConversationTurn(:user, [ConversationPart("Run it.")])]
            for _ in 1:ASSISTANT_WAKE_LIMIT
                push!(turns, ConversationTurn(:user, [ConversationPart(ConversationNote("ended"; kind = :wake))]))
                push!(turns, ConversationTurn(:assistant, [ConversationPart("Again.")]))
            end
            a = Assistant(; llm = FakeLlm("no"), wake = true, conversation = ConversationConversation(turns))
            wake_assistant!(editor, a, group)
            @test length(a.conversation.turns) == length(turns) + 1 && a.status === :idle

            # Off, a wake does nothing.
            a = Assistant(; llm = FakeLlm("no"))
            wake_assistant!(editor, a, group)
            @test isempty(collect(a.conversation.turns))
        end
    end
end
