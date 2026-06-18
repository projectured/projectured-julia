# Capable MCP Editor Tools + Documentation/API Search

Make the AI-facing MCP surface able to *operate the editor*, not just run raw
Julia. Add high-level, discoverable tools for opening/closing documents in the
workbench, addressing and editing parts of a document, and reordering parts —
plus a search mechanism over guides and API so the AI finds the right call fast
instead of enumerating everything.

## Motivation

Today the MCP/assistant surface (`program/src/editor/Mcp.jl`,
`program/src/editor/ToolRegistry.jl`) exposes exactly **one** action,
`execute_julia_code`, plus a flat set of read-only documentation resources
(`resource://guides`, `resource://modules`, `resource://class/...`,
`resource://function/...`). Two problems follow:

1. **Manipulation is all-or-nothing.** Every edit — opening a document, moving
   the selection, changing a string, reordering elements — is a Julia program
   the model must author against an API it can only learn by reading. It guesses
   names, builds malformed reactive-cell mutations, and bypasses the
   `evaluate_operation` path the interactive editor uses, so its edits don't
   behave like real user edits.

2. **Discovery is enumerate-everything.** There is no search. The model lists
   *all* guides/modules/classes/functions and reads them whole. With the current
   module/class/function fan-out that is a large, low-signal context dump, and it
   still has to read entire guides to find one sentence.

The fix is a layer of **named, validated, operation-backed tools** for the
common editor manipulations, addressed through the existing
reference/selection mechanism, plus a **search tool** over docs and API.

This plan touches only the tool/registry/MCP layer and adds operations where a
manipulation has no existing operation. It does **not** rebuild the projection
pipeline. New tools register through `ToolRegistry`, so they are automatically
available to both the external MCP client and the in-editor `WorkbenchAssistant`
(see `assistant_tool_schemas` / `dispatch_assistant_tool` in
`program/src/editor/WorkbenchAssistant.jl`).

## Design principles

- **Tools map to operations, not to cell pokes.** Where an editor manipulation
  can be expressed as an `Operation`, the tool builds the operation and calls
  `evaluate_operation(editor, op)`. This keeps AI edits identical to user edits,
  reuses selection-fixup logic, and makes them undoable once undo lands
  (`plan/tentative/further-development.md` §3). `execute_julia_code` stays as the
  escape hatch for everything not yet covered.
- **Parts are addressed by reference path.** "Edit this part", "sort these
  parts", "select that node" all need a way to name a part. The existing
  `ReferencePath` / global-selection mechanism is exactly that vocabulary
  (`guide/editor/reference.md`, `guide/editor/selection.md`,
  `guide/selection-deep-dive.md`). Tools accept and return paths as compact
  strings; a single parse/format helper pair is the only new addressing code.
  This dovetails with the pending `DocumentLocator` abstraction
  (`plan/pending/document-locator.md`) — when that lands, the path argument
  becomes one locator mode.
- **Tools are self-describing and registered in one place.** Each new tool is a
  `Tool(name, description, parameters, handler)` registered in
  `register_default_tools_and_resources!`. No second source of truth.
- **Honest scope.** Some manipulations (string edits, selection, tab/scroll,
  show/hide) already have operations. Structural insert/delete/reorder do **not**
  yet exist (`further-development.md` §1b) — this plan adds the minimal
  operations needed for the "sort/reorder/insert/delete parts" tools, scoped to
  collection-shaped documents (`CellVector`, `JsonArray`, `JsonObject`,
  workbench pages).

---

## Part A — Documentation & API search (do this first)

**Recommendation: yes, add a search mechanism.** It is the highest-leverage,
lowest-risk change and it makes every subsequent tool cheaper to use, because the
model can find the operation/struct/guide section it needs in one call.

### A1. `search_documentation` tool

Keyword/substring search across all guide markdown files. Returns ranked
**snippets with their `resource://guide/{name}` URI and heading context**, not
whole files.

- Index: the same `guide/` walk already done in
  `register_default_tools_and_resources!`. Build an in-memory index of
  `(guide_name, heading_path, section_text)` by splitting each guide on markdown
  headings. Cache it (rebuild only if missing).
- Query: case-insensitive term matching over heading + body; rank by term
  frequency and heading hits. Return top N (default 8) as:
  `resource://guide/{name}#heading — <one-line excerpt with match>`.
- Parameters: `query` (string, required), `limit` (number, optional).

### A2. `search_api` tool

Search the reflected module/class/function universe (the same data
`_submodules` / `_struct_types` / `_module_functions` already expose).

- Index entries: every module, struct, and function with its kind, fully
  qualified name, first-paragraph doc, and its `resource://...` URI.
- Match on name and docstring; rank exact-name > name-substring > doc-substring.
- Return each hit as: `<kind> <Module.Name> — <one-line doc> → <resource uri>`.
- Parameters: `query` (string, required), `kind` (string, optional:
  `module|class|function`), `limit` (number, optional).

### A3. Trim the resource fan-out

Once search exists, the giant per-function resource registration becomes
redundant. Keep the `resource://guide/*`, `resource://module/*`,
`resource://class/*` resources (they are addressable URLs search points at), but
**stop pre-registering one resource per function** — `search_api` plus
`read_function_documentation` (exposed as a small tool) covers it. This shrinks
the resource list the client must hold.

### A4. Update the tool/system prompt

Rewrite the `execute_julia_code` description and `DEFAULT_ASSISTANT_SYSTEM`
(`program/src/document/Workbench.jl`) to lead with **search**: "To find an API
or guide section, call `search_api` / `search_documentation` first; read full
text with `read_resource`. Prefer the high-level editor tools below over writing
raw Julia." Keep the two prompt sites sourced from the single constant.

### Done when

- `search_documentation("selection")` returns guide sections with URIs.
- `search_api("replace selection")` surfaces `ReplaceSelectionOperation` and
  `replace_selection!` with their resource URIs.
- Per-function resource explosion removed; `McpTest` updated.

---

## Part B — Workbench manipulation tools

Operate on `editor.document`, which for the IDE is a `WorkbenchWorkbench`
(`program/src/document/Workbench.jl`). Pages are `WorkbenchPage` whose
`elements` is a `CellVector`; open documents are `WorkbenchEditor(title,
filename, content)`. `WorkbenchPage` already has `setfn!(page, f)` to rebuild its
elements.

### B1. `list_open_documents`

Walk the four pages and return a table: index, page (`navigation|editing|
information|control`), panel type, `title`, `filename`. Lets the model see what
exists before acting. Read-only.

### B2. `open_document`

Open a document as a `WorkbenchEditor` in a page (default: editing page).

- Parameters: `source` (one of: a `filename` to load, or a `kind` +
  `content`/empty to create a new domain document — start with the kinds that
  have a clear constructor: `json`, `xml`, `text`, `ini`, `ned`), `title`
  (optional), `page` (optional, default `editing`).
- Handler builds the inner document, wraps in `WorkbenchEditor`, and appends to
  the target page via `setfn!`. Returns the new entry's index/path.
- Back this with a `WorkbenchOpenEditorOperation(page, editor_entry)` +
  `evaluate_operation` so it matches the operation-backed principle and is
  undoable later. (Operation lives in `WorkbenchModule`.)

### B3. `close_document`

Remove a `WorkbenchEditor` from its page by index or title.
Back with `WorkbenchCloseEditorOperation(page, index)`.

### B4. `reorder_documents` / `focus_document`

- `reorder_documents(page, order)` — reorder a page's elements (the "sort parts"
  request at the workbench level). Back with the generic reorder operation from
  Part C applied to the page's `elements`.
- `focus_document(index|title)` — set the active tab. There is already
  `SelectTabOperation` (`document/Widget.jl`); resolve the page's tabbed-pane and
  emit it, or set the page `selection`.

### Done when

- The model can list, open, close, and reorder editors in the workbench and see
  the change rendered, all through operations.

---

## Part C — Addressing and editing parts of a document

This is the core "edit parts, sort parts" capability, expressed against any
document via reference paths.

### C1. Path helpers (shared addressing)

Add a parse/format pair so tools can take/return paths as strings:

- `parse_reference_path(str) -> ReferencePath` — e.g.
  `"editing_page.elements[1].content.entries[2].value"`.
- `format_reference_path(path) -> String`.

Build on the existing reference DSL (`@reference`, `ConcreteReferencePath`,
`FieldReference`, `RangeReference`, `EmptyReferencePath` — already imported in
`McpTest`) so the format matches what the selection guides document. This is the
one new piece of addressing code; everything else reuses it.

### C2. `describe_document`

Given an optional path (default: whole document or current selection), return a
compact structural outline of that subtree: type, fields, child collection
lengths, and the reference path of each child. This is what lets the model *see*
structure before editing — the read counterpart to the edit tools. Reuse
`WorkbenchDescriptor`-style introspection / the reflection helpers.

### C3. `get_selection` / `set_selection`

- `get_selection` — format the document's current selection path as a string.
- `set_selection(path)` — parse and apply via the existing
  `ReplaceSelectionOperation` / `replace_selection!`. (Already fully supported —
  this is just a thin, named wrapper.)

### C4. `edit_text`

Replace a character range in a `PrimitiveString`-shaped part.

- Parameters: `path`, `start`, `end`, `text`.
- Back with the existing `StringReplaceRangeOperation`
  (`document/Primitive.jl`); resolve the target by path. (Already declared;
  `further-development.md` §1a wires it into `evaluate_operation` — coordinate so
  this tool and that work share the same operation.)

### C5. Structural part edits — `insert_part`, `delete_part`, `move_part`,
`sort_parts`

These need operations that do **not** exist yet (`further-development.md` §1b).
Add minimal, collection-generic operations in `OperationModule` /
`CollectionModule`, evaluated by mutating the target `CellVector` (or
`JsonArray`/`JsonObject`/page `elements`) via `setfn!`:

- `CollectionInsertOperation(path, index, value)` — insert a child at `index`.
- `CollectionDeleteOperation(path, index)` — remove the child at `index`.
- `CollectionMoveOperation(path, from, to)` — move one child (used by
  `move_part` and by workbench `reorder_documents`).
- `CollectionReorderOperation(path, order)` — apply a full permutation; this is
  the backing for `sort_parts` (the model computes the desired order, e.g.
  sorted by a key, and submits the permutation).

Tools (`insert_part`, `delete_part`, `move_part`, `sort_parts`) parse the path,
build the operation, and call `evaluate_operation`. Keep them
collection-agnostic so JSON arrays, syntax-node children, and workbench pages all
work through the same path.

**Open question — selection fixup after structural change:** when a part is
deleted/moved, the global selection path may dangle. `further-development.md` §1
flags this as unresolved. For v1, after a structural op, clear any selection that
no longer resolves (walk the path; if a step is missing, reset to the nearest
valid ancestor). Refine later.

### Done when

- The model can, against a JSON document opened in the workbench: select a node,
  read its structure, change a string, insert/delete an element, and **sort the
  elements of an array** — each via a named tool, each applied through
  `evaluate_operation`, each visible in the editor.

---

## Suggested order

1. **Part A (search)** — immediate value, unblocks discovery, low risk.
2. **Part C1–C4** — path helpers, `describe_document`, selection wrappers,
   `edit_text` (the last reuses the §1a operation work).
3. **Part B** — workbench open/close/reorder (depends on C's reorder op for B4).
4. **Part C5** — structural operations (the largest new-code chunk; coordinate
   with `further-development.md` §1b so the operations are defined once).

## Files touched

- `program/src/editor/Mcp.jl` — new search functions + tool registrations,
  trim function-resource fan-out, prompt rewrite.
- `program/src/editor/ToolRegistry.jl` — no shape change; new tools register
  through it (verify `search`/structured results serialize as strings).
- `program/src/document/Workbench.jl` — `DEFAULT_ASSISTANT_SYSTEM` update;
  `WorkbenchOpenEditorOperation` / `WorkbenchCloseEditorOperation`.
- `program/src/common/Operation.jl` (or `CollectionModule`) — the four
  collection operations + `evaluate_operation` methods.
- New small module/file for `parse_reference_path` / `format_reference_path` if
  one doesn't already exist near the reference DSL.
- `test/src/editor/McpTest.jl` — coverage for search and each new tool against a
  small workbench fixture.

## Open questions

- **Operation-backed vs. direct mutation.** Backing every tool with an
  `Operation` is the clean path (matches user edits, future undo) but is more
  code than poking cells. Recommendation: operation-backed for B/C5 (structural,
  want undo), thin wrappers for already-existing operations in C3/C4, and accept
  that `open_document`'s document construction is plain Julia inside the handler.
- **Result format.** MCP tool handlers must return `String`. Structured results
  (tables, search hits) are formatted as markdown text. Good enough; revisit if a
  client wants JSON.
- **Which page is "the" document set.** Tools default to the editing page but
  accept an explicit `page` argument; `list_open_documents` shows all pages so
  the model can target precisely.
- **Coordination with in-flight plans.** `document-locator.md` (path → locator),
  `further-development.md` §1 (string + structural edit operations), and
  `consolidate-operations-replace.md` may define overlapping operations — reuse
  rather than duplicate when implementing.
</content>
</invoke>
