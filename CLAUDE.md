# ProjecturEd

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured), a generic-purpose projectional editor. Documents are structured data (trees, ASTs, graphs) presented through bidirectional, composable projections; editing acts on the projection and is mapped back to the underlying domain.

## Before working in this repo

Read the guides in [guide/](guide/) before making non-trivial changes. They explain the architecture, the reactive cell system, and the domain/projection/editor layering that the code assumes you understand.

The canonical reading order for contributors is in [README.md](README.md) under **"Building something? Read next"**. A quick summary:

1. [guide/concepts.md](guide/concepts.md) — plain-English conceptual guide (domain, document, selection, operation, projection). **Start here if you are new.**
2. [guide/architecture.md](guide/architecture.md) — layer diagram and module inventory.
3. [guide/reactive-cells.md](guide/reactive-cells.md) — the pull-based reactive cell system that powers incrementality.
4. [guide/macros.md](guide/macros.md) — `@document`, `@projection`, `@iomap`.
5. [guide/projection-system.md](guide/projection-system.md) — the four interface functions and the printer/reader pair.
6. [guide/editor.md](guide/editor.md) — the read-eval-print loop, event handling, and rendering pipeline.

When touching selection/reference handling or a specific domain, also consult:

- [guide/editor/reference.md](guide/editor/reference.md) and [guide/editor/selection.md](guide/editor/selection.md) — how selections are represented and mapped through projections.
- [guide/selection-deep-dive.md](guide/selection-deep-dive.md) — the full reference/selection mechanism with worked examples.
- [guide/document/](guide/document/) — per-domain guides: [json.md](guide/document/json.md), [xml.md](guide/document/xml.md), [text.md](guide/document/text.md), [syntax.md](guide/document/syntax.md), [graphics.md](guide/document/graphics.md), [widget.md](guide/document/widget.md), [workbench.md](guide/document/workbench.md), [collection.md](guide/document/collection.md).

When iterating in the REPL or running the test suite:

- [guide/debugging.md](guide/debugging.md) — REPL debugging tips: `run_example`, `print_example`, `write_image_example`, driving the printer/reader by hand, and forcing reactive cells.
- [guide/testing.md](guide/testing.md) — testing tips: `test_all`, `test_printers`, `test_readers`, `test_text_navigations`, `test_repls`, and the walker helpers behind them.

## Conventions

- All indexing is 1-based (Julia convention).
- Projections must be bidirectional: every printer needs a matching reader, and the IO map is what makes the inversion possible.

## Testing a change

When you change something and want to verify it, run the **smallest test that covers the change** — do not blindly run `test_all`. It is slow and its output floods the context with tokens.

Pick the narrowest scope that exercises your change:

- A single example: `test_printer(json_example)`, `test_reader(json_example)`, `test_text_navigation(json_example)`, `test_repl(json_example)`, or `test_example(json_example)` for all three at once. Add `test_text_navigation(json_example; check_reaches_all=true)` to also assert navigation reaches every enumerated caret.
- A single domain or pipeline stage: e.g. `test_json()`, `test_syntax()`, `test_json_to_syntax()`, `test_syntax_to_text()`.
- The reactive primitive only: `test_cell()`.
- Want errors back as a `Vector{String}` instead of `@testset` output (less noise, keeps going on failure): the walker helpers `walk_printer_output(doc, proj)`, `walk_repl_loop(doc, proj)`, `explore_text_selections(doc, proj)`.

Running `test_all()` is usually not needed — the targeted test above is enough to verify a change. Only reach for the loop-over-every-example functions (`test_printers()` / `test_readers()` / `test_text_navigations()` / `test_repls()`), and rarely `test_all()`, when you specifically want a broad sweep after the targeted test already passes. See [guide/testing.md](guide/testing.md) for the full table of test functions and which layer each one covers.

Always narrow down tests to the smallest reasonable scope — never default to `test_all()`, it is slow. Prefer single-example or single-domain test functions as described in the "Testing a change" section above.
