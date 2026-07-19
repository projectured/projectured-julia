# Full `@document` variant family with native per-kind layouts

Make every `@document Foo` generate a complete family of variants, each compiled to
its **optimal native representation**, so one schema serves the whole pipeline with
no duplication: the simulator mutates the **mutable** variant at plain-`mutable
struct` speed, the editor holds the **reactive** variant, and `sync_document!`
copies mutable → reactive, where the lazy/incremental reactive engine (L1) takes
over and repaints only what changed.

## The variants (goal)

For `@document struct Foo …`:

| variant | representation | speed | use |
|---------|----------------|-------|-----|
| **`IFoo`** (immutable) | immutable `struct`, inline value fields | isbits, inlines into parent/array | value docs, hot immutable data (e.g. FES events) |
| **`MFoo`** (mutable) | **`mutable struct`, inline raw fields** | **exactly plain-`mutable struct`** | the simulator's live model state |
| **`RFoo`** (reactive) | `ReactiveCell{T}` fields | field-granular reactivity, lazy (L1) | the editor's document |
| **`DFoo`** (default) | per-field kind mix as declared | per field | the default variant |

Plus: **`Foo`** = the family (abstract type) + a constructor that builds `DFoo`;
**per-field kind override** on the type and per instance; **inheritance + dispatch**
(`@document Derived <: Base` ⇒ `f(x::Base)` matches all Base variants incl. Derived,
`f(x::Derived)` matches Derived's).

## Why two layouts (a hard Julia fact — verified)

`isbitstype` requires an immutable `struct`; inline-*mutable* fields require a
`mutable struct`; **no single type is both** — even an all-`const` mutable struct is
`isbitstype=false` and heap/pointer-stored (checked: `Vector{allconst}` holds 8-B
pointers; `Vector{immutable}` inlines). So `IFoo` (isbits) and `MFoo` (inline-mutable)
*must* be different struct types. The macro therefore emits **two layouts** and
routes by field kinds:

- **immutable layout** `struct Foo_i{…}` — `IFoo` (isbits) and `RFoo` (cells) and
  immutable+reactive mixes.
- **mutable layout** `mutable struct Foo_m{…}` — `MFoo` and any mutable-bearing mix.
  Field storage per kind: `f::T` (mutable, inline), `const f::T` (immutable-in-mutable,
  inline), `f::ReactiveCell{T}` (reactive, boxed). Per-field accessors resolve at
  **compile time** (direct `getfield`/`setfield!` for raw fields; `[]`-unwrap only for
  cell fields).

Routing: **any mutable field ⇒ mutable layout; all-immutable ⇒ immutable layout
(isbits); reactive fields work in either (always boxed).** `MutableCell{T}` becomes
redundant for documents — a mutable field is just a raw field in the mutable layout —
and is retired there.

## Validated target expansion (proven by hand before touching the macro)

`@document struct Point; x::Int; y::Int; end` must generate (verified 13/13,
`plan/pending/document-native-variants-reference.jl`):

```julia
abstract type Point <: Document end                          # bare name = the family

struct PointC{X<:AbstractCell,Y<:AbstractCell,S<:AbstractCell} <: Point   # cells layout
    x::X; y::Y; selection::S
end
Base.getproperty(o::PointC, n)     = getfield(o, n)[]        # unwrap
Base.setproperty!(o::PointC, n, v) = (getfield(o, n)[] = v)
const RPoint = PointC{Cell,Cell,Cell}                                          # reactive
const IPoint = PointC{ImmutableCell{Int},ImmutableCell{Int},ImmutableCell{Nothing}}  # isbits value-doc

mutable struct PointM <: Point                               # mutable layout — NATIVE, no cells
    x::Int; y::Int; selection::Union{Nothing,Reference}
end
const MPoint = PointM                    # no getproperty override → direct getfield/setfield!

document_family(::Type{<:Point}) = Point # identity across layouts (replaces the `.wrapper` test)
```

Measured/checked:
- **`MPoint` is byte-for-byte a plain `mutable struct`** — identical `@allocated` *and* identical
  compiler elision (both drop to 0 allocs in a non-escaping loop; a boxed `MutableCell` `MFoo` cannot).
  `!isbitstype(PointM)` (reference type, as expected).
- **`IPoint` is isbits** (16 B: `x`+`y` inline, `selection` a zero-size `ImmutableCell{Nothing}`) → inlines.
- **`x isa Point`** matches all three variants; **`x isa PointM`** still targets exactly one.
- **`document_family`** makes reactive/mutable/immutable one document → `sync` bridges layouts.
- **`sync` copies a mutated `MPoint` into a live `RPoint`** (reactive cells update; `RPoint` stays reactive).

So the codegen target is settled; the remaining work is generating this from the macro and threading
`document_family` through `is_same_document_type`/`sync_document!`/`copy_document`/`walk`.

## Naming & inheritance (abstract family types)

- Bare **`Foo`** flips from today's concrete parametrized stem to an **abstract family
  type**: `abstract type Foo <: Super`. All variants (`IFoo`/`MFoo`/`RFoo`/`DFoo` and
  any parametrization) subtype it. `Foo(args…)` builds `DFoo`.
- `@document Derived <: Base` emits `abstract type Derived <: Base`; `Derived`'s
  variants `<: Derived <: Base`. So `f(x::Base)` matches *all* Base variants (and
  Derived's, correct subtyping); `f(x::Derived)` matches Derived's variants;
  `h(x::MBase)` matches just the mutable Base variant. (The two-layout design *needs*
  this abstract anyway — `Foo_i`/`Foo_m` are distinct structs, no shared UnionAll.)
- Cross-cutting "all *mutable* variants regardless of type" is the *kind* axis — a
  **trait** (`kindof(::MFoo)=Mutable()`), not a supertype (Julia single inheritance).

## The omnetpp payoff (why we're doing this)

One `@document` schema, no duplication, full sim speed:

- sim builds/mutates **`MFoo`** model state — plain-`mutable struct` speed (by
  construction; **no measurement gate**);
- hot immutable kernel data (FES events) is **`IFoo`** — isbits, stored inline, ~as
  fast as today's plain events (this is what dissolves the earlier boxed-`MFoo` 4.5×
  FES result);
- editor holds **`RFoo`**;
- `sync_document!(RFoo_ui, MFoo_sim)` copies changed fields into the reactive tree;
  only changed reactive cells are written → L1 lazy/incremental engine → partial GUI
  invalidation.

Design-X realized at native speed — see `../../omnetpp-julia` →
`plan/pending/simulator-as-reactive-document.md` (revisit its "FES stays plain /
window it" note once native layouts exist: the FES *can* now be `IFoo`).

## Phases

1. **Family abstract + variant naming.** Bare `Foo` → `abstract type Foo <: Super`;
   emit `IFoo`/`MFoo`/`RFoo`/`DFoo <: Foo`; `Foo(args…)` builds `DFoo`. Migrate all
   dispatch that currently uses the concrete stem `Foo{…}`.
2. **Mutable layout.** Emit `mutable struct Foo_m{…}` with raw/`const`/cell fields +
   compile-time per-field accessors. `MFoo` = all-raw = plain mutable struct. Sanity
   check (not a perf gate): `MFoo` allocates like a hand-written `mutable struct` and
   its accessors lower to `getfield`/`setfield!`. Retire `MutableCell` for documents.
3. **Immutable layout.** Keep today's isbits `IFoo` + reactive `RFoo`; make them
   coexist with the mutable layout under the family abstract.
4. **Schema identity across layouts.** `sync_document!`/`copy_document`/`walk`/
   `is_same_document_type` recognize all variants of a family as one document (via the
   family abstract / a schema tag, not the type wrapper). Implement cross-kind
   `sync_document!` (mutable/immutable source → reactive shadow, and any → any writable).
5. **Per-field kind override** — type-level declaration and per-instance.
6. **Inheritance.** Dispatch inheritance from Phase 1; *optional* field-splicing so
   `Derived` carries `Base`'s fields across all variants (Julia has no struct field
   inheritance) — decide if we want field inheritance or dispatch-only (today's domain
   hierarchy is dispatch-only).
7. **Migrate the whole document surface** to the new codegen; keep behavior — diff the
   full suite against a clean baseline (the L1 change alone spanned 106k+ assertions;
   this touches every `@document`).

## Constraints / risks

- **Large macro rewrite** — `document/DocumentMacro.jl`, `cell/CellStruct.jl`,
  `cell/CellStructPlan.jl`, `cell/MutableCell.jl` (all 🔒 sealed; owner authorized
  unsealing; **re-audit each vs `documentation/architecture-requirements.md`**).
- **Migration surface** — every `@document` in the codebase (all domains, the whole
  editor) must keep working; behavior-preserving is the bar, verified by a full-suite
  diff, not targeted tests.
- **Depends on L1** (lazy reactive cells — `cheap-reactive-cells.md`, branch
  `lazy-reactive-cells`): `RFoo` relies on it to be cheap.
- **Supersedes L4** (object-granular reactivity) in `cheap-reactive-cells.md`:
  field-granular reactivity stays in `RFoo` (cheap via L1) and fast mutation comes
  from `MFoo`'s native layout, so object-granular is not needed.
- **No perf gate** — `MFoo` is a plain `mutable struct` by construction; a codegen /
  allocation sanity check suffices.

## Cross-refs

- Depends: `cheap-reactive-cells.md` (L1).
- Enables: `../../omnetpp-julia` `plan/pending/simulator-as-reactive-document.md`.
