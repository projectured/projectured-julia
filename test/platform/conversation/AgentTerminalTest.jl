# The terminals that an external agent runs in the editor, against a scripted
# agent that sends the five terminal requests: each command is a task alone that
# the assistant started, the tool call that shows it names the call in the row and
# shows the task in its card, a stop of the person ends a wait, and a release
# stops a command that runs and keeps its row.

# A step of a scripted agent that sends an `AgentTerminalRequest` of `method` for
# the terminal that `terminal()` names, waits at most 30 seconds for the reply,
# and pushes `method => answer` to `answers`, or `method => :no_answer`.
function _terminal_step(answers::Vector{Any}, method::Symbol; terminal = () -> "", options...)
    function (connection, on_event)
        answer = Channel{Any}(1)
        is_answered = Threads.Atomic{Bool}(false)
        reply = value -> (Threads.atomic_xchg!(is_answered, true) ? false : (put!(answer, value); true))
        push!(connection.waiting_replies, reply)
        on_event(AgentTerminalRequest("session-1", method, terminal(), reply; options...))
        value = timedwait(() -> isready(answer), 30.0; pollint = 0.01) === :ok ? take!(answer) : :no_answer
        filter!(waiting -> waiting !== reply, connection.waiting_replies)
        push!(answers, method => value)
        nothing
    end
end

# The answer of the `index`-th request of `method` in `answers`.
_terminal_answer(answers, method, index = 1) = last(filter(pair -> first(pair) === method, answers)[index])

# An assistant whose agent plays `turn` at its first prompt, in an editor of the
# window that runs no loop, so each event of the agent applies at once. The
# assistant draws as a tab of the application draws it: its split pane, then the
# natural renderer, which draws a task as its page.
function _make_terminal_assistant(turn)
    a = Assistant(; backend = :acp, agent_session = ExternalAgentSession(ScriptedAgentConnection([turn])))
    backend = HeadlessBackend()
    measure = FixedMeasure(8, 12, 4, 0)
    rows = Pair{Type,Any}[make_conversation_draft_row(; measure), make_conversation_row(; measure)]
    projection = ChainingProjection(RecursiveProjection(AssistantToWidgetSplitPane()),
                                    NaturalToGraphics(; measure, extra = rows))
    editor = EditorModule.build_editor(a, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                                       window = false, tabs = false, appearance = false, settings = false)
    (a, editor, backend)
end

function _submit_terminal_prompt!(editor, a::Assistant; wait::Bool = true)
    a.input.value = "Run it."
    evaluate_operation(editor, SubmitProseOperation(a))
    wait && @test timedwait(() -> a.status !== :streaming, 60.0; pollint = 0.01) === :ok
    nothing
end

# The row of the task list of `editor` that is the task of `terminal_id`.
_find_terminal_row(editor, terminal_id) = find_task_group(terminal_id; editor)

function test_agent_terminal()
    @testset "the terminals of an agent run in the editor" begin
        @testset "the five requests, a tool call that shows its terminal, and the cut of the output" begin
            answers = Any[]
            id = Ref("")
            short = Ref("")
            # The call of the agent shows the terminal that it created.
            function show_terminal(connection, on_event)
                id[] = _terminal_answer(answers, :create)
                on_event(AgentToolCallUpdate("tu_9"; name = "Bash", title = "echo", kind = :execute,
                                             status = :in_progress, terminal_ids = [id[]]))
            end
            turn = Any[
                _terminal_step(answers, :create; command = "sh",
                               arguments = ["-c", "echo terminal-line-one; echo two >&2; exit 3"],
                               directory = tempdir(), output_byte_limit = 1000),
                show_terminal,
                _terminal_step(answers, :wait_for_exit; terminal = () -> id[]),
                _terminal_step(answers, :output; terminal = () -> id[]),
                _terminal_step(answers, :kill; terminal = () -> id[]),
                # The end of the call keeps its terminal as its content.
                (connection, on_event) -> on_event(AgentToolCallUpdate("tu_9"; status = :completed,
                                                                       output = "[terminal $(id[])]",
                                                                       terminal_ids = [id[]])),
                # A two-byte letter is not cut in two.
                _terminal_step(answers, :create; command = "printf", arguments = ["aé"], directory = tempdir(),
                               output_byte_limit = 2),
                (connection, on_event) -> (short[] = _terminal_answer(answers, :create, 2)),
                _terminal_step(answers, :wait_for_exit; terminal = () -> short[]),
                _terminal_step(answers, :output; terminal = () -> short[]),
                _terminal_step(answers, :release; terminal = () -> id[]),
                _terminal_step(answers, :output; terminal = () -> id[])]
            a, editor, backend = _make_terminal_assistant(turn)
            _submit_terminal_prompt!(editor, a)
            @test occursin(r"^T\d+$", id[])
            row = _find_terminal_row(editor, id[])
            @test row isa TaskDocument
            # The row is a task alone that the assistant started, and it names the call.
            @test get_work_item_starter(row) == make_assistant_starter(a; tool_call = "tu_9")
            task = getfield(row, :task)[]
            @test task isa ProgramTask && task.arguments == ["sh", "-c", "echo terminal-line-one; echo two >&2; exit 3"]
            @test task.working_directory == tempdir()
            @test _terminal_answer(answers, :wait_for_exit) == (exit_code = 3, signal = nothing)
            @test _terminal_answer(answers, :output) ==
                  (output = "terminal-line-one\ntwo\n", truncated = false, exit_code = 3, signal = nothing)
            @test _terminal_answer(answers, :kill) === true
            @test _terminal_answer(answers, :output, 2) == (output = "\n", truncated = true, exit_code = 0, signal = nothing)
            # A release forgets the terminal, and the row stays.
            @test _terminal_answer(answers, :release) === true
            @test _terminal_answer(answers, :output, 3) isa ArgumentError
            @test !haskey(a.agent_session.terminals, id[]) && haskey(a.agent_session.terminals, short[])
            @test any(item -> item === row, collect_work_items(get_session_task_group_list(; editor)))
            # The card of the call shows the task, also after the end of the call.
            form = only(part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                        if part.content isa EvaluatorForm && part.content.tool_use_id == "tu_9")
            @test form.result === row
            # The window drains the feed of the tasks in each turn of its loop; here a
            # wait drains it, and a frame draws the card.
            wait_for_tasks!(row; timeout = 10, editor)
            EditorModule.run_frame!(editor)
            @test _work_page_has_text(backend, "terminal-line-one")
        end

        @testset "a stop of the person ends the command, and the wait of the agent answers" begin
            answers = Any[]
            id = Ref("")
            turn = Any[
                _terminal_step(answers, :create; command = "sh", arguments = ["-c", "exec sleep 30"],
                               directory = tempdir()),
                (connection, on_event) -> (id[] = _terminal_answer(answers, :create)),
                _terminal_step(answers, :wait_for_exit; terminal = () -> id[])]
            a, editor, _ = _make_terminal_assistant(turn)
            _submit_terminal_prompt!(editor, a; wait = false)
            @test timedwait(() -> !isempty(id[]), 30.0; pollint = 0.01) === :ok
            row = _find_terminal_row(editor, id[])
            @test timedwait(() -> getfield(row, :running)[] !== nothing &&
                                  is_task_running(getfield(row, :running)[]), 30.0; pollint = 0.01) === :ok
            # The person stops the row, as Stop of its page or of the Tasks pane does.
            stop_work_item!(row)
            @test timedwait(() -> a.status !== :streaming, 30.0; pollint = 0.01) === :ok
            @test _terminal_answer(answers, :wait_for_exit) == (exit_code = nothing, signal = "SIGINT")
            wait_for_tasks!(row; timeout = 10, editor)
            @test get_task_document_result(row).result == "CANCEL"
        end

        @testset "a release stops a command that runs, the row stays, and the end of the agent stops the rest" begin
            answers = Any[]
            id = Ref("")
            left = Ref("")
            turn = Any[
                _terminal_step(answers, :create; command = "sh", arguments = ["-c", "exec sleep 30"],
                               directory = tempdir()),
                (connection, on_event) -> (id[] = _terminal_answer(answers, :create)),
                _terminal_step(answers, :release; terminal = () -> id[]),
                _terminal_step(answers, :output; terminal = () -> id[]),
                _terminal_step(answers, :create; command = "sh", arguments = ["-c", "exec sleep 30"],
                               directory = tempdir()),
                (connection, on_event) -> (left[] = _terminal_answer(answers, :create, 2))]
            a, editor, _ = _make_terminal_assistant(turn)
            _submit_terminal_prompt!(editor, a)
            @test _terminal_answer(answers, :release) === true
            @test _terminal_answer(answers, :output) isa ArgumentError
            row = _find_terminal_row(editor, id[])
            @test row isa TaskDocument
            @test startswith(string(wait_for_tasks!(row; timeout = 10, editor)), "Ended: CANCEL")
            # A command that its agent did not release stops when the agent stops.
            other = _find_terminal_row(editor, left[])
            @test is_task_running(getfield(other, :running)[])
            stop_external_agent!(a)
            @test startswith(string(wait_for_tasks!(other; timeout = 10, editor)), "Ended: CANCEL")
            @test isempty(a.agent_session === nothing ? Dict() : a.agent_session.terminals)
            @test all(item -> any(other -> other === item, collect_work_items(get_session_task_group_list(; editor))),
                      (row, other))
        end
    end
end
