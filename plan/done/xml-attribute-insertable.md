# Make `XmlAttribute` insertable

## Problem

`XmlAttribute` is not an insertion candidate — `insertion_candidates(XmlDocument)`
returns `[XmlElement, XmlText]`. It is excluded only because `XmlAttribute()` throws
`UndefKeywordError` (`name`/`value` have no defaults) and there is no
`make_insertion_document` method, so `insertable(XmlAttribute)` is `false`. Nothing
about the type prevents it from standing alone as a document.

Adding the factory alone is not enough: `XmlToSyntax`'s type-dispatch table has no
`XmlAttribute` entry, so a committed attribute would have no projection to print
through. The `name="value"` markup exists, but *inline* inside
`XmlElementToSyntaxNode`'s `collection(:attrs) do a … end` builder, where nothing
else can reach it.

JSON registers its analogue as `JsonObjectEntry => CopyingProjection()` — a
passthrough that emits an entry-shaped node, not real syntax. Not copied here.

## Design

Lift the attribute markup into its own projection and have the element delegate to
it (School A: delegate through child IO maps, do not re-walk).

1. **`XmlAttributeToSyntaxNode`** — a new `@projection_template` over `XmlAttribute`
   producing the fixed 2-leaf node `name="value"`: `bound(:name)` and `bound(:value)`
   leaves, `sep="="`, the value leaf opened/closed with `"`. It takes over the
   `attr_name` / `quote_style` / `attr_value` styles.
2. **Dispatch table** — `XmlAttribute => XmlAttributeToSyntaxNode()` in `XmlToSyntax`.
3. **`XmlElementToSyntaxNode`** — its attrs node becomes a plain `collection(:attrs)`
   (no builder), so each attribute dispatches through the composite, exactly like
   `collection(:children)` already does. The element keeps the `>` close and `" "`
   separator; it drops the three attribute styles it no longer renders.
4. **Factory** — `make_insertion_document(::Type{<:XmlAttribute}) =
   @with_selection XmlAttribute("", "") name{0}`, which is what makes
   `insertable(XmlAttribute)` true and puts it in the candidate list.

## Risk

(3) moves attribute references from the element's IO map into a child IO map, so
`attrs[i].name{k}` selections now map through one more level. The XML printer,
reader, navigation and repl suites all exercise attribute carets, so a regression
shows up immediately.

## Verification

`test_example(xml_example)` against the clean-main baseline **12482 pass / 52 fail**
(the 52 are the pre-existing wholesale typein "no cursor" failures). Plus
`insertion_candidates(XmlDocument)` must gain `XmlAttribute`, and an attribute
committed into an `XmlInsertion` must print.

## Steps

- [x] 1. **Done.** `XmlAttributeToSyntaxNode` + dispatch entry.
- [x] 2. **Done.** Element delegates `collection(:attrs)`; its `attr_name` /
  `quote_style` / `attr_value` styles moved to the attribute projection.
- [x] 3. **Done.** `make_insertion_document` factory.
- [x] 4. **Done.** Verified:
  - `test_example(xml_example)`: **12483 pass / 52 fail** vs the 12482 / 52 baseline —
    no new failures, and one *more* passing assertion.
  - `test_document_insertion()` 101/101, `test_xml_to_syntax()` 7/7,
    `test_xml_to_syntax_reader()` 32/32, `test_xml_parser()` 11/11.
  - `insertion_candidates(XmlDocument)` is now `[XmlAttribute, XmlElement, XmlText]`.
  - Completion stays prefix-free: `a` → attribute, `e` → element, `t` → text, all
    unambiguous.
  - Rendering: a standalone `XmlAttribute("id", "42")` prints as `id="42"`, and an
    element still prints as `<a id="1" cls="x">…</a>` — the delegation is
    output-identical.
