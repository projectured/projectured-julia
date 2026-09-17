# ProjecturEd

A projectional editor, reimplemented in Julia from
[the original ProjecturEd](https://github.com/projectured/projectured). A
document is structured data — a tree, an AST, a graph. A projection renders it,
and an edit on the projection is mapped back to the data.

<img width="1595" alt="ProjecturEd workbench" src="asset/image/example/workbench.png">

## What the design is for

**Editing through an AI.** The built-in AI conversation reads and changes both
the document and the projection by running Julia against the live editor. You
describe a change and it is applied as a structural operation, rather than as a
sequence of keystrokes. The conversation is itself a ProjecturEd document, so
the editor edits its own AI session with the machinery it uses for everything
else.

**Composition.** A document is built by nesting primitives, reactive
collections and other documents; any field can hold another domain. A
projection is a function over documents, and projections compose. One document
can be shown several ways, and one view can mix domains. That is how a single
mechanism covers JSON, XML, source code, prose, tables and graphics.

**Lazy, incremental update.** A pull-based reactive cell system recomputes only
what a change affects, and a projection is evaluated only where the screen
pulls on it. A part of a document that nobody looks at costs nothing, so a very
large document is an ordinary case. With a lazy structure such as `ListNode`,
whose neighbours are re-projected on demand, an unbounded one is too: you
project a finite slice of an infinite list and edit it without building the
rest.

---

## AI-assisted editing

Open the assistant, type a request, and press **Enter**. Claude reads the live
document structure, looks up the types and functions involved, writes Julia, and
runs it against the editor — `editor.document` and `editor.projection` are both
bound in scope. To run code yourself, press **Alt+Enter** to evaluate a Julia
fragment directly. Either way the run is recorded in the conversation as a
re-readable code execution.

The conversation is a ProjecturEd domain
([ConversationDocument.jl](source/conversation/ConversationDocument.jl)):
messages, streaming response blocks and code executions are all structured
documents, projected and selectable like everything else.

The parts:

- The AI's core tool, `execute_julia_code`, evaluates Julia in-process with
  `Projectured` preloaded and `editor` bound — its handler lives in
  [CodeExecution.jl](source/kernel/tool/CodeExecution.jl).
- Before writing code, the AI reads the editor's own guides, modules, classes,
  and functions, exposed as resources, so it works from real signatures
  ([Documentation.jl](source/kernel/tool/Documentation.jl)).
- The in-editor assistant and an external **MCP server** (`127.0.0.1:9876/mcp`)
  share the editor's one tool set
  ([ToolSet.jl](source/kernel/tool/ToolSet.jl)), so an external MCP
  client can drive the editor too.
- The assistant uses Claude when `ANTHROPIC_API_KEY` is set, and a
  deterministic offline backend otherwise, so the example runs without a key
  and without a network connection. The default model is named in
  [Anthropic.jl](source/anthropic/Anthropic.jl); an Ollama backend is in
  [Ollama.jl](source/ollama/Ollama.jl).

> **Status.** The assistant and the MCP bridge work end to end, and both are
> new. Selection and cursor movement work in every domain. Character type-in
> and range editing work in the field-addressed domains; making them uniform
> across every domain is the current work. See the
> [roadmap](documentation/requirement/delivery-roadmap.md).

---

## How a keystroke round-trips

Most editors store the work as a flat sequence of characters. ProjecturEd
stores it as **structured data** — a tree, a graph, a typed AST — and shows it
through *bidirectional projections* that translate between domains. The printer
renders the data as something you can read and edit. The reader maps each edit
back into structural operations on the original data.

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

An edit is an operation on the model, never a change to a text buffer. That
holds for a keystroke and for an edit the AI issues.

---

## Every field is a cell

The cell is what makes the update incremental. The mechanism shapes every
document type you write, so it comes first.

`@document` stores each field in a **cell** and generates the accessors, so the
reactivity stays invisible in ordinary code:

```julia
@document struct JsonString <: JsonDocument
    value::String
end

s = JsonString("Alice")
s.value               # reads through the cell
s.value = "Bob"       # writes through the cell — and invalidates whoever read it
getfield(s, :value)   # the escape hatch: the raw cell itself
```

### Three kinds of cell

A field declares **which kind** of cell holds it. The kind decides what the field
costs and what it can do.

| Kind | Behaviour | Declare it for |
|---|---|---|
| `ReactiveCell` *(default)* | records every cell that reads it; a write invalidates all of them | editable content — the document data itself |
| `MutableCell` | a plain box: a write costs nothing and tells nobody | high-frequency state that no view derives from |
| `ImmutableCell` | read-only: a write is a `MethodError` | style and configuration values that never change |

Name the cell type on one field, or lead the struct with a kind to set the
default for every field:

```julia
@projection struct JsonStringToSyntaxLeaf
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@document ImmutableCell [DC] struct StyleText   # a value document: no field is reactive
    font::StyleFont
    color::StyleColor
    selection::Nothing
end
```

The marker before `struct` sets the kind of every field. The list after it says
what the bare name means: `[DC]` makes `StyleText` the concrete default
spelling, which is what lets a `StyleText`-typed field inline.

Each type also gets spelling aliases: `RCFoo`, `MCFoo` and `ICFoo` put every
field in one kind, and `DCFoo` names the default combination the bare
constructor builds. `copy_document(doc)` copies a tree and keeps each cell's
kind;
`copy_document(K, doc)` rebuilds the whole tree in kind `K`. That conversion is
what makes the double-buffer pattern possible: edit a `MutableCell` document at
full speed with no reactive overhead, then `sync_document!` it into a
`ReactiveCell` shadow, which writes only the cells whose value really changed.

### Where the laziness comes from

A cell holds a value or a thunk. While a thunk runs, every cell it reads becomes
an upstream dependency — you declare nothing, because the read *is* the
declaration. One rule then does the rest:

> **A write invalidates eagerly. A read recomputes lazily.**

```julia
a = Cell(1)
b = ComputedCell(() -> a[] + 1)   # a thunk — nothing runs yet
b[]                               # 2  — the thunk runs, and its read of a records the edge
a[] = 10                          # marks b invalid; b's thunk does NOT run
b[]                               # 11 — the thunk runs now, because you asked for it
```

The same rule scales from two cells to a whole projection pipeline, and it
gives two properties:

- **Consistency.** Every view is exactly what the current model projects to.
  There is no cache to invalidate by hand and no derived state that can drift.
- **Cost follows attention.** One edited character invalidates a path of cells
  and recomputes only the ones the screen pulls on. A subtree that is
  off-screen, collapsed, or past the end of a lazy `ListNode` costs nothing.

A deep pipeline is therefore affordable, which is what lets a projection stay
small and pure.

See the [reactive cells](documentation/package/kernel/cell.md) guide for the engine and its
invariants, and the [macros](documentation/package/kernel/macros.md) guide for the codegen
behind `@document`, `@projection`, and `@iomap`.

---

## Composable data, composable projections

Both layers compose, and they meet in the middle.

**Documents compose.** A document is built by nesting primitives, reactive
collections (`CellVector`, `ListNode`), and other documents; any field can hold
another domain. A `Workbench` holds pages that hold panels; a `Book` holds
chapters that hold paragraphs, lists, and embedded pictures; a `Conversation`
holds messages that hold blocks that hold Julia and text documents. There is no
privileged root type — you assemble domains out of smaller domains.

**Projections compose.** A bidirectional projection is a function, and four
things follow from that:

- **Several views of one document.** Edit a JSON object as a tree, then render
  the same data as a widget form, a table, or source. There is no second
  representation to keep in sync.
- **Computed views.** Insert a sorting, filtering or focusing projection and
  the view is sorted, filtered or zoomed without a change to the model.
  Removing the projection removes the view, not the data.
- **Mixed-domain documents.** A `NestingProjection` embeds one domain inside
  another, so one document can nest JSON inside XML inside styled prose. Every
  cursor position round-trips across the boundaries.
- **Backend-agnostic rendering.** The pipeline emits an abstract
  `GraphicsCanvas`. SDL2 renders it in a native window and a web backend renders
  it in the browser (the editor runs in an HTTP/WebSocket server; the browser
  paints a JSON draw-list and sends back raw input) — the same projection code
  drives both. A backend can also tap an earlier stage: the `ConsoleBackend`
  renders the **Text** domain straight to the terminal (ANSI colors, keyboard
  navigation, no graphics step). An IDE-plugin backend could follow the same way.

See the [projection system](documentation/package/kernel/projection-system.md) and [higher-order
projections](documentation/package/kernel/higher-order-projections.md) guides for the mechanics.

---

## What works today

There are twenty domain packages. Each one owns its document types, its parser
where it has a text syntax, and its projection.

| Domain | What it holds |
|---|---|
| **JSON** | Object, array and primitive tree, with a parser and a file wrapper |
| **YAML** | The same data model, with indentation syntax |
| **XML** | Element and attribute tree |
| **Markdown** | Block and inline documents, rendered or as source |
| **RST** | reStructuredText sections and directives, rendered or as source |
| **Book** | Structured prose: chapters, paragraphs, lists, embedded pictures |
| **Math** | Algebraic expression trees: variable, binary operator, parenthesis, assignment |
| **Julia** | A subset of the Julia AST: identifier, integer, binary operator, call, if, function, block |
| **SQL** | Select, insert, update and create statements, with a parser |
| **Database** | Database and instance documents, and the `make_database_adapter` seam |
| **DbCatalog** | Schema, table and column documents; a catalog query becomes SQL |
| **FileSystem** | Directory and file tree |
| **Graph** | Vertices, edges and the layout document that holds their geometry |
| **Chart** | Line, bar, histogram, scatter and strip plots |
| **SequenceChart** | Events on timelines, and the arrows between them |
| **Formula** | A spreadsheet cell formula whose expression is a Julia document |
| **FSM** | States, transitions and the diagram that lays them out |
| **Process** | A flowchart language: the step documents and the runtime that walks them |
| **Conversation** | The AI chat as a domain: messages, blocks, code executions |
| **Workbench** | The IDE shell: navigator, console, descriptor, operator, searcher, evaluator, assistant |

The substrate under them carries what no single domain owns:

| Package | What it holds |
|---|---|
| **Text** | Styled multi-span text, word wrapping, line numbering |
| **Syntax** | The generic S-expression intermediate between a semantic domain and text |
| **Graphics** | The render primitives every backend paints |
| **Widget** | Labels, buttons, checkboxes, tabbed panes, scroll panes, split panes, toolbars, tables |
| **Collection** | `CellVector`, a reactive indexed vector, and `ListNode`, a lazy doubly-linked list |

Selection and cursor movement work in every domain. The SDL backend is the
primary frontend; a [web backend](documentation/package/kernel/devices-and-backends.md#web-backend)
renders the same editor in the browser (`run_example("json"; backend=WebBackend())`
after `using ProjecturedWeb`). The assistant and the MCP server are built in.
Character type-in and range editing work in the field-addressed domains; the
[roadmap](documentation/requirement/delivery-roadmap.md) has the rest.

### Screenshots

| JSON editor | Widget forms | Table view |
|---|---|---|
| <img width="396" alt="JSON example" src="asset/image/example/json.png"> | <img width="1024" alt="Widget example" src="asset/image/example/widget.png"> | <img width="397" alt="Table example" src="asset/image/example/table.png"> |

| Syntax tree | Julia AST | Workbench |
|---|---|---|
| <img width="586" alt="Syntax example" src="asset/image/example/syntax.png"> | <img width="336" alt="Julia AST example" src="asset/image/example/julia.png"> | <img width="1285" alt="Workbench example" src="asset/image/example/workbench.png"> |

---

## Quick start

**Prerequisites**

- Julia 1.11 or later. The `Project.toml` files use `[sources]` path
  dependencies.
- SDL2 and SDL_ttf, for the SDL backend.
- `ANTHROPIC_API_KEY`, optional. Without it the assistant uses a deterministic
  offline backend.

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
julia --project=environment/all
```

```julia
julia> using Projectured, ProjecturedExample
julia> run_example()                  # opens the JSON example
julia> run_example("assistant")       # the built-in AI conversation
julia> run_example("widget")          # widget form example
julia> run_example("table")           # table view
julia> run_example("julia")           # Julia AST editor
julia> run_example("json"; backend=WebBackend())   # in the browser (after `using ProjecturedWeb`) → http://127.0.0.1:8080
julia> print_example("syntax")        # dump a projection's output to stdout
julia> write_example_image("json", "/tmp/snapshot.bmp")   # save to file
```

See the [debugging guide](documentation/guide/debugging-guide.md) for the full REPL helper catalogue
and the [testing guide](documentation/guide/testing-guide.md) for running the test suite.

---

## Repository layout

One dimension per level: what a file **is** decides its top folder, and which
**slice** it belongs to decides the folder under that. The slices are flat, and
`kernel` is the one with layers inside it. See
[plan/done/repository-tree.md](plan/done/repository-tree.md).

| Path | Contents |
|---|---|
| [source/](source/) | The system — one folder per slice, and `kernel/` with its seventeen layers |
| [test/](test/) | The suites, one folder per slice, plus `suite/` for what belongs to no package |
| [example/](example/) | Documents, galleries and workload bodies, one folder per slice |
| [package/](package/) | One directory per package, named for the package: a `Project.toml` and a `src/<Name>.jl`, and nothing else |
| [environment/](environment/) | `all/` — the resolved closure the whole suite runs in. No code |
| [documentation/](documentation/) | Cross-cutting guides, plus [package/](documentation/package/) for the per-slice ones — see [the guide index](documentation/README.md) |
| [asset/](asset/) | Fonts, screenshots, the web client, and the precompile recording |
| [tool/](tool/) | Scripts that are not part of the system |
| [plan/](plan/) | Design notes and work-in-progress plans |

A package and its code do not share a directory. `package/ProjecturedJson/` is a
name and an include list; the code it includes is `source/json/`, its suite is
`test/json/` and its documents are `example/json/`.

## Guides

Three reading orders.

### Start here

1. [Introduction](documentation/design/editor-derivation.md) — the engineer's introduction: every concept with its real code, how the concepts combine, and how to extrapolate what the system can do.
2. [Concepts](documentation/design/editor-concepts.md) — plain-English introduction: what projectional editing is, the five core ideas, and a step-by-step walkthrough of what happens when you press a key.
3. [Examples tour](documentation/guide/examples-tour.md) — guided tour of six examples, from simplest to most complex; what to try and what each one demonstrates.
4. [Getting started](documentation/guide/setup-guide.md) — prerequisites, setup, and the REPL helpers.

### Before you build something

5. [Architecture](documentation/design/system-anatomy.md) — the package graph, the kernel's layers, module inventory, and the projection pipeline. [Terminology](documentation/rule/division-terminology.md) defines the division vocabulary (package / layer / slice / module).
6. [Reactive cells](documentation/package/kernel/cell.md) — the `Cell` system that powers incrementality.
7. [Macros](documentation/package/kernel/macros.md) — `@document`, `@projection`, `@iomap` macros.
8. [Projection system](documentation/package/kernel/projection-system.md) — the four projection interface functions and the printer/reader pair.
9. [Tutorial: new domain](documentation/guide/new-domain-guide.md) — step-by-step: add a new domain from scratch.

### Going deeper

- [Higher-order projections](documentation/package/kernel/higher-order-projections.md) — `Sequential`, `Recursive`, the dispatchers, `Nesting`, `Alternative`.
- [Generic projections](documentation/package/kernel/generic-projections.md) — `Preserving`, `Invariably`, `Copying`, `Sorting`, `Reversing`, `Focusing`.
- [Operations](documentation/package/kernel/operation.md) — what an operation is and how the reader chain produces them.
- [Editor](documentation/package/kernel/editor.md) — the REPL loop, event handling, and rendering pipeline.
- [Reference guide](documentation/package/kernel/reference.md) — reference paths and the `@reference` / `@reference_case` DSL.
- [Selection guide](documentation/package/kernel/selection.md) — how selection propagates through nested documents.
- [Devices and backends](documentation/package/kernel/devices-and-backends.md) — the `Backend`/`Device` split.
- [Build a binary](documentation/guide/build-guide.md) — the build command, what goes into a binary, what it reads from its bundle, and how a distribution is tested.
- [Static compilation](documentation/guide/static-compilation-guide.md) — `juliac --trim`, why an abstract type with four or more subtypes blocks it, and how to keep the abstract type anyway.
- [Design decisions](documentation/design/architecture-decisions.md) — why pull-based reactivity, every-field-is-a-cell, shared selection, `ProjectionReference`.

### Per-slice guides

Domains: [json](documentation/package/json/json.md) · [xml](documentation/package/xml/xml.md) · [rst](documentation/package/rst/rst.md) · [math](documentation/package/math/math.md) · [graph](documentation/package/graph/graph-layout.md) · [chart](documentation/package/chart/chart.md) · [sequencechart](documentation/package/sequencechart/sequencechart.md) · [fsm](documentation/package/fsm/fsm.md) · [process](documentation/package/process/process.md) · [workbench](documentation/package/workbench/workbench.md)

Substrate: [text](documentation/package/text/text.md) · [syntax](documentation/package/syntax/syntax.md) · [graphics](documentation/package/graphics/graphics.md) · [widget](documentation/package/widget/widget.md) · [pane](documentation/package/pane/pane.md) · [collection](documentation/package/collection/collection.md) · [versioning](documentation/package/versioning/versioning.md) · [bounded sync](documentation/package/reflection/bounded-sync.md)

Tooling: [adaptagrams](documentation/package/adaptagrams/README.md) · [build a binary](documentation/guide/build-guide.md)

### Working in the REPL

- [Debugging](documentation/guide/debugging-guide.md) — `run_example`, `print_example`, `write_example_image`, driving the printer/reader by hand, forcing reactive cells.
- [Testing](documentation/guide/testing-guide.md) — `test_all`, per-package helpers, walker utilities.

## Roadmap

See [the roadmap](documentation/requirement/delivery-roadmap.md) for the near,
medium and long term. Four items are in progress: uniform character editing,
click-to-select in every domain, undo and redo, and editable tables.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for repo conventions, the PR process,
code style, and how to add a new domain.

## Conventions

- All indexing is **1-based** (Julia convention).
- Projections must be **bidirectional**: every printer needs a matching reader.

## Project context for agents

If you are an AI assistant working in this repo, also read [CLAUDE.md](CLAUDE.md);
it points at the same guides with a framing tuned for non-trivial changes.
[SEALING.md](SEALING.md) says which files are sealed, and a sealed file must not
be changed without permission.

## Licence

Dual-licensed:

- [LICENCE-PD](LICENCE-PD) — free, public-domain-style dedication for
  non-commercial use of unmodified copies only.
- [LICENCE-COMMERCIAL](LICENCE-COMMERCIAL) — required for commercial use
  or for any modification or derivative work. Contact
  levente.meszaros@gmail.com.
