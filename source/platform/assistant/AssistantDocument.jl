# Fragment of `AssistantModule` — the assistant document types and the prompts
# they start from: the shared system prompt, and the conversation an assistant
# keeps with its model.

const ASSISTANT_TITLE = "Assistant"
"""
    DEFAULT_ASSISTANT_SYSTEM

The system prompt of an `Assistant` whose window gives no text of its own: what
the editor is, the tools, the rule against a guess, and the rule against files and
programs in code. A window gives its own
text in the `system` field, with its rules, a worked example and the names that
it offers. `McpServer` has its own, domain-free instructions
(`DEFAULT_MCP_INSTRUCTIONS` in `source/adapter/mcp/McpServer.jl`), so the MCP
module keeps no dependency on the assistant.
"""
const DEFAULT_ASSISTANT_SYSTEM =
    "You are Claude working inside the ProjecturEd editor — a projectional editor built in Julia.\n\n" *
    "Use `execute_julia_code` to read and change the editor; the variable `editor` is bound " *
    "to the running editor. Before you write code, find the names with `search_api` and the " *
    "guides with `search_guides`, and read a guide with `read_resource`. NEVER guess a name " *
    "or a signature: search for it.\n\n" *
    "NEVER read files or run programs directly in code. Read a file with the verbs of the editor. " *
    "Start a program as a task with `run_tasks!`, so that the person sees it and can stop it."

"""
    ASSISTANT_ANSWER_INSTRUCTIONS

What every model of the assistant pane learns about its answer: when the answer
ends, the transcript folds the work into one line and shows only the parts after
the last part of work, so the last text must stand alone. The built-in loop adds
it after the `system` text, and an external agent gets it at the end of
[`DEFAULT_AGENT_INSTRUCTIONS`](@ref), because the text of a window replaces the
`system` text.
"""
const ASSISTANT_ANSWER_INSTRUCTIONS =
    "When your answer ends, the assistant pane folds your thinking, your tool calls and every " *
    "text before your last tool call into one line, and shows only the text after your last " *
    "tool call. So end each answer with a text that stands alone: put in it what the person " *
    "needs from your earlier texts, such as a result, a finding, a decision or a question."

"""
    DEFAULT_AGENT_INSTRUCTIONS

What an external agent of the assistant gets before the text of its window: the
agent runs inside the editor of the person, the MCP server controls that editor,
and a request about what the editor shows goes through its tools. The session
gets these and then the `system` of the assistant in its system prompt, so an
agent and the built-in loop read the same text of the window. The text of the
window forbids reading files and running programs directly in the code that runs in
the window, and names `run_tasks!` for a program. These instructions add that the
agent uses its own file tools only when the person asks for work on files, and that
a command of its shell tool that runs through the terminals of the editor is a task.
They end with [`ASSISTANT_ANSWER_INSTRUCTIONS`](@ref).
"""
const DEFAULT_AGENT_INSTRUCTIONS =
    "You run inside ProjecturEd, the projectional editor built in Julia that the person uses now, " *
    "as the agent of its assistant pane. The MCP server `projectured` controls this running editor: " *
    "its windows, panes, tabs, open documents and widgets.\n\n" *
    "When the person asks you to show, open, change, arrange or build something in the editor — " *
    "a tab, a pane, a table, a form, a widget, or a value in an open document — do it in the running " *
    "editor with the tools of this server. Do not write source files, change the code of ProjecturEd, " *
    "or start a git worktree for such a request. Use your own file tools only when the person asks " *
    "for work on files or on the code of a project. When your shell tool runs through the " *
    "terminals of the editor, each command is a task that the person sees and can stop.\n\n" *
    ASSISTANT_ANSWER_INSTRUCTIONS

"""
    AgentSessionFork(session_id, directory, turn_count, options)

The session of an external agent that the duplicate of an assistant forks: the
id and the folder of the session that the original keeps, how many turns of the
conversation that session saw, and the options of the session of the original,
such as its model and its effort.
"""
struct AgentSessionFork
    session_id::String
    directory::String
    turn_count::Int
    options::Vector{AgentOption}
end

"""
    Assistant(; conversation, input, backend, model, system, api_key, context, status, llm)

The assistant panel. Holds the full chat history (`conversation`), the
editable prompt (`input`, a `PrimitiveString` so the existing text-edit
projections route `KeyPress`/backspace/delete to it directly), the
`backend` that services a turn (`:anthropic`, `:ollama`), the model id
(`model`), the system prompt (`system`), the API key (`api_key`), a `status`
symbol (`:idle`, `:streaming`, `:error`, ...), and a pluggable `llm::Llm` that
overrides the backend entirely (a canned-reply fake, in a test).

**A person can say which backend they want.** `backend` defaults to `:ollama`,
the local model that runs with no key. A person who wants Claude sets it to
`:anthropic` and exports a key. `backend` set to `:none` names no backend at
all, and a submit then errors with the list of backends whose packages are
loaded.

`model` defaults to empty, which means "the backend's own default" — a model name
belongs to a provider, and a Claude id means nothing to a local server.

`context` is how many tokens of this conversation the model may see, and `0` leaves
the size to the backend. It is one of the three keywords every backend accepts, and
a backend it does not apply to ignores it: a hosted provider's window comes with the
model and cannot be set per request.

**An external agent is a backend too.** With `backend = :acp` a turn goes to an
agent that runs its own loop, and the agent runs its own tools. `agent_command`
is the command line that starts the agent in another process. Empty, the
default, starts the built-in agent of `ProjecturedACP` in this process, which
runs Claude Code, the `claude` program that the person installed.
`agent_session_meta` is the JSON `_meta` that a new session of the agent gets;
its default asks the agent `claude-agent-acp` for the summary of its reasoning,
and an agent that does not read it, as the built-in one, ignores it.
`agent_mode` is the mode of the tools that each session of the agent starts in,
`"auto"` by default ([`DEFAULT_AGENT_MODE`](@ref)). The assistant sets it when a
session opens and the agent offers that mode. Empty leaves the mode to the
agent. The package `ProjecturedACP` must be
loaded. `agent_session` is the live link to
the agent, an `ExternalAgentSession`: `nothing` until the first turn starts it,
or one that a test gives. It is no data, like `llm`. `agent_session_id` is the
id of the session of the agent that the assistant keeps, `agent_session_directory`
its folder, and `agent_session_turn_count` how many turns of the conversation
that session saw. They are written when the agent answers a prompt, and empty
until then. A stop of the agent keeps them, so the next turn resumes that
session with its history, as after the undo of the close of the tab; a new
conversation and a duplicate clear them. `agent_options` are the options of
the session of the agent, such as its model and how much it reasons, as the agent
last listed them: empty until a session opens. `agent_title` is the title that
the agent gave its session, empty until it gives one, and the tab of the
assistant shows it. `agent_usage` is how much of its context window the
session uses, an `AgentUsageUpdate`, or `nothing`. `agent_commands` are the
commands that the agent offers, as `/name` at the start of a prompt. They are no
data either. `agent_work` is the work of the session of the agent, an
[`AgentWork`](@ref): its subagents, its plans, its background tasks, its notices
and its processes. It is the live state of the session, so it is no data either:
a file does not keep it, and a duplicate and a new session start with an empty
one.

`agent_fork` is the session that the duplicate of an assistant forks, an
[`AgentSessionFork`](@ref), or `nothing`. The duplicate of an assistant whose
external agent keeps a session gets it, and its acquire opens its session as a
fork of that session, so the agent of the duplicate has the history that the
duplicate shows. The first answer of the agent in the fork, or a fork that the
agent can not make, clears it. It is live state, so a file does not keep it.

`workflow` is the node of a workflow that the conversation records its work in,
or `nothing`. It is data that the person chose, so a `.pred` file keeps it; the
platform names no domain, so the field holds any document.

`description` and `comment` are what the person writes about the conversation:
what it is about, and a note. Each is a `PrimitiveString`, as `input` is, so the
text-edit projections route keys to it. `work_state` is the state of the work
that the person sets, one of [`ASSISTANT_WORK_STATES`](@ref); only the person
changes it. The three are data that the person wrote, so a `.pred` file keeps
them for every backend, and a fork copies them.

`max_rounds` is how many rounds a turn of a model may run, eight by default
([`DEFAULT_ASSISTANT_ROUNDS`](@ref)). A turn that reaches it ends with the stop
reason `:round_limit`, and a note under the answer says so and offers to go on.
A window that serves long work gives its assistant more rounds. The budget is a
setting that a person or a window chose, so a `.pred` file keeps it.

An assistant starts a turn of its own when a task group that one of its turns
started ends, with a note that says why. `wakes_left` is how many turns it may
still start without a message of the person: a wake takes one, a stop of a turn
sets 0, and a message of the person raises it to at least [`ASSISTANT_WAKE_LIMIT`](@ref). Only the person sets it to
another value. It is live state, like `status`: a `.pred` file does not keep it,
and a fork starts at 0.

`number` tells the assistant from the other assistants of its window while it has
no title: with no title, 1 is "Assistant" and 2 is "Assistant (2)". `Ctrl+T` with
the name "assistant" and a duplicate give the lowest number that no assistant in a
tab of the window has. A `.pred` file does not keep it, and a load gives 1.

`identifier` names the assistant in the rows of the task list that it starts
(`WorkStarter`): `A1`, `A2`, … in the order the assistants of the process are
made. It never changes while the assistant lives, so its work page finds its rows.
A duplicate and a load get a new one.

`turn_control` is the live control of the turn that runs, an
`AssistantTurnControl`, and `nothing` between turns. A stop sets its flag. It is
no data, like `llm`.

`llm` defaults to `nothing` and `api_key` to empty: the backend and key are
resolved **at submit time**, not here. This keeps the choice out of the
precompiled image — documents are built eagerly into `const`s during
precompilation (no key then), so resolving at construction would freeze the wrong
choice. Resolving lazily means a key exported before launch is honoured.
Production `main` never fabricates a fake — tests/examples that want offline
behaviour pass an explicit `llm` (a `FakeLlm`/`ScriptedLlm` from
`ProjecturedKernelExample`, e.g. `FakeLlm("ok")`).
"""
@document struct Assistant <: Document
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    backend::Symbol
    model::String
    system::String
    api_key::String
    context::Int
    status::Symbol
    llm::Union{Nothing,Llm}
    turn_control::Any
    agent_command::String
    agent_session_meta::String
    agent_mode::String
    agent_session::Any
    agent_session_id::String
    agent_session_directory::String
    agent_session_turn_count::Int
    agent_options::Vector{AgentOption}
    agent_title::String
    agent_usage::Union{Nothing,AgentUsageUpdate}
    agent_commands::Vector{AgentCommand}
    agent_work::AgentWork
    agent_fork::Union{Nothing,AgentSessionFork}
    workflow::Any
    description::PrimitiveString
    comment::PrimitiveString
    work_state::Symbol
    max_rounds::Int
    wakes_left::Int
    number::Int
    identifier::String
end

"""
    ASSISTANT_WORK_STATES

The states of the work of a conversation that a person sets on an `Assistant`
(`work_state`): `:pending`, `:in_progress`, `:complete` and `:abandoned`. A new
assistant is `:pending`.
"""
const ASSISTANT_WORK_STATES = (:pending, :in_progress, :complete, :abandoned)

"""
    DEFAULT_ASSISTANT_ROUNDS

How many rounds a turn of a model may run when nobody says otherwise: eight. A
round is one answer of the model and the tools that it asked for. A window that
serves long work, such as a study, gives its assistant more.
"""
const DEFAULT_ASSISTANT_ROUNDS = 8

# The command of the external agent that an assistant starts when nobody names
# another: empty, which starts the built-in agent of `ProjecturedACP`.
const DEFAULT_AGENT_COMMAND = ""

# The `_meta` of a new session of the external agent when nobody names another.
# `claude-agent-acp` reads SDK options from `claudeCode.options`, and a recent
# model streams no text of its reasoning unless `thinking.display` says
# `"summarized"`.
const DEFAULT_AGENT_SESSION_META =
    raw"""{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}"""

"""
    DEFAULT_AGENT_MODE

The mode of the tools that a session of an external agent starts in when nobody
names another: `"auto"`. In this mode, Claude Code and Codex decide themselves
which tool calls need a question to the person. An agent that offers no mode
`"auto"` keeps its own mode.
"""
const DEFAULT_AGENT_MODE = "auto"

# What the duplicate of an assistant with an external agent says under the
# history that it copied, when the agent could not fork the session of the
# original.
const FORK_AGENT_NOTE =
    "This copy talks to the agent in a new session, because the agent could not copy the session " *
    "of the original. The agent does not have the history above."

# What the duplicate of an assistant whose external agent answered at the copy
# says under the history that it copied.
const FORK_DURING_ANSWER_NOTE =
    "The original answered when this copy was made, so this copy talks to the agent in a new " *
    "session. The agent does not have the history above."

# What the transcript says when the agent opened a new session in place of the
# session that the assistant kept.
const NEW_SESSION_AGENT_NOTE =
    "The agent could not resume its session, so the next answer comes from a new session, which does not have the history above."

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function Assistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              backend::Symbol = :ollama,
                              model::AbstractString = "",
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = "",
                              context::Integer = 0,
                              status::Symbol = :idle,
                              llm::Union{Nothing,Llm} = nothing,
                              turn_control = nothing,
                              agent_command::AbstractString = DEFAULT_AGENT_COMMAND,
                              agent_session_meta::AbstractString = DEFAULT_AGENT_SESSION_META,
                              agent_mode::AbstractString = DEFAULT_AGENT_MODE,
                              agent_session = nothing,
                              agent_session_id::AbstractString = "",
                              agent_session_directory::AbstractString = "",
                              agent_session_turn_count::Integer = 0,
                              agent_options::AbstractVector = AgentOption[],
                              agent_title::AbstractString = "",
                              agent_usage::Union{Nothing,AgentUsageUpdate} = nothing,
                              agent_commands::AbstractVector = AgentCommand[],
                              agent_fork::Union{Nothing,AgentSessionFork} = nothing,
                              workflow = nothing,
                              description::Union{AbstractString,PrimitiveString} = "",
                              comment::Union{AbstractString,PrimitiveString} = "",
                              work_state::Symbol = :pending,
                              max_rounds::Integer = DEFAULT_ASSISTANT_ROUNDS,
                              number::Integer = 1)
    max_rounds >= 1 ||
        throw(ArgumentError("an assistant runs at least one round in a turn, not $(max_rounds)"))
    work_state in ASSISTANT_WORK_STATES ||
        throw(ArgumentError("the work state of an assistant is one of $(ASSISTANT_WORK_STATES), not $(repr(work_state))"))
    number >= 1 || throw(ArgumentError("the number of an assistant is at least 1, not $(number)"))
    a = Assistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(backend), Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(Int(context)), Cell(status),
                           Cell(llm), Cell(turn_control),
                           Cell(String(agent_command)), Cell(String(agent_session_meta)),
                           Cell(String(agent_mode)), Cell(agent_session), Cell(String(agent_session_id)),
                           Cell(String(agent_session_directory)), Cell(Int(agent_session_turn_count)),
                           Cell(CellVector{AgentOption}(collect(AgentOption, agent_options))),
                           Cell(String(agent_title)), Cell(agent_usage),
                           Cell(CellVector{AgentCommand}(collect(AgentCommand, agent_commands))),
                           Cell(AgentWork("")), Cell(agent_fork), Cell(workflow),
                           Cell(_make_primitive_string(description)),
                           Cell(_make_primitive_string(comment)), Cell(work_state),
                           Cell(Int(max_rounds)), Cell(0), Cell(Int(number)),
                           Cell(_make_assistant_identifier()), Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

# The counter of the identifiers of the assistants of the process.
const _ASSISTANT_COUNT = Threads.Atomic{Int}(0)

_make_assistant_identifier() = "A" * string(Threads.atomic_add!(_ASSISTANT_COUNT, 1) + 1)

"""
    make_assistant_starter(assistant; tool_call = "") -> WorkStarter

The starter of the work that `assistant` starts: its identifier, the name that the
Tasks pane shows, such as "Assistant 2", and `tool_call`, the id of the call of the
model or of the agent that starts it. A turn binds it for the code of each tool
call, so a row that the code starts records it.
"""
make_assistant_starter(a::Assistant; tool_call::AbstractString = "") =
    WorkStarter(:assistant; identifier = a.identifier, name = string(ASSISTANT_TITLE, " ", a.number),
                tool_call)

_make_primitive_string(text::PrimitiveString) = text
_make_primitive_string(text::AbstractString) = PrimitiveString(String(text))

set_cell_computation!(a::Assistant, f::Function) = (set_cell_computation!(getfield(a, :conversation), f); a)

# A key must never be written to a file, so `api_key` is not one of the
# arguments a `.pred` file writes. A command is not one either: a file that named
# the program of an external agent, or the options of its sessions, would start
# it at the next message, and a `.pred` file runs no code. A mode is not one
# either: a file that named the mode `bypassPermissions` would let the agent run
# each tool with no question to the person. So `agent_command`,
# `agent_session_meta` and `agent_mode` come from the settings of the
# application, never from a file. A live connection is not data either: `llm`
# is a fake or a running client, `agent_session` is a running agent, `agent_work`
# is the work of its session, `status` is what a turn is doing right now,
# and `conversation`/`input`/`draft` are this session's exchange, not the
# next one's — so a save keeps only the settings that describe an assistant
# rather than a moment of one, and a load starts a fresh, empty conversation.
#
# An assistant that keeps a session of an external agent is the exception: the
# agent holds the history of that conversation. So its file also keeps the
# conversation, and the id, the folder, the count of turns and the title of the
# session, and the next turn after a load resumes the session. An id is no
# command and no credential: the agent still comes from the settings.
function pred_arguments(a::Assistant)
    keywords = Pair{Symbol,Any}[
        :backend           => a.backend,
        :model             => a.model,
        :system            => a.system,
        :context           => a.context,
    ]
    # The workflow that the conversation records its work in is data that the
    # person chose, so the file keeps the link.
    a.workflow === nothing || push!(keywords, :workflow => a.workflow)
    # What the person wrote about the conversation is data too, so the file keeps
    # it for every backend.
    isempty(a.description.value) || push!(keywords, :description => a.description.value)
    isempty(a.comment.value) || push!(keywords, :comment => a.comment.value)
    a.work_state === :pending || push!(keywords, :work_state => a.work_state)
    # How long a turn may run is what a person or a window chose for the work, so
    # the file keeps it when it differs.
    a.max_rounds == DEFAULT_ASSISTANT_ROUNDS || push!(keywords, :max_rounds => a.max_rounds)
    if a.backend === :acp && !isempty(a.agent_session_id)
        append!(keywords, Pair{Symbol,Any}[
            :conversation             => a.conversation,
            :agent_session_id         => a.agent_session_id,
            :agent_session_directory  => a.agent_session_directory,
            :agent_session_turn_count => a.agent_session_turn_count,
            :agent_title              => a.agent_title,
        ])
    end
    (), keywords
end

# A file can name `collapse_thinking`, which an assistant does not keep: what a
# finished answer shows is the setting `finished_turn` of `ConversationSettings`.
make_pred_document(::Type{<:Assistant}, positional, keywords) =
    invoke(make_pred_document, Tuple{Type,Any,Any}, Assistant, positional,
           filter(pair -> first(pair) !== :collapse_thinking, collect(Pair{Symbol,Any}, keywords)))

# The name the tab calls itself: the title that an external agent gave its
# session, else the first line of its first prompt, else the name of the
# assistant with its number. A tab with an empty name asks at each draw, so the
# tab follows the title. No alias: `get_insertion_names` already derives one from
# the type name, so a person types "assistant" without a hand-written method.
get_document_title(a::Assistant) = compute_assistant_overview_title(a)

# ── The duplicate ─────────────────────────────────────────────────────────────
#
# The duplicate of an assistant is a fork: the conversation so far and the text
# in the composer, and a draft of its own that links back to the fork. The
# backend, the model, the prompt, the key and the `llm` are values it shares. The
# fork starts idle, with the lowest number that no assistant of the window of the
# evaluation has. A reply that streams stays with the assistant that started
# it: its task writes there, and it is the last turn, pushed when the stream
# began, so the fork leaves it out.
#
# The session of an external agent stays with the assistant that opened it, also
# when the agent stopped and the assistant keeps the id of the session. The fork
# keeps that session in `agent_fork`, and its acquire asks the agent for a copy
# of it, so the agent of the fork has the history above. The original of a fork
# that answers now is in the middle of a turn that the fork leaves out, so the
# fork starts a new session, and a note in its transcript says that its agent
# does not have the history above.
has_document_duplicate(::Assistant) = true

function copy_document(policy::DuplicatePolicy, assistant::Assistant)
    is_answering = assistant.status === :streaming
    draft = copy_document_fields(policy, assistant.draft; assistant = nothing)
    fork = copy_document_fields(policy, assistant; draft = draft, status = :idle, turn_control = nothing,
                                agent_session = nothing, agent_session_id = "",
                                agent_session_directory = "", agent_session_turn_count = 0,
                                agent_options = AgentOption[],
                                agent_title = "", agent_usage = nothing,
                                agent_commands = AgentCommand[],
                                agent_work = AgentWork(""),
                                agent_fork = is_answering ? nothing : _make_agent_session_fork(assistant),
                                wakes_left = 0,
                                number = _compute_assistant_number(find_evaluation_editor()),
                                identifier = _make_assistant_identifier())
    draft.assistant = fork
    turns = fork.conversation.turns
    if is_answering && !isempty(turns) && turns[length(turns)].role === :assistant
        deleteat!(turns, length(turns))
    end
    is_answering && (assistant.agent_session !== nothing || !isempty(assistant.agent_session_id)) &&
        push!(turns, ConversationTurn(:assistant, [ConversationPart(ConversationNote(FORK_DURING_ANSWER_NOTE))]))
    fork
end

# The session that the duplicate of `assistant` forks: the session that its
# external agent keeps, with the options of that session. An assistant that is
# a fork whose agent did not answer yet gives the session that it forks itself.
function _make_agent_session_fork(assistant::Assistant)
    assistant.backend === :acp || return nothing
    isempty(assistant.agent_session_id) && return assistant.agent_fork
    AgentSessionFork(assistant.agent_session_id, assistant.agent_session_directory,
                     assistant.agent_session_turn_count, collect(AgentOption, assistant.agent_options))
end

# The assistant is a tool pane: its conversation is a record, and its draft
# belongs to the composer. A pasted document replaces neither it nor anything in
# it. The composer's own text paste is not a pasted document, so it still works.
accepts_pasted_document(::Assistant) = false

# A file opens beside the conversation, never over it.
accepts_opened_file(::Assistant) = false

# A new pane does not cover a conversation: the answer must not hide the question.
avoids_new_panes(::Assistant) = true

# A person who types "assistant" in a tab gets a new assistant, with the lowest
# number that no assistant of the window of the evaluation has.
make_insertion_document(::Type{Assistant}) = Assistant(; number = _compute_assistant_number(find_evaluation_editor()))
