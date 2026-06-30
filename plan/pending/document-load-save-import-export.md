# Load / Save / Import / Export document operations

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
  detached `Cell`s** and resets `selection`. This is the model for the binary
  snapshot — detaching from the reactive graph is what makes serialization safe
  (see below).
- **Parsers** (text → document) exist per domain in
  [package/domain/src/parser/](../../package/domain/src/parser/): `jsonparse` /
  `jsonparse_file`, `xmlparse`, `sqlparse`, `juliaparse`. The inverse
  (document → text) for export reuses the existing **printer** projections down
  to the text stage (`*ToSyntax → SyntaxToText`), flattened to a `String`.

## Design decisions

### D1 — Binary format: snapshot, then `Serialization`

A live document `Cell` holds `deps`/`dependents` sets wiring it into the
reactive graph, and computed cells hold `thunk` closures. Calling
`Serialization.serialize(editor.document)` directly would drag the entire
projection output graph in through `dependents` (and serialize closures). So:

1. **Snapshot** the document with a `copy_document`-style walk that allocates
   fresh `Cell`s with **empty** dep sets and no thunks — i.e. detach the value
   tree from the reactive graph.
2. `Serialization.serialize` the detached snapshot, behind a small versioned
   header (`("PROJECTURED-DOC", 1)`) so `load_document` can validate.

`Serialization` is a stdlib (no new heavy dep — fits the kernel's
"no heavy dependencies" rule). Caveat to document: the binary format is **not
guaranteed stable across package versions or struct changes** — that is what
natural export is for.

**Selection (decided): preserve.** The snapshot **keeps** the document's
selection so a saved document reloads with its cursor exactly where it was.
`copy_document` resets selection to `nothing`, so the snapshot walk must *not*
reuse that behavior for `selection` — it clones the stored `ReferencePath` into
fresh, detached step-`Cell`s (a `ConcreteReferencePath` carries `head`/`tail`
and a `RangeReference` carries `start`/`stop` as `Cell`s), so the path
serializes cleanly and is rebound on load. Factor the shared field-walk with
`copy_document` but parameterize the selection handling
(`snapshot_document` keeps it; `copy_document` keeps resetting it).

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

Two pieces are needed:

1. A **text-flatten** helper `TextText → String` (extend the existing text
   helpers near `text_selection_substring` in
   [Text.jl](../../package/domain/src/document/Text.jl)).
2. A **document → text projection** per domain. Prefer the existing per-domain
   `*ToSyntax` + `SyntaxToText` printers; the generic natural renderer is graphics-
   oriented, so export wires the text-stage printers directly.

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

## Module placement

```
kernel/  (domain-agnostic, binary)
  common/DocumentSnapshot.jl   NEW  snapshot_document; save_document/load_document
  common/Operation.jl          EDIT SaveDocumentOperation, LoadDocumentOperation + evaluate_operation

domain/  (domain-aware, natural)
  document/Text.jl              EDIT TextText → String flatten helper
  serializer/NaturalFormat.jl  NEW  document_to_text (printer-to-text per root type);
                                     extension registry; import_document / export_document;
                                     ImportDocumentOperation, ExportDocumentOperation + evaluate_operation
```

Rationale: binary is structural and lives in the kernel next to `copy_document`;
natural needs the domain parsers, so it lives in `ProjecturedDomain` (which may
extend the kernel's `evaluate_operation` generic, as other domain ops do).

## Operation API sketch

```julia
# kernel — binary
struct SaveDocumentOperation <: Operation; path::String; end
struct LoadDocumentOperation <: Operation; path::String; end
evaluate_operation(ed, op::SaveDocumentOperation) = save_document(ed.document, op.path)
function evaluate_operation(ed, op::LoadDocumentOperation)
    ed.document = load_document(op.path); ed.iomap = nothing      # whole-root swap
end

# domain — natural
struct ExportDocumentOperation <: Operation; path::String; end
struct ImportDocumentOperation <: Operation; path::String; end
evaluate_operation(ed, op::ExportDocumentOperation) = export_document(ed.document, op.path)
function evaluate_operation(ed, op::ImportDocumentOperation)
    ed.document = import_document(op.path); ed.iomap = nothing
end
```

(Load/Import may instead delegate to `evaluate_operation(ed,
ReplaceReferencedValue(nothing, EmptyReferencePath(), doc))` to share the swap
code path verbatim — preferred.)

## Implementation steps (each = one commit)

1. **Binary snapshot + save/load (kernel).** Add `snapshot_document` (detaching
   walk; factor shared logic with `copy_document`) and `save_document` /
   `load_document` with the versioned header in `common/DocumentSnapshot.jl`.
   Add `Serialization` to the kernel `[deps]`.
2. **Binary operations (kernel).** `SaveDocumentOperation` /
   `LoadDocumentOperation` + `evaluate_operation` in `common/Operation.jl`;
   export them.
3. **Export via projection-to-text (domain).** Add the `TextText → String`
   flatten helper, and a `document_to_text(doc)::String` that selects the
   domain's text-stage printer (`*ToSyntax → SyntaxToText`) by root type, runs
   it, and flattens. Cover all four parser domains (JSON, XML, SQL, Julia).
4. **Natural registry + operations (domain).** `serializer/NaturalFormat.jl`:
   extension registry, `import_document` (parser by extension) /
   `export_document` (`document_to_text` by root type),
   `ImportDocumentOperation` / `ExportDocumentOperation` + `evaluate_operation`.
   Wire the include into `ProjecturedDomain.jl` and re-export through the
   umbrella.
5. **(optional) MCP tools** for the four operations.
6. **(deferred) Interactive path picker** projection + keybindings — separate
   plan.

## Testing

Per repo convention, keep scope narrow.

- **Binary round-trip** (any domain): `load_document(save_document(doc))`
  reproduces `doc` structurally. Compare with existing structural-equality
  helpers (`*_ignoring_types`) or by equality of printer output
  (`walk_printer_output`). Use a temp path under the session scratchpad.
- **Natural round-trip** (per parser domain): `import_document(export_document(
  doc, path))` reproduces the parsed document — assert
  `jsonparse(document_to_text(doc))` round-trips on `json_example`, etc. Drive
  each from its smallest domain test (`test_json`, `test_xml`, …), not
  `test_all`. (Round-trip is best-effort per D2 — if a domain's projected text
  is not re-parseable, record it as a known limitation rather than forcing it.)
- **Operation level**: build each `*Operation` with a scratchpad path, call
  `evaluate_operation` against a throwaway `Editor`, assert the file appears
  (save/export) or `editor.document` swapped and `editor.iomap === nothing`
  (load/import).

## Resolved (was open)

- **Export mechanism** — **project the document to text** (D2): reuse the
  domain's `*ToSyntax → SyntaxToText` printer and flatten, rather than writing
  dedicated unparsers.
- **Selection in binary** — **preserved** (D1): the snapshot clones the
  selection path into fresh Cells so a saved document reloads with its cursor.
- **Domains** — **all four** parser domains (JSON, XML, SQL, Julia) in the first
  cut.
