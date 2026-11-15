# Fragment of `AssistantModule` — the terminals that the external agent of an
# assistant runs in the editor. The command of each terminal is a task alone, a row
# of the task list that the assistant started; the tool call whose content shows
# the terminal is the call that the row names, and the card of that call shows the
# task while it runs.

# A terminal of the session of an agent: the task that runs its command, and the
# count of bytes of its output that an answer keeps, or `nothing` for all.
struct _AgentTerminal
    document::TaskDocument
    output_byte_limit::Union{Nothing,Int}
end

# One terminal request of the agent of `a`, on the editor task. The request names a
# terminal of the session by the identifier of its row. A wait for the end of a
# command answers on a task of its own, so no frame waits for it.
function _apply_agent_terminal_request!(editor, a::Assistant, request::AgentTerminalRequest)
    session = a.agent_session
    try
        session isa ExternalAgentSession || throw(ArgumentError("The assistant has no session of an agent."))
        request.method === :create && return (request.reply(_create_agent_terminal!(editor, a, session, request));
                                              nothing)
        terminal = get(session.terminals, request.terminal_id, nothing)
        terminal === nothing &&
            throw(ArgumentError(string("No terminal `", request.terminal_id, "` is open in this session.")))
        if request.method === :output
            request.reply(_read_agent_terminal_output(terminal))
        elseif request.method === :wait_for_exit
            _reply_at_agent_terminal_exit(request, terminal.document)
        elseif request.method === :kill
            stop_task!(terminal.document)
            request.reply(true)
        else
            # A release forgets the terminal, and the row of its task stays.
            delete!(session.terminals, request.terminal_id)
            stop_task!(terminal.document)
            request.reply(true)
        end
    catch exception
        is_fault_exception(exception) || rethrow()
        request.reply(exception)
    end
    nothing
end

# The command of a request as a task alone that `a` starts, in the folder that the
# request names or else in the folder of the session; answers the identifier of
# its row, which is the id of the terminal. A start that throws adds no row.
function _create_agent_terminal!(editor, a::Assistant, session::ExternalAgentSession,
                                 request::AgentTerminalRequest)
    words = String[request.command; request.arguments]
    directory = something(request.directory, isempty(session.directory) ? pwd() : session.directory)
    program = ProgramTask(words; working_directory = directory, environment = Dict(request.environment),
                          name = basename(request.command))
    document = run_with_evaluation_starter(make_assistant_starter(a)) do
        run_tasks!(program; title = join(words, " "), editor)
    end
    terminal_id = get_work_item_identifier(document)
    session.terminals[terminal_id] = _AgentTerminal(document, request.output_byte_limit)
    terminal_id
end

# What the command of a terminal printed so far, stdout and then stderr, as its
# execution holds the lines, cut at its start to the limit of the terminal, and
# the exit status of a command that ended.
function _read_agent_terminal_output(terminal::_AgentTerminal)
    execution = getfield(terminal.document, :running)[]
    execution === nothing && return (output = "", truncated = false, exit_code = nothing, signal = nothing)
    (output, error_output, has_ended) = lock(execution.runtime.lock) do
        (copy(execution.output), copy(execution.error_output), execution.result !== nothing)
    end
    (text, is_cut) = _cut_agent_terminal_output(format_output_text(output) * format_output_text(error_output),
                                                terminal.output_byte_limit)
    truncated = is_cut || get_left_out_line_count(output) > 0 || get_left_out_line_count(error_output) > 0
    status = has_ended ? _get_agent_terminal_exit(execution) : (exit_code = nothing, signal = nothing)
    (output = text, truncated = truncated, exit_code = status.exit_code, signal = status.signal)
end

# The end of `text` within `limit` bytes, which starts at a character, and whether
# it is cut.
function _cut_agent_terminal_output(text::String, limit::Union{Nothing,Int})
    (limit === nothing || ncodeunits(text) <= limit) && return (text, false)
    start = ncodeunits(text) - max(limit, 0) + 1
    while start <= ncodeunits(text) && !isvalid(text, start)
        start += 1
    end
    (start > ncodeunits(text) ? "" : text[start:end], true)
end

# The exit code of the process of an execution that ended, or the name of the
# signal that ended it.
function _get_agent_terminal_exit(execution)
    process = execution.runtime.process
    if process !== nothing
        process.termsignal != 0 && return (exit_code = nothing, signal = _describe_signal(process.termsignal))
        return (exit_code = Int(process.exitcode), signal = nothing)
    end
    result = execution.result
    (exit_code = result isa ProgramResult ? result.exit_code : nothing, signal = nothing)
end

const _SIGNAL_NAMES = Dict(1 => "SIGHUP", 2 => "SIGINT", 3 => "SIGQUIT", 6 => "SIGABRT", 9 => "SIGKILL",
                           13 => "SIGPIPE", 15 => "SIGTERM")

_describe_signal(number::Integer) = get(_SIGNAL_NAMES, Int(number), string(number))

# The reply of a wait comes from a task of its own when the execution of the
# terminal ends: after its process ended and its streams were read.
function _reply_at_agent_terminal_exit(request::AgentTerminalRequest, document::TaskDocument)
    execution = getfield(document, :running)[]
    execution === nothing && throw(ArgumentError(string("The command of terminal `", request.terminal_id,
                                                        "` did not start.")))
    errormonitor(Threads.@spawn :default begin
        try
            wait_task_execution(execution)
            request.reply(_get_agent_terminal_exit(execution))
        catch exception
            request.reply(exception)
            is_fault_exception(exception) || rethrow()
        end
    end)
    nothing
end

# A tool call whose content shows terminals of the session: the row of each names
# the call, and the card of the call shows the task, which follows it while it
# runs. The task stays the result of the card when a later update repeats its
# content.
function _show_agent_terminals!(a::Assistant, state, update::AgentToolCallUpdate)
    session = a.agent_session
    session isa ExternalAgentSession || return nothing
    form = get(state[:tool_forms], update.id, nothing)
    for terminal_id in update.terminal_ids
        terminal = get(session.terminals, terminal_id, nothing)
        terminal === nothing && continue
        document = terminal.document
        _name_terminal_tool_call!(document, update.id)
        form === nothing && continue
        form.result === document || (form.result = document)
        push!(state[:live_results], update.id)
    end
    nothing
end

# The row of a terminal records the tool call that shows it, once: the request
# that started it came before the call named it.
function _name_terminal_tool_call!(document::TaskDocument, call_id::AbstractString)
    starter = getfield(document, :started_by)[]
    (starter isa WorkStarter && starter.kind === :assistant && isempty(starter.tool_call)) || return nothing
    document.started_by = WorkStarter(:assistant; identifier = starter.identifier, name = starter.name,
                                      tool_call = call_id)
    nothing
end

# The terminals of a session whose connection ended: each command that runs stops,
# the ids go, and the rows stay.
function _release_agent_terminals!(session::ExternalAgentSession)
    foreach(terminal -> stop_task!(terminal.document), values(session.terminals))
    empty!(session.terminals)
    nothing
end
