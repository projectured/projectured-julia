# Guide Index

Three reading tracks depending on your goal.

Guides come in two kinds. **Cross-cutting guides** — concepts, the whole-system
architecture, onboarding, and the repo-wide tooling — live here in
`documentation/`. **Per-package reference guides** live next to the code they
document, in each package's `doc/` directory
([kernel](package/kernel/), one per substrate package such as
[widget](package/widget/), and one per domain such as
[json](package/json/)). The AI
agent sees both sets through `list_guides` / `read_guide`.

---

## Track 1 — New here (user / evaluator)

You want to understand what ProjecturEd is, see it in action, and form a
mental model before diving into code.

1. [Introduction](introduction.md) — the engineer's introduction: every concept
   with its real code, how the concepts combine, and how to extrapolate what the
   system can do.
2. [Concepts](concepts.md) — what projectional editing is, the five core
   ideas, and a step-by-step walkthrough of a key event.
3. [Examples tour](examples-tour.md) — guided tour of six examples with
   screenshots and what to try.
4. [Getting started](getting-started.md) — prerequisites, setup, and REPL
   helpers (`run_example`, `print_example`, `write_example_image`).
5. [Debugging](debugging.md) — driving the printer/reader by hand, forcing
   reactive cells, inspecting selection.

---

## Track 2 — Building something (contributor)

You want to add a domain, a projection, a backend, or extend an existing one.

1. [Introduction](introduction.md) then [Concepts](concepts.md) — start here if
   you haven't already.
2. [Architecture](architecture.md) — the package chain, layer/slice structure,
   full module inventory, pipeline status. See [Terminology](terminology.md)
   for the division vocabulary (package / layer / slice / module).
3. [Reactive cells](package/kernel/cell.md) — the three cell kinds
   (`ReactiveCell` / `MutableCell` / `ImmutableCell`), dependency tracking, and
   the eager-invalidate / lazy-recompute rule. Everything assumes you understand
   this.
4. [Macros](package/kernel/macros.md) — `@document`, `@projection`,
   `@iomap` and why field access looks like plain Julia even though every field
   is a `Cell`.
5. [Projection system](package/kernel/projection-system.md) — the four
   interface functions, the printer/reader pair, and the projection taxonomy.
6. [Tutorial: new domain](tutorial-new-domain.md) — step-by-step: define
   document types, write a projection, implement the reader, add an example,
   write a test.
7. [Design decisions](design-decisions.md) — rationale for key choices.
8. [Architecture requirements](architecture-requirements.md) — the internal
   development requirements (`PAR-PURE-THUNK`, `PAR-PER-EDITOR-STATE`, …) every
   change must respect; keep this open as a checklist while you work.
9. [Naming](package/kernel/naming.md) then
   [Code quality](code-quality.md) — how a name is derived, and the shape the
   code around it takes: file layout, comments, public surface, size budgets.

Then read the guide for the domain or area you are touching:

- Higher-order projections: [higher-order projections guide](package/kernel/higher-order-projections.md)
- Generic projections: [generic projections guide](package/kernel/generic-projections.md)
- Operations: [operations guide](package/kernel/operation.md)
- Editor loop: [editor guide](package/kernel/editor.md)
- References + DSL: [reference guide](package/kernel/reference.md)
- Selection mechanism: [selection guide](package/kernel/selection.md)
- Finding / selecting nodes by content: [finding-and-selecting guide](package/kernel/finding-and-selecting.md)
- Backends and devices: [devices and backends guide](package/kernel/devices-and-backends.md)
- Per-package: each package's own `doc/`, for example [widget/doc/](package/widget/) and [collection/doc/](package/collection/) — see [domains.md](domains.md)

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
| [Introduction](introduction.md) | The engineer's introduction — every concept with its code, how they combine, what the combinations make possible |
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
| [Static compilation](static-compilation.md) | juliac `--trim`: why an abstract type blocks it, and four ways to keep the abstract type |
| [Tutorial: new domain](tutorial-new-domain.md) | Step-by-step: add a new domain |
| [Orientation](orientation.md) | Concept→symbol search index for navigating the code |

### Architecture (top level)

| Guide | Contents |
|---|---|
| [Terminology](terminology.md) | The division vocabulary: package, layer, slice, module |
| [Architecture](architecture.md) | Package chain, layer/slice structure, module inventory, pipeline status |
| [Architecture rules](architecture-rules.md) | Decision rules: when to create a package, layer, slice, or module, and where code belongs |
| [Architecture requirements](architecture-requirements.md) | Internal development requirements (`PAR-…`): the invariants and conventions every change must respect |
| [Design decisions](design-decisions.md) | Rationale for key architectural choices |
| [Requirements](requirements.md) | Implementation-independent behavior/capability spec |
| [Code quality](code-quality.md) | File shape, comments, public surface, redundancy, size budgets, and the measured baseline |

The kernel documents its own internal structure in
[its `doc/architecture.md`](package/kernel/architecture.md); it is the
one layered package. Every other package is one concept, and the graph they
form is in [architecture.md](architecture.md) and [domains.md](domains.md).

### The projection system (kernel)

| Guide | Contents |
|---|---|
| [Projection system](package/kernel/projection-system.md) | The four interface functions, the recursion contract, and the projection taxonomy |
| [Higher-order projections](package/kernel/higher-order-projections.md) | Chaining, Recursive, the dispatchers, Nesting, Switching |
| [Generic projections](package/kernel/generic-projections.md) | Identity, Copying, Sorting, Reversing, Filtering, Focusing, … |
| [Operations](package/kernel/operation.md) | Operations: what they are and how the reader produces them |
| [Macros](package/kernel/macros.md) | @document, @projection, @iomap |
| [Reactive cells](package/kernel/cell.md) | The three cell kinds, dependency tracking, eager invalidation and lazy recompute |

### Editor and runtime (kernel)

| Guide | Contents |
|---|---|
| [Editor](package/kernel/editor.md) | REPL loop, event handling, rendering pipeline |
| [Reference guide](package/kernel/reference.md) | Reference paths and the @reference / @reference_case DSL |
| [Selection guide](package/kernel/selection.md) | How selection is stored and propagated, incl. the recursion algorithm |
| [Finding and selecting](package/kernel/finding-and-selecting.md) | Search for nodes by content (`search_references` / `search_documents`), resolve paths (`evaluate_reference`), select |
| [Devices and backends](package/kernel/devices-and-backends.md) | Backend/Device split, the SDL, Console, and Web backends, and how to add a new one |

### Per-domain (in the owning package)

| Guide | Domain | Package |
|---|---|---|
| [JSON domain](package/json/json.md) | JSON | domain |
| [XML domain](package/xml/xml.md) | XML | domain |
| [Workbench domain](package/workbench/workbench.md) | Workbench (IDE shell) | domain |
| [Versioning domain](package/versioning/versioning.md) | Versioning overlay | substrate |
| [Text domain](package/text/text.md) | Text | substrate |
| [Syntax domain](package/syntax/syntax.md) | Syntax (intermediate) | substrate |
| [Graphics domain](package/graphics/graphics.md) | Graphics + write_image + write_pdf | substrate |
| [Widget domain](package/widget/widget.md) | Widgets | substrate |
| [Collection domain](package/collection/collection.md) | CellVector and ListNode | substrate |
| [Bounded sync](package/reflection/bounded-sync.md) | shadowing something too big to walk whole | substrate |
