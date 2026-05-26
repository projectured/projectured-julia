# ProjecturEd (predj)

A Julia reimplementation of [ProjecturEd](https://github.com/projectured/projectured),
a generic-purpose **projectional editor**.

Documents are structured data — trees, ASTs, graphs — not flat text. They
are presented through **bidirectional, composable projections**: a printer
projects the document forward toward a display domain, and a matching
reader projects user events backward into operations on the original
document. The same machinery edits JSON, XML, styled text, graphics,
widgets, source code, and combinations thereof.

```
        ┌─────────────┐    printer    ┌──────────────┐    printer    ┌────────────┐
        │   Document  │ ───────────▶  │  Intermediate│ ───────────▶  │  Graphics  │
        │  (domain A) │  ◀─────────── │  (domain B)  │  ◀─────────── │  / Display │
        └─────────────┘     reader    └──────────────┘     reader    └────────────┘
```

A keystroke arrives at the display, the reader chain walks back through
each projection's IO map, and the corresponding domain operation is applied
to the original document. The document re-projects forward, and the screen
updates incrementally via a pull-based reactive cell system.

## Status

Active reimplementation of the original Common Lisp project. Domains and
projections implemented so far include JSON, XML, mixed-domain documents,
text, syntax, graphics, widgets, the workbench (IDE shell), tables, books,
filesystems, lazy collections, math, and a Julia front-end — see
[example/src/](example/src/) for the catalogue.

The SDL backend is the primary frontend today; an MCP server is built in
so external agents can drive the editor over the Model Context Protocol.

## Prerequisites

- Julia 1.10+
- SDL2 and SDL_ttf (for the SDL backend)

## Quick start

```sh
git clone https://github.com/<you>/predj
cd predj
julia --project=.
```

```julia
julia> using Projectured, ProjecturedExample
julia> run_example()              # opens the default JSON example
julia> run_example("widget")      # try another domain
julia> print_example("syntax")    # dump a projection's output to stdout
```

See [guide/debugging.md](guide/debugging.md) for the full set of REPL
helpers and [guide/testing.md](guide/testing.md) for running the test
suite from the same REPL.

## Repository layout

| Path | Contents |
|---|---|
| [program/src/](program/src/) | The core `Projectured` package — API, documents, projections, references, editor, devices, backends. |
| [example/src/](example/src/) | The `ProjecturedExample` package — concrete document/projection examples and the `run_example` / `print_example` REPL helpers. |
| [example/workspace/](example/workspace/) | On-disk fixtures used by the examples (`contact-list.json`, `hello-world.html`, `lorem-ipsum.txt`). |
| [test/src/](test/src/) | The `ProjecturedTest` package — `test_all` and every per-layer helper documented in [guide/testing.md](guide/testing.md). |
| [guide/](guide/) | All architecture and topic guides — see below. |
| [executable/](executable/) | Build configuration for producing a standalone executable. |
| [font/](font/), [image/](image/) | Bundled assets. |
| [plan/](plan/) | Design notes and roadmap material. |

## Guides

All guides live under [guide/](guide/). The recommended reading order:

### Start here

1. [guide/design.md](guide/design.md) — architecture overview, design decisions, module inventory, and roadmap. **Read this first.**
2. [guide/getting-started.md](guide/getting-started.md) — core concepts (domain, document, selection, operation, projection, editor) and basic usage.

### Foundations

3. [guide/reactive-cells.md](guide/reactive-cells.md) — the pull-based reactive cell system that powers incrementality.
4. [guide/macros.md](guide/macros.md) — the `@document`, `@projection`, and `@iomap` macros that hide the cell wrapping.

### The projection system

5. [guide/projection-system.md](guide/projection-system.md) — projection taxonomy (domain-to-domain, domain-preserving, domain-independent) and the printer/reader pair.
6. [guide/higher-order-projections.md](guide/higher-order-projections.md) — `Sequential`, `Recursive`, the dispatchers, `Nesting`, `Alternative`, and `ApplyAtProjection`.
7. [guide/generic-projections.md](guide/generic-projections.md) — `Preserving`, `Invariably`, `Copying`, `Sorting`, `Reversing`, `Focusing`.
8. [guide/operations.md](guide/operations.md) — what an operation is, when to add one, and how the reader chain produces them.

### Editor and runtime

9. [guide/editor.md](guide/editor.md) — the read-eval-print loop, event handling, and rendering pipeline.
10. [guide/editor/reference.md](guide/editor/reference.md) — reference paths, the `@reference` DSL, and the `@reference_case` pattern matcher.
11. [guide/editor/selection.md](guide/editor/selection.md) — how selection is stored and propagated through nested documents.
12. [guide/devices-and-backends.md](guide/devices-and-backends.md) — the `Backend`/`Device` split and how to add a new one.

### Per-domain guides

- [guide/document/json.md](guide/document/json.md) — JSON documents and projections.
- [guide/document/xml.md](guide/document/xml.md) — XML documents and projections.
- [guide/document/text.md](guide/document/text.md) — the text domain.
- [guide/document/syntax.md](guide/document/syntax.md) — the syntax/intermediate domain.
- [guide/document/graphics.md](guide/document/graphics.md) — the graphics domain.
- [guide/document/widget.md](guide/document/widget.md) — widgets (buttons, tabbed panes, etc.).
- [guide/document/workbench.md](guide/document/workbench.md) — the workbench (IDE shell).
- [guide/document/collection.md](guide/document/collection.md) — `CellVector` and `ListNode`.

### Working in the REPL

- [guide/debugging.md](guide/debugging.md) — `run_example`, `print_example`, driving the printer/reader by hand, forcing reactive cells, and inspecting selection.
- [guide/testing.md](guide/testing.md) — `test_all`, the per-layer test functions (`test_printers`, `test_readers`, `test_selections`, `test_repls`, `test_mcp_tools`), and the walker helpers behind them.

## Conventions

- All indexing is **1-based** (Julia convention).
- Projections must be **bidirectional**: every printer needs a matching reader, and the IO map is what makes the inversion possible.

## Project context for agents

If you are an AI assistant working in this repo, also read [CLAUDE.md](CLAUDE.md);
it points at the same guides with a slightly tighter framing for non-trivial
changes.

## Licence

Dual-licensed:

- [LICENCE-PD](LICENCE-PD) — free, public-domain-style dedication for
  non-commercial use of unmodified copies only.
- [LICENCE-COMMERCIAL](LICENCE-COMMERCIAL) — required for commercial use
  or for any modification or derivative work. Contact
  levente.meszaros@gmail.com.
