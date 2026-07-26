# Guide Index

Three reading tracks depending on your goal.

Guides come in two kinds. **Cross-cutting guides** — concepts, the whole-system
architecture, onboarding, and the repo-wide tooling — live here in
`documentation/`. **Per-package reference guides** live next to the code they
document, in each package's `doc/` directory
([kernel](../package/kernel/doc/), [base](../package/base/doc/),
[visual](../package/visual/doc/), [domain](../package/domain/doc/)). The AI
agent sees both sets through `list_guides` / `read_guide`.

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
3. [Reactive cells](../package/kernel/doc/cell.md) — `Cell`, dependency
   tracking, lazy invalidation. Everything assumes you understand this.
4. [Macros](../package/kernel/doc/macros.md) — `@document`, `@projection`,
   `@iomap` and why field access looks like plain Julia even though every field
   is a `Cell`.
5. [Projection system](../package/kernel/doc/projection-system.md) — the four
   interface functions, the printer/reader pair, and the projection taxonomy.
6. [Tutorial: new domain](tutorial-new-domain.md) — step-by-step: define
   document types, write a projection, implement the reader, add an example,
   write a test.
7. [Design decisions](design-decisions.md) — rationale for key choices.
8. [Architecture requirements](architecture-requirements.md) — the internal
   development requirements (`AR-PURE-THUNK`, `AR-PER-EDITOR-STATE`, …) every
   change must respect; keep this open as a checklist while you work.

Then read the guide for the domain or area you are touching:

- Higher-order projections: [higher-order projections guide](../package/kernel/doc/higher-order-projections.md)
- Generic projections: [generic projections guide](../package/kernel/doc/generic-projections.md)
- Operations: [operations guide](../package/kernel/doc/operation.md)
- Editor loop: [editor guide](../package/kernel/doc/editor.md)
- References + DSL: [reference guide](../package/kernel/doc/reference.md)
- Selection mechanism: [selection guide](../package/kernel/doc/selection.md)
- Finding / selecting nodes by content: [finding-and-selecting guide](../package/kernel/doc/finding-and-selecting.md)
- Backends and devices: [devices and backends guide](../package/kernel/doc/devices-and-backends.md)
- Per-domain: [visual/doc/](../package/visual/doc/), [domain/doc/](../package/domain/doc/), [base/doc/](../package/base/doc/)

---

## Track 3 — AI agent

You are an AI assistant working in this repo via MCP or a chat interface.
[CLAUDE.md](../CLAUDE.md) is the canonical entry point — it already captures
the contributor reading order and conventions tuned for non-trivial changes.
Read it first; it will point you here and to the specific guides you need.

---

## Full guide listing

### Conceptual (top level)

| Guide | Contents |
|---|---|
| [Concepts](concepts.md) | Plain-English conceptual guide — the five core ideas and a key-event walkthrough |
| [Examples tour](examples-tour.md) | Guided tour of six examples with what to try |
| [Vision](vision.md) | Long-term potential, positioning, and "compared to…" |
| [Roadmap](roadmap.md) | Near-, medium-, and long-term development priorities |

### Getting started (top level)

| Guide | Contents |
|---|---|
| [Getting started](getting-started.md) | Setup and REPL helpers |
| [Debugging](debugging.md) | REPL debugging: print_example, write_example_image, forcing cells |
| [Testing](testing.md) | test_all and per-package test helpers |
| [Tutorial: new domain](tutorial-new-domain.md) | Step-by-step: add a new domain |
| [Orientation](orientation.md) | Concept→symbol search index for navigating the code |

### Architecture (top level)

| Guide | Contents |
|---|---|
| [Terminology](terminology.md) | The division vocabulary: package, layer, slice, module |
| [Architecture](architecture.md) | Package chain, layer/slice structure, module inventory, pipeline status |
| [Architecture rules](architecture-rules.md) | Decision rules: when to create a package, layer, slice, or module, and where code belongs |
| [Architecture requirements](architecture-requirements.md) | Internal development requirements (`AR-…`): the invariants and conventions every change must respect |
| [Design decisions](design-decisions.md) | Rationale for key architectural choices |
| [Requirements](requirements.md) | Implementation-independent behavior/capability spec |

Each package also documents its own internal structure in its `doc/architecture.md`:
[kernel](../package/kernel/doc/architecture.md) ·
[base](../package/base/doc/architecture.md) ·
[visual](../package/visual/doc/architecture.md) ·
[domain](../package/domain/doc/architecture.md).

### The projection system (kernel)

| Guide | Contents |
|---|---|
| [Projection system](../package/kernel/doc/projection-system.md) | The four interface functions, the recursion contract, and the projection taxonomy |
| [Higher-order projections](../package/kernel/doc/higher-order-projections.md) | Chaining, Recursive, the dispatchers, Nesting, Switching |
| [Generic projections](../package/kernel/doc/generic-projections.md) | Identity, Copying, Sorting, Reversing, Filtering, Focusing, … |
| [Operations](../package/kernel/doc/operation.md) | Operations: what they are and how the reader produces them |
| [Macros](../package/kernel/doc/macros.md) | @document, @projection, @iomap |
| [Reactive cells](../package/kernel/doc/cell.md) | Cell, dependency tracking, lazy invalidation |

### Editor and runtime (kernel)

| Guide | Contents |
|---|---|
| [Editor](../package/kernel/doc/editor.md) | REPL loop, event handling, rendering pipeline |
| [Reference guide](../package/kernel/doc/reference.md) | Reference paths and the @reference / @reference_case DSL |
| [Selection guide](../package/kernel/doc/selection.md) | How selection is stored and propagated, incl. the recursion algorithm |
| [Finding and selecting](../package/kernel/doc/finding-and-selecting.md) | Search for nodes by content (`search_references` / `search_documents`), resolve paths (`evaluate_reference`), select |
| [Devices and backends](../package/kernel/doc/devices-and-backends.md) | Backend/Device split, the SDL, Console, and Web backends, and how to add a new one |

### Per-domain (in the owning package)

| Guide | Domain | Package |
|---|---|---|
| [JSON domain](../package/domain/doc/json.md) | JSON | domain |
| [XML domain](../package/domain/doc/xml.md) | XML | domain |
| [Workbench domain](../package/domain/doc/workbench.md) | Workbench (IDE shell) | domain |
| [Versioning domain](../package/domain/doc/versioning.md) | Versioning overlay | domain |
| [Text domain](../package/visual/doc/text.md) | Text | visual |
| [Syntax domain](../package/visual/doc/syntax.md) | Syntax (intermediate) | visual |
| [Graphics domain](../package/visual/doc/graphics.md) | Graphics + write_image + write_pdf | visual |
| [Widget domain](../package/visual/doc/widget.md) | Widgets | visual |
| [Collection domain](../package/base/doc/collection.md) | CellVector and ListNode | base |
| [Bounded sync](../package/base/doc/bounded-sync.md) | shadowing something too big to walk whole | base |
