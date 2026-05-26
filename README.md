# ProjecturEd (predj)

> **What if your editor understood the *structure* of what you're editing?**

Most editors store your work as a flat sequence of characters. ProjecturEd
stores it as **structured data** — a tree, a graph, a typed AST — and presents
it to you through *bidirectional projections* that translate between domains.
The projection renders your data as something you can read and edit; the reverse
projection maps your keystrokes back into precise structural operations on the
original data.

This means:
- Edit a JSON object and the tree updates; switch the projection and see the
  same data rendered as a widget form, a table, or source code.
- Cursor movement, text insertion, and structural edits all operate on the
  *model*, not on a string serialisation of it.
- The same framework handles JSON, XML, source code, styled documents,
  mathematical notation, and graphics — because the projection is just a
  function between domains.

```
        ┌─────────────┐    printer    ┌──────────────┐    printer    ┌────────────┐
        │   Document  │ ───────────▶  │  Intermediate│ ───────────▶  │  Graphics  │
        │  (domain A) │  ◀─────────── │  (domain B)  │  ◀─────────── │  / Display │
        └─────────────┘     reader    └──────────────┘     reader    └────────────┘
```

A keystroke arrives at the display; the reader chain walks back through each
projection's IO map, and the corresponding domain operation is applied to the
original document. The document re-projects forward, and the screen updates
incrementally via a pull-based reactive cell system.

## Screenshots

Screenshots are generated with `write_image_example` and stored in
[image/](image/) as BMP files (clone the repo to view them).

| JSON editor | Widget forms |
|---|---|
| [image/json-example.bmp](image/json-example.bmp) | [image/widget-example.bmp](image/widget-example.bmp) |

| Table view | Julia AST |
|---|---|
| [image/table-example.bmp](image/table-example.bmp) | [image/julia-example.bmp](image/julia-example.bmp) |

## What can it do today?

| Domain | What it demonstrates |
|---|---|
| **JSON** | Full object/array/primitive tree editing with cursor and selection |
| **XML** | Element/attribute tree, mixed with HTML-style namespaces |
| **Text** | Styled multi-span text with word wrapping and line numbering |
| **Syntax** | Generic S-expression intermediate; the glue between semantic domains and text |
| **Graphics** | SDL2 render primitives; foundation for everything you see |
| **Widget** | Labels, buttons, checkboxes, tabbed panes, scroll panes, split panes, toolbars |
| **Workbench** | Full IDE shell: navigator, console, descriptor, operator, evaluator, assistant |
| **Table** | 2-D spreadsheet-style grid rendered directly to graphics |
| **Book** | Structured prose: chapters, paragraphs, lists, embedded pictures |
| **Math** | Algebraic expression trees (variable, binary op, parenthesised, assignment) |
| **Julia** | Julia AST subset: identifier, integer, binary op, call, if, function, block |
| **FileSystem** | Directory/file tree |
| **Collection** | `CellVector` (reactive indexed vector) and `ListNode` (lazy doubly-linked list) |

All domains support **selection** and **cursor movement** end-to-end. Character
editing is the next milestone (see [Roadmap](guide/roadmap.md)).

The SDL backend is the primary frontend today. An **MCP server** is built in so
external AI agents can drive the editor over the Model Context Protocol.

## Vision

ProjecturEd is not just a better JSON editor — it is an architecture for
**universal structured editing**:

- **Any domain in ~100 lines.** Define your document types, write a
  projection to the syntax domain, and you have a fully-navigable, fully-editable
  view of your data.
- **AI-native editing.** The MCP bridge lets language-model agents read the live
  document structure, build precise reference paths, and apply structural
  operations — no string parsing, no hallucinated line numbers.
- **Multiple backends.** The projection pipeline is backend-agnostic. A terminal
  backend, a web backend, and an IDE-plugin backend all receive the same
  `GraphicsCanvas`; only the renderer changes.
- **Mixed-domain documents.** Because projections are composable, a single document
  can contain JSON inside XML inside a styled prose wrapper — and every cursor
  position is faithfully represented and round-tripped.
- **Live collaboration.** Structural operations on a well-defined model are the
  natural substrate for operational-transform or CRDT-based collaboration.

See [guide/vision.md](guide/vision.md) for the full vision and a "Compared
to…" positioning relative to MPS, Lamdu, Hazel, Tree-sitter, and text editors.

## Prerequisites

- Julia 1.10+
- SDL2 and SDL_ttf (for the SDL backend)

## Quick start

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
julia --project=.
```

```julia
julia> using Projectured, ProjecturedExample
julia> run_example()                  # opens the JSON example
julia> run_example("widget")          # widget form example
julia> run_example("table")           # table view
julia> run_example("julia")           # Julia AST editor
julia> print_example("syntax")        # dump a projection's output to stdout
julia> write_image_example("json", "/tmp/snapshot.bmp")   # save to file
```

See [guide/debugging.md](guide/debugging.md) for the full REPL helper
catalogue and [guide/testing.md](guide/testing.md) for running the test suite.

## Repository layout

| Path | Contents |
|---|---|
| [program/src/](program/src/) | Core `Projectured` package — API, documents, projections, references, editor, devices, backends |
| [example/src/](example/src/) | `ProjecturedExample` package — concrete examples and `run_example` / `print_example` / `write_image_example` helpers |
| [example/workspace/](example/workspace/) | On-disk fixtures used by examples |
| [test/src/](test/src/) | `ProjecturedTest` package — `test_all` and every per-layer helper |
| [guide/](guide/) | All architecture and topic guides — see [guide/README.md](guide/README.md) for the reading-order index |
| [executable/](executable/) | Build configuration for a standalone executable |
| [font/](font/), [image/](image/) | Bundled assets and screenshots |
| [plan/](plan/) | Design notes and work-in-progress plans |

## Guides

Three reading tracks — pick the one that matches your goal.

### New here? Start with

1. [guide/concepts.md](guide/concepts.md) — plain-English introduction: what projectional editing is, the five core ideas, and a step-by-step walkthrough of what happens when you press a key.
2. [guide/examples-tour.md](guide/examples-tour.md) — guided tour of six examples, from simplest to most complex; what to try and what each one demonstrates.
3. [guide/getting-started.md](guide/getting-started.md) — prerequisites, setup, and the REPL helpers.

### Building something? Read next

4. [guide/architecture.md](guide/architecture.md) — layer diagram, module inventory, and the projection pipeline.
5. [guide/reactive-cells.md](guide/reactive-cells.md) — the `Cell` system that powers incrementality.
6. [guide/macros.md](guide/macros.md) — `@document`, `@projection`, `@iomap` macros.
7. [guide/projection-system.md](guide/projection-system.md) — the four projection interface functions and the printer/reader pair.
8. [guide/tutorial-new-domain.md](guide/tutorial-new-domain.md) — step-by-step: add a new domain from scratch.

### Going deeper

- [guide/higher-order-projections.md](guide/higher-order-projections.md) — `Sequential`, `Recursive`, the dispatchers, `Nesting`, `Alternative`.
- [guide/generic-projections.md](guide/generic-projections.md) — `Preserving`, `Invariably`, `Copying`, `Sorting`, `Reversing`, `Focusing`.
- [guide/operations.md](guide/operations.md) — what an operation is and how the reader chain produces them.
- [guide/editor.md](guide/editor.md) — the REPL loop, event handling, and rendering pipeline.
- [guide/editor/reference.md](guide/editor/reference.md) — reference paths and the `@reference` / `@reference_case` DSL.
- [guide/editor/selection.md](guide/editor/selection.md) — how selection propagates through nested documents.
- [guide/devices-and-backends.md](guide/devices-and-backends.md) — the `Backend`/`Device` split.
- [guide/design-decisions.md](guide/design-decisions.md) — why pull-based reactivity, every-field-is-a-cell, shared selection, `ProjectionReference`.
- [guide/selection-deep-dive.md](guide/selection-deep-dive.md) — the full reference/selection mechanism with worked examples.

### Per-domain guides

[json](guide/document/json.md) · [xml](guide/document/xml.md) · [text](guide/document/text.md) · [syntax](guide/document/syntax.md) · [graphics](guide/document/graphics.md) · [widget](guide/document/widget.md) · [workbench](guide/document/workbench.md) · [collection](guide/document/collection.md)

### Working in the REPL

- [guide/debugging.md](guide/debugging.md) — `run_example`, `print_example`, `write_image_example`, driving the printer/reader by hand, forcing reactive cells.
- [guide/testing.md](guide/testing.md) — `test_all`, per-layer helpers, walker utilities.

## Roadmap

See [guide/roadmap.md](guide/roadmap.md) for near-, medium-, and long-term plans.
The three next priorities: character editing, mouse click-to-select, and undo/redo.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for repo conventions, the PR process,
code style, and how to add a new domain.

## Conventions

- All indexing is **1-based** (Julia convention).
- Projections must be **bidirectional**: every printer needs a matching reader.

## Project context for agents

If you are an AI assistant working in this repo, also read [CLAUDE.md](CLAUDE.md);
it points at the same guides with a framing tuned for non-trivial changes.

## Licence

Dual-licensed:

- [LICENCE-PD](LICENCE-PD) — free, public-domain-style dedication for
  non-commercial use of unmodified copies only.
- [LICENCE-COMMERCIAL](LICENCE-COMMERCIAL) — required for commercial use
  or for any modification or derivative work. Contact
  levente.meszaros@gmail.com.
