# The relevance model on OpenRouter

> **Kind:** design · **Status:** current · **Stands on:** [agent.md](../kernel/agent.md)

`ProjecturedOpenRouter` gives a `ToolSet` a `RelevanceModel` that asks a decision model through the Decisions API of OpenRouter. A decision model reads a text and typed questions about it, and answers each question with probabilities instead of words. Jev of TypeSafe is such a model, and it is the default. This document says what the package sends, what it reads back, and what it does not do.

## How it is used

Nothing binds the model by itself. A window, or a person at the REPL, asks for it:

```julia
using ProjecturedOpenRouter
set_relevance_model!(editor.tools, make_openrouter_relevance_model())
```

`make_openrouter_relevance_model` reads the key from `OPENROUTER_API_KEY`, or from its `api_key` keyword, and throws at once without one. The model is `~typesafe/jev-latest` unless the `model` keyword names another: the alias follows the new versions of Jev. [agent.md](../kernel/agent.md) says how a search uses a relevance model: which searches go to it, the flat and the cascade shapes, and what happens when it fails.

## How it works

The kernel asks a `RelevanceModel` two things, and the package turns each into one kind of question of the Decisions API:

| the kernel asks | the package sends | the package reads |
| --- | --- | --- |
| `score(query, context, texts)` | a `noul` per text, "would a programmer call or use this API entry to do what the request asks", with the text of the entry in its instructions; 150 texts to a request | the `noul` of each, a probability from 0 to 1 |
| `choose(query, context, options)` | one `choice` whose options are the identifiers, each with its line | the `probabilities` of the options, in their order |

The state of a request holds the query, and the context when a caller from code gives one. The state is paid once per request, however many questions the request holds, so a score sends many texts to one request rather than one text to each.

- **The address** is `https://openrouter.ai/api/alpha/decisions`, with the key as the bearer token. "alpha" in it says that OpenRouter can still change it.
- **A request is tried again** when the server is busy (429), fails (5xx), or the connection breaks, six times at most, with a wait that doubles. Then the model throws, and the search ranks by meaning and says why in the first line of its answer.
- **The same request is answered from memory.** A decision model gives the same answer to the same request, and an agent repeats its searches, so each model keeps its answers by the hash of the request for as long as the process runs.

## What it does not do

- It keeps no file and counts no cost. The answer of the server holds its cost in `usage.cost`; a measurement that must stay under a limit counts it itself.
- It does not bind itself to a tool set, and it adds nothing to what a search shows the model: the relevance model only orders the hits.
- It has no `Llm` backend. OpenRouter also serves chat models, and one would join this package, as the wire format of one service belongs in one package.

## Tests

`test_openrouter()` runs the layering guard, the translation with a stand-in for the network — the batches, the state, a choice, the memory, the tries — and one live request, which skips itself when no key is exported.
