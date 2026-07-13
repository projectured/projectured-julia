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

- [ ] 1. `XmlAttributeToSyntaxNode` + dispatch entry.
- [ ] 2. Element delegates `collection(:attrs)`; drop its now-unused styles.
- [ ] 3. `make_insertion_document` factory.
- [ ] 4. Verify against baseline; check the candidate list and a standalone print.
