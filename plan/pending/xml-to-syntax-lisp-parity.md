# Bringing `XmlToSyntax` up to the Lisp reference's capabilities

> **Status (2026-08-12): IN PROGRESS.** Phases 1-4 and Phase 6 are done;
> Phase 5 (placeholders) is the only remaining work, and it is genuinely
> unblocked. **Architectural note, found while re-verifying (2026-08-09
> restructure and later domain-kit work moved the reader commands):** the XML
> authoring reader command set described section-by-section below (insertion
> replace, element/text insert, attribute insert, `=` navigation) has been
> **rewritten onto the `@domain`/`@gestures` domain-insertion-kit machinery**
> (the same kit [text-domain-kit.md](text-domain-kit.md) documents for the
> Text domain). It now lives in
> [`package/xml/main/Xml.jl`](../../source/xml/Xml.jl) — `@gestures
> XmlDocument` (lines 103-107: `"`/`<`/`@` insertion replace, plus an `@`
> attribute-replace case beyond the original Lisp scope) and `@gestures
> XmlElement` (lines 128-133: `<`/`"` element/text insert, `KeyDown(:insert)`
> generic insert, `KeyDown(:space)` attribute insert, `KeyPress('=')` name→value
> navigation) — calling shared generic helpers
> (`replace_selected_document`, `append_insertion_operation`, `move_to_field`,
> all in `package/domain/main/Domain.jl`) instead of the bespoke
> `ReplaceDocumentOperation`/`CollectionInsertOperation` structural operations
> §1 below specifies. Those two operation types (and `CollectionDeleteOperation`)
> **no longer exist as named types anywhere in the tree** — insert/delete is now
> expressed as a splice through the generic `ReplaceReferencedValueOperation` +
> `RangeReferenceStep` (`package/kernel/main/operation/Operations.jl`), which
> subsumes what §1 asked for. The **feature is still delivered** — same
> keystrokes, same behavior — just through a newer, more generic mechanism than
> this plan specifies; `XmlToSyntax.jl` itself now carries almost none of the
> reader logic the sections below cite line numbers in (it keeps the printer,
> `map_reference_forward`, and a click-selection `read_intent`). The detailed
> per-section "✅ VERIFIED (2026-06-23)" citations below describe an
> intermediate implementation that has since been superseded by this
> refactor; treat their line numbers as historical, not current, and use this
> banner as the up-to-date picture. Covered by
> [`XmlToSyntaxTest.jl`](../../test/xml/projection/XmlToSyntaxTest.jl)
> (44 `@test`s including a new `test_xml_override_gestures()` not in the
> original plan) — not re-run here, but the code exists.
>
> **Phase 5 (placeholders) is the only remaining work**, and it is more
> unblocked than the last check found: the JSON plan §4 placeholder mechanism
> has not just landed, it is now a genuinely **shared, exported** helper —
> `hinted_text` (renamed from the JSON-local `_hinted_text`) in
> [`package/text/main/Text.jl:177`](../../source/text/Text.jl), used by
> JSON (`package/json/main/JsonToSyntax.jl`, 6 call sites) but by **zero** call
> sites in `package/xml/main/XmlToSyntax.jl`. Separately, the top-level
> `XmlInsertion` placeholder problem this section originally described (a
> hardcoded `"insert XML here"` string) is **already gone** — `XmlToSyntax.jl`
> no longer hardcodes any such string; `XmlInsertionToSyntaxLeaf() =
> DomainInsertionToSyntaxLeaf(XmlDocument)` now renders through the same
> generic domain-insertion-name UI every `@domain`-kitted domain gets. What
> remains open is specifically the **four field-level placeholders** — XML
> text content, element tag, attribute name, attribute value — none of which
> route through `hinted_text` yet. See the per-section marker below.

## Origin

This plan comes from comparing the Julia
[`XmlToSyntax.jl`](../../source/xml/XmlToSyntax.jl)
against the original Common Lisp
[`xml-to-syntax.lisp`](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp).
The Julia port's **printer** is sound and its School-A reference mapping is
clean (keep it — see memory: prefer School-A delegation). The gap is almost
entirely on the **reader / authoring** side, plus a placeholder mechanism and a
couple of fidelity details. This plan closes that gap.

It is the XML sibling of
[json-to-syntax-lisp-parity.md](../done/json-to-syntax-lisp-parity.md) and **shares that
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
([XmlToSyntax.jl:69](../../source/xml/XmlToSyntax.jl#L69),
[:82](../../source/xml/XmlToSyntax.jl#L82),
[:225](../../source/xml/XmlToSyntax.jl#L225),
[:237](../../source/xml/XmlToSyntax.jl#L237))
only re-target *existing* text edits (`StringReplaceRangeOperation`) and
replace-selection (clicks). `XmlInsertionToSyntaxLeaf` has **no reader at all**
([:103-114](../../source/xml/XmlToSyntax.jl#L103-L114)).

---

## 0. Scope, and what is delegated to other plans

This plan does **not** re-specify the shared machinery; it depends on it:

- **The two new structural operations** (`ReplaceDocumentOperation`,
  `CollectionInsertOperation` / `CollectionDeleteOperation`) are defined in
  [json-to-syntax-lisp-parity.md §1](../done/json-to-syntax-lisp-parity.md). They are
  document-domain operations, not JSON-specific; XML reuses them verbatim. **Out
  of scope here** beyond noting the XML call sites (§1).
- **Event routing** — getting a raw `KeyPress`/`KeyDown` to a projection's
  reader so it can emit a structural operation — is
  [reader-gesture-context.md](../done/reader-gesture-context.md) +
  [text-syntax-json-typein.md](../done/text-syntax-json-typein.md) Phase 3. **Out of
  scope here**; this plan adds XML-specific reader methods on top (§2).
- **The placeholder / default-text mechanism** is
  [json-to-syntax-lisp-parity.md §4](../done/json-to-syntax-lisp-parity.md). XML reuses
  it for its four placeholders (§4).
- **Collapse wiring** (the dormant `collapsed` field on `XmlElement`,
  [Xml.jl:161](../../source/xml/Xml.jl#L161)) is
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

## 1. Structural operations (shared prerequisite — see JSON plan §1) — ✅ superseded, feature still delivered

> **✅ landed, but not as these named types (re-verified 2026-08-12) — see the
> top status banner for the full picture.** At the 2026-06-23 check,
> `ReplaceDocumentOperation` / `CollectionInsertOperation` / `CollectionDeleteOperation`
> existed in the kernel and the XML readers emitted them directly. **As of
> 2026-08-12, none of those three types exist anywhere in the tree** — a grep
> for `struct ReplaceDocumentOperation` / `struct CollectionInsertOperation` /
> `struct CollectionDeleteOperation` under `package/` finds nothing. They were
> superseded by a more general mechanism: insert/delete/replace is now a splice
> through `ReplaceReferencedValueOperation` + `RangeReferenceStep`
> (`package/kernel/main/operation/Operations.jl`, `insert_elements`/`delete_elements`-style
> helpers), and the XML readers no longer construct operations directly at all —
> they call shared `@domain`-kit helpers (`replace_selected_document`,
> `append_insertion_operation`) that build the splice underneath. The
> **behavior** this section asked for is still delivered end to end; only the
> concrete operation vocabulary changed.

Today the only document-mutating operations are `ReplaceSelectionOperation`
([Operations.jl:162](../../source/kernel/operation/Operations.jl#L162)),
`StringReplaceRangeOperation`
(find its current location under `package/*/main/` before picking this up —
`Primitive.jl` moved during the per-domain package split) and
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
([Xml.jl:159-160](../../source/xml/Xml.jl#L159-L160),
insert helper [Xml.jl:208-211](../../source/xml/Xml.jl#L208-L211)).
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
[`XmlToSyntax.jl`](../../source/xml/XmlToSyntax.jl),
alongside the existing `projection_read` methods.

### 3.1 Insertion replace (`xml/insertion->syntax/leaf` reader) — ✅ done

> ✅ VERIFIED: `projection_read(::XmlInsertionToSyntaxLeaf, ::SimpleIoMap, ::KeyPress)`
> at `XmlToSyntax.jl:442` → `_xml_read_command` (`:372-383`) returns a
> `ReplaceDocumentOperation` with `XmlText("")` (cursor `content{0}`) on `"` or
> `XmlElement("")` (cursor `tag{0}`) on `<`.

`XmlInsertionToSyntaxLeaf` currently has **no reader**
([XmlToSyntax.jl:103-114](../../source/xml/XmlToSyntax.jl#L103-L114)).
Add `projection_read(::XmlInsertionToSyntaxLeaf, iomap, ::KeyPress)` that, on an
insertion selection, returns a `ReplaceDocumentOperation` with a fresh document
whose initial selection is pre-placed:

| Key | Replacement document               | Lisp ref |
|-----|------------------------------------|----------|
| `"` | `XmlText("")`                      | [:306-310](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L306-L310) |
| `<` | `XmlElement("")` (empty, no attrs) | [:311-314](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L311-L314) |

The text replacement pre-selects `.cell[0:0]`; the element replacement
pre-selects `.tag[0:0]` (Julia constructors: [Xml.jl:125](../../source/xml/Xml.jl#L125),
[Xml.jl:165](../../source/xml/Xml.jl#L165)).

### 3.2 Element structural insert (`xml/element->syntax/node` reader) — ✅ done

> ✅ VERIFIED: `KeyPress` reader at `XmlToSyntax.jl:445` (`<`→`_xml_child_element_insert`,
> `"`→`_xml_child_text_insert`) and `KeyDown` reader at `:456`
> (`:space`→`_xml_attr_insert`, `:insert`→`_xml_generic_insert`). Helpers at
> `:388-429` emit `CollectionInsertOperation` into `.children`/`.attrs` with the
> follow-up selection, appending at `length(...)`.

On `XmlElementToSyntaxNode`
([XmlToSyntax.jl:225](../../source/xml/XmlToSyntax.jl#L225)),
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
  ([Xml.jl:50-55](../../source/xml/Xml.jl#L50-L55)). Use `XmlInsertion`
  for both — collapse the distinction unless a generic insertion type is later
  introduced.
- Space gating per §2: only fire when the cursor is in the start tag / an
  existing attribute / the element node.
- Index is `length(e.cell)` (or `length(e.attrs)`) — append at the end, as the
  Lisp does.

### 3.3 Attribute `=` navigation — and the missing attribute projection — ✅ done, decision reversed to option (b)

> **✅ DONE, but re-verified 2026-08-12 finds the recorded decision has since
> reversed:** at the 2026-06-23 check, option (a) was chosen — `_xml_attr_equals`
> handled `=` inline in `XmlElementToSyntaxNode`'s reader, and no separate
> `XmlAttributeToSyntaxNode` projection existed. **As of 2026-08-12, a real,
> separate `XmlAttributeToSyntaxNode` projection now exists**
> (`package/xml/main/XmlToSyntax.jl`, `@projection struct XmlAttributeToSyntaxNode`
> with its own `@projection_template`), wired into the dispatch table as
> `XmlAttribute => XmlAttributeToSyntaxNode()`, and the old inline `_attr_node`
> helper is gone — this is now option (b), the "faithful refactor" the plan
> explicitly said was not taken. The `=` navigation gesture itself, however,
> still fires from the element level: `KeyPress('=') => move_to_field(doc, :name, :value)`
> inside `@gestures XmlElement` (`package/xml/main/Xml.jl:133`), a shared generic
> helper (`package/domain/main/Domain.jl:416`) rather than an `_xml_attr_equals`
> function. So the printer separation is option (b) while the reader placement
> is closer in spirit to option (a) (centralized, not on a per-attribute
> gesture block) — a hybrid neither original option fully describes.

The Lisp models attributes as a **separate projection**
`xml/attribute->syntax/node` with its own reader, whose `=` command moves the
cursor name→value
([xml-to-syntax.lisp:360-367](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L360-L367)).

**The Julia port has no such projection.** Attributes are rendered *inline* by
the helper `_attr_node`
([XmlToSyntax.jl:337-364](../../source/xml/XmlToSyntax.jl#L337-L364))
inside `XmlElementToSyntaxNode`, and `XmlToSyntax`'s dispatch table has no
`XmlAttribute` entry
([XmlToSyntax.jl:366-372](../../source/xml/XmlToSyntax.jl#L366-L372)).
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

## 4. Placeholder / default text (shared mechanism — see JSON plan §4) — ⏳ remaining (unblocked)

> **⏳ OPEN, re-verified 2026-08-12 — see the top status banner for the full,
> current picture.** In short: `hinted_text` (renamed from `_hinted_text`) is
> now a genuinely shared, exported helper in `package/text/main/Text.jl:177`,
> used by JSON but by zero call sites in `package/xml/main/XmlToSyntax.jl`. The
> top-level `XmlInsertion` hardcoded-content problem is already fixed by an
> unrelated change (`DomainInsertionToSyntaxLeaf`). What is left is routing the
> four field-level leaves below through `hinted_text`.

The Lisp `text/make-default-text value placeholder …` shows a muted hint when
the field is empty. Reuse the placeholder concept the JSON
plan adds (an optional muted `placeholder` shown iff live content is empty, with
an emptiness flag the reader can test) for (line numbers re-verified 2026-08-12
against the current file):

- `XmlText` → `"enter xml text"`
  ([content leaf at XmlToSyntax.jl:65-66](../../source/xml/XmlToSyntax.jl#L65)).
- element tag → `"enter xml element name"`
  (tag leaf — find its current line in `XmlElementToSyntaxNode`'s printer,
  `package/xml/main/XmlToSyntax.jl`; the section moved since the last audit).
- attribute name → `"enter xml attribute name"`
  ([name leaf at XmlToSyntax.jl:92](../../source/xml/XmlToSyntax.jl#L92),
  now inside the separate `XmlAttributeToSyntaxNode` projection — see §3.3).
- attribute value → `"enter xml attribute value"`
  ([value leaf at XmlToSyntax.jl:93-95](../../source/xml/XmlToSyntax.jl#L93)).
- `XmlInsertion` placeholder — **already done**, via `DomainInsertionToSyntaxLeaf`
  (see the top status banner), not via `hinted_text`.

---

## 5. Selection / render fidelity nits

Lower priority; each is independent and small.

### 5.1 Attribute projection (see §3.3) — ✅ done, now option (b) (re-verified 2026-08-12)
Inline `_attr_node` vs. a real `XmlAttributeToSyntaxNode`. The plan originally
chose (a), inline. **That decision has since reversed**: a real
`XmlAttributeToSyntaxNode` projection now exists and is in the dispatch table
(see §3.3 above); `_attr_node` and `_xml_attr_equals` no longer exist.

### 5.2 End-tag editing — ✅ resolved (display-only)
> ✅ VERIFIED: `map_reference_backward` `child_i == 4` falls through to `nothing`
> with the display-only decision documented in the comment at
> `XmlToSyntax.jl:202-210`.

The Lisp maps end-tag edits to `xml/end-tag`
([xml-to-syntax.lisp:390-397](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L390-L397)).
Julia renders the closing tag from the same `e.tag` field but the closing-tag
leaf (child 4) carries no cursor and `map_reference_backward`'s `child_i == 4`
falls through to `nothing`
([XmlToSyntax.jl:218-220](../../source/xml/XmlToSyntax.jl#L218-L220)).
Since `_apply_string_replace!(::XmlElement, "tag", …)` already updates both tags
reactively ([Xml.jl:287-290](../../source/xml/Xml.jl#L287-L290)),
either route child-4 value edits to `.tag` too, or document that the end tag is
display-only and edited via the start tag. **Chose display-only**; recorded as a
comment on the `child_i == 4` fall-through in `map_reference_backward`.

### 5.3 Indentation parity — ⏭ won't-do (cosmetic)
> VERIFIED unchanged: body node still uses `indentation=1` at `XmlToSyntax.jl:276`.
> Cosmetic; left as won't-do.

The Lisp indents deep element children by 2 and gives the closing tag
indentation 0 ([xml-to-syntax.lisp:279-285](../../../projectured-lisp/source/projection/primitive/xml-to-syntax.lisp#L279-L285));
Julia's body node uses `indentation = 1`
([XmlToSyntax.jl:284-291](../../source/xml/XmlToSyntax.jl#L284-L291)).
Cosmetic only; round-trips fine. **Defer / likely won't-do.**

---

## 6. Phasing

*(The "Depends on" column names `ReplaceDocumentOperation`/`CollectionInsertOperation`
— see the top status banner: those specific types no longer exist, superseded
by the generic `ReplaceReferencedValueOperation` + `RangeReferenceStep` splice
mechanism, but the phases are still delivered.)*

| Phase | Deliverable | Depends on | Status |
|-------|-------------|-----------|--------|
| 1 | XML insertion reader (`"`/`<` → `ReplaceDocumentOperation`) (§3.1) | JSON plan §1 op + §2 routing | ✅ done |
| 2 | Element structural insert: `<`, `"` children (§3.2) | Phase 1; `CollectionInsertOperation` | ✅ done |
| 3 | Space → attribute insert (§3.2) + `=` name→value navigation (§3.3a) | Phase 2 | ✅ done |
| 4 | Insert key → generic insertion child (§3.2) | Phase 2 | ✅ done |
| 5 | Placeholders / default text (§4) | `_hinted_text` (landed) | ⏳ remaining (unblocked) |
| 6 | Fidelity nits (§5) as separate commits, each optional | none | ✅ resolved (§5.1/§5.2 done, §5.3 won't-do) |

Phases 1–4 are the substance (the Lisp reader). Phase 5 is independent. Phase 6
items are individually optional.

---

## 7. Tests — ✅ done (placeholder test pending Phase 5)

> **✅ VERIFIED (re-checked 2026-08-12):** `package/xml/test/projection/XmlToSyntaxTest.jl` exists with
> `test_xml_to_syntax()` (printer) and `test_xml_to_syntax_reader()` (reader),
> plus a third function not in the original plan, `test_xml_override_gestures()`.
> Registered in `package/xml/test/ProjecturedXmlTest.jl` (`include` at `:68`, calls at
> `:97-98`). Reader sections cover insertion replace, root swap, child-insertion
> replace, element/text insert, Space attribute insert + gating, Insert key, and
> `=` navigation. The **placeholder** test is absent (deferred with Phase 5), as
> stated. `xml_example` is registered in the example gallery (find its current
> registration line in `package/xml/example/` or `package/projectured/example/Gallery.jl`
> before picking this up — not confirmed here).

> Created [`XmlToSyntaxTest.jl`](../../test/xml/projection/XmlToSyntaxTest.jl)
> with `test_xml_to_syntax()` (printer) + `test_xml_to_syntax_reader()` (reader),
> registered in [`ProjecturedTest.jl`](../../package/ProjecturedXmlTest/src/ProjecturedXmlTest.jl) next to
> the JSON ones. All reader sections below are covered (insertion replace, element
> insert, attribute insert + gating, `=` navigation). The **placeholder** test is
> deferred with Phase 5.

There is **no** `XmlToSyntaxTest.jl` today (only
[`JsonToSyntaxTest.jl`](../../test/json/projection/JsonToSyntaxTest.jl)) —
historical: both now exist, see the "done" note above. Create
`package/xml/test/projection/XmlToSyntaxTest.jl` with a `test_xml_to_syntax()` mirroring
`test_json_to_syntax()`, register it in
[`ProjecturedTest.jl`](../../package/ProjecturedXmlTest/src/ProjecturedXmlTest.jl) (next to
`test_json_to_syntax()` at [:69](../../package/ProjecturedXmlTest/src/ProjecturedXmlTest.jl#L69)), and add
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
[DomainExamples.jl:17](../../example/projectured/DomainExamples.jl#L17)); these run under
`SDL_VIDEODRIVER=dummy` like the other reader suites. Broad sweeps
(`test_readers()` / `test_selections()`) only as a final check, per
[CLAUDE.md](../../CLAUDE.md).

---

## 8. Acceptance — ◑ mostly met

> Reader command set and tests are in place; `test_printers()`, `test_readers()`,
> `test_selections()` are all green with no new warnings. The live
> `run_example("xml")` authoring flow depends on the delegated event-routing layer
> (a `KeyPress` at a character cursor is consumed by `TextToGraphics` first), and
> placeholder hints await Phase 5.

`run_example("xml")` supports authoring a document from scratch:

- Start on an `XmlInsertion`; press `<` → an empty element; type a tag, press
  Space → an attribute, type its name, `=`, type its value; then `<`/`"` to add
  child elements and text — matching the Lisp editor's flow.
- `test_printers()`, `test_readers()`, `test_selections()` all green, zero
  `@warn`.

---

## 9. Out of scope

- The shared structural operations themselves → [json-to-syntax-lisp-parity.md §1](../done/json-to-syntax-lisp-parity.md).
- The event-routing / gesture mechanism → [reader-gesture-context.md](../done/reader-gesture-context.md), [text-syntax-json-typein.md](../done/text-syntax-json-typein.md).
- The placeholder mechanism's implementation → [json-to-syntax-lisp-parity.md §4](../done/json-to-syntax-lisp-parity.md) (this plan only lists the XML strings).
- Collapse wiring & rendering → [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md).
- Undo/redo — but `CollectionInsert/Delete` are designed with inverses so it can build on them.
- Indentation parity (§5.3) — likely won't-do; documented for completeness. (A
  separate `XmlAttributeToSyntaxNode` projection, previously listed here as
  "likely won't-do", was in fact built since — see §3.3 and §5.1.)
- Escape-aware string offset mapping (same caveat the printer already carries).
- IME / non-ASCII input.

---

## 10. What to keep (the Julia version is already fine here)

Do **not** "fix" these toward the Lisp shape — they are deliberate choices:

- **School-A delegation** in the element reference mappers. Re-verified
  2026-08-12 at a different location than cited: `map_reference_forward` is at
  [XmlToSyntax.jl:156](../../source/xml/XmlToSyntax.jl#L156), and
  `map_reference_backward` is no longer hand-written here at all — it is
  called (line 144) but resolves to the generic default implementation in
  `package/kernel/main/projection/Projection.jl`, an even more thorough form of
  School-A delegation than the plan describes.
- **Multiple-dispatch readers** vs. the Lisp `typecase` operation-mapper lambdas.
- **`xml_escape_attr`**
  ([XmlToSyntax.jl:223](../../source/xml/XmlToSyntax.jl#L223)) and
  **`_xml_text_escape`** (renamed from `xml_escape_text`,
  [XmlToSyntax.jl:210](../../source/xml/XmlToSyntax.jl#L210))
  — proper XML escaping.
- The single reactive `e.tag` field driving both open and close tags
  ([XmlToSyntax.jl:111](../../source/xml/XmlToSyntax.jl#L111),
  [:121](../../source/xml/XmlToSyntax.jl#L121)) — editing
  one updates both with no extra wiring.
</content>
