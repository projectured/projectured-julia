# Roadmap

This document distils the development priorities for ProjecturEd into three
horizons: what has been **delivered**, what is **in progress**, and what is
**planned**. The detailed design notes and open questions for each item live in
[the further development plan](../plan/tentative/further-development.md).

The ordering principle: **deepen the end-to-end path first** (make editing
actually work end-to-end), **then widen** (more domains, more layouts, more
backends), **then distribute** (network, collaboration, external data).

---

## Delivered

Much of the original near- and medium-term roadmap has shipped. What now works
end to end:

- **Structural insert / delete.** Elements can be added to and removed from JSON
  arrays, entries from JSON objects, XML elements and attributes, and syntax
  children, via `insert_elements` / `delete_elements` (a `ReplaceReferencedValueOperation`
  splice) driven by contextual authoring gestures.
- **In-place authoring in structured domains.** JSON, XML, and YAML have full
  contextual gesture sets, and character-level editing works inside strings,
  numbers, keys, XML text and attribute values, and styled text spans, produced
  by the reader chain and evaluated as `ReplaceStringRangeOperation`s.
- **Type-in with live completion.** Julia and SQL are edited through a
  parser-backed insertion cursor (`juliaparse` / `sqlparse`) with live
  reflection-driven completion; Math, Book, and Markdown support text type-in.
- **Clipboard.** Copy, cut, note, and paste over arbitrary wrapped content is
  provided by the clipboard projections, with an operating-system clipboard
  bridge when text conversion is configured.
- **Console / terminal backend.** Renders the Text domain straight to the
  terminal with 24-bit ANSI colour and structural navigation; run via
  `run_console_example(interactive=true)`.
- **Web backend.** Runs the same editor in the browser over HTTP + WebSocket,
  shipping a JSON draw-list to a canvas client with incremental dirty-rect
  rendering; run via `run_web_example`.
- **Graph domain and auto-layout.** A vertex/edge/graph domain with a separate
  layout stage; native placement and edge routing come from the opt-in
  Adaptagrams package, with a pure-Julia fallback engine when it is absent.
- **Document persistence.** Binary `save_document` / `load_document` (exact,
  lossless, same-version) plus a human-readable natural-format
  `import_document` / `export_document` path dispatched by file extension.
- **Search.** `search_references` / `search_objects` produce selectable paths;
  filtering, focusing, and highlighting projections and a search-input widget
  build on them.
- **Version history.** A versioning overlay records and deletes snapshots
  (Ctrl+Shift+S / Ctrl+Delete) and selects a version by criterion (latest,
  index, author, as-of, predicate).

---

## In progress

Editing works end to end for the field-addressed domains; the remaining work is
making it uniform and complete.

### 1. Character editing everywhere

Character type-in and range editing are wired and tested for the field-addressed
domains (JSON, XML, YAML, text, prose, and the type-in / insertion path). The
target is uniform in-place character editing of every leaf value the caret can
enter, in every domain.

### 2. Mouse click-to-select everywhere

Click-to-position works where a projection records the necessary
coordinate map (for example `TextToGraphics`'s segment table). The remaining work
is completing click-to-select across all domains and projections.

### 3. Undo / redo

Version history exists through the versioning overlay, but a general operation-log
undo/redo of arbitrary edits does not. It needs an operation log on the `Editor`
that appends each `evaluate_operation` call and its inverse, replayed by
`Ctrl+Z`; it depends on the editing operations having well-defined inverses.

### 4. Editable tables

Table cells with column-header navigation, building on the existing table
rendering.

---

## Planned

### 5. Transactional / staged editing

A `StagingProjection` that accumulates edits in a buffer without touching the
real document. Commit applies them atomically; discard drops them. Enables
previewing complex multi-step refactors before committing.

### 6. Live collaboration

Structural operations on a well-defined model are the natural substrate for
OT (operational-transform) or CRDT-based collaboration. Each operation is
already a typed, invertible value — the infrastructure for multi-user editing
is mostly a transport and merge layer.

### 7. Runtime plugin loading

Opt-in packages already extend the editor at its factory seams (`make_backend`,
`make_agent_server`, and the solver / layout generics) at load time. The
remaining goal is loading third-party domains and projections into a *running*
editor, analogous to VS Code extensions.

### 8. Annotation domain

Attaching typed annotations to any document through a global registry is
described in the design ([editor/annotation.md](../plan/tentative/annotation.md)) but not
yet implemented; no annotation types or functions exist in the code today.

### 9. Self-hosting

Edit ProjecturEd's own source code using the Julia domain projection, running
inside ProjecturEd. This is the strongest validation of the architecture's
generality and the primary long-term goal.

---

## What won't change

The following are considered stable design decisions and are not on the roadmap
for revision:

- **Pull-based reactive `Cell` system** — the foundation of incrementality.
- **Bidirectional projections** — the printer/reader pair is the contract.
- **Module-per-domain / module-per-projection** — keeps dependencies auditable.
- **1-based indexing** — Julia convention.
- **MCP server** — the AI bridge is a first-class feature, not an afterthought.
