# Document, Projection, and IoMap Macros

Three macros — `@document`, `@projection`, and `@iomap` — generate the
boilerplate that makes the cell-based code in the rest of the codebase look
like ordinary Julia. They are defined in
[common/Document.jl](../program/src/common/Document.jl),
[common/Projection.jl](../program/src/common/Projection.jl), and
[common/IoMap.jl](../program/src/common/IoMap.jl) respectively.

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

## When to declare a field as `::Cell` vs. let the macro wrap it

The macros wrap *every* declared field in a `Cell` regardless of the type
annotation. The annotation is preserved in the generated I-struct (for
`@document`) so it can be used for serialisation and type-stable
inspection. So the rule is:

- Declare the field with its **logical** type (`::String`, `::Reference`,
  `::Int`) — that is what the I-struct will use and what `setproperty!`
  expects when writing.
- The macro takes care of the Cell wrapping for the runtime struct.

The only time you'd annotate `::Cell` directly is when the field really
*is* the cell itself (e.g. when sharing a cell between two structs, or when
the cell holds a thunk rather than a value).

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
