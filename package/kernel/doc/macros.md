# Document, Projection, and IoMap Macros

Three macros — `@document`, `@projection`, and `@iomap` — generate the
boilerplate that makes the cell-based code in the rest of the codebase look
like ordinary Julia. They are defined in
[document/Document.jl](../../../package/kernel/main/document/Document.jl),
[projection/Projection.jl](../../../package/kernel/main/projection/Projection.jl), and
[projection/IoMap.jl](../../../package/kernel/main/projection/IoMap.jl) respectively.

All three share the same core pattern: declared field types are *what you
mean*, but every field is *stored as a `Cell`* and accessed transparently
through generated `getproperty` / `setproperty!` methods.

## `@cell_struct` — the codegen the three build on

The shared pattern is implemented **once, in the cell layer**:
[cell/CellStruct.jl](../../../package/kernel/main/cell/CellStruct.jl) defines
`@cell_struct struct T [<: Super] … end` — every field becomes a transparent
`Cell` (auto-wrapping constructor, read/write-through accessors, raw cells via
`getfield`), and `field::T = value` defaults produce the keyword constructor
described below. It injects no supertype and carries no document, projection,
or IoMap vocabulary.

`@iomap` and `@projection` are exactly `@cell_struct` plus their default
supertype: they inject `<: IoMap` / `<: Projection` when none is written and
delegate to the cell layer's assembler (`cell_struct_exprs`). `@document`
generates its own kind-parameterized stem (see below) and reuses the cell
layer's keyword-constructor builders (`cell_struct_kw_params`, `cell_struct_kwctor`). Use
`@cell_struct` directly for a transparent-Cell struct that is none of the
three framework kinds.

## Default base supertype

Each macro **supplies its framework base supertype by default**, so you don't
repeat the obvious:

| Macro | Bare form | Expands to |
|---|---|---|
| `@document struct T … end`   | no `<:` | `mutable struct T <: Document … end` |
| `@projection struct T … end` | no `<:` | `struct T <: Projection … end` |
| `@iomap struct T … end`      | no `<:` | `struct T <: IoMap … end` |

An **explicit supertype always wins**. This is how a document declares its
*domain* supertype — `@document struct JsonString <: JsonDocument` keeps
`JsonDocument` (and since `JsonDocument <: Document`, it is still a `Document`).
Likewise `@projection struct Foo <: SomethingElse` keeps `SomethingElse`.

So the default only kicks in when you write no supertype at all; reach for it
whenever the base type is the one you'd have written anyway. The injected
`Document` / `Projection` / `IoMap` name resolves in the *calling* module, so
that module must have it in scope (every framework module already imports it).

## `@document`

```julia
@document struct JsonString <: JsonDocument
    value::String
end
```

The macro rewrites the struct into the **kind-parameterized stem**: an
immutable struct with one cell type-parameter per field
(see [plan/pending/cell-kind-documents.md](../../../plan/done/cell-kind-documents.md)),
plus an injected `selection::Reference = nothing` field appended as the last
field — the programmer never writes it, and writing it by hand is an error:

```julia
struct JsonString{C1 <: AbstractCell, C2 <: AbstractCell} <: JsonDocument
    value::C1          # a cell holding the String
    selection::C2      # injected by the macro: a cell holding the Reference
end
```

The *cell kind* in the fields decides the node's behavior — `ReactiveCell{T}`
(the reactive engine, historic `Cell`), `MutableCell{T}` (plain box, no
reactive bookkeeping), or `ImmutableCell{T}` (read-only, zero-cost). The bare
name is a UnionAll matching every kind, so `::JsonString` dispatch and
`x isa JsonString` cover all of them. The macro also generates:

- **A `getproperty` method**: `s.value` calls `getfield(s, :value)[]` — one
  uniform method for every kind; a reactive dependency is registered only when
  the cell is reactive.
- **A `setproperty!` method**: `s.value = "x"` calls
  `getfield(s, :value)[] = "x"` — invalidates dependents on the reactive kind,
  plainly stores on the mutable kind, and is a `MethodError` on the immutable
  kind (that is the contract).
- **An auto-wrapping constructor** (bare name): `JsonString("x")` wraps raw
  values in `ReactiveCell{Any}` — exactly the historic untyped `Cell`, so the
  bare name builds the reactive kind with unchanged semantics. Cells (of any
  kind, even mixed per-field) pass through as-is.
- **Kind aliases + ctors**: `RJsonString` (what the bare ctor builds),
  `IJsonString` / `MJsonString` (immutable / mutable kinds with *typed* cells,
  `ImmutableCell{String}` etc.), each with value-accepting and keyword ctors.
  The aliases are exported by the macro itself.
- **Kind conversion** happens through the generic functions, not ctors:
  `snapshot(doc)` (→ immutable), `hydrate(doc)` (→ reactive),
  `rekind(MutableCell, doc)`, and `cell_kind(doc)` to query.

Why loose bounds (`C <: AbstractCell`, not `C <: AbstractCell{String}`)?
`AbstractCell{T}` is invariant, and the projection machinery freely stores
untyped cells and even non-`String` values (template `bound(…)` markers) in a
"String" field before stripping them — declared types are enforced by the
typed kind ctors, not by the type system.

### Why every field is a cell

The uniformity matters:

1. Any field can be wired into a reactive computation later by calling
   `set_function!(getfield(obj, :field), thunk)` — without changing types.
2. Projections can read any field as if it were the source of truth and the
   reactive engine will invalidate the projection automatically.
3. One printer/reader body serves every kind, because access goes through the
   same `getproperty` for all of them.

### Escape hatch

When you genuinely need the raw cell (for example to share it between two
documents or pass it to `set_function!`), use `getfield(obj, :field)`. The
projection layer does this often, e.g. to make the `selection` field of a
`SyntaxLeaf` literally the same Cell as the upstream `JsonString.selection`.
Since the stem is immutable, such sharing must be established at
construction time — a field's cell object can never be swapped afterwards.

## `@domain`

```julia
@domain Json
```

One line generates a document domain's **insertion kit**: the abstract root
(`JsonDocument <: Document`, **exported** from the calling module — a domain
never re-exports its own root by hand, and an adopted `root = X` is exported
too), the empty placeholder
(`@document struct JsonNothing`), the typed-name insertion buffer
(`@document struct JsonInsertion` with `value::String = ""` plus the
`JsonInsertion("…")` convenience constructor), the **Insert-key gesture**
that turns the placeholder into the insertion (cursor in the buffer), and the
**insertion traits** the completion machinery dispatches on —
`domain_prefix`, `domain_insertion`, `insertion_root`, `nothing_document`,
`insertion_document`, the lowercase domain name as the insertion's alias, and
the placeholder's `insertable` opt-out.

Each `root = X` / `nothing = X` / `insertion = X` option **adopts** an
existing type instead of generating one (only its traits and gestures are
emitted); the adopted type must already be defined at the call site — e.g.
`@domain Julia root = JuliaDocument nothing = JuliaNothing insertion =
JuliaInsertion`, because `JuliaNothing` doubles as the parsed `nothing`
literal.

What the completion machinery then gives the domain for free: the reflected
candidate list (`insertion_candidates(JsonDocument)`, every insertable
concrete subtype — zero-arg constructible or with an `@insertion`
method), derived names (`JsonString` / `json string`, prefix-free inside the
domain), live completion + commitability colouring in the shared insertion
leaf, Enter-commit of unambiguous prefixes, Tab completion, and the
Insert ⇄ Escape loop between placeholder and insertion. Not generated
(layering): the two projection-table lines in the domain's `ToSyntax`
(`XInsertion => DomainInsertionToSyntaxLeaf(XDocument)` via the domain's
`XInsertionToSyntaxLeaf()` delegate, `XNothing => NothingToSyntaxLeaf()`).

## `@insertion`

```julia
@insertion JsonString    = @with_selection JsonString("") value{0}
@insertion JuliaFunction = julia_scaffold("function")
```

The document a committed insertion of that candidate becomes — `@domain`'s
companion. A candidate whose empty instance is already right needs no
`@insertion` at all: the zero-arg constructor is the fallback. The macro is for
the rest — a cursor to place (an empty string wants a caret *inside* it, not a
whole-node selection) or a scaffold of holes to build.

It expands to a single **fully qualified** `make_insertion_document` method, so
a domain declares its factories without importing the generic it extends. The
type matches its subtypes too (`::Type{<:JsonString}`).

## `@projection`

```julia
# illustrative — a projection whose active branch is a reactive cell.
# No `<: Projection`: the macro supplies it (see "Default base supertype").
@projection struct ReactiveBranchProjection
    projections::Vector{Any}
    index::Cell
end
```

Identical mechanic to `@document`, minus the immutable I-struct and
conversion constructors. In the current codebase `@projection` is the standard
way to declare a projection struct — the `…ToSyntax*` / `…ToText` / the
`Widget…ToGraphicsCanvas` projections all use it — so the `<: Projection` is
defaulted in (it was redundant on every one of them).

A projection that genuinely needs a *different* supertype still writes it
explicitly (`@projection struct Foo <: SomethingElse`). And a plain
`struct MyProjection <: Projection ... end` — declared without the macro —
remains a valid option for a projection with no reactive fields; a plain struct
gets no defaulting, so it must spell out `<: Projection` itself.

## `@iomap`

```julia
@iomap struct TextToGraphicsIoMap
    projection::Any
    input::TextText
    output::GraphicsCanvas
    char_to_coord::Cell
end
```

Same as `@projection` for IoMap structs. It defaults the supertype to `<: IoMap`
when none is given (see "Default base supertype" — `@iomap` was the first of the
three to do this), so the resulting struct satisfies the IoMap interface (every
iomap has `projection`, `input`, `output` fields).

## Default field values (`@kwdef`-style)

All three macros (and the underlying `@cell_struct`) accept `Base.@kwdef`-style
defaults on fields, so you no longer need an outer convenience constructor whose
only job is to fill in defaults:

```julia
@projection struct WidgetButtonToGraphicsCanvas      # <: Projection is defaulted in
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
struct and its immutable `I`-prefixed snapshot — but only when **the programmer**
declares at least one field default; the always-defaulted, macro-injected
`selection` field does not itself count. A struct with no defaults of its own
(`JsonString` above) gets no `JsonString(; …)`, which leaves that signature free
for a hand-written keyword constructor that needs to do more than fill fields
(`WorkbenchAssistant` back-links its draft this way). A struct with no fields of
its own beyond the injected `selection` (e.g. `JsonNull`) is the exception: `Foo()`
has to come from somewhere, so it gets the generated keyword constructor too. Why
`Base.@kwdef` can't simply be stacked on these macros (macro-ordering and the
dueling inner constructors), and why the defaults must be stripped out of the
struct body, is spelled out in `plan/done/macro-default-field-values.md`.

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
  needs value comparison (e.g. `search_references`) compares the unwrapped
  *leaf values*, not whole documents.

## How this pattern threads through the codebase

- Domain types (`JsonString`, `XmlElement`, `WidgetButton`, …) use
  `@document`.
- IoMaps with reactive subfields (`SortingProjectionIoMap`,
  `TextToGraphicsIoMap`, `NestingProjectionIoMap`, …) use a mixture of
  hand-rolled structs and `@iomap`.
- Most projection structs use `@projection` (with the `<: Projection` defaulted
  in) — the `…ToSyntax*` / `…ToText` / `Widget…ToGraphicsCanvas` families. A
  plain `struct ... <: Projection` is the exception, used when the macro can't
  be: `SyntaxNodeToText` stays plain because it stores a `Function` field (which
  the auto-wrapping ctor would turn into a thunk — see "Gotchas"), and
  `AlternativeProjection` stays plain even though it holds a reactive
  `index::Cell`, reading the cell explicitly rather than through `@projection`.
  A plain struct gets no supertype defaulting, so it must write `<: Projection`.

The result is that domain and projection code reads like Julia you'd write
without any framework — the reactivity is invisible until you reach for
`Cell`, `set_function!`, or `getfield` explicitly.
