# A Composable Julia API for AI Editor Manipulation

Make the AI far more capable at operating the editor **without adding
manipulation MCP tools**. Keep `execute_julia_code` as the single *action* and
invest in a curated, well-documented, composable set of **Julia functions** for
manipulating the workbench and documents — opening/closing documents, editing
parts, sorting parts. The only new MCP tools are two read-only **discovery**
tools (`search_api`, `search_documentation`) so the AI finds the right function
fast.

## Why not more MCP tools

A rigid tool per manipulation (`open_workbench_document`,
`close_workbench_document`, `insert_part`, …) does not compose. The AI can only
call them one at a time with literal arguments. By contrast, a single
`execute_julia_code` over a good function library lets the AI write ordinary
Julia:

```julia
for f in readdir("/some/folder"; join=true)
    open_workbench_file!(editor, f)
end
```

Loops, conditionals, comprehensions, intermediate values, and composition with
the rest of `Projectured` all come for free. So the work is **not** new tools —
it is making the function library that `execute_julia_code` runs against
capable, discoverable, and safe to call.

The current gaps that make the AI weak today are therefore:

1. **No high-level manipulation functions.** There is no
   `open_workbench_document!`, `close_workbench_document!`, `insert_part!`,
   `delete_part!`. The AI must hand-assemble
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
> dropped, and both prompts keep the mandatory orienting resources **and** add
> search-first guidance below them. Tests: `test_search_documentation`,
> `test_search_api`, `test_search_tools_registered` in
> [McpTest.jl](../../test/src/editor/McpTest.jl) (all 60 tool + 22 resource
> tests pass).
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

### A1. `search_documentation(query; limit=8) -> String` (MCP tool) — as built

Keyword search across `guide/` markdown. Returns ranked sections, each headed by
its `resource://guide/{name}` URI (with the heading shown after an em dash) plus
a whitespace-collapsed excerpt centred on the first matching term.

- `_index_guide_sections` walks `guide/`, splitting each file on markdown
  headings into `_GuideSection(guide, heading, body)`; cached in `_GUIDE_INDEX`.
- Query terms are lowercase alphanumeric/underscore tokens (1-char noise
  dropped). Score = heading hits ×5 + body hits ×1.
- Registered as a `Tool` with `query` (required) and `limit` (optional).

### A2. `search_api(query; kind=nothing, limit=8) -> String` (MCP tool) — as built

Search the reflected module/class/function universe (`_submodules` /
`_struct_types` / `_module_functions`), cached in `_API_INDEX` as `_ApiEntry`.
Each hit: `**<kind>** \`<Module.Name>\` — <one-line doc>` plus a "read full"
line — a `resource://module|class/...` URI for modules and classes, or a
`read_function_documentation("Module", "name")` call for functions (since
per-function resources are no longer registered).

- Scoring: exact name +100, name substring +20, qualified-name substring +10,
  each doc-hit +1.
- `kind` filters to `module|class|function`.
- Compiler-generated `#` closure types are filtered out of results.

```julia
search_api("replace selection")   # → ReplaceSelectionOperation, replace_selection!
```

### A3. Keep resources for direct reads, drop the function fan-out — as built

Kept `resource://guides`, `resource://guide/*`, `resource://module/*`,
`resource://class/*/*`. **Removed the per-function `resource://function/...`
registrations** — `search_api` + `read_function_documentation(...)` covers them
and the resource list no longer fans out to hundreds of entries.

### A4. Prompts: `execute_julia_code` description + `DEFAULT_ASSISTANT_SYSTEM` — as built

Both prompt sites (sourced from the single `DEFAULT_ASSISTANT_SYSTEM` constant in
`program/src/document/Workbench.jl`) **keep** the mandatory orienting reading
list (`resource://guides`, `resource://modules`, `guide/getting-started`,
`guide/editor/reference`, `guide/editor/selection`) and **add** a search-first
block below it: use `search_api` / `search_documentation` to find a specific
function/struct/guide section; read full text with `read_resource(uri)` or
`read_function_documentation("Module", "name")`; never guess names.

> The flow the prompts encode: orient broadly (mandatory reads) → search
> narrowly → read full text → write code.

### Done — verified

- The `search_api` and `search_documentation` tools appear in the MCP tool list
  and the assistant schema (`["execute_julia_code", "search_documentation",
  "search_api", "list_resources", "read_resource"]`).
- `search_api("replace selection")` surfaces `ReplaceSelectionOperation` /
  `replace_selection!` with their locators; `search_documentation("selection")`
  returns guide sections with URIs.
- Per-function resources removed; `_doc_string` (and thus the existing
  `list_*` / `read_*` doc functions) fixed for Julia 1.12; `McpTest` updated and
  green.

---

## Part B — The editor-manipulation function library

These are ordinary, exported, **docstringed** Julia functions that the AI (and
humans) call. They live in the relevant domain modules, take `editor` (or a
document) as first argument, mutate through the existing reactive primitives,
and — where a manipulation maps to an `Operation` — go through
`evaluate_operation(editor, op)` so AI edits behave exactly like user edits and
become undoable once undo lands (`further-development.md` §3).

> Naming follows the Julia convention already in the repo (`setfn!`,
> `replace_selection!`): mutating functions end in `!`. **Every function name
> starts with a verb** — `list_workbench_documents`, not `workbench_documents`;
> `open_workbench_document!`, `search_object`, `get_selection`. Every function
> gets a docstring with a usage example, because the docstring is what `search_api`
> surfaces and what the AI reads before calling.

### B1. Workbench: open / close / list / focus documents — ✅ DONE

> **Implemented** in [Workbench.jl](../../program/src/document/Workbench.jl):
> `open_workbench_document!`, `open_workbench_file!`, `close_workbench_document!`,
> `list_workbench_documents`, `focus_workbench_document!`, backed by
> `WorkbenchOpenDocumentOperation` / `WorkbenchCloseDocumentOperation`. Re-exported
> from `Projectured`; test `test_workbench_b1`.

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
- `list_workbench_documents(editor) -> Vector` — list open documents (page,
  index, title, filename, content type) so the AI can see state before acting.
- `focus_workbench_document!(editor, which)` — activate a tab (reuse
  `SelectTabOperation` from `document/Widget.jl`).

Back open/close with operations in `WorkbenchModule`
(`WorkbenchOpenDocumentOperation`, `WorkbenchCloseDocumentOperation`).

### B2. Inspecting and searching parts — ✅ DONE

> **Implemented** in
> [ObjectToSyntax.jl](../../program/src/projection/primitive/ObjectToSyntax.jl):
> `print_object` gained `newlines::Bool`, `indent::Int`, and `filter` (value
> predicate) — `newlines`/`filter` thread through `ObjectToSyntax` /
> `ObjectNodeToSyntaxNode`, `indent` maps to the existing `SyntaxToText(indent_size=…)`
> (no `SyntaxToText` change needed). `search_object(obj, predicate)` walks any
> object and returns `ReferencePath`s (`FieldReference` for fields,
> `ElementReference` for array/`CellVector` elements, Cells transparent,
> mutable-cycle-guarded) that resolve via `evaluate_reference` and feed
> `set_selection!` / `replace_selection!`. Re-exported from `Projectured`; tests
> `test_print_object_options`, `test_search_object`.

**No string-path layer, no `describe_document`.** The AI is already writing
Julia, so it addresses parts with the existing reference DSL directly:
`@reference editing_page.elements[1].content.entries[2].value` for literals, or
`ConcreteReferencePath(ElementReference(i), …)` when the path is built dynamically
(loop variables, computed indices). Since there is no string-args entry point —
manipulation flows through `execute_julia_code`, not a string tool —
`parse_reference_path` / `format_reference_path` would only ever parse a string
the AI itself wrote. They are dead weight.

`describe_document` was also dropped: the reference path **is** the structural
path, so an explicit per-node path dump only repackages information the AI can
already get from `show` (content), plain Julia field access (`typeof`, `length`,
`doc.entries[2].value`), and `print_object` (structure). Worse, it would be a
second structure-walker running parallel to `print_object`, which already
traverses through the real projection pipeline (`ObjectToSyntax`).

Instead, sharpen the inspection primitives that already exist or fill a real gap:

#### B2a. Enhance `print_object` (in `ObjectToSyntax.jl`)

`print_object` already produces a structural rendering through the projection
chain (`ObjectToSyntax → SyntaxToText → TextToString`). Add formatting/filtering
parameters so it is actually pleasant to read (today it leaks `CellVector` /
`Array` wrapper lines, `collapsed`, and blank lines):

- `newlines::Bool` — whether each node goes on its own line (`true`) or the
  output is rendered on a single line (`false`).
- `indent::Int` — spaces per nesting level; `0` ⇒ no indentation. (Pairs with
  `newlines`: `newlines=true, indent=2` is the readable tree; `newlines=false`
  is a compact one-liner.)
- `filter` — a predicate to include/exclude nodes (and/or fields) from the
  result, so the AI can narrow a large object to the parts it cares about.
- room for further formatting options (e.g. eliding internal fields, max depth).

These thread into the `print_object` chain / `ObjectToSyntax` — **one** traversal,
no new walker.

#### B2b. Add `search_object(obj, predicate) -> Vector{ReferencePath}`

Walk any object and return **references to the parts that match** `predicate`.
This is the one genuinely new capability: it lets the AI find parts *by content*
("every value `== 42`", "every string containing `foo`", "every node of type
`JsonNumber`") and get copy-paste `@reference` paths back — something neither
`show`, `@reference`, nor `print_object` gives without hand-rolling a walker. It
composes directly with the rest:

```julia
for ref in search_object(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    set_selection!(editor.document, ref)   # or edit_text! at ref, etc.
end
```

Open design points (resolve when implementing): predicate signature (value-only
vs. `(value, ref)`); whether to offer a string/substring convenience wrapper;
return `Vector{ReferencePath}` vs. `Vector{(ref, value)}`; reuse the
`ObjectToSyntax` traversal vs. a small dedicated walk; where it lives
(`ObjectToSyntax.jl` alongside `print_object`, most likely).

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

  Keep them collection-agnostic so JSON arrays, syntax-node children, and
  workbench pages all work through one path.

> **Reordering (move/sort) is out of scope for now** — deferred until a concrete
> need arises. No `move_part!` / `sort_parts!` and no
> `CollectionMoveOperation` / `CollectionReorderOperation`.

**Open question — selection fixup after structural change.** A deleted part can
leave the global selection dangling (`further-development.md` §1, open). For v1,
after a structural op, drop any selection that no longer resolves (walk the path;
reset to nearest valid ancestor). Refine later.

### Done when

The AI, in a single `execute_julia_code` block, can: open every file in a folder
into the workbench; select a node by path; read its structure; change a string;
and insert/delete an element — all by calling named functions, all through
`evaluate_operation`, all visible in the editor.

---

## Suggested order

1. ~~**Part A (discovery)**~~ — ✅ done (search tools + prompts + resource trim).
2. ~~**B1**~~ — ✅ done (workbench open/close/list/focus, operation-backed).
3. ~~**B2**~~ — ✅ done (`print_object` `newlines`/`indent`/`filter`,
   `search_object`). No `describe_document`, no string-path helpers; the AI uses
   `@reference` + Julia field access directly.
4. **B3** — `edit_text!` (reuses §1a operation), then `insert_part!` /
   `delete_part!`; coordinate with `further-development.md` §1b so the operations
   are defined once.

## Files touched

- `program/src/editor/Mcp.jl` — ✅ `search_api` / `search_documentation` functions
  **registered as the only new MCP tools** (discovery is read-only, so tools fit;
  manipulation stays Julia-function-only), resource-fan-out trim,
  `execute_julia_code` description rewrite.
- `program/src/document/Workbench.jl` — ✅ `DEFAULT_ASSISTANT_SYSTEM` rewrite;
  ✅ B1 workbench manipulation functions + open/close operations.
- `program/src/projection/primitive/ObjectToSyntax.jl` — ✅ B2: `print_object`
  formatting/filtering params (`newlines`, `indent`, `filter`) and `search_object`.
- `program/src/common/Operation.jl` / `CollectionModule` — B3 collection
  operations + `evaluate_operation` methods + the wrapper functions.
- `program/src/document/Primitive.jl` / domain modules — B3 `edit_text!`.
- `test/src/editor/McpTest.jl` — ✅ search + B1 coverage; later B2/B3 coverage.

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
