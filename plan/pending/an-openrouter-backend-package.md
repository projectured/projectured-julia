# An OpenRouter backend package

Status: a plan, 2026-09-29. Nothing is implemented. It builds on the branch
`classifier-search`, whose kernel holds the `RelevanceModel`.

## 1. The request

`a-classifier-ranks-the-search.md` measured Jev, the decision model of TypeSafe,
through the Decisions API of OpenRouter, with a script. The product needs a
package that gives a `ToolSet` that model. The owner agreed, 2026-09-29, to the
name `ProjecturedOpenRouter` and the names that follow from it (§3).

## 2. What exists

- **The kernel** (on the branch): `RelevanceModel(name, score, choose)` in
  `ToolModule`, and `set_relevance_model!`. `score(query, context, texts)`
  answers a probability per text; `choose(query, context, options)` a
  probability per option. A model that throws leaves the ranking to the meaning
  model.
- **The script** `tool/search/typesafe_classifier.jl`: the request of the
  Decisions API, a `noul` per text in batches of 150, a `choice` over at most
  255 options, retries on 429, on a server error and on a broken connection, a
  cache of answers on disk and a ledger of cost. `make_jev_relevance_model(ask)`
  makes the kernel's model from it.
- **Two backend packages to follow**: `ProjecturedAnthropic` and
  `ProjecturedOllama` depend on the kernel, HTTP and JSON3, hold the wire format
  of one service, and read the key from the environment.
- **What the Decisions API does** (measured, §10 of the measurement plan):
  `POST https://openrouter.ai/api/alpha/decisions` with the key as the bearer
  token; `model`, `state`, `questions`; about 0.4 s a request; up to 1,024
  questions a request; the same answer to the same request; `usage.cost` in
  dollars. "alpha" in the address says that OpenRouter can change it.

## 3. The design

- **The package** `ProjecturedOpenRouter`, a stem of its own: it depends on
  `ProjecturedKernel`, HTTP and JSON3, as `ProjecturedAnthropic` does. The slice
  folder is `source/openrouter/`, its file `OpenRouter.jl`.
- **The one function**
  `make_openrouter_relevance_model(; api_key = get(ENV, "OPENROUTER_API_KEY", ""), model = "typesafe/jev-1.13")`
  answers a `RelevanceModel` named `"openrouter/" * model`:
  - `score` sends the query as the state (and the context, when a caller from
    code gives one) and one `noul` per text, 150 texts a request;
  - `choose` sends one `choice` whose options are the identifiers and lines;
  - both retry a busy server (429), a failed one (5xx) and a broken connection,
    with a wait that doubles, and throw after six tries; the kernel then ranks
    by meaning and says why.
- **A cache in memory**, per model, of the answers by the hash of the request:
  an agent repeats its searches, and the same request gives the same answer.
  No file and no ledger: those belong to the measurement.
- **No key, no model**: with an empty key the function throws at once with a
  message that names `OPENROUTER_API_KEY`, so a window that asks for it without
  a key learns why.
- **The tests** (`ProjecturedOpenRouterTest`, `test/openrouter/OpenRouterSuite.jl`,
  `test_openrouter()` and `test_openrouter_layering()`) never reach the network:
  the function that sends a request is a keyword argument, and a test gives one
  that answers from a table. They check the body of a request, the reading of
  an answer, the batches, the retries and the error without a key.
- **The documents**: `documentation/package/openrouter/openrouter.md`, and the
  row of the table of `documentation/rule/package-rules.md` for the packages that
  own a third-party dependency.
- **The script of the measurement** keeps its disk cache and its ledger; it is a
  tool of measurement, not a second client of the product. It can move onto the
  package later.

## 4. Steps

- [ ] **Step 0.** The owner answers §5.
- [ ] **Step 1.** The package, the test package, `environment/all`, and the
  naming guard.
- [ ] **Step 2.** `make_openrouter_relevance_model` and its tests.
- [ ] **Step 3.** The documents, and `test_package_graph()`.
- [ ] **Step 4.** One real request with the key, and the Step 4c questions
  through the kernel's `search_api` with this model: the ranks must match the
  ranks of the harness within a question or two. About $0.20.
- [ ] **Step 5.** Where it is bound (§5, question 1).

## 5. Questions for the owner

1. **Who binds it, and when?** My recommendation: a window binds it when
   `OPENROUTER_API_KEY` is set, and runs as today when it is not. The omnet IDE
   would do that in its window setup, beside the meaning model.
2. **The key.** The file `~/.config/typesafe/api.env` names it
   `TYPESAFE_API_KEY`. The package reads `OPENROUTER_API_KEY`, the usual name.
   Rename the line, and move the file to `~/.config/openrouter/`? The scripts of
   the measurement follow.
3. **The default model**: `typesafe/jev-1.13`, the one id your workspace allows,
   or the alias `~typesafe/jev-latest`, which follows new versions and which the
   workspace could refuse?
