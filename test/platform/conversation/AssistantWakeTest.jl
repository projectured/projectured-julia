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

# A tool set whose tool `start` starts a program that sleeps for a second, with
# the verb `run_tasks!`.
function _make_wake_program_tools()
    set = register_default_tools!(ToolSet())
    register_tool!(set, Tool("start"; description = "a tool of the test", parameters = NamedTuple[],
                             handler = (editor, arguments) -> begin
        program = ProgramTask(`sh -c "sleep 1"`; working_directory = tempdir(), name = "sleep")
        run_tasks!(TaskGroup([program]; name = "sleep", jobs = 1); title = "the sleep", editor)
        "started"
    end))
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
            @test a.wakes_left == ASSISTANT_WAKE_LIMIT - 1
            @test occursin("It ended.", AssistantModule._text_to_string(last(collect(after.parts)).content))
            # The model reads the note as the words of a turn of the person.
            messages = build_messages(a.conversation)
            @test any(message -> message.role === :user && occursin("ended: ", string(message.content)),
                      messages)
        end

        @testset "a group that run_tasks! started wakes the assistant when it ends" begin
            llm = ScriptedLlm([_make_wake_call_round(), _make_wake_answer_round("It runs."),
                               _make_wake_answer_round("It ended.")])
            a = Assistant(; llm, wake = true)
            editor = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[],
                            tools = _make_wake_program_tools())
            a.input.value = "Start it."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test timedwait(() -> length(a.conversation.turns) >= 4 && a.status === :idle, 30.0;
                            pollint = 0.05) === :ok
            wake = collect(a.conversation.turns)[3]
            @test is_note_turn(wake)
            note = only(collect(wake.parts)).content
            @test note.kind === :wake
            @test startswith(note.text, "The task group \"the sleep\" ended: ")
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
            a.wakes_left = 1
            wake_assistant!((document = a,), a, group)
            @test timedwait(() -> a.status !== :streaming && length(a.conversation.turns) == 4, 10.0;
                            pollint = 0.01) === :ok
            prompt = only(connection.prompts)
            @test length(prompt) == 1 && startswith(only(prompt).text, "The task group \"the sleep\" ended: ")
        end

        @testset "a message gives at least the limit, and keeps a larger count" begin
            a = Assistant(; llm = FakeLlm("ok"))
            editor = Editor(a, IdentityProjection(); backend = HeadlessBackend(), devices = Device[])
            @test a.wakes_left == 0
            a.input.value = "One."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test a.wakes_left == ASSISTANT_WAKE_LIMIT
            @test timedwait(() -> a.status === :idle, 30.0; pollint = 0.05) === :ok
            a.wakes_left = 70
            a.input.value = "Two."
            evaluate_operation(editor, SubmitProseOperation(a))
            @test a.wakes_left == 70
            @test timedwait(() -> a.status === :idle, 30.0; pollint = 0.05) === :ok
        end

        @testset "a stop of a turn sets the count to 0" begin
            a = Assistant(; llm = FakeLlm("ok"))
            a.wakes_left = 5
            evaluate_operation((document = a,), CancelAssistantTurnOperation(a))
            @test a.wakes_left == 5          # no turn runs: nothing stops
            a.status = :streaming
            evaluate_operation((document = a,), CancelAssistantTurnOperation(a))
            @test a.wakes_left == 0
        end

        @testset "a file keeps no count of wakes, and a fork starts at 0" begin
            a = Assistant(; wake = true)
            a.wakes_left = 9
            @test !occursin("wakes_left", print_pred_text(a))
            @test parse_pred_text(print_pred_text(a)).wakes_left == 0
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

            # No wake left.
            a = Assistant(; llm = FakeLlm("no"), wake = true,
                          conversation = ConversationConversation([person]))
            wake_assistant!(editor, a, group)
            @test length(a.conversation.turns) == 2 && a.status === :idle && a.wakes_left == 0

            # Off, a wake does nothing.
            a = Assistant(; llm = FakeLlm("no"))
            wake_assistant!(editor, a, group)
            @test isempty(collect(a.conversation.turns))
        end
    end
end
