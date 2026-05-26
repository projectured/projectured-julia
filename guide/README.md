# Guide Index

Three reading tracks depending on your goal.

---

## Track 1 — New here (user / evaluator)

You want to understand what ProjecturEd is, see it in action, and form a
mental model before diving into code.

1. [concepts.md](concepts.md) — what projectional editing is, the five core
   ideas, and a step-by-step walkthrough of a key event.
2. [examples-tour.md](examples-tour.md) — guided tour of six examples with
   screenshots and what to try.
3. [getting-started.md](getting-started.md) — prerequisites, setup, and REPL
   helpers (`run_example`, `print_example`, `write_image_example`).
4. [debugging.md](debugging.md) — driving the printer/reader by hand, forcing
   reactive cells, inspecting selection.

---

## Track 2 — Building something (contributor)

You want to add a domain, a projection, a backend, or extend an existing one.

1. [concepts.md](concepts.md) — start here if you haven't already.
2. [architecture.md](architecture.md) — layer diagram, full module inventory,
   pipeline status.
3. [reactive-cells.md](reactive-cells.md) — `Cell`, dependency tracking, lazy
   invalidation. Everything assumes you understand this.
4. [macros.md](macros.md) — `@document`, `@projection`, `@iomap` and why field
   access looks like plain Julia even though every field is a `Cell`.
5. [projection-system.md](projection-system.md) — the four interface functions,
   the printer/reader pair, and the projection taxonomy.
6. [tutorial-new-domain.md](tutorial-new-domain.md) — step-by-step: define
   document types, write a projection, implement the reader, add an example,
   write a test.
7. [design-decisions.md](design-decisions.md) — rationale for key choices.

Then read the guide for the domain or subsystem you are touching:

- Higher-order projections: [higher-order-projections.md](higher-order-projections.md)
- Generic projections: [generic-projections.md](generic-projections.md)
- Operations: [operations.md](operations.md)
- Editor loop: [editor.md](editor.md)
- References + DSL: [editor/reference.md](editor/reference.md)
- Selection mechanism: [editor/selection.md](editor/selection.md) and
  [selection-deep-dive.md](selection-deep-dive.md)
- Backends and devices: [devices-and-backends.md](devices-and-backends.md)
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

| File | Contents |
|---|---|
| [concepts.md](concepts.md) | Plain-English conceptual guide — the five core ideas and a key-event walkthrough |
| [examples-tour.md](examples-tour.md) | Guided tour of six examples with what to try |
| [vision.md](vision.md) | Long-term potential, positioning, and "compared to…" |
| [roadmap.md](roadmap.md) | Near-, medium-, and long-term development priorities |

### Getting started

| File | Contents |
|---|---|
| [getting-started.md](getting-started.md) | Setup and REPL helpers |
| [debugging.md](debugging.md) | REPL debugging: print_example, write_image_example, forcing cells |
| [testing.md](testing.md) | test_all and per-layer test helpers |
| [tutorial-new-domain.md](tutorial-new-domain.md) | Step-by-step: add a new domain |

### Architecture

| File | Contents |
|---|---|
| [architecture.md](architecture.md) | Layer diagram, module inventory, pipeline status |
| [design-decisions.md](design-decisions.md) | Rationale for key architectural choices |
| [design.md](design.md) | ← redirects to the three split documents above |

### The projection system

| File | Contents |
|---|---|
| [projection-system.md](projection-system.md) | The four interface functions and projection taxonomy |
| [higher-order-projections.md](higher-order-projections.md) | Sequential, Recursive, dispatchers, Nesting, Alternative |
| [generic-projections.md](generic-projections.md) | Preserving, Invariably, Copying, Sorting, Reversing, Focusing |
| [operations.md](operations.md) | Operations: what they are and how the reader produces them |
| [macros.md](macros.md) | @document, @projection, @iomap |
| [reactive-cells.md](reactive-cells.md) | Cell, dependency tracking, lazy invalidation |

### Editor and runtime

| File | Contents |
|---|---|
| [editor.md](editor.md) | REPL loop, event handling, rendering pipeline |
| [editor/reference.md](editor/reference.md) | Reference paths and the @reference / @reference_case DSL |
| [editor/selection.md](editor/selection.md) | How selection is stored and propagated |
| [selection-deep-dive.md](selection-deep-dive.md) | Full reference/selection mechanism with worked examples |
| [devices-and-backends.md](devices-and-backends.md) | Backend/Device split and how to add a new one |

### Per-domain

| File | Domain |
|---|---|
| [document/json.md](document/json.md) | JSON |
| [document/xml.md](document/xml.md) | XML |
| [document/text.md](document/text.md) | Text |
| [document/syntax.md](document/syntax.md) | Syntax (intermediate) |
| [document/graphics.md](document/graphics.md) | Graphics + write_image |
| [document/widget.md](document/widget.md) | Widgets |
| [document/workbench.md](document/workbench.md) | Workbench (IDE shell) |
| [document/collection.md](document/collection.md) | CellVector and ListNode |
