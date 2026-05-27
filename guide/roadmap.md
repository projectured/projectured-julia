# Roadmap

This document distils the development priorities for ProjecturEd into three
horizons. The detailed design notes and open questions for each item live in
[the further development plan](../plan/further-development.md).

The ordering principle: **deepen the vertical slice first** (make editing
actually work end-to-end), **then widen** (more domains, more layouts, more
backends), **then distribute** (network, collaboration, external data).

---

## Near-term: make the editor actually edit

The projection pipeline is complete and bidirectional. Cursor movement works
across all domains. What's missing is the ability to *change* a document.

### 1. Character editing (`StringReplaceRangeOperation`)

Wire printable key events and backspace/delete into `evaluate_operation` for
`JsonString`, `XmlText`, `PrimitiveString`, and any domain with text-valued
leaf nodes. The `StringReplaceRangeOperation` type already exists in the
`Primitive` domain; it needs to be produced by the reader chain and evaluated
by the editor.

### 2. Mouse click-to-select

`TextToGraphics` already stores `char_to_coord` (a segment table of
`(char_start, x, y)` triples) in its IO map. The reader needs one more method:
receive a `MousePress(x, y)` event, binary-search `char_to_coord`, and produce
`ReplaceSelectionOperation({flat_pos})`. The rest of the reader chain already
handles flat positions. This is the highest-impact, lowest-effort change.

### 3. Structural insert / delete

Add/remove elements from `JsonArray`, entries from `JsonObject`, children from
`SyntaxNode`. Requires `CollectionInsertOperation` / `CollectionDeleteOperation`
and reader-side logic that detects when the cursor is on structural whitespace
and a structural key is pressed.

### 4. Undo / redo

An operation log on the `Editor` that appends each `evaluate_operation` call
and its inverse. `Ctrl+Z` replays the inverse. Depends on the editing
operations above having well-defined inverses.

### 5. Clipboard

The `Clipboard` domain exists as a stub. Wire `Ctrl+C/X/V` to
`ClipboardCopyOperation` / `ClipboardPasteOperation`.

---

## Medium-term: widen the scope

Once editing works, the natural expansions:

### 6. Complete domain readers

Most domains have printers but no readers (navigation only). Priority order:
- **Julia** — `JuliaToSyntax` printer exists; adding the reader is the path
  to self-hosting (editing predj's own source code).
- **Math** — compelling demo: edit `x + y * z` and see the AST update.
- **XML** — wire the existing `XmlToSyntax` reader stubs.
- **Table** — editable cells with column-header navigation.

### 7. Terminal backend

Implement `Backend` over terminal I/O (ANSI escape sequences). `KeyPress` is
already backend-agnostic; only `measure_text` and `write_to_devices` need
new implementations. Enables SSH-accessible editing and headless CI.

### 8. Incremental search and focus

A `FocusingProjection`-based mode where typing a query narrows the visible
document to matching subtrees. The reader maps edits back through the filter.
Ctrl+F opens the search input; confirmations produce `StringReplaceRangeOperation`s
on the matching nodes.

### 9. Transactional / staged editing

A `StagingProjection` that accumulates edits in a buffer without touching the
real document. Commit applies them atomically; discard drops them. Enables
previewing complex multi-step refactors before committing.

### 10. Graph domain and graph layout

A directed-graph domain where nodes hold sub-documents as content and edges
carry relationship metadata. A graph-layout projection assigns `(x, y)` to
each node and renders edges as `GraphicsRect` strokes. Foundation for dataflow
diagrams, dependency graphs, and mind maps.

---

## Long-term: distribute and integrate

### 11. Web backend

HTTP + WebSocket; `GraphicsCanvas` rendered via `<canvas>` or SVG. Opens the
editor to browser-based workflows.

### 12. Live collaboration

Structural operations on a well-defined model are the natural substrate for
OT (operational-transform) or CRDT-based collaboration. Each operation is
already a typed, invertible value — the infrastructure for multi-user editing
is mostly a transport and merge layer.

### 13. External document persistence

Load and save documents to disk in a structured format (JSON, XML, or a
domain-specific format). Today documents are in-memory only. Persistence needs
a serialiser per domain plus a loader that reconstructs the reactive cell graph.

### 14. Self-hosting

Edit predj's own source code using the Julia domain projection, running inside
predj. This is the strongest validation of the architecture's generality and
the primary long-term goal.

### 15. Plugin / package system

Allow third-party domains and projections to be distributed as Julia packages
and loaded into a running editor at runtime, analogous to VS Code extensions.

---

## What won't change

The following are considered stable design decisions and are not on the roadmap
for revision:

- **Pull-based reactive `Cell` system** — the foundation of incrementality.
- **Bidirectional projections** — the printer/reader pair is the contract.
- **Module-per-domain / module-per-projection** — keeps dependencies auditable.
- **1-based indexing** — Julia convention.
- **MCP server** — the AI bridge is a first-class feature, not an afterthought.
