# WorkbenchAssistant: in-editor AI chat with shared tools & Julia eval

## Context

`WorkbenchAssistant` already exists as a placeholder ([program/src/document/Workbench.jl:265-281](../program/src/document/Workbench.jl#L265-L281)) with a single `content::Any` field defaulting to `nothing`. It is already wired into the workbench layout and the widget projection ([program/src/projection/primitive/WorkbenchToWidget.jl:192-199](../program/src/projection/primitive/WorkbenchToWidget.jl#L192-L199)) but has no real content.

predj already runs an MCP **server** ([program/src/editor/Mcp.jl](../program/src/editor/Mcp.jl)) on port 9876 that lets *external* AI clients drive the editor. The goal of this work is the opposite direction: build an *internal* AI client — a chat surface inside predj where the user converses with Claude, Claude calls the same tools the MCP server exposes (without HTTP round-trip), and the user can interleave Julia code that runs locally and stays visible in Claude's history.

The whole conversation, including in-flight streaming, must be a real predj domain (cells, operations, projections, bidirectional reader), so selection and editing inside messages compose with the rest of the editor.

### Key decisions (resolved during interview)

| Decision | Choice |
|---|---|
| LLM backend | Anthropic Claude API direct HTTP (no abstraction layer for v1). `ANTHROPIC_API_KEY` env var; default model `claude-opus-4-7`. |
| Conversation data model | New `Conversation` domain with structured message and block types. |
| Tool dispatch | Shared in-process registry; the MCP server and the assistant both call into it directly (no localhost HTTP loopback). |
| Julia eval | Registered as one of the shared tools **and** exposed as a first-class user keybinding. |
| Streaming | SSE; deltas write into cells incrementally; UI re-renders mid-response. |
| Tool gating | Auto-execute; agent loop until `stop_reason != "tool_use"`. |
| Input field | Stored as a separate field on `WorkbenchAssistant` (not in the message list). Two submit operations on different keybindings. |
| Assistant rendering | Parse markdown into structured blocks: prose `TextText`, code blocks become `JuliaDocument` when language is julia (else monospace `TextText`), plus headings/lists. |
| Persistence | None in v1. |
| User-initiated Julia evals visible to Claude | Yes — synthesized as a user message on the next turn ("I ran `<code>` and got: `<output>`"). |
| Documentation pathway | MCP **resources**, not tools (AI consumes resources more easily). Registry holds tools + resources separately; assistant bridges resources to the Anthropic API via two thin tools. |

## Architecture

```
┌── WorkbenchAssistant ─────────────────────────────────────────┐
│  conversation : ConversationConversation  (full history)      │
│  input        : TextText                  (editable prompt)   │
│  model        : Cell{String}              (default claude…)   │
│  system       : Cell{String}              (hardcoded prompt)  │
│  api_key      : Cell{String}              (from ENV)          │
│  status       : Cell{Symbol}              (:idle|:streaming…) │
│  selection    : Reference                                     │
└───────────────┬───────────────────────────────────────────────┘
                │ contains
                ▼
        ConversationConversation
          messages: CellVector{ConversationMessage}

        ConversationMessage (abstract)
          ConversationUserMessage        { text::TextText }           ← prose Enter
          ConversationAssistantMessage   { blocks::CellVector{Block}, stop_reason::Cell{Symbol} }
          ConversationToolUseMessage     { id, name, input::JsonObject, status::Cell }   ← Claude requested this
          ConversationToolResultMessage  { tool_use_id, content::TextText, is_error::Cell }
          ConversationJuliaInputMessage  { code::JuliaDocument }      ← Alt+Enter
          ConversationJuliaResultMessage { output::TextText, is_error::Cell }

        Block (inside AssistantMessage)
          ConversationTextBlock          { text::TextText }
          ConversationCodeBlock          { language::String, body::Union{JuliaDocument,TextText} }
          ConversationHeadingBlock       { level::Int, text::TextText }
          ConversationListBlock          { items::CellVector{TextText} }
          ConversationToolUseBlock       { id, name, input::JsonObject }      ← rendered inline
```

Submit flow (prose / Enter):

```
input(TextText) ──SubmitProseOperation──▶ snapshot text
        │
        ├──▶ append ConversationUserMessage(text) to conversation
        ├──▶ clear input
        ├──▶ status := :streaming
        └──▶ @async Anthropic.stream_message(api_key, model, system,
                                              build_messages(conversation), tools)
                  on event ────────────────────────────────────────────────────
                  · message_start             → push! ConversationAssistantMessage
                  · content_block_start text  → push! ConversationTextBlock("")
                  · content_block_delta text  → append to current block's TextText cell
                  · content_block_start tool  → push! ConversationToolUseBlock(id,name,partial)
                  · content_block_delta input → JSON-accumulate into input
                  · content_block_stop tool   → ToolRegistry.call_tool(name,input,editor)
                                                push! ConversationToolResultMessage(...)
                                                if any tool_use blocks present → re-POST
                  · message_stop              → status := :idle
```

Submit flow (Julia / Alt+Enter):

```
input(TextText) ──SubmitJuliaOperation──▶ parse via Julia reader
        │
        ├──▶ append ConversationJuliaInputMessage(JuliaDocument)
        ├──▶ ToolRegistry.call_tool("execute_julia_code", {code}, editor)
        ├──▶ append ConversationJuliaResultMessage(output)
        └──▶ clear input
                  (no Claude call now; the pair is folded into the next
                   build_messages() turn as a synthetic user message)
```

## Implementation

### 1. Dependencies — [program/Project.toml](../program/Project.toml)
Add:
```toml
HTTP   = "cd3eb016-35fb-5094-929b-558a96fad6f3"
JSON3  = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
```

### 2. Shared registry — NEW `program/src/editor/ToolRegistry.jl`
The MCP layer already distinguishes **tools** (actions, e.g. `execute_julia_code`) from **resources** (read-only data with URIs, e.g. `resource://guides`, `resource://module/<name>`). The assistant must honor this split — Claude consumes documentation through resources, not tools.

The registry holds both:

```julia
struct Tool
    name::String
    description::String
    parameters::Vector{NamedTuple}     # name,type,description,required
    handler::Function                   # (editor, args::Dict) -> String
end

struct Resource
    uri::String                         # e.g. "resource://guide/getting-started"
    name::String
    description::String
    mime_type::String                   # default "text/markdown"
    provider::Function                  # () -> String   (or (uri) -> String for templated)
end

# tools
register_tool!(t::Tool)
list_tools()                                -> Vector{Tool}
call_tool(name, args, editor)               -> String
anthropic_tool_schema(tools)                -> Vector{Dict}
mcp_tools(editor, tools)                    -> Vector{MCPTool}

# resources
register_resource!(r::Resource)
register_resources!(rs::Vector{Resource})
list_resources()                            -> Vector{Resource}
read_resource(uri)                          -> String
mcp_resources(resources)                    -> Vector{MCPResource}
```

The existing handler functions in [program/src/editor/Mcp.jl:84-328](../program/src/editor/Mcp.jl#L84-L328) stay byte-for-byte; only their *registration sites* move:
- `execute_julia_code` → registered as a **Tool**.
- `list_guides`, `read_guide`, `list_modules`, `list_classes`, `list_functions`, `read_module_documentation`, `read_class_documentation`, `read_function_documentation` → registered as **Resource** providers (matching how `_make_resources` in [program/src/editor/Mcp.jl:404-486](../program/src/editor/Mcp.jl#L404-L486) already exposes them).

Update [program/src/editor/Mcp.jl](../program/src/editor/Mcp.jl): `_make_tools` and `_make_resources` become thin adapters: `mcp_tools(editor, list_tools())` and `mcp_resources(list_resources())`. No behavioral change for external MCP clients.

#### Exposing resources to the Anthropic API
The Anthropic Messages API has tools but no native concept of "resources". Bridge by registering **two extra tools** (only at the assistant layer — not exported as MCP tools, to avoid duplication for external clients):

- `list_resources()` → returns a markdown bullet list of all registered resource URIs with their descriptions.
- `read_resource(uri)` → calls `ToolRegistry.read_resource(uri)`.

The assistant's system prompt instructs Claude to use these (and lists the most important URIs up front, mirroring the existing MCP server description at [program/src/editor/Mcp.jl:41-50](../program/src/editor/Mcp.jl#L41-L50)). This keeps the documentation pathway uniformly "resource-shaped" inside the registry, while still making it usable through the Anthropic tool-use interface.

### 3. Anthropic HTTP+SSE client — NEW `program/src/editor/Anthropic.jl`
Single function:
```julia
stream_message(api_key, model, system, messages, tools; on_event)
```
- POST `https://api.anthropic.com/v1/messages` with `stream=true`, `anthropic-version: 2023-06-01`.
- Parses SSE `data: {...}` lines incrementally with `JSON3.read`.
- Invokes `on_event(event::NamedTuple)` for each event. Event types follow Anthropic's streaming spec (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`).
- Errors raise; caller can catch and append a `ConversationAssistantMessage` with an error text block + set `status := :error`.

This file owns only protocol concerns. It must not touch cells or documents.

### 4. Conversation domain — NEW `program/src/document/Conversation.jl`
Define the types in the diagram above using `@document` (mirror the patterns in [program/src/document/Text.jl](../program/src/document/Text.jl) and [program/src/document/Json.jl](../program/src/document/Json.jl)). Each concrete subtype carries `selection::Reference` and wraps its mutable parts in `Cell` via the macro.

Operations live alongside the domain:
- `SubmitProseOperation`  — kicks off the Claude turn, async, mutates conversation cells.
- `SubmitJuliaOperation`  — synchronous: parse, eval via `ToolRegistry.call_tool`, append.
- `AppendAssistantBlockOperation` / `AppendBlockDeltaOperation` — used internally by the SSE event handler so all mutations flow through operations (matches the operation discipline in [program/src/api/Operation.jl:19](../program/src/api/Operation.jl#L19)).
- `ClearInputOperation`, `ResetConversationOperation`.

`build_messages(conversation)`: walks the message list and produces the JSON array Anthropic expects:
- `ConversationUserMessage` → `{role: "user", content: [{type: "text", text: ...}]}`
- `ConversationAssistantMessage` → `{role: "assistant", content: [...blocks rendered as text/tool_use...]}`
- `ConversationToolUseMessage` → folded into the preceding assistant message as a `tool_use` content block.
- `ConversationToolResultMessage` → `{role: "user", content: [{type: "tool_result", tool_use_id, content}]}`
- `ConversationJuliaInputMessage` + following `ConversationJuliaResultMessage` → synthesized as one `{role: "user", content: "I ran the following Julia code:\n\`\`\`julia\n<code>\n\`\`\`\nResult:\n\`\`\`\n<output>\n\`\`\`"}`.

### 5. Markdown → blocks (streaming-safe)
For the assistant's incoming text, we cannot fully parse markdown until the stream stops (a fence may be unclosed). Approach:
- Buffer the raw streaming text in a "scratch" `TextText` block (rendered live as monospace prose).
- On `content_block_stop` for a text block, re-parse the full block text with the stdlib `Markdown.parse` and replace the scratch block with a sequence of structured blocks.
- For code blocks where ``language == "julia"``, parse the code with `Meta.parseall` and wrap into a `JuliaDocument` (existing reader in [program/src/document/Julia.jl](../program/src/document/Julia.jl)).

This keeps streaming responsive without trying to write a partial markdown parser. Acceptable v1 trade-off: live formatting is plain; final formatting is structured.

### 6. Projection — NEW `program/src/projection/primitive/ConversationToWidget.jl`
A `TypeDispatchingProjection` whose printer maps:
- `ConversationConversation` → `WidgetComposite` (vertical) containing one widget per message **plus the input row at the bottom**. The input row is a thin composite wrapping the assistant's `input::TextText` (selection descends into it via `FieldReference("input")` from the parent `WorkbenchAssistant`).
- Each message subtype → `WidgetComposite` of its blocks/content with role label.
- `ConversationTextBlock` → a `TextText` (use existing `TextToGraphics`).
- `ConversationCodeBlock` (julia) → recurse into the `JuliaDocument` via `JuliaToSyntax` then `SyntaxToText`.
- `ConversationToolUseBlock`, `ConversationToolResultMessage` → labeled `TextText` with a distinct style (gray padding, monospace).

The reader maps text-edit operations on the input's `TextText` back into the `input` cell (this just means producing the right `ReferencePath` and delegating to the text reader — see [program/src/projection/primitive/TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl)).

Export a `ConversationToWidget` `TypeDispatchingProjection` like `WorkbenchToWidget`.

### 7. Wire into Workbench
Edit [program/src/document/Workbench.jl:265-281](../program/src/document/Workbench.jl#L265-L281): replace `content::Any` with explicit fields (`conversation`, `input`, `model`, `system`, `api_key`, `status`). Update the constructor to take optional overrides and default `conversation` to an empty `ConversationConversation()`, `input` to an empty `TextText("")`, `api_key` to `get(ENV, "ANTHROPIC_API_KEY", "")`.

Edit [program/src/projection/primitive/WorkbenchToWidget.jl:192-199](../program/src/projection/primitive/WorkbenchToWidget.jl#L192-L199): instead of recursing on `a.content`, recurse on `a.conversation` (and the projection chain reaches `ConversationToWidget` defined in step 6). The `WidgetScrollPane` wrapper stays.

### 8. Keybindings
Find the editor's keybinding/operation-dispatch site (the editor REPL loop — [program/src/editor/Editor.jl](../program/src/editor/Editor.jl) area) and register:
- `Enter`   when the assistant input has focus → `SubmitProseOperation`
- `Alt+Enter` when the assistant input has focus → `SubmitJuliaOperation`

If keybindings are document-scoped (likely), add them where the existing text-input keybindings live. (Worth a quick look at how `WorkbenchEvaluator` accepts input today — it's a placeholder, so it may need parallel work; out of scope for this plan.)

### 9. Async / cell-write safety
`@async` (single-threaded scheduling, like the existing `mcp.task = @async start!(mcp.server)` at [program/src/editor/Mcp.jl:73](../program/src/editor/Mcp.jl#L73)) is the right primitive. All cell writes happen inside the streaming task via the operation API. The render loop reads cells on its next tick and re-renders. Do **not** use `Threads.@spawn` — the cell system is not promised thread-safe.

### 10. Module include & exports
Add the new files to `program/src/Projectured.jl` (or wherever the module includes live; mirror how `Mcp.jl` and `Workbench.jl` are included).

## Critical files

**Edit**
- [program/src/document/Workbench.jl](../program/src/document/Workbench.jl) — fill in `WorkbenchAssistant`
- [program/src/projection/primitive/WorkbenchToWidget.jl](../program/src/projection/primitive/WorkbenchToWidget.jl) — recurse into conversation
- [program/src/editor/Mcp.jl](../program/src/editor/Mcp.jl) — delegate tool list to `ToolRegistry`
- [program/Project.toml](../program/Project.toml) — add HTTP, JSON3
- `program/src/Projectured.jl` (or equivalent) — register new modules

**Create**
- `program/src/editor/ToolRegistry.jl`
- `program/src/editor/Anthropic.jl`
- `program/src/document/Conversation.jl`
- `program/src/projection/primitive/ConversationToWidget.jl`

**Reuse / reference**
- Existing handlers in [program/src/editor/Mcp.jl:84-328](../program/src/editor/Mcp.jl#L84-L328) — `execute_julia_code` re-registered as a Tool; the documentation/reflection helpers re-registered as Resource providers. Bodies unchanged.
- Existing resource registration shape in [program/src/editor/Mcp.jl:404-486](../program/src/editor/Mcp.jl#L404-L486) — port the URI/template/walkdir-of-guides logic into `ToolRegistry` resource registration.
- [program/src/document/Text.jl](../program/src/document/Text.jl), [program/src/document/Json.jl](../program/src/document/Json.jl) — domain pattern templates
- [program/src/document/Julia.jl](../program/src/document/Julia.jl) — for `ConversationCodeBlock` (julia) and `ConversationJuliaInputMessage`
- [program/src/api/Operation.jl:19](../program/src/api/Operation.jl#L19) — `Operation` abstract type
- [program/src/projection/primitive/TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl) — reference for the input reader

## Verification

1. **Smoke / unit**
   - `using Projectured; ToolRegistry.list_tools()` returns the `execute_julia_code` tool.
   - `ToolRegistry.list_resources()` returns the guide / module / class / function resources.
   - `ToolRegistry.call_tool("execute_julia_code", Dict("code"=>"1+1"), nothing)` returns `"2\n"`.
   - `ToolRegistry.read_resource("resource://guides")` returns a non-empty markdown listing.
   - `build_messages(empty_conversation())` returns `[]`.

2. **MCP server regression** — start the editor, confirm port 9876 still serves `execute_julia_code` as a tool and `resource://guides` etc. as resources (call via `curl` against the SSE endpoint or an MCP client).

3. **End-to-end chat** — set `ANTHROPIC_API_KEY`, `run_example` for an editor with a `WorkbenchAssistant` panel. Type "hello" + Enter, confirm a streaming response appears character-by-character, the response gets re-rendered as structured blocks at `message_stop`, and the panel re-renders without freezing.

4. **Resource round-trip** — ask "what guides are available?" and confirm Claude calls the bridging `list_resources` tool, then `read_resource("resource://guide/getting-started")` (or similar), with both `ConversationToolUseMessage` + `ConversationToolResultMessage` pairs appearing inline before Claude's final summary.

5. **Julia interleave** — type `editor.document |> typeof` + Alt+Enter, confirm `ConversationJuliaInputMessage` + `ConversationJuliaResultMessage` are appended locally. Then type "what did I just print?" + Enter and confirm Claude sees the prior exec (i.e., the next request body contains a synthesized user message describing the eval).

6. **Selection / editing** — use the existing text-edit operations on the input `TextText` (cursor move, insert, delete) and confirm selection propagates through `WorkbenchAssistant.input` correctly. Open the descriptor panel and confirm it shows a sane reference path into the input.

7. **Streaming cancellation (nice to have)** — pressing Esc while streaming should set `status := :idle` and stop appending deltas; the task should observe a cancellation flag and exit. (Optional for v1; flag if deferred.)
