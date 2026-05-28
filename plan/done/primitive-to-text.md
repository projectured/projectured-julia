# Plan: `PrimitiveToText.jl` — direct PrimitiveDocument → TextText projection

Add a new projection source file
`program/src/projection/primitive/PrimitiveToText.jl` that converts
`PrimitiveDocument` instances directly to a `TextText`, bypassing the
intermediate `SyntaxLeaf` representation.

The file mirrors [PrimitiveToSyntax.jl](../../program/src/projection/primitive/PrimitiveToSyntax.jl)
and bundles individual projections per primitive subtype plus a composite
`PrimitiveToText` constructor.

---

## Motivation

Today, rendering a `PrimitiveBool`, `PrimitiveNumber`, or `PrimitiveString`
into a text-domain context requires composing two projections:

```
PrimitiveDocument → SyntaxLeaf → TextText
                    (PrimitiveBoolToSyntaxLeaf, …)   (SyntaxLeafToText)
```

That two-step path is the right default when the value participates in a
larger syntax tree (e.g. JSON, Math, Julia). But several contexts need a
primitive value to land in the text domain directly without the syntax
detour:

- **Widget labels / inline values** — buttons, captions, and form fields that
  display a single editable scalar. The intermediate `SyntaxLeaf` is dead
  weight; its open/value/close span structure becomes a one-span TextText.
- **Conversation / book / table cells** — places that already aggregate
  styled spans and want to slot a primitive in as one of those spans without
  introducing a syntax tree.
- **Direct text-domain editing** — KeyPress/KeyDown handling can be wired
  straight from text-coordinate operations to `StringReplaceRangeOperation`
  /`NumberReplaceRangeOperation` without going through
  `SyntaxLeafToText`'s reverse mapping. Fewer projection hops means fewer
  places where reference mapping can drop a step.

Composing the two existing projections is functionally correct but adds an
extra IoMap layer per primitive instance and forces every consumer to
import both modules. A direct projection is simpler and faster for the
common "one editable scalar in a text container" case.

---

## Design

### File layout

`program/src/projection/primitive/PrimitiveToText.jl` defines module
`PrimitiveToTextModule`. Public exports:

- `PrimitiveBoolToText`
- `PrimitiveNumberToText`
- `PrimitiveStringToText`
- `PrimitiveToText` (composite constructor)

Imports follow the same pattern as
[PrimitiveToSyntax.jl](../../program/src/projection/primitive/PrimitiveToSyntax.jl):
`ProjectionApiModule`, `PrimitiveModule`, `TextModule`, `FontModule`,
`ColorModule`, `IoMapModule`, `IoMapApiModule`, `ReferenceModule`,
`ReferenceBuilderModule`, `ReferenceCaseModule`, `OperationModule`,
`KeyboardModule`, `TypeDispatchingModule`.

### Output shape

Each per-type projection emits a single `TextText` whose `elements` is a
`CellVector` of one `TextString` span:

| Projection | Spans (left to right) |
|---|---|
| `PrimitiveBoolToText` | `[ value ]` — single span containing `"true"` / `"false"` |
| `PrimitiveNumberToText` | `[ value ]` — single span containing the number's string form (or empty) |
| `PrimitiveStringToText` | `[ value ]` — single span containing the raw string (no surrounding quote delimiters) |

All three types use a one-span layout. `PrimitiveString` deliberately
omits the open/close quote spans that `PrimitiveStringToSyntaxLeaf`
emits: this projection is used in contexts (widget labels, conversation
cells, inline scalars) where the string is rendered as plain text rather
than as a syntactically quoted literal. If quotes are required, compose
through `PrimitiveStringToSyntaxLeaf` + `SyntaxLeafToText` instead.

The `TextText.elements` cell reads `b.value` / `n.value` / `s.value` so
reactive updates flow through.

The `TextText.selection` cell follows the same shape as
`SyntaxLeafToText`'s output: `.elements[1].content[k]` for all three
types.

### Per-type projection structs

```julia
struct PrimitiveBoolToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveBoolToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_cyan) = …

struct PrimitiveNumberToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveNumberToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) = …

struct PrimitiveStringToText <: Projection
    font::StyleFont
    color::StyleColor
end
PrimitiveStringToText(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) = …
```

Field defaults match the colors currently used in `PrimitiveToSyntax.jl`
so visual output is identical to the two-stage path.

### `projection_print`

Each method returns `SimpleIoMap(p, input, TextText(...))`.

`PrimitiveBoolToText`:

```julia
function projection_print(p::PrimitiveBoolToText, b::PrimitiveBool, recursion, reference)
    span = TextString(() -> string(b.value), p.font, p.color)
    out = TextText(CellVector(() -> TextDocument[span]),
                   Cell(() -> _bool_to_text_selection(b)))
    SimpleIoMap(p, b, out)
end
```

`PrimitiveNumberToText` is analogous with `() -> string(something(n.value, ""))`.

`PrimitiveStringToText`:

```julia
function projection_print(p::PrimitiveStringToText, s::PrimitiveString, recursion, reference)
    value = TextString(() -> something(s.value, ""), p.font, p.color)
    out = TextText(CellVector(() -> TextDocument[value]),
                   Cell(() -> _string_to_text_selection(s)))
    SimpleIoMap(p, s, out)
end
```

The selection conversion helpers (`_bool_to_text_selection` etc.) translate
`Primitive*.selection[]` (which is `.value[k]` or `.value[range]`) into
the `TextText`-domain shape `.elements[1].content[k]`:

| Primitive selection | Output |
|---|---|
| `nothing` | `nothing` |
| `.value[k]` | `.elements[1].content[k]` |
| `.value[range]` | `.elements[1].content[range.start]` |

(Range selections collapse to a cursor at `range.start` to match the
existing `SyntaxLeafToText` behaviour.)

### Reference mapping

`map_reference_forward` / `map_reference_backward` translate between the
primitive domain's `.value[k]` references and the text domain's
`.elements[1].content[k]` paths. All three types use the same single-span
shape:

```julia
forward:   .value[k]                → .elements[1].content[k]
backward:  .elements[1].content[k]  → .value[k]
```

Because no quote delimiters are emitted, every text-domain position
corresponds directly to a primitive `.value[k]` position — no
`ProjectionReference` wrapping is needed.

### `projection_read`

For all three types, accept `ReplaceSelectionOperation` and translate the
path back through `map_reference_backward`:

```julia
function projection_read(p::PrimitiveBoolToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end
```

For `PrimitiveStringToText`, also handle `KeyPress` and `KeyDown` to
produce `StringReplaceRangeOperation` directly, mirroring the existing
handlers in `PrimitiveStringToSyntaxLeaf`. The only difference is that
the input selection lives on the `PrimitiveString` itself (read via
`getfield(s, :selection)[]`) so the helpers from `PrimitiveToSyntax.jl`
(`_string_value_range`, `_string_value_path`) can be reused — consider
lifting them into a shared internal module if both files end up needing
them.

For `PrimitiveNumberToText`, a follow-up can wire `KeyPress`/`KeyDown` to
`NumberReplaceRangeOperation` similarly. Initial version can skip this
and only do `ReplaceSelectionOperation`, matching what
`PrimitiveNumberToSyntaxLeaf` does today.

### Composite constructor

```julia
function PrimitiveToText(; bool_kw=(), number_kw=(), string_kw=())
    TypeDispatchingProjection(
        PrimitiveBool   => PrimitiveBoolToText(; bool_kw...),
        PrimitiveNumber => PrimitiveNumberToText(; number_kw...),
        PrimitiveString => PrimitiveStringToText(; string_kw...),
    )
end
```

---

## Wiring into `Projectured.jl`

Add (in dependency order — after `TextModule`, after
`PrimitiveModule`, after `TypeDispatchingModule`):

```julia
include("projection/primitive/PrimitiveToText.jl")
```

near the other primitive-projection includes
([Projectured.jl:80-98](../../program/src/Projectured.jl#L80-L98)).

Add `using .PrimitiveToTextModule: …` and re-exports next to the
existing `PrimitiveToSyntaxModule` block
([Projectured.jl:236](../../program/src/Projectured.jl#L236),
[Projectured.jl:425](../../program/src/Projectured.jl#L425)).

---

## Tests

Add tests under `test/` that mirror the existing
`PrimitiveToSyntax`/`SyntaxToText` coverage:

1. **Print** — each per-type projection produces a `TextText` with the
   expected span count, contents, fonts, and colors.
2. **Reactivity** — mutating the primitive's `value` updates the
   corresponding `TextString.content` (verify via the reactive
   walker helpers; see [guide/testing.md](../../guide/testing.md)).
3. **Selection forward** — `.value[k]` on the primitive ⇒ correct
   `.elements[1].content[k]` on the `TextText`.
4. **Selection backward** — round-trip the above and confirm equality.
5. **KeyPress / KeyDown** on `PrimitiveStringToText` — produces
   `StringReplaceRangeOperation` with the expected `RangeReference`.

The composite `PrimitiveToText()` should also be exercised via
`test_printers` / `test_readers` (see
[guide/testing.md](../../guide/testing.md)).

---

## Files affected

| File | Kind of change |
|---|---|
| **New**: `program/src/projection/primitive/PrimitiveToText.jl` | New projection module |
| `program/src/Projectured.jl` | `include`, `using`, re-exports |
| **New**: `test/projection/primitive/PrimitiveToText_test.jl` (or however the test layout is named) | New tests |
| `guide/projection-system.md` | Optionally mention the direct primitive→text path as an alternative |

---

## Risks and open questions

- **Duplication with `PrimitiveToSyntax.jl` + `SyntaxToText.jl`.** The
  selection/range helpers (`_string_value_range`, `_string_value_path`)
  and the `_flat_to_text_elem_path`-style conversions overlap with
  existing code. Decide: copy them verbatim (cheap, drifts), lift them
  into an internal helper module (cleaner, more refactor), or have the
  new file `import` the private helpers from the existing modules
  (couples lifetimes). **Recommendation:** start with verbatim copies;
  refactor only after the second consumer appears.

- **When should consumers prefer this over the two-stage path?** Needs
  a one-paragraph note in the guide so future authors aren't tempted to
  duplicate it again. Rule of thumb: use the direct projection only
  when the surrounding context is *already* a `TextText` aggregator
  (Widget, Conversation, Table, etc.) and you do not need syntax-tree
  features like indentation, sibling separators, or nested children.

- **Number editing.** Initial version may or may not implement
  `KeyPress`/`KeyDown` for `PrimitiveNumberToText`. If included, must
  validate parseability (matching `evaluate_operation(::NumberReplaceRangeOperation, …)`
  in [Primitive.jl:164](../../program/src/document/Primitive.jl#L164));
  otherwise punt to a follow-up plan, since the SyntaxLeaf path already
  leaves this out.

- **`PrimitiveInsertion` / `PrimitiveForeign`.** These two
  `PrimitiveDocument` subtypes are not in the composite. Either declare
  them out of scope (consistent with `PrimitiveToSyntax`) or add a
  passthrough that emits an empty `TextText`. **Recommendation:** out of
  scope; document explicitly.
