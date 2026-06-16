# Document layer: consistency & correctness cleanup

Outcome of a design review of all document data structures and the document
guides. Each item below was confirmed against the source and ruled on by the
author. Worktree: `worktree-document-cleanup`.

## Decisions (author-ruled)

1. **`selection` terminology** — Canonical phrasing: "`selection::Reference` — a
   `ReferencePath` or `nothing`", with a note that it is stored in a `Cell` so
   selection changes propagate reactively (the Cell-ness is an internal
   mechanism a document author should be *aware* of, not the primary model).
2. **Field names are the reference vocabulary** — Deliberate, load-bearing:
   `evaluate_reference` resolves a `FieldReference` via
   `getfield(document, Symbol(name))`, so every field name is public selection
   API and renaming a field breaks stored references. Must be documented.
3. **`[i]`/`{k}` convention is final** — `[i]` = 1-based element/item,
   `{k}` = 0-based cursor (0-length). `[k]`-as-cursor in any docstring is a bug.
4. **XML `cell` fields are wrong** — rename: `XmlElement.cell`→`children`,
   `XmlText.cell`→`content`, `XmlAttribute.cell`→`value` (keeps `name`).
   Backward compatibility not important.
5. **Child-collection field names** — no convention; leave as-is.
6. **Per-domain `Insertion` types** — justified (each is the domain's
   domain-specific type-in / insertion entry point). Tutorial should explain it.
7. **Splice unification** — the ~40 `_apply_string_replace!` /
   `_apply_number_replace!` methods reduce to 3 value *representations*
   (string / TextText / number). Hoist one `splice_string` helper into
   `OperationApiModule`; replace the per-type methods with `splice_value!`
   dispatched on the value representation. Scope now: string + TextText + number
   (sequence/structural left for a later unification of all replace-part
   operations around a reference).
8. **`DocumentBase` content ops** (`Load/Save/ExportDocumentOperation`) are
   incompletely ported (need a `content`-bearing wrapper) — mark WIP, do not
   delete.
9. **`Syntax*` wrapper types** (Delimitation/Indentation/Collapsible/Navigation/
   Concatenation/Separation) — potentially useful, currently unused; leave.
10. **Honest type annotations** — annotation = the I-struct's enforced type, so
    it must admit every value the field can hold, including `nothing` where the
    domain uses it as the empty sentinel. Widen reachable-`nothing` fields to
    `Union{T,Nothing}` (audit; do not blanket-widen). Fix the macros.md promise.
11. **New-domain tutorial** — keep illustrative but every code block must be
    correct (it currently has 3 errors in Step 6: `node.elements` vs `children`,
    comparing a `TextString` to a `String`, and a transposed `projection_print`
    arg order).

## Work items — all complete

- [x] #3 Docstring sweep — swept `[k]`-as-cursor → `{k}` and standardized the
      `selection::Reference` line across Json, Syntax, Text, Xml, Primitive,
      **plus** Ini, Math, Ned, Table, Tabular (the bug was uniform).
- [x] #4 XML rename `cell`→`children`/`content`/`value` + ripple: Xml.jl
      (fields, accessors, `setattr!`, `show`), XmlToSyntax.jl (all `@reference`
      paths and field access), test/projection/XmlToSyntaxTest.jl.
- [x] #7 Splice refactor — `splice_string`/`splice_number`/`splice_value!` in
      `OperationApiModule`; `splice_value!` dispatched on value representation
      (String / Number / TextString / TextText / Nothing); TextString+TextText
      methods live in `TextModule`. Deleted ~40 `_apply_string_replace!` /
      `_apply_number_replace!` methods and 6 duplicate slice helpers across
      Json, Xml, Text, Syntax, Primitive, Book, Ned, Ini, Julia, Document.
      `evaluate_operation` for String/Number replace rewritten in Primitive.jl.
- [x] #10 Widened the three genuinely-nullable fields (`PrimitiveString.value`,
      `PrimitiveNumber.value`, `JsonNumber.value`) to `Union{T,Nothing}`; the
      other "defended" fields (NedParam.value, Book author/content) are already
      `::Any`. Rewrote the macros.md annotation promise to state the honesty rule.
- [x] #8 WIP annotations on `Load/Save/ExportDocumentOperation` (content field
      not yet ported).
- [x] #1 json.md selection phrasing (`selection::Reference`, Cell note).
- [x] #2 Field-name contract: authoritative in api/Document.jl `Document`
      docstring, plus concepts.md §Selection and a tutorial key-point.
- [x] #6 Insertion-purpose comment in tutorial Step 1.
- [x] #11 Fixed tutorial Step 6 (`children` not `elements`, `.value.content`,
      `projection_print` arg order).

## Verification

- Loads clean; targeted tests pass: PrimitiveReplaceRange 32/32, XmlToSyntax
  reader 32/32, json/xml/syntax/text printers+readers, json+xml repls.
- #10 confirmed: `IPrimitiveString(nothing)`, `IPrimitiveNumber(nothing)`,
  `IJsonNumber(cleared)` now snapshot instead of throwing.

## Out of scope — pre-existing bug noticed (NOT fixed here)

`test_example(text_example)` errors with `StringIndexError` inside
`set_selection!(::String)` (common/Operation.jl) when exhaustive navigation
(`check_reaches_all`) reaches a multibyte caret (`é`/`€`). Confirmed identical
on pristine origin/main — unrelated to this work. Worth a separate fix
(byte-vs-character indexing in `set_selection!(::String)`).
</content>
