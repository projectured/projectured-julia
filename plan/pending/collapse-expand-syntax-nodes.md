# Collapsing / expanding syntax nodes — remaining work

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

**⏳ OPEN (verified 2026-06-23):** still not wired. The file moved to
`package/domain/src/projection/primitive/JsonToSyntax.jl`. The array node
(`JsonArrayToSyntaxNode`, line 113) and the object node
(`JsonObjectToSyntaxNode`, line 133) construct `SyntaxNode(...)` without a
`collapsed=` keyword, so they fall back to the constructor default `false`
(`Syntax.jl:326-329`). The `collapsed::Bool=false` domain fields exist
(`Json.jl:171` JsonArray, `:228` JsonObject). No `json` case exists in
`CollapseRoundtripTest.jl` (only the `syntax` example is covered).

`JsonArrayToSyntaxNode` and `JsonObjectToSyntaxNode` build their `SyntaxNode`s
with a hard-coded `Cell(false)` (grep `collapsed` in
[`JsonToSyntax.jl`](../../program/src/projection/primitive/JsonToSyntax.jl)
returns no live hookup). `JsonObject` / `JsonArray` already carry a
`collapsed::Cell` field.

- Pass `getfield(j, :collapsed)` into the `SyntaxNode` constructor at both call
  sites so the node shares the source's reactive cell (original plan §7.1–§7.2).
- `ToggleCollapseOperation` already propagates up the chain unchanged and
  `evaluate_operation` resolves the innermost collapsible node generically, so no
  JSON-specific reader is needed.
- Add a `CollapseRoundtripTest` case for the `json` example.

Per-entry pair folding (`"key": …`) stays deferred — `JsonObjectEntry.collapsed`
remains dormant.

## 2. XML hookup ⏳

**⏳ OPEN (verified 2026-06-23):** still not wired. File moved to
`package/domain/src/projection/primitive/XmlToSyntax.jl`. The root element node
(`XmlElementToSyntaxNode`, `SyntaxNode(...)` at line 283) passes only
`selection=sel` — no `collapsed=`, so it defaults to `false`. `XmlElement`
already has the `collapsed::Bool` field (`Xml.jl:160`). No `xml` case in
`CollapseRoundtripTest.jl`.

Same shape for `XmlElementToSyntaxNode`
([`XmlToSyntax.jl`](../../program/src/projection/primitive/XmlToSyntax.jl) —
no live `collapsed` hookup today). `XmlElement` already has a `collapsed::Cell`.

- Pass `getfield(e, :collapsed)` into the `SyntaxNode` constructor. The collapsed
  render is the expected `<tag>…</tag>` idiom (original plan §7.3–§7.4).
- Add a `CollapseRoundtripTest` case for the `xml` example.

## 3. Verify Book inherits it ⏳

**⏳ OPEN (verified 2026-06-23):** the code half is confirmed in place —
`BookToSyntax.jl` passes `collapsed=b.collapsed` into the `SyntaxNode`
constructor at all three call sites (lines 146, 304, 481). The remaining
deliverable (a `book` roundtrip test case) is **not** present:
`CollapseRoundtripTest.jl` only covers the `syntax` example; no `book` collapse
test exists anywhere under `package/test/`.

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
