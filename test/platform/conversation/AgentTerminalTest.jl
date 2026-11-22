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

# The steps of an agent that runs `command` with its Bash tool, in the order of
# Claude Code over ACP: the call with its title and its input, the terminal that
# runs `bash -c` with the command, the update that shows the terminal, the wait for
# the end of the command, and the end of the call, which answers `answered`, or
# the name of the terminal. `after` are the steps that follow, such as the text of
# the answer.
function _command_steps(answers::Vector{Any}, id::Ref{String}, command::AbstractString;
                        title::AbstractString, after = Any[], answered = nothing)
    call(; options...) = (connection, on_event) -> on_event(AgentToolCallUpdate("tu_c"; options...))
    vcat(Any[call(; name = "mcp__claude_code_acp__Bash", title, kind = :execute, status = :pending,
                  input = Dict{String,Any}("command" => command, "description" => title)),
             _terminal_step(answers, :create; command = "bash", arguments = ["-c", command],
                            directory = tempdir()),
             function (connection, on_event)
                 id[] = _terminal_answer(answers, :create)
                 on_event(AgentToolCallUpdate("tu_c"; status = :in_progress, terminal_ids = [id[]]))
             end,
             _terminal_step(answers, :wait_for_exit; terminal = () -> id[]),
             (connection, on_event) -> on_event(AgentToolCallUpdate("tu_c"; status = :completed,
                                                                    output = something(answered,
                                                                                       "[terminal $(id[])]"),
                                                                    terminal_ids = [id[]]))],
         after)
end

# The vertical place of the one text of the last frame that is `text`.
function _command_text_y(backend, text)
    places = [entry[3] for entry in _work_page_texts(backend) if entry[1] == text]
    length(places) == 1 || error("the frame draws \"", text, "\" ", length(places), " times")
    only(places)
end

# The texts of the last frame.
_command_words(backend) = String[entry[1] for entry in _work_page_texts(backend)]

# Whether the last frame draws `text` on the line at `y`.
_command_draws_at(backend, text, y) = any(entry -> entry[1] == text && entry[3] == y, _work_page_texts(backend))

# A click on the text `text` on the line at `y`.
function _command_click_at(backend, text, y)
    (_, x, _) = only(entry for entry in _work_page_texts(backend) if entry[1] == text && entry[3] == y)
    MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)
end

# The part of the call `tu_c` in the conversation of `a`.
_command_part(a) = only(part for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                        if _is_command_part(part.content))
_is_command_part(content) = _has_call_id(content, "tu_c")

# Whether `content` is the call `id`, or a command of that call.
function _has_call_id(content, id)
    call = hasproperty(content, :call) ? content.call : content
    hasproperty(call, :tool_use_id) && call.tool_use_id == id
end

# A click on the middle of the chevron of the card whose title starts with
# `title`: the glyph left of the title, on its line, open or folded.
function _command_chevron_click(backend, title)
    texts = _work_page_texts(backend)
    (_, x, y) = only(entry for entry in texts if startswith(entry[1], title))
    (_, cx, cy) = last(sort([entry for entry in texts
                             if entry[1] in ("\ue06d", "\ue06f") && entry[2] < x && abs(entry[3] - y) <= 2];
                            by = entry -> entry[2]))
    MouseClick(:left, cx + 6, cy + 2, 1, ModifierKeys(); time = 0.0)
end

# The operation that the editor reads from `click`, which it does not evaluate.
function _command_click_operation(editor, backend, click)
    ProjecturedKernelExample.push_event!(backend, click)
    EditorModule.run_read_stage!(editor)
    editor.operation
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
            # The call is a command, which shows the task, also after the end of the call.
            command = only(part.content for turn in collect(a.conversation.turns) for part in collect(turn.parts)
                           if _has_call_id(part.content, "tu_9"))
            @test hasproperty(command, :task) && command.task === row
            # The window drains the feed of the tasks in each turn of its loop; here a
            # wait drains it, and a frame draws the card.
            wait_for_tasks!(row; timeout = 10, editor)
            EditorModule.run_frame!(editor)
            @test _work_page_has_text(backend, "terminal-line-one")
        end

        @testset "the card of a command: its title, state and row, the command one time, and its last lines" begin
            answers = Any[]
            id = Ref("")
            command = "seq -f line-%02g 1 12"
            a, editor, backend = _make_terminal_assistant(_command_steps(answers, id, command;
                                                                         title = "Print twelve lines"))
            _submit_terminal_prompt!(editor, a)
            row = _find_terminal_row(editor, id[])
            wait_for_tasks!(row; timeout = 10, editor)
            EditorModule.run_frame!(editor)
            words = _command_words(backend)
            # The header: the title, the state and the row, on one line.
            y = _command_text_y(backend, "Print twelve lines")
            @test _command_draws_at(backend, "DONE", y)
            @test _command_draws_at(backend, id[], y)
            # The command one time, as the agent wrote it, under the header.
            line = "\$ " * command
            @test _command_text_y(backend, line) > y
            @test count(word -> occursin(command, word), words) == 1
            @test !any(word -> occursin("bash -c", word) || occursin("mcp__", word), words)
            # No other fact of the task.
            @test isempty(intersect(words, ["Run again", "folder", "exit code", "Process", "arguments", "result"]))
            @test !_command_draws_at(backend, "Stop", y)
            # The count of the lines, and the last 8 lines under it, in their order.
            count_y = _command_text_y(backend, "stdout · 12 lines")
            @test count_y > _command_text_y(backend, line)
            places = [_command_text_y(backend, string("line-", lpad(n, 2, '0'))) for n in 5:12]
            @test issorted(places) && first(places) > count_y
            @test !any(word -> word in ("line-01", "line-04"), words)
            # The tree names the command by its title, and the text of the
            # conversation writes its title, its command and its result.
            part = _command_part(a)
            @test format_tree_node_label(part.content) == "Print twelve lines"
            @test occursin("# Print twelve lines\n$line\n= DONE", AssistantModule.format_conversation(a.conversation))
            # A press on the count opens the page of every line of stdout, and a
            # press on the row opens the page of the task; the editor opens each
            # in a new tab, as no navigator is around the transcript.
            open_lines = _command_click_operation(editor, backend,
                                                  _work_page_click(backend, "stdout · 12 lines"; exact = true))
            @test open_lines isa OpenPageOperation && open_lines.document === row &&
                  last(get_reference_steps(strip_reference_types(open_lines.reference))) ==
                  FieldReferenceStep("stdout_page")
            open_row = _command_click_operation(editor, backend, _command_click_at(backend, id[], y))
            @test open_row isa OpenPageOperation && open_row.document === row &&
                  open_row.reference isa EmptyReference
            # A press on the chevron folds the card, and the command keeps the
            # choice of the person.
            _work_page_press!(editor, backend, _command_chevron_click(backend, "Print twelve lines"))
            @test part.content.fold === :folded
            @test _command_draws_at(backend, "DONE", _command_text_y(backend, "Print twelve lines"))
            @test !_work_page_has_text(backend, "line-12")
        end

        @testset "a command in a file keeps its call, its command and its fold, and not its task" begin
            answers = Any[]
            id = Ref("")
            command = "seq -f line-%02g 1 12"
            answered = join([string("line-", lpad(n, 2, '0')) for n in 1:12], "\n")
            a, editor, _ = _make_terminal_assistant(_command_steps(answers, id, command;
                                                                   title = "Print twelve lines", answered))
            _submit_terminal_prompt!(editor, a)
            wait_for_tasks!(_find_terminal_row(editor, id[]); timeout = 10, editor)
            text = print_pred_text(_command_part(a).content)
            @test !occursin("ProgramTask", text)
            loaded = parse_pred_text(text)
            @test print_pred_text(loaded) == text
            # A loaded command shows its title, its command and the last lines of
            # the text that its call answered, and no state and no row.
            _, backend = _work_page_editor(loaded)
            words = _command_words(backend)
            y = _command_text_y(backend, "Print twelve lines")
            @test _command_text_y(backend, "\$ " * command) > y
            @test all(n -> string("line-", lpad(n, 2, '0')) in words, 5:12)
            @test !("line-04" in words)
            @test !any(word -> word in ("DONE", id[]), words)
        end

        @testset "a command that fails shows its reason under the header, and only a stream that has lines" begin
            answers = Any[]
            id = Ref("")
            a, editor, backend = _make_terminal_assistant(_command_steps(answers, id, "echo oops >&2; exit 3";
                                                                         title = "Fail on purpose"))
            _submit_terminal_prompt!(editor, a)
            row = _find_terminal_row(editor, id[])
            wait_for_tasks!(row; timeout = 10, editor)
            EditorModule.run_frame!(editor)
            y = _command_text_y(backend, "Fail on purpose")
            @test _command_draws_at(backend, "ERROR", y)
            @test _command_text_y(backend, "Non-zero exit code: 3") > y
            @test _command_text_y(backend, "oops") > _command_text_y(backend, "stderr · 1 line")
            @test !any(word -> startswith(word, "stdout"), _command_words(backend))
        end

        @testset "Stop shows while the command runs, and a press stops it" begin
            answers = Any[]
            id = Ref("")
            a, editor, backend = _make_terminal_assistant(_command_steps(answers, id, "exec sleep 30";
                                                                         title = "Wait a while"))
            _submit_terminal_prompt!(editor, a; wait = false)
            @test timedwait(() -> !isempty(id[]) && hasproperty(_command_part(a).content, :task), 30.0;
                            pollint = 0.01) === :ok
            row = _find_terminal_row(editor, id[])
            @test timedwait(() -> getfield(row, :running)[] !== nothing &&
                                  is_task_running(getfield(row, :running)[]), 30.0; pollint = 0.01) === :ok
            EditorModule.run_frame!(editor)
            y = _command_text_y(backend, "Wait a while")
            @test _command_draws_at(backend, "Stop", y)
            _work_page_press!(editor, backend, _command_click_at(backend, "Stop", y))
            @test timedwait(() -> a.status !== :streaming, 30.0; pollint = 0.01) === :ok
            @test _terminal_answer(answers, :wait_for_exit) == (exit_code = nothing, signal = "SIGINT")
            wait_for_tasks!(row; timeout = 10, editor)
            EditorModule.run_frame!(editor)
            y = _command_text_y(backend, "Wait a while")
            @test _command_draws_at(backend, "CANCEL", y)
            @test !_command_draws_at(backend, "Stop", y)
        end

        @testset "the work line of a finished turn counts a command as a tool call" begin
            answers = Any[]
            id = Ref("")
            after = Any[LlmTextStart(), LlmTextDelta("Printed."), LlmTextStop()]
            a, editor, backend = _make_terminal_assistant(_command_steps(answers, id, "echo one";
                                                                         title = "Print one line", after))
            _submit_terminal_prompt!(editor, a)
            wait_for_tasks!(_find_terminal_row(editor, id[]); timeout = 10, editor)
            EditorModule.run_frame!(editor)
            words = _command_words(backend)
            @test any(word -> startswith(word, "Work: 1 tool call"), words)
            # The work line starts folded, so the card of the command does not show.
            @test !("Print one line" in words)
            # In a work line that a person opened, each part of the work starts
            # folded by the rule of the transcript.
            _work_page_press!(editor, backend, _command_chevron_click(backend, "Work: 1 tool call"))
            words = _command_words(backend)
            @test "Print one line" in words
            # @broken: the rule of the transcript is a print property of the parts that the turn prints, and the transcript embeds a command, which the layout prints later without it, so the card of a command starts open (plan a-command-of-an-agent-is-a-short-card, proposed decision 9; question to the owner)
            @test_broken !("\$ echo one" in words)
            @test _command_part(a).content.fold === :default
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
