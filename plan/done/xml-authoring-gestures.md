# Reify XML authoring as `@gestures`; trim Xml.jl comments

Two asks:

1. **Add `@gestures` to `Xml.jl`** (the domain file) so XML is editable through the
   same reified `document_read` path JSON uses — and remove the now-redundant
   `projection_read(::KeyPress/::KeyDown)` handlers from `XmlToSyntax.jl`.
2. **Comment cleanup** in `Xml.jl`: reduce surface, don't name JSON, don't restate
   what the code/macro obviously does, match `Json.jl`'s density.

## Why this works (routing)

`JsonToSyntax()` and `XmlToSyntax()` both return a `TypeDispatchingProjection`, and
both reader tests drive `projection_read(RecursiveProjection(…ToSyntax()), iomap, evt)`.
JSON has **no** projection-level key readers — a raw key reaches the domain via the
generic `projection_read(::Projection, iomap, ::Union{KeyPress,KeyDown}) →
document_read(iomap.input, evt)` fallback (Projection.jl), which fires the reified
`@gestures`. So once XML's `projection_read(::KeyPress/::KeyDown)` overrides are gone,
XML routes identically. XML handles everything at the *root document* level (its custom
`ChildrenIoMap` has no recursive gesture reader — only `@projection_template`'s
`RuleIoMap` does), exactly as the old element reader did via `iomap.input`.

## Gesture design (reproduces all 8 reader-test groups)

`document_gestures(T)` = own bindings first, then each supertype's;
`read_document_gesture` fires the first binding that matches + is `applicable` + whose
operation returns non-`nothing`.

- `@gestures XmlDocument` (inherited by `XmlInsertion` and `XmlElement`), guarded
  `when(_xml_replaceable(doc, sel))` (the selected target is an `XmlInsertion`):
  - `"` → replace the selected insertion with `XmlText("")`, cursor at `content{0}`
  - `<` → replace it with `XmlElement("")`, cursor at `tag{0}`
- `@gestures XmlElement` (no block guard; each op self-gates by returning `nothing`):
  - `<` → append a child element (declines if an insertion is selected, so the
    `XmlDocument` replace above wins); select new `children[n+1].tag{0}`
  - `"` → append a child text; select `children[n+1].content{0}`
  - `Insert` → append a bare `XmlInsertion`; select `children[n+1]`
  - `Space` → insert an attribute, but only in attribute context (element / tag /
    attrs, never inside a child); select `attrs[n+1].name{0}`
  - `=` → move the cursor from an attribute name to its value (`@reference_case`)

Precedence check (the `<`/`"` overload): for a selected child insertion, `XmlElement`'s
`<` op returns `nothing` (via `_xml_replaceable`), so iteration reaches `XmlDocument`'s
`<` which fires the replace. For a non-insertion selection it appends. ✓

## Edits

- **`Xml.jl`**: add imports (`evaluate_reference`, `EmptyReferencePath`,
  `ConcreteReferencePath`, `FieldReference`, `ProjectionReference`, `@reference`,
  `@reference_case`, `replace_document`, `insert_elements`, `ReplaceSelectionOperation`,
  `with_selection`, `KeyPress`, `KeyDown`, `@gestures`), all matching `Json.jl`'s module
  paths. Add the helper fns + the two `@gestures` blocks. Trim comments (drop the
  `@forward_map` comment entirely — `Json.jl` doesn't comment it; trim the ctor and
  text-replace notes; no JSON references).
- **`XmlToSyntax.jl`**: delete lines 343–457 (the reader block: the big header comment,
  `_xml_read_command`, `_xml_child_element_insert`/`_text`/`_generic_insert`,
  `_xml_in_attr_context`, `_xml_attr_insert`, `_xml_attr_equals`, and the three
  `projection_read(::KeyPress/::KeyDown)` methods). Prune now-unused imports:
  `OperationModule` → keep only `ReplaceSelectionOperation`; drop
  `import ..DocumentApiModule: with_selection` and `import ..KeyboardModule: KeyPress, KeyDown`;
  from `ReferenceModule` drop `EmptyReferencePath`, `evaluate_reference`.

## Verification — DONE

All green (worktree): `test_xml_to_syntax_reader` **32/32** (authoritative), `test_xml_to_syntax` 7, `test_xml_parser` 11, printer 7318, reader 225, repl 225; `test_gesture_help` 35, `test_json_gesture_collection` 10, `test_gesture_map` 14. Registry: `document_gestures(XmlElement)`=7 (5 own + 2 inherited), `XmlInsertion`=2.

- `test_xml_to_syntax_reader()` (32) — the authoritative behavioural check; must stay green.
- `test_xml_to_syntax()`, `test_printer/test_reader(xml_example)`, `test_xml_parser()`.
- `test_gesture_help()` / any gesture-collection sweep (adding XML gestures must not break them).
</content>
