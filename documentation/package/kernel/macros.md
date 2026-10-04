# Document, Projection, and IoMap Macros

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

`@document`, `@projection`, and `@iomap` generate the boilerplate that makes
the cell-based code in the rest of the codebase look like ordinary Julia. A
fourth macro, [`@projection_template`](#projection_template), writes the
`print_document`/`read_intent` pair of a structural projection from a builder
expression instead of by hand. Thirteen files of `source/` use it, among them
eleven of the thirty `*ToSyntax.jl` files; the other printers are written by hand.
They are defined in
[document/DocumentMacro.jl](../../../source/kernel/document/DocumentMacro.jl),
[projection/ProjectionMacro.jl](../../../source/kernel/projection/ProjectionMacro.jl),
[iomap/IoMapDefaults.jl](../../../source/kernel/iomap/IoMapDefaults.jl), and
[projection/ProjectionTemplate.jl](../../../source/kernel/projection/ProjectionTemplate.jl)
respectively.

All three share the same core pattern: declared field types are *what you
mean*, but every field is *stored as a `Cell`* and accessed transparently
through generated `getproperty` / `setproperty!` methods.

## `@cell_struct` — the codegen the three build on

The shared pattern is implemented **once, in the struct layer**:
[struct/CellStruct.jl](../../../source/kernel/struct/CellStruct.jl) defines
`@cell_struct struct T [<: Super] … end`: every field becomes a transparent
`Cell` (auto-wrapping constructor, read/write-through accessors, raw cells via
`getfield`), and `field::T = value` defaults produce the keyword constructor
described below. It injects no supertype and carries no document, projection,
or IoMap vocabulary.

`@iomap` and `@projection` are exactly `@cell_struct` plus their default
supertype: they inject `<: IoMap` / `<: Projection` when none is written and
delegate to the struct layer's assembler (`build_cell_struct_exprs`). `@document`
generates its own kind-parameterized stem (see below), but shares the struct
layer's codegen kit for everything that is not document-specific:

- the field parse (`make_cell_struct_plan`, which reads the four field forms into
  a `CellStructPlan`) and the argument parse (`parse_cell_struct_macro_arguments`);
- the kind and the value type of each field (`get_cell_struct_field_kinds`,
  `get_cell_struct_value_types`), and the declared type of a field of a kind
  (`build_cell_struct_field_type`);
- the rule that binds a type parameter from a constructor argument
  (`find_cell_struct_parameter_slots`, `get_cell_struct_argument_type`), and the names of
  the parameters for a type application (`get_cell_struct_parameter_names`);
- the keyword-constructor builders (`build_cell_struct_keyword_parameters`,
  `build_cell_struct_keyword_constructor`), and **Rule Y**
  (`build_cell_struct_positional_constructors`).
Rule Y fills a trailing run of defaults positionally; it is a rule about any
cell struct, not about documents. `@document` is then a parse plus six emitters, each a pure
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

So the default only applies when you write no supertype at all; reach for it
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
plus an injected `selection::Union{Nothing, Reference, SelectionDocument} = nothing`
field appended as the last field — a `Reference` for what is selected inside this
node, a `SelectionDocument` that holds a reference and says whether it is the live
selection, or `nothing` for no selection. Around the stem it emits a per-schema **family** and
a **native mutable layout**:

```julia
abstract type AJsonString <: JsonDocument end   # the family both layouts share

struct JsonString{C1 <: AbstractCell, C2 <: AbstractCell} <: AJsonString
    value::C1          # a cell holding the String
    selection::C2      # injected by the macro: a cell holding the selection
end

mutable struct MJsonString <: AJsonString      # the native layout
    value::String                          # the declared type, with no cell box
    selection::Union{Nothing, Reference, SelectionDocument}
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

### The layout list

```julia
@document [Kind] [[layouts]] struct T [<: Super] … end
```

An optional **layout list** — a bracketed, comma-separated list of codes right
before `struct` — says which layouts the schema emits: `C` the cell layout
(`Foo{C1, …}`), `M` the mutable native struct. A code names a layout and
nothing else; the family and the four spelling aliases (`RCFoo`/`ICFoo`/`MCFoo`/`DCFoo`)
are always generated regardless of the list. The default, when no list is
written, emits both `C` and `M`.

The list's **first entry sets what the bare name `Foo` means**:

| First entry | `Foo` means | Fits |
|---|---|---|
| `C` (the default) | the cell layout, `Foo{C1, …}` | anything an editor holds |
| `DC` | `DCFoo`, the concrete default spelling | a value document stored by value in a config cell, where a `Foo`-typed field must inline |
| `M` | `MFoo`, the plain `mutable struct` | a schema whose primary object is the one a simulator mutates |

`DC` emits nothing that `C` does not; it only moves the bare name one step in.
The coded name always resolves too. A `C` schema still gets `const ACFoo = Foo`,
so `ACFoo` names the cell layout whichever binding the bare name took. A `[Kind]`
token before the layout list (`ImmutableCell`, `MutableCell`, …) is the field
cell kind the auto-wrapping constructor uses; it is independent of the layout
list.

A docstring directly above `@document` documents the schema, and a lookup of
the bare name shows it, whichever layout the bare name took. The cell layout
always carries it, so `ACFoo` shows it too. When the list starts with `M` or
`I`, the native struct carries it as well, because the bare name is that
struct. Do not put a comment or a blank line between the docstring and
`@document`. Julia then discards the text.

A package that keeps the same list on every schema declares a preset once.
[`@document_preset`](../../../source/kernel/document/DocumentMacro.jl) defines
`@name` as `@document` with a fixed layout list, and every schema in the
package writes the preset's name instead of repeating the brackets:

```julia
@document_preset native_document [M, C]     # once, in the package root module

@native_document struct TicTocMessage1      # and then at every declaration
    name::String
end
```

A preset's own arguments still pass through, so a field-kind marker keeps
working: `@native_document ImmutableCell struct …`.

**Declaring `selection` by hand.** You normally never write it. The one reason to
declare it is a **value document** that must pin the field's *value* type, the
isbits pivot: `selection::ImmutableCell{Nothing}` is isbits and not selectable (a leaf value),
while the injected `Union{Nothing, Reference, SelectionDocument}` form is selectable. An explicit
`selection` must come **last** (anywhere else is an error) and defaults to
`nothing`, so it does not count as a programmer default and leaves Rule Y and the
keyword constructors gated exactly as the injected field would. `StyleText` is the
worked example:

```julia
@document ImmutableCell [DC] struct StyleText
    font::StyleFont
    color::StyleColor
    selection::Nothing
end
```

The `[DC]` here is the **layout list** — see the next section.

The *cell kind* in the fields determines the node's behavior: `ReactiveCell{T}`
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
  cell `JsonString`. The `C` says the variant keeps its fields in cells, which
  distinguishes it from `MJsonString`, the plain `mutable struct` layout: the first
  holds one `MutableCell` box per field, the second its fields inline.
- **Kind conversion** happens through the generic functions, not ctors:
  `copy_document(doc)` deep-copies and preserves each cell's kind, and
  `copy_document(K, doc)` rebuilds every cell as kind `K` (reactive ↔ mutable ↔
  immutable). To query, `get_cell_struct_kind(doc)` (the struct layer) reads the
  kind a value's fields are built from. A cell struct's kind lives in its field
  cells, not in its type name.

Loose bounds (`C <: AbstractCell`, not `C <: AbstractCell{String}`) exist because
`AbstractCell{T}` is invariant, and the projection machinery freely stores
untyped cells and even non-`String` values (template `bound(…)` markers) in a
"String" field before stripping them. Declared types are enforced by the
typed kind ctors, not by the type system.

### Why every field is a cell

The uniformity matters:

1. Any field can be wired into a reactive computation later by calling
   `set_cell_computation!(getfield(obj, :field), computation)` — without changing types.
2. Projections can read any field as if it were the source of truth and the
   reactive engine will invalidate the projection automatically.
3. One printer/reader body serves every kind, because access goes through the
   same `getproperty` for all of them.

### Escape hatch

When you genuinely need the raw cell (for example to share it between two
documents or pass it to `set_cell_computation!`), use `getfield(obj, :field)`. The
projection layer does this often, e.g. to make the `selection` field of a
`SyntaxLeaf` the same Cell as the upstream `JsonString.selection`.
Since the stem is immutable, such sharing must be established at
construction time. A field's cell object can never be swapped afterwards.

## `@domain`

```julia
@domain Json
```

One line generates a document domain's **insertion kit**. This is the abstract root
(`JsonDocument <: Document`, **exported** from the calling module; a domain
never re-exports its own root by hand, and an adopted `root = X` is exported
too), the empty placeholder
(`@document struct JsonNothing`), the typed-name insertion buffer
(`@document struct JsonInsertion` with `value::String = ""` plus the
`JsonInsertion("…")` convenience constructor), the **Insert-key gesture**
that turns the placeholder into the insertion (cursor in the buffer), and the
**insertion traits** the completion machinery dispatches on:
`get_domain_prefix`, `get_domain_insertion`, `get_insertion_root`, `get_nothing_document`,
`get_insertion_document`, the lowercase domain name as the insertion's alias, and
the placeholder's `insertable` opt-out.

Each `root = X` / `nothing = X` / `insertion = X` option **adopts** an
existing type instead of generating one (only its traits and gestures are
emitted); the adopted type must already be defined at the call site. For example,
`@domain Julia root = JuliaDocument nothing = JuliaNothing insertion =
JuliaInsertion`, because `JuliaNothing` doubles as the parsed `nothing`
literal.

What the completion machinery then gives the domain for free: the reflected
candidate list (`get_insertion_candidates(JsonDocument)`: every insertable
concrete subtype, either zero-arg constructible or with an `@insertion`
method), derived names (`JsonString` / `json string`, prefix-free inside the
domain), live completion + commitability colouring in the shared insertion
leaf, Enter-commit of unambiguous prefixes, Tab completion, and the
Insert ⇄ Escape loop between placeholder and insertion. Not generated
(layering): the two projection-table lines in the domain's `ToSyntax`
(`XInsertion => DomainInsertionToSyntaxLeaf(XDocument)` via the domain's
`XInsertionToSyntaxLeaf()` delegate, `XNothing => InsertionNothingToSyntaxLeaf()`).

## `@insertion`

```julia
@insertion JsonString    = @selected JsonString("") value{0}
@insertion JuliaFunction = make_julia_scaffold("function")
```

The document a committed insertion of that candidate becomes — `@domain`'s
companion. A candidate whose empty instance is already right needs no
`@insertion` at all: the zero-arg constructor is the fallback. The macro is for
the rest: a cursor to place (an empty string needs a caret *inside* it, not a
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
way to declare a projection struct: the `…ToSyntax*` / `…ToText` / the
`Widget…ToGraphicsCanvas` projections all use it, so the `<: Projection` is
defaulted in and is redundant to write on any of them.

A projection that genuinely needs a *different* supertype still writes it
explicitly (`@projection struct Foo <: SomethingElse`). And a plain
`struct MyProjection <: Projection ... end`, declared without the macro,
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
when none is given (see "Default base supertype"), so the resulting struct
satisfies the IoMap interface (every iomap has `projection`, `input`, `output`
fields).

## `@projection_template`

```julia
@projection_template ProjName InType (p, doc) -> <builder expression>
```

Writes `print_document(p::ProjName, recursion, doc::InType, ctx)` and the
matching reader from one builder expression, instead of a hand-written
`print_document`/`map_reference_forward`/`map_reference_backward`/`read_intent`
group. Eleven of the `*ToSyntax.jl` files and two `*DiagramToGraph.jl` files use
it. The other `*ToSyntax.jl` files are written by hand, and nine of the thirteen
files that use the template also hold hand-written printers. A new hand-written
pair needs a reason (see
[code-quality-rules.md](../../rule/code-quality-rules.md)).
[`@projection`](#projection) still declares the projection struct itself (a
config/style holder); `@projection_template` supplies the four projection
functions for it. The macro is defined in
[projection/ProjectionTemplate.jl](../../../source/kernel/projection/ProjectionTemplate.jl).

The builder expression is ordinary Julia that constructs the output document
(a `SyntaxLeaf`, `SyntaxNode`, …), marked at the positions that carry input
structure with one of five **marker words**:

| Marker | Marks |
|---|---|
| `bound(:field, Type, render; retype=nothing)` | This output position holds the value of `doc.field` (declared `Type`), drawn by `render`; a cursor there maps back to `doc.field`. `retype` names the `Operation` that replaces the whole value when a type-changing edit (e.g. a digit typed into a string) fires. |
| `project(:field; as=nothing)` | This child is `doc.field`, projected through its own type-dispatched projection (or, with `as`, a supplied projection instance or a `value -> projection` chooser). |
| `collection(:field)` / `collection(element, :field)` | `doc.field` is a repeated child collection; each element projects through the type dispatcher by default, or through `element` (a `do`-block) when given. |
| `tokens(thunk)` | A computed, inline sequence of leaves — `thunk` is a zero-argument function returning the leaf vector. |
| `sections(specs)` | Several fields grouped into their own labelled sub-collections; `specs` is a vector of `(field, make_wrapper)` pairs. |

A marker word resolves only as a call head (`bound(...)`), so a local variable
or field access of the same name is left alone — a builder does not need to
import any of the five names itself.

A minimal worked example, the null-and-bool leaves of the JSON domain
(`source/domain/json/JsonToSyntax.jl`):

```julia
@projection UntrackedCell struct JsonBoolToSyntaxLeaf
    style::StyleText = get_json_style(nothing, :bool_text)
end

@projection_template JsonBoolToSyntaxLeaf JsonBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool,
                     make_hinted_text(() -> doc.value ? "true" : "false";
                                      empty_thunk = () -> !(doc.value isa Bool),
                                      placeholder = "enter json bool",
                                      style = prj.style)))
```

`get_json_style(theme, name)`, which `@theme struct JsonTheme` writes, gives the
style of the field `name` of a `JsonTheme`: a cell that reads `bool_text` of a
theme, scaled or not, or the plain value of the default `JsonTheme` with
`nothing`. The projection holds its style and no theme, and the factory
`JsonToSyntax(; theme)` gives it `style = get_json_style(theme, :bool_text)`. A
projection never holds a font or a colour as a literal value; its builder reads
the theme, as [style.md](../platform/style/style.md#themes-and-the-appearance)
describes.

Printing a `JsonBool` through it needs no hand-written printer at all:

```julia
julia> iomap = print_document(JsonBoolToSyntaxLeaf(), JsonBool(true));

julia> typeof(iomap)
TemplateIoMap

julia> iomap.output
SyntaxLeaf(nothing, nothing, TextString("true", …), 0, false)
```

The `bound(:value, …)` marker is also what makes reference mapping and the
reader work with no further code: a `map_reference_forward`/`map_reference_backward`
pair and a `read_intent` method come from the template for every `bound`,
`project` and `collection` position in the builder.

**A child list that follows the document.** A node whose child list depends on
the value of a field writes the list as a thunk: `SyntaxConcatenation(() -> [...])`.
The constructor of the node makes the thunk the computation of its children cell.
The template finds that cell, a computed cell that holds a vector of markers, and
walks the markers again each time a cell that the thunk reads changes. The output
node gets its children in a cell of its own, so the children cell keeps its
computation. A slot therefore appears when an optional field gets a value, and
goes when the field becomes `nothing`. The range of the Julia domain
(`source/domain/julia/JuliaToSyntax.jl`) has a slot for its step only when the step is
not `nothing`:

```julia
@projection_template JuliaRangeToSyntaxNode JuliaRange (p, r) ->
    SyntaxConcatenation(() -> r.step === nothing ?
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)), project(:stop) ] :
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)),
                              project(:step),  SyntaxLeaf(TextString(":", p.op)), project(:stop) ])
```

A structural caret that has no input pre-image (a delimiter the builder always
renders, never bound to a field) is the one case the template cannot map on its
own. A domain overrides `read_intent`/`map_reference_forward` for that one
position, as `XmlElementToSyntaxNode` does for its `<`/`>`/`</` delimiters.
Everything else comes from the template: the printer, both reference-mapping
directions, and the reader.

## Default field values (`@kwdef`-style)

All three macros (and the underlying `@cell_struct`) accept `Base.@kwdef`-style
defaults on fields, so you no longer need an outer convenience constructor whose
only job is to fill in defaults:

```julia
@projection UntrackedCell struct ReferenceToHumanReadableText   # <: Projection is defaulted in
    document::Any
    font::StyleFont   = get_reference_style(nothing, :font)          # default
    style::NamedTuple = get_theme_defaults(ReferenceTheme)
end
```

When **at least one** field carries a default, the macro additionally emits a
**keyword** constructor:

```julia
ReferenceToHumanReadableText(; document)                 # font and style of the default theme
ReferenceToHumanReadableText(; document, font = StyleFont("Ubuntu", 20))
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

This is the standard idiom across the codebase: the insertion-cursor /
empty-document types (`JsonInsertion`, `XmlInsertion`, `SyntaxInsertion`,
`DocumentNothing`, …) and the `*To*` projection style-config structs
(`@projection struct …ToSyntaxLeaf`) declare their defaults inline rather than via a
convenience constructor. Copy that pattern, not the old `Foo() = Foo(Cell(nothing), …)`
form.

For `@document`, the keyword constructor is generated for the bare name, the
`IC`-prefixed and `MC`-prefixed spellings, and the native `MFoo` layout. It is
generated only when **the programmer** declares at least one field default; the
always-defaulted, macro-injected `selection` field does not itself count. A struct with no defaults of its own
(`JsonString` above) gets no `JsonString(; …)`, which leaves that signature free
for a hand-written keyword constructor that needs to do more than fill fields
(`Assistant` back-links its draft this way). A struct with no fields of
its own beyond the injected `selection` (e.g. `JsonNull`) is the exception: `Foo()`
has to come from somewhere, so it gets the generated keyword constructor too. Why
`Base.@kwdef` cannot simply be stacked on these macros (macro-ordering and the
dueling inner constructors), and why the defaults must be stripped out of the
struct body, is spelled out in [plan/done/macro-default-field-values.md](../../../plan/done/macro-default-field-values.md).

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
  name and then causes two separate failures: `ICFoo(…)` / `MCFoo(…)` **throw** on
  a value the annotation rejects (`ImmutableCell{Real}(nothing)` has no method), and
  `copy_document(ImmutableCell, doc)` does *not* throw. It falls back to the
  value's own type, so the copy quietly lands **off** the alias and
  `copy isa ICFoo` is `false`.
- The macro handles the Cell wrapping for the runtime struct.

The only time you would annotate `::Cell` directly is when the field really
*is* the cell itself (e.g. when sharing a cell between two structs, or when
the cell holds a computation rather than a value).

## Gotchas these macros impose

All three macros (`@document`, `@projection`, `@iomap`) share the same generated
machinery, and with it the same three gotchas:

- **A macro-wrapped field can never hold a `Cell` — or a `Computation` — as its
  logical value.** The auto-wrapping inner constructor runs `x isa Cell ? x : Cell(x)`
  on every argument, so a value that *is* a `Cell` is stored unwrapped and read back
  transparently. There is no way to have a field whose value is itself a `Cell`. A
  `Computation` is consumed the same way: it becomes the field's *derivation*, making it a
  computed cell, which is what `output = @computation …` is for. If you genuinely
  need to store either *as a value*, box it (e.g. in a one-element tuple or a wrapper
  struct), or keep it in a plain hand-rolled struct instead.

  A **`Function` is an ordinary value** and needs none of this: a field may hold a
  callback, predicate, or factory, and reading it returns the function uncalled. So a
  config field like `marker_eligible::Any = some_predicate` is fine. Computedness is
  stated with `Computation`, never inferred from the value's type.
- **The macro emits the *only inner* constructor.** Any convenience constructor
  you write must therefore be an **outer** constructor (`Foo(args...) = Foo(...)`
  outside the `@document struct` body); an inner one would collide with the
  generated auto-wrapping constructor. The one constructor the macro itself can
  add is the *outer* keyword constructor for `@kwdef`-style defaults (see
  "Default field values" above).
- **Equality is identity for every kind but the immutable one.** The stem is an
  immutable struct, so `===` compares it field cell by field cell. A
  `ReactiveCell` and a `MutableCell`, however, are *mutable* objects, which `===` compares
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
  in), across the `…ToSyntax*` / `…ToText` / `Widget…ToGraphicsCanvas` families. A
  plain `struct ... <: Projection` is the exception, used when the macro cannot
  be: `AlternativeProjection` stays plain because it holds a reactive
  `index::Cell`, reading the cell explicitly rather than through `@projection`.
  A `Function` field is not a reason to stay plain: `SyntaxCompoundToText`'s
  `marker_eligible` predicate is an ordinary value, so a plain struct that carries
  one can move to the macro.
  A plain struct gets no supertype defaulting, so it must write `<: Projection`.

The result is that domain and projection code reads like Julia you would write
without any framework. The reactivity is invisible until you reach for
`Cell`, `set_cell_computation!`, or `getfield` explicitly.
