# Fragment of `AgentModule` — the loop.

# Did a tool fail? A `Tool` reports failure in its text (it returns a `String`,
# because the reader is a language model), so this is a heuristic, and deliberately
# a generous one: it is used to mark a result as an error for the model, and a
# false positive costs a needlessly apologetic retry while a false negative lets the
# model build on a stack trace it thinks succeeded.
_is_error_output(output::AbstractString) =
    occursin("ERROR", output) || occursin("Error", output)

"""
    run_turn!(agent, target; messages, on_event, tools = Tool[]) -> stop_reason

Run one turn: stream a round from the model, run any tools it asked for, and go
again until it stops asking. Returns the stop reason of the final round
(`:end_turn`, `:tool_use` if the round cap cut it short, `:max_tokens`, `:error`).
A round whose stream ends with no `LlmTurnEnd` and no `LlmFailure` gives `:error`,
and the loop runs none of its tool calls.

- `target`   — what the tools act on, passed through to each handler untouched.
- `messages` — `() -> Vector{LlmMessage}`, called at the **start of every round**.
               A callback, not a list, on purpose: the caller already has the
               conversation, and each round's prompt is simply that conversation as
               it now stands — including the tool results just appended to it. A list
               the loop mutated would be a second copy of the transcript, free to
               drift from the caller's.
- `on_event` — called with every `LlmEvent` as it streams, and with an
               `AgentToolResult` for each tool that runs.
- `tools`    — tools of this turn beside the tool set of `agent`, such as a tool
               that asks the person of the caller, which no other client of the
               tool set may see.

A handler can answer a `Task` in place of its text, as a tool that waits for a
person does. The loop then waits for the task on its own task, not on the task
of the editor, so no frame waits with it, and the value of the task is the text
of the tool.

A tool that throws gives an `AgentToolResult` with `is_error = true`, and the
fault goes into the fault store of `target`. An exception that
[`is_passthrough_exception`](@ref) names goes through: `run_turn!` throws it and
sends no result.

Throws what `stream_turn`, `messages` and `on_event` throw.

Each tool call runs through [`run_on_editor_task!`](@ref) with `target`: on the
task of the editor's loop when one runs on another task, and at once otherwise.

The loop holds the *control flow* of a turn, and only that. It builds no messages
and renders no answer: the loop streams, runs the tools, and stops when the model
asks for no tool.
"""
function run_turn!(agent::Agent, target; messages, on_event, tools::AbstractVector{Tool} = Tool[])
    register_default_tools!(agent.tools)
    turn_tools = collect(Tool, tools)
    listed = vcat(list_tools(agent.tools), turn_tools)

    stop  = :end_turn
    round = 0
    while true
        round += 1
        if round > agent.max_rounds
            rounds = round - 1
            @warn "[agent] hit the round cap; ending the turn" agent.max_rounds rounds
            break
        end

        # Live state for this round. `stop` starts empty, and only a terminal
        # event of this round sets it.
        pending = LlmToolUse[]
        stop    = nothing

        @info "[agent] round $round: streaming"
        stream_turn(agent.llm,
                    LlmRequest(system   = agent.system,
                               messages = messages(),
                               tools    = listed,
                               thinking = agent.thinking);
                    on_event = ev -> begin
                        ev isa LlmToolUseStop && push!(pending, ev.tool_use)
                        ev isa LlmTurnEnd     && (stop = ev.stop_reason)
                        ev isa LlmFailure     && (stop = :error)
                        on_event(ev)
                        nothing
                    end)
        # A stream that ends with no terminal event did not finish its round.
        stop === nothing && (stop = :error)
        @info "[agent] round $round: done" stop tool_calls = length(pending)

        # The model is finished unless it is waiting on tools it asked for.
        (isempty(pending) || stop !== :tool_use) && break

        for call in pending
            @info "[agent] tool call" call.name
            # The loop runs on a task of its own, and a tool may write what the
            # editor shows, so the call runs on the editor's task.
            output, is_error = run_on_editor_task!(target) do
                try
                    turn_tool = findfirst(tool -> tool.name == call.name, turn_tools)
                    text = turn_tool === nothing ? call_tool(agent.tools, call.name; args = call.input, target) :
                           turn_tools[turn_tool].handler(target, call.input)
                    text isa Task ? (text, false) : (text, _is_error_output(text))
                catch e
                    is_passthrough_exception(e) && rethrow()
                    # A tool that throws is not a broken turn: the model gets the
                    # text of the error and can try something else. The fault is
                    # recorded as well, so a person reading the editor's log sees
                    # what the model ran into.
                    traceback = catch_backtrace()
                    record_fault!(get_fault_store(target), :tool;
                                  origin = Symbol(call.name), exception = e, traceback)
                    # A `showerror` method that throws gives the type name.
                    text = try
                        sprint(showerror, e, traceback)
                    catch exception
                        is_passthrough_exception(exception) && rethrow()
                        string(nameof(typeof(e)))
                    end
                    (text, true)
                end
            end
            output isa Task && ((output, is_error) = _wait_for_tool_task(output))
            on_event(AgentToolResult(call, output, is_error))
        end
    end
    stop
end

# A tool that answered a `Task` answers when the task ends, here on the task of
# the loop. The value of the task is the text of the tool, and a task that throws
# gives the text of its error, as a handler that throws does.
function _wait_for_tool_task(task::Task)
    text = try
        string(fetch(task))
    catch exception
        exception isa TaskFailedException || rethrow()
        failure = exception.task.exception
        is_passthrough_exception(failure) && throw(failure)
        return (sprint(showerror, failure), true)
    end
    (text, _is_error_output(text))
end
