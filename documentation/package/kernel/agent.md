# The agent stack — tool, llm, agent

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Three kernel layers, not one. They are separate because they are separately
useful, and the shortest way to see that is to notice what each works without:

- an **MCP server** is useful with no LLM in the process at all;
- an **LLM** is an abstraction over providers, and has nothing to do with MCP;
- an **agent** is the glue — a model, some tools, and something to act on.

They meet at one place, and it is worth naming: **the tool surface is the pivot.**
An agent loop calls a `ToolSet`; an MCP server publishes one; a provider adapter
renders one into its own schema. Three consumers, three directions, and no
knowledge of each other.

```
layer 14  tool/    the capability surface     — no LLM, no MCP
layer 15  llm/     the provider abstraction   — no MCP, no agent
layer 16  agent/   the glue                   — llm + tools + a target
```

The order is a real one: an LLM request carries the tools the model may call, so
`llm` sits on `tool`; the loop drives a model against a tool set, so `agent` sits
on both.

## Layer 14 — `tool/`: what the editor can be asked to do

```
Tool.jl           Tool (an action), Resource (a read-only datum), MeaningModel, ToolSet
ToolSet.jl        register / list / find / call — all on a ToolSet
CodeExecution.jl  execute_julia_code, and its persistent scratch namespace
SearchQuery.jl    what a search query says: keywords with classes, a pattern, a description
Documentation.jl  guide / module / type / function docs, and search over them
MeaningSearch.jl  the rank of a description by its meaning, and the stores of vectors
DefaultTools.jl   register_default_tools!, which puts the above into a ToolSet
```

A `Tool` is a name, a description, abstractly-described parameters, and a handler
`(target, args) -> String`. It carries **no wire format**: rendering it into
Anthropic's `input_schema` is `ProjecturedAnthropic`'s job, rendering it into MCP's
parameter list is `ProjecturedMcp`'s, and neither is the tool's business.

**One `ToolSet` per editor** ([PAR-PER-EDITOR-STATE](../../rule/architecture-invariants.md#par-per-editor-state)).
`Editor` owns one. Nothing here is process-global: not the tool list, not the
resource list, not the scratch module `execute_julia_code` evaluates into, not its
last result. Two editors in one process therefore cannot see each other's tools or
evaluate code into each other's namespace.

*The one carve-out*, stated where it lives: the guide and API indexes, and the
stores of meaning vectors, are process-global lazily-built caches. They are
derived from source files that do not change while the process runs, and from
the model a store is named for, so they are identical for every editor — the same
principled exception PAR-PER-EDITOR-STATE grants the wall clock.

### Three kinds of query

`search_api` and `search_documentation` read their query in one of three modes.
The `mode` argument names the mode, and a `Regex` value is a pattern in every
mode.

| mode | the query | use it when |
| --- | --- | --- |
| `"keywords"`, the default | words, in the forms below | you know a word of the name or of its documentation |
| `"regex"` | a regular expression, matched as written; `(?i)` ignores case | you know the shape of the name |
| `"description"` | a sentence that says what you want to do | you do not know what it is called |

`parse_keyword_query` reads a keyword query into terms of three classes:

| form | the term |
| --- | --- |
| `word` | ranks a hit, and does not filter |
| `+word` | must match, or the hit is dropped |
| `-word` | must not match where a word starts, or the hit is dropped |
| `a\|b` | matches when one of its alternatives matches |
| `"two words"` | matches the words together and in order, also written with `_` |

A word matches without case, as a substring, with or without a final `s`. A
forbidden word matches only where a word starts, because a forbidden substring
removes hits that nobody sees: `-test` would drop every entry that says
`invokelatest`. The name score and the prose score of a hit count only the
required and the optional terms.

**A description is ranked twice.** Its words rank the hits, all of them optional.
When the `ToolSet` has a `MeaningModel`, the vector of the description and the
vector of each entry or guide section rank the hits by cosine as well, and
reciprocal rank fusion merges the two ranks. A backend gives a tool set its model
through `bind_meaning_model!`. The assistant binds at every turn, and a window
that serves MCP binds when it starts, because an MCP client runs no turn.

A task per model computes the vectors of the documents and keeps them in
`build/meaning/<model>.bin`, keyed by their text, so a changed guide section
costs one new vector. The first search of a build waits for it, for at most 30
seconds; a later search during the same build does not wait.

**A description never fails for want of a model.** When the tool set has no
meaning model, when the model throws, or when its vectors are not ready, the
words alone rank the hits, and the first line of the answer says why. For a model
that is not installed, the reason says how to install it: `Run ollama pull
nomic-embed-text`.

## Layer 15 — `llm/`: how the editor talks to a model

```
Llm.jl         the Llm supertype; the stream_turn and render_tool_schema seams; the meaning model
LlmMessage.jl  LlmText / LlmThinking / LlmToolUse / LlmToolResult; LlmMessage; LlmRequest
LlmEvent.jl    LlmTextDelta, LlmToolUseStart, LlmTurnEnd, … — what streams back
```

**None of this is any provider's wire format.** The messages and events are the
project's own vocabulary, and an adapter translates its protocol into them. That is
the difference between an abstraction with implementations and a hook one
implementation leaks through: a second provider writes an adapter, rather than
transcoding its stream into the first provider's event names.

Provider *configuration* belongs to the provider, not to the seam:

```julia
stream_turn(llm::Llm, request::LlmRequest; on_event)
```

`LlmRequest` carries only what varies per turn — the system prompt, the messages,
the tools the model may call, and whether to ask for extended reasoning. The API
key, model name, endpoint, and token budget live on the concrete `Llm`, because
they are its identity and not parameters of "have a conversation": a local model
has no API key, and a hosted one may want a region.

A finished tool call arrives **already parsed**, in `LlmToolUseStop`. Turning
argument JSON into a `Dict` is the adapter's job and nobody else's — every adapter
necessarily has a JSON parser, because it speaks a JSON protocol, while the kernel
has no dependencies at all and so has none.

Concrete backends live outside `main`: `AnthropicLlm` in the opt-in
`ProjecturedAnthropic`, `OllamaLlm` in `ProjecturedOllama`, and the `FakeLlm` /
`ScriptedLlm` doubles in `ProjecturedKernelExample` — never in a `main` package
(PAR-NO-TEST-DOUBLES-IN-MAIN). A caller names a backend by symbol,
`make_llm(:ollama; model = …)`, so nothing in the core stack names a concrete
backend and `get_llm_backend_names()` says which packages are loaded.

### Choose a backend

A person says which backend they want. Nothing guesses, because a guess is only
ever right while one backend exists.

```julia
using ProjecturedOllama              # or ProjecturedAnthropic

assistant.backend = :ollama          # which provider
assistant.model   = ""               # empty means the backend's own default
```

An assistant that names no backend errors on submit, and the error lists the
backends whose packages are loaded. An explicit `assistant.llm` overrides both,
which is what a test does with a `FakeLlm`.

The backend is built once per turn, not kept on the document. The key and the
model are the backend's own configuration, so a cached backend would freeze
whichever model was selected first and editing `assistant.model` would stop taking
effect.

Three functions carry the whole selection, and all three live in `llm/Llm.jl`:

| function | what it answers |
| --- | --- |
| `make_llm(kind; model, api_key, context)` | build the backend registered under `kind` |
| `default_llm_model(kind)` | the model this backend talks to when nobody names one |
| `get_llm_backend_names()` | which backends can be built right now |

`make_llm` dispatches on `Val`, and each adapter package adds one method. **The
method table is the registry**: there is no dictionary to keep in step, nothing to
run at load time, and a backend counts as available exactly when it can be built.

Its three keywords are what a caller can hold without knowing which provider will
answer, and **a backend uses the ones that apply to it**: a server on this machine
ignores `api_key`, and a hosted provider ignores `context`, whose window comes with
the model rather than with a request. Each adapter says in its own documentation
what it ignores. That is the price of a seam a caller can use with no provider in
mind, and it is smaller than the price of a caller that must know.

### A backend's meaning model

A backend can also have a **meaning model**, which turns a text into a vector
for a search by description. Three functions carry it, and a backend that has
none keeps their defaults:

| function | what it answers |
| --- | --- |
| `has_meaning_model(llm)` | whether the backend has one; `false` by default |
| `get_meaning_model_name(llm)` | which model, as `"ollama/nomic-embed-text"` |
| `compute_meaning_vectors(llm, texts; purpose)` | one vector per text, as the columns of a `Matrix{Float32}` |

`purpose` is `:query` or `:document`, because some models want a different
prefix for each, and the adapter knows which. `OllamaLlm` has `nomic-embed-text`
unless its `meaning_model` keyword names another, and asks `/api/embed`.
Anthropic has no such API, so `AnthropicLlm` has no meaning model.

`bind_meaning_model!(set, llm)` turns the three into a `MeaningModel` on a
`ToolSet`: a name and a function, never the backend, so `tool/` stays below
`llm/`. A backend that has no meaning model leaves the tool set as it is.

### What each adapter must answer for itself

The two adapters show how far providers differ below this seam, and what a third
one would have to decide.

| question | Anthropic | Ollama |
| --- | --- | --- |
| the stream | Server-Sent Events | newline-delimited JSON |
| block framing | the provider sends it | the adapter makes it |
| a tool call's arguments | streamed fragments, parsed at the end | one parsed object |
| reasoning | a parameter chosen from the model name | asked of the server, because a wrong ask is HTTP 400 |
| the context window | comes with the model | `options.num_ctx`, and the server's own answer until a caller sets one |
| a reasoning block's signature | required back, unchanged | none exists |
| the stop reason for a tool call | the provider says `tool_use` | the provider says `stop`; the adapter counts the calls |
| meaning vectors | no API | `/api/embed`, with the prefix the model family wants |

The last row is the one that fails silently. `run_turn!` runs a tool only when the
turn ends in `:tool_use`, so an adapter that passes its provider's word through
would show a tool call and never run it.

### What a model may write

A `ToolSet` declares its API: the modules whose names the model may call.

```julia
editor.tools = ToolSet(; api = [CampaignAgent])
declare_api!(editor.tools, [CampaignAgent])   # or on a set that already exists
```

`declare_api!` is for the second case, where the editor made the `ToolSet` and a
caller says afterwards what it is for. It drops the namespace the code runs in,
because that namespace is built from the declaration on first use and kept: a
declaration that arrived after it was built would otherwise do nothing.

**One list decides two things**, and that is the point of it: what
`execute_julia_code` can resolve, and what `search_api`,
`read_function_documentation` and `resource://modules` offer. A model that finds a
function it cannot call wastes a round and learns to distrust the answer, so the
two are never allowed to differ.

Empty — the default — means the editor's whole surface: every loaded `Projectured`
package, which is what the workbench and the MCP server want.

**The list opens as much as it narrows.** The default surface is gathered by
package name, so a module in a package not called `Projectured…` is unreachable
until some `ToolSet` names it. A program that embeds this editor declares its own
verbs that way, and gets both halves from one line.

A declared module is taken as it stands: its **exported** names, and not the names
of the submodules it reaches. A module that means to offer more exports more, so
the list stays a decision a person wrote down rather than a consequence of what a
module happens to import.

**How to look is always in scope.** The declaration says what a model may *do*;
finding out what that is, is not one of the things it does. So `search_api` and
`read_function_documentation` are bound in the namespace the code runs in, with
the declaration already applied — which is what makes the locator `search_api`
prints for every function, a `read_function_documentation(…)` call, name something
the model can actually reach. It cannot widen its own view by passing a different
list.

The tool description follows the declaration too. With a list it names the modules
and says that anything else is an `UndefVarError`; with none it keeps the wider
text that sends a model to the guides.

**This is a focus mechanism and not a security boundary.** `Base` and `Core` stay
in scope, as in every Julia module, and code that means to reach `Main` can. What
it buys is that a name outside the list fails in the round that used it, with an
error the model reads and corrects, instead of the model choosing among thousands
of names that mean nothing to its task.

## Layer 16 — `agent/`: the two directions

```
AgentServer.jl  (AgentServerModule)  inbound  — make/start/stop_agent_server!
Agent.jl        (AgentModule)        outbound — the Agent, and AgentToolResult
AgentLoop.jl    (AgentModule)        outbound — run_turn!
```

**Inbound** is something outside the process driving *this* editor. The editor loop
reaches it only through `make_agent_server(:mcp, editor)` and never names a concrete
server type — which is exactly what lets the MCP transport live in an optional
package whose types cannot be referenced at load time.

**Outbound** is this editor driving a model:

```julia
run_turn!(agent, target; messages, on_event) -> stop_reason
```

The loop owns a turn's **control flow** and nothing else: stream a round, collect the
tool calls the model made, dispatch them through the `ToolSet`, decide from the stop
reason whether to go again, and stop at the round cap. It owns nothing about
*conversations* — how a transcript is stored, how a message is built from one, and
how an answer is rendered are all the caller's, because they are the caller's domain
and not an agent's.

`messages` is a **callback**, called at the start of every round, rather than a list
the loop mutates. The caller already has the conversation, and each round's prompt is
simply that conversation as it now stands — including the tool results the previous
round appended to it. A message list inside the agent would be a second copy of the
transcript, free to drift from the real one.

`on_event` receives every `LlmEvent` as it streams, plus an `AgentToolResult` for
each tool that runs. The workbench assistant turns those into live conversation
parts; something else might simply print them.

## Who implements what

| Seam | Declared in | Implemented by |
| --- | --- | --- |
| `make_agent_server(:mcp, …)` | `agent/AgentServer.jl` | `ProjecturedMcp` (`package/mcp`) |
| `stream_turn`, `render_tool_schema`, `make_llm` | `llm/Llm.jl` | `ProjecturedAnthropic`, `ProjecturedOllama`; `FakeLlm` / `ScriptedLlm` in `ProjecturedKernelExample` |
| a `Tool`'s handler | `tool/Tool.jl` | `register_default_tools!`, and anyone else who registers one |
