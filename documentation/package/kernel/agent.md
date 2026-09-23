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
tool/    the capability surface     — no LLM, no MCP
llm/     the provider abstraction   — no MCP, no agent
agent/   the glue                   — llm + tools + a target
```

The order is a real one: an LLM request carries the tools the model may call, so
`llm` sits on `tool`; the loop drives a model against a tool set, so `agent` sits
on both.

## `tool/`: what the editor can be asked to do

```
Tool.jl           Tool (an action), Resource (a read-only datum), MeaningModel, ToolSet
ToolSet.jl        register / list / find / call — all on a ToolSet
CodeExecution.jl  execute_julia_code and execute_julia_expression, and their persistent scratch namespace
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

`search_api` and `search_guides` read their query in one of three modes.
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

**What a hit shows.** Two lines: the signature in code, with the kind and the
module after it, and the first sentence of the description under it.

```
- `replace_referenced_value!(editor, reference, value) -> Text` — function in PaneModule
  Put `value` where `reference` points, and answer the window's new program.
```

The signature leads because a model copies what it reads first, and a
`Module.name` at the front made one write `Module.name` (measured 2026-09-13).
A declared name that a declaration renamed shows the name the model writes, in
the list and in the whole docstring of one clear hit. One line at the end of
the list says how to read a hit in full: a function with
`read_function_documentation(module, name)`, a type or a module with
`read_resource` and its `resource://` URI. A description search that no
meaning model ranked says so in its first line, and says what to do instead.

`search_api(set, query; …)` and `search_guides(set, query; …)` search as
the tools of `set` do, with its declaration and its meaning model, so a call
from the REPL answers what a model is answered.

**Two searches, two intents.** `search_api` finds the name to call, and
`search_guides` says how the parts fit together; their descriptions say so in
one sentence each, and a miss in one names the other. They rank differently on
purpose — a name by its name first, a guide section by its heading first — so
they stay two tools.

**`detail` says how much a hit shows**, the same on both: `"names"` is one line
each, up to 25; `"summary"`, the default, adds the sentence or the excerpt, up
to 8; `"full"` is the whole docstring or section, up to 3. A `limit` given
replaces the count.

**A long answer ends with what to do next.** Over 600 characters, a list of hits
ends with how to read the first one in full and how to narrow the search; a
whole guide ends with its sections. A shorter answer ends with its data. The
rules are one function, `_make_footer`, so a footer never names a tool that is
not registered.

**A section, a function, a constant and a re-exported type are read by the
shape of their URI.** A search hit for a guide carries
`resource://guide/<name>#<heading>`, a hit for a function
`resource://function/<module>/<name>`, and a hit for a constant — a declared
name that is neither a type nor a function, such as a size policy —
`resource://value/<module>/<name>`; `read_resource` resolves each, and lists
none, because one resource per section or per function would list in the
hundreds. A type has a resource when its module defines it; a type a module
re-exports, such as `Point2D` given through `WidgetModule`, is read by the same
shape, `resource://type/<module>/<type>`. `list_resources` answers the kinds,
each with its count and its shape, in six lines.

**`execute_julia_code` answers what the code printed, whole, and the last value
in one line.** What the code prints is what the model asked for, so it is never
cut. The value of the last expression comes unasked — a `DataFrame` of thousands
of rows, the `Text` a side-effect verb answers — so a short one is shown as it
is and a long one is described by its `summary`, and the model prints the part
it wants. `nothing` with nothing printed answers "Done.", because an empty
answer reads as a broken tool. A name that is not defined answers with the
nearest declared names: a call to `plot_results` returns `make_result_plot`,
the search that starts from a guess, done where the guess fails.

`execute_julia_expression(set, target, expression)` runs code that is already an
`Expr`, as `make_julia_expression` gives it, and shares everything with
`execute_julia_code` except the parse: the scratch module, the `editor` binding,
the answer and the notice to the observers. An object that the expression holds
in a `QuoteNode` is used as that very object.

**A description is ranked by its meaning.** When the `ToolSet` has a
`MeaningModel`, the vector of the description and the vector of each entry or
guide section rank the hits by cosine. An entry's vector is computed from its
qualified name and its whole documentation.

- **For an entry, the meaning alone decides.** Merged with the rank of the
  description's words, words such as "value" and "runs" put unrelated names
  above the verb that was meant.
- **For a guide section, the two ranks are merged**, by reciprocal rank fusion,
  and the words count twice. A heading says what its section is about in a
  person's words, so there the words are a strong ranking. A backend gives a tool set its model
through `bind_meaning_model!`. The assistant binds at every turn, and a window
that serves MCP binds when it starts, because an MCP client runs no turn.

A task per model computes the vectors of the documents and keeps them in
`build/meaning/<model>.bin`, keyed by their text, so a changed guide section
costs one new vector. The first search of a build waits for it, for at most 30
seconds; a later search during the same build does not wait.

**Three cases need a hand.** The vectors are computed without a manual step,
but not in these:

- **A docstring or a guide edited in a running process.** The index of the
  declared names and the index of the guide sections are read once per
  process, so Revise does not reach them. Restart the process, and the next
  binding computes the new texts.
- **A model pulled again under the same name.** A vector of a new length
  empties the store, but a vector of the same length is taken as the model's.
  Delete the model's file.
- **A file that grew.** The vector of a text that is gone stays in the file.
  Delete the file, and the next binding computes every vector again.

The folder is read when a store is made, on the task that builds it. A test
that points `_MEANING_FOLDER` at a folder of its own makes its store before it
sets the folder back, or the build writes into `build/meaning/`.

**A description never fails for want of a model.** When the tool set has no
meaning model, when the model throws, or when its vectors are not ready, the
words of the description rank the hits as optional keywords, and the first line
of the answer says why. For a model
that is not installed, the reason says how to install it: `Run ollama pull
nomic-embed-text`.

## `llm/`: how the editor talks to a model

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
has no API key, and a hosted one may need a region.

A round ends in an `LlmTurnEnd`, which carries the stop reason and what the round
cost, `input_tokens` and `output_tokens`, as the provider counted them. A double
leaves the counts 0. A measurement of a turn adds the rounds up; nothing else
reads them.

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

Each backend reads its key and its default model from its own configuration:

| backend | key | default endpoint | default model |
| --- | --- | --- | --- |
| `:anthropic` | the `ANTHROPIC_API_KEY` environment variable, read once at construction | `https://api.anthropic.com/v1/messages` | the newest model with adaptive thinking, from the Models API; `claude-opus-5` if the request fails |
| `:ollama` | none — the server runs on this machine and needs no key | `http://localhost:11434` | `qwen3.8:27b` |

The backend is built once per turn, not kept on the document. The key and the
model are the backend's own configuration, so a cached backend would freeze
whichever model was selected first and editing `assistant.model` would stop taking
effect.

Three functions carry the whole selection, and all three live in `llm/LlmInterface.jl`:

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

`purpose` is `:query` or `:document`, because some models need a different
prefix for each, and the adapter determines which. `OllamaLlm` has `nomic-embed-text`
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
| meaning vectors | no API | `/api/embed`, with the prefix the model family needs |

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

**One list determines two things**, and that is the point of it: what
`execute_julia_code` can resolve, and what `search_api`,
`read_function_documentation` and `resource://modules` offer. A model that finds a
function it cannot call wastes a round and learns to distrust the answer, so the
two are never allowed to differ.

Empty — the default — means the editor's whole surface: every loaded `Projectured`
package, which is what the assistant and the MCP server want.

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

## `agent/`: the two directions

```
AgentModule.jl  (AgentModule)  inbound  — make/start/stop_agent_server!, run_on_editor_task!
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
each tool that runs. The assistant turns those into live conversation
parts; something else might simply print them.

### Both directions call from another task

An MCP server calls a tool on the task of the server, and a turn runs on a task
of its own. A tool can write what the editor shows, and a frame of the editor
reads it on the editor task. So both directions call through one door:

```julia
run_on_editor_task!(function_, target; wait = true) -> value
```

It runs `function_()` on the task that runs the loop of `target`, in the drain of
the next frame, and the calling task waits for the value. `run_turn!` runs each
tool call through it, with its fault barrier inside the call, and the MCP server
runs the call of a client the same way. So a tool runs on the editor task for
the assistant in the window and for an MCP client. With `wait = false` the call
only posts, and the answer is `nothing`. The assistant posts each streamed part
in this way.

The agent layer declares the function, and its default runs `function_()` at
once, because a target that is not an editor has no loop to wait for. The editor
layer answers it for an `Editor` whose loop runs on another task;
[editor.md](editor.md) says how.

## Who implements what

| Seam | Declared in | Implemented by |
| --- | --- | --- |
| `make_agent_server(:mcp, …)` | `agent/AgentModule.jl` | `ProjecturedMcp` (`package/ProjecturedMcp`, source in `source/mcp/`) |
| `run_on_editor_task!` | `agent/AgentInterface.jl` | the editor layer (`editor/Inbox.jl`) for an `Editor`; the default in `agent/AgentDefaults.jl` runs every other target at once |
| `stream_turn`, `render_tool_schema`, `make_llm` | `llm/LlmInterface.jl` | `ProjecturedAnthropic`, `ProjecturedOllama`; `FakeLlm` / `ScriptedLlm` in `ProjecturedKernelExample` |
| a `Tool`'s handler | `tool/Tool.jl` | `register_default_tools!`, and anyone else who registers one |
