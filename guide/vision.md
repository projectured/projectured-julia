# Vision

This document explains the long-term potential of ProjecturEd, the pain
points it addresses, and how it relates to other tools in the structured
editing space. For the current state and near-term priorities see
[the roadmap](roadmap.md).

---

## Why structured editing matters

Traditional text editors have a fundamental mismatch: the things they edit
(source code, configuration, data) have rich structure, but the editor sees
only a flat sequence of characters. Consequences:

- **Syntax errors are discovered after the fact**, not prevented at the point
  of entry. Malformed JSON, unclosed parentheses, mis-indented Python — the
  editor lets you type them and tells you later.
- **Refactoring is string manipulation.** Rename a variable and your tool
  must parse, analyse, transform, and re-serialise the entire file — and it
  still gets confused by macros, string literals, and comments.
- **Multiple views of the same data require multiple files.** If you want to
  see your data as a table and as a tree, you maintain two separate
  representations and keep them in sync manually.
- **AI assistants work with line numbers and character offsets**, not with
  the semantic structure of the document. They hallucinate positions and
  produce diffs that fail to apply.

A projectional editor where the *model* is the truth eliminates all of these
problems by construction:

- The cursor never leaves a valid position in the model. You literally cannot
  type a syntax error.
- Rename is a single `FieldReference` update; the projection re-renders all
  occurrences automatically.
- Multiple projections of the same model give multiple views — switch
  projections without touching the underlying data.
- AI operations target reference paths, not line numbers; they cannot produce
  structurally invalid edits.

---

## What bidirectional projections enable

ProjecturEd's projections are composable functions. This has non-obvious
consequences:

**1. Domain-crossing documents.** A `NestingProjection` lets you embed a
domain inside another. A prose document can contain a rendered JSON value.
A workbench pane can display a Math expression. Cursor navigation crosses
domain boundaries transparently because each projection in the chain handles
its own selection translation.

**2. Computed views.** A `SortingProjection` inserted before `JsonToSyntax`
gives you a sorted view of a JSON object *without changing the model*. Undo
removes the sort projection, not a data transformation. Similarly, a
`FilteringProjection` gives a filtered view; a `FocusingProjection` zooms into
a sub-document.

**3. Backend-agnostic rendering.** The projection pipeline produces a
`GraphicsCanvas` — an abstract description of what to draw. Any backend that
can render a `GraphicsCanvas` is a valid target: SDL2 today, a terminal
renderer, a WebGL canvas, or an IDE extension tomorrow. The projection code
does not change.

**4. Offline rendering.** `write_image` renders any projected document to a
BMP file without opening a window. This enables automated documentation
generation, screenshot testing, and CI-based visual regression checks.

---

## The MCP bridge: AI-native editing

When the editor's `run!` loop is active it exposes an MCP server on port 9876.
An AI assistant connected to this server can:

- **Read the live document structure** via `resource://guide/...` and
  `print_object(editor.document)` — not a string, the actual typed tree.
- **Build precise reference paths** using `@reference` — `entries[1].value{3}`
  is unambiguous and cannot be confused with a line number.
- **Apply structural operations** via `replace_selection!`, `set_selection!`,
  and domain operations — no string parsing, no diffs, no patch failures.
- **Inspect the projection output** at any stage to verify the visual
  consequence of a structural change before committing it.

This makes ProjecturEd a natural substrate for AI-driven editing workflows:
the assistant operates on the model, not the presentation, so its actions are
always semantically coherent.

---

## Multi-backend future

The platform abstraction is split in two: the `Backend` interface is
`init!` / `quit!` / `measure_text`, and the `Device` interface is
`write_to_device(s)` / `read_from_device(s)`. Any platform that can implement
these is a valid backend.

Near-term:
- **Terminal backend** — `KeyPress`-compatible, renders `GraphicsCanvas` as
  ANSI escape sequences. Enables SSH-accessible editing and CI-friendly
  projections.
- **Headless backend** — for testing and screenshot generation (already
  partially available via `write_image`'s software renderer).

Medium-term:
- **Web backend** — HTTP + WebSocket; canvas rendering via `<canvas>` or SVG.
  Opens the editor to browser-based workflows and collaboration.

Long-term:
- **IDE plugin backend** — render into VS Code or JetBrains using their
  custom renderer APIs while keeping the full projection pipeline in Julia.

---

## Extensibility story

Adding a new domain in ProjecturEd is intentionally small:

1. Define your document types (structs with `@document` + `selection::Reference`).
2. Write `projection_print` methods mapping each type to the syntax domain.
3. Write `projection_read` methods translating selection operations backward.
4. Add an example and a test.

Step 2–3 together are typically 50–150 lines for a simple domain. The
framework — reactive cells, the editor REPL, higher-order projections,
selection mechanism, MCP server — is already there. See
[the tutorial](tutorial-new-domain.md) for a worked walkthrough.

---

## Compared to other tools

### JetBrains MPS

MPS is the most mature projectional editor IDE available today. It is
production-quality, supports many industrial domains, and has a large user
base in embedded and safety-critical software.

ProjecturEd differs in:
- **Language:** Julia vs. Java/Kotlin. Easier to embed in scientific and
  data-processing workflows.
- **Architecture:** Composable pure-function projections vs. a more tightly
  coupled AST-centric model. Projections in ProjecturEd can be combined
  independently of the domain.
- **Reactivity:** Pull-based incremental computation vs. a more imperative
  update model.
- **Scope:** MPS is a full IDE with a language workbench, build system, and
  version control integration. ProjecturEd is a library and framework — you
  compose your editor from it.

### Lamdu

Lamdu is a live-programming structured editor for a Haskell-like language.
Its goal is type-safe editing with live execution.

ProjecturEd differs in:
- **Domain generality:** Lamdu edits one specific language; ProjecturEd edits
  any domain you define.
- **Projection composability:** Lamdu does not have the notion of composable
  bidirectional projections as a first-class abstraction.

### Hazel

Hazel is a research language with a structured editor that maintains semantic
meaning even in the presence of holes (incomplete programs).

ProjecturEd shares the structural editing philosophy but differs in:
- **Focus:** Hazel optimises for type-theoretic properties of incomplete
  programs. ProjecturEd optimises for generality across arbitrary domains.
- **Practicality:** ProjecturEd has a working SDL editor with multiple domains
  today; Hazel is primarily a research prototype.

### Tree-sitter

Tree-sitter is a fast incremental parser, not an editor. It gives you a
concrete syntax tree from text, but text remains the primary representation.
Editing still mutates characters; Tree-sitter re-parses the result.

ProjecturEd eliminates the text/parse round-trip entirely — the model is
always the tree, and text is a derived view.

### Traditional text editors (VS Code, Emacs, Vim, …)

Traditional editors are fast, flexible, and have enormous ecosystem support.
ProjecturEd does not compete with them for text editing. It targets a
different problem space: domains where the structure matters more than the
text serialisation, where multiple views of the same data are useful, and
where AI-assisted editing benefits from operating on a typed model rather
than on character offsets.

In the long run, ProjecturEd's backend architecture allows it to *be* a VS
Code extension or an Emacs mode — adding structured editing as a layer on
top of an existing editor rather than replacing it.
