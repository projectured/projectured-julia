# `@kwdef`-style default field values for `@document` / `@projection` / `@iomap`

## Goal

Let the three Cell-wrapping struct macros accept default field values inline so
authors stop writing outer convenience constructors that exist only to fill in
defaults:

```julia
@projection struct Foo <: Projection
    measure::Function
    corner_radius::Int = 4
    shadow_offset::Int = 0
end

Foo(measure)                       # corner_radius=4, shadow_offset=0
Foo(measure; corner_radius = 8)    # override one default
```

Scope of this change: the macros only. **Do not change any usages yet** — this
just makes the syntax available.

## Background — why `Base.@kwdef` can't simply be stacked

- `@projection`/`@document`/`@iomap` rewrite every declared field to `::Cell` and
  emit the *only inner* constructor (an auto-wrapping `new(...)`). `Base.@kwdef`
  emits a keyword constructor that forwards to the *positional* constructor, so
  the two want to own different pieces and don't compose.
- Macro ordering also blocks it: `@projection` requires `structdef.head === :struct`
  (a `@kwdef`-wrapped form is a `:macrocall`), and `@kwdef` requires a `:struct`
  (a `@projection`-wrapped form is a `:macrocall`). Neither nesting works.
- A plain `struct` rejects `x::T = v` at lowering ("inside type definition is
  reserved"), but the form *parses* into `Expr(:(=), :(x::T), v)`, so a macro can
  intercept it, strip the default out of the struct body, and re-emit it as a
  keyword constructor.

## Design

Each macro already (a) walks the field list rewriting types to `::Cell` and
collecting field names, and (b) emits a positional auto-wrapping inner ctor. Add:

1. **Recognise the default form** `name = v` / `name::T = v`
   (`Expr(:(=), lhs, default)`) in the field-walk loop:
   - treat the field as a normal Cell field (`name::Cell` in the body, default
     stripped so the struct definition stays legal);
   - record `name => default` in a `defaults` list, preserving the original
     declared type where present (needed by `@document`'s I-struct).
2. **Emit a keyword outer constructor** — only when at least one default exists,
   to avoid adding a keyword ctor to every existing usage:
   ```julia
   Foo(; required_field, defaulted_field = v, ...) = Foo(required_field, defaulted_field, ...)
   ```
   Fields without a default become *required* keywords (mirrors `Base.@kwdef`:
   `UndefKeywordError` if omitted). The keyword ctor is an **outer** ctor that
   forwards into the existing positional inner ctor, so Cell auto-wrapping is
   unchanged and there is no collision with the inner ctor.
   - Later defaults may reference earlier fields by name (Julia keyword defaults
     see earlier keyword args), matching `@kwdef` semantics.
   - For `@document`, also emit the parallel keyword ctor for the immutable
     `IFoo` struct (raw types, no Cell) for symmetry.

### Why "only when a default is present"

The user asked not to change usages. Emitting an unconditional all-keyword ctor
would add `Foo(; a, b, c)` to every existing `@document`/`@projection`/`@iomap`
type. Gating on "≥1 default declared" keeps every current type byte-for-byte the
same and makes the feature strictly opt-in.

## Steps

- [ ] `@projection` (package/kernel/src/common/Projection.jl)
- [ ] `@document` (package/kernel/src/common/Document.jl) — incl. `IFoo` kw ctor
- [ ] `@iomap` (package/kernel/src/common/IoMap.jl)
- [ ] Verify by macro-expanding + constructing a throwaway type in Julia
- [ ] Update documentation/macros.md (note defaults + that the kw ctor is the
      one exception to "convenience ctors must be outer / hand-written")

## Risks / notes

- The three macros duplicate their machinery today; this change follows that and
  duplicates the small addition in each rather than introducing a shared helper
  module (kept out of scope to avoid a structural refactor).
- No existing usage uses the `=` field form (it would currently be a syntax
  error), so there is nothing to migrate.
