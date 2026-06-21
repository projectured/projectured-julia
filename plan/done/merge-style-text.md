# Merge font + color pairs into `StyleText` project-wide

## Goal

Replace the recurring **separate `font::StyleFont` / `color::StyleColor` field pair**
with a single `StyleText` value — in projection data structures *and* in the function
arguments that thread those pairs around. Example of the smell, from
[JsonToSyntax.jl](../../program/src/projection/primitive/JsonToSyntax.jl):

```julia
struct JsonStringToSyntaxLeaf <: Projection
    quote_font::StyleFont
    quote_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
end
```

becomes

```julia
struct JsonStringToSyntaxLeaf <: Projection
    quote::StyleText
    value::StyleText
end
```

`StyleText` already exists ([StyleText.jl](../../program/src/document/StyleText.jl)) and
bundles exactly `(font::StyleFont, color::StyleColor)`. The widget theme layer already
uses it ([WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl)),
so this plan extends an established convention to the rest of the projection layer rather
than introducing anything new.

## Why

- A `font`/`color` pair is *always* used together to construct a `TextString` run. Carrying
  them as two fields and two arguments is noise that triples the field/argument count.
- Themes want to expose **semantic** styles (e.g. "the quote style", "the keyword style")
  as one value that can be swapped, interpolated, or stored in a theme struct — exactly what
  `WidgetToGraphics`'s `WidgetTheme` already does with `body_text`/`title_text`/… `StyleText`
  fields.
- The constructor keyword surface shrinks: `JsonStringToSyntaxLeaf(; quote_font=…,
  quote_color=…, value_font=…, value_color=…)` → `(; quote=…, value=…)`.

## Current state / precedent

- `StyleText(font, color)` is a plain value struct with `.font` and `.color`, plus
  `make_style_text` and a `show` method. No reactive `Cell` wrapping — it is an immutable
  style value, like `StyleColor`/`StyleFont`.
- **Already migrated:** `WidgetToGraphics.jl` (the `WidgetTheme` and per-widget projections)
  holds `StyleText` fields and reads `.font` / `.color` at render time
  (`_text_size(p.measure, p.text.font, …)`, `_rgba(p.text.color)`).
- **Not migrated:** every `*ToSyntax` / `*ToText` projection still holds split pairs and
  feeds them positionally into `TextString(content, font, color)`.

### The bridge: a `StyleText` constructor for `TextString`

`TextString`'s document model stays unchanged (it keeps `font`, `font_color`, plus
`fill_color`, `line_color`, `padding`, `selection`). We only add overloads so a projection
holding a `StyleText` can construct a run without unpacking:

```julia
TextString(content::AbstractString, style::StyleText) = TextString(content, style.font, style.color)
TextString(content::Function,      style::StyleText) = TextString(content, style.font, style.color)
```

This decouples the projection-struct refactor (the bulk of the work) from any change to the
`TextString` / `GraphicsText` *document* model (Phase 4, optional). Render code that reads
`.font_color` (only 6 sites) is untouched.

## Scope

Counts are `::StyleFont` field declarations per file (a rough proxy for pairs to merge):

| Layer | File | fonts | colors | Notes |
|------|------|------|------|------|
| Core value | `document/StyleText.jl` | — | — | add `TextString` bridge constructors (in Text.jl) |
| Projection | `JuliaToSyntax.jl` | 32 | 33 | largest; many keyword-styled token kinds |
| Projection | `SqlToSyntax.jl` | 30 | 26 | second largest |
| Projection | `JsonToSyntax.jl` | 13 | 13 | the motivating example |
| Projection | `ObjectToSyntax.jl` | 12 | 12 | |
| Projection | `BookToSyntax.jl` | 9 | 11 | |
| Projection | `XmlToSyntax.jl` | 7 | 7 | |
| Projection | `DbCatalogToSyntax.jl` | 6 | 6 | |
| Projection | `FormulaToSyntax.jl` | 5 | 5 | |
| Projection | `MathToSyntax.jl` | 5 | 5 | |
| Projection | `PrimitiveToSyntax.jl` | 4 | 4 | |
| Projection | `PrimitiveToText.jl` | 4 | 4 | |
| Projection | `CollectionToSyntax.jl` | 2 | 2 | |
| Projection | `FileSystemToSyntax.jl` | 2 | 2 | |
| Projection | `ObjectToWidget.jl` | 2 | 2 | |
| Projection | `DocumentInsertionToSyntax.jl` | 1 | 2 | one font, two colors — see "unbalanced" below |
| Projection | `ReferenceToText.jl` | 3 | 1 | unbalanced — see below |
| Projection | `TextToGraphics.jl` | 6 | 2 | unbalanced; mostly measurement fonts |
| Projection | `LineNumbering.jl` / `TextToWidget.jl` | 1 / 1 | 0 / 0 | **font only, no pair — leave as-is** |

### What is *in* scope

- Projection config structs whose fields form `<name>_font` / `<name>_color` pairs.
- Their keyword constructors (the `(; …_font=, …_color=)` default signatures).
- Helper functions that take a `(font, color)` pair, chiefly `_hinted_text(…, font, color)`
  in JsonToSyntax (and any equivalents found per file).
- `TextString(content, font, color)` *call sites inside migrated projections* — switch them
  to `TextString(content, style)` using the new bridge constructor.

### What is *out* of scope (or deferred)

- **Standalone colors** with no font partner (backgrounds, borders, separators' fill,
  selection highlights, `WidgetToGraphics`'s 76 colors that are mostly non-text). These stay
  `StyleColor`. Only *paired* font+color merge.
- **Font-only fields** (`LineNumbering`, `TextToWidget`, measurement-only fonts in
  `TextToGraphics`) — nothing to merge.
- **Unbalanced groups** (e.g. one font shared by two colored runs, like
  `DocumentInsertionToSyntax` 1 font / 2 colors, or `ReferenceToText` 3 fonts / 1 color).
  Merge only where a genuine 1:1 font↔color pairing exists; where one font backs two colors,
  prefer two `StyleText` values sharing the same font over forcing an artificial merge. Decide
  per-occurrence during implementation and record the call.
- **Phase 4 — `TextString` / `GraphicsText` document-model merge** (replacing the `font` +
  `font_color` *document fields* with a `StyleText` field). Higher blast radius: it changes
  `@document` field layout, reference paths (`.font_color` → `.style.color`), IO maps, the SDL/
  PDF/Web backends, and ~387 `TextString(` call sites. The bridge constructor makes this
  unnecessary for the present goal; keep it as a separate, explicitly-optional phase.

## Design decisions

1. **Field naming.** Drop the `_font`/`_color` suffixes and name the merged field after the
   *role*: `quote_font`+`quote_color` → `quote`; `value_*` → `value`; `delim_*` → `delim`;
   `sep_*` → `sep`; `key_*` → `key`; `colon_*` → `colon`. This matches `WidgetToGraphics`
   (`body_text`, `label_text`) — when the bare role noun would be unclear, use the `_text`
   suffix (`label_text::StyleText`) as that file does.
2. **Keyword constructors** take one `StyleText` per role with a `StyleText(font_…, color_…)`
   default built from the existing named font/color constants, e.g.
   `JsonStringToSyntaxLeaf(; quote=StyleText(font_ubuntu_monospace_regular_24,
   color_solarized_yellow), value=StyleText(font_ubuntu_monospace_regular_24,
   color_solarized_green))`.
3. **Bridge constructors** on `TextString` (above) are the single integration point; add them
   first so every projection edit compiles against them.
4. **No behavioral change.** Same fonts, same colors, same rendering. This is a pure
   refactor; tests must pass unchanged.

## Implementation phases

Work in a dedicated git worktree. Commit after each file/phase. Delegate the mechanical
per-file edits (struct fields, constructor signatures, call-site rewrites) to a **Sonnet
subagent**, then verify each file compiles and its targeted test passes before moving on.

### Phase 0 — Bridge constructors + smoke test
- Add `TextString(content, style::StyleText)` overloads in
  [Text.jl](../../program/src/document/Text.jl) (string + function content).
- Ensure `StyleText` is imported where needed; it's already re-exported via `Projectured.jl`.
- Verify: `test_cell()` and one existing example (`test_example(json_example)`).

### Phase 1 — JsonToSyntax (the motivating file, smallest "real" pattern)
- Merge each struct's pairs; update keyword constructors; rewrite the internal
  `TextString(…, font, color)` and `_hinted_text(…, font, color)` calls.
- Change `_hinted_text` signature to take `style::StyleText`.
- Verify: `test_example(json_example)`, then `test_json_to_syntax()`.

Phase 1 is the template. Each subsequent projection file repeats the same three moves
(struct fields → constructor → call sites + helpers).

### Phase 2 — remaining small/medium projections
`CollectionToSyntax`, `FileSystemToSyntax`, `DbCatalogToSyntax`, `FormulaToSyntax`,
`MathToSyntax`, `PrimitiveToSyntax`, `PrimitiveToText`, `XmlToSyntax`, `BookToSyntax`,
`ObjectToSyntax`, `ObjectToWidget`. One file per commit; run that domain's targeted test
(e.g. `test_xml_to_syntax()`, `test_example(xml_example)`).

### Phase 3 — large projections
`JuliaToSyntax` (32) and `SqlToSyntax` (30). Most fields, highest chance of unbalanced
groups; do these last when the pattern is well-rehearsed. Targeted tests:
`test_example(julia_example)` / the Julia + SQL domain tests.

### Phase 4 — (optional, separate decision) document-model merge
Only if desired after Phases 0–3 land. Replace `TextString`/`GraphicsText` `font` +
`font_color` document fields with a single `StyleText` field; update `@document`, reference
paths, IO maps, backends (SDL/PDF/Web), and all `TextString(` constructors. Treat as its own
plan — do **not** bundle into this one.

## Testing strategy

Per the repo's "smallest test that covers the change" rule — never `test_all()`:

- After Phase 0: `test_cell()`, `test_example(json_example)`.
- After each projection file: that file's pipeline test (`test_<domain>_to_syntax()`) and one
  representative `test_example(<domain>_example)` covering printer + reader + navigation.
- After all phases: one broad sweep `test_printers()` / `test_readers()` to catch any missed
  call site, since the change is purely mechanical and broad.

## Risks

- **Unbalanced font/color groups** (one font, multiple colors, or vice versa) — the merge is
  not 1:1 there; resolve per-occurrence (two `StyleText` sharing a font, or leave split).
  Record each decision inline in the file and here.
- **Positional `TextString(content, font, color)` vs new `(content, style)`** — both must
  remain valid during migration; keep the old three-arg constructors intact (Phase 4 is the
  only thing that would remove them).
- **Keyword-name churn** ripples to any external caller passing `…_font=`/`…_color=`. Grep for
  keyword call sites of each constructor before renaming; most are constructed with defaults
  inside the `*To*()` convenience builders, so the blast radius is small.

## Progress

- [x] Phase 0 — bridge constructors (`TextString(content, style::StyleText)`, string + function)
- [x] Phase 1 — JsonToSyntax
- [x] Phase 2 — small/medium projections + FormulaToSyntax, DocumentInsertionToSyntax, BookToSyntax
- [x] Phase 3 — JuliaToSyntax, SqlToSyntax
- [ ] Phase 4 — (optional) document-model merge — **not done, deferred as planned**

## Outcome / decisions discovered during implementation

- **`StyleText` is now exported from `Projectured`** (alongside `StyleFont`/`StyleColor`). It
  became part of the public projection-constructor API, and an example referenced it.
- **Reserved-word / field-clash renames:** a merged field that would be `quote` is named
  `quote_style` (JSON/Primitive/Xml/Object/Julia string+char). Where a `keyword::String` field
  already existed (`SqlBooleanBinaryToSyntaxNode`) the merged style is `keyword_style`; same for
  `PrimitiveStringToTextText` (`placeholder::String` stays, color → `placeholder_style`).
- **Font-sharing merges (lone color paired with a shared font):** turned into a second
  `StyleText` that reuses the font in its default — `FormulaFormula.result`, `Book*.placeholder`,
  `DocumentInsertion` `label`/`value`, `Julia` string/char `quote_style`.
- **Lone fonts left as-is** (no color partner; rendered with literal colors): `FormulaEnvironment`,
  `JuliaBlock`, `SqlStatementList` (`.font`), and Sql `identifier_font` (Subquery/CreateSchema) /
  `alias_font` (SelectItem).
- **Out of scope, untouched:** `ReferenceToText` (font-only struct; per-token colors are literals)
  and `TextToGraphics` (document-model reads + measurement fonts, no config pairs).
- **External callers updated:** `example/.../ObjectToWidget.jl` and `example/.../Workbench.jl`
  (the latter forwards `string_kw` to `PrimitiveStringToTextText`).
- **Verification:** `test_printers` matches the base exactly (165711 passed; the 5 `sql_table`
  failures are a pre-existing WidgetTable `length` bug, confirmed by a stashed-base run).
  `test_readers` clean. `test_text_navigations` shows the same 5 pre-existing failures
  (conversation_editor, dvdrental_catalog, filesystem, formula, navigator) that the untouched
  base commit also produces — no regressions.
