# Fragment of `AssistantModule` — what the table of the assistants reads from one
# assistant: its title, its first and its last prompt, how many prompts it has,
# whose turn it is, what the turn that runs does, and the times of its turns.
# Each read goes through cells, so a view that calls one draws again when the
# assistant changes.

"""
    compute_assistant_overview_title(assistant) -> String

The title of `assistant` in the table of the assistants: the title that its
agent gave the session, else the first line of the first prompt that holds
text, else "Assistant".
"""
function compute_assistant_overview_title(a::Assistant)
    isempty(a.agent_title) || return a.agent_title
    for turn in collect(a.conversation.turns)
        turn.role === :user || continue
        for part in turn.parts, line in eachsplit(_part_text(part), '\n')
            text = strip(line)
            isempty(text) || return String(text)
        end
    end
    ASSISTANT_TITLE
end

"""
    find_first_prompt(assistant) -> String or nothing
    find_last_prompt(assistant) -> String or nothing

The text of the first and of the last turn of the person in the conversation of
`assistant`, or `nothing` before the first prompt.
"""
find_first_prompt(a::Assistant) = _find_prompt(a, findfirst)
find_last_prompt(a::Assistant) = _find_prompt(a, findlast)

function _find_prompt(a::Assistant, find::Function)
    turns = collect(a.conversation.turns)
    index = find(turn -> turn.role === :user, turns)
    index === nothing ? nothing : join((_part_text(part) for part in turns[index].parts), "\n\n")
end

"""
    compute_prompt_count(assistant) -> Int

How many prompts the person gave `assistant`: the count of the turns of the
person in its conversation.
"""
compute_prompt_count(a::Assistant) = count(turn -> turn.role === :user, collect(a.conversation.turns))

"""
    compute_assistant_turn_side(assistant) -> Symbol

Whose turn it is in the conversation of `assistant`: `:assistant` while a turn
runs, else `:person`. A question of the agent that waits for an answer is the
turn of the person, also while the turn of the agent runs.
"""
function compute_assistant_turn_side(a::Assistant)
    is_assistant_turn_running(a) || return :person
    _find_open_permission_request(a) === nothing ? :assistant : :person
end

"""
    describe_assistant_activity(assistant) -> String

What the turn of `assistant` that runs does now, in a few words: "starts",
"thinks", "writes", "runs <tool>", or the question of the agent that waits for
the person. "failed" after a turn that failed, and empty between turns.
"""
function describe_assistant_activity(a::Assistant)
    a.status === :error && return "failed"
    is_assistant_turn_running(a) || return ""
    request = _find_open_permission_request(a)
    request === nothing || return request.title
    turns = collect(a.conversation.turns)
    (isempty(turns) || last(turns).role !== :assistant) && return "starts"
    parts = collect(last(turns).parts)
    isempty(parts) && return "starts"
    content = last(parts).content
    content isa ConversationThinking && return "thinks"
    content isa EvaluatorForm && return "runs " * content.tool_name
    "writes"
end

# The question of the agent in the last turn that waits for the person.
function _find_open_permission_request(a::Assistant)
    turns = collect(a.conversation.turns)
    isempty(turns) && return nothing
    for part in collect(last(turns).parts)
        content = part.content
        content isa ConversationPermissionRequest && is_permission_request_open(content) && return content
    end
    nothing
end

"""
    collect_open_assistant_requests(assistant) -> Vector{Any}

The requests in the last turn of `assistant` that wait for an answer of the
person: a permission that the agent asks, a question with a form, and a sign-in
that the agent needs while its request is live.

Use it to know whether an assistant waits for the person, and for what.

# Example

    length(collect_open_assistant_requests(get_session_assistant_list().assistants[1]))

See also `describe_assistant_activity`.
"""
function collect_open_assistant_requests end

function collect_open_assistant_requests(a::Assistant)
    turns = collect(a.conversation.turns)
    isempty(turns) && return Any[]
    Any[part.content for part in collect(last(turns).parts) if _is_open_assistant_request(part.content)]
end

_is_open_assistant_request(request::ConversationPermissionRequest) = is_permission_request_open(request)
_is_open_assistant_request(request::ConversationQuestionRequest) = is_question_request_open(request)
_is_open_assistant_request(request::ConversationSignInRequest) = request.start !== nothing
_is_open_assistant_request(_) = false

# An assistant runs while its turn streams, failed after a turn that failed, and
# waits for the person while a request of its last turn is open. The work state
# that the person sets is its count, and its activity its detail.
function get_document_decoration(a::Assistant)
    conditions = DocumentCondition[]
    a.status === :streaming && push!(conditions, DocumentCondition(:running))
    a.status === :error && push!(conditions, DocumentCondition(:failed))
    waiting = length(collect_open_assistant_requests(a))
    waiting > 0 && push!(conditions, DocumentCondition(:waiting; count = waiting))
    state = a.work_state
    counts = state === :pending ? DocumentCount[] :
             [DocumentCount(_format_work_state(state); role = _get_work_state_role(state))]
    DocumentDecoration(; icon = :bot, conditions, counts, detail = describe_assistant_activity(a))
end

"""
    find_assistant_start_time(assistant) -> Float64 or nothing

When the conversation of `assistant` started: the start of its first turn whose
time is known, in seconds of `time()`, or `nothing`.
"""
function find_assistant_start_time(a::Assistant)
    for turn in collect(a.conversation.turns)
        turn.start_time > 0 && return turn.start_time
    end
    nothing
end

"""
    find_assistant_last_activity_time(assistant) -> Float64 or nothing

The time of the last activity in the conversation of `assistant`: the latest
end of a turn, in seconds of `time()`, or `nothing`.
"""
function find_assistant_last_activity_time(a::Assistant)
    times = [turn.finish_time for turn in collect(a.conversation.turns) if turn.finish_time > 0]
    isempty(times) ? nothing : maximum(times)
end

"""
    compute_assistant_elapsed_time(assistant; now = time()) -> Float64 or nothing

How long the conversation of `assistant` runs, in seconds: from its start to
`now` while a turn runs, else to its last activity. `nothing` before the first
turn whose time is known.
"""
function compute_assistant_elapsed_time(a::Assistant; now::Real = time())
    start = find_assistant_start_time(a)
    start === nothing && return nothing
    is_assistant_turn_running(a) && return now - start
    finish = find_assistant_last_activity_time(a)
    finish === nothing ? 0.0 : finish - start
end

"""
    compute_assistant_busy_time(assistant; now = time()) -> Float64

How long `assistant` worked, in seconds: the sum of the durations of its turns,
with the last turn counted up to `now` while it runs. A turn whose end is not
known and that does not run counts nothing.
"""
function compute_assistant_busy_time(a::Assistant; now::Real = time())
    turns = collect(a.conversation.turns)
    is_running = is_assistant_turn_running(a)
    total = 0.0
    for (index, turn) in enumerate(turns)
        (turn.role === :assistant && turn.start_time > 0) || continue
        if turn.finish_time > 0
            total += turn.finish_time - turn.start_time
        elseif is_running && index == length(turns)
            total += now - turn.start_time
        end
    end
    total
end

# The facets of an assistant, which a roster of assistants shows, filters and
# sorts by. Its state of the work and its status are fields, which a key names as
# they are.
get_item_facets(::Type{Assistant}) = [
    "title" => "the title of the conversation, as the Assistants pane shows it",
    "turn" => "whose turn it is: assistant or you",
    "tokens" => "how many tokens of its context the conversation uses, or 0 before the " *
                "first answer",
    "plan" => "how far the plan of its agent is, as the completed steps over all the " *
              "steps of the first plan with steps, such as 3/7; empty without one",
    "subagents" => "how many subagents of its agent run, at every depth",
    "background_tasks" =>
        "how many background tasks of its agent and of their subagents run"]
compute_item_facet(a::Assistant, ::Val{:title}) = compute_assistant_overview_title(a)
compute_item_facet(a::Assistant, ::Val{:turn}) = compute_assistant_turn_side(a) === :assistant ? "assistant" : "you"
compute_item_facet(a::Assistant, ::Val{:tokens}) = (usage = a.agent_usage; usage === nothing ? 0 : usage.used)
compute_item_facet(a::Assistant, ::Val{:plan}) = _format_agent_plan_progress(a.agent_work)
compute_item_facet(a::Assistant, ::Val{:subagents}) =
    _count_running_subagents(a.agent_work)
compute_item_facet(a::Assistant, ::Val{:background_tasks}) =
    _count_running_background_tasks(a.agent_work)
