# An OpenRouter backend package

Status: done, 2026-09-29. Built and checked (`2fef98b4`), and on `main` with
the kernel `RelevanceModel` (`b4127e3e`).

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
  `make_openrouter_relevance_model(; api_key = get(ENV, "OPENROUTER_API_KEY", ""), model = "~typesafe/jev-latest")`
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

- [x] **Step 0.** The owner answers §5 (§6).
- [x] **Step 1.** The package, the test package, `environment/all`, and the
  naming guard.
- [x] **Step 2.** `make_openrouter_relevance_model` and its tests:
  `test_openrouter()` passes 30 checks offline and skips the live one without a
  key; with the key the live check passes. The keywords `send` and `wait`
  replace the request and the wait, so the tests reach no network.
- [x] **Step 3.** The documents (`documentation/package/openrouter/openrouter.md`,
  the row of the package rules, the index), and `test_package_graph()` (675
  checks, run on its own: it reads only the project files).
- [x] **Step 4.** The questions of Step 4c through the kernel's `search_api`
  with this model, end to end (`/var/tmp/classifier-search/e2e/run.jl`, in the
  scratch environment of the two worktrees). First / five / eight / ten of 20:

  | answers | the kernel with the package | the harness (Step 4c) |
  | --- | --- | --- |
  | no docstring | 5 / 11 / 14 / 14 | 5 / 10 / 14 / 15 |
  | short docstring | 12 / 16 / 17 / 17 | 11 / 15 / 17 / 18 |
  | longer docstring | 13 / 16 / 16 / 16 | 13 / 15 / 16 / 16 |

  47 of the 60 questions got the same rank, and no search failed. The corpus
  held 5,191 entries, not 5,187 (the name of the package among them), which
  moves the groups of 255 of the cascade and so some choices. The package keeps
  no ledger; by the tokens of Step 4c the run cost about $0.50, so the ledger
  of the measurement ($6.87) understates the spend by that much.
- [x] **Step 5.** Where it is bound: nowhere by itself (§6, D1); the document
  of the package shows the call.

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

## 6. Decisions of the owner, 2026-09-29

- **D1. Explicit use** ("should be used explicitly"): no window binds the model
  by itself; a caller gives it to a tool set with `set_relevance_model!`.
- **D2. The key** ("yes"): the line is `OPENROUTER_API_KEY=` in
  `~/.config/openrouter/api.env`, mode 600; the old file is gone, and the
  measurement scripts read the new name.
- **D3. The default model** ("type alias"): `~typesafe/jev-latest`. The workspace
  of the key accepts it; it resolved to `typesafe/jev-1.13-20260917`.

A slip on the way: one run of the live test passed the key on the command line
of `systemd-run` for a few seconds, where another local user could have read it
in the process list. Every run since reads it through `EnvironmentFile=`.
