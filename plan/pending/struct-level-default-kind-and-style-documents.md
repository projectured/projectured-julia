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

Part A shipped (independently useful). Part B is not worth doing as a value-type promotion; if style
editing is wanted, do the `ColorDocument`/`ColorToWidget` projection instead — awaiting user's call.

## Status
- Worktree `/home/projectured/workspace/projectured-julia-cellkind`, branch `document-field-cell-kind`.
- Part A done. Part B measured → recommend design (b) instead of promotion.
