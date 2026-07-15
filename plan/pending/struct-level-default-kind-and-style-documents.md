# Struct-level default cell kind + promoting the style structs to `@document`

Builds on `document-field-cell-kind` (per-field cell kind already landed). Two parts:

## Part A — struct-level default cell kind

A leading kind argument on the macro sets the default for every *unannotated* field;
per-field annotations still override. Avoids repeating `ImmutableCell{}` on every field.

```julia
@document ImmutableCell struct StyleColor
    red::Float64          # → ImmutableCell{Float64} (struct default)
    green::Float64
    blue::Float64
    alpha::Float64
end
# bare StyleColor(r,g,b,a) == IStyleColor (all immutable, incl. the injected selection)
```

Works for all four macros (`@cell_struct` / `@projection` / `@iomap` / `@document`).
**`selection` follows the default** (user's choice): under an immutable default, bare builds a
fully-frozen node — no reactive selection cell, no fanout on static config nodes. Navigable/editable
instances use `RFoo`. Backward-compatible: no leading kind ⇒ `:reactive` ⇒ byte-identical to today.

### Implementation (small — the per-field machinery already does the work)
- `_field_kind_type(ftype)` → also report `explicit::Bool` (was the kind annotated, or inferred).
- `field_cell_kinds(plan; default = :reactive)` → non-explicit fields get `default`.
- Export `cell_kind_of(sym)` (`:ImmutableCell`→`:immutable`, …) for the macros.
- `cell_struct_exprs(structdef; default)` + `@cell_struct`/`@projection`/`@iomap` parse a leading kind.
- `@document` parses a leading kind; thread `default` into `_emit_autowrap_ctor` (aliases unchanged —
  they already force one kind). The injected `selection` field is non-explicit → gets the default.
- Verify: no-leading-kind is a no-op (test_kernel unchanged); `@… ImmutableCell struct` makes bare == IFoo.

## Part B — promote StyleFont / StyleText / StyleColor to `@document ImmutableCell`

Make them navigable/editable documents whose *value* fields default to `ImmutableCell` (cheap, no
fanout for the static-config majority). Editing an *active* instance uses the reactive kind
(`RStyleColor`, `color.red = v`). This touches **foundational value types**, so do it incrementally
and measure. `StyleColor` is the risk (used in numeric hot paths: interpolate/lighten/gradient/animation).

### Order & risk
- **Benchmark first** (baseline): construct / `color_interpolate` / `color_lighten` throughput.
- **B1 StyleFont** (~34 uses, light math) — derisk the pattern.
- **B2 StyleText** (font+color wrapper).
- **B3 StyleColor** (~211 uses, HOT) — re-run the benchmark; if it regresses materially, STOP and
  report (the alternative is design (b): keep `StyleColor` a plain value + a separate editable
  `ColorDocument` projection).

### Fallout to handle per type (audit each)
- Construction `StyleColor(r,g,b,a)` now builds a `@document` (immutable stem + inlined cells + selection).
- `.red`/`.green`/… reads: getproperty through the `ImmutableCell` → the `Float64` (works).
- Arithmetic/eq: `color_interpolate`, `color_lighten`, `color_darken`, `color_equal` — read fields via
  getproperty (fine) but watch equality/hashing semantics (stem `==` vs the custom `color_equal`).
- `_value_kind` (ObjectToWidget) treats `StyleColor`/fonts as `:opaque`; as a `@document` they gain
  cell fields → would become `:struct` (recursed). Decide: keep opaque (explicit) or allow the sub-grid.
- `::StyleColor` type annotations become the UnionAll (matches any kind) — dispatch still works.

## Verification
Precompile + `test_visual` + `test_domain` after each phase, against the branch baseline. A macro
change is validated by a real load (memory: "guards are not a load check"). Cap memory with systemd-run.

## Results

### Part A — DONE (commit `abc8080f`)
Struct-level default kind works across all four macros; `selection` follows the default; per-field
overrides win; backward-compatible (`test_kernel` 431/0/0). Smoke test green.

### Part B — MEASURED, DO NOT PROCEED (recommend design (b))
Micro-benchmark (`bench/colorbench.jl`) of a plain value struct vs the `@document ImmutableCell` form:

| | plain `StyleColor` (today) | `@document StyleColor` |
|---|---|---|
| the value | **isbits, 32 B, inlined** | **not isbits, 40 B, heap object** |
| config cell `ImmutableCell{StyleColor}` | **isbits, inlined (Phase 2/3 win)** | **boxed pointer** |

Root cause: `@document` injects a mandatory **`selection` field** (`ImmutableCell{Reference}`, and
`Reference = Union{Nothing,ReferencePath}` is not isbits), so **every** `StyleColor` becomes a heap
object; and because the promoted type is a **UnionAll**, `ImmutableCell{StyleColor}` boxes it —
**undoing the Phase 2/3 inlining** on the render-hot path. `@cell_struct ImmutableCell` would avoid
the selection field (could stay isbits) but then gives no navigability/selection and no reactive
kind — so it can't be *edited* either.

**Conclusion:** no promotion of the value type preserves both inlining AND editability. Editing is
better served by **design (b)** — keep `StyleColor`/`StyleFont`/`StyleText` as cheap plain values
(inlined everywhere, millions of them) and add a separate editable **`ColorDocument` `@document`**
(a handful under active edit) that projects to/from a `StyleColor`. That keeps the render path cheap
and still gives `doc.red = v` live per-component editing.

Part A shipped (independently useful). Part B (naive promotion, `IC{Reference}` selection) is
net-negative. **BUT the selection-parameter design (Part C) recovers it** — see below.

### Part C — selection-parameterized promotion (VIABLE) — bench + audit done
The selection field is already the 5th type parameter (`StyleColor{C1..C4,Csel}`). Its **value type**
is the isbits pivot: `ImmutableCell{Nothing}` is isbits (non-selectable), `Cell{Reference}` holds a
path (selectable). So ONE `@document StyleColor` covers both, and the non-selectable form keeps the
Phase 2/3 inlining. Declaration (explicit selection field):

```julia
@document ImmutableCell struct StyleColor
    red::Float64; green::Float64; blue::Float64; alpha::Float64
    selection::ImmutableCell{Nothing}     # non-selectable ⇒ isbits
end
```

**Bench (`bench/colorbench.jl`), four-way:**

| colour form | value | `ImmutableCell{it}` config cell |
|---|---|---|
| plain struct (today) | isbits, 32 B | isbits |
| `@document` default (`IC{Reference}` sel) | heap | boxed |
| **`@document` non-selectable (`IC{Nothing}` sel)** | **isbits, 32 B** | **isbits (inlines)** |
| `@document` reactive selectable (`Cell` sel) | heap | — · editable `rsel.red=0.9`, holds `rsel.selection=:a_path` |

So bare `StyleColor(...)`/`IStyleColor` == isbits/inline/non-selectable (Phase 2/3 win intact);
`RStyleColor` (`Cell{Any}` selection) == reactive + selectable + editable in place. Same type.

**Audit (`Selection.jl`):** every selection WRITE (`set_selection!`/`clear_selection!`/`_sync_selection!`
→ `getfield(doc,:selection)[]=…`) is **path-routed** (descends only via `_selection_child` along the
current path) or on a **projection output root** — never a nested colour. So a non-selectable colour's
selection is written **only if a path routes into it**, and nothing routes into a colour by default
(colours are leaves). **Latent footgun:** a promoted colour is a `Document`, so `_selection_child`
would return it; if a future projection emitted a path into a *non-selectable* colour the write would
be a `MethodError`, not a graceful decline. **Cheap fix:** make `_selection_child` treat an
immutable-selection node as a leaf (`return nothing`) → non-selectable documents degrade gracefully.

**Verdict:** the promotion is viable with the selection parameter. Macro work still needed: (1) allow
an explicit `selection` field (today errors) so its value type controls selectability; (2) optional
`RFoo(vals…)` value ctor; (3) the `_selection_child` graceful-leaf guard. Then convert `StyleColor`
and re-run the suites.

### Part C impl progress

- **Explicit-`selection` support — DONE + verified.** `@document` now accepts an explicit `selection`
  field (must be last; `= nothing` supplied if omitted) instead of erroring. Verified:
  `@document ImmutableCell struct SC; red..alpha::Float64; selection::ImmutableCell{Nothing}; end` →
  bare `SC(r,g,b,a)` returns **`ISC`, isbits=true**; `ImmutableCell{ISC}` **inlines**; the reactive
  form (via `SC(Cell…)`) is editable + selectable. Full-stack precompile clean.

- **Remaining, and its real cost.** With explicit-selection, the *concrete* form `ISC` is isbits and
  `ImmutableCell{ISC}` inlines — but the **name** `StyleColor` is still the parameterized stem
  (UnionAll), so `ImmutableCell{StyleColor}` still boxes. Two ways to finish:
  - **(a) naming mode** — make `@document` (value-document) emit the stem under an internal name and
    `const StyleColor = <stem>{concrete default}` + a delegating `StyleColor(args…)` ctor (needs
    Rule-Y-style selection fill). Then `ImmutableCell{StyleColor}` inlines and nothing downstream
    re-types. **Cost:** a name/stem split touching every emitter + the alias-prefix naming + a
    delegating ctor that coexists with the `IFoo` value ctor — a focused refactor of the `@document`
    codegen, exercised on *every* document type.
  - **(b) mechanical re-type** — keep `StyleColor` = stem; convert the ~200 `ImmutableCell{StyleColor}`
    /`{StyleFont}`/`{StyleText}` config fields to the concrete `I…` alias. A sed; safe (config is
    always the immutable form); no macro change.
  Both reach isbits/inline. (a) matches the "`StyleColor` is the concrete name" preference at higher
  macro risk; (b) is simpler but re-types the config fields. Pending the user's call before the
  pervasive `StyleColor` conversion.

## Status
- Worktree `/home/projectured/workspace/projectured-julia-cellkind`, branch `document-field-cell-kind`.
- Part A done. Part B measured → recommend design (b) instead of promotion.
