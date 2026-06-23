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

- [x] `@projection` (package/kernel/src/common/Projection.jl)
- [x] `@document` (package/kernel/src/common/Document.jl) — incl. `IFoo` kw ctor
- [x] `@iomap` (package/kernel/src/common/IoMap.jl)
- [x] Verify by constructing throwaway types in Julia against `ProjecturedKernel`
      (defaults, keyword-only semantics, required keywords, default-referencing-
      earlier-field, snapshot/hydrate round-trip, and the no-default path *not*
      gaining a keyword ctor). Regression: `ProjecturedDomain` precompiles clean.
- [x] Update documentation/macros.md (new "Default field values" section + the
      gotcha now notes the generated outer keyword ctor)

## Outcome / decisions confirmed during implementation

- **Defaults are keyword-only** (matches `Base.@kwdef`): the positional
  auto-wrapping inner ctor is untouched and still requires every field. A
  fewer-than-all positional call does *not* pick up defaults — use the keyword
  form. (The verification initially assumed partial-positional defaults;
  corrected to keyword-only.)
- **Gated on "≥1 default declared"** so default-free usages are byte-for-byte
  unchanged (no surprise keyword ctor).
- `@document` emits the keyword ctor for **both** `Foo` and `IFoo`.
- The small addition was duplicated into each of the three macros, matching the
  existing triplicated machinery (no shared helper module — out of scope).

## Risks / notes

- The three macros duplicate their machinery today; this change follows that and
  duplicates the small addition in each rather than introducing a shared helper
  module (kept out of scope to avoid a structural refactor).
- No existing usage uses the `=` field form (it would currently be a syntax
  error), so there is nothing to migrate.
