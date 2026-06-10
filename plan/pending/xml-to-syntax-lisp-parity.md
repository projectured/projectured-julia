# Bringing `XmlToSyntax` up to the Lisp reference's capabilities

## Origin

This plan comes from comparing the Julia
[`XmlToSyntax.jl`](../../program/src/projection/primitive/XmlToSyntax.jl)
against the original Common Lisp
[`xml-to-syntax.lisp`](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp).
The Julia port's **printer** is sound and its School-A reference mapping is
clean (keep it — see memory: prefer School-A delegation). The gap is almost
entirely on the **reader / authoring** side, plus a placeholder mechanism and a
couple of fidelity details. This plan closes that gap.

It is the XML sibling of
[json-to-syntax-lisp-parity.md](json-to-syntax-lisp-parity.md) and **shares that
plan's prerequisites** (the new structural operations §1, the event-routing
mechanism §2, and the placeholder mechanism §4). Where they overlap, this plan
*depends on* the JSON plan rather than re-specifying.

The Lisp reader gives the editor its entire XML-authoring vocabulary
([xml-to-syntax.lisp:296-448](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L296-L448)):

- **insertion reader** — on an `xml/insertion`, type `"`/`<` to **replace** the
  selection with an empty text node / element
  ([:305-314](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L305-L314)).
- **element reader** — the authoring workhorse
  ([:371-448](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L371-L448)):
  - `<` **inserts** a child element and selects its start tag
    ([:437-446](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L437-L446)).
  - `"` **inserts** a child text node and selects its value
    ([:427-436](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L427-L436)).
  - Space **inserts** an attribute and selects its name — gated on the cursor
    being in the start tag, an existing attribute, or the element node
    ([:410-426](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L410-L426)).
  - Insert **inserts** a generic `document/insertion` child and selects it
    ([:400-409](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L400-L409)).
- **attribute reader** — `=` moves the cursor from the attribute **name** to the
  attribute **value**
  ([:360-367](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L360-L367)).
- **`text/make-default-text` placeholders** — `"enter xml text"`
  ([:234](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L234)),
  `"enter xml element name"`
  ([:264](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L264)),
  `"enter xml attribute name"`
  ([:242](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L242)),
  `"enter xml attribute value"`
  ([:246](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L246)).

The Julia version has none of these. Its readers
([XmlToSyntax.jl:69](../../program/src/projection/primitive/XmlToSyntax.jl#L69),
[:82](../../program/src/projection/primitive/XmlToSyntax.jl#L82),
[:225](../../program/src/projection/primitive/XmlToSyntax.jl#L225),
[:237](../../program/src/projection/primitive/XmlToSyntax.jl#L237))
only re-target *existing* text edits (`StringReplaceRangeOperation`) and
replace-selection (clicks). `XmlInsertionToSyntaxLeaf` has **no reader at all**
([:103-114](../../program/src/projection/primitive/XmlToSyntax.jl#L103-L114)).

---

## 0. Scope, and what is delegated to other plans

This plan does **not** re-specify the shared machinery; it depends on it:

- **The two new structural operations** (`ReplaceDocumentOperation`,
  `CollectionInsertOperation` / `CollectionDeleteOperation`) are defined in
  [json-to-syntax-lisp-parity.md §1](json-to-syntax-lisp-parity.md). They are
  document-domain operations, not JSON-specific; XML reuses them verbatim. **Out
  of scope here** beyond noting the XML call sites (§1).
- **Event routing** — getting a raw `KeyPress`/`KeyDown` to a projection's
  reader so it can emit a structural operation — is
  [reader-gesture-context.md](../done/reader-gesture-context.md) +
  [text-syntax-json-typein.md](text-syntax-json-typein.md) Phase 3. **Out of
  scope here**; this plan adds XML-specific reader methods on top (§2).
- **The placeholder / default-text mechanism** is
  [json-to-syntax-lisp-parity.md §4](json-to-syntax-lisp-parity.md). XML reuses
  it for its four placeholders (§4).
- **Collapse wiring** (the dormant `collapsed` field on `XmlElement`,
  [Xml.jl:161](../../program/src/document/Xml.jl#L161)) is
  [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md). **Out of
  scope here.**

What remains — and what this plan covers:

- **A.** The XML call sites for the shared structural operations (§1).
- **B.** The XML reader command set: insertion replace, element structural
  insert (element / text / attribute / generic), attribute `=` navigation (§3).
- **C.** The four XML placeholders, via the shared mechanism (§4).
- **D.** Fidelity nits: attribute-as-inline vs. as-projection, end-tag editing
  (§5).

---

## 1. Structural operations (shared prerequisite — see JSON plan §1)

Today the only document-mutating operations are `ReplaceSelectionOperation`
([Operation.jl:50](../../program/src/common/Operation.jl#L50)),
`StringReplaceRangeOperation`
([Primitive.jl:117](../../program/src/document/Primitive.jl#L117)) and
`NumberReplaceRangeOperation`. There is **no** operation that swaps the document
at a selection, and **none** that inserts a collection element. Every Lisp XML
authoring command is built on exactly those two:

- `make-operation/replace-target nil <new-document>` — the insertion reader's
  `"`/`<` commands
  ([xml-to-syntax.lisp:308-314](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L308-L314)).
- `make-operation/sequence/replace-range` + `make-operation/replace-selection`
  in a `make-operation/compound` — the element reader's insert commands
  ([xml-to-syntax.lisp:402-446](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L402-L446)).

Both map onto the operations the JSON plan introduces:

- `ReplaceDocumentOperation(path, document)` — replace the selected element.
- `CollectionInsertOperation(path, index, items)` — insert into a `CellVector`,
  paired with a `ReplaceSelectionOperation` to move the cursor into the new node.

XML's containers for the insert case are `XmlElement.cell` (children) and
`XmlElement.attrs` (attributes), both `CellVector`
([Xml.jl:159-160](../../program/src/document/Xml.jl#L159-L160),
insert helper [Xml.jl:208-211](../../program/src/document/Xml.jl#L208-L211)).
**If the JSON plan has already landed these operations, this plan adds no new
operation types** — it only emits them from XML readers. If this plan lands
first, define them per the JSON plan's §1 spec.

---

## 2. Event routing (reuse, do not rebuild)

Same constraint as the JSON plan §2. Raw `KeyPress`/`KeyDown` enter at the
bottom of the chain (`TextToGraphics`) and the `SequentialProjection` reader
walks steps last→first until one returns non-`nothing`; unhandled keys propagate
up. Each XML command therefore becomes a
`projection_read(::Xml…ToSyntax…, iomap, ::KeyPress)` / `::KeyDown` method on the
XML projection. **This is a dependency on the typein/gesture-routing work
landing first** ([reader-gesture-context.md](../done/reader-gesture-context.md)); this
plan adds the XML reader methods.

Gating subtlety the Lisp handles and we must too: a creation command (`<`, `"`,
Space, Insert) fires **only when the selection is on the appropriate XML target**
— e.g. Space only when the cursor is in the start tag, an existing attribute, or
the element node, never while editing text inside a child
([xml-to-syntax.lisp:412-418](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L412-L418)).
Replicate that selection-state gating per command.

---

## 3. The XML reader command set

All methods live in
[`XmlToSyntax.jl`](../../program/src/projection/primitive/XmlToSyntax.jl),
alongside the existing `projection_read` methods.

### 3.1 Insertion replace (`xml/insertion->syntax/leaf` reader)

`XmlInsertionToSyntaxLeaf` currently has **no reader**
([XmlToSyntax.jl:103-114](../../program/src/projection/primitive/XmlToSyntax.jl#L103-L114)).
Add `projection_read(::XmlInsertionToSyntaxLeaf, iomap, ::KeyPress)` that, on an
insertion selection, returns a `ReplaceDocumentOperation` with a fresh document
whose initial selection is pre-placed:

| Key | Replacement document               | Lisp ref |
|-----|------------------------------------|----------|
| `"` | `XmlText("")`                      | [:306-310](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L306-L310) |
| `<` | `XmlElement("")` (empty, no attrs) | [:311-314](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L311-L314) |

The text replacement pre-selects `.cell[0:0]`; the element replacement
pre-selects `.tag[0:0]` (Julia constructors: [Xml.jl:125](../../program/src/document/Xml.jl#L125),
[Xml.jl:165](../../program/src/document/Xml.jl#L165)).

### 3.2 Element structural insert (`xml/element->syntax/node` reader)

On `XmlElementToSyntaxNode`
([XmlToSyntax.jl:225](../../program/src/projection/primitive/XmlToSyntax.jl#L225)),
add a `KeyPress`/`KeyDown` reader emitting `CollectionInsertOperation` +
`ReplaceSelectionOperation` (a small compound, or evaluate both):

| Gesture | Inserts into        | New node                | Selects        | Lisp ref |
|---------|---------------------|-------------------------|----------------|----------|
| `<`     | `.cell` (children)  | `XmlElement("")`        | new `.tag[0:0]`| [:437-446](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L437-L446) |
| `"`     | `.cell` (children)  | `XmlText("")`           | new `.cell[0:0]`| [:427-436](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L427-L436) |
| Space   | `.attrs`            | `XmlAttribute("", "")`  | new `.name[0:0]`| [:410-426](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L410-L426) |
| Insert  | `.cell` (children)  | `XmlInsertion()`        | new insertion   | [:400-409](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L400-L409) |

Notes:
- The Lisp uses a generic `document/insertion` for the Insert key and an
  `xml/insertion` for type-in flows; Julia has only `XmlInsertion`
  ([Xml.jl:50-55](../../program/src/document/Xml.jl#L50-L55)). Use `XmlInsertion`
  for both — collapse the distinction unless a generic insertion type is later
  introduced.
- Space gating per §2: only fire when the cursor is in the start tag / an
  existing attribute / the element node.
- Index is `length(e.cell)` (or `length(e.attrs)`) — append at the end, as the
  Lisp does.

### 3.3 Attribute `=` navigation — and the missing attribute projection

The Lisp models attributes as a **separate projection**
`xml/attribute->syntax/node` with its own reader, whose `=` command moves the
cursor name→value
([xml-to-syntax.lisp:360-367](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L360-L367)).

**The Julia port has no such projection.** Attributes are rendered *inline* by
the helper `_attr_node`
([XmlToSyntax.jl:337-364](../../program/src/projection/primitive/XmlToSyntax.jl#L337-L364))
inside `XmlElementToSyntaxNode`, and `XmlToSyntax`'s dispatch table has no
`XmlAttribute` entry
([XmlToSyntax.jl:366-372](../../program/src/projection/primitive/XmlToSyntax.jl#L366-L372)).
So the `=` command has nowhere natural to live. Two options:

- **(a) Handle it in `XmlElementToSyntaxNode`'s reader.** Detect that the cursor
  is in `.attrs[i].name` and return
  `ReplaceSelectionOperation(@reference attrs[i].cell[0:0])`. Smallest change;
  keeps attributes inline. **Recommended** unless attributes need to become
  independently composable.
- **(b) Introduce a real `XmlAttributeToSyntaxNode` projection** and add
  `XmlAttribute => XmlAttributeToSyntaxNode()` to the dispatch, mirroring the
  Lisp. More faithful and lets `_attr_node` move into it under School-A
  delegation, but a larger refactor of the element printer/mappers.

Pick (a) for this plan; note (b) as a possible later refactor. Record the
decision in the code comment either way.

---

## 4. Placeholder / default text (shared mechanism — see JSON plan §4)

The Lisp `text/make-default-text value placeholder …` shows a muted hint when
the field is empty. Julia hardcodes `"insert XML here"` as *content* for the
insertion ([XmlToSyntax.jl:113](../../program/src/projection/primitive/XmlToSyntax.jl#L113))
and renders empty tags/text/attrs blank. Reuse the placeholder concept the JSON
plan adds (an optional muted `placeholder` shown iff live content is empty, with
an emptiness flag the reader can test) for:

- `XmlText` → `"enter xml text"`
  ([content at XmlToSyntax.jl:100](../../program/src/projection/primitive/XmlToSyntax.jl#L100)).
- element tag → `"enter xml element name"`
  ([tag leaf at :272-276](../../program/src/projection/primitive/XmlToSyntax.jl#L272-L276)).
- attribute name → `"enter xml attribute name"`
  ([name leaf at :353-357](../../program/src/projection/primitive/XmlToSyntax.jl#L353-L357)).
- attribute value → `"enter xml attribute value"`
  ([value leaf at :358-362](../../program/src/projection/primitive/XmlToSyntax.jl#L358-L362)).
- `XmlInsertion` placeholder, replacing the hardcoded content.

---

## 5. Selection / render fidelity nits

Lower priority; each is independent and small.

### 5.1 Attribute projection (see §3.3)
Inline `_attr_node` vs. a real `XmlAttributeToSyntaxNode`. The `=` command (a)
keeps it inline; (b) is the faithful refactor. **Decide in §3.3; default (a).**

### 5.2 End-tag editing
The Lisp maps end-tag edits to `xml/end-tag`
([xml-to-syntax.lisp:390-397](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L390-L397)).
Julia renders the closing tag from the same `e.tag` field but the closing-tag
leaf (child 4) carries no cursor and `map_reference_backward`'s `child_i == 4`
falls through to `nothing`
([XmlToSyntax.jl:218-220](../../program/src/projection/primitive/XmlToSyntax.jl#L218-L220)).
Since `_apply_string_replace!(::XmlElement, "tag", …)` already updates both tags
reactively ([Xml.jl:287-290](../../program/src/document/Xml.jl#L287-L290)),
either route child-4 value edits to `.tag` too, or document that the end tag is
display-only and edited via the start tag. **Likely a one-line backward-mapper
addition; decide when implementing.**

### 5.3 Indentation parity
The Lisp indents deep element children by 2 and gives the closing tag
indentation 0 ([xml-to-syntax.lisp:279-285](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L279-L285));
Julia's body node uses `indentation = 1`
([XmlToSyntax.jl:284-291](../../program/src/projection/primitive/XmlToSyntax.jl#L284-L291)).
Cosmetic only; round-trips fine. **Defer / likely won't-do.**

---

## 6. Phasing

| Phase | Deliverable | Depends on |
|-------|-------------|-----------|
| 1 | XML insertion reader (`"`/`<` → `ReplaceDocumentOperation`) (§3.1) | JSON plan §1 op + §2 routing |
| 2 | Element structural insert: `<`, `"` children (§3.2) | Phase 1; `CollectionInsertOperation` |
| 3 | Space → attribute insert (§3.2) + `=` name→value navigation (§3.3a) | Phase 2 |
| 4 | Insert key → generic insertion child (§3.2) | Phase 2 |
| 5 | Placeholders / default text (§4) | JSON plan §4 mechanism |
| 6 | Fidelity nits (§5) as separate commits, each optional | none |

Phases 1–4 are the substance (the Lisp reader). Phase 5 is independent. Phase 6
items are individually optional.

---

## 7. Tests

There is **no** `XmlToSyntaxTest.jl` today (only
[`JsonToSyntaxTest.jl`](../../test/src/projection/JsonToSyntaxTest.jl)). Create
`test/src/projection/XmlToSyntaxTest.jl` with a `test_xml_to_syntax()` mirroring
`test_json_to_syntax()`, register it in
[`ProjecturedTest.jl`](../../test/src/ProjecturedTest.jl) (next to
`test_json_to_syntax()` at [:69](../../test/src/ProjecturedTest.jl#L69)), and add
a reader section:

- **Insertion replace**: cursor on an `XmlInsertion`, feed `KeyPress('"')` /
  `'<'`; assert a `ReplaceDocumentOperation` of the expected type with the
  pre-placed selection; apply and assert the tree + selection.
- **Element insert**: `KeyPress('<')` / `'"')` on an `XmlElement` yields a
  `CollectionInsertOperation` into `.cell` + selection into the new child; after
  apply, `length(e) == n+1` and the cursor is in the new node.
- **Attribute insert**: `KeyDown(:space)` with the cursor in the start tag adds
  an `XmlAttribute` to `.attrs` and selects its name; assert gating returns
  `nothing` when the cursor is inside a child.
- **`=` navigation**: cursor in `attrs[1].name`, `KeyPress('=')` →
  `ReplaceSelectionOperation` into `attrs[1].cell`.
- **Placeholder**: render an empty `XmlText` / `XmlElement` tag / attribute;
  assert the hint text and the emptiness flag; after typing, the hint is gone.

Run with `test_reader(xml_example)` / `test_selection(xml_example)` /
`test_repl(xml_example)` (the `xml_example` is registered at
[Examples.jl:15](../../example/src/Examples.jl#L15)); these run under
`SDL_VIDEODRIVER=dummy` like the other reader suites. Broad sweeps
(`test_readers()` / `test_selections()`) only as a final check, per
[CLAUDE.md](../../CLAUDE.md).

---

## 8. Acceptance

`run_example("xml")` supports authoring a document from scratch:

- Start on an `XmlInsertion`; press `<` → an empty element; type a tag, press
  Space → an attribute, type its name, `=`, type its value; then `<`/`"` to add
  child elements and text — matching the Lisp editor's flow.
- `test_printers()`, `test_readers()`, `test_selections()` all green, zero
  `@warn`.

---

## 9. Out of scope

- The shared structural operations themselves → [json-to-syntax-lisp-parity.md §1](json-to-syntax-lisp-parity.md).
- The event-routing / gesture mechanism → [reader-gesture-context.md](../done/reader-gesture-context.md), [text-syntax-json-typein.md](text-syntax-json-typein.md).
- The placeholder mechanism's implementation → [json-to-syntax-lisp-parity.md §4](json-to-syntax-lisp-parity.md) (this plan only lists the XML strings).
- Collapse wiring & rendering → [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md).
- Undo/redo — but `CollectionInsert/Delete` are designed with inverses so it can build on them.
- A separate `XmlAttributeToSyntaxNode` projection (§3.3b) and indentation parity (§5.3) — likely won't-do; documented for completeness.
- Escape-aware string offset mapping (same caveat the printer already carries).
- IME / non-ASCII input.

---

## 10. What to keep (the Julia version is already fine here)

Do **not** "fix" these toward the Lisp shape — they are deliberate choices:

- **School-A delegation** in the element reference mappers
  ([XmlToSyntax.jl:150-223](../../program/src/projection/primitive/XmlToSyntax.jl#L150-L223))
  vs. the Lisp's hand-reconstructed structure (see memory: prefer School-A
  delegation).
- **Multiple-dispatch readers** vs. the Lisp `typecase` operation-mapper lambdas.
- **`xml_escape_text` / `xml_escape_attr`**
  ([XmlToSyntax.jl:310-332](../../program/src/projection/primitive/XmlToSyntax.jl#L310-L332))
  — proper XML escaping.
- The single reactive `e.tag` field driving both open and close tags
  ([XmlToSyntax.jl:275](../../program/src/projection/primitive/XmlToSyntax.jl#L275),
  [:296](../../program/src/projection/primitive/XmlToSyntax.jl#L296)) — editing
  one updates both with no extra wiring.
</content>
