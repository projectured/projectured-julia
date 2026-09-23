# Fragment of `AgentModule` — the loop.

# Did a tool fail? A `Tool` reports failure in its text (it returns a `String`,
# because the reader is a language model), so this is a heuristic, and deliberately
# a generous one: it is used to mark a result as an error for the model, and a
# false positive costs a needlessly apologetic retry while a false negative lets the
# model build on a stack trace it thinks succeeded.
_is_error_output(output::AbstractString) =
    occursin("ERROR", output) || occursin("Error", output)

"""
    run_turn!(agent, target; messages, on_event) -> stop_reason

Run one turn: stream a round from the model, run any tools it asked for, and go
again until it stops asking. Returns the stop reason of the final round
(`:end_turn`, `:tool_use` if the round cap cut it short, `:max_tokens`, `:error`).

- `target`   — what the tools act on, passed through to each handler untouched (an
               `Editor`, in practice).
- `messages` — `() -> Vector{LlmMessage}`, called at the **start of every round**.
               A callback, not a list, on purpose: the caller already has the
               conversation, and each round's prompt is simply that conversation as
               it now stands — including the tool results just appended to it. A list
               the loop mutated would be a second copy of the transcript, free to
               drift from the caller's.
- `on_event` — called with every `LlmEvent` as it streams, and with an
               `AgentToolResult` for each tool that runs.

Each tool call runs through [`run_on_editor_task!`](@ref) with `target`: on the
task of the editor's loop when one runs on another task, and at once otherwise.

The loop is where a turn's *control flow* lives, and only that. It builds no
messages and renders no answer; it streams, dispatches, and decides whether to go
around again.
"""
function run_turn!(agent::Agent, target; messages::Function, on_event::Function)
    register_default_tools!(agent.tools)
    tools = list_tools(agent.tools)

    stop  = :end_turn
    round = 0
    while true
        round += 1
        if round > agent.max_rounds
            @warn "[agent] hit the round cap; ending the turn" agent.max_rounds rounds = round - 1
            break
        end

        # Live state for this round. `stop` resets: a round that ended in `:tool_use`
        # must not be mistaken for the next one's outcome.
        pending = LlmToolUse[]
        stop    = :end_turn

        @info "[agent] round $round: streaming"
        stream_turn(agent.llm,
                    LlmRequest(system   = agent.system,
                               messages = messages(),
                               tools    = tools,
                               thinking = agent.thinking);
                    on_event = ev -> begin
                        ev isa LlmToolUseStop && push!(pending, ev.tool_use)
                        ev isa LlmTurnEnd     && (stop = ev.stop_reason)
                        ev isa LlmFailure     && (stop = :error)
                        on_event(ev)
                        nothing
                    end)
        @info "[agent] round $round: done" stop tool_calls = length(pending)

        # The model is finished unless it is waiting on tools it asked for.
        (isempty(pending) || stop !== :tool_use) && break

        for call in pending
            @info "[agent] tool call" call.name
            # The loop runs on a task of its own, and a tool may write what the
            # editor shows, so the call runs on the editor's task, as the call of
            # an MCP client does.
            output = run_on_editor_task!(target) do
                try
                    call_tool(agent.tools, call.name; args = call.input, target)
                catch e
                    # A tool that throws is not a broken turn: the model is told
                    # what went wrong and can try something else, which is the
                    # whole point of giving it tools it can misuse. The fault is
                    # recorded as well, so a person reading the editor's log sees
                    # what the model ran into.
                    traceback = catch_backtrace()
                    record_fault!(get_fault_store(target), :tool; origin = Symbol(call.name),
                                  exception = e, traceback)
                    sprint(showerror, e, traceback)
                end
            end
            on_event(AgentToolResult(call, output, _is_error_output(output)))
        end
    end
    stop
end
