# Collapsing / expanding syntax nodes — remaining work

> **Status (2026-08-12): IN PROGRESS.** JSON and XML are still not wired: a
> fresh check of
> [package/json/main/JsonToSyntax.jl](../../package/json/main/JsonToSyntax.jl)
> and
> [package/xml/main/XmlToSyntax.jl](../../package/xml/main/XmlToSyntax.jl)
> finds no `collapsed` keyword in either file's `@projection_template` body
> (both projections were since rewritten to use `@projection_template` rather
> than a hand-written `projection_print`, but the missing hookup is
> unchanged). Book is confirmed wired: `BookToSyntax.jl` passes
> `collapsed=b.collapsed` at three call sites. `JsonObjectEntryToSyntaxNode`
> now exists (it shipped as part of
> [catalog-all-documents.md](catalog-all-documents.md) workstream 1), so the
> "JsonObjectEntry gets its own projection" precondition this file's item 1
> assumed no longer blocks per-entry folding, though the folding itself is
> still not wired.

The Syntax-layer foundation **shipped** — `ToggleCollapseOperation`, the
`SyntaxNodeToText` collapsed render (marker + ellipsis), the click/keyboard
readers, and the syntax-example roundtrip test. That work is recorded in
[`../done/collapse-expand-syntax-nodes.md`](../done/collapse-expand-syntax-nodes.md).

This file tracks the slices that are **not** wired yet. The originally-planned
end goal — folding a JSON object/array or an XML element through the standard
`JsonToSyntax → SyntaxToText → TextToGraphics` /
`XmlToSyntax → SyntaxToText → TextToGraphics` pipeline — does **not** work today
because the domain printers still hard-code `Cell(false)` for the node's
`collapsed` cell instead of sharing the domain field.

## 1. JSON hookup ⏳

**⏳ OPEN (verified 2026-08-12):** still not wired. The file is
[package/json/main/JsonToSyntax.jl](../../package/json/main/JsonToSyntax.jl).
The array node (`JsonArrayToSyntaxNode`) and the object node
(`JsonObjectToSyntaxNode`) now build their `SyntaxNode` through a
`@projection_template` (the projections were rewritten to use that macro
since this plan was written) that omits the `collapsed=` keyword entirely, so
they fall back to the `SyntaxNode` constructor default `false`
([package/syntax/main/Syntax.jl](../../package/syntax/main/Syntax.jl),
`collapsed::Bool = false` at line 557). The `collapsed::Bool = false` domain
fields exist in
[package/json/main/Json.jl](../../package/json/main/Json.jl) (line 63
`JsonArray`, line 83 `JsonObject`). No `json` case exists in
`CollapseRoundtripTest.jl` (only the `syntax` example is covered).

`JsonArrayToSyntaxNode` and `JsonObjectToSyntaxNode` do not mention
`collapsed` anywhere in
[`JsonToSyntax.jl`](../../package/json/main/JsonToSyntax.jl) — grepping the
file for `collapsed` returns zero matches, confirming no live hookup.
`JsonObject` / `JsonArray` already carry a `collapsed::Cell` field.

- Pass `getfield(j, :collapsed)` into the `SyntaxNode` constructor at both call
  sites so the node shares the source's reactive cell (original plan §7.1–§7.2).
- `ToggleCollapseOperation` already propagates up the chain unchanged and
  `evaluate_operation` resolves the innermost collapsible node generically, so no
  JSON-specific reader is needed.
- Add a `CollapseRoundtripTest` case for the `json` example.

Per-entry pair folding (`"key": …`) stays deferred — `JsonObjectEntry.collapsed`
remains dormant.

## 2. XML hookup ⏳

**⏳ OPEN (verified 2026-08-12), and the shape changed since this plan was
written.** File is
[package/xml/main/XmlToSyntax.jl](../../package/xml/main/XmlToSyntax.jl).
`XmlElementToSyntaxNode` now builds its output through a
`@projection_template` that wraps `[tag_leaf, attrs_node, body_node,
close_leaf]` in a **`SyntaxConcatenation`**, not a `SyntaxNode` — the two
inner `SyntaxNode(...)` calls (`attrs_node`, `body_node`) pass no
`collapsed=` either, so both default to `false`. `SyntaxConcatenation` has no
`collapsed` field at all (only `SyntaxNode` and `SyntaxCollapsible` carry
one; every other `SyntaxCompound` reports `syntax_collapsed(...) = false`
unconditionally). Wiring the whole element's collapse therefore needs either
a `collapsed` field added to `SyntaxConcatenation`, or the element template
restructured to build a `SyntaxNode`/`SyntaxCollapsible` instead — a real
design decision this plan did not anticipate. `XmlElement` already has the
`collapsed::Bool` field
([package/xml/main/Xml.jl](../../package/xml/main/Xml.jl), line 56). No `xml`
case in `CollapseRoundtripTest.jl`.

- Pass `getfield(e, :collapsed)` through to a node that can carry it — either
  a new `collapsed` field on `SyntaxConcatenation`, or by rebuilding the
  element template around `SyntaxNode`/`SyntaxCollapsible`. The collapsed
  render is the expected `<tag>…</tag>` idiom (original plan §7.3–§7.4).
- Add a `CollapseRoundtripTest` case for the `xml` example.

## 3. Verify Book inherits it ⏳

**⏳ OPEN (verified 2026-08-12):** the code half is confirmed in place —
[package/book/main/BookToSyntax.jl](../../package/book/main/BookToSyntax.jl)
passes `collapsed=b.collapsed` into the `SyntaxNode` constructor at all three
call sites (lines 177, 348, 508). The remaining deliverable (a `book`
roundtrip test case) is **not** present:
[package/substrate/test/editor/CollapseRoundtripTest.jl](../../package/substrate/test/editor/CollapseRoundtripTest.jl)
only covers the `syntax` example; no `book` collapse test exists anywhere
under `package/*/test/`.

`BookBook`/`BookChapter`/`BookList` already pass `b.collapsed` into the
`SyntaxNode` constructor, so Book should fold for free now that `SyntaxNodeToText`
honours the field. Confirm with a manual `run_example("book")` + a roundtrip test
case; no code change expected.

## 4. Followups (deferred — original plan §10)

- **Leaf folding** ("…rest…" for long strings) — `SyntaxLeaf.collapsed` exists
  but no printer reads it.
- **JSON object-entry folding** (`"key": …`).
- **Persistent fold state** across reloads (needs a serializer).
- **Gutter UI** with triangle widgets (a higher-order projection wrapping
  `SyntaxToText`); this plan only added the inline marker/ellipsis.
- **"Fold all at depth N"** command — trivial once `ToggleCollapseOperation` /
  the resolver exist.
- **Filesystem marker-click** hookup.
- A live-editor smoke test that clicking the ellipsis expands, once
  [`json-navigation-and-clicks`](../done/json-navigation-and-clicks.md)-style
  mouse-click testing is re-enabled.

## Related

- Foundation (done): [`../done/collapse-expand-syntax-nodes.md`](../done/collapse-expand-syntax-nodes.md).
- The JSON/XML parity plans explicitly delegate collapse wiring here
  ([`../done/json-to-syntax-lisp-parity.md`](../done/json-to-syntax-lisp-parity.md) §0,
  [`xml-to-syntax-lisp-parity.md`](xml-to-syntax-lisp-parity.md) §0).
