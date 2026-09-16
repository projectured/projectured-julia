# Three kinds of search: keywords, a pattern, a description

> **Kind:** plan · **Status:** pending, in progress · **Stands on:**
> [declared-api-is-a-list-of-names.md](../done/declared-api-is-a-list-of-names.md),
> [ollama-backend.md](../done/ollama-backend.md),
> [agent.md](../../documentation/package/kernel/agent.md),
> [package-rules.md](../../documentation/rule/package-rules.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md)

`search_api` and `search_documentation` answer a model that does not know our
names. Today they take one string, and the type of the string is the mode: a
`String` is a list of keywords, a `Regex` is a pattern. This plan gives the two
tools three kinds of query, and makes each kind say what it is:

1. **Keywords** with a positive, a negative, an alternative and a phrase form.
2. **A regular expression**, as today.
3. **A description in English** of what the model wants to do.

The first two are a parser and a scorer. The third needs a model that turns a
sentence into a vector, and it falls back to the first when no such model is
present.

## 1. Decisions

These were made on 2026-09-16 and are not open:

1. **A plain word is optional.** It ranks a hit and does not filter. `+word` is
   required, `-word` is forbidden. The model does not know our names, and a
   required word that we spell differently answers nothing.
2. **The mode is explicit.** A tool call names it with a `mode` argument. In
   Julia, a `Regex` argument still means the regex mode by its type, so
   `search_api(r"foo.*bar")` stays what it is.
3. **The description mode uses an Ollama embedding model**, and it falls back
   to the keyword scorer when no embedding model answers.
4. **Both tools get all three modes.** A guide heading is prose, so the
   description mode helps `search_documentation` most.
5. **The vectors are cached in one file under the repository's `build/`
   folder** for now. `build/` is in `.gitignore`, and it does not exist until
   something writes to it.
6. **The vocabulary is "meaning", not "embed".** This one was made when the
   work started, after the review: "embed" already names a document placed in
   a card, and "embedder" names a program that holds this editor and a graph
   layout. A vector that stands for what a text means is a third thing, so a
   **meaning model** computes **meaning vectors**. §3d uses these words.

## 2. What is there now

The whole search lives in
[Documentation.jl](../../source/kernel/tool/Documentation.jl). The facts a step
below depends on:

- **Two indexes, built once.** `_api_index(api)` holds one `_ApiEntry` per
  module, type and function: `kind`, `qualname`, `doc` (what a hit shows),
  `text` (what a hit is scored on: the signature and the first two paragraphs),
  `full` and `locator`. The whole surface is about 1,700 entries. A declared API
  has its own index, keyed by the declaration. `_guide_index()` holds one
  `_GuideSection` per heading: `guide`, `heading`, `body`. About 1,000
  sections. Both are process-global caches, the carve-out that
  `PAR-PER-EDITOR-STATE` grants to values that are the same for every editor.
- **`_matchers(query)` turns the query into `(patterns, fold)`.** A `String`
  becomes groups of forms, one group per word, each word with and without a
  final `s`, and `fold` is `lowercase`. A `Regex` becomes one group and `fold`
  is `identity`. Stop words are dropped. A word under two characters is dropped.
- **A hit has two scores, and the first decides.** In `search_api` the name
  score is 100 for an exact name, 20 for a name substring, 10 for a qualified
  name substring; the prose score counts matches in `text`. In
  `search_documentation` the heading score and the body score take the same
  roles. A tie goes to the shorter name. These were measured on 2026-09-13 and
  this plan keeps them.
- **One clear hit is answered in full.** When one hit stands alone, or one hit
  has the exact name and no other does, `search_api` prints its whole
  documentation. Half of a turn's tool calls were the search-then-read pair.
- **A miss lists what there is.** With a declared API, a miss prints
  `describe_api` so the model learns the names it can write.
- **The tools.** `register_default_tools!` in
  [DefaultTools.jl](../../source/kernel/tool/DefaultTools.jl) registers both
  tools with `query`, `regex` (a boolean), `limit`, and for `search_api` also
  `kind`. `_query_arg(args)` builds a `Regex` when `regex` is true. No adapter
  renders an `enum`, so an argument with a fixed set of values is a string whose
  description names the values, as `kind` is today.
- **`search_api` is bound in the scratch namespace** with the declared API
  applied, as `(query; kwargs...) -> search_api(query; api = declared, kwargs...)`.
  A keyword this plan adds passes through unchanged.
- **The kernel has no dependency.** `ProjecturedKernel/Project.toml` lists no
  package, and a stdlib module counts as one. The vector cache and the cosine
  arithmetic must use `Base` only.
- **The layer order.** `tool/` is layer 14, `llm/` is layer 15, `agent/` is
  layer 16. A `ToolSet` can not hold an `Llm`. `LlmModule` already
  `using ..ToolModule`, so the connection goes from `llm/` down to `tool/`.
- **The backends.** `OllamaLlm` in [Ollama.jl](../../source/ollama/Ollama.jl)
  talks to `http://localhost:11434` with `HTTP.jl`. Anthropic has no embedding
  API. The `Llm` seam has two methods, `stream_turn` and `render_tool_schema`.
  The offline doubles are `FakeLlm` and `ScriptedLlm` in
  `example/kernel/`, included by `ProjecturedKernelExample`, which depends on
  the kernel only.
- **This machine.** Ollama 0.33.1 runs, and `/api/tags` lists `qwen3.8:27b`,
  `qwen3.5:27b` and `mistral:latest`. No embedding model is pulled.
  `/api/embed` exists in this version.
- **Tests.** [DeclaredApiTest.jl](../../test/kernel/tool/DeclaredApiTest.jl)
  drives `search_api` through the tool handler and through the scratch
  namespace. [McpTest.jl](../../test/projectured/editor/McpTest.jl) has
  `test_search_documentation` and `test_search_api`, and two assertions pass
  `"regex" => true` through the handler. `test_ollama_live` skips itself when no
  server answers or no model is in memory.
- **Guides that name the tools.** The Layer 14 section of
  [agent.md](../../documentation/package/kernel/agent.md) lists the fragments
  of `tool/`. [orientation.md](../../documentation/guide/orientation.md) lines
  30–31 name the two tools. The `PAR-PER-EDITOR-STATE` text in
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
  names the two indexes as the carve-out. In omnet,
  [assistant-guide.md](../../../omnet-julia/documentation/guide/assistant-guide.md)
  line 22 shows a `search_documentation` call, and `OmnetCampaignUi.__init__`
  registers `documentation/guide` under the prefix `omnet/`.

## 3. The design

### 3a. One `mode` argument

Both tools take `mode`, a string with three values: `"keywords"` (the default),
`"regex"` and `"description"`. The `regex` boolean goes away. The description
of `mode` names the three values and says in one line when to use each:

- `keywords` when you know a word of the name or of its documentation;
- `regex` when you know the shape of the name;
- `description` when you know what you want to do and not what it is called.

An unknown mode answers a readable error that lists the three values. It does
not throw.

In Julia the two functions keep their signatures and gain the keyword:

```julia
search_api(query::Union{AbstractString,Regex}; mode = "keywords", kind = nothing,
           limit = 8, api = ApiEntry[], meaning_model = nothing)
search_documentation(query::Union{AbstractString,Regex}; mode = "keywords",
                     limit = 8, meaning_model = nothing)
```

A `Regex` selects its mode by type, as decided. A `mode = :regex` with a string
compiles the string, and an invalid pattern answers `Invalid regex: …` as it
does today.

`_read_search_query(query, mode)` reads the query once, and both functions
start with it. It answers a `KeywordQuery`, a `Regex`, a `_DescriptionQuery`,
or a `String` that says why the query can not be read. The mode is read without
case, and a missing mode is `"keywords"`. The tool handlers pass `mode` through
and no longer compile a pattern themselves, so a call from Julia and a call
through the tool answer the same text. `_query_arg` and `_arg_bool` go away.

The tool descriptions are sent with every request, so the syntax help is four
lines and no more. The long explanation goes in the guide.

### 3b. Kind 1: keywords with operators

**Syntax.** The query is split on white space outside quotes. Each token is one
term:

| form | class | meaning |
| --- | --- | --- |
| `word` | should | ranks a hit; does not filter |
| `+word` | must | a hit without it is dropped |
| `-word` | must not | a hit with it is dropped |
| `a\|b` | alternatives | one of them counts, in any class |
| `"two words"` | phrase | matched as one unit, no stem forms |

A term is a `SearchTerm`: its alternatives as written, which can earn a name
match, and every form that counts in prose. A word has the forms `_term_forms`
gives today. A phrase has two: as written, and with its spaces written as `_`,
so `"replace selection"` finds `replace_selection`. A regex is one term whose
one alternative is the pattern, so the scorer has one shape for both. The
parsed query is a `KeywordQuery` with three vectors: `must`, `should`,
`must_not`.

A plain piece that holds several words, as `OperationModule.Replace` or
`selection,`, is split at the characters that are not word characters, and each
word is a term of the piece's class. That is what the tokenizer does today. A
piece with `|` is one term, and every word and phrase in it is an alternative.

**A forbidden word matches only where a word starts.** Matching is by
substring, and a forbidden substring removes hits silently: `-test` would drop
every entry that says `invokelatest`. So `-row` drops `rows` and `table_row`
and keeps `arrow`. A required or optional word still matches anywhere, because
an extra hit there only costs rank.

The parser is `parse_keyword_query(text) -> KeywordQuery` in a new fragment
`source/kernel/tool/SearchQuery.jl`. Stop words are dropped from `should` only.
A `+the` is what the person asked for and it stays. A query whose every term
was a stop word keeps its words, as `_query_terms` does today. A query with no
term at all answers `Provide a search query (two or more characters).`, as
today.

**Scoring.** The two-number rank stays. The classes change what enters it:

1. `is_keyword_match(query, texts...)` filters, over texts that are already
   lower case. Every `must` term must match one of them. No `must_not` term
   may match any. A hit that fails is not scored. For `search_api` the texts
   are the qualified name and the scored text.
2. The name score and the prose score are computed over `must` and `should`
   together, term by term, with the same weights as today. A `must_not` term
   scores nothing.
3. The tie-break stays the shorter name.

For `search_documentation` the same filter runs over the heading and the body.

The `_matchers` pair goes away. A query answers its scored terms and its fold:
`lowercase` for keywords, `identity` for a regex. Each text is folded once per
hit, for the filter and the score together. `_excerpt` takes the scored terms,
so an excerpt centres on a word the person asked for and never on a forbidden
one.

A query of forbidden words only has nothing to look for, and it answers that in
one sentence.

**Normalized prose score, measured before adopted.** A long docstring earns a
higher count than a short one. The two-number rank already stops that from
deciding, so a BM25-shaped normalization is a separate step with a gate: it is
adopted only if the golden queries of §3e improve. It is not adopted by default.

### 3c. Kind 2: a regular expression

This exists. The changes are only the ones §3a makes: the mode is named, and
the string form of the tool argument compiles under `mode = "regex"`. A regex
matches original-case text. The tool description keeps its one line about the
`(?i)` prefix.

Operators do not combine with a regex. A regex is for a name the model almost
knows, and a pattern can already say "not" and "or".

### 3d. Kind 3: a description

**The words.** Decision 6: a **meaning model** turns a text into a **meaning
vector**. Ollama's wire names, `/api/embed` and `nomic-embed-text`, stay inside
its adapter.

**The seam.** `LlmModule` gets two functions:

```julia
has_meaning_model(llm::Llm) -> Bool        # false by default
compute_meaning_vectors(llm::Llm, texts; purpose = :document) -> Matrix{Float32}   # one column per text
```

`purpose` is `:query` for the text a search looks for, and `:document` for the
texts it looks in. Some models want a different prefix for each, and the
adapter knows which. A backend that has no meaning model keeps the default
`false`, and a call on it is an error that names the backend.

`OllamaLlm` gets a field `meaning_model::String`, a keyword of its constructor,
with the default `_DEFAULT_MEANING_MODEL = "nomic-embed-text"`. It answers
`has_meaning_model` with `!isempty(meaning_model)`, and it computes the vectors
with `POST /api/embed` and `{"model": m, "input": [texts…]}`, in batches of 64.
For `nomic-embed-text` it writes `search_query: ` or `search_document: ` in
front of each text, because that model needs them. `make_llm(:ollama;
meaning_model)` passes the keyword through. The Anthropic factory passes its
keywords to its own constructor, which does not know this one, so the keyword
belongs to Ollama and is not a fourth keyword of the seam.

`FakeLlm` gets the same field, with the default `""`. With a name, it computes a
deterministic bag-of-words vector, so the whole path runs offline in a test.
Without one, which is every test that exists, nothing changes.

**The connection.** `ToolModule` gets a small type, `MeaningModel`: a
`name::String` and a `compute::Function` that takes `(texts, purpose)`.
`ToolSet` gets one field, `meaning_model::Union{Nothing,MeaningModel}`.
`LlmModule` gets `bind_meaning_model!(set::ToolSet, llm::Llm)`. It sets the
field when `has_meaning_model(llm)`, leaves the field as it is otherwise, and
starts the build of the vectors. Two callers bind:

- `_run_agent_loop!` in [AssistantTurn.jl](../../source/assistant/AssistantTurn.jl),
  right after it resolves `llm`. This is the assistant in the window.
- `run_campaign_window` in omnet, in its `on_start`, when `llm !== :none` and
  `mcp` is on. This is the MCP client outside the window. It never runs an
  assistant turn, so it would otherwise never get a meaning model. Ollama needs
  no key, so a backend built at start is safe. With `:anthropic` the bind sets
  nothing.

The kernel holds a function and a name, never a backend. `tool/` stays below
`llm/`.

**The vector store.** A new fragment `source/kernel/tool/MeaningSearch.jl`
holds `_MeaningStore`: the model name, one normalized `Vector{Float32}` per
text keyed by the text, the texts that wait for a vector, and the one task that
computes them. There is one store per model name, in a process-global `Dict`
behind a lock. The vectors come from read-only sources and the model, so every
editor that names the same model shares them. This is the carve-out that the
two lexical indexes use, and the invariant text gets one sentence that says so.

What gets a vector:

- For an `_ApiEntry`, the text is `qualname * "\n" * text`. The name is in the
  signature already, and the qualified name adds the module.
- For a `_GuideSection`, the text is `guide * " › " * heading * "\n\n" * body`.
  A body over 2,000 characters is split at paragraph boundaries into chunks of
  at most 2,000 characters, each with the same prefix. A section's score is the
  best score of its chunks.

If a stored vector has a different length from the query's vector, the model
changed under its name. The store then forgets every vector and builds again.

**Build time.** `bind_meaning_model!` puts the texts of the guides and of the
set's API in the queue of the store, and a task computes them. A search first
computes the vector of its own description, so a server that is down, or a
model that is not installed, fails fast. Then it puts its missing texts in the
queue. The first search that finds texts missing waits for them, for at most 30
seconds. When the bound passes, the search falls back to keywords, and its first
line says that the vectors are not ready yet. A later search does not wait: it
uses the vectors when they are complete and falls back when they are not. The
bound is a `Ref`, so a test can make it shorter.

**The cache file.** The vectors go to `build/meaning/<model>.bin` under the
repository root that `_guide_roots()` already computes from `@__DIR__`. A `/`
or a `:` in a model name is written as `_`. The file uses `Base` only: an
eight-byte header, then for each vector the byte length of the text, the text,
the length of the vector, and the `Float32` values. The text is the key, so
there is no hash and no hash-version trap. A store reads the file once, when the
store is made. A batch is appended with one write call. If a crash cuts a
record short, the read cuts that record off the file. If the folder can not be
written, the vectors stay in memory and one warning says so. A test points the
folder somewhere else through a `Ref`, so a test never writes to `build/`.

**The rank.** The description mode runs both scorers and merges them with
reciprocal rank fusion. A hit's score is `1 / (60 + lexical_rank) +
1 / (60 + meaning_rank)`, over the first 50 hits of each list. A hit that is
not in one list gets no term from that list. The lexical list is the keyword
scorer on the words of the description, all of them optional. Fusion needs no
calibration, and a hit that only one side finds still ranks. The output format
is the one that exists. In the description mode, the full documentation is
printed only when one hit remains; the exact-name rule does not apply to a
sentence.

**The fallback.** The description mode runs the keyword scorer alone when:

- the set has no meaning model (no backend, or a backend that has none);
- the vector of the description can not be computed (no server, no model, a
  timeout);
- the vectors of the texts are not ready within the bound, or their build
  failed.

The first line of the answer then says why, in one sentence. Where a fix
exists, it gives the fix: `ollama pull nomic-embed-text` when the server says
that the model is not found. The model learns what happened and does not spend a
round on a guess.

A Julia call of `search_api` in `execute_julia_code` reads the set's meaning
model when it runs, if the set declares an API. With the whole surface,
`search_api` is the exported function, which has no set, so a description falls
back to keywords there.

### 3e. How we know it works

A table of golden queries, each a sentence and the name it must find, lives in
the test:

| description | expected |
| --- | --- |
| `draw how a value changes over time` | `make_result_plot` |
| `stop every simulation that is running` | `stop_simulations!` |
| `the single numbers the runs recorded` | `get_simulation_scalar_results` |
| `write down what the runs taught us` | `add_finding!` |
| `how do I plot results after a run` | a section of `omnet/assistant-guide` |

The names are verbs that the omnet IDE window declares with
`get_assistant_api()`. The first version of this table named
`describe_campaign` and `stop_campaign`, which are tools of
`SimulationToolsModule` that no window registers, and `plot_vector`, which does
not exist.

The offline test checks the pipeline with a hand-made `MeaningModel` whose
vectors come from a table of synonyms, so it proves that a description finds a
name that shares no word with it. A second offline test binds a `FakeLlm` that
has a meaning model. The live test in `ProjecturedOllamaTest` checks that the
real model puts two sentences of one meaning closer than two of different
meanings. The table above needs the omnet names, so it runs as a measurement in
omnet's `environment/all`: it prints the rank each sentence gets under keywords
and under description. The description rank must never be worse than the keyword
rank. The numbers go in §6 of this plan.

## 4. Steps

Work in a worktree. Commit each step with explicit paths. Land with
`git merge --ff-only`. Cap every Julia process with `ulimit -v 20971520`, a
`timeout`, and `nice -n 10 taskset -c 24-27`.

### Step 0. Baseline — done 2026-09-16

- [x] Worktree `../projectured-julia-search` on the branch
      `three-kinds-of-search`, off `main` at `d7baee48`.
- [x] `test_declared_api()` and `test_kernel_layering()` in
      `package/ProjecturedKernelTest`: 102 pass.
- [x] `test_search_documentation()`, `test_search_api()` and
      `test_search_tools_registered()` in `environment/all`: 24 pass.
      `package/ProjecturedTest` alone does not instantiate, because it has no
      `[sources]` entry for `ProjecturedSdl`. The umbrella tests run in
      `environment/all`.
- [x] `test_ollama()` in `package/ProjecturedOllamaTest`: 69 pass. The live
      turn skips itself, because the server holds no model in memory.

### Step 1. The mode argument and the keyword query (kernel) — done 2026-09-16

- [x] `SearchQuery.jl`: `SearchTerm`, `KeywordQuery`, `parse_keyword_query`,
      `is_keyword_match`, `_read_search_query`, and the scored terms and fold
      of each kind of query. Included in `ToolModule.jl` before
      `Documentation.jl`. `_STOP_WORDS`, `_query_terms` and `_term_forms` moved
      here from `Documentation.jl`; `_matchers` is gone.
- [x] `Documentation.jl`: `search_api` and `search_documentation` take `mode`;
      the filter runs before the score, and each text is folded once for both;
      `_excerpt` takes the scored terms; the description mode searches its words
      as keywords and says in its first line that no meaning model is present.
- [x] `MeaningSearch.jl` already exists after this step, with the note for a
      missing meaning model and `_fuse_rankings`. Step 3 fills in the rest.
- [x] `DefaultTools.jl`: `mode` replaces `regex` in both tools, through the
      shared `_QUERY_PARAMETER` and `_MODE_PARAMETER`; the handlers pass `mode`
      through and compile no pattern; one sentence in
      `_WHOLE_SURFACE_DESCRIPTION` and `_execute_julia_code_description` names
      the description mode.
- [x] Tests: `test/kernel/tool/SearchQueryTest.jl`, `test_search_query()`, 62
      assertions, registered in `KernelSuite.jl` and `ProjecturedKernelTest`.
      The two `"regex" => true` calls in `McpTest.jl` use `"mode" => "regex"`.
      `SEALING.md` lists the two new kernel files, unsealed.
- [x] `test_declared_api()`, `test_search_query()`, `test_kernel_layering()`:
      164 pass. The three MCP search tests in `environment/all`: 24 pass.

### Step 2. The meaning seam (kernel, example) — done 2026-09-16

- [x] `Llm.jl`: `has_meaning_model` (default `false`),
      `get_meaning_model_name` and `compute_meaning_vectors` (defaults that
      throw and name the backend), their docstrings, and the exports in
      `LlmModule.jl`. The name is a third seam function, because a
      `MeaningModel` needs it and only the adapter knows it.
- [x] `Tool.jl`: `MeaningModel(name, compute)`, the `meaning_model` field, the
      keyword constructor. The keyword constructor was the only caller of the
      positional one, in all three repositories.
- [x] `ToolSet.jl`: `set_meaning_model!(set, model)`, which step 3 makes start
      the vectors.
- [x] `LlmModule`: `bind_meaning_model!(set, llm)`, in `Llm.jl`.
- [x] `example/kernel/LlmFake.jl`: `FakeLlm(; meaning_model)` computes a
      bag-of-words vector of 64 places, placed by FNV-1a so that the places do
      not change between Julia versions.
- [x] Tests: `test/kernel/tool/MeaningSearchTest.jl`, `test_meaning_search()`.
      The kernel tests of steps 1 and 2 and `test_agent_seam()`: 183 pass.

### Step 3. The description mode (kernel) — done 2026-09-16

- [x] `MeaningSearch.jl`: `_MeaningStore`, the chunks, the cache file, the
      build task with its bound, the rank by meaning, the fusion.
      `set_meaning_model!` calls `_start_meaning_vectors!`, which gathers the
      texts on a task of its own, because the first gathering reads every
      docstring and every guide.
- [x] `Documentation.jl`: the description mode in both functions, the fallback
      and its first line. One lock, `_INDEX_LOCK`, now guards the lazy build of
      the guide and API indexes, because the gathering task reads them from
      another thread.
- [x] `CodeExecution.jl`: the declared `search_api` reads the set's meaning
      model when it runs. `DefaultTools.jl`: both tools pass it.
- [x] Tests, offline, in `MeaningSearchTest.jl`: a description finds a name that
      shares no word with it, through a synonym table; the guides rank by
      meaning; a long section is cut into chunks; a model that throws on the
      description, and one that throws on the documents, fall back and say why;
      only the first search of a slow build waits; the file round-trips, a
      record cut short is cut off, a foreign file is written again; a change of
      vector length starts the store again; the tools and the scratch module
      use the set's model; binding a `FakeLlm` computes the vectors of the
      guides and the API. The kernel tests: 221 pass. The umbrella search
      tests: 24 pass.

### Step 4. Ollama computes meaning vectors (ollama package) — done 2026-09-16

- [x] `Ollama.jl`: `meaning_model` (default `nomic-embed-text`),
      `has_meaning_model`, `get_meaning_model_name` (`ollama/<model>`),
      `compute_meaning_vectors` with `/api/embed` in batches of 64, the
      prefixes of `nomic-embed-text` and `mxbai-embed-large`, and a refusal
      that says `Run \`ollama pull <model>\``. `make_llm(:ollama; meaning_model)`
      needed no change: it passes its keywords to the constructor.
- [x] `test/ollama/OllamaTest.jl`: `test_ollama_meaning()` asks a stand-in
      server that the test starts with `HTTP.serve!` on a free port, and checks
      the path, the model, the prefixes, the batches, a short answer, a model
      that is not pulled and a server that does not answer.
      `test_ollama_meaning_live()` skips itself when the server does not list
      the model. It does not pull one.
- [x] `test_ollama()`, with its layering guard: 97 pass. Both live tests
      skipped: no chat model is in memory, and `nomic-embed-text` is not pulled.

### Step 5. Bind the meaning model where a backend is chosen — done 2026-09-16

- [x] `AssistantTurn.jl`: `bind_meaning_model!(set, llm)` after the backend
      resolves, through `Base.invokelatest`, as `_build_llm` calls `make_llm`,
      because the backend's methods can come from a package loaded later.
- [x] `AssistantDocument.jl`: the default system prompt names the description
      mode in one line.
- [x] Test: `test_assistant_turn_binds_meaning_model()` in `McpTest.jl`, in
      `test_mcp_tools()`. The umbrella search tests, the editor reference test,
      the new test and the composer panel test: 49 pass.
- [x] Land projectured on `main` first. omnet resolves projectured through its
      `main` checkout. Before the landing: `test_kernel()` has 1,755 passes and
      the known 3 failures and 3 errors (five Rule C assertions in
      `DocumentMacroTest.jl` and one in `ReferenceEvalTest.jl`);
      `test_mcp_tools()`, `test_mcp_resources()` and `test_assistant_mvp()`
      have 227 passes and 2 failures, and clean `main` has the same 2 failures
      in `test_assistant_mvp()` (79 passes).
- [x] omnet `CampaignWindow.jl`: `bind_backend_meaning_model!(tools,
      build_backend)`, exported, called in `on_start` when `mcp` is on and
      `llm !== :none`. It builds the backend with `make_llm(llm; model,
      context)` and warns when the backend can not be built. The
      `run_campaign_window` docstring says why, and `CAMPAIGN_SYSTEM` names
      the description mode in one sentence.
- [x] Test: a new testset in `CampaignAssistantTest.jl` binds a `FakeLlm` that
      has a meaning model, one that has none, and a backend that throws.
      `test_campaign_assistant()` and `test_campaign_controls()`: 30 pass.
      `test/build.jl`: 118 passes and the 3 known errors (no `juliac`, and the
      reactive build's two tests).

### Step 6. Guides — done 2026-09-16

- [x] `agent.md`: the Layer 14 file list gains `SearchQuery.jl` and
      `MeaningSearch.jl`; the carve-out names the stores of vectors; a new
      subsection "Three kinds of query" holds the two syntax tables and the
      fallback rule; a new Layer 15 subsection "A backend's meaning model"
      names the three seam functions and `bind_meaning_model!`; the adapter
      table gains a row for meaning vectors.
- [x] `orientation.md`: one line names the three modes and the keyword forms.
- [x] `architecture-invariants.md`, `PAR-PER-EDITOR-STATE`: the stores of
      meaning vectors join the carve-out, in one sentence.
- [x] `test_naming()` and `test_tree()` pass with the new files and exports.
- [x] omnet `assistant-guide.md`: a paragraph names the three modes, gives an
      example of a description, and says how to install `nomic-embed-text`.

### Step 7. Measure

- [x] The measurement is ready. It runs in omnet's `environment/all` against
      `get_assistant_api()`, which declares 88 entries, and prints for each
      sentence the rank of the expected name under keywords, under the meaning
      alone, and fused. A rank of 0 means not in the first 50.
- [x] A dry run without the model, 2026-09-16: the build failed after 3.4 s,
      and every description answer began with "The meaning model
      ollama/nomic-embed-text failed, so the words of the description were
      searched as keywords. The reason: Ollama has no model nomic-embed-text.
      Run `ollama pull nomic-embed-text` to install it." The words alone rank
      `stop_simulations!` first and do not find the other three verbs in the
      first 50; they rank a section of `omnet/assistant-guide` first for the
      guide sentence.
- [ ] Ask before `ollama pull nomic-embed-text`. It is 274 MB.
- [ ] Run the golden table live and record the ranks in §6.
- [ ] Decide the BM25 normalization of §3b on that table, and record the
      decision.
- [ ] Move this plan to `plan/done/`.

## 5. Out of scope

- An `enum` field on a tool parameter. Three adapters render a parameter, and
  none of them has it. The description of `mode` names its values, as `kind`
  does.
- A cache folder outside the repository. Decision 5 puts it in `build/` for now.
- A `--meaning-model=<name>` flag for the omnet binary. `OllamaLlm(; meaning_model)`
  is the one knob until a person asks for another.
- The model that rewrites its own description into keywords. That is a prompt
  change in the agent, not a search mode.
- A meaning model for Anthropic. Its API computes no vectors.

## 6. Findings

**Step 1, 2026-09-16.**

- **The declared `search_api` in the scratch module could widen its own view.**
  It was bound as `search_api(query; api = declared, kwargs...)`, and of two
  equal keywords Julia keeps the later one, so `search_api("x"; api = [])`
  searched the whole surface. The comment above it said the opposite. The
  declared list is now written after the splat, and a test holds it.
- **`register_default_tools!` had no documentation.** Its docstring stood above
  `const _WHOLE_SURFACE_DESCRIPTION`, so Julia attached it to the constant. It
  now stands above the function, and a test reads it through `@doc`.
- **A term is a `SearchTerm`, not a `KeywordTerm`,** because a regex is a term
  of the same shape: its one alternative is the pattern. One scorer serves both.
- **A phrase has a second spelling with `_` for each space**, so a quoted
  phrase finds the name that spells it. This is not a stem form: the words stay
  in their order.
- **A forbidden word matches only where a word starts.** Plain substring
  matching would make `-test` drop every entry that says `invokelatest`.

**Step 3, 2026-09-16.**

- **"Only the first search waits" is per build.** Traced by hand before the
  first run: with one flag per store, a search of the guides after a search of
  the API found its texts missing and did not wait, because the API search had
  waited already. A store now clears the flag whenever it starts a build.
- **The lazy indexes needed a lock.** The gathering task calls `_api_index`
  and `_guide_index` from another thread, and `_DECLARED_INDEX` is a `Dict`
  that `get!` changes. One lock guards both builds; a build is the only slow
  part, and a second caller would wait for it anyway.
- **With the whole surface, a Julia call of `search_api` has no meaning
  model.** The scratch module gets the exported function there, which has no
  set. A description falls back to keywords in that case, and says so. The
  tools are the path a model uses.
- **The whole surface is smaller than §2 says.** Measured in `environment/all`:
  797 API entries, built in 0.46 s, and 1,033 guide sections, which make 1,159
  chunks. The texts hold about 1.04 million characters: 132,000 for the API and
  905,000 for the guides. A test process has one default thread and one
  interactive thread, so a spawned task really runs beside the caller.

**Step 5, 2026-09-16.**

- **A turn with no editor fails before it starts, and a test does not see it.**
  `_run_agent_loop!` reads `editor.tools` on its first line, and
  `test_assistant_composer_panel` runs a turn with `nothing` as the editor. The
  turn fails with a `FieldError`, and the error turn it leaves counts as the
  reply the test waits for. The line dates from 2026-07-14 and is outside this
  plan.
- **A live omnet test calls `search_api` with a keyword it does not take.**
  `test/campaign/CampaignVerbsTest.jl` passes `modules = editor.tools.api` to
  `search_api` and to `read_function_documentation`; both take `api`. The test
  runs only when Ollama holds a model in memory, so it has not failed where
  anyone saw it. This plan did not change that keyword, and the test is left as
  it is.

