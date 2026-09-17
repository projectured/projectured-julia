# Fragment of `AssistantModule` — the assistant document types and the prompts
# they start from: the shared system prompt, and the conversation an assistant
# keeps with its model.

const ASSISTANT_TITLE = "Assistant"
"""
    DEFAULT_ASSISTANT_SYSTEM

Shared system / instruction prompt for any AI assistant working against the
editor: the `system` field of an in-editor `Assistant`, and the
`instructions` field of the MCP server's `initialize` response. Keep the
two sites in sync by sourcing both from this constant.
"""
const DEFAULT_ASSISTANT_SYSTEM = "You are Claude working inside the ProjecturEd editor — a projectional editor built in Julia.\n\n" *
                                  "Use `execute_julia_code` to inspect and modify the editor's document and projection; " *
                                  "the variable `editor` is bound to the running editor.\n\n" *
                                  "MANDATORY — read this BEFORE writing any code:\n" *
                                  "- resource://guide/orientation  (the concept index — your starting point)\n" *
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
                                  "  See resource://guide/editor/finding-and-selecting and resource://guide/operations.\n\n" *
                                  "SCOPING A SEARCH TO A DOMAIN — the workbench renders the SAME document through\n" *
                                  "several projections (a JSON value also appears in syntax and text editors), so a\n" *
                                  "bare value match (e.g. \"Alice\" or `n isa AbstractString`) returns one hit per\n" *
                                  "projection and cannot tell them apart. Match the DOMAIN NODE TYPE instead, e.g.\n" *
                                  "`v -> v isa JsonString && v.value == \"Alice\"`, and/or first locate the document\n" *
                                  "with `search_documents(editor.document, x -> x isa JsonDocument)`.\n\n" *
                                  "STATE PERSISTS between `execute_julia_code` calls: a variable you assign at top\n" *
                                  "level in one call (e.g. `paths = search_references(...)`) is still bound in the\n" *
                                  "next call, so you can build up state incrementally instead of one giant block.\n\n" *
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

**A person says which backend they want.** `backend` defaults to `:none`, and an
assistant that names none errors on submit with the list of backends whose
packages are loaded. Nothing is guessed: a guess was only ever right while one
backend existed.

`model` defaults to empty, which means "the backend's own default" — a model name
belongs to a provider, and a Claude id means nothing to a local server.

`context` is how many tokens of this conversation the model may see, and `0` leaves
the size to the backend. It is one of the three keywords every backend accepts, and
a backend it does not apply to ignores it: a hosted provider's window comes with the
model and cannot be set per request.

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
end

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function Assistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              backend::Symbol = :none,
                              model::AbstractString = "",
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = "",
                              context::Integer = 0,
                              status::Symbol = :idle,
                              collapse_thinking::Bool = true,
                              llm::Union{Nothing,Llm} = nothing)
    a = Assistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(backend), Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(Int(context)), Cell(status),
                           Cell(collapse_thinking),
                           Cell(llm),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

set_cell_function!(a::Assistant, f::Function) = (set_cell_function!(getfield(a, :conversation), f); a)

# ── The duplicate ─────────────────────────────────────────────────────────────
#
# The duplicate of an assistant is a fork: the conversation so far and the text
# in the composer, and a draft of its own that links back to the fork. The
# backend, the model, the prompt, the key and the `llm` are values it shares. The
# fork starts idle. A reply that streams stays with the assistant that started
# it: its task writes there, and it is the last turn, pushed when the stream
# began, so the fork leaves it out.
has_document_duplicate(::Assistant) = true

function copy_document(policy::DuplicatePolicy, assistant::Assistant)
    draft = copy_document_fields(policy, assistant.draft; assistant = nothing)
    fork = copy_document_fields(policy, assistant; draft = draft, status = :idle)
    draft.assistant = fork
    turns = fork.conversation.turns
    if assistant.status === :streaming && !isempty(turns) &&
       turns[length(turns)].role === :assistant
        deleteat!(turns, length(turns))
    end
    fork
end

# The assistant is a tool pane: its conversation is a record, and its draft
# belongs to the composer. A pasted document replaces neither it nor anything in
# it. The composer's own text paste is not a pasted document, so it still works.
accepts_pasted_document(::Assistant) = false
