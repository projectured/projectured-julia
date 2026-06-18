# A Composable Julia API for AI Editor Manipulation

Make the AI far more capable at operating the editor **without adding
manipulation MCP tools**. Keep `execute_julia_code` as the single *action* and
invest in a curated, well-documented, composable set of **Julia functions** for
manipulating the workbench and documents — opening/closing documents, editing
parts, sorting parts. The only new MCP tools are two read-only **discovery**
tools (`search_api`, `search_documentation`) so the AI finds the right function
fast.

## Why not more MCP tools

A rigid tool per manipulation (`open_document`, `close_document`, `sort_parts`,
…) does not compose. The AI can only call them one at a time with literal
arguments. By contrast, a single `execute_julia_code` over a good function
library lets the AI write ordinary Julia:

```julia
for f in readdir("/some/folder"; join=true)
    open_document!(editor, f)
end
```

Loops, conditionals, comprehensions, intermediate values, and composition with
the rest of `Projectured` all come for free. So the work is **not** new tools —
it is making the function library that `execute_julia_code` runs against
capable, discoverable, and safe to call.

The current gaps that make the AI weak today are therefore:

1. **No high-level manipulation functions.** There is no `open_document!`,
   `close_document!`, `move_part!`, `sort_parts!`. The AI must hand-assemble
   reactive-cell mutations (`setfn!` on a `WorkbenchPage`, building
   `WorkbenchEditor`s, computing `ReferencePath`s) from primitives, guessing the
   shapes. These manipulations should exist as named functions a human would
   also use at the REPL.
2. **Discovery is enumerate-everything.** There is no search over guides/API; the
   AI lists *all* guides/modules/classes/functions and reads them whole to find
   one function. It needs to find the right function in one step.

This plan addresses both. It adds **no manipulation tools**: the only MCP
surface changes are improving `execute_julia_code`'s prompt and adding the two
read-only discovery tools (`search_api`, `search_documentation`).

---

## Part A — Documentation & API discovery (do this first) — ✅ DONE

> **Implemented.** `search_documentation` and `search_api` are live in
> [Mcp.jl](../../program/src/editor/Mcp.jl) as MCP tools (auto-flow to the
> assistant schema via `list_tools()`), the per-function resource fan-out is
> dropped, and both prompts lead with search. Tests:
> `test_search_documentation`, `test_search_api`, `test_search_tools_registered`
> in [McpTest.jl](../../test/src/editor/McpTest.jl).
>
> **Discovered during implementation:** on Julia 1.12 `Base.Docs.doc(obj)` has
> *no method* for modules, types, or functions, so the existing `_doc_string`
> helper (and therefore `list_modules`/`list_classes`/`read_*_documentation`)
> was already broken. Fixed by rewriting `_doc_string` to go through the binding
> path `Base.Docs._doc(Binding(mod, sym))` — what `@doc` lowers to — and
> rendering the resulting `DocStr`/`MultiDoc` via a new `_render_doc`. `_index_api`
> uses the accurate `(module, symbol)` form directly. Compiler-generated `#`
> closure types are filtered out of API results.

**Recommendation: yes, add search — as MCP tools.** Discovery is read-only and
does not need composition, so the tool form is right: `search_api` and
`search_documentation` are then always visible to the AI without it having to
first discover that a search *function* exists. (The manipulation API of Part B
stays as Julia functions reached through `execute_julia_code` — only discovery
is promoted to tools.) Search is the highest-leverage change: it makes every
manipulation function cheaper to use because the AI can find it in one call.

The two search functions are also plain Julia functions exported from
`McpModule`, so they remain callable at the REPL and inside
`execute_julia_code` — registering them as tools is just the extra, always-on
entry point.

### A1. `search_documentation(query; limit=8) -> String` (MCP tool)

Keyword/substring search across `guide/` markdown. Returns ranked **section
snippets with their `resource://guide/{name}#heading` URI**, not whole files.

- Index the `guide/` walk already done in
  `register_default_tools_and_resources!`, split on markdown headings into
  `(guide_name, heading_path, section_text)`. Cache in-process.
- Case-insensitive term match over heading + body; rank by frequency and heading
  hits.
- Register as a `Tool` in `register_default_tools_and_resources!` with one
  `query` (required) and optional `limit` parameter.

### A2. `search_api(query; kind=nothing, limit=8) -> String` (MCP tool)

Search the reflected module/class/function universe (the data
`_submodules` / `_struct_types` / `_module_functions` already expose in
`Mcp.jl`). Each hit: `<kind> <Module.Name> — <one-line doc> → <resource uri>`.
Match name + docstring; rank exact-name > name-substring > doc-substring.
`kind` filters to `module|class|function`. Register as a `Tool` (params:
`query` required, `kind` and `limit` optional).

```julia
search_api("open a document in the workbench")
```

### A3. Keep resources for direct reads, drop the function fan-out

Keep `resource://guides`, `resource://guide/*`, `resource://module/*`,
`resource://class/*` (search points at these URIs; `read_resource` fetches full
text). **Stop pre-registering one resource per function** — `search_api` plus a
`read_function_documentation(...)` call covers it and shrinks the resource list.

### A4. Update `execute_julia_code`'s description + `DEFAULT_ASSISTANT_SYSTEM`

Lead with discovery and the high-level API:

- "To find a function/struct/guide section, call the `search_api` /
  `search_documentation` tools first; read full text with `read_resource(uri)`."
- "Prefer the high-level workbench/part manipulation functions (find them via
  `search_api("workbench")`, `search_api("part")`) over hand-writing cell
  mutations."

Keep both prompt sites sourced from the single `DEFAULT_ASSISTANT_SYSTEM`
constant (`program/src/document/Workbench.jl`).

### Done when

- The `search_api` and `search_documentation` tools appear in the MCP tool list
  and the assistant schema; `search_api("replace selection")` surfaces
  `ReplaceSelectionOperation` / `replace_selection!` with URIs;
  `search_documentation("selection")` returns guide sections. Per-function
  resource explosion removed; `McpTest` updated.

---

## Part B — The editor-manipulation function library

These are ordinary, exported, **docstringed** Julia functions that the AI (and
humans) call. They live in the relevant domain modules, take `editor` (or a
document) as first argument, mutate through the existing reactive primitives,
and — where a manipulation maps to an `Operation` — go through
`evaluate_operation(editor, op)` so AI edits behave exactly like user edits and
become undoable once undo lands (`further-development.md` §3).

> Naming follows the Julia convention already in the repo (`setfn!`,
> `replace_selection!`): mutating functions end in `!`. Every function gets a
> docstring with a usage example, because the docstring is what `search_api`
> surfaces and what the AI reads before calling.

### B1. Workbench: open / close / list / reorder documents

> **Naming.** The word "document" is overloaded — `Document` is the abstract base
> type of *everything* in ProjecturEd. These functions therefore qualify it with
> `workbench` so the name says *what kind* of document and *where*: a document
> opened as a `WorkbenchEditor` entry in a workbench page. (Decision: keep
> "document", add the "workbench" qualifier — not a bare `open_document!` and not
> a new noun like "tab".)

Operate on `editor.document` (a `WorkbenchWorkbench`); pages are `WorkbenchPage`
whose `elements` is a `CellVector`; `WorkbenchPage` already has `setfn!`.

- `open_workbench_document!(editor, content; title="", filename="", page=:editing)`
  — wrap `content` in a `WorkbenchEditor` and append to the target page. Returns
  the entry (so the AI can keep a handle).
- `open_workbench_file!(editor, filename; page=:editing)` — load a file, pick the
  domain by extension (`json`, `xml`, `ini`, `ned`, text), and
  `open_workbench_document!`. This is the one the for-loop-over-a-folder example
  calls.
- `close_workbench_document!(editor, which; page=:editing)` — remove a
  `WorkbenchEditor` by index, title, or identity.
- `workbench_documents(editor) -> Vector` — list open documents (page, index,
  title, filename, content type) so the AI can see state before acting.
- `reorder_workbench_documents!(editor, order; page=:editing)` /
  `focus_workbench_document!(editor, which)` — reorder a page's elements /
  activate a tab (reuse `SelectTabOperation` from `document/Widget.jl`).

Back open/close/reorder with operations in `WorkbenchModule`
(`WorkbenchOpenDocumentOperation`, `WorkbenchCloseDocumentOperation`, and the
generic reorder operation from B3).

### B2. Addressing and inspecting parts

The vocabulary for "a part" is the existing `ReferencePath` / global-selection
mechanism (`guide/editor/reference.md`, `selection.md`,
`selection-deep-dive.md`). Add the minimum to make it ergonomic from code:

- `parse_reference_path(str) -> ReferencePath` and
  `format_reference_path(path) -> String`, built on the existing reference DSL
  (`@reference`, `ConcreteReferencePath`, `FieldReference`, `RangeReference`,
  `EmptyReferencePath`). String form mirrors the guides, e.g.
  `"editing_page.elements[1].content.entries[2].value"`.
- `describe_document(editor; path=nothing) -> String` — compact structural
  outline of a subtree (type, fields, collection lengths, child paths). The read
  counterpart the AI uses to *see* structure before editing.
- `get_selection(editor)` / `set_selection!(editor, path)` — thin wrappers over
  the existing `ReplaceSelectionOperation` / `replace_selection!`.

These compose: `set_selection!(editor, parse_reference_path(p))`.

### B3. Editing parts

- `edit_text!(editor, path, start, stop, text)` — replace a character range in a
  `PrimitiveString`-shaped part via the existing `StringReplaceRangeOperation`
  (`document/Primitive.jl`; §1a of `further-development.md` wires it into
  `evaluate_operation` — share that work).
- Structural edits, which need operations that **do not exist yet**
  (`further-development.md` §1b). Add minimal collection-generic operations
  (in `OperationModule` / `CollectionModule`) that mutate the target `CellVector`
  / `JsonArray` / `JsonObject` / page `elements` via `setfn!`, with thin function
  wrappers:
  - `insert_part!(editor, path, index, value)` → `CollectionInsertOperation`
  - `delete_part!(editor, path, index)` → `CollectionDeleteOperation`
  - `move_part!(editor, path, from, to)` → `CollectionMoveOperation`
  - `sort_parts!(editor, path; by=identity, order=...)` →
    `CollectionReorderOperation`. The AI can pass a `by` key or an explicit
    permutation, e.g. sort an array's elements — this is the "sort parts"
    request, expressed as composable Julia.

  Keep them collection-agnostic so JSON arrays, syntax-node children, and
  workbench pages all work through one path.

**Open question — selection fixup after structural change.** A deleted/moved
part can leave the global selection dangling (`further-development.md` §1, open).
For v1, after a structural op, drop any selection that no longer resolves (walk
the path; reset to nearest valid ancestor). Refine later.

### Done when

The AI, in a single `execute_julia_code` block, can: open every file in a folder
into the workbench; select a node by path; read its structure; change a string;
insert/delete an element; and **sort an array's elements** — all by calling named
functions, all through `evaluate_operation`, all visible in the editor.

---

## Suggested order

1. **Part A (discovery)** — search functions + prompt rewrite + resource trim.
   Immediate value, low risk, unblocks everything else.
2. **B2 + B3 `edit_text!`** — path helpers, `describe_document`, selection
   wrappers, string edit (reuses §1a operation).
3. **B1** — workbench open/close/list/reorder (reorder reuses B3's operation).
4. **B3 structural ops** — largest new-code chunk; coordinate with
   `further-development.md` §1b so the operations are defined once.

## Files touched

- `program/src/editor/Mcp.jl` — `search_api` / `search_documentation` functions
  **registered as the only new MCP tools** (discovery is read-only, so tools fit;
  manipulation stays Julia-function-only), resource-fan-out trim,
  `execute_julia_code` description rewrite.
- `program/src/document/Workbench.jl` — `DEFAULT_ASSISTANT_SYSTEM` rewrite;
  workbench manipulation functions + open/close operations.
- `program/src/common/Operation.jl` / `CollectionModule` — collection operations
  + `evaluate_operation` methods + the wrapper functions.
- Reference DSL area — `parse_reference_path` / `format_reference_path`.
- `program/src/document/Primitive.jl` / domain modules — `edit_text!` and any
  `describe_document` introspection.
- `test/src/editor/McpTest.jl` — search coverage and a workbench fixture
  exercising the manipulation functions through `execute_julia_code`.

## Open questions

- **Operation-backed vs. direct mutation.** Recommendation: operation-backed for
  structural edits and workbench open/close (want undo + user-edit parity), thin
  wrappers for the operations that already exist (selection, string range).
- **Discovery bootstrapping.** The AI learns `search_api`/`search_documentation`
  exist from the `execute_julia_code` description and system prompt — same way it
  learns about resources today. Make sure both name the search functions
  explicitly.
- **Coordination with in-flight plans.** `document-locator.md` (path → locator),
  `further-development.md` §1 (string + structural edit operations), and
  `consolidate-operations-replace.md` may define overlapping operations — reuse
  rather than duplicate.
</content>
