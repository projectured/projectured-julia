# ProjecturEd (predj)

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured), a generic-purpose projectional editor. Documents are structured data (trees, ASTs, graphs) presented through bidirectional, composable projections; editing acts on the projection and is mapped back to the underlying domain.

## Before working in this repo

Read the guides in [guide/](guide/) before making non-trivial changes. They explain the architecture, the reactive cell system, and the domain/projection/editor layering that the code assumes you understand. Start with:

1. [guide/design.md](guide/design.md) — architecture overview, design decisions, module inventory, and roadmap. **Read this first.**
2. [guide/getting-started.md](guide/getting-started.md) — core concepts (domain, document, selection, operation, projection, editor) and basic usage.
3. [guide/projection-system.md](guide/projection-system.md) — projection taxonomy (domain-to-domain, domain-preserving, domain-independent) and the printer/reader pair.
4. [guide/reactive-cells.md](guide/reactive-cells.md) — the pull-based reactive cell system that powers incrementality.
5. [guide/editor.md](guide/editor.md) — the read-eval-print loop, event handling, and rendering pipeline.

When touching selection/reference handling or a specific domain, also consult:

- [guide/editor/reference.md](guide/editor/reference.md) and [guide/editor/selection.md](guide/editor/selection.md) — how selections are represented and mapped through projections.
- [guide/document/](guide/document/) — per-domain guides: [json.md](guide/document/json.md), [xml.md](guide/document/xml.md), [text.md](guide/document/text.md), [syntax.md](guide/document/syntax.md), [graphics.md](guide/document/graphics.md).

When iterating in the REPL or running the test suite:

- [guide/debugging.md](guide/debugging.md) — REPL debugging tips: `run_example`, `print_example`, driving the printer/reader by hand, and forcing reactive cells.
- [guide/testing.md](guide/testing.md) — testing tips: `test_all`, `test_printers`, `test_readers`, `test_selections`, `test_repls`, and the walker helpers behind them.

## Conventions

- All indexing is 1-based (Julia convention).
- Projections must be bidirectional: every printer needs a matching reader, and the IO map is what makes the inversion possible.
