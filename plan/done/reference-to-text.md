# Plan: `ReferenceToText` and `ReferenceToHumanReadableText` projections

## Context

A `Reference` is a linked list of `ReferenceStep`s ([program/src/reference/Reference.jl:40-176](program/src/reference/Reference.jl#L40-L176)) that names a location inside a document. Today the only human view is `Base.show` ([Reference.jl:230-263](program/src/reference/Reference.jl#L230-L263)) — uncolored, single-line, impossible to scan when a `ProjectionReference` carries a nested `output_path`.

We want two projections that turn a `Reference` into a `TextText`:

1. **`ReferenceToText`** — the **short form**: a single colored line, the same compact shape as `Base.show` but rendered as a `TextText` with color-coded tokens. Suitable for status lines, inline labels, and dense debugger views.
2. **`ReferenceToHumanReadableText`** — the **long form**: a multi-line narrative that reads in **reverse order** (innermost step first), one phrase per line, with each step described in English and tagged with the Julia type of the value the step is applied to. Suitable for tooltips, "what is selected?" panels, and onboarding views.

These are real projections rather than plain functions so they compose with the rest of the projection pipeline, get reactive rendering for free when wired into a `Cell`, and follow the codebase's established style (cf. [ObjectToSyntax](program/src/projection/primitive/ObjectToSyntax.jl), which similarly projects non-document Julia values).

## File location

New file: [program/src/projection/primitive/ReferenceToText.jl](program/src/projection/primitive/ReferenceToText.jl), included in [program/src/Projectured.jl](program/src/Projectured.jl) immediately after `include("projection/primitive/PrimitiveToText.jl")` (line 103). It only depends on Reference, Text, Font, Color, and IoMap modules — all loaded earlier.

Add to the public-API section of Projectured.jl:

```julia
using .ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
export ReferenceToText, ReferenceToHumanReadableText
```

## Module shape

```julia
module ReferenceToTextModule
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ReferenceModule: Reference, ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          ReferenceStep, RangeReference, FieldReference, ProjectionReference,
                          PointReference, TypeReference, FunctionReference,
                          is_element_reference, is_position_reference, head, tail,
                          evaluate_reference
import ..TextModule: TextDocument, TextText, TextString, TextNewline
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default, color_solarized_gray, color_solarized_cyan,
                      color_solarized_magenta, color_solarized_orange,
                      color_solarized_green, color_solarized_yellow, color_solarized_red
import ..IoMapModule: SimpleIoMap
export ReferenceToText, ReferenceToHumanReadableText
end
```

Shared helper (file-private):

```julia
_tok(content::AbstractString, font::StyleFont, color::StyleColor) =
    TextString(content, font, color)
```

For both projections:

- `map_reference_forward(::T, ::SimpleIoMap, _) = nothing`
- `map_reference_backward(::T, ::SimpleIoMap, _) = nothing`

v1 does not map sub-selections between Reference steps and TextText spans — the output `TextText.selection` is always `nothing`. A later revision can add per-step selection mapping if a UI needs it.

`projection_read` is not overridden; the default handles `ReplaceSelectionOperation` by calling `map_reference_backward`, which returns `nothing` → no operation.

---

## `ReferenceToText` (short form)

```julia
struct ReferenceToText <: Projection
    font::StyleFont
end
ReferenceToText(; font=font_ubuntu_monospace_regular_24) = ReferenceToText(font)

projection_print(p::ReferenceToText, ::Nothing,                recursion, ctx) = _short(p, nothing)
projection_print(p::ReferenceToText, ::EmptyReferencePath,     recursion, ctx) = _short(p, EmptyReferencePath())
projection_print(p::ReferenceToText, r::ConcreteReferencePath, recursion, ctx) = _short(p, r)
```

`_short(p, r)` builds a `Vector{TextDocument}` of token spans (no `TextNewline` entries), then returns:

```julia
SimpleIoMap(p, r, TextText(CellVector(() -> spans), Cell(() -> nothing)))
```

### Per-step token rendering

| Step | Tokens (color) | Example |
|---|---|---|
| `FieldReference(name)` | `.` gray · `name` cyan | `.entries` |
| `RangeReference` element | `[` gray · `i` magenta · `]` gray | `[3]` |
| `RangeReference` position | `{` gray · `k` magenta · `}` gray | `{2}` |
| `RangeReference` range | `{` gray · `s` magenta · `:` gray · `e` magenta · `}` gray | `{1:4}` |
| `TypeReference(type)` | `{{` gray · `type` orange · `}}` gray | `{{Int}}` |
| `FunctionReference(f)` | `(` gray · `f` green · `)` gray | `(visible)` |
| `PointReference(x,y)` | `@(` gray · `x` magenta · `,` gray · `y` magenta · `)` gray | `@(10,20)` |
| `ProjectionReference(p, output)` | `<` gray · `name(p)` yellow · `:` gray · *recurse `output` inline* · `>` gray | `<SortingProjection: .value{1}>` |
| `EmptyReferencePath` (only at top) | `(no selection)` gray | — |
| `nothing` (only at top) | `(no selection)` gray | — |
| Fallback unknown step | `string(step)` red | — |

`name(p)` is `string(typeof(p))`.

No separators are emitted between steps — concatenation matches the existing `Base.show` shape.

ProjectionReference nesting is rendered inline (still one line). No `TextNewline` is ever emitted by `ReferenceToText`.

---

## `ReferenceToHumanReadableText` (long form)

```julia
struct ReferenceToHumanReadableText <: Projection
    document::Any           # the document to evaluate the reference against
    font::StyleFont
end
ReferenceToHumanReadableText(document; font=font_ubuntu_monospace_regular_24) =
    ReferenceToHumanReadableText(document, font)

projection_print(p::ReferenceToHumanReadableText, ::Nothing,                recursion, ctx) = _long(p, nothing)
projection_print(p::ReferenceToHumanReadableText, ::EmptyReferencePath,     recursion, ctx) = _long(p, EmptyReferencePath())
projection_print(p::ReferenceToHumanReadableText, r::ConcreteReferencePath, recursion, ctx) = _long(p, r)
```

The `document` field is the document the reference points into; it is needed to derive the Julia type of the value at each step prefix.

### Phrasing templates

Each step becomes one line: `the <step-description> of the <parent-type>`, where `<parent-type>` is `string(typeof(evaluate_reference(p.document, prefix)))` and `prefix` is the path up to *but not including* the current step.

| Step | Phrase |
|---|---|
| `FieldReference(name)` | `the {name} of the {parent-type}` |
| `RangeReference` element `i` | `the {ordinal(i)} element of the {parent-type}` |
| `RangeReference` position `k` | `the {ordinal(k)} position of the {parent-type}` |
| `RangeReference` range `s:e` | `the range {s} to {e} of the {parent-type}` |
| `TypeReference(T)` | `the elements of type {T} of the {parent-type}` |
| `FunctionReference(f)` | `the elements matching {f} of the {parent-type}` |
| `PointReference(x,y)` | `the pixel at ({x}, {y}) of the {parent-type}` |
| `ProjectionReference(p, output)` | first recurse into `output` (inner phrases above), then emit `inside the {name(p)} projection of the {parent-type}` |
| Fallback unknown step | `string(step)` in red, no type tail |

`ordinal(n)` is a small file-private helper returning `"1st"`, `"2nd"`, `"3rd"`, `"4th"`, ….

Type names come straight from `string(typeof(...))` — no friendly-name dictionary in v1. Raw output like `JsonString`, `JsonObjectEntry`, `CellVector{JsonObjectEntry}` is accepted.

### Coloring within a phrase

| Token kind | Color |
|---|---|
| ordinal numbers, coordinates, range bounds | magenta |
| field names | cyan |
| type names from `TypeReference` and projection names | orange |
| function names from `FunctionReference` | green |
| `{parent-type}` (Julia type name) | orange |
| connective words (`the`, `of`, `element`, `position`, `inside`, `projection of`, …) | gray |
| fallback unknown step | red |

### Reverse-order assembly

Walk the path front-to-back into a `Vector{Vector{TextDocument}}` of lines (each inner vector is the spans of one phrase). After the walk, `reverse!` the outer vector, then splice `TextNewline()` between lines into a single flat `Vector{TextDocument}` for the final `TextText`.

For `ProjectionReference` at any depth, recursively expand its `output_path` into lines first (they sit *above* the projection's own line, because they live *inside* its output), then append the projection's own `inside the {Name} projection of the {parent-type}` line, then continue with the rest of the outer path. The recursion threads a `prefix::ReferencePath` argument so each step knows what to evaluate against. When entering a `ProjectionReference`, the nested recursion's prefix starts fresh at `EmptyReferencePath()` (the projection's output root).

### Type lookup

```julia
_parent_type_name(document, prefix) =
    try
        string(typeof(evaluate_reference(document, prefix)))
    catch
        "?"           # stale/invalid prefix — degrade gracefully
    end
```

The `"?"` substitute is rendered in red. The remaining phrase still emits with its step-description prefix in normal colors.

---

## Edge cases (both projections)

| Input | Output |
|---|---|
| `nothing` | single gray `no selection` span, no newlines |
| `EmptyReferencePath()` | single gray `no selection` span, no newlines |
| `ConcreteReferencePath` whose tail is `EmptyReferencePath` | normal rendering of the head only |
| `ProjectionReference` with empty `output_path` | short form: `<Name:>` — long form: skip the inner phrases, emit only `inside the {Name} projection of the {parent-type}` |
| `evaluate_reference` throws for a partial prefix (long form only) | substitute `"?"` (red) for the parent-type tail and continue rendering |

---

## Verification

REPL smoke test (per [guide/debugging.md](guide/debugging.md)):

```julia
using Projectured
doc = JsonDocument(...)                       # any document the test suite already builds
ref = @reference .entries[3].key{2}

short_iomap = projection_print(ReferenceToText(), ref)
short = short_iomap.output
# expect a single-line TextText with ~10 colored spans, no TextNewline entries

long_iomap = projection_print(ReferenceToHumanReadableText(doc), ref)
long = long_iomap.output
# expect 4 phrase lines (3 TextNewlines), innermost step first, e.g.:
#   the 2nd position of the JsonString
#   the key of the JsonObjectEntry
#   the 3rd element of the CellVector{JsonObjectEntry}
#   the entries of the JsonObject
```

Round-trip the outputs through `TextTextToString` to get a stripped-text preview and eyeball the phrasing.

Automated test — add cases to [test/src/document/TextTest.jl](test/src/document/TextTest.jl):

- Build a reference exercising every step kind plus a nested `ProjectionReference`.
- For `ReferenceToText`: assert the output `TextText` contains zero `TextNewline` entries; spot-check a couple of spans' `font_color` against the exported color constants using `===`.
- For `ReferenceToHumanReadableText`: assert the line count equals `(step_count + nested_step_count)`; assert the first line corresponds to the deepest (last) step of the original path.

---

## Risks

1. **Open step taxonomy.** `ReferenceStep` is an open abstract type ([Reference.jl:40](program/src/reference/Reference.jl#L40)). New subtypes would otherwise throw `MethodError` — the red-text fallback method on the abstract type surfaces the gap without crashing.
2. **Stale documents in the long form.** The `document` field is captured at projection construction time; if the document mutates and the consumer doesn't reconstruct the projection, type lookups can lag. Document this in the function docstring; reactive callers should rebuild the projection in a `Cell` keyed on `document`.
3. **Long parameterized type names** (e.g. `CellVector{JsonObjectEntry}`) can overflow narrow UI surfaces. Acceptable for v1; the friendly-name dictionary is the natural follow-up.
4. **Newlines must be standalone `TextNewline()` spans** — never embedded `\n` in a `TextString.content` (Text.jl treats lines as separate elements).
5. **Selection is not mapped between Reference and TextText.** Clicking a token in the rendered TextText will not (yet) reposition selection on the input Reference. `map_reference_forward`/`backward` return `nothing` until a UI surface needs the round-trip.
