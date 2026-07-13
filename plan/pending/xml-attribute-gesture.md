# XML attribute follow-ups: a single-key gesture, and the children-slot question

Follow-up to [xml-attribute-insertable](../done/xml-attribute-insertable.md), which made
`XmlAttribute` an insertion candidate and gave it its own projection.

## 1. A single-key gesture for an attribute

`@gestures XmlDocument` turns a selected `XmlInsertion` into a node with one key:

    KeyPress('"') => "Replace with text"       => make_insertion_document(XmlText)
    KeyPress('<') => "Replace with an element" => make_insertion_document(XmlElement)

`XmlAttribute` has no such key — it is reachable only by typing its name into the
insertion buffer (`a` + Return). Add the third:

    KeyPress('@') => "Replace with an attribute" => make_insertion_document(XmlAttribute)

`@` is the conventional attribute sigil (XPath `@attr`) and is otherwise unbound.
It must not be a name character: the insertion is a **typed-name buffer**, so a
letter key (`a`) would be swallowed by the buffer instead of firing a gesture —
which is exactly why `<` and `"` were chosen for the other two.

`=` is deliberately **not** used: `@gestures XmlElement` already binds `KeyPress('=')`
to "Move to attribute value", and both binding sets are consulted for an `XmlElement`,
so the two would be distinguished only by precondition ordering.

## 2. The children-slot question — investigated, deferred

**The problem.** The only place an `XmlInsertion` placeholder is ever created is the
`children` list (`_xml_insert_node`, `KeyDown(:insert)`), plus a document that *is* an
insertion at the root. Since `XmlAttribute` became a candidate, committing one at a
`children` insertion puts an attribute into `children` — structurally wrong XML. (The
gesture in (1) does not add this hazard: the name-completion path already allows it.)

**Why it is not a small fix.** Candidate scope is *baked into the projection instance*:
`DomainInsertionToSyntaxLeaf(root)` closes over `root` in its `commit` / `completion`
closures at construction time, and `XmlInsertion => XmlInsertionToSyntaxLeaf()` is a
single global entry in the `TypeDispatchingProjection` table. The printer context can
carry a slot scope (`with_property` / `get_property` — precedent: Markdown's `:md_style`,
DbCatalog's schema), but the **reader** commits through the closure, which never sees a
context. Slot-aware candidates therefore need the insertion machinery reworked so the
scope flows from the context rather than from construction — a change to shared
`DocumentInsertionToSyntaxModule` machinery affecting every domain, not an XML tweak.

**Decision: defer, do not paper over.** Two designs, for whoever picks this up:

- *Context-scoped candidates* — the element sets an `:insertion_scope` property on the
  `children` / `attrs` child contexts; the insertion leaf's completion and commit read
  it (requires the leaf's IoMap to retain its printer context, as `CopyingProjectionIoMap`
  already does with `base_ctx`). General, benefits every domain.
- *Per-slot projection instances* — the element installs a differently-scoped insertion
  projection per collection instead of relying on the global dispatch entry. Narrower,
  but pushes projection choice into the parent.

Nothing in this domain validates well-formedness today (an `XmlText` may nest anywhere,
elements nest freely, there is no DTD), so an attribute in `children` is a recoverable
user error, not a corruption — which is why it is acceptable to leave standing until the
scope machinery is designed properly.

## Steps

- [ ] 1. Add the `KeyPress('@')` gesture to `@gestures XmlDocument`.
- [ ] 2. Verify against baseline.

## Verification

- `test_example(xml_example)` — baseline **12483 pass / 52 fail** (the 52 are the
  pre-existing wholesale typein "no cursor" failures).
- `test_document_insertion()` 101/101, `test_xml_to_syntax()` 7/7,
  `test_xml_to_syntax_reader()` 32/32.
- The gesture drives end-to-end: `@` on a selected `XmlInsertion` yields an
  `XmlAttribute` with its caret on `name{0}`.
