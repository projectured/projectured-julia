# WorkbenchAssistant: wire up real Claude conversations

## Context

The [workbench-assistant](../done/workbench-assistant.md) and
[workbench-assistant-mvp](../done/workbench-assistant-mvp.md) plans built the
full machinery for an in-editor AI chat:

- Anthropic SSE client ([program/src/editor/Anthropic.jl](../../program/src/editor/Anthropic.jl))
- shared tool/resource registry ([program/src/editor/ToolRegistry.jl](../../program/src/editor/ToolRegistry.jl))
- MCP bridge ([program/src/editor/Mcp.jl](../../program/src/editor/Mcp.jl)) registering the same tools/resources
- `Conversation` document domain with reactive `CellVector` thunks
- syntax-based rendering ([program/src/projection/primitive/ConversationToSyntax.jl](../../program/src/projection/primitive/ConversationToSyntax.jl))
- agent loop, SSE event handler, markdown→blocks parser, tool dispatch, message builder, schema helpers — all in [program/src/editor/WorkbenchAssistant.jl](../../program/src/editor/WorkbenchAssistant.jl)
- keybindings (Enter / Alt+Enter), event routing through the workbench, and headless test coverage

The MVP step explicitly stubbed `SubmitProseOperation` with a canned `"Yes, sir!"` reply so the layout work could iterate without a network round-trip. That stub is the only thing standing between the editor and a real Claude conversation. There is also one reactive-cell issue that would otherwise make streaming deltas invisible until the next structural mutation.

## Design: pluggable LLM backend

To preserve the value of the canned-reply implementation (offline development,
deterministic tests, fast feedback when iterating on layout), introduce a
small `LlmBackend` abstraction. `SubmitProseOperation` always dispatches
through the backend; the choice between fake and real Claude becomes a single
field on `WorkbenchAssistant`.

```
abstract type LlmBackend end

# Drive a single Claude turn. Emits SSE-shaped events to `on_event` so the
# existing `_handle_sse_event!` works unchanged. Implementations decide how
# to materialise those events (real HTTP+SSE vs. synthetic in-memory).
function stream_turn(backend::LlmBackend, model, system, messages, tools; on_event) end

struct FakeLlm <: LlmBackend
    reply::String         # e.g. "Yes, sir!"
    chunk_size::Int       # 1 = char-by-char; len(reply) = single delta
    delay::Float64        # seconds between chunks (default 0)
end

struct AnthropicLlm <: LlmBackend
    base_url::String      # default "https://api.anthropic.com/v1/messages"
    max_tokens::Int       # default 4096
end
```

`FakeLlm.stream_turn` synthesises `message_start` → `content_block_start(text)`
→ N × `content_block_delta(text_delta)` → `content_block_stop` →
`message_delta(stop_reason=end_turn)` → `message_stop`, optionally with a
`sleep(delay)` between deltas so the streaming visibility code path
(step 2 below) gets exercised by tests as well.

`AnthropicLlm.stream_turn` is the existing
[`AnthropicModule.stream_message`](../../program/src/editor/Anthropic.jl#L32)
wrapped to match the `LlmBackend` interface (the function already takes
`on_event`).

Add an `llm::LlmBackend` field to `WorkbenchAssistant`. Default it to
`AnthropicLlm()` when `ANTHROPIC_API_KEY` is set, `FakeLlm("Yes, sir!")`
otherwise — so the example still runs offline. The model/system/api_key
fields stay where they are; the backend reads them off the assistant when
`stream_turn` is invoked.

```julia
@document struct WorkbenchAssistant <: WorkbenchDocument
    conversation::ConversationConversation
    input::PrimitiveString
    model::String
    system::String
    api_key::String
    status::Symbol
    llm::LlmBackend            # ← new
    selection::Reference
end
```

`_run_agent_loop!` swaps its single `stream_message(...)` call for
`stream_turn(a.llm, a.model, a.system, msgs, tools; on_event = ...)` — no
other change to the loop, the SSE handler, the markdown reparse, or the
tool-result interleave logic.

## What's missing

Four concrete changes. Everything else (tool calls, SSE parsing, markdown rendering, message history, error handling, JSON schemas) is in place and unused.

### 1. Introduce `LlmBackend` with `FakeLlm` and `AnthropicLlm`

New file `program/src/editor/Llm.jl` (or a section inside `WorkbenchAssistant.jl` — same module load layer):

```julia
abstract type LlmBackend end

# Real Claude — thin wrapper around the existing AnthropicModule.stream_message.
struct AnthropicLlm <: LlmBackend
    base_url::String
    max_tokens::Int
end
AnthropicLlm(; base_url = "https://api.anthropic.com/v1/messages",
               max_tokens = 4096) = AnthropicLlm(base_url, max_tokens)

function stream_turn(b::AnthropicLlm, api_key, model, system, messages, tools; on_event)
    stream_message(api_key, model, system, messages, tools;
                   on_event = on_event,
                   max_tokens = b.max_tokens,
                   base_url = b.base_url)
end

# Canned-reply fake — emits the existing SSE event shapes so the agent loop
# and `_handle_sse_event!` don't change.
struct FakeLlm <: LlmBackend
    reply::String
    chunk_size::Int
    delay::Float64
end
FakeLlm(reply = "Yes, sir!"; chunk_size = 1, delay = 0.0) =
    FakeLlm(String(reply), chunk_size, delay)

function stream_turn(b::FakeLlm, _api_key, _model, _system, _messages, _tools; on_event)
    on_event((type = :message_start, data = Dict()))
    on_event((type = :content_block_start,
              data = Dict(:content_block => Dict(:type => "text"))))
    i = 1
    while i <= length(b.reply)
        j = min(i + b.chunk_size - 1, length(b.reply))
        on_event((type = :content_block_delta,
                  data = Dict(:delta => Dict(:type => "text_delta",
                                              :text => b.reply[i:j]))))
        b.delay > 0 && sleep(b.delay)
        i = j + 1
    end
    on_event((type = :content_block_stop, data = Dict()))
    on_event((type = :message_delta,
              data = Dict(:delta => Dict(:stop_reason => "end_turn"))))
    on_event((type = :message_stop, data = Dict()))
    nothing
end
```

Add the `llm::LlmBackend` field to `WorkbenchAssistant` (see Design above).
Pick a sensible default:

```julia
function WorkbenchAssistant(; …,
                              llm::LlmBackend = isempty(get(ENV, "ANTHROPIC_API_KEY", ""))
                                                  ? FakeLlm()
                                                  : AnthropicLlm())
    …
end
```

This keeps `run_example(assistant_example)` working offline (using `FakeLlm`)
while making `export ANTHROPIC_API_KEY=...` enough to switch to real Claude.

### 2. Un-stub `SubmitProseOperation`

[program/src/editor/WorkbenchAssistant.jl:170-186](../../program/src/editor/WorkbenchAssistant.jl#L170-L186) — replace the canned reply with a call to the existing `_run_agent_loop!`, kicked off on an `@async` task so the editor's read loop keeps spinning:

```julia
function evaluate_operation(op::SubmitProseOperation, _document)
    a = op.assistant
    text = _text_to_string(a.input)
    isempty(strip(text)) && return nothing

    push!(a.conversation, ConversationUserMessage(text))
    _set_input!(a, "")
    a.status = :streaming

    @async begin
        try
            _run_agent_loop!(a)
        catch e
            a.status = :error
            push!(a.conversation,
                  ConversationToolResultMessage("error",
                      sprint(showerror, e, catch_backtrace()); is_error=true))
        finally
            a.status === :streaming && (a.status = :idle)
        end
    end
    nothing
end
```

Inside `_run_agent_loop!` ([line 359](../../program/src/editor/WorkbenchAssistant.jl#L359)), replace the single direct call

```julia
stream_message(a.api_key, a.model, a.system, msgs, tools;
               on_event = ev -> _handle_sse_event!(ev, a, assistant_msg, state))
```

with the backend dispatch:

```julia
stream_turn(a.llm, a.api_key, a.model, a.system, msgs, tools;
            on_event = ev -> _handle_sse_event!(ev, a, assistant_msg, state))
```

Everything else (`_handle_sse_event!` at [line 412](../../program/src/editor/WorkbenchAssistant.jl#L412), `assistant_tool_schemas` at [line 211](../../program/src/editor/WorkbenchAssistant.jl#L211), `dispatch_assistant_tool` at [line 242](../../program/src/editor/WorkbenchAssistant.jl#L242), `build_messages` at [line 264](../../program/src/editor/WorkbenchAssistant.jl#L264), `_replace_last_block!`, `parse_markdown_blocks`) stays unchanged.

**`@async` (single-threaded scheduling) is the right primitive** — the cell system is not promised thread-safe; do not use `Threads.@spawn`.

### 3. Make text leaves **reactive** in `ConversationToSyntax`

[program/src/projection/primitive/ConversationToSyntax.jl](../../program/src/projection/primitive/ConversationToSyntax.jl) currently bakes the rendered text at projection-print time:

```julia
SyntaxLeaf(_empty_ts(), _empty_ts(),
           _ts(_text_to_string(b.text)))     # ← eager value, no dep on b.text
```

The SSE handler appends text deltas via [`_append_text_delta!`](../../program/src/editor/WorkbenchAssistant.jl#L476):

```julia
block.text = TextText(TextString(current * String(s)))
```

That reassignment invalidates `block.text` — but the `TextString` inside the `SyntaxLeaf` was constructed with a frozen `String`, so the rendered output ignores the update. Tokens stop appearing until the next *structural* change (e.g. `message_stop` runs the markdown reparser, which replaces the whole block).

The fix mirrors what [`JsonStringToSyntaxLeaf`](../../program/src/projection/primitive/JsonToSyntax.jl#L119-L125) already does: give the leaf a *thunked* `TextString` whose content is a function of `b.text`.

```julia
# In ConversationToSyntax.jl:
_ts(f::Function)                  = TextString(f, _FONT, _TEXT_COL)
_ts(f::Function, font, color)     = TextString(f, font, color)

# Per-message/block projections — swap the eager calls for closures.
function projection_print(p::ConversationTextBlockToSyntaxLeaf, b::ConversationTextBlock, recursion, reference)
    leaf = SyntaxLeaf(_empty_ts(), _empty_ts(),
                      _ts(() -> _text_to_string(b.text)))
    SimpleIoMap(p, b, leaf)
end
```

Apply the same change to every place that reads a runtime-mutable text via `_text_to_string`:

- `ConversationUserMessageToSyntaxNode` — body leaf
- `ConversationAssistantMessageToSyntaxNode` — (no leaf; the block thunks already handle the structural reactivity)
- `ConversationToolResultMessageToSyntaxNode` — body leaf
- `ConversationJuliaInputMessageToSyntaxNode` — code leaf (read `m.code.name` reactively)
- `ConversationJuliaResultMessageToSyntaxNode` — output leaf
- `ConversationTextBlockToSyntaxLeaf` — body leaf
- `ConversationCodeBlockToSyntaxNode` — body leaf
- `ConversationHeadingBlockToSyntaxLeaf` — body leaf
- `ConversationListBlockToSyntaxNode` — item leaves (already in a thunked `CellVector`; widen the per-item leaf the same way)
- `ConversationToolUseBlockToSyntaxLeaf` / `ConversationToolUseMessageToSyntaxLeaf` — input dict can be re-rendered if needed

The `CellVector(() -> …)` thunks already in this file handle *structural* changes (message appended, block appended). Leaf thunks handle *value* changes (delta appended to existing block). Both are needed for streaming.

**Why this isn't optional for streaming**: without it, a 200-token reply visually arrives all at once at `message_stop`. With it, you see characters land as the SSE stream produces them — and `iomap` invalidation in the editor loop is *not* a substitute because we only invalidate `iomap` after evaluating an `Operation`, and SSE deltas mutate cells without going through an operation.

### 4. Set `ANTHROPIC_API_KEY` (only when you want real Claude)

With the default backend selection from step 1, the example uses `FakeLlm`
when `ANTHROPIC_API_KEY` is unset, and `AnthropicLlm` when it is. So:

```sh
# offline / deterministic
julia --project=. -e 'using Projectured, ProjecturedExample; run_example(assistant_example)'

# real Claude
export ANTHROPIC_API_KEY=sk-ant-...
julia --project=. -e 'using Projectured, ProjecturedExample; run_example(assistant_example)'
```

Override per-construction when you need explicit control:

```julia
assistant = WorkbenchAssistant(; llm = FakeLlm("Hello there"; chunk_size = 3, delay = 0.05))
# or
assistant = WorkbenchAssistant(; llm = AnthropicLlm(max_tokens = 1024))
```

`_run_agent_loop!` still errors with `"ANTHROPIC_API_KEY is not set"` when an
`AnthropicLlm` is selected with an empty key — failure mode stays loud.

## Verification

### Headless smoke (no SDL)

The existing [test/src/editor/AssistantMvpTest.jl](../../test/src/editor/AssistantMvpTest.jl) keeps working with a small adjustment: construct the assistant with `WorkbenchAssistant(; llm = FakeLlm("Yes, sir!"))` to make the behavior identical to today's stub. With `chunk_size = length(reply)` and `delay = 0.0` the fake produces one delta then `message_stop`, so the post-`@async` assertions need a brief `wait` (poll `a.status === :idle`) or just call `stream_turn` synchronously in tests (a `_run_agent_loop_sync!` helper that skips the `@async` is the cleanest path for asserting end state).

Add a new subtest that swaps in a different `FakeLlm` to prove the dispatch works:

```julia
@testset "FakeLlm dispatch" begin
    a = WorkbenchAssistant(; llm = FakeLlm("hi there"))
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0,0), EmptyReferencePath()))
    _mvp_type!(a, "ping")
    _mvp_enter!(a)
    # wait for @async to finish
    while a.status === :streaming; sleep(0.01); end
    @test _text_to_string(a.conversation.messages[end].blocks[end].text) == "hi there"
end
```

### Interactive smoke

```julia
ENV["ANTHROPIC_API_KEY"] = "sk-ant-..."
using Projectured, ProjecturedExample
run_example(assistant_example)
# type "Say hi briefly" + Enter
# expect: tokens appear character-by-character; final reply re-renders as
# structured blocks once `message_stop` fires the markdown reparse.
```

### Tool round-trip

```julia
# type "What guides are available?" + Enter
# expect: a tool_use message for `list_resources`, then a tool_result
# message with the markdown listing, then a final summarising text block.
```

### Julia interleave

```julia
# type "1 + 2 * 3" + Alt+Enter
# expect: ConversationJuliaInputMessage + ConversationJuliaResultMessage("7") rows.
# then type "what did I just compute?" + Enter
# expect: Claude's next request body includes a synthetic user message
# describing the eval (`build_messages` already does this).
```

## Out of scope (deliberate)

- **Esc cancels streaming** — would need a cancellation flag on `WorkbenchAssistant` plus a check in the SSE loop. One afternoon's work but not blocking.
- **Status indicator in the panel** — render `a.status` as a small label next to the input. Cosmetic.
- **Real `JuliaDocument` for julia-input messages** — today `ConversationJuliaInputMessage.code` is a `JuliaIdentifier` containing the raw source; integrating the real Julia reader would unlock syntax highlighting through `JuliaToSyntax`. Cosmetic but increasingly visible as julia interleave is used.
- **Persistence** — not in scope per the original interview decision.
- **Selection forwarding through ConversationToSyntax** — `map_reference_forward` / `_backward` are no-ops; clicking on rendered text doesn't move the cursor into the source. Requires the same shape of work as `JsonToSyntax`'s reference mapping but the conversation tree is different enough to need its own design.

## Critical files (quick reference)

**Create**
- `program/src/editor/Llm.jl` — `LlmBackend`, `AnthropicLlm`, `FakeLlm`, `stream_turn` (step 1). Wire into [Projectured.jl](../../program/src/Projectured.jl) between `Anthropic.jl` and `WorkbenchAssistant.jl`.

**Edit**
- [program/src/document/Workbench.jl](../../program/src/document/Workbench.jl) — add the `llm::LlmBackend` field (step 1)
- [program/src/editor/WorkbenchAssistant.jl](../../program/src/editor/WorkbenchAssistant.jl) — un-stub `SubmitProseOperation`, replace `stream_message(...)` inside `_run_agent_loop!` with `stream_turn(a.llm, ...)` (step 2)
- [program/src/projection/primitive/ConversationToSyntax.jl](../../program/src/projection/primitive/ConversationToSyntax.jl) — thunked leaf values (step 3)
- [test/src/editor/AssistantMvpTest.jl](../../test/src/editor/AssistantMvpTest.jl) — construct with `llm = FakeLlm(...)`, add a `FakeLlm` dispatch subtest

**Reuse without modification**
- [program/src/editor/Anthropic.jl](../../program/src/editor/Anthropic.jl) — `stream_message` (called from `AnthropicLlm.stream_turn`)
- [program/src/editor/ToolRegistry.jl](../../program/src/editor/ToolRegistry.jl) — `call_tool`, `list_tools`, `list_resources`, `anthropic_tool_schema`
- [program/src/editor/Mcp.jl](../../program/src/editor/Mcp.jl) — `register_default_tools_and_resources!`
- The agent loop / SSE handler / message builder / tool dispatch / markdown parser in [WorkbenchAssistant.jl](../../program/src/editor/WorkbenchAssistant.jl) — unchanged except for the single `stream_message` → `stream_turn` swap
