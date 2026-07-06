# ProjecturEd

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured), a generic-purpose projectional editor. Documents are structured data (trees, ASTs, graphs) presented through bidirectional, composable projections; editing acts on the projection and is mapped back to the underlying domain.

## Before working in this repo

Read the guides in [documentation/](documentation/) before making non-trivial changes. They explain the architecture, the reactive cell system, and the domain/projection/editor layering that the code assumes you understand.

The canonical reading order for contributors is in [README.md](README.md) under **"Building something? Read next"**. A quick summary:

1. [documentation/concepts.md](documentation/concepts.md) — plain-English conceptual guide (domain, document, selection, operation, projection). **Start here if you are new.**
2. [documentation/architecture.md](documentation/architecture.md) — layer diagram and module inventory.
3. [documentation/reactive-cells.md](documentation/reactive-cells.md) — the pull-based reactive cell system that powers incrementality.
4. [documentation/macros.md](documentation/macros.md) — `@document`, `@projection`, `@iomap`.
5. [documentation/projection-system.md](documentation/projection-system.md) — the four interface functions and the printer/reader pair.
6. [documentation/editor.md](documentation/editor.md) — the read-eval-print loop, event handling, and rendering pipeline.

When touching selection/reference handling or a specific domain, also consult:

- [documentation/editor/reference.md](documentation/editor/reference.md) and [documentation/editor/selection.md](documentation/editor/selection.md) — how selections are represented and mapped through projections.
- [documentation/selection-deep-dive.md](documentation/selection-deep-dive.md) — the full reference/selection mechanism with worked examples.
- [documentation/document/](documentation/document/) — per-domain guides: [json.md](documentation/document/json.md), [xml.md](documentation/document/xml.md), [text.md](documentation/document/text.md), [syntax.md](documentation/document/syntax.md), [graphics.md](documentation/document/graphics.md), [widget.md](documentation/document/widget.md), [workbench.md](documentation/document/workbench.md), [collection.md](documentation/document/collection.md), [versioning.md](documentation/document/versioning.md).

When iterating in the REPL or running the test suite:

- [documentation/debugging.md](documentation/debugging.md) — REPL debugging tips: `run_example`, `print_example`, `write_example_image`, driving the printer/reader by hand, and forcing reactive cells.
- [documentation/testing.md](documentation/testing.md) — testing tips: `test_all`, `test_printers`, `test_readers`, `test_text_navigations`, `test_repls`, and the walker helpers behind them.

## Conventions

- All indexing is 1-based (Julia convention).
- Projections must be bidirectional: every printer needs a matching reader, and the IO map is what makes the inversion possible.

## Testing a change

When you change something and want to verify it, run the **smallest test that covers the change** — do not blindly run `test_all`. It is slow and its output floods the context with tokens.

Pick the narrowest scope that exercises your change:

- A single example: `test_printer(json_example)`, `test_reader(json_example)`, `test_text_navigation(json_example)`, `test_repl(json_example)`, or `test_example(json_example)` for all three at once. Add `test_text_navigation(json_example; check_reaches_all=true)` to also assert navigation reaches every enumerated caret.
- A single domain or pipeline stage: e.g. `test_json()`, `test_syntax()`, `test_json_to_syntax()`, `test_syntax_to_text()`.
- One runtime package's whole suite: `test_kernel()`, `test_base()`, `test_visual()`, `test_domain()` — each lives in its own test package (`package/kernel-test` … `package/domain-test`) that only depends on the runtime packages below it, so these also run in an environment without SDL/ODBC/Tulip installed (`julia --project=package/kernel-test`, etc.). Each includes its package's static layering guard (`test_kernel_layering()`, …).
- The reactive primitive only: `test_cell()`.
- Want errors back as a `Vector{String}` instead of `@testset` output (less noise, keeps going on failure): the walker helpers `walk_printer_output(doc, proj)`, `walk_repl_loop(doc, proj)`, `explore_text_selections(doc, proj)`.

Running `test_all()` is usually not needed — the targeted test above is enough to verify a change. Only reach for the per-package aggregators (`test_kernel()` / `test_base()` / `test_visual()` / `test_domain()`), the loop-over-every-example functions (`test_printers()` / `test_readers()` / `test_text_navigations()` / `test_repls()`), and rarely `test_all()` (which runs the four per-package suites plus the umbrella integration tests), when you specifically want a broad sweep after the targeted test already passes. See [documentation/testing.md](documentation/testing.md) for the full table of test functions and which layer each one covers.

Always narrow down tests to the smallest reasonable scope — never default to `test_all()`, it is slow. Prefer single-example or single-domain test functions as described in the "Testing a change" section above.
