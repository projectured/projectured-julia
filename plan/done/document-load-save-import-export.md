# Load / Save / Import / Export document operations

> **STATUS: DONE.** All four operations implemented and tested
> (`test_serialization`, 53 assertions; document group 465/465, no regressions).
> Commits on branch `worktree-document-load-save-import-export`.
>
> **Key discovery during implementation:** `DocumentCoreModule`
> ([document/Document.jl](../../package/domain/src/document/Document.jl)) already
> carried a **non-functional WIP port** of `LoadDocumentOperation` /
> `SaveDocumentOperation` / `ExportDocumentOperation` (shape `(document,
> filename)`, evaluators reading a `content` field no document type has, calling
> undefined `call_loader`/`call_saver`/`print_document`). Nothing referenced
> them. This task **completes that port**: the WIP stubs were deleted and
> replaced by the working serializer operations (and the missing
> `ImportDocumentOperation` added). The operation shape changed to carry just a
> `path` and act on `editor.document`, consistent with the rest of the editor's
> operations.

## Goal

Add four editor operations for moving a document between the editor and disk:

| Operation | Direction | Format | Scope |
|-----------|-----------|--------|-------|
| **Save**   | document → file | **binary** (exact snapshot) | any `Document` |
| **Load**   | file → document | **binary** | any `Document` |
| **Export** | document → file | **natural** (printer/parser text) | domains with a parser |
| **Import** | file → document | **natural** | domains with a parser |

Two formats with deliberately different trade-offs:

- **Binary (save/load)** — an exact, lossless snapshot of the live document tree
  (every field, including `collapsed` flags and, optionally, the selection).
  Works for **every** document type because it is structural, not domain-aware.
  Fast and faithful, but tied to the in-memory struct layout: it is a
  *same-version* persistence format, not a portable interchange format.
- **Natural (import/export)** — the human-readable text the domain already
  parses and prints (JSON text, XML markup, SQL, Julia source). Portable and
  editable outside ProjecturEd, but only available for domains that have a
  **parser** (`jsonparse`, `xmlparse`, `sqlparse`, `juliaparse`) for import and a
  **projection to text** for export, and lossy w.r.t. editor-only state
  (selection, collapse).

## Background (what already exists)

- **Operations** are `OperationApiModule.Operation` subtypes applied by
  `evaluate_operation(editor, op)`. Built-ins live in
  [package/kernel/src/common/Operation.jl](../../package/kernel/src/common/Operation.jl);
  domain packages may define their own and extend `evaluate_operation` (e.g.
  `DatabaseUpdateOperation` in [Database.jl](../../package/domain/src/document/Database.jl)).
- **Whole-root swap** already exists: `ReplaceReferencedValue(nothing,
  EmptyReferencePath(), doc)` rebinds `editor.document` and drops the cached
  iomap (Operation.jl:203). Load/Import reuse exactly this so the next print
  rebuilds on the new root.
- **`copy_document`** ([DocumentCopy.jl](../../package/kernel/src/common/DocumentCopy.jl))
  is the generic `@document` field-walk that rebuilds a subtree with **fresh,
  detached `Cell`s** and resets `selection`. It motivated the binary design
  (detaching from the reactive graph is what makes serialization safe), though
  the final implementation detaches via a custom `Cell` serializer rather than a
  walk (see D1).
- **Parsers** (text → document) exist per domain in
  [package/domain/src/parser/](../../package/domain/src/parser/): `jsonparse` /
  `jsonparse_file`, `xmlparse`, `sqlparse`, `juliaparse`. The inverse
  (document → text) for export reuses the existing **printer** projections down
  to the text stage (`*ToSyntax → SyntaxToText`), flattened to a `String`.

## Design decisions

### D1 — Binary format: value-only `Cell` serialization (as built)

A live document `Cell` holds `deps`/`dependents` sets wiring it into the
reactive graph, and computed cells hold `thunk` closures. Calling
`Serialization.serialize(editor.document)` directly would drag the entire
projection output graph in through `dependents` (and serialize closures).

**As built — no snapshot walk.** Instead of a `copy_document`-style detaching
walk, a custom `Serialization.serialize(::AbstractSerializer, ::Cell)` writes
**only the cell's value** (`getfield(c, :value)`, never `c[]`), and
`deserialize(::AbstractSerializer, ::Type{Cell})` rebuilds a fresh value cell
(empty `deps`/`dependents`, no `thunk`). That single rule prunes the reactive
graph at *every* cell boundary, so `serialize(document)` stays within the
document's data and covers the document tree, `CellVector`s, and the selection
`ReferencePath` (whose steps are also `Cell`-backed) **uniformly**. A small
versioned header (`"PROJECTURED-DOC"`, `1`) precedes the document so
`load_document` can validate.

This is simpler and more uniform than a per-type walk, and it makes selection
preservation **automatic** (the selection `Cell` and the path's step-`Cell`s
serialize by the same rule) — satisfying the "preserve selection" decision with
zero extra code.

**Finding — do NOT use `serialize_cycle`.** The first cut called
`serialize_cycle(s, c) && return` to preserve object sharing. It *corrupts the
stream*: `serialize_cycle` registers the cell in the writer's backref table, but
the custom `deserialize(::Type{Cell})` has no matching read-side registration, so
the shared-object counter desyncs and a later `CellVector` deserializes as
garbage (a `TypeError`/`KeyError` from a misread tag). A lone `Cell(1)` survived
(no later backref), masking the bug until a container hit it. Fix: drop
`serialize_cycle`. Cost: cell **sharing** (the shared selection chain) is not
preserved — the chain reloads as an equal *value* tree and is re-shared by the
next `set_selection!`/`update_selection!`. A perf nuance, not a correctness
issue; document trees are acyclic, so dropping cycle tracking cannot loop.

`Serialization` is a stdlib. To keep the **kernel dependency-free** (its module
docstring is emphatic), this lives in the **domain** package, not the kernel —
the custom method extends our own `Cell` type (not piracy). Caveat: the binary
format is **not** stable across package/struct versions, and documents holding
live external resources (DB adapters, sockets) won't serialize — that is what
natural export is for.

### D2 — Natural export: project the document to text (decided)

Export renders the document → text **through a projection**, not a hand-written
unparser. Run the domain's printer down to its **text stage**
(`*ToSyntax → SyntaxToText`, producing a `TextText`), flatten that to a
`String`, and write it. This reuses the existing, already-bidirectional printer
as the "natural printer format."

Consequence / known limitation to record: the projected text is the *rendered*
form (indentation, etc.); the import round-trip relies on the domain's parser
being able to re-read it. Where a domain's projected text and its parser's
accepted grammar diverge, export→import is best-effort, not guaranteed
byte-identical. This is the accepted trade for reusing the printer.

**As built:** no new flatten helper was needed — the existing `TextToString()`
projection already turns a `TextText` into a `String`. `document_to_text(doc)`
composes the established three-stage pipeline (the same one the SQL document
tests use):

```julia
SequentialProjection(
    RecursiveProjection(_domain_to_syntax(doc)),  # JsonToSyntax/XmlToSyntax/SqlToSyntax/JuliaToSyntax
    RecursiveProjection(SyntaxToText()),
    RecursiveProjection(TextToString()))           # already flattens to String
# → projection_print(pipeline, doc).output[]
```

`_domain_to_syntax` dispatches on the document's abstract domain supertype
(`JsonDocument`/`XmlDocument`/`SqlDocument`/`JuliaDocument`).

**Round-trip outcome (measured):** JSON / SQL / Julia export→import→export is a
fixed point. **XML is best-effort** (its parser captures inter-element whitespace
as text, so a second export differs) — export still produces valid, re-importable
XML. JSON/XML examples that contain an *insertion placeholder* render as
`"insert … here"` prose, which is not valid source — confirming the editor-state
lossiness; round-trip on real data documents, not editor scaffolding.

### D3 — Dispatch by file extension ↔ root document type (all four domains)

A single registry maps extension ↔ (parser, text-projection, root predicate) for
**all four** parser domains:

```
.json → (jsonparse, json→text projection, JsonDocument)
.xml  → (xmlparse,  xml→text projection,  XmlDocument)
.sql  → (sqlparse,  sql→text projection,  SqlStatement)
.jl   → (juliaparse, julia→text projection, JuliaDocument)
```

- `import_document(path)` picks the parser from the extension.
- `export_document(doc, path)` picks the text projection from the **document
  root type** (validating it matches the path's extension).

### D4 — Scope: whole document in v1

Save/Export serialize `editor.document`; Load/Import replace it whole (via the
existing whole-root swap). A subtree variant — save/export the *selected*
subtree, import *into* the selection — is a natural extension using the same
reference write `ReplaceReferencedValue` already provides; **deferred**.

### D5 — Path source & triggering

The operations carry an explicit `path::String`, so they are fully drivable from
the REPL, tests, MCP tools, and `play_live!` timelines on day one. **Interactive
path picking is out of scope for v1** — wiring a keybinding (Ctrl+S/Ctrl+O) to a
file dialog needs a path-input UI, for which a future *file-picker projection*
(built on the existing `FileSystem` domain + a text-input widget) is the right
home. Note it; do not build it here.

Optional nice-to-have: expose the four as **MCP tools**
([editor/Mcp.jl](../../package/kernel/src/editor/Mcp.jl)) so the agent can
persist/restore documents. Mark optional.

## Module placement (as built)

Both formats live in the **domain** package under a new `serializer/` dir. Binary
*could* be kernel (it is structural), but the kernel deliberately has **zero
dependencies** and binary needs `Serialization` (stdlib), so it stays in domain;
the custom `serialize` extends our own `Cell` type, so this is not piracy.

```
domain/
  Project.toml                       EDIT add Serialization to [deps]
  serializer/BinarySerialization.jl  NEW  value-only Cell (de)serialization;
                                          save_document / load_document;
                                          SaveDocumentOperation, LoadDocumentOperation + evaluate_operation
  serializer/NaturalFormat.jl        NEW  document_to_text (per-domain printer-to-text);
                                          import_document (parser by extension) / export_document;
                                          ImportDocumentOperation, ExportDocumentOperation + evaluate_operation
  document/Document.jl               EDIT remove the non-functional WIP Load/Save/Export stubs
  src/ProjecturedDomain.jl           EDIT include both serializer files (after the *ToSyntax projections)

test/
  src/serializer/SerializationTest.jl  NEW  test_serialization() (registered + exported)
```

The eight public names (`save_document`, `load_document`, `import_document`,
`export_document`, and the four `*DocumentOperation`s) reach `using Projectured`
automatically via the umbrella's mechanical re-export — no manual edit.

## Operation API (as built, all in domain serializer modules)

```julia
# binary (BinarySerializationModule)
struct SaveDocumentOperation <: Operation; path::String; end
struct LoadDocumentOperation <: Operation; path::String; end
evaluate_operation(ed, op::SaveDocumentOperation) = save_document(ed.document, op.path)
function evaluate_operation(ed, op::LoadDocumentOperation)
    ed.document = load_document(op.path); ed.iomap = nothing      # whole-root swap
end

# natural (NaturalFormatModule)
struct ExportDocumentOperation <: Operation; path::String; end
struct ImportDocumentOperation <: Operation; path::String; end
evaluate_operation(ed, op::ExportDocumentOperation) = export_document(ed.document, op.path)
function evaluate_operation(ed, op::ImportDocumentOperation)
    ed.document = import_document(op.path); ed.iomap = nothing
end
```

The whole-root swap (`ed.document = …; ed.iomap = nothing`) is exactly the
empty-path branch of `ReplaceReferencedValue`, inlined for two lines rather than
imported.

## Implementation steps — all DONE ✅

1. ✅ **Binary save/load (domain).** `serializer/BinarySerialization.jl`:
   value-only `Cell` `serialize`/`deserialize` (no `serialize_cycle`),
   `save_document` / `load_document` + versioned header. `Serialization` added to
   domain `[deps]`; include wired into `ProjecturedDomain.jl`.
2. ✅ **Binary operations (domain).** `SaveDocumentOperation` /
   `LoadDocumentOperation` + `evaluate_operation` (whole-root swap).
3. ✅ **Export via projection-to-text (domain).** `document_to_text` composing
   `*ToSyntax → SyntaxToText → TextToString` per domain (reused `TextToString`,
   no new flatten helper). All four parser domains.
4. ✅ **Natural registry + operations (domain).** `serializer/NaturalFormat.jl`:
   `import_document` (parser by extension), `export_document` (with an
   extension-mismatch guard), `ImportDocumentOperation` /
   `ExportDocumentOperation` + `evaluate_operation`.
5. ✅ **Remove WIP collision.** Deleted the non-functional WIP Load/Save/Export
   stubs from `DocumentCoreModule` (see status note at top).
6. ✅ **Tests.** `test_serialization()` (53 assertions) + registration; document
   group regression 465/465.
7. **(not done, optional) MCP tools** for the four operations.
8. **(not done, deferred) Interactive path picker** projection + keybindings —
   separate plan.

## Testing (as built)

`package/test/src/serializer/SerializationTest.jl` — `test_serialization()`,
registered in `test_documents()` and exported. Covers:

- **Binary round-trip** (json/xml/sql/julia example docs): save → load → re-save
  is a **byte-identical fixed point**; loaded cells are detached (empty
  `deps`/`dependents`, no `thunk`); the loaded document still projects through
  the real example projection.
- **Binary selection**: a set selection survives save→load (`==`).
- **Binary header validation**: `load_document` on a non-ProjecturEd file throws.
- **Natural round-trip** (clean, no-insertion docs): `import_document(
  export_document(doc))` yields the right type; `document_to_text` is a fixed
  point for JSON/SQL/Julia; XML is asserted re-importable only (best-effort).
- **Export extension guard**: writing one format under another known extension
  throws.
- **Operations**: binary and natural Save/Load/Export/Import through a mutable
  editor stand-in — file appears, or `document` swapped and `iomap === nothing`.

## Resolved (was open)

- **Export mechanism** — **project the document to text** (D2): reuse the
  domain's `*ToSyntax → SyntaxToText` printer and flatten, rather than writing
  dedicated unparsers.
- **Selection in binary** — **preserved** (D1): the snapshot clones the
  selection path into fresh Cells so a saved document reloads with its cursor.
- **Domains** — **all four** parser domains (JSON, XML, SQL, Julia) in the first
  cut.
