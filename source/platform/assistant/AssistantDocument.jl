# Fragment of `AssistantModule` — the assistant document types and the prompts
# they start from: the shared system prompt, and the conversation an assistant
# keeps with its model.

const ASSISTANT_TITLE = "Assistant"
"""
    DEFAULT_ASSISTANT_SYSTEM

The system prompt an `Assistant` starts with: its `system` field, unless a
caller names another. `McpServer` has its own, domain-free instructions
(`DEFAULT_MCP_INSTRUCTIONS` in `source/adapter/mcp/Mcp.jl`), so the MCP module keeps
no dependency on the assistant.
"""
const DEFAULT_ASSISTANT_SYSTEM = "You are Claude working inside the ProjecturEd editor — a projectional editor built in Julia.\n\n" *
                                  "Use `execute_julia_code` to inspect and modify the editor's document and projection; " *
                                  "the variable `editor` is bound to the running editor.\n\n" *
                                  "MANDATORY — read this BEFORE writing any code:\n" *
                                  "- resource://guide/guide/orientation  (the concept index — your starting point)\n" *
                                  "Everything else is on demand: the orientation lists the catalogues " *
                                  "(resource://guides, resource://modules) and the search tools, and points to the " *
                                  "specific guides (reference, selection, finding-and-selecting, operations, …). " *
                                  "Read whatever your task touches.\n\n" *
                                  "TO INSPECT OR CHANGE THE DOCUMENT — never hand-walk the document tree or write\n" *
                                  "bespoke helpers; use the general primitives (they work through any Screen/Window\n" *
                                  "wrapping and across every domain):\n" *
                                  "- `search_references(editor.document, query)` returns paths to matching document nodes.\n" *
                                  "- `search_documents(editor.document, query)` returns the matching document nodes themselves (each once).\n" *
                                  "  `query` is a predicate `node -> Bool`, or a `String`/`Regex` matching leaf text (which folds to its enclosing document; pass `raw=true` for the exact matched value).\n" *
                                  "- `evaluate_reference(editor.document, path)` resolves a path back to its node.\n" *
                                  "- Build an `Operation` and apply it with `evaluate_operation(editor, op)` — e.g. " *
                                  "`ReplaceSelectionOperation(path)` to select. This is the one way to change the document.\n" *
                                  "  See resource://guide/kernel/finding-and-selecting and resource://guide/kernel/operation for the details.\n\n" *
                                  "SCOPING A SEARCH TO A DOMAIN — the pane tree holds every open tab inside the\n" *
                                  "SAME document, so a JSON file in one tab and an unrelated value in another can\n" *
                                  "share the same string (e.g. \"Alice\" or match `n isa AbstractString`), and a\n" *
                                  "bare value match returns one hit per tab and cannot tell them apart. Match the\n" *
                                  "DOMAIN NODE TYPE instead, e.g.\n" *
                                  "`v -> v isa JsonString && v.value == \"Alice\"`, and/or first locate the document\n" *
                                  "with `search_documents(editor.document, x -> x isa JsonDocument)`.\n\n" *
                                  "STATE PERSISTS between `execute_julia_code` calls: a variable you assign at top\n" *
                                  "level in one call (e.g. `paths = search_references(...)`) is still bound in the\n" *
                                  "next call, so you can build up state incrementally instead of one giant block.\n" *
                                  "The person edits the window between your turns too: a key, an undo or a click can\n" *
                                  "change what a variable of an earlier turn shows. Read a document again before you\n" *
                                  "tell the person what it holds.\n\n" *
                                  "TO FIND A SPECIFIC API OR GUIDE — do this BEFORE writing code:\n" *
                                  "- Call the `search_api` tool to find the right module, struct, or function.\n" *
                                  "- Call the `search_guides` tool to find the relevant guide section.\n" *
                                  "- When you know what you want to do but not what it is called, call either " *
                                  "search with mode \"description\" and say it in a sentence.\n" *
                                  "- Read full text with `read_resource(uri)`; read a function's full docs with " *
                                  "`read_function_documentation(\"Module\", \"name\")`.\n" *
                                  "- `list_resources` enumerates documentation/module/class resources if you need to browse.\n\n" *
                                  "NEVER guess names or signatures — search for them.\n" *
                                  "NEVER search in files, read files, or run shell commands — use the editor's search tools and resources."

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
and an agent that does not read it, as the built-in one, ignores it. The package `ProjecturedACP` must be
loaded. `agent_session` is the live link to
the agent, an `ExternalAgentSession`: `nothing` until the first turn starts it,
or one that a test gives. It is no data, like `llm`. `agent_options` are the options of
the session of the agent, such as its model and how much it reasons, as the agent
last listed them: empty until a session opens. `agent_title` is the title that
the agent gave its session, empty until it gives one, and the tab of the
assistant shows it. `agent_usage` is how much of its context window the
session uses, an `AgentUsageUpdate`, or `nothing`. `agent_commands` are the
commands that the agent offers, as `/name` at the start of a prompt. They are no
data either.

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
    collapse_thinking::Bool
    llm::Union{Nothing,Llm}
    agent_command::String
    agent_session_meta::String
    agent_session::Any
    agent_options::Vector{AgentOption}
    agent_title::String
    agent_usage::Union{Nothing,AgentUsageUpdate}
    agent_commands::Vector{AgentCommand}
end

# The command of the external agent that an assistant starts when nobody names
# another: empty, which starts the built-in agent of `ProjecturedACP`.
const DEFAULT_AGENT_COMMAND = ""

# The `_meta` of a new session of the external agent when nobody names another.
# `claude-agent-acp` reads SDK options from `claudeCode.options`, and a recent
# model streams no text of its reasoning unless `thinking.display` says
# `"summarized"`.
const DEFAULT_AGENT_SESSION_META =
    raw"""{"claudeCode": {"options": {"thinking": {"type": "adaptive", "display": "summarized"}}}}"""

# What the fork of an assistant with an external agent says under the history it
# copied.
const FORK_AGENT_NOTE =
    "This copy talks to the agent in a new session. The agent does not have the history above."

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
                              collapse_thinking::Bool = true,
                              llm::Union{Nothing,Llm} = nothing,
                              agent_command::AbstractString = DEFAULT_AGENT_COMMAND,
                              agent_session_meta::AbstractString = DEFAULT_AGENT_SESSION_META,
                              agent_session = nothing,
                              agent_options::AbstractVector = AgentOption[],
                              agent_title::AbstractString = "",
                              agent_usage::Union{Nothing,AgentUsageUpdate} = nothing,
                              agent_commands::AbstractVector = AgentCommand[])
    a = Assistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(backend), Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(Int(context)), Cell(status),
                           Cell(collapse_thinking),
                           Cell(llm),
                           Cell(String(agent_command)), Cell(String(agent_session_meta)),
                           Cell(agent_session), Cell(collect(AgentOption, agent_options)),
                           Cell(String(agent_title)), Cell(agent_usage),
                           Cell(collect(AgentCommand, agent_commands)),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

set_cell_computation!(a::Assistant, f::Function) = (set_cell_computation!(getfield(a, :conversation), f); a)

# A key must never be written to a file, so `api_key` is not one of the
# arguments a `.pred` file writes. A command is not one either: a file that named
# the program of an external agent, or the options of its sessions, would start
# it at the next message, and a `.pred` file runs no code. So `agent_command` and
# `agent_session_meta` come from the settings of the application, never from a
# file. A live connection is not data either: `llm`
# is a fake or a running client, `agent_session` is a running agent, `status` is what a turn is doing right now,
# and `conversation`/`input`/`draft` are this session's exchange, not the
# next one's — so a save keeps only the settings that describe an assistant
# rather than a moment of one, and a load starts a fresh, empty conversation.
pred_arguments(a::Assistant) = (), Pair{Symbol,Any}[
    :backend           => a.backend,
    :model             => a.model,
    :system            => a.system,
    :context           => a.context,
    :collapse_thinking => a.collapse_thinking,
]

# The name the tab calls itself: the title that an external agent gave its
# session, else the name of the assistant. A tab with an empty name asks at each
# draw, so the tab follows the title. No alias: `get_insertion_names` already
# derives one from the type name, so a person types "assistant" without a
# hand-written method.
get_document_title(a::Assistant) = isempty(a.agent_title) ? ASSISTANT_TITLE : a.agent_title

# ── The duplicate ─────────────────────────────────────────────────────────────
#
# The duplicate of an assistant is a fork: the conversation so far and the text
# in the composer, and a draft of its own that links back to the fork. The
# backend, the model, the prompt, the key and the `llm` are values it shares. The
# fork starts idle. A reply that streams stays with the assistant that started
# it: its task writes there, and it is the last turn, pushed when the stream
# began, so the fork leaves it out.
#
# The session of an external agent stays with the assistant that opened it. The
# fork starts a new session at its first turn, and a note in its transcript says
# that the agent of the fork does not have the history above it.
has_document_duplicate(::Assistant) = true

function copy_document(policy::DuplicatePolicy, assistant::Assistant)
    draft = copy_document_fields(policy, assistant.draft; assistant = nothing)
    fork = copy_document_fields(policy, assistant; draft = draft, status = :idle,
                                agent_session = nothing, agent_options = AgentOption[],
                                agent_title = "", agent_usage = nothing,
                                agent_commands = AgentCommand[])
    draft.assistant = fork
    turns = fork.conversation.turns
    if assistant.status === :streaming && !isempty(turns) &&
       turns[length(turns)].role === :assistant
        deleteat!(turns, length(turns))
    end
    assistant.agent_session === nothing ||
        push!(turns, ConversationTurn(:assistant, [ConversationPart(FORK_AGENT_NOTE)]))
    fork
end

# The assistant is a tool pane: its conversation is a record, and its draft
# belongs to the composer. A pasted document replaces neither it nor anything in
# it. The composer's own text paste is not a pasted document, so it still works.
accepts_pasted_document(::Assistant) = false

# A file opens beside the conversation, never over it.
accepts_opened_file(::Assistant) = false
