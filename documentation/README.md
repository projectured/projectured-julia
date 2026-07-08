# Guide Index

Three reading tracks depending on your goal.

---

## Track 1 — New here (user / evaluator)

You want to understand what ProjecturEd is, see it in action, and form a
mental model before diving into code.

1. [Concepts](concepts.md) — what projectional editing is, the five core
   ideas, and a step-by-step walkthrough of a key event.
2. [Examples tour](examples-tour.md) — guided tour of six examples with
   screenshots and what to try.
3. [Getting started](getting-started.md) — prerequisites, setup, and REPL
   helpers (`run_example`, `print_example`, `write_example_image`).
4. [Debugging](debugging.md) — driving the printer/reader by hand, forcing
   reactive cells, inspecting selection.

---

## Track 2 — Building something (contributor)

You want to add a domain, a projection, a backend, or extend an existing one.

1. [Concepts](concepts.md) — start here if you haven't already.
2. [Architecture](architecture.md) — the package chain, layer/slice structure,
   full module inventory, pipeline status. See [Terminology](terminology.md)
   for the division vocabulary (package / layer / slice / module).
3. [Reactive cells](reactive-cells.md) — `Cell`, dependency tracking, lazy
   invalidation. Everything assumes you understand this.
4. [Macros](macros.md) — `@document`, `@projection`, `@iomap` and why field
   access looks like plain Julia even though every field is a `Cell`.
5. [Projection system](projection-system.md) — the four interface functions,
   the printer/reader pair, and the projection taxonomy.
6. [Tutorial: new domain](tutorial-new-domain.md) — step-by-step: define
   document types, write a projection, implement the reader, add an example,
   write a test.
7. [Design decisions](design-decisions.md) — rationale for key choices.

Then read the guide for the domain or area you are touching:

- Higher-order projections: [higher-order projections guide](higher-order-projections.md)
- Generic projections: [generic projections guide](generic-projections.md)
- Operations: [operations guide](operations.md)
- Editor loop: [editor guide](editor.md)
- References + DSL: [reference guide](editor/reference.md)
- Selection mechanism: [selection guide](editor/selection.md) and
  [selection deep dive](selection-deep-dive.md)
- Finding / selecting nodes by content: [finding-and-selecting guide](editor/finding-and-selecting.md)
- Backends and devices: [devices and backends guide](devices-and-backends.md)
- Per-domain: [document/](document/)

---

## Track 3 — AI agent

You are an AI assistant working in this repo via MCP or a chat interface.
[CLAUDE.md](../CLAUDE.md) is the canonical entry point — it already captures
the contributor reading order and conventions tuned for non-trivial changes.
Read it first; it will point you here and to the specific guides you need.

---

## Full guide listing

### Conceptual

| Guide | Contents |
|---|---|
| [Concepts](concepts.md) | Plain-English conceptual guide — the five core ideas and a key-event walkthrough |
| [Examples tour](examples-tour.md) | Guided tour of six examples with what to try |
| [Vision](vision.md) | Long-term potential, positioning, and "compared to…" |
| [Roadmap](roadmap.md) | Near-, medium-, and long-term development priorities |

### Getting started

| Guide | Contents |
|---|---|
| [Getting started](getting-started.md) | Setup and REPL helpers |
| [Debugging](debugging.md) | REPL debugging: print_example, write_example_image, forcing cells |
| [Testing](testing.md) | test_all and per-package test helpers |
| [Tutorial: new domain](tutorial-new-domain.md) | Step-by-step: add a new domain |

### Architecture

| Guide | Contents |
|---|---|
| [Terminology](terminology.md) | The division vocabulary: package, layer, slice, module |
| [Architecture](architecture.md) | Package chain, layer/slice structure, module inventory, pipeline status |
| [Architecture rules](architecture-rules.md) | Decision rules: when to create a package, layer, slice, or module, and where code belongs |
| [Design decisions](design-decisions.md) | Rationale for key architectural choices |
| [Design overview](design.md) | ← redirects to the three split documents above |

### The projection system

| Guide | Contents |
|---|---|
| [Projection system](projection-system.md) | The four interface functions and projection taxonomy |
| [Higher-order projections](higher-order-projections.md) | Sequential, Recursive, dispatchers, Nesting, Alternative |
| [Generic projections](generic-projections.md) | Preserving, Invariably, Copying, Sorting, Reversing, Focusing |
| [Operations](operations.md) | Operations: what they are and how the reader produces them |
| [Macros](macros.md) | @document, @projection, @iomap |
| [Reactive cells](reactive-cells.md) | Cell, dependency tracking, lazy invalidation |

### Editor and runtime

| Guide | Contents |
|---|---|
| [Editor](editor.md) | REPL loop, event handling, rendering pipeline |
| [Reference guide](editor/reference.md) | Reference paths and the @reference / @reference_case DSL |
| [Selection guide](editor/selection.md) | How selection is stored and propagated |
| [Finding and selecting](editor/finding-and-selecting.md) | Search for nodes by content (`search_references` / `search_objects`), resolve paths (`evaluate_reference`), select |
| [Selection deep dive](selection-deep-dive.md) | Full reference/selection mechanism with worked examples |
| [Devices and backends](devices-and-backends.md) | Backend/Device split, the SDL, Console, and Web backends, and how to add a new one |

### Per-domain

| Guide | Domain |
|---|---|
| [JSON domain](document/json.md) | JSON |
| [XML domain](document/xml.md) | XML |
| [Text domain](document/text.md) | Text |
| [Syntax domain](document/syntax.md) | Syntax (intermediate) |
| [Graphics domain](document/graphics.md) | Graphics + write_image + write_pdf |
| [Widget domain](document/widget.md) | Widgets |
| [Workbench domain](document/workbench.md) | Workbench (IDE shell) |
| [Collection domain](document/collection.md) | CellVector and ListNode |
