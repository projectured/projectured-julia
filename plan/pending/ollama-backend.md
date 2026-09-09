# Add an Ollama backend, and give each backend its own name

> **Kind:** plan · **Status:** pending · **Stands on:**
> [package-rules.md](../../documentation/rule/package-rules.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [agent.md](../../documentation/package/kernel/agent.md)

## The goal

Drive the AI assistant with a local Ollama model. Today the only real backend is
Anthropic, and the package that holds it is called `ProjecturedLlm` — the name of
the abstraction, not of the provider. A second provider makes that name wrong.
So this plan does two things at once:

1. Give each backend its own name, at every level: package, source folder, type,
   and selector symbol.
2. Add the Ollama adapter, and a seam that selects a backend by name.

## What exists now

The kernel owns the abstraction and nothing else:

| piece | file |
| --- | --- |
| `Llm`, `stream_turn`, `tool_schema` | [Llm.jl](../../source/kernel/llm/Llm.jl) |
| `LlmMessage`, `LlmContent`, `LlmRequest` | [LlmMessage.jl](../../source/kernel/llm/LlmMessage.jl) |
| `LlmEvent` and its 14 subtypes | [LlmEvent.jl](../../source/kernel/llm/LlmEvent.jl) |
| `run_turn!`, the round loop | [AgentLoop.jl](../../source/kernel/agent/AgentLoop.jl) |

One adapter implements the seam: `AnthropicLlm` in
[source/llm/Llm.jl](../../source/llm/Llm.jl), packaged as
[ProjecturedLlm](../../package/ProjecturedLlm/src/ProjecturedLlm.jl). It renders a
request into Anthropic JSON and translates the Server-Sent Events stream back into
`LlmEvent`s.

The assistant finds that adapter by a reflection scan in
[AssistantTurn.jl:610](../../source/assistant/AssistantTurn.jl#L610):

```julia
function _discover_remote_llm(api_key::AbstractString, model::AbstractString)
    for m in values(Base.loaded_modules)
        nameof(m) === :ProjecturedLlm || continue
        isdefined(m, :AnthropicLlm) || continue
        return Base.invokelatest(getfield(m, :AnthropicLlm); api_key = api_key, model = model)
    end
    nothing
end
```

Two things block a second provider here. The scan names one package and one type.
And the caller only reaches it when an API key is present
([AssistantTurn.jl:630-637](../../source/assistant/AssistantTurn.jl#L630)), which a
local model never has.

## The Ollama wire format

I measured this against the Ollama server that runs on this machine (version
0.33.1), not from memory. Every claim below is a recorded response.

**The endpoint is `POST /api/chat`.** The stream is newline-delimited JSON, one
object per line — not Server-Sent Events. There is no `event:` line, no `data:`
prefix, and no block framing at all.

Text:

```json
{"model":"mistral:latest","message":{"role":"assistant","content":" Hello"},"done":false}
{"model":"mistral:latest","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","eval_count":4}
```

A tool call arrives **whole, in one line**, with an id and with arguments already
parsed into an object:

```json
{"message":{"role":"assistant","content":"","tool_calls":[
  {"id":"call_xdzs68uo","function":{"index":0,"name":"get_weather","arguments":{"city":"Paris"}}}]},"done":false}
```

Note what the last line of that same turn said: `"done_reason":"stop"`. Ollama
does not report a tool call in the stop reason.

A tool result goes back as its own message. This round trip answered correctly:

```json
{"role":"tool","tool_name":"get_weather","content":"18 degrees and sunny"}
```

Reasoning is asked for with `"think": true`, and a model that does not support it
**fails the whole request with HTTP 400**:

```
{"error":"\"mistral:latest\" does not support thinking"}
```

`GET /api/tags` and `POST /api/show` both report a `capabilities` list per model,
for example `["completion","vision","tools","thinking"]`. That list is how the
adapter can know whether to send `think`. An unknown model is HTTP 404.

## Design decisions

### D1 — the seam selects a backend by name, through `Val` dispatch

Add to `LlmModule`, beside `stream_turn`:

```julia
make_llm(kind::Symbol; kwargs...) = make_llm(Val(kind); kwargs...)
make_llm(::Val{K}; kwargs...) where {K} = error(
    "No LLM backend registered for :$(K). Is the package that provides it loaded?")
```

This is the shape [PAR-OPT-IN-DEPENDENCY](../../documentation/rule/architecture-invariants.md)
already names, and the exact mirror of `make_agent_server(:mcp, editor)` in
[AgentServer.jl:29](../../source/kernel/agent/AgentServer.jl#L29). Each opt-in
package adds one method. Nothing in the core stack names a concrete backend, and
the method table is the registry — no dictionary, no mutable global, no `__init__`
registration to keep in step. See [[declare-dont-promise]].

The reflection scan `_discover_remote_llm` goes away. Which backends are available
becomes `methods(make_llm)`, and a helper `llm_backend_names()` reads that table
for the error message and for a future selector widget.

### D2 — each adapter also declares its default model

```julia
default_llm_model(kind::Symbol) = default_llm_model(Val(kind))
```

`ProjecturedAnthropic` returns the Claude id; `ProjecturedOllama` returns
`"qwen3.8:27b"`, which reports both `tools` and `thinking`.
The assistant must not send a Claude model id to Ollama, and
`DEFAULT_ASSISTANT_MODEL = "claude-opus-4-8"` in
[AssistantDocument.jl:26](../../source/assistant/AssistantDocument.jl#L26) is an
Anthropic name sitting in a provider-neutral document.

### D3 — the assistant selects by symbol, and resolves at submit time

`Assistant` gains one field, `backend::Symbol`, default `:none`. **A person says
which backend they want; nothing guesses.** The resolution order in
`_run_agent_loop!` becomes:

1. An explicit `llm` wins. This is what the tests and examples pass.
2. A named `backend` calls `make_llm(backend; …)`, and its missing-method error is
   the report.
3. `:none` errors, and the error lists `llm_backend_names()`.

There is no auto-detection. This is a decided behaviour change: a person who set
`ANTHROPIC_API_KEY` and loaded the adapter used to get Claude with no further
word, and must now write `backend = :anthropic`. The reason is that the guess was
only ever correct while one backend existed.

Resolution stays at submit time, per turn, for the reason the current code already
gives: a backend cached on the document would freeze the model that was selected
first.

`model` becomes `""` by default, meaning "the backend's own default", resolved
through D2. An explicit model string always wins.

Two constraints on this edit. `Assistant` is a `@document` with nine required
fields, so it is in the Rule Y family; adding a field changes the all-positional
arity and the new `Cell(...)` must be inserted **before** the trailing selection
cell. See [[document-ctor-arity-vs-defaults]]. Do not give any existing field a
new default in the `@document` body.

### D4 — the Ollama adapter synthesizes the block framing

The kernel's events describe blocks that open, fill and close. Ollama sends no
such framing, so the adapter keeps the open block on a local `Ref` — exactly as
the Anthropic adapter already does for `content_block_stop` — and derives the
events:

| Ollama line | events emitted |
| --- | --- |
| first non-empty `message.content` | `LlmTextStart`, then `LlmTextDelta` |
| later `message.content` | `LlmTextDelta` |
| first non-empty `message.thinking` | close any open block, `LlmThinkingStart`, `LlmThinkingDelta` |
| later `message.thinking` | `LlmThinkingDelta` |
| `message.tool_calls` entry | close any open block, `LlmToolUseStart`, one `LlmToolInputDelta`, `LlmToolUseStop` |
| `"done":true` | close any open block, then `LlmTurnEnd` |

The tool call arrives complete, so all three of its events come from one line. The
`LlmToolInputDelta` carries `JSON3.write(arguments)`, so the panel still shows the
arguments arriving; the `LlmToolUseStop` carries the parsed `Dict`.

`LlmThinkingSignature` is never emitted. Ollama has no signature, so the
`LlmThinking` blocks the assistant stores carry `""`, and the adapter drops the
field when it renders history back.

### D5 — the stop reason must count the tool calls

`run_turn!` breaks out of the loop unless the stop reason is `:tool_use`
([AgentLoop.jl](../../source/kernel/agent/AgentLoop.jl)). Ollama reports
`done_reason: "stop"` on a turn that made tool calls. So the adapter tracks whether
any tool call arrived in the turn and maps:

- a tool call arrived → `:tool_use`
- `"stop"` → `:end_turn`
- `"length"` → `:max_tokens`

Without this the assistant would show the tool call and then never run it. This is
the single most important line in the adapter.

### D6 — the request render, and the id-to-name map

- `request.system` becomes a leading `{"role":"system"}` message. Ollama has no
  top-level system field.
- `LlmText` becomes the message `content`.
- `LlmThinking` becomes the assistant message's `thinking` field.
- `LlmRedactedThinking` has no Ollama equivalent and is dropped.
- `LlmToolUse` becomes a `tool_calls` entry.
- `LlmToolResult` becomes `{"role":"tool","tool_name":…,"content":…}`. Our
  `LlmToolResult` carries `tool_use_id` but not the name, so the adapter builds an
  id-to-name map while it walks the history in order, and looks the name up. A
  result whose id is unknown falls back to a user message that quotes the output,
  which is worse but never wrong.
- `max_tokens` becomes `options.num_predict`.
- `tool_schema(::OllamaLlm, tools)` renders the OpenAI function shape:
  `{"type":"function","function":{"name","description","parameters"}}`.

### D7 — the thinking capability is asked, not guessed

`_thinking_param` in the Anthropic adapter guesses from the model name. That is
not safe here: a wrong guess is HTTP 400 and a dead turn. `OllamaLlm` gets a
`thinking::Union{Nothing,Bool}` field. `nothing` means "ask the server": the
adapter reads `capabilities` from `POST /api/show` once and caches the answer on
its own instance. Per-instance, never a module global — see
[PAR-PER-EDITOR-STATE](../../documentation/rule/architecture-invariants.md).

### D8 — the names

| now | after |
| --- | --- |
| package `ProjecturedLlm` | `ProjecturedAnthropic` |
| folder `source/llm/` | `source/anthropic/` |
| file `source/llm/Llm.jl` | `source/anthropic/Anthropic.jl` |
| type `AnthropicLlm` | unchanged — it already names its provider |
| — | package `ProjecturedOllama`, folder `source/ollama/`, file `Ollama.jl`, type `OllamaLlm` |

The kernel keeps `LlmModule`, `llm/`, and `Llm`. Those name the abstraction, and
the abstraction is right. Only the adapter takes the provider's name.

[naming-rules.md](../../documentation/rule/naming-rules.md) fixes the folder: the
slice is the package name with the prefix removed, in lower case, and it is the
source folder. So the rename of the package forces the rename of the folder.

`ProjecturedAnthropic` gets a **fresh UUID**. A path dependency is matched by name
and UUID together, and every manifest that names the old pair must be regenerated
anyway.

## Steps

Work in a dedicated worktree. Make one commit per step.

### Step 1 — the `make_llm` seam in the kernel — **DONE**

- [x] Add `make_llm` and `default_llm_model` to
      [source/kernel/llm/Llm.jl](../../source/kernel/llm/Llm.jl), with the `Val`
      fallback that errors helpfully.
- [x] Add `llm_backend_names()`, which reads `methods(make_llm)`.
- [x] Export all three from `LlmModule`.
- [x] Test: `test_kernel_layering()` passes 10/10. The seam answers as designed:
      with nothing loaded, `llm_backend_names()` is empty and `make_llm(:ollama)`
      says so; after a method is added for `Val{:fake}`, the name appears and the
      factory builds.

`llm_backend_names()` reads the method table and must skip the two generic
methods. The `Symbol` method's signature is a plain `DataType` and the `Val{K}`
fallback's is a `UnionAll`, so the filter keeps only a method whose second
parameter is a concrete `Val` with a `Symbol` parameter.

### Step 2 — rename `ProjecturedLlm` to `ProjecturedAnthropic` — **DONE**

Move the code:

- [x] `git mv package/ProjecturedLlm package/ProjecturedAnthropic`, then
      `git mv .../src/ProjecturedLlm.jl .../src/ProjecturedAnthropic.jl`.
- [x] `git mv source/llm source/anthropic`, then
      `git mv source/anthropic/Llm.jl source/anthropic/Anthropic.jl`.
- [x] New UUID in `Project.toml` (`7a22cfc9-547a-444c-98bf-c26ac0f0a0b0`); fix the `include` path in the package file.
- [x] Register `make_llm(::Val{:anthropic}; …)` and
      `default_llm_model(::Val{:anthropic})` in the adapter.

Update every site that names the package. The list is complete; I inventoried it:

| file | what is there |
| --- | --- |
| [AssistantTurn.jl:612-614](../../source/assistant/AssistantTurn.jl#L612) | the `:ProjecturedLlm` / `:AnthropicLlm` symbol literals — **the one site that breaks silently**; Step 3 deletes it |
| [Builder.jl:39](../../source/builder/Builder.jl#L39) | `LOCAL_CORE_PACKAGES` holds the string `"llm/main"` |
| [ProjecturedExecutable/Project.toml:11](../../package/ProjecturedExecutable/Project.toml#L11) | a dep, with no `[sources]` — deliberate |
| [ProjecturedExample/Project.toml:23](../../package/ProjecturedExample/Project.toml#L23) | a dep, with no `[sources]` — deliberate |
| [ProjecturedExample.jl:53](../../package/ProjecturedExample/src/ProjecturedExample.jl#L53) | `using ProjecturedLlm`, loaded for the reflection side effect alone |
| `environment/all/Project.toml:2,64,185` | the "eight opt-in stems" count, the dep, the `[sources]` path |
| `environment/all/Manifest.toml:992,1164-1167` | regenerate, do not hand-edit |
| [PackageGraphTest.jl:172](../../test/projectured/PackageGraphTest.jl#L172) | `SIDE_EFFECT_DEPS` — the executable's declared-but-unnamed dependency |

Prose that names it, and must follow: `package-rules.md:56,184`,
`system-anatomy.md:118`, `agent.md:39,84-87,131`,
`architecture-invariants.md:762`, `AssistantDocument.jl:90,94`,
`AssistantTurn.jl:624,636`, `Mcp.jl:103`.

- [ ] Regenerate `environment/all/Manifest.toml` — deferred to one resolve after Step 4, so the whole stack precompiles once instead of twice.
- [x] **Warning: a word-boundary rename also rewrites file-path strings.** After
      the rename, grep for `Anthropic.jl` and `ProjecturedAnthropic.jl` inside
      strings and doc links and check each one. See
      [[rename-file-string-corruption]].
- [x] Test: `ProjecturedAnthropic` loads standalone. `llm_backend_names()` is `[:anthropic]`, `default_llm_model(:anthropic)` answers, and `make_llm(:anthropic; model = "")` builds an `AnthropicLlm` on the default model. `test_package_graph()` waits for the resolve.

`AnthropicLlm(; model = "")` now falls back to the default model, because a caller
that holds no model asks for the backend's own (D2), and an empty string reaching
the API would be an error with no explanation.

**The builder's paths were repaired here**, as the fault section says.
`LOCAL_CORE_PACKAGES` and `_backend_localdir` now name the package folder itself,
which is the flat layout on disk.

What needs **no** edit, and why:

- `PackageGraphTest` reads `package/` with `readdir` and parses each
  `Project.toml`. A new package folder is picked up with no test edit. The one
  hard-coded entry is `SIDE_EFFECT_DEPS`.
- `ProjecturedKernelTest.package_source_root` maps a package name to its source
  folder by the naming rule. Because the package and the folder are renamed
  together, that mapping stays correct.
- The test doubles keep their names. `FakeLlm`
  ([example/kernel/LlmFake.jl](../../example/kernel/LlmFake.jl)) and `ScriptedLlm`
  ([example/kernel/LlmScripted.jl](../../example/kernel/LlmScripted.jl)) implement
  the kernel seam and name no provider, so `Llm` is the right word in both.
- `ProjecturedAssistant` and `ProjecturedConversation` declare no dependency on
  the adapter package at all, by design. That does not change.
- There is no continuous-integration script, no `ProjecturedLlmTest`, and no test
  that exercises `AnthropicLlm`.

### Step 3 — the assistant selects a backend by name — **DONE**

- [x] Delete `_discover_remote_llm` from
      [AssistantTurn.jl](../../source/assistant/AssistantTurn.jl) and resolve
      through `make_llm` (D3).
- [x] Add `backend::Symbol` to `Assistant` (D3's two constraints).
- [x] Make `model` default to `""`; the backend resolves it (D2).
- [x] Rewrite the "no backend available" error to list `llm_backend_names()`.
- [x] Test: `test_assistant_mvp()` is 76 pass, 1 broken, 0 fail. The 1 broken is a
      marker that was there before. Eight of those passes are new: an assistant
      that names no backend errors with "no LLM backend was named", one that names
      an unloaded backend gets the seam's own message, and an explicit `llm` still
      wins over both.

`DEFAULT_ASSISTANT_MODEL = "claude-opus-4-8"` is **deleted**. It was one provider's
model name held by a provider-neutral document, and nothing else read it.

### Step 4 — the `ProjecturedOllama` package — **DONE**

- [x] `package/ProjecturedOllama/Project.toml` — deps `ProjecturedKernel`, `HTTP`,
      `JSON3`, with the same compat bounds `ProjecturedLlm` uses today.
- [x] `package/ProjecturedOllama/src/ProjecturedOllama.jl` — a name and one
      include, shaped like the Anthropic package.
- [x] `source/ollama/Ollama.jl` — `OllamaLlm`, `stream_turn`, `tool_schema`,
      `make_llm(::Val{:ollama})`, `default_llm_model(::Val{:ollama})`.
- [x] Register it at the same sites Step 2 lists: `environment/all`
      (dep, `[sources]`, the stem count, the manifest), `ProjecturedExecutable`,
      `ProjecturedExample` (the dep and a `using` line for the side effect),
      `SIDE_EFFECT_DEPS`, and `LOCAL_CORE_PACKAGES` in `Builder.jl`.

The adapter's parts, in the order they should be written:

1. the request render (D6) — pure, no network;
2. the NDJSON line reader — one line in, translated events out (D4, D5);
3. the HTTP call, which is `HTTP.open` with the same `readavailable` chunk loop the
   Anthropic adapter uses, splitting on `"\n"` instead of `"\n\n"`;
4. the capability probe (D7).

Measured against the server on this machine, with `mistral:latest`:

- a text turn emits `LlmTextStart`, four `LlmTextDelta`s, `LlmTextStop`,
  `LlmTurnEnd(:end_turn)`;
- a turn that calls a tool ends in **`LlmTurnEnd(:tool_use)`** and carries the
  call complete — `call_oh34040d get_weather Dict("city" => "Paris")`;
- the second round renders that call and its result back, and the model answers
  from the result: "The weather in Paris is 18 degrees and sunny.";
- `thinking = true` on a model that cannot reason does not kill the turn, because
  the capability is asked for. The probe answers `false` for `mistral:latest`,
  `true` for `qwen3.8:27b`, and `false` for a model the server does not hold.

`base_url` is the **server**, not one endpoint, because the adapter uses two of
them. This differs from `AnthropicLlm`, whose `base_url` is the messages endpoint.

### Step 5 — the tests — **DONE**

- [x] `package/ProjecturedOllamaTest` with `test_ollama()`. Every opt-in stem here
      has a test package — `ProjecturedSdlTest`, `ProjecturedOdbcTest`,
      `ProjecturedTulipTest`, `ProjecturedVideoTest` — so this one follows them.
- [x] Feed the recorded lines through the reader and assert the event sequence.
- [x] Assert the tool-call turn ends in `LlmTurnEnd(:tool_use)` (D5).
- [x] Assert the request render, including that a result whose call was never seen
      still reaches the model as quoted text.
- [x] One live test, skipped when no server answers within two seconds.
- [x] Wire it into the umbrella: `using ProjecturedOllamaTest` and a `test_ollama()`
      call in `test_all()`. It is **not** re-exported to `Main`, which is how the
      other opt-in suites behave — the loop at `ProjecturedSuite.jl:39` lists the
      domain test packages only.

**Result: 65 pass, 0 fail.** `test_package_graph()` is 728 pass, 2 fail — the same
two failures clean `main` gives (719 pass, 2 fail), so the new packages add nine
passing checks and no regression.

The stream reader had to come out of `stream_turn` to be testable: `_line_handler`
is the translation as a function of one line, and the HTTP call is the only thing
left around it. That separation is what lets the suite run with no server.

### Step 6 — the documentation

- [ ] [agent.md](../../documentation/package/kernel/agent.md) — the "Who
      implements what" table and the "Concrete backends live outside `main`"
      paragraph.
- [ ] [package-rules.md](../../documentation/rule/package-rules.md) — the
      third-party dependency table, and the sentence that lists the stems.
- [ ] [system-anatomy.md](../../documentation/design/system-anatomy.md) — the
      opt-in package block.
- [ ] A short section in the assistant guide on how to select a backend.

## A fault I found on the way

[Builder.jl:39](../../source/builder/Builder.jl#L39) names its local packages in
the layout the repository used before the packages were flattened:

```julia
const LOCAL_CORE_PACKAGES = ["projectured/main", "projectured/example", "llm/main"]
```

`_compile!` joins each one with `package/`, which gives `package/llm/main`.
Neither `package/llm` nor `package/projectured` exists today; the packages are
`package/ProjecturedLlm` and `package/Projectured`. `_backend_localdir` builds the
same stale `<short>/main` shape for every opt-in backend it develops.

This is not caused by this plan, and this plan does not fix it. But Step 4 must
add the Ollama package to that same list, so the fault has to be repaired first or
the executable build cannot find either adapter. Repair it in Step 2, where the
line is edited anyway.

## Decided

1. **The name is `ProjecturedAnthropic`.**
2. **A person says which backend they want.** There is no `:auto` (D3).
3. **The default Ollama model is `qwen3.8:27b`.**

## Open questions

The assistant's system prompt is written for Claude and is long. A 27B local
model may follow it poorly. That is separate work, but it decides whether the
first Ollama turn looks like a success.
