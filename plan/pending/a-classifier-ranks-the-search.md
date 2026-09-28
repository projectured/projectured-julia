# A classifier ranks the search

Status: a plan, 2026-09-28. Nothing is implemented. The owner answered the
questions of §8 the same day, and nothing is open.

## 1. The request

The owner, 2026-09-28:

> do you think that a jev like search would be better? can we make a
> measurement to compare the two mechanisms in a concrete use case such as the
> M/M/1/K study automated video recording script?
>
> my goal is to find out whether a generic classifier such as jev can give
> better help for the agent to find out which function are relevant for a given
> question in a given context. […] the search_api would get an optional
> context, and a question to search the API for. Then internally it could do
> what it does today or it could use jev to score functions. For each function
> it would give the function signature the function documentation and also the
> call sites for the given function to the generic classifier. […] If there are
> limitations wrt. the number of possibilities which can be scored, we can do a
> recrursive divide and conquer approach along Julia packages/module/classes/
> functions and/or folders.
>
> Finally, we could do the same for guides in the search_documentation where we
> could score markdown files, chapters/sections in guides, paragraphs, etc.
>
> Maybe we should do a staged development where in the first stage we test
> artificial examples for search not the actual agent and recording a video.

The function the owner calls `search_documentation` is `search_guides` in the
code.

The owner, later the same day:

> note that in the real application the corpus size will be several thousands
> of functions/types, so this is not the real scale of the problem

So Stage 1 measures up to that scale (§5c), and a shape of the search counts
only if it works there.

The plan answers one question with numbers: **does a classifier that reads the
question, an optional context, and the signature, the documentation and the call
sites of each candidate put the names and the guide sections that the agent
needs higher than the search of today?**

It has three stages. Each stage starts only when the one before it shows a gain,
and the owner says so.

1. **Stage 1: the ranks.** Artificial questions with a known answer. No agent,
   no video, no change to the kernel.
2. **Stage 2: the agent.** The search of the kernel gets a context and a
   classifier. The fast loop runs the study with the real model on seeds.
3. **Stage 3: the video.** A take of the S0 study with the new search.

## 2. What exists

### 2a. The search of today

`search_api` and `search_guides` are in
[Documentation.jl](../../source/kernel/tool/Documentation.jl) and
[MeaningSearch.jl](../../source/kernel/tool/MeaningSearch.jl). The tool layer is
not sealed (⬜ in `SEALING.md`, layer 18).

- **An API entry** is a module, a type, a function or a value of the declared
  API. The text that the ranking reads is the qualified name and the whole
  docstring (`_ApiEntry.text`). No call site is in it.
- **By keywords**, an entry ranks on two numbers: the name score (the whole
  name, a word of the name, a piece of the name), then BM25 over the prose.
- **By description**, the meaning vectors of `nomic-embed-text` rank the
  entries, and the words do not count. The fusion of the two ranks was worse,
  measured twice (at 88 names and at 1,389 names).
- **A guide section** is the text between two headings. A section scores as its
  best chunk of 2,000 characters. By description, the meaning rank and the word
  rank are fused, and the words count twice.
- **A search has no context.** The model writes one query, and the search sees
  nothing of the conversation or of the editor.

### 2b. The instruments

- `measure_search_scale!` in
  [SearchScaleMeasurement.jl](../../example/kernel/SearchScaleMeasurement.jl)
  asks each `ScaleQuestion` (a sentence, the one expected name or guide, the
  kind) by words and by description. It prints first, in five, in ten, and the
  mean reciprocal rank.
- The corpora: `SCALE_SEARCH_QUESTIONS` in
  [SearchScaleCorpus.jl](../../example/projectured/SearchScaleCorpus.jl) (25
  modules, 26 questions of names, 6 of guides), and `IDE_SCALE_QUESTIONS` in
  `example/ide/SearchScaleCorpus.jl` of omnet-julia (34 of names, 6 of guides).
  Each question has one expected answer and no context.
- The fast loop: `tool/assistant/rehearsal.jl` here and
  `tool/assistant/study_rehearsal.jl` in omnet-julia run the real model on
  seeds, with a check of each step. See `a-fast-loop-for-the-assistant.md`.

The last numbers, from `plan/done/assistant-recovers-from-a-miss.md` (names
first / in five / in ten, by description):

| corpus | entries | first / five / ten |
| --- | --- | --- |
| projectured, 26 questions | 1,224 | 10 / 20 / 21 |
| omnet, 34 questions | 786 | 8 / 15 / 19 |

The guides, 6 questions each, by description: projectured 3 first and 5 in ten,
omnet 3 first and 5 in ten.

### 2c. The S0 study

The files are in omnet-julia:

- `tool/video/record_study_take.jl` records a take. `SENTENCES` holds the seven
  requests of the person.
- `tool/video/study_warm_up_steps.jl` holds the correct path in code, one block
  per request.
- `tool/assistant/study_rehearsal.jl` runs the same requests in the fast loop,
  with a check of each (`make_study_turns`).

The seven requests, and the names that the correct path calls:

| # | the request | the names |
| --- | --- | --- |
| 1 | "Start a study of an M/M/1/K queue. The question is how large the buffer must be to keep the blocking under 1 % at 80 % load." | `make_study!` |
| 2 | "Write the network: a source, a queue with a finite capacity and a sink, from queueinglib." | `write_ned_file!`, `embed_in_study!` |
| 3 | "Write the configuration: choose the rates so that the load is 0.8, use a capacity of 5 and no job limit with a time limit of 2000000 s, and add a second configuration that sweeps the capacity from 1 to 15." | `write_ini_file!`, `embed_in_study!` |
| 4 | "Write the closed form into the study: the blocking probability and the mean queue length as formulas at load 0.8 with capacity 5, and show them in the page." | `add_study_formula!`, `embed_in_study!`, `get_formula_value` |
| 5 | "Run both configurations, the sweep too, and put the runs in the study." | `make_run_card`, `embed_in_study!`, `run_card!` |
| 6 | "Plot the queue length of the first run over time, and state an expectation that the measured queue length agrees with the formula within 10 %, then check it." | `make_result_plot` with a `VectorResultSelection`, `add_expectation!`, `embed_in_study!`, `check_expectations!` |
| 7 | "Plot the drops of the sweep over the capacity, and write the finding: the smallest capacity that keeps the blocking under 1 %, then save the study." | `make_result_plot` with a `ScalarResultSelection`, `embed_in_study!`, `get_project_result_directory`, `read_results`, `add_finding!`, `save_study!` |

**The window of the study declares 131 entries**: `get_assistant_api()`
(`source/ide/IdeWindow.jl`) gives 13 modules, and the index holds 64 functions,
53 types, 12 modules and 2 values. The scale corpora are about ten times larger,
and the real application declares several thousand names. The window is a
control of this plan, and not its scale.

**The system text teaches the names.** `make_ide_system()` puts nine sections of
the assistant guide of omnet-julia into the system text. That change took the
study from 0 of 5 seeds to 3 of 5, and later fixes of the guide took it to 7 of
7 (`plan/done/the-study-video-with-the-real-model.md` in omnet-julia). The
system text also says: when you do not know the name of a verb, search with mode
"description" and say in a sentence what you want done.

**The logs of the rehearsals.** `/var/tmp/s2/study/out/<experiment>/seed_<n>.txt`
holds 21 transcripts with search calls: 82 calls of `search_api` and 24 of
`search_guides`, 106 in all. (A first count of 144 counted every mention of the
two names, in the system text and in the thinking too.) A line of the thinking
of the model (`∴ …`) comes before each call, so each query has a real context.
A long query is cut with "…" in the header, and the full query is on the
`query:` line under it.

Most queries already name the verb, because the guide sections in the system
text taught it: `"make_study! start a study"`, `"write_ned_file! study network
file"`. So the search in S0 is mostly a lookup of a known name. The misses are
of another kind:

- `search_guides "write_ned_file! source queue sink queueinglib M/M/1/K NED"`
  answered sections of the model migration guide about the NED syntax.
- `search_api "add_expectation! result_selection reference tolerance
  check_expectations!"` answered `ReferenceModule`, because "reference" is a
  word of its name. The next query, `"add_expectation! study tolerance reference
  formula"`, found the verb.

A classifier can gain in two places here: on misses of this kind, where the
context says what the words do not; and for a model with no guide in its system
text, which must find the names from the words of the person.

### 2d. What the earlier plans found, and what this plan adds

1. **Recall is the loss, not the order.** At about 2,000 names, a third of the
   expected names were not in the first ten. Some were not in the first fifty
   by either mode.
2. **"A ranking cannot read what the text does not say."** The names that no
   mode found had documentation that did not say what the question said. The
   fix then was the docstrings.
3. **The model seldom searches for a type, and a docstring alone does not
   teach it how names combine.** The oracle runs of the fast loop: the section
   "Reach what a tab holds" of the orientation guide in the system text took S2
   from 9 of 10 to 10 of 10. The docstrings of the 17 names that the tasks need,
   in the system text, did worse (2 of 5).

The owner's proposal adds two things that the earlier plans did not measure:

- **The call sites.** A call site shows how a caller writes the name, with the
  names it combines with. That is the text that item 2 says is missing, and it
  is what made the guide section of item 3 work.
- **A scorer that reads the question and the candidate together.** A meaning
  vector reads each text alone and compares two vectors. A classifier reads the
  pair, so it can use the context and the call sites in relation to the
  question.

These are two separate changes. The measurement must separate them (§4).

## 3. What Jev is

Facts read on 2026-09-28 from docs.typesafe.ai and the simple-jev repository.

### 3a. TypeSafe Jev, the hosted model

- **Released** 2026-09-15. The model now is `jev-1.13.0` (alias `jev-latest`).
- **The call**: `POST https://api.typesafe.ai/v1/systemone` with a bearer key.
  The request holds a `state` (text, a JSON object or an array) and a map of
  `questions`. The answers come back in one response.
- **Three kinds of question**:
  - `noul`: is this true? A number from 0 to 1.
  - `choice`: one of at most 255 options, with a probability for each option.
  - `score`: a level of 2 to 10 ordered levels, with the probabilities.
- **Limits**: 64k tokens per request; 32k tokens for the state and the longest
  question. 250,000 tokens per second and 1,200 requests per minute. The number
  of questions per request is not documented.
- **Price**: $0.042 per million input tokens; output tokens are free.
- **Data**: zero data retention only for enterprise customers.
- **Known limits of jev-1.13** that apply here: it reads words literally; it
  does not count; "accuracy falls as the state grows with content unrelated to
  the decision"; a property of a property costs accuracy. English is best.

Three cookbooks do what this plan does:

| cookbook | the method | the result |
| --- | --- | --- |
| Re-rank | BM25 gives 30 candidates; one `noul` per candidate, with the query and the passage in the state | top 1 from 5% to 18%, top 10 from 38% to 62%; 1,200 calls for $0.0645 |
| Skill suggestion | one `choice` over 182 skills (name and a description of about 54 characters), then a second request over the best 3 with the full text and one `noul` each | 2.3 times fewer wrong loads than the baseline; 0.27 s for the two requests |
| Hierarchical classification | one `choice` per node of a tree; a beam of 3 paths; a path scores as the geometric mean of its probabilities | the beam 4 of 4, greedy 2 of 4 |

### 3b. simple-jev, the open form

`featherless-ai/simple-jev` serves the same request shape from an open model. It
reads the probabilities of the next token over the answer labels, and it does
not generate text. It computes the shared state once and reuses it for each
question. It runs on Hugging Face Transformers with PyTorch, and it has no
Ollama backend. It lists Qwen3.8-27B among its models. The default limits are
100 questions per request and 16,384 tokens per question.

### 3c. This machine

- An AMD Strix Halo with the Radeon 8060S graphics, 61 GB of shared memory, no
  swap, and no CUDA.
- Ollama 0.33.1 with `qwen3.8:27b`, `nomic-embed-text`, `mxbai-embed-large` and
  `mistral`. Ollama returns `logprobs` and up to 20 `top_logprobs` on
  `/api/chat` and `/api/generate`.
- No PyTorch is installed. Python is 3.14; simple-jev asks for 3.13.

## 4. What the measurement separates

A gain has four possible causes. Each is a factor of the measurement, so that a
gain can be given to its cause.

| factor | levels |
| --- | --- |
| F1, the scorer | words (BM25); meaning vectors; the classifier |
| F2, the text of a candidate | the documentation; the documentation and the call sites |
| F3, the context | none; the context of the question |
| F4, the shape of the search | flat; two stages; a tree |

Two controls are the most important:

1. **The call sites in the vector text too** (F1 = meaning, F2 = call sites). If
   the vectors gain as much as the classifier, the gain is the text and not the
   classifier. The text is then the cheap change.
2. **The context in the vector query too** (F1 = meaning, F3 = context). The
   baseline must get the same information as the classifier.

Not every cell of the table runs. §6 gives the order, and each step says which
result stops the stage.

## 5. The design

### 5a. The text of a candidate

A candidate of the API is:

1. The signature, as a hit shows it now.
2. The docstring, cut to a budget of characters. Step 4 tries three budgets.
3. At most three call sites. Each call site is the line of the call and the
   signature of the function that holds it, with the file. The budget is about
   160 characters per call site.

**How a call site is found.** A tool parses every `.jl` file of the named
folders with `Base.JuliaSyntax`, as `workspace/bin/julia-rename.jl` does, and
keeps the nodes that are a call of an identifier or of `Module.name`. The fenced
Julia blocks of the guides are call sites too, because a guide example shows a
call as a caller writes it. The tool writes one file per corpus: each entry with
its call sites.

**Which call sites win.** A call from outside the package that defines the name
comes first: a test, an example, a tool, a guide, another package. A call from
inside the package comes last. Two call sites from one function count as one.

**A name that two modules define.** The first version gives a call to every
entry of that short name, and the report counts these names. The tool does not
resolve the binding.

**What the tool must not read.** A call site that answers a question word for
word makes the measurement test memory and not relevance. The tool excludes:

- the S0 scripts and their checks (`tool/video/study_*`,
  `tool/video/record_study_take.jl`, `tool/assistant/study_rehearsal.jl` in
  omnet-julia);
- the other files that script the S0 study word for word:
  `test/ide/AssistantStudyTest.jl` and `example/ide/StudyRecording.jl` of
  omnet-julia (found in Step 1);
- `tool/assistant/rehearsal.jl` and its checks;
- the files that hold the questions of the corpora, and their tests
  (`test/ide/AssistantSessionTest.jl` holds the eleven problems);
- the fragments of the measurement itself, which call `search_api` and
  `declare_api!`.

The M/M/1/K model is the standard test model of the simulator, and about 80
files name it. Only the files above script the study; the others stay.

A guide section that a question expects stays a call site source for the API
questions, because the agent can read the guides too. The report says how many
questions have their expected name in a call site of a guide.

A candidate of the guides is a unit of one of three sizes: a guide file (its
title and its first paragraph), a section (its heading and its body), or a
paragraph (with the heading of its section).

### 5b. The classifier questions

**A `noul` per candidate.** True means "the person calls this to do the request,
or a step of it". False means "this is about a similar topic, and it does not do
this". The rank is the order of the nouls.

Two layouts of the request. Step 0 compares them on ten questions:

- **L1, the layout of the re-rank cookbook**: the state holds the question, the
  context and one candidate; one fixed `noul`; one request per candidate.
- **L2, the fan-out layout**: the state holds the question and the context; one
  `noul` per candidate, with the text of the candidate in its `instructions`;
  up to 100 candidates per request.

L1 is the documented use. L2 sends the state once. The known limit "accuracy
falls as the state grows with content unrelated to the decision" says to keep
the state small in both.

**A `choice`** is for the choice cascade and the tree (§5c): which option holds
what the request needs. An option is a short line: a module and its first
sentence, or a name and its first sentence. A `choice` has at most 255 options,
so a longer list is cut into groups.

### 5c. The scale, and the shapes of the search

**The scale is several thousand names** (§1). The window of the study has 131,
and the scale corpora of today have 1,224 and 786. Step 1 builds the **full
corpus**: every module of the packages that the omnet IDE loads, with every name
that the index keeps. Step 1 counts it. If it has fewer than several thousand
names, the report says so, and the modules of inet-julia join it.

**The ladder.** The questions are asked on corpora of four sizes: the window,
about 1,000, about 2,000, and the full corpus. Each size holds the expected
names, and the other names come from more modules. The ladder shows how each
method loses rank as the corpus grows, and at which size a shape stops to work.

At 5,000 entries, with a full text of about 400 tokens and a short line of
about 25 tokens, a question costs:

| shape | what the classifier reads | tokens | B1: cost, time | B2 with the 27B model |
| --- | --- | --- | --- | --- |
| flat | a `noul` per entry, full text | 2,000,000 | 8 cents, about 8 s at the rate limit | hours |
| two stages | a `noul` over the first 50 by words and the first 50 by meaning, full text | 40,000 | 0.2 cents | minutes |
| choice cascade | a `choice` over all names in groups of 255, short lines; then a `noul` over the best 30, full text | 140,000 | 0.6 cents | about ten minutes |
| tree | a `choice` over the modules, a beam of 3; a `choice` over the names of each chosen module; then a `noul` over the best 20, full text | 25,000 | 0.1 cent | minutes |

The B2 column is a guess until Step 0 measures the rate.

1. **Flat** is the reference: what the classifier ranks with no first stage. At
   the full scale it is too slow and too expensive for one search of the agent.
   It runs on B1 only, on a sample of the questions.
2. **Two stages** is capped by the recall of the first stage. At about 2,000
   names, a third of the expected names were not in the first ten by
   description, and some were not in the first fifty (§2d). Step 4 measures
   that recall on the ladder first. It costs nothing.
3. **The choice cascade** is the skill-suggestion cookbook at scale. Its first
   stage is the classifier, so the vectors do not cap it.
4. **The tree** is the owner's divide and conquer. A module of more than 255
   names splits by its types or by its files. For the guides: a `choice` over
   the guides, then over the sections, then over the paragraphs. A path scores
   as the geometric mean of its probabilities, as the cookbook does. The text of
   a module lists the names it declares, so a module with a poor docstring can
   still be chosen.

The choice cascade and the tree are the shapes that a product can use at the
full scale. The flat shape says how much they lose.

**B2 at the full scale.** With the 27B model, no shape answers in the time of one
round of the agent, which is about 50 s. If Step 0 confirms this, the local
option at scale needs a smaller model. Step 0 names a candidate, and the owner
decides if it is pulled.

### 5d. The backends

| backend | what it is | for | against |
| --- | --- | --- | --- |
| B1, TypeSafe Jev | the hosted model of §3a | the real Jev; every shape of §5c, and the flat reference at the full scale | sends docstrings, call sites and questions to an outside service (approved, D1); the flat shape costs 8 cents a question at the full scale |
| B2, a local classifier on Ollama | the simple-jev method: a prompt that ends in a yes or no question, `think` off; the noul is p(yes) / (p(yes) + p(no)) from `top_logprobs` of the first token; a `choice` reads the labels of its options the same way | local, as the product runs; the model of the study; no outside service | slow: a 27B model reads perhaps a few hundred tokens a second here, so it fits the window, and minutes a question in two stages or a tree (§5c) |
| B3, simple-jev | the open server of §3b | the method of B2 with KV reuse | no PyTorch here, no known ROCm support for this GPU, and 27B in bfloat16 does not fit the memory rule; only a small model fits |

The speed of B2 is a guess. Step 0 measures it.

**Where the clients are in Stage 1.** The harness of D4 takes a ranker as a
function, so it holds no HTTP code. The two clients are scripts in
`tool/search/`. They need `HTTP` and `JSON3`, which `environment/all` does not
list directly, so Step 3 gives the folder an environment of its own or adds the
two to `environment/all`. B1 reads `TYPESAFE_API_KEY` from the environment, as
`ProjecturedAnthropic` reads `ANTHROPIC_API_KEY`. Stage 2 moves the clients into
backend packages: B2 into `ProjecturedOllama`, beside the meaning model, and B1
into a new package whose name and place Stage 2 sets by the package rules.

**The classifier answers are kept.** A file keeps each answer by the hash of the
model name, its version and the request. A second run of a measurement costs
nothing and gives the same numbers.

### 5e. The questions of Stage 1

1. **The corpora of today**: 26 + 6 questions of projectured and 34 + 6 of
   omnet, with no context. They give the comparison with the earlier numbers.
2. **The S0 questions**: one question for each step of the table of §2c. Each
   has:
   - the sentence the model would search with when it does not know the name,
     in the words of the person and not of the docstring;
   - the context: the request of the person at that step and what the IDE holds
     at that point;
   - the expected **set** of names, and the expected guide section when there is
     one.

   They are asked on every size of the ladder of §5c, from the 131 entries of
   the study window to the full corpus, where the same names must be found among
   several thousand.
3. **The context pairs**: one sentence with two contexts that need different
   names. If the context does nothing, a pair shows it at once. About ten pairs.
4. **The real queries**: the 106 search calls of the logs of §2c. The context
   of each is the request of the person and the line of thinking before the
   call. The expected name is the one the model called next with success. A
   query that the transcript cut is read in full from the record of the seed,
   or it is left out.

The metrics: first, in five, in eight (what a summary answer shows), in ten,
and the mean reciprocal rank. For a set of expected names, the part of the set
in the first eight, and whether all of it is there. The comparison is per
question: how many questions rank better, worse, or the same.

**A tuning half and a report half.** The instructions of the `noul`, the budget
of the text and the count of call sites are chosen on one half of the
questions. The report gives the numbers of the other half.

### 5f. Stage 2: the search of the kernel

This is a change of the kernel and a new mechanism. The owner approved it (D5).
It starts only when Step 6 says that Stage 2 runs. What it is:

- `search_api(query; context = nothing, …)` and `search_guides(query; context =
  nothing, …)`. The two tool schemas get an optional `context` argument.
- A `ToolSet` holds a classifier as it holds a `MeaningModel`: a name and a
  function that answers a noul for each candidate. A backend package binds it,
  so the kernel does not hold HTTP code.
- The call-site file is built beside the meaning vectors, because a binary does
  not always have the source files.

The measurement in the fast loop: seeds 1 to 10 of `study_rehearsal.jl`, and of
`rehearsal.jl` for S2 and the tasks. It counts passes, rounds, search calls, the
rank of the needed name in each search answer, and the names the model guessed.
The conditions:

1. the search of today;
2. the classifier search;
3. the classifier search, with the context that the model writes;
4. the classifier search, with the last request of the person as the context,
   passed by the harness.

Conditions 3 and 4 both run (D3). The declared API of the fast loop is the full
corpus of §5c, and not the window, because the window is not the scale of the
application.

The system text stays fixed. The guide sections in the system text put S2 at 10
of 10 and the study at 7 of 7, and they teach the names, which hides a gain of
the search. So conditions 1 and 2 run again without those sections.

### 5g. Stage 3: the video

A take of S0 with the search that Stage 2 kept. The owner decides if it runs.

## 6. Steps

Each step says what stops the stage.

- [x] **Step 0. The probes.** No code in the repository. Done 2026-09-28 (§10):
  the key is an OpenRouter key, and Jev is reached through the Decisions API of
  OpenRouter.
  1. B1, with the key of D8: ask ten questions in the layouts L1 and L2. Read
     `usage.input_tokens`, to learn if the state is paid once per question. Ask
     each twice, to learn if the answer is the same. Find the limit of questions
     per request. Ask one `choice` of 255 options, to learn its cost and time.
  2. B2: ask `qwen3.8:27b` ten yes or no questions with `top_logprobs` and
     `think` off. Check that "yes" and "no" are in the top tokens. Read the time
     of the prompt from the Ollama answer (`prompt_eval_duration`), and compute
     the tokens per second. From it, fill the B2 column of §5c with numbers. If
     no shape fits a round of the agent at the full scale, name a smaller local
     model for the owner. The memory rule of §7 applies.
- [x] **Step 1. The corpora and the call sites.** Done 2026-09-28 (§10). The
  sizes of the ladder need the expected names of Step 2, so Step 3 builds them.
  1. The full corpus of §5c, and its count by kind and by package. ~~The sizes of
     the ladder, each with every expected name of every question.~~
  2. The call-site tool of §5a, and one file for the full corpus. The report:
     how many entries have a call site, how many have one from outside their
     package, how many short names are shared.
- [x] **Step 2. The questions.** The S0 questions, the context pairs, and the
  real queries (§5e), in a fragment beside `SearchScaleCorpus.jl` and in
  `OmnetIdeExample`. Done 2026-09-28 (§10): the three files are in
  `example/ide/` of the omnet-julia branch, and `OmnetIdeExample` includes them
  after the projectured side lands.
- [x] **Step 3. The harness.** ~~`measure_search_rankers!`~~
  `measure_search_rankings` beside `measure_search_scale!`: a ranker is a
  function of the question, the context and the entries that answers them in
  order. It prints the table of §5e for each ranker, the paired comparison, and
  the tokens and seconds of each. Done 2026-09-28 (§10). The ladder of §5c is
  not built yet.
- [ ] **Step 4. The API ranks.** In this order:
  1. Words and meaning on every size of the ladder, with and without the call
     sites, with and without the context (the controls of §4). The recall of the
     first stage at 50 and at 100 comes from the same runs. None of this costs
     money.
  2. On B1, at the full scale, the tree: with the documentation, then with the
     call sites, then with the context. This finds the best variant.
  3. On B1, at the full scale, the best variant in the choice cascade and in two
     stages.
  4. On B1, the flat reference: 20 questions of the report half, the best
     variant, at the full scale.
  5. The tree and the cascade on the smaller sizes of the ladder.
  6. On B2, the shapes that Step 0 found to fit, on the same questions.

  The budget of each item is in §8b.

  **Stop** if no classifier shape with the call sites and the context beats
  the best control at the full scale on the report half. Then the result is the
  text or nothing.
- [x] **Step 5. The guide ranks.** The same for `search_guides`, at the three
  sizes of §5a. Done 2026-09-28 (§10), with words, meaning, and Jev in two
  stages and as a cascade; the tree and the local classifier were not run on
  the guides.
- [x] **Step 6. The decision.** The owner reads the tables and decides if
  Stage 2 runs, and with which backend. Done 2026-09-28: D9.
- [ ] **Step 7. Stage 2** (§5f, §8c). The mechanism is approved (D5); the step
  starts when Step 6 says so.
  - [x] The kernel: `RelevanceModel`, `set_relevance_model!`, the `context` of
    both searches, the ranking by relevance, and a miss of a large declaration
    that names its modules (`3fc6a999`, `b9a7cbb9`); `test_relevance_search`
    (29), and the search suites pass.
  - [x] The backend: `make_jev_relevance_model` in `tool/search/typesafe_classifier.jl`.
  - [x] The harness: the conditions in `tool/assistant/study_rehearsal.jl` of
    omnet-julia (`e531c0e6`), and `/var/tmp/classifier-search/stage2/run_conditions.jl`.
  - [ ] The runs: six conditions, seeds 1 to 5, in a warm session of the scratch
    environment of the two worktrees.
- [ ] **Step 8. Stage 3** (§5g), if the owner asks for it.

## 7. Rules of a run

- **Memory.** One Julia process at a time. Before every run that loads a model,
  read `free -g`: the available memory must cover the cap of the Julia process,
  the model and 10 GB. Read `/api/ps`, and do not start when another session has
  a model loaded. Unload the models this session loaded at the end of each run.
- **Time.** A rank is not a time, so a run of ranks needs no idle machine. A
  figure of seconds per search is marked as taken on a shared machine. A timing
  measurement for a decision needs an idle machine and the word of the owner.
- **The outside service.** Send only the corpora of D1. The key is never in the
  repository, in a log or in the conversation. The answer file keeps the cost of
  a rerun at zero. The harness adds up the tokens it sent, and it stops at the
  limit of cost of D7.
- **The work** is done in a worktree, with a commit per step, and this plan is
  updated as the steps are done.

## 8. Decisions and open questions

### 8a. Decisions of the owner, 2026-09-28

- **D1. TypeSafe: yes.** The measurement can send the text of the corpora to
  TypeSafe: the projectured text, and the omnet-julia text and the S0 questions
  too. The account exists, and the owner holds the key.
- **D2. The local classifier on Ollama (B2): yes**, as a tool of the
  measurement.
- **D3. The context in Stage 2: both.** The model writes it in the tool call,
  and the harness passes the last request of the person. Both are measured.
- **D4. The measurement code** is a fragment of `ProjecturedKernelExample`
  beside `measure_search_scale!`.
- **D5. The kernel change of Stage 2 (§5f) is approved.** It starts only when
  Step 6 says that Stage 2 runs.
- **D6. The scale is several thousand names** (§1). The window of the study is
  a control, and the result counts at the full corpus.

The order of the backends: B1 first, because it answers "is a Jev classifier
better" with Jev itself and in every shape. Then B2 on the same questions, to
learn how much of a gain a local model keeps. Before D6, my view was that the
flat shape of the window was the main measurement. D6 moved it: at several
thousand names the flat shape is only a reference, and the choice cascade and
the tree are what a product can use.

- **D7. The limit of cost of Stage 1 is 10 dollars.** The harness stops at it
  and asks.
- **D8. The key** is in `~/.config/typesafe/api.env`, as the line
  `TYPESAFE_API_KEY=<key>`, with mode 600. A run reads it through
  `EnvironmentFile=` of `systemd-run`. The key never enters the conversation, a
  log, or the repository. It is an OpenRouter key (§10, Step 0, item 1).
- **D9. Stage 2 goes, with the recommendation of Step 6** (the owner,
  2026-09-28: "let's go"): `search_api` gets the optional `context` and ranks
  with Jev through OpenRouter; `search_guides` keeps the meaning vectors and
  lets Jev rank a pool of them; the local classifier is only a fallback.

### 8c. The design of Stage 2, as built

These are my decisions inside D5 and D9; each says the fact it rests on.

1. **`RelevanceModel`** in the tool layer, beside `MeaningModel`: a name, a
   `score(query, context, texts)` that answers a probability per text, and a
   `choose(query, context, options)` that answers a probability per option. A
   `ToolSet` holds one or none; `set_relevance_model!` gives one. The kernel
   holds no HTTP code.
2. **The classifier ranks a search by description** (`mode = "description"`).
   A keyword search stays as it is: its exact-name answer is right for a name
   the model knows, and most logged queries name the verb (§10, Step 2).
3. **The shape follows the size of the declaration.** Up to 255 entries, every
   entry gets a `noul` (the flat shape, one request); above, the cascade: a
   `choice` per group of 255, the best 3 of each, then a `noul` each. Stage 1:
   the cascade was the best shape at 5,187 entries, and flat is the most exact
   where it is cheap.
4. **`search_guides` by description with a relevance model**: a pool of the
   first 50 by words and 50 by meaning (with the context), then a `noul` each.
   Stage 1: two stages beat the cascade on the guides.
5. **The context** is an optional argument of both tools. The meaning vector of
   a search reads it too when there is no relevance model: on the context
   pairs of Stage 1 it took the vectors from 3 to 9 first.
6. **A failed relevance model falls back** to the ranking by meaning, and the
   first line of the answer says so, as a failed meaning model does now.
7. **No call sites in Stage 2.** Stage 1 found no gain from them, for the
   vectors or for Jev.
8. **The backend of Stage 2 is the script** `tool/search/typesafe_classifier.jl`,
   which makes a `RelevanceModel`. A package (`ProjecturedOpenRouter`, say) is
   made only when Stage 2 shows a gain at the level of the agent; a package
   before that result could be one to delete.
9. **The conditions of the fast loop that change what the model sends** (no
   context, the request of the person as the context) are made by the harness,
   which registers a wrapper of the search tool under the same name. No product
   mechanism passes the request.
10. **The declared API of the rehearsal is the full corpus** (§5c), 5,187
    entries, beside the window of the study (131) as a control.

### 8b. The budget of D7

My first estimate at the full scale was about 30 dollars. Each factor now runs
on the cheapest shape that can answer it, and only the best variant runs on the
dear shapes:

| work | what runs | tokens | dollars |
| --- | --- | --- | --- |
| Step 0 | the probes of B1 | 5 M | 0.2 |
| the text and the context (F2, F3) | the tree, three variants, every question, full scale | 20 M | 0.8 |
| the shapes (F4) | the choice cascade and two stages, the best variant, every question, full scale | 45 M | 1.9 |
| the flat reference | 20 questions of the report half, the best variant, full scale | 40 M | 1.7 |
| the ladder | the tree and the cascade, the best variant, three smaller sizes | 45 M | 1.9 |
| the guides (Step 5) | the tree and the cascade over the sections | 35 M | 1.5 |
| the tuning | reruns on the tuning half | 25 M | 1.0 |
| **total** | | **215 M** | **9.0** |

The answer file makes a rerun free, so a change of the harness does not spend
the budget again. If Step 0 finds that the state is paid once per question in
layout L2, the costs are higher, and the report of Step 0 gives a new table
before Step 4.

## 9. What can make the result wrong

- **A leak of words.** A question written with the words of a docstring, or a
  call site that holds the answer word for word. The questions are written from
  the steps and the words of the person, and §5a lists the excluded files.
- **Few questions.** At 26 or 34 questions, a difference of two is noise. The
  report gives the paired count per question and not only the totals.
- **A long state.** Jev loses accuracy on text unrelated to the decision. The
  budgets of Step 4 measure this.
- **The model does not search.** A better rank helps only when the model calls
  the search. Stage 2 counts the calls, and it runs without the guide section in
  the system text too.

## 10. Findings

### Step 0, 2026-09-28

The probes are in `/var/tmp/classifier-search/step0/`, outside the repository:
`dump_corpus.jl`, `typesafe.py`, `probe_b1.py`, `probe_b2.py`, and their logs.

**The corpus of the probes.** `dump_corpus.jl` declares the 25 modules of the
projectured scale corpus, and the index holds **1,360 entries**: 569 functions,
511 types, 255 values, 25 modules. The dump took less than a minute with the
main checkout. A docstring is short: the median is 181 characters, the tenth
from the top is 819, and the whole corpus is 459,430 characters, about 115,000
tokens. So a full text is about 115 tokens without call sites, and the 400
tokens of §5c hold three call sites with room to spare.

**B1, TypeSafe: the key is refused.** The header is right:
`Authorization: Bearer <key>` answers 401 "Cannot authenticate with the server.
Please check your API key", and `x-api-key`, `api-key` and a bare
`Authorization` answer 403 "Must supply an API key!". The key in the file is 73
characters, with no white space and no quotes. Nothing was spent. The owner
checks the key.

**B2, the local classifier: it works, and it is fast enough for small pools.**
Ten questions of the scale corpus, 16 candidates each: the expected name and
the best 15 other names by words. The candidate text is the name, the kind, the
signature and the docstring cut at 1,500 characters. No call site and no
context.

| question | the expected name | rank by words in the corpus | rank by B2 of 16 | noul of the expected, and of the next |
| --- | --- | --- | --- | --- |
| put widgets beside each other in one row | `HorizontalLayout` | 81 | 1 | 1.00, 0.92 |
| a surface with a heading around a table | `WidgetCard` | 28 | 1 | 0.89, 0.45 |
| let a person scroll over content taller than the space | `WidgetScrollPane` | 2 | 1 | 1.00, 0.94 |
| show a document in a new tab of the window | `open_pane!` | 139 | 1 | 1.00, 0.42 |
| write a new value where a reference points | `replace_referenced_value!` | 3 | 1 | 0.99, 0.98 |
| a value that is computed again when what it reads changes | `Cell` | 112 | 1 | 0.98, 0.37 |
| make a field of a document computed | `set_cell_computation!` | 284 | 1 | 0.99, 0.09 |
| turn a key press into an edit of the document | `read_intent` | 116 | 1 | 1.00, 0.42 |
| read a saved document back from its text | `parse_pred_text` | 10 | 1 | 0.98, 0.07 |
| say which names a model may write | `declare_api!` | 9 | 1 | 0.97, 0.90 |

- **10 of 10 first.** The distractors are the best by words, so they share
  words with the question. They are not the best by meaning, so this pool is
  easier than the pools of Step 4. What it shows: the classifier reads the
  question and the docstring together, and three names that the earlier plan
  could not find by either mode (`Cell`, `set_cell_computation!`,
  `parse_pred_text`) rank first here with a wide margin.
- **The second place is often a real neighbour**: `ReplaceReferencedValueOperation`
  at 0.98, `WidgetScrollBar` at 0.94, `list_types` at 0.90. So a threshold does
  not separate the answer; the order does.
- **The answer token is always there.** With `think` off, "yes" or "no" was in
  the 20 top tokens of the first position in all 160 calls. The first position
  also holds "Yes", " yes" and "No", so the sum over the forms of a word is
  right.
- **The rate.** 39,082 tokens of prompt in 156 s: **250 tokens a second**. Ollama
  reuses the shared start of the prompt, so a call evaluated 244 new tokens on
  average. The 160 calls took 181 s, with the load of the model. So one
  candidate costs about one second.

**The B2 column of §5c, measured.** At one second a candidate: two stages over
30 candidates take about 30 s, and over 100 about 100 s; the tree takes about
100 s; the flat shape takes about 2 minutes on the window of 131 names and more
than 20 minutes on 1,360. So B2 with the 27B model fits a round of the agent
(about 50 s) only in two stages over about 30 candidates, where the vectors
cap the recall. A smaller model is the local option for the other shapes. I
will name a candidate when Step 4 shows which shape wins.

### Step 1, 2026-09-28

The code: `example/kernel/SearchCorpus.jl` and `example/kernel/CallSite.jl`,
fragments of `ProjecturedKernelExample`, with `test/projectured/SearchCorpusTest.jl`
(6 pass) and `test/projectured/CallSiteTest.jl` (17 pass). The tests ran against
the main environment, with the fragments included from the worktree, so nothing
recompiled; they are in `ProjecturedSuite.jl` too. The naming guard passes. The
run script is `/var/tmp/classifier-search/step1/build_corpus.jl`, and it writes
`corpus.ndjson` with the three best call sites of each entry.

**The full corpus: 5,185 entries.** The script loads `OmnetIde`, `Omnet`,
`Projectured`, `OmnetLegacy`, `OmnetLegacyModel`, `OmnetRunner`, `OmnetStudy`,
`OmnetDynamics` and `OmnetMeasure`, and `collect_package_modules` takes every
module of the packages named `Projectured…` and `Omnet…`, except the example,
test and benchmark packages.

| corpus | modules | entries | functions | types | values |
| --- | --- | --- | --- | --- | --- |
| the window of the study | 13 | 131 | 64 | 53 | 2 |
| `using OmnetIde` alone | 150 | 2,650 | 1,130 | 1,053 | 317 |
| the full corpus | 280 | 5,185 | 2,559 | 1,894 | 452 |

The largest packages of the full corpus are `OmnetSimulator` (1,092 entries),
`ProjecturedKernel` (524), `OmnetPresentation` (419) and `ProjecturedStyle`
(326). 18 names were dropped because a second module exports another binding
under the same name. The declaration takes 45 s and the index 1 s.

**A decision: a name comes from the module that owns it.** The umbrella modules
`Projectured` and `Omnet` re-export the names of their packages and come first in
the order of full names. The first run gave them 2,760 and 1,409 names, so a hit
read `Projectured.open_pane!` and the folder of its call sites was the umbrella.
`make_corpus_declaration` now gives a name from the module that owns its binding
(`Base.binding_module`) when that module exports it.

**The call sites.** The roots are `source`, `example`, `test`, `tool`, `package`
and `documentation` of both repositories. 133,711 calls of 12,479 names, parsed
in 1.1 s. **3,983 of the 4,905 names have a call site (81 %)**, and 2,945 (60 %)
have one from outside the folder of their module. `open_pane!` has 17, `Cell`
766, `make_study!` 3.

- A parser fact: in Julia 1.13 the parser gives `f(x) = y` as a `function`
  node, like the long form. The first version counted every call in the body of
  a short definition as a definition, and the test found it.
- **The assistant guide of omnet-julia shows the S0 study.** The best call site
  of `make_study!`, `add_expectation!` and `make_result_plot` is its code:
  `make_study!(editor; title = "An M/M/1/K queue", …`. It stays a source (§5a),
  because the guide is real and the agent reads it. So Step 4 asks the S0
  questions a second time without the call sites of the guides, to learn how
  much of a gain is the guide.

### Step 2 and Step 3, 2026-09-28

**The questions** are in `example/ide/` of the omnet-julia branch
`classifier-search`:

| file | constant | questions | context | expected |
| --- | --- | --- | --- | --- |
| `SearchContextCorpus.jl` | `STUDY_SEARCH_QUESTIONS` | 14, one per step of the study that needs a name | the request of the person and what the window holds | every name the step calls, 1 to 3 |
| `SearchContextCorpus.jl` | `CONTEXT_PAIR_SEARCH_QUESTIONS` | 16: 8 sentences, each with two contexts | a situation in two sentences | one name, another for each context |
| `SearchLogCorpus.jl` | `LOG_SEARCH_QUESTIONS` | 41 | the request and the thinking of the model before the call | the names of the corpus that the next working code called |

- The 41 logged questions are the `search_api` calls whose next code worked
  and called a name of the corpus. 6 more had a next call that worked but the
  parser did not find its code. The expected set of a logged question can hold
  names the model knew already, so only the best place counts for them, not
  "all in eight". Most of their queries name the verb already (49 of 82 hold a
  `!` or a `_`), so they measure a lookup more than a discovery.
- The pairs are: "stop it now", "save it", "run it", "open it", "add one more
  row to it", "get its current value", "read that file" and "write it to a
  file".
- `OmnetIdeExample` does not include the files yet: they use `SearchQuestion`
  of the projectured branch, and omnet-julia sees only the main checkout of
  projectured-julia. The run script includes them directly.

**The harness** is `example/kernel/SearchRanking.jl` in `ProjecturedKernelExample`:
`SearchQuestion`, `SearchRanker`, `make_word_ranker`, `make_meaning_ranker`,
`make_classifier_ranker`, `make_candidate_text` and `measure_search_rankings`.
The classifier ranker takes the score function as an argument, so the example
package holds no HTTP code. The run script is `tool/search/measure_rankings.jl`
of the omnet branch, and the local classifier is `tool/search/ollama_classifier.jl`
of the projectured branch; both take `HTTP` and `JSON3` from `ProjecturedOllama`,
so no environment changes.

- **A decision: the first stage of the classifier reads the sentence alone**:
  the first 20 by words and the first 20 by meaning. So the three classifiers
  differ only in what the classifier reads: the documentation; the call sites
  too; the context too.

### Step 4, the free rankers at the full scale, 2026-09-28

5,187 entries (the full corpus and the two names of `ProjecturedOllama`, which
the script loads), 3,984 with call sites, 90 questions. First / five / eight /
ten; the mean reciprocal rank of the best expected name; the questions with
every expected name in the first eight.

| questions | ranker | first / 5 / 8 / 10 | reciprocal | all in 8 |
| --- | --- | --- | --- | --- |
| scale, 60, no context | words | 6 / 14 / 14 / 16 | 0.16 | 14 |
| | meaning | 13 / 26 / 28 / 30 | 0.33 | 28 |
| | meaning, call sites | 14 / 24 / 27 / 29 | 0.31 | 27 |
| study, 14 | words | 2 / 6 / 6 / 7 | 0.23 | 4 |
| | words, context | 0 / 4 / 7 / 8 | 0.14 | 3 |
| | meaning | 4 / 6 / 7 / 7 | 0.38 | 7 |
| | meaning, call sites | 4 / 6 / 6 / 8 | 0.36 | 6 |
| | meaning, context | 3 / 8 / 8 / 8 | 0.37 | 5 |
| | meaning, call sites, context | 3 / 7 / 8 / 8 | 0.35 | 5 |
| pair, 16 | words | 3 / 6 / 7 / 8 | 0.31 | 7 |
| | words, context | 5 / 11 / 13 / 13 | 0.48 | 13 |
| | meaning | 3 / 4 / 9 / 11 | 0.29 | 9 |
| | meaning, call sites | 3 / 6 / 11 / 11 | 0.31 | 11 |
| | meaning, context | 9 / 13 / 14 / 14 | 0.66 | 14 |
| | meaning, call sites, context | 7 / 14 / 15 / 15 | 0.62 | 15 |

- **The meaning vectors are the control to beat, and with the context.** At
  5,187 names they put half of the scale questions in the first ten, and words
  put a quarter there. Against words per question, meaning is better on 61 of
  90 and worse on 23.
- **The call sites do not help a vector.** On the scale questions they cost a
  little (26 against 24 in five); on the pairs they gain two in eight. A vector
  of one text averages the call sites into the docstring, and the words of a
  call site (`editor`, `card`, `title`) are the words of every call site.
- **The context helps a vector much.** On the pairs, 9 first against 3, and 14
  in eight against 9. So the context is worth giving to the search whatever the
  scorer is. On the study questions it helps less (8 in five against 6),
  because the request of the person names the whole study and not the step.
- The recall of the first stage is visible here: by meaning, 30 of 60 scale
  questions have their name in the first ten. So a classifier over the first 20
  of two rankers can reach at most what those pools hold. The flat shape on B1
  measures what that cap costs.

### Step 4, the local classifier on the questions with a context, 2026-09-28

B2 (`qwen3.8:27b`, `think` off) in two stages: the pool is the first 20 by words
and the first 20 by meaning, both of the sentence alone. 71 questions, 5,187
entries; 8,500 answers of the model at about 46 a minute (about 3 hours), kept
in `/var/tmp/classifier-search/rankings/ollama-classifier-cache.ndjson`.

| questions | ranker | first / 5 / 8 / 10 | reciprocal | all in 8 |
| --- | --- | --- | --- | --- |
| study, 14 | meaning, context (the best control) | 3 / 8 / 8 / 8 | 0.37 | 5 |
| | local classifier, documentation | 11 / 11 / 11 / 11 | 0.79 | 8 |
| | local classifier, call sites | 11 / 11 / 11 / 11 | 0.79 | 8 |
| | local classifier, call sites, context | 10 / 11 / 11 / 11 | 0.75 | 8 |
| pair, 16 | meaning, context (the best control) | 9 / 13 / 14 / 14 | 0.66 | 14 |
| | local classifier, documentation | 4 / 9 / 11 / 11 | 0.42 | 11 |
| | local classifier, call sites | 6 / 10 / 10 / 11 | 0.49 | 10 |
| | local classifier, call sites, context | **13 / 15 / 15 / 15** | 0.86 | 15 |
| log, 41 | meaning (the best control) | 35 / 38 / 40 / 40 | 0.90 | 6 |
| | local classifier, call sites, context | 36 / 40 / 41 / 41 | 0.92 | 8 |

- **Inside its pool, the classifier is nearly always right.** On the study
  questions it put the name first in every one of the 11 whose name was in the
  pool; on the pairs, with the context, in 13 of the 15.
- **Every miss is a miss of the pool.** The three study questions that no
  classifier answered have ranks such as 37 and 53 by meaning of the sentence,
  outside a pool of 20. By meaning with the context the same names stand at 2,
  4 and 7. `insert_elements!` for "add one more row to it" in the JSON context
  is at 101 and 184, so no pool holds it. **The decision of Step 3 to take the
  pool from the sentence alone hid this**; the stage `local-pool` of the run
  script takes it from words, meaning, and meaning with the context.
- **The context is read.** On the pairs the classifier without the context puts
  4 or 6 first, which is the most a reader of the sentence alone can reach in
  pairs whose two answers differ; with it, 13.
- **The call sites change little for the classifier here**: two more first on
  the pairs without the context, one more in ten on the logged questions, none
  on the study.
- The logged questions mostly name the verb (§10, Step 2), so every ranker does
  well on them, and they separate the rankers little.
- The seconds: the classifier took 1,700 to 3,300 s for 71 questions, 25 to 45 s
  a question. Too slow for a round of the agent at this depth; the pool of three
  rankers is larger still.

### Step 0, item 1: Jev through OpenRouter, 2026-09-28

**The key was an OpenRouter key.** The owner's colleague saw that the workspace
of the key allows one model, Jev 1.13 of the provider TypeSafe. OpenRouter
serves Jev at `POST https://openrouter.ai/api/alpha/decisions`, with the key as
the bearer token and the request shape of TypeSafe (`model`, `state`,
`questions`). The model is `typesafe/jev-1.13`, the exact id the workspace
allows; the answer says `typesafe/jev-1.13-20260917`, the provider `TypeSafe`,
and `usage.cost` in dollars, which the ledger now keeps. The key limit of the
account is $50 a month, and it showed $0.20 used before this work began.

The probe (`probe_b1.py`), on the ten questions of item 2, cost $0.0075:

| probe | result |
| --- | --- |
| L1, one request per candidate, 160 requests | 9 of 10 first (`declare_api!` second); 86,608 tokens; 0.37 s a request |
| L2, one request per question, 16 nouls | **10 of 10 first; 46,513 tokens**; 0.38 s a request |
| the state, with 1 and with 10 short questions | 1,925 and 2,072 tokens: the state is paid once per request |
| the same request twice | 0.97 and 0.97 |
| questions in one request | 100, 256, 512 and 1,024 accepted; 1,024 took 1.44 s |
| one `choice` of 255 short lines | 7,584 tokens, 0.79 s; `WidgetCard` second, at 0.13 after 0.21 |

- **L2, the fan-out layout, is the layout**: half the tokens of L1 and at least
  as good. `make_typesafe_noul_score` sends 150 candidates per request, well
  under the 64k tokens of a request.
- A `choice` over short lines is weaker than a `noul` over full texts, as the
  skill-suggestion cookbook expects: it is a first stage that keeps a few, and
  the cascade keeps three of each group.
- **The budget of §8b is too high.** A docstring is short (§10, Step 0, item 2)
  and the state is paid once, so a two-stage question costs about 30,000
  tokens, a tree about 35,000, a cascade about 175,000, and a flat question over
  5,187 entries about 1.3 million. The whole stage `hosted` is about $3.

### Step 4, Jev through OpenRouter at the full scale, 2026-09-28

The stage `hosted`, on the 131 questions and the 5,187 entries. The first run
lost 26 cascade questions and 11 of the 20 flat questions to connection errors,
because the client retried only a status of 429 or 529 and one failed request
failed its question. The client now retries a connection error too, with a wait
that doubles, and the second run sent only what had failed; one tree question
still failed on an HTTP 520 of the server. **The whole of Stage 1 on Jev so far,
Step 0 included, cost $3.24.**

The two stages read a pool of the first 50 by words, by meaning, and by meaning
with the context. The cascade keeps the 3 best of each group of 255. The tree
keeps a beam of 3 and scores the best 20.

| questions | ranker | first / 5 / 8 / 10 | reciprocal | all in 8 |
| --- | --- | --- | --- | --- |
| scale, 60 | meaning (the best control) | 13 / 26 / 28 / 30 | 0.33 | 28 |
| | Jev, two stages, documentation | 35 / 43 / 43 / 43 | 0.63 | 43 |
| | Jev, two stages, call sites | 35 / 42 / 43 / 43 | 0.63 | 43 |
| | Jev, two stages, call sites, context | 35 / 42 / 43 / 43 | 0.63 | 43 |
| | **Jev, cascade, call sites, context** | **44 / 49 / 52 / 54** | 0.78 | 52 |
| | Jev, tree, call sites, context | 28 / 32 / 33 / 33 | 0.49 | 33 |
| study, 14 | meaning, context (the best control) | 3 / 8 / 8 / 8 | 0.37 | 5 |
| | Jev, two stages, documentation | 11 / 13 / 13 / 14 | 0.84 | 9 |
| | Jev, two stages, call sites | 12 / 14 / 14 / 14 | 0.89 | 10 |
| | Jev, two stages, call sites, context | 10 / 14 / 14 / 14 | 0.82 | 11 |
| | Jev, cascade, call sites, context | 8 / 13 / 13 / 13 | 0.70 | 9 |
| | Jev, tree, call sites, context | 9 / 10 / 10 / 10 | 0.67 | 8 |
| pair, 16 | meaning, context (the best control) | 9 / 13 / 14 / 14 | 0.66 | 14 |
| | Jev, two stages, documentation | 3 / 7 / 9 / 9 | 0.34 | 9 |
| | Jev, two stages, call sites, context | **14 / 15 / 15 / 15** | 0.91 | 15 |
| | Jev, cascade, call sites, context | 13 / 15 / 15 / 15 | 0.88 | 15 |
| | Jev, tree, call sites, context | 7 / 9 / 9 / 9 | 0.50 | 9 |
| log, 41 | meaning (the best control) | 35 / 38 / 40 / 40 | 0.90 | 6 |
| | Jev, two stages, call sites, context | 35 / 39 / 40 / 41 | 0.90 | 5 |
| | Jev, cascade, call sites, context | 34 / 39 / 39 / 40 | 0.88 | 5 |
| | Jev, tree, call sites, context | 30 / 31 / 33 / 33 | 0.74 | 10 |

The flat shape, on 20 questions (the first 5 of each group), against the same
questions: meaning with the context 7 / 16 / 18 / 18; Jev in two stages
16 / 18 / 19 / 20; **Jev flat 16 / 18 / 18 / 19**. Flat cost 16.3 million
tokens for the 20 questions, $0.034 a question, and 12 s a question.

- **A classifier ranks far better than the meaning vectors at the full scale.**
  On the scale questions, which have no context, Jev puts 35 or 44 first where
  the vectors put 13, and 43 or 54 in ten where they put 30. On the study
  questions, 10 to 12 first against 3 or 4.
- **The cascade is the best shape at scale.** Its first stage is the classifier
  itself, so it does not inherit the recall of the vectors: 54 of 60 in ten,
  against 43 for two stages. On the study questions it is a little behind two
  stages (13 against 14 in ten). It costs about $0.009 a question and 22
  requests, which run one after another here; in parallel they take about one
  second.
- **The flat shape adds nothing over two stages on the sample**, at thirty times
  the cost. The pool of 150 holds the answer as often as the whole corpus does,
  for these 20 questions.
- **The tree is the weakest shape of Jev.** A choice among the packages and then
  among the modules, from a line of each, loses the answer early: 33 of 60 in
  ten, less than two stages. A beam of 3 does not repair it. The divide and
  conquer of the owner was measured, and in this form it is not the shape to
  use. A wider beam or a better line per module could change that; it is not
  measured.
- **The call sites do not help Jev either.** On the scale questions, 35 / 43
  with and without them; on the study questions one more first; on the pairs
  without the context one fewer. The gain is the classifier reading the
  question and the documentation together, not the call sites.
- **The context decides the pairs**: 3 first without it, 14 with it.
- The logged questions name their verb, so every ranker answers them; only the
  tree loses there.

### Step 5, the guides, 2026-09-28

34 questions: the 12 guide questions of the two scale corpora, which name a
guide; `GUIDE_SEARCH_QUESTIONS`, 13 questions of the projectured guides, each
with its section; and `STUDY_GUIDE_SEARCH_QUESTIONS`, 9 questions of the steps
of the study, each with its section of the assistant guide and the request of
the person as its context. The guides of the IDE are the projectured
documentation and `omnet/…`: **120 guides, 1,707 sections, 4,931 paragraphs**.
Jev read the pool of words, meaning, and meaning with the context, 50 each; the
cascade kept 3 of each group of 255. The run cost $0.62. Two cascade requests
failed on an HTTP 520; the client now retries a server error too.

| part | questions | best of words and meaning | Jev, two stages | Jev, cascade |
| --- | --- | --- | --- | --- |
| guide, 120 | scale, 12 (a guide) | meaning 9 / 9 / 9 / 9 | 9 / 12 / 12 / 12 | 11 / 11 / 11 / 11 |
| | guide, 13 (by its guide) | words 4 / 7 / 9 / 9 | **9 / 12 / 12 / 12** | 6 / 7 / 7 / 7 |
| | study, 9 (by its guide) | words 3 / 8 / 8 / 8; meaning, context 1 / 3 / 3 / 5 | **7 / 9 / 9 / 9** | 4 / 5 / 5 / 5 |
| section, 1,707 | scale, 12 | meaning 7 / 11 / 11 / 11 | 6 / 10 / 12 / 12 | 5 / 8 / 8 / 9 |
| | guide, 13 | meaning 9 / 10 / 10 / 10 | 10 / 11 / 12 / 12 | 9 / 12 / 13 / 13 |
| | study, 9 | meaning, context 7 / 9 / 9 / 9 | **9 / 9 / 9 / 9** | 9 / 9 / 9 / 9 |
| paragraph, 4,931 | scale, 12 | meaning 5 / 11 / 12 / 12 | 3 / 12 / 12 / 12 | 2 / 10 / 10 / 10 |
| | guide, 13 | meaning 8 / 11 / 12 / 12 | 9 / 12 / 12 / 13 | 9 / 11 / 11 / 11 |
| | study, 9 | meaning, context 6 / 9 / 9 / 9 | **9 / 9 / 9 / 9** | 6 / 8 / 8 / 8 |

- **On the guides the vectors are already good, and the classifier gains
  less than on the API.** At the size of a section the meaning vectors put 9
  of 13 section questions first and Jev 10; on the study questions, 7 of 9
  against 9 of 9. At these counts, one or two questions are noise.
- **The gain is large where a part is long and mixed**: a whole guide. There
  the vectors put 1 of the 9 study questions first, and Jev in two stages 7.
- **Two stages beat the cascade on the guides**, the other way round from the
  API. A choice reads a line of a part, and the first hundred characters of a
  paragraph say less of it than the first sentence of a docstring says of a
  name.
- The questions that name only a guide (scale) are answered better when the
  parts are whole guides; at the size of a section, Jev puts a section of
  another guide first more often than the vectors do (6 against 7 first).
- **What this says for `search_guides`**: the section stays the part; a
  classifier over a pool of the vectors, with the context, puts the right
  section first a little more often, and it keeps the study questions at 9 of
  9. The case for the classifier is the API, not the guides.

### Step 7, the conditions of the runs, 2026-09-28

All six declare the full corpus, 5,187 entries (§8c, item 10):

| | ranking of a search by description | context the relevance model reads | the guide sections in the system text |
| --- | --- | --- | --- |
| c1 | meaning | (none: no relevance model; the vector reads what the model writes) | yes |
| c2 | Jev | none | yes |
| c3 | Jev | what the model writes | yes |
| c4 | Jev | the request of the person, from the harness | yes |
| c5 | meaning | (as c1) | no |
| c6 | Jev | what the model writes | no |

- **c1 is not the search of `main`**: the tool schema has the `context`
  argument in every condition, so the conditions differ only in the ranking
  and the context the ranking reads.
- **c6 runs c3 without the guide sections, not c2** as §5f said: c3 is the form
  the product would have.
- The runs go seed by seed across the conditions, so a stop leaves comparable
  results, and they stop before a seed when the ledger holds $9.50: the limit
  of D7 covers Stage 2 too, until the owner sets another.
- The local classifier run of the pool with the context was stopped for Stage
  2 at 7,784 answers, because the agent of the rehearsal uses the same model.
