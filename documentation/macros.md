# Document, Projection, and IoMap Macros

Three macros — `@document`, `@projection`, and `@iomap` — generate the
boilerplate that makes the cell-based code in the rest of the codebase look
like ordinary Julia. They are defined in
[common/Document.jl](../package/kernel/src/common/Document.jl),
[common/Projection.jl](../package/kernel/src/common/Projection.jl), and
[common/IoMap.jl](../package/kernel/src/common/IoMap.jl) respectively.

All three share the same core pattern: declared field types are *what you
mean*, but every field is *stored as a `Cell`* and accessed transparently
through generated `getproperty` / `setproperty!` methods.

## `@document`

```julia
@document struct JsonString <: JsonDocument
    value::String
    selection::Reference
end
```

The macro rewrites the struct so that every field becomes `::Cell`:

```julia
mutable struct JsonString <: JsonDocument
    value::Cell        # actually holds a Cell wrapping a String
    selection::Cell    # actually holds a Cell wrapping a Reference
end
```

It also generates:

- **A `getproperty` method**: `s.value` calls `getfield(s, :value)[]`,
  returning the current value and registering a reactive dependency if any
  computed cell is observing.
- **A `setproperty!` method**: `s.value = "x"` calls
  `getfield(s, :value)[] = "x"`, which invalidates downstream dependents.
- **An auto-wrapping inner constructor**: callers can pass either a plain
  value or an already-wrapped `Cell`; both work.
- **An I-prefixed immutable struct** (`IJsonString`) with the original
  declared field types — no Cell indirection. This is useful for
  snapshotting or serialisation.
- **Conversion constructors**: `IJsonString(obj::JsonString)` snapshots all
  cells; `JsonString(ifoo::IJsonString)` hydrates back into reactive cells.

### Why every field is a Cell

The uniformity matters:

1. Any field can be wired into a reactive computation later by calling
   `setfn!(getfield(obj, :field), thunk)` — without changing types.
2. Projections can read any field as if it were the source of truth and the
   reactive engine will invalidate the projection automatically.
3. Equality, struct hashing, and reflection still work because the field
   layout is consistent.

### Escape hatch

When you genuinely need the raw `Cell` (for example to share it between two
documents or pass it to `setfn!`), use `getfield(obj, :field)`. The
projection layer does this often, e.g. to make the `selection` field of a
`SyntaxLeaf` literally the same Cell as the upstream `JsonString.selection`.

## `@projection`

```julia
# illustrative — a projection whose active branch is a reactive cell
@projection struct ReactiveBranchProjection <: Projection
    projections::Vector{Any}
    index::Cell
end
```

Identical mechanic to `@document`, minus the immutable I-struct and
conversion constructors. Use it when your projection struct has reactive
fields (e.g. an `index` cell that switches the active branch) and you want
transparent access. In the current codebase `@projection` is used by the
`Widget…ToGraphicsCanvas` projections.

Most simple projections do not need `@projection` — a plain
`struct MyProjection <: Projection ... end` suffices.

## `@iomap`

```julia
@iomap struct TextToGraphicsIoMap
    projection::Any
    input::TextText
    output::GraphicsCanvas
    char_to_coord::Cell
end
```

Same as `@projection` for IoMap structs. The macro additionally adds the
`<: IoMap` supertype if it isn't already present, so the resulting struct
satisfies the IoMap interface (every iomap has `projection`, `input`,
`output` fields).

## Default field values (`@kwdef`-style)

All three macros accept `Base.@kwdef`-style defaults on fields, so you no longer
need an outer convenience constructor whose only job is to fill in defaults:

```julia
@projection struct WidgetButtonToGraphicsCanvas <: Projection
    measure::Function
    label::StyleText
    background_color::StyleColor
    corner_radius::Int = 4        # default
    shadow_offset::Int = 0        # default
end
```

When **at least one** field carries a default, the macro additionally emits a
**keyword** constructor:

```julia
WidgetButtonToGraphicsCanvas(; measure, label, background_color)        # corner_radius=4, shadow_offset=0
WidgetButtonToGraphicsCanvas(; measure, label, background_color, corner_radius = 8)
```

Semantics deliberately match `Base.@kwdef`:

- **Defaults are keyword-only.** The positional auto-wrapping constructor is
  untouched and still requires *every* field — `T(a, b)` does not become
  partially-applicable. Use the keyword form to get defaults.
- **Fields without a default become required keywords** (`UndefKeywordError` if
  omitted), so the keyword form can construct the whole struct.
- **A later default may reference an earlier field by name** (e.g.
  `label::String = "n=" * string(value)`), exactly as keyword defaults do.
- The keyword constructor is **only** generated when a default is present, so
  every existing macro usage is byte-for-byte unchanged (no surprise keyword
  constructor appears on default-free types).

This is now the standard idiom across the codebase: the insertion-cursor /
empty-document types (`JsonInsertion`, `XmlInsertion`, `SyntaxInsertion`,
`DocumentNothing`, …) and the `*To*` projection style-config structs
(`@projection struct …ToSyntaxLeaf`) declare their defaults inline rather than via a
convenience constructor. Copy that pattern, not the old `Foo() = Foo(Cell(nothing), …)`
form.

For `@document`, the keyword constructor is generated for **both** the Cell-based
struct and its immutable `I`-prefixed snapshot. Why `Base.@kwdef` can't simply be
stacked on these macros (macro-ordering and the dueling inner constructors), and
why the defaults must be stripped out of the struct body, is spelled out in
`plan/done/macro-default-field-values.md`.

## When to declare a field as `::Cell` vs. let the macro wrap it

The macros wrap *every* declared field in a `Cell` regardless of the type
annotation. The annotation is preserved verbatim in the generated I-struct (for
`@document`), where it becomes an **enforced** field type. So the rule is:

- Declare the field with its logical type (`::String`, `::Reference`, `::Int`),
  **but the annotation must admit every value the field can actually hold.** If
  the domain ever stores `nothing` in a field as an empty sentinel — e.g. a
  number whose text has been fully deleted — the annotation must include it
  (`::Union{Real, Nothing}`), or snapshotting that document (`IFoo(foo)`) will
  throw when it tries to put `nothing` into a non-`Nothing` field. The runtime
  struct hides this (the field is really a `Cell`), so a dishonest annotation
  stays silent until the first snapshot.
- The macro takes care of the Cell wrapping for the runtime struct.

The only time you'd annotate `::Cell` directly is when the field really
*is* the cell itself (e.g. when sharing a cell between two structs, or when
the cell holds a thunk rather than a value).

## Gotchas these macros impose

All three macros (`@document`, `@projection`, `@iomap`) share the same generated
machinery, and with it the same three sharp edges:

- **A macro-wrapped field can never hold a `Cell` — or a `Function` — as its
  logical value.** The auto-wrapping inner constructor runs `x isa Cell ? x : Cell(x)`
  on every argument, so a value that *is* a `Cell` is stored unwrapped and read back
  transparently — there is no way to have a field whose value is itself a `Cell`. A
  `Function` is worse: `Cell(f)` builds a **computed thunk**, so the field would be
  *called* (with no args) when read, not returned — a config field like
  `marker_eligible::Any = some_predicate` silently breaks at runtime. (This is exactly
  the trap that forced `SyntaxNodeToText` to stay a plain `struct` instead of becoming
  `@projection`.) If you genuinely need to store a cell or a callable *as a value*, box
  it (e.g. in a one-element tuple or a wrapper struct), or keep it in a plain
  hand-rolled struct instead.
- **The macro emits the *only inner* constructor.** Any convenience constructor
  you write must therefore be an **outer** constructor (`Foo(args...) = Foo(...)`
  outside the `@document struct` body); an inner one would collide with the
  generated auto-wrapping constructor. (The one constructor the macro itself can
  add is the *outer* keyword constructor for `@kwdef`-style defaults — see
  "Default field values" above.)
- **Equality is identity, not structural.** A `@document` type is a `mutable
  struct`, so it keeps Julia's default *identity* `==`/`hash`; only the
  generated `I`-prefixed snapshot (`IFoo`, an immutable `struct`) compares
  structurally. Reference/path types define `==` by hand. Don't assume two
  freshly built documents with equal fields are `==` — they are not. Code that
  needs value comparison (e.g. `collect_references`) compares the unwrapped
  *leaf values*, not whole documents.

## How this pattern threads through the codebase

- Domain types (`JsonString`, `XmlElement`, `WidgetButton`, …) use
  `@document`.
- IoMaps with reactive subfields (`SortingProjectionIoMap`,
  `TextToGraphicsIoMap`, `NestingProjectionIoMap`, …) use a mixture of
  hand-rolled structs and `@iomap`.
- Projection structs are usually plain `struct ... <: Projection` because
  their configuration is immutable. `AlternativeProjection` is itself a plain
  `struct` even though it holds a reactive `index::Cell` (it reads the cell
  explicitly rather than through `@projection`); the `Widget…ToGraphicsCanvas`
  projections are the ones that actually use `@projection`.

The result is that domain and projection code reads like Julia you'd write
without any framework — the reactivity is invisible until you reach for
`Cell`, `setfn!`, or `getfield` explicitly.
