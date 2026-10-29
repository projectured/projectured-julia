# Fragment of `AssistantModule` — one turn of an external agent that a compile
# workload gives the assistant of a window, with no agent. Its events take the path
# of the events of a connection, through the queue of a session and the feed of the
# window, so a recording sees the calls of a turn, and the loop of a window does
# not compile them while an agent works.

"""
    warm_assistant_turn!(editor, assistant) -> assistant

Give `assistant`, which the window of `editor` shows, one turn of an external
agent, with no agent and no process. A session with no connection gets a queue
that joins the feed of the window, the events of the turn go into the queue as a
connection puts them, and the editor wakes. The frames that follow apply them
([`apply_agent_event!`](@ref)). Call it on the task of the editor.

The turn holds a thinking block, Markdown text with a list and a code block, a
`search_api` call with a Markdown answer, a permission request to run a command,
which stays open, an `execute_julia_code` call whose code comes in a later
update, with its result, and the answer, which says `33.5`. The code comes last
but one, because a pane follows the end of a turn, so the code is in view. The
turn ends at the usage that the agent reports, as a turn that an agent starts by
itself ends. The assistant keeps the session, so only a window that its
workload closes afterwards takes the turn.

Only a compile workload calls it, as the step `WorkloadAgentTurn` of a window
workload. No path that a person starts calls it.

# Example

    warm_assistant_turn!(editor, assistant)
"""
function warm_assistant_turn!(editor, a::Assistant)
    session = ExternalAgentSession(nothing)
    a.agent_session = session
    queue = _make_agent_event_queue!(editor, a, session)
    push!(a.conversation.turns, _make_instant_turn(:user, [ConversationPart(_WARM_PROMPT)]))
    foreach(event -> put_agent_event!(queue, event), _make_warm_turn_events())
    wake_editor!(editor)
    a
end

const _WARM_PROMPT = "Run the Fifo configuration twice, and tell me the mean length of the queue."

const _WARM_THINKING = """
The person asks for two runs of one configuration and for one number of their results.
I open a Runner over the project, select the configuration, and read the scalars.
"""

const _WARM_TEXT = """
I open a **Runner** over the project and select the `Fifo` configuration:

- two repetitions, as you asked;
- the scalar `queueLength:timeavg` of each run.

```julia
runner = open_runner!(find_simulation_projects()[1])
```
"""

const _WARM_CODE = """
runner_1 = open_runner!(find_simulation_projects()[1])
select_simulations!(runner_1; config = "Fifo", repetitions = 2)
lengths_1 = [x^2 + 0.5 for x in 1:10 if isodd(x)]
for (index, value) in enumerate(lengths_1)
    println("run ", index, ": ", value, ' ', :done)
end
result_1 = (count = length(lengths_1), mean = sum(lengths_1) / length(lengths_1))
names_1 = Dict("queue" => 1, :sink => nothing, 3 => [true, false])
label_1 = isempty(lengths_1) ? "none" : "first \$(first(lengths_1))"
@show result_1 label_1
"""

const _WARM_CODE_OUTPUT = "run 1: 1.5 done\nrun 2: 9.5 done\nresult_1 = (count = 5, mean = 33.5)\n"

const _WARM_SEARCH_OUTPUT = """
## select_simulations!

    select_simulations!(runner; config, repetitions)

Selects the runs of `config` in `runner`, `repetitions` times each.
"""

const _WARM_ANSWER = "The mean length of the queue is **33.5** over the two runs.\n"

# The events of the turn, in the order in which an agent sends them. Text and
# thinking come in pieces, and the code of a tool call comes in an update after
# the call opens, as Claude Code sends it.
function _make_warm_turn_events()
    pieces(text) = [line * "\n" for line in split(chomp(text), '\n')]
    Any[LlmThinkingStart(),
        (LlmThinkingDelta(piece) for piece in pieces(_WARM_THINKING))...,
        LlmThinkingStop(),
        LlmTextStart(),
        (LlmTextDelta(piece) for piece in pieces(_WARM_TEXT))...,
        LlmTextStop(),
        AgentToolCallUpdate("warm-search"; name = "mcp__projectured__search_api", title = "search_api",
                            kind = :search, status = :pending,
                            input = Dict{String,Any}("query" => "select the runs of a configuration")),
        AgentToolCallUpdate("warm-search"; status = :completed, output = _WARM_SEARCH_OUTPUT,
                            output_mime_type = "text/markdown"),
        AgentToolCallUpdate("warm-command"; name = "Bash", title = "make -C samples/fifo",
                            kind = :execute, status = :pending,
                            input = Dict{String,Any}("command" => "make -C samples/fifo")),
        AgentPermissionRequest(AgentToolCallUpdate("warm-command"; name = "Bash",
                                                   title = "make -C samples/fifo", kind = :execute),
                               [AgentPermissionOption("allow", "Allow", :allow_once),
                                AgentPermissionOption("reject", "Reject", :reject_once)],
                               _ -> true),
        AgentToolCallUpdate("warm-code"; name = "mcp__projectured__execute_julia_code",
                            title = "execute_julia_code", kind = :other, status = :pending,
                            input = Dict{String,Any}()),
        AgentToolCallUpdate("warm-code"; status = :in_progress,
                            input = Dict{String,Any}("code" => _WARM_CODE)),
        AgentToolCallUpdate("warm-code"; status = :completed, output = _WARM_CODE_OUTPUT),
        LlmTextStart(),
        (LlmTextDelta(piece) for piece in pieces(_WARM_ANSWER))...,
        LlmTextStop(),
        AgentUsageUpdate(12_000, 200_000, nothing, "")]
end
