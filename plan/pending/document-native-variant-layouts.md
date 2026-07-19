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

1. **Family abstract + variant naming.** ✅ **Done (additive form).** Emitted
   `abstract type AbstractFoo <: Super` with the stem and native both subtyping it —
   *without* the disruptive bare-`Foo`-rename; existing dispatch and aliases unchanged.
2. **Mutable layout.** ✅ **Done as native `FooMut`** — a plain `mutable struct` with
   raw value fields (no `MutableCell` box; default `getfield`/`setfield!`), same Rule-Y
   ctors. *Not yet:* flip the `MFoo` alias to native + retire the box (optional tail).
3. **Immutable layout.** ✅ Unchanged — the isbits `IFoo` + reactive `RFoo` stem
   already coexist; `FooMut` now sits beside them under the family abstract.
4. **Schema identity across layouts.** ◐ **Partial.** `is_same_document_type` /
   `sync_document!` are family-aware and cross-kind sync (native → reactive shadow) is
   proven with minimal invalidation. *Not yet:* `copy_document`/`walk` family-threading
   — deferred **with** native-nesting (see Implementation status; can't be triggered
   until a native document nests native children).
5. **Per-field kind override** — type-level declaration and per-instance.
6. **Inheritance.** Dispatch inheritance from Phase 1; *optional* field-splicing so
   `Derived` carries `Base`'s fields across all variants (Julia has no struct field
   inheritance) — decide if we want field inheritance or dispatch-only (today's domain
   hierarchy is dispatch-only).
7. **Migrate the whole document surface** to the new codegen; keep behavior — diff the
   full suite against a clean baseline (the L1 change alone spanned 106k+ assertions;
   this touches every `@document`).

## Implementation status (what is actually built)

The macro rewrite was done **additively**, not as the disruptive Phase-1 rename. The
existing stem `Foo` and its `RFoo`/`IFoo`/`MFoo`/`DFoo` aliases are **untouched**;
the two-layout support is emitted *alongside* them, so the whole document surface
keeps working with no migration:

- **Family abstract** `AbstractFoo` is inserted between the stem and its supertype:
  `struct Foo{…} <: AbstractFoo`, `abstract type AbstractFoo <: Super`. Transitive, so
  every existing `<: Super` dispatch is unchanged.
- **Native mutable layout** `mutable struct FooMut <: AbstractFoo` holds the declared
  **value** types directly (no `MutableCell` box) — an all-mutable document is
  byte-for-byte a plain `mutable struct`. Emitted by `_emit_native_mutable` in
  `DocumentMacro.jl`; gets the same Rule-Y positional + keyword constructors (storing
  raw values). *(Bare `Foo` stays the stem; `MFoo` stays the boxed alias. The native
  variant is the new `FooMut`. Flipping `MFoo` → native and retiring the box is the
  optional Phase-2 tail.)*
- **Schema identity across layouts** via `document_family` (`DocumentInterface.jl`
  declares it, `DocumentDefaults.jl` defines the fallback = name-wrapper, the macro
  emits `document_family(::Type{<:AbstractFoo}) = AbstractFoo`). `is_same_document_type`
  and hence `sync_document!` now compare families, so a reactive `Foo`, an immutable
  `IFoo`, and a native `FooMut` all count as **the same document**.
- **Regression guard:** native `FooMut` structs subtype the family, so document-type
  reflection (`insertion_candidates` in base `Domain.jl`) would pick them up as a second
  concrete type per schema. `_is_layout_variant` filters them out structurally (a
  concrete type whose `document_family` isn't its own name-wrapper). Domain suite stayed
  **byte-identical at baseline** (106125/0/0/5) — strong evidence the change is
  behaviour-preserving across every domain `@document`.

**Capability proven** (`plan/pending/document-native-variants-capability.jl`, 22/23):
native `FooMut` constructs + mutates as a plain mutable struct; `sync_document!(RFoo,
FooMut)` copies values into the reactive shadow; and it does so with **minimal
invalidation** — a changed field invalidates only its own reactive watcher, an
unchanged field's watcher stays valid → the L1 lazy engine repaints only what changed.

**FES speed answered — native `@document` costs nothing on the hot path**
(`plan/pending/document-native-variants-fes-speed.jl`). A 2 M-iteration sim inner loop (advance time, bump
a per-module counter, push!/pop! the event set) on the native variant vs a hand-written
plain `mutable struct` with identical fields:

| | native `SimStateMut` | plain `mutable struct` | ratio |
|---|---|---|---|
| allocated | 178 049 920 B | 178 038 560 B | **1.00** |
| time | 0.0298 s | 0.0319 s | **0.93** |

Byte-identical allocation (no per-access boxing) and indistinguishable time — native
field access lowers to `getfield`/`setfield!`. So the omnetpp sim can be **one**
`@document` schema mutating the native variant at full speed; there is no perf reason
to keep a separate hand-written simulator struct.

**One characterized limitation — native cannot nest native.** A document-typed field
in `FooMut` is typed to the *stem* (`child::Union{Bar,Nothing}`), and `BarMut <:
AbstractBar` is **not** `<: Bar`, so a native parent can hold a **reactive/stem** child
but not a native `BarMut` child. Consequences:

- **Not needed for omnetpp.** `SequentialSimulator`'s fields are plain Julia values
  (`SimTime`, `BinaryMinHeap{SequentialEvent}`, `Vector{UInt128}`, scalars, `Function`)
  — **no nested documents** — so its native variant nests nothing and the limit never
  bites. This is why Phase-4's `copy_document` threading is **not** implemented yet.
- **`copy_document` family-threading defers with it.** Sync only calls `copy_document(K,
  child)` when a `child isa Document` slot changed type — which requires a *native
  document nested in a native document*, i.e. exactly the case the layout forbids. So
  `copy_document(ReactiveCell, FooMut)` rebuilding a native `FooMut` instead of a
  reactive `RFoo` is a latent bug that **cannot be triggered** until native-nesting
  exists. The two are one coherent future unit: **type document-typed native fields as
  the family abstract** (needs macro-time detection of which field types are documents,
  the same problem `is_collection_field_type` solves via an opt-in trait) **and** make
  `copy_document`/`walk` family-aware so a cross-layout rebuild produces the target
  kind.

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
