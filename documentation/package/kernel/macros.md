# Document, Projection, and IoMap Macros

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Three macros — `@document`, `@projection`, and `@iomap` — generate the
boilerplate that makes the cell-based code in the rest of the codebase look
like ordinary Julia. They are defined in
[document/DocumentMacro.jl](../../../source/kernel/document/DocumentMacro.jl),
[projection/Projection.jl](../../../source/kernel/projection/Projection.jl), and
[iomap/IoMapDefaults.jl](../../../source/kernel/iomap/IoMapDefaults.jl) respectively.

All three share the same core pattern: declared field types are *what you
mean*, but every field is *stored as a `Cell`* and accessed transparently
through generated `getproperty` / `setproperty!` methods.

## `@cell_struct` — the codegen the three build on

The shared pattern is implemented **once, in the cell layer**:
[cell/CellStruct.jl](../../../source/kernel/cell/CellStruct.jl) defines
`@cell_struct struct T [<: Super] … end` — every field becomes a transparent
`Cell` (auto-wrapping constructor, read/write-through accessors, raw cells via
`getfield`), and `field::T = value` defaults produce the keyword constructor
described below. It injects no supertype and carries no document, projection,
or IoMap vocabulary.

`@iomap` and `@projection` are exactly `@cell_struct` plus their default
supertype: they inject `<: IoMap` / `<: Projection` when none is written and
delegate to the cell layer's assembler (`build_cell_struct_exprs`). `@document`
generates its own kind-parameterized stem (see below), but shares the cell
layer's codegen kit for everything that is not document-specific: the field
parse (`make_cell_struct_plan`, which reads the three field forms into a `CellStructPlan`),
the keyword-constructor builders (`build_cell_struct_kw_params`,
`build_cell_struct_kwctor`), and **Rule Y** (`build_cell_struct_positional_ctors` — filling
a trailing run of defaults positionally is a rule about any cell struct, not
about documents). `@document` is then a parse plus six emitters, each a pure
function of the plan. Use `@cell_struct` directly for a transparent-Cell struct
that is none of the three framework kinds.

## Default base supertype

Each macro **supplies its framework base supertype by default**, so you don't
repeat the obvious:

| Macro | Bare form | Expands to |
|---|---|---|
| `@document struct T … end`   | no `<:` | `T{…} <: AbstractT <: Document` — three types; see [`@document`](#document) |
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
(see [plan/done/cell-kind-documents.md](../../../plan/done/cell-kind-documents.md)),
plus an injected `selection::Union{Nothing, Reference} = nothing` field appended
as the last field — a `Reference` for what is selected inside this node, or
`nothing` for no selection. Around the stem it emits a per-schema **family** and
a **native mutable layout**:

```julia
abstract type AJsonString <: JsonDocument end   # the family both layouts share

struct JsonString{C1 <: AbstractCell, C2 <: AbstractCell} <: AJsonString
    value::C1          # a cell holding the String
    selection::C2      # injected by the macro: a cell holding the selection
end

mutable struct MJsonString <: AJsonString      # the native layout
    value::String                          # the declared type, with no cell box
    selection::Union{Nothing, Reference}
end
```

### Two layouts, one schema

| Type | What it is |
|---|---|
| `Foo{C1, …}` — the **stem** | The bare name. An immutable struct, one cell per field; every kind alias is a parameterization of it. |
| `MFoo` — the **native layout** | A real `mutable struct` holding the declared value types directly. No cell box, so `getproperty` / `setproperty!` are the default `getfield` / `setfield!` — byte-for-byte the struct you would have written by hand. It gets the same Rule Y positional and keyword constructors as the stem. |
| `AFoo` — the **family** | The abstract type both layouts subtype, so `get_document_family(T)` answers `AFoo` for either one and `x isa AFoo` covers both. |

The family sits between the stem and the supertype you wrote, so the domain
dispatch you declared is unchanged — `JsonString <: JsonDocument` still holds,
transitively. The two layouts are additive: the bare name is still the stem, and
every existing `Foo` / `Foo{…}` dispatch and alias means what it meant before.
The macro exports `AFoo` and `MFoo` itself.

**Declaring `selection` by hand.** You normally never write it. The one reason to
is a **value document** that must pin the field's *value* type — the isbits pivot:
`selection::ImmutableCell{Nothing}` is isbits and not selectable (a leaf value),
while the injected `Union{Nothing, Reference}` form is selectable. An explicit
`selection` must come **last** (anywhere else is an error) and defaults to
`nothing`, so it does not count as a programmer default and leaves Rule Y and the
keyword constructors gated exactly as the injected field would. `StyleText` is the
worked example:

```julia
@document ImmutableCell struct StyleText
    font::StyleFont
    color::StyleColor
    selection::Nothing
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
- **Spelling aliases + ctors**: `ICJsonString` / `MCJsonString` put every field in
  the immutable / mutable kind with *typed* cells (`ImmutableCell{String}` etc.),
  each with value-accepting and keyword ctors. `RCJsonString` names the
  all-reactive combination (`ReactiveCell{Any}` per field) but is a **type alias
  only** — it has no constructor, so build that kind through the bare name.
  `DCJsonString` names the **default combination** the bare `JsonString(…)` ctor
  builds: each field in the kind it declares, which equals `RCJsonString` only
  when no field declares one. The macro exports the aliases itself.

  Each name abbreviates a phrase, adjective first: `MCJsonString` is the mutable
  cell `JsonString`. The `C` says the variant keeps its fields in cells, which is
  what tells it from `MJsonString`, the plain `mutable struct` layout — the first
  holds one `MutableCell` box per field, the second its fields inline.
- **Kind conversion** happens through the generic functions, not ctors:
  `copy_document(doc)` deep-copies and preserves each cell's kind, and
  `copy_document(K, doc)` rebuilds every cell as kind `K` (reactive ↔ mutable ↔
  immutable). To query, `get_cell_struct_kind(doc)` (the cell layer) reads the
  kind a value's fields are built from — a cell struct's kind lives in its field
  cells, not in its type name.

Why loose bounds (`C <: AbstractCell`, not `C <: AbstractCell{String}`)?
`AbstractCell{T}` is invariant, and the projection machinery freely stores
untyped cells and even non-`String` values (template `bound(…)` markers) in a
"String" field before stripping them — declared types are enforced by the
typed kind ctors, not by the type system.

### Why every field is a cell

The uniformity matters:

1. Any field can be wired into a reactive computation later by calling
   `set_cell_function!(getfield(obj, :field), thunk)` — without changing types.
2. Projections can read any field as if it were the source of truth and the
   reactive engine will invalidate the projection automatically.
3. One printer/reader body serves every kind, because access goes through the
   same `getproperty` for all of them.

### Escape hatch

When you genuinely need the raw cell (for example to share it between two
documents or pass it to `set_cell_function!`), use `getfield(obj, :field)`. The
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
    input::TextBlock
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

For `@document`, the keyword constructor is generated for the bare name, the
`CI`-prefixed and `CM`-prefixed spellings, and the native `MFoo` layout — but only
when **the programmer** declares at least one field default; the
always-defaulted, macro-injected `selection` field does not itself count. A struct with no defaults of its own
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
annotation. The annotation is what the **typed spellings** enforce: `ICFoo` / `MCFoo`
build their cells from it (`ImmutableCell{String}`, …), while the bare reactive
kind stores every field as `Any`. So the rule is:

- Declare the field with its logical type (`::String`, `::Reference`, `::Int`),
  **but the annotation must admit every value the field can actually hold.** If
  the domain ever stores `nothing` in a field as an empty sentinel — e.g. a
  number whose text has been fully deleted — the annotation must include it
  (`::Union{Real, Nothing}`). A dishonest annotation stays silent under the bare
  name and then bites twice: `ICFoo(…)` / `MCFoo(…)` **throw** on a value the
  annotation rejects (`ImmutableCell{Real}(nothing)` has no method), and
  `copy_document(ImmutableCell, doc)` does *not* throw — it falls back to the
  value's own type, so the copy quietly lands **off** the alias and
  `copy isa ICFoo` is `false`.
- The macro takes care of the Cell wrapping for the runtime struct.

The only time you'd annotate `::Cell` directly is when the field really
*is* the cell itself (e.g. when sharing a cell between two structs, or when
the cell holds a thunk rather than a value).

## Gotchas these macros impose

All three macros (`@document`, `@projection`, `@iomap`) share the same generated
machinery, and with it the same three sharp edges:

- **A macro-wrapped field can never hold a `Cell` — or a `Computed` — as its
  logical value.** The auto-wrapping inner constructor runs `x isa Cell ? x : Cell(x)`
  on every argument, so a value that *is* a `Cell` is stored unwrapped and read back
  transparently — there is no way to have a field whose value is itself a `Cell`. A
  `Computed` is consumed the same way: it becomes the field's *derivation*, making it a
  computed cell, which is what `output = Computed(() -> …)` is for. If you genuinely
  need to store either *as a value*, box it (e.g. in a one-element tuple or a wrapper
  struct), or keep it in a plain hand-rolled struct instead.

  A **`Function` is an ordinary value** and needs none of this: a field may hold a
  callback, predicate, or factory, and reading it returns the function uncalled — so a
  config field like `marker_eligible::Any = some_predicate` is fine. Computedness is
  stated with `Computed`, never inferred from the value's type.
- **The macro emits the *only inner* constructor.** Any convenience constructor
  you write must therefore be an **outer** constructor (`Foo(args...) = Foo(...)`
  outside the `@document struct` body); an inner one would collide with the
  generated auto-wrapping constructor. (The one constructor the macro itself can
  add is the *outer* keyword constructor for `@kwdef`-style defaults — see
  "Default field values" above.)
- **Equality is identity for every kind but the immutable one.** The stem is an
  immutable struct, so `===` compares it field cell by field cell — but a
  `ReactiveCell` and a `MutableCell` are *mutable* objects, which `===` compares
  by identity. So two separately built `Foo`s (or `MFoo`s) with equal contents
  are **not** `==`. `ICFoo` is immutable the whole way down, stem and cells, so it
  is the one kind that compares structurally. Reference/path types define `==` by
  hand. Code that needs value comparison (e.g. `search_references`) compares the
  unwrapped *leaf values*, not whole documents.

## How this pattern threads through the codebase

- Domain types (`JsonString`, `XmlElement`, `WidgetButton`, …) use
  `@document`.
- IoMaps with reactive subfields (`SortingIoMap`,
  `TextToGraphicsIoMap`, `NestingIoMap`, …) use a mixture of
  hand-rolled structs and `@iomap`.
- Most projection structs use `@projection` (with the `<: Projection` defaulted
  in) — the `…ToSyntax*` / `…ToText` / `Widget…ToGraphicsCanvas` families. A
  plain `struct ... <: Projection` is the exception, used when the macro can't
  be: `AlternativeProjection` stays plain because it holds a reactive
  `index::Cell`, reading the cell explicitly rather than through `@projection`.
  (A `Function` field is no longer such a reason — `SyntaxCompoundToText`'s
  `marker_eligible` predicate is an ordinary value — so plain structs that carry
  one are free to move to the macro.)
  A plain struct gets no supertype defaulting, so it must write `<: Projection`.

The result is that domain and projection code reads like Julia you'd write
without any framework — the reactivity is invisible until you reach for
`Cell`, `set_cell_function!`, or `getfield` explicitly.
