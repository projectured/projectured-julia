# Fold collection logic into collection types; drop document-level forwards

## Motivation

Many document types carry a block of `Base` collection methods (`length`, `isempty`,
`getindex`, `firstindex`, `lastindex`, `iterate`, `eachindex`, plus mutators
`push!`/`insert!`/`setindex!`/`deleteat!`/`pop!`) that merely **forward to a
`CellVector` field**. This is copy-pasted across at least ten document types.

Almost all of it is pure pass-through: `CellVector` already implements the full
collection interface ([Collection.jl:54-108](../../program/src/document/Collection.jl#L54-L108)),
and its read methods already unwrap the stored `Cell` to the value. The *only*
real logic in the forwards is that the document-level mutators wrap a plain value
in `Cell(...)` before delegating, because `CellVector.push!`/`insert!` currently
require an already-wrapped `Cell`.

**Plan:** move that wrapping into `CellVector` itself, then delete the
document-level forwards entirely. Callers access the `CellVector` field directly
(`node.children[i]`, `for c in node.children`, `push!(node.children, x)`), since
the field *is* the collection and now holds all the logic.

> Decision (2026-06-22): we are **dropping the forwards entirely**, not
> regenerating them via a `@forward_collection` macro. Rationale: the macro keeps
> document-as-collection ergonomics but preserves the conceptual confusion that a
> document "is" a collection. Accessing the `CellVector` field directly makes the
> data model explicit and puts all collection logic in one place.

## Why this is lower-risk than it looks

The one piece of **generic** code that walks documents as collections —
[`_walk` in Searching.jl:107-114](../../program/src/projection/generic/Searching.jl#L107-L114)
— already special-cases `CellVector` and otherwise recurses via
`fieldnames`/`getfield`. It does **not** rely on document-level forwards. So only
**type-specific** call sites (`node[i]`, `for c in node`, `length(node)`,
`push!(node, x)` where `node` is a concrete document) need updating, and the
per-domain test suites cover them.

## Cross-repo ordering

`omnetpp-pred` depends on `Projectured` (path dependency) and uses this same
`CellVector`. **Phase 0 of this plan must land before** the companion plan
`omnetpp-pred/plan/pending/drop-collection-forwards.md` can drop its Ini/Ned
forwards. The per-document phases here (1+) are independent of omnetpp-pred.

---

## Phase 0 — CellVector (and siblings) absorb the wrapping logic

In [Collection.jl](../../program/src/document/Collection.jl):

- [ ] `Base.push!(cv::CellVector, xs...)` — replace the `cells::Cell...` signature
      with a wrap-or-passthrough version:
      `_wrap(x) = x isa Cell ? x : Cell(x)`, push `_wrap(x)` for each `x`.
      A `Cell` is passed through unchanged so **identity-preserving moves still
      work**; a plain value is wrapped. No ambiguity: a `Cell` is never stored
      *as a value* in this codebase, so the single method is unambiguous.
- [ ] `Base.insert!(cv::CellVector, i::Integer, x)` — same wrap-or-passthrough
      (currently requires `cell::Cell`).
- [ ] `setindex!` already has both a value path (`elems[i][] = val`, writes into
      the existing cell) and a `Cell` path (replaces the cell). Leave both.
- [ ] Confirm `pop!`/`deleteat!` need no change (they already return/operate on
      values).
- [ ] `CellMatrix` / `CellTable`: they already expose `val` and `Cell` variants of
      `setindex!` and have no `push!`. Audit for any document type that forwards a
      mutator to them; add wrapping only if a Phase 1+ removal needs it. Likely
      no change required.
- [ ] `ListNode` is **out of scope**: it is a linked list with its own semantics;
      its `push!(value)` already wraps internally and it is not a `CellVector`
      forward target.
- [ ] Verify: `test_cell()` and a collection-touching example
      (e.g. `test_example(json_example)`).

Commit: "CellVector: absorb Cell-wrapping into push!/insert! (Phase 0)".

---

## Phase 1+ — Remove forwards per document type, fix call sites

For each type below: delete the listed forwarding `Base` methods, then update the
type-specific call sites to go through the field. One commit per type (or per
file), each verified with the narrowest covering test.

**Removable forwards (pure CellVector pass-through):**
`length`, `isempty`, `getindex(::Integer)`, `firstindex`, `lastindex`,
`iterate`, `eachindex`, `push!`, `insert!`, `setindex!(::Integer)`,
`deleteat!`, `pop!`.

| Type | File | Field | Has mutator forwards? | Test |
|------|------|-------|-----------------------|------|
| `SyntaxNode` | [Syntax.jl:329-360](../../program/src/document/Syntax.jl#L329) | `children` | yes | `test_syntax()` / `test_json_to_syntax()` |
| `JsonArray` | [Json.jl:305-343](../../program/src/document/Json.jl#L305) | `elements` | yes | `test_json()` |
| `XmlElement` | [Xml.jl:184-218](../../program/src/document/Xml.jl#L184) | `children` (also `attrs`) | yes | `test_xml()` |
| `FileSystemDirectory` | [FileSystem.jl:54-66](../../program/src/document/FileSystem.jl#L54) | `elements` | push! only | filesystem example |
| `EvaluatorToplevel` | [Evaluator.jl:92-101](../../program/src/document/Evaluator.jl#L92) | `elements` | push! only | evaluator example |
| `Workspace` | [Workspace.jl:46-52](../../program/src/document/Workspace.jl#L46) | `folders` | no | workspace example |
| `ConversationDraft` | [Conversation.jl:188-194](../../program/src/document/Conversation.jl#L188) | `parts` | no | conversation example |
| `ConversationConversation` | [Conversation.jl:204-210](../../program/src/document/Conversation.jl#L204) | `turns` | no | conversation example |
| `ConversationTurn` | [Conversation.jl:219-225](../../program/src/document/Conversation.jl#L219) | `parts` | no | conversation example |
| `TextText` | [Text.jl:251-282](../../program/src/document/Text.jl#L251) | `elements` (`CollectionDocument`) | yes | `test_syntax_to_text()` |
| `FormulaEnvironment` | [Formula.jl:152-157](../../program/src/document/Formula.jl#L152) | `formulas` | no | formula example |

**Per-type procedure:**

1. Delete the forwarding methods from the document file.
2. `grep` the codebase for type-specific collection usage of that document and
   rewrite:
   - `node[i]` → `node.children[i]`
   - `for c in node` → `for c in node.children`
   - `length(node)` / `isempty(node)` → `length(node.children)` / …
   - `push!(node, x)` / `insert!(node, i, x)` → `push!(node.children, x)` / …
   - `eachindex(node)` / `firstindex(node)` / `lastindex(node)` → field form
3. Run the narrowest covering test from the table.
4. Commit.

**Suggested order** (leaf domains first, to surface call-site patterns cheaply):
`FormulaEnvironment` → `Workspace` → `Conversation*` → `EvaluatorToplevel` →
`FileSystemDirectory` → `JsonArray` → `XmlElement` → `SyntaxNode` → `TextText`.
`SyntaxNode` and `TextText` are highest-traffic; do them once the pattern is
proven.

---

## MUST KEEP — do not remove these (not CellVector pass-through)

- **Scalar value accessors** — `getindex` on `JsonNull`/`JsonBool`/`JsonNumber`/
  `JsonString` ([Json.jl:283-286](../../program/src/document/Json.jl#L283)) and
  `XmlAttribute`/`XmlText` ([Xml.jl:96,128](../../program/src/document/Xml.jl#L96)).
  These unwrap a scalar field, unrelated to collections.
- **`JsonObject`** — key-based `getindex(j, key::AbstractString)`, the pair-style
  `iterate`, and `setindex!(j, v, key)`
  ([Json.jl:358-389](../../program/src/document/Json.jl#L358)) are domain logic
  over the `entries` CellVector, not pass-through. Its plain `length`/`isempty`
  forwards *may* be removed (pass-through), but keep the key/pair semantics.
- **`XmlElement` name lookup** — `getindex(e, name::AbstractString)`
  ([Xml.jl:220](../../program/src/document/Xml.jl#L220)). Keep.
- **`PrimitiveString`** ([Primitive.jl:223-236](../../program/src/document/Primitive.jl#L223))
  forwards to a `String`, not a `CellVector` (char-level indexing). Out of scope.
- **`ListNode`** collection methods — linked-list semantics, out of scope.

---

## Verification (final)

- After each phase: the narrowest covering test only (per repo CLAUDE.md).
- After all phases land: a broad sweep — `test_printers()` / `test_readers()` /
  `test_text_navigations()` / `test_repls()` — to catch any missed call site.
- Then unblock and execute `omnetpp-pred/plan/pending/drop-collection-forwards.md`.

## Notes / decisions discovered during implementation

**Status: COMPLETE.** All phases done on branch `fold-collection-methods`.

- **Phase 0 done** (`CellVector` `push!`/`insert!` wrap-or-passthrough via `_wrap_cell`).
- **Phase 1+ done** for all 11 types (one commit each, leaf-first):
  FormulaEnvironment, Workspace, Conversation{Draft,Conversation,Turn},
  EvaluatorToplevel, FileSystemDirectory, JsonArray/JsonObject, XmlElement,
  SyntaxNode, TextText. Call sites routed through the field across
  document/, editor/ (ConversationEditor, WorkbenchAssistant), and
  projection/primitive/ (Book/FileSystem/Formula/Json/Text/Workspace/Xml ToSyntax),
  plus the affected tests.

### Deviation — `JsonArray.getindex`/`size` retained (justified, not a miss)
`evaluate_reference` (reference/Reference.jl:471) descends a `RangeReference`
step with `document[step.start+1]`. For SyntaxNode/FileSystemDirectory/etc.,
references descend through a **field** step first (`.children` → CellVector,
which keeps `getindex`), so the document itself is never directly indexed.
But the **JSON reference convention indexes the array directly** (`arr[i]`, no
`.elements` field step), so `Base.getindex(::JsonArray, ::Integer)` and
`Base.size(::JsonArray)` are **load-bearing** for reference/Focusing evaluation,
not pass-through boilerplate. They are kept (documented in Json.jl). Fully
"dropping" them would require rewriting the JSON reference/selection convention
— out of scope here.

### MUST-KEEP confirmed present
`JsonObject` key getindex/pair-iterate/setindex!(key); `XmlElement` name lookup;
scalar getindex on Json/Xml primitives; PrimitiveString; ListNode.

### Verification (worktree vs. base a236a88 — exact parity, ZERO regressions)
All remaining test failures are **pre-existing on the base** (verified by running
the same test on the clean checkout):
- `PrimitiveReplaceRange` — 7 errors (selection-shape assertion in test helper).
- `sql_table` — printer 5 fails, reader 225 fails (`MethodError(length, Cell(...))`).
- `SyntaxTreeSelection` — 10 fail + 3 error (deferred whole-element-selection feature).
- `TextNavigation` — 5 fails (conversation_editor, dvdrental_catalog, filesystem,
  formula, navigator — structural `state_count == 0`, no swallowed exceptions).

Green on our branch (matching base): `test_cell`, `test_documents` (384 pass),
`test_printers` (165711 pass), `test_readers` (18675 pass),
`test_text_navigations` (4906 pass), and targeted projection tests
(json_to_syntax, syntax_to_text, xml_to_syntax, filesystem_to_syntax,
formula_to_syntax, conversation_editor, collection, copying, clipboard).

Two missed TextText call sites in test files were found and fixed during
verification (iterating `.output` → `.output.elements` in
FileSystemToSyntaxTest.jl and SyntaxTreeSelectionTest.jl).

### Follow-up (omnetpp-pred)
The companion plan `omnetpp-pred/plan/pending/drop-collection-forwards.md`
depends on Phase 0. omnetpp-pred consumes `Projectured` via a path dependency to
the **main** checkout, so this branch must be integrated to main (or omnetpp-pred
temporarily pointed at this worktree) before that plan can be executed/tested.
