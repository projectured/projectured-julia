"""
    AssistantModule

The assistant: a chat with a model that can act on the editor.

The document alone lives here — the conversation it holds, the prompt a person
types, the draft the composer edits, the model and the key it talks to, and the
`Llm` that services a turn. What a turn DOES is `AssistantTurnModule`'s, and what
it looks like is `AssistantToWidgetModule`'s.

It was `ProjecturedWorkbench`'s, as a `WorkbenchDocument` beside the navigator and
the console. It is a `Document` of its own now, because a program that wants an
assistant beside its own panes should not carry an IDE to get one.
"""
module AssistantModule

import ..CellModule: Cell, set_cell_function!
import ..DocumentModule: Document, @document
import ..PrimitiveModule: PrimitiveString
import ..LlmModule: Llm
# `@document` gives every document a `selection::Reference` slot.
import ..ReferenceModule: Reference
import ..ConversationModule: ConversationConversation, ConversationDraft, ConversationPart

export Assistant, ASSISTANT_TITLE, DEFAULT_ASSISTANT_MODEL, DEFAULT_ASSISTANT_SYSTEM

const ASSISTANT_TITLE = "Assistant"
const DEFAULT_ASSISTANT_MODEL  = "claude-opus-4-8"
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
                                  "- Call the `search_documentation` tool to find the relevant guide section.\n" *
                                  "- Read full text with `read_resource(uri)`; read a function's full docs with " *
                                  "`read_function_documentation(\"Module\", \"name\")`.\n" *
                                  "- `list_resources` enumerates documentation/module/class resources if you need to browse.\n\n" *
                                  "NEVER guess names or signatures — search for them.\n" *
                                  "NEVER search in files, read files, or run shell commands — use the editor's search tools and resources."

"""
    Assistant(; conversation, input, model, system, api_key, status, llm)

The assistant panel. Holds the full chat history (`conversation`), the
editable prompt (`input`, a `PrimitiveString` so the existing text-edit
projections route `KeyPress`/backspace/delete to it directly), the
Anthropic model id (`model`), the system prompt (`system`), the Anthropic
API key (`api_key`), a `status` symbol (`:idle`, `:streaming`, `:error`,
...), and a pluggable `llm::Llm` that decides how submit turns are
serviced (real Claude vs. a canned-reply fake).

`llm` defaults to `nothing` and `api_key` to empty: the backend and key are
resolved from `ENV["ANTHROPIC_API_KEY"]` **at submit time**, not here. This keeps
the choice out of the precompiled image — documents are built eagerly into
`const`s during precompilation (no key then), so resolving at construction would
freeze the wrong choice. Resolving lazily means a key exported before launch is
honoured. When a key is set *and* the opt-in `ProjecturedLlm` package is loaded,
the real Claude backend is discovered by reflection; otherwise submitting errors
with a clear message. Production `main` never fabricates a fake — tests/examples
that want offline behaviour pass an explicit `llm` (a `FakeLlm`/`ScriptedLlm`
from `ProjecturedKernelExample`, e.g. `FakeLlm("ok")`).
"""
@document struct Assistant <: Document
    conversation::ConversationConversation
    input::PrimitiveString
    draft::ConversationDraft
    model::String
    system::String
    api_key::String
    status::Symbol
    collapse_thinking::Bool
    llm::Union{Nothing,Llm}
end

# A fresh user draft (one active text typein) for the composer input pane.
_default_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function Assistant(; conversation::ConversationConversation = ConversationConversation(),
                              input::PrimitiveString = PrimitiveString(""),
                              draft::ConversationDraft = _default_draft(),
                              model::AbstractString = DEFAULT_ASSISTANT_MODEL,
                              system::AbstractString = DEFAULT_ASSISTANT_SYSTEM,
                              api_key::AbstractString = "",
                              status::Symbol = :idle,
                              collapse_thinking::Bool = true,
                              llm::Union{Nothing,Llm} = nothing)
    a = Assistant(Cell(conversation), Cell(input), Cell(draft),
                           Cell(String(model)), Cell(String(system)),
                           Cell(String(api_key)), Cell(status),
                           Cell(collapse_thinking),
                           Cell(llm),
                           Cell(nothing))
    # Back-link the draft to its owning assistant so the composer's ENTER can be
    # turned into a submit (push into the conversation + stream a reply).
    draft.assistant = a
    a
end

set_cell_function!(a::Assistant, f::Function) = (set_cell_function!(getfield(a, :conversation), f); a)

end # module AssistantModule
