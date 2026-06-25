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

## Implementation order — DONE

Implemented in worktree `macro-default-supertypes` (branch
`worktree-macro-default-supertypes`). Commits per step.

1. ✅ **Enable** — applied the `@projection` and `@document` macro edits (#1, #2).
   `@iomap` untouched. Commit `ab34765`.
   - Verified: `test_cell()` 25/25, `test_json()` 24/24 green.

2. ✅ **Migrate `@projection` call sites** — stripped `<: Projection` from
   **137** sites (turned out to all live in one folder,
   `package/domain/src/projection/primitive/`, 16 files — so one reviewable
   commit rather than per-folder). Done with a single `sed`; `import … Projection`
   lines left intact. Commit `d5e16ce`.
   - Verified: `test_json`, `test_syntax`, `test_json_to_syntax` green;
     `test_projections` 1439 pass with only the known pre-existing baselines
     failing — proving the migrated projections still dispatch as `<: Projection`.

3. ✅ **Migrate the direct `@document … <: Document` sites** — **17** sites (the
   plan estimated ~15) across domain/example/kernel/test. Domain-abstract
   supertypes (194 of them, `<: JsonDocument` etc.) left untouched. Commit
   `86de2d4`.
   - Verified: all four packages precompile; `test_collection`,
     `test_gesture_binding`, `test_gesture_map`, `test_object_to_widget`,
     `test_tooltip`, `test_reference_inspector_text`,
     `test_layout_constraint_helpers` all green (exercises the `I`-struct
     snapshot path too).

4. ✅ **Docs** — updated `documentation/macros.md`: added a "Default base
   supertype" section, moved the `@projection`/kwdef examples to the bare form,
   noted `@iomap` was the first to do this, and corrected the stale "projection
   structs are usually plain `struct <: Projection`" claim. Commit `46ee756`.

5. ✅ **Sweep** — `test_all()` run on the change AND on the base commit
   `82a332a` in an identical environment (same copied native `.so`). The
   per-failure fingerprint (by test `file:line`) is **byte-identical**:
   **165 fail / 3 error on both**, zero delta. So the change introduces **zero
   regressions**. (The "~13" figure in the old `test-suite-green` memory is stale
   — the suite has since grown to ~230k tests; the 165 failures are all
   pre-existing known-incomplete features: `TypeinTest:269` ×111 "KeyPress→no
   edit", `MouseClickTest:218` ×31, conversation REPL ×5, SplitPaneDrag ×8,
   SqlToSyntax/JSON-array-insert/TableNavigation ×1 each, plus the worktree's
   environmental `DirtyRectTest` SDL `UndefVarError`.)

6. ✅ Moved this plan to `plan/done/`.

### Why this is provably safe

For every migrated site the supertype was already written explicitly as the
base type, so the macro now *injects the same symbol it used to read* — the
generated struct/`I`-struct is byte-identical to before. The byte-identical
`test_all` fingerprint is the empirical confirmation.

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
