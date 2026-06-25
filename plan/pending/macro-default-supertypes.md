# Default base supertypes for `@document` / `@projection` / `@iomap`

## Goal

Let the three Cell-wrapping struct macros supply the **framework base supertype
by default**, so authors stop repeating the obvious:

```julia
# before
@projection struct JsonStringToSyntaxLeaf <: Projection
    ...
end

# after — the `<: Projection` is the default, so drop it
@projection struct JsonStringToSyntaxLeaf
    ...
end
```

Rules:

- `@projection struct T …`  → `struct T <: Projection …` unless a supertype is given.
- `@document struct T …`    → `mutable struct T <: Document …` unless a supertype is given.
- `@iomap struct T …`       → `struct T <: IoMap …` unless a supertype is given.
- **An explicitly written supertype always wins.** `@document struct JsonString <: JsonDocument`
  keeps `JsonDocument`; `@projection struct Foo <: SomethingElse` keeps `SomethingElse`.

The motivation is pure noise reduction: `@projection` already *means* "this is a
projection", so repeating `<: Projection` on every one of ~135 call sites is
redundant. Same for the `<: Document` direct cases.

## Background — current state

- **`@iomap` already implements exactly this.** It is the reference implementation:

  ```julia
  # package/kernel/src/common/IoMap.jl
  name_expr = structdef.args[2]
  if name_expr isa Expr && name_expr.head === :(<:)
      struct_name = name_expr.args[1]
  else
      struct_name = name_expr
      structdef.args[2] = Expr(:(<:), name_expr, :IoMap)   # inject default
  end
  ```

  The injected `:IoMap` is a literal symbol inside the `esc`'d expression, so it
  resolves in the **calling** module's scope (not the macro's). This is the
  pattern to copy. (`@iomap` currently has no concrete call sites in the tree,
  but the mechanism is live and proven.)

- **`@projection` and `@document` do NOT inject a default.** Every call site
  spells the supertype out:
  - `@projection`: **all** ~135 sites write `<: Projection`. Verified that every
    module using `@projection struct` imports `Projection` (most via
    `import ..ProjectionApiModule: …, Projection`). So the symbol is already in
    scope everywhere — dropping `<: Projection` will compile.
  - `@document`: ~15 sites write `<: Document` *directly* (e.g. `Address`,
    `AppSettings`, `CellMatrix`, `CellTable`, `CellVector`, `GestureMap`,
    `LayoutConstraint`, `ListNode`, `Person`, `ProbeAlpha`, `ProbeBeta`,
    `ReferenceInspector`, `ScreenDocument`, `SearchSettings`, `TooltipSource`).
    The remaining ~190 write a **domain abstract supertype**
    (`<: JsonDocument`, `<: WidgetDocument`, `<: SyntaxDocument`, …) which is
    *not* redundant and must be preserved.

- **No `@document`/`@projection` site currently omits the supertype**, so adding
  the default is purely additive — it cannot change the meaning of any existing
  code. It only enables the shorter form.

- `@document` additionally generates an `I`-prefixed immutable snapshot struct
  that inherits the **same** supertype as the main struct (today: `IAddress <:
  Document`, `IJsonString <: JsonDocument`). The default must flow into both the
  main struct and the `I`-struct. For the 15 direct-`Document` cases this is
  behavior-preserving: `IAddress <: Document` whether `<: Document` is written or
  defaulted.

- `@projection_template` (ProjectionTemplate.jl) emits only a `projection_print`
  method, never a struct — unaffected. Projection structs are still declared with
  `@projection struct …`.

## Design

### 1. `@projection` macro — `package/kernel/src/common/Projection.jl`

The projection macro has no `I`-struct, so the change is local to the name
handling at the top. Replace:

```julia
name_expr = structdef.args[2]
struct_name = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[1] : name_expr
body = structdef.args[3]
```

with the `@iomap`-style branch:

```julia
name_expr = structdef.args[2]
if name_expr isa Expr && name_expr.head === :(<:)
    struct_name = name_expr.args[1]
else
    struct_name = name_expr
    structdef.args[2] = Expr(:(<:), name_expr, :Projection)
end
body = structdef.args[3]
```

Nothing else in the projection macro references `name_expr` again.

### 2. `@document` macro — `package/kernel/src/common/Document.jl`

Normalize the name expression to always carry a supertype *up front*, so the
later `I`-struct logic picks it up automatically. Replace:

```julia
name_expr = structdef.args[2]
struct_name = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[1] : name_expr
body = structdef.args[3]
```

with:

```julia
name_expr = structdef.args[2]
if !(name_expr isa Expr && name_expr.head === :(<:))
    name_expr = Expr(:(<:), name_expr, :Document)
    structdef.args[2] = name_expr
end
struct_name = name_expr.args[1]
body = structdef.args[3]
```

Then simplify the now-unconditional `I`-struct supertype lines from:

```julia
i_supertype = name_expr isa Expr && name_expr.head === :(<:) ? name_expr.args[2] : nothing
i_name_expr = i_supertype !== nothing ? Expr(:(<:), i_name, i_supertype) : i_name
```

to:

```julia
i_supertype = name_expr.args[2]   # always present after normalization
i_name_expr = Expr(:(<:), i_name, i_supertype)
```

`structdef.args[1] = true` (mutable) and the rest of the macro are unchanged.

### 3. `@iomap` macro — no change

Already defaults to `<: IoMap`. Leave as is; it is the precedent the other two
are being aligned to.

### Scope note for `@document` migration

Only the **direct `<: Document`** sites are redundant. Domain-abstract
supertypes (`<: JsonDocument`, etc.) carry real dispatch meaning and **must
stay**. Do not blanket-strip every `<: …` from `@document` structs.

## Implementation order

Work in a dedicated git worktree. Commit per step.

1. **Enable** — apply the three macro edits above (only #1 and #2 change code).
   `@iomap` untouched. This alone changes no behavior of existing code.
   - Verify: `test_cell()` plus one targeted domain that exercises both macros,
     e.g. `test_json()` (JSON documents + JSON→Syntax projections), still green.

2. **Migrate `@projection` call sites** — drop the trailing `<: Projection` from
   every `@projection struct … <: Projection`. Purely mechanical
   (`<: Projection` → ``), ~135 sites across `package/domain/src/projection/`.
   Delegate to a **Sonnet subagent** (broad repetitive edit). Constraints for the
   subagent:
   - Only strip `<: Projection` (the exact base type), never a different
     supertype.
   - Leave the `import … Projection` lines in place — `Projection` is still
     referenced by signatures like `map_reference_forward(p::Projection, …)`.
   - Group commits by domain folder (json, julia, sql, widget, math, …) so each
     commit is reviewable and individually testable.
   - After each domain folder: run that domain's targeted test (`test_json()`,
     `test_sql()`, `test_syntax()`, the widget/graphics pipeline test, …).

3. **Migrate the ~15 direct `@document … <: Document` sites** — drop `<: Document`
   from exactly those types listed in Background. Leave every domain-abstract
   supertype alone. Smaller, can be done on Opus or delegated with an explicit
   allow-list of the 15 type names.
   - Verify each affected type still snapshots: the `I`-struct must remain a
     `Document` subtype (e.g. `IAddress <: Document`). A quick REPL check
     `IAddress <: Document` should be `true`.

4. **Docs** — update `documentation/macros.md`:
   - State that `@document`/`@projection`/`@iomap` now default to
     `Document`/`Projection`/`IoMap` when no supertype is given, and that an
     explicit supertype (including a domain abstract type) overrides the default.
   - Update the illustrative snippets to use the bare form where appropriate.
   - Update the "How this pattern threads through the codebase" notes.

5. **Sweep** — `test_all()` once at the end as a broad regression check (per
   CLAUDE.md, only after the targeted tests pass). Compare against the known
   green baseline (~13 known-incomplete failures, not regressions).

6. Move this plan to `plan/done/`.

## Risks / edge cases

- **Symbol scope.** The injected `:Projection` / `:Document` resolves at the call
  site (the expression is `esc`'d). Confirmed every `@projection` module imports
  `Projection`; every direct-`Document` `@document` module imports `Document`.
  Modules that keep an explicit supertype need nothing new.
- **Parametric structs.** None exist today (`@document struct Foo{T} <: Bar`
  appears nowhere). The normalization assumes a plain name in the no-supertype
  branch — same assumption the current macros already make. If a parametric
  no-supertype struct is ever added, `Expr(:(<:), Foo{T}, :Document)` is still
  the correct rewrite, but field-name handling would need its own review (out of
  scope here).
- **`I`-struct subtype change is a no-op** for the 15 direct cases (already
  `<: Document` transitively). No code dispatches on a non-`Document` `I`-struct
  because none exist.
- **Backward compatibility.** Steps 2–3 (call-site migration) are cosmetic; the
  enabling change in step 1 keeps every current spelling working, so the
  migration can be partial/incremental without breakage.

## Optional follow-up (not in scope)

The three macros now share almost all of their body (field walking, Cell
wrapping, auto-wrapping ctor, getproperty/setproperty!, kwdef defaults, and the
default-supertype injection). A later refactor could factor the common machinery
into one helper that the three thin macros call with their base type
(`:Document` / `:Projection` / `:IoMap`) and an `emit_istruct::Bool` flag. Left
out here to keep this change reviewable and low-risk.
