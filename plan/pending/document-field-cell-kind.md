# Per-field default cell kind for `@document` (+ immutable style)

## Goal

Extend the `@document` macro so each field can declare a **default cell kind**
(reactive / immutable / mutable). Use it to make authored **style** fields
(`StyleFont`, `StyleColor`) default to `ImmutableCell`, eliminating the
dependent-edge fanout those shared style constants accumulate — while keeping the
reactive kind available per instance for the few sites that genuinely mutate style.

This is a **cleanliness + allocation** win, not a slowdown fix. Measured facts
that motivate it (workbench_example, 23 670 live cells, on branch main):

- `dependents` (the downstream edge) fanout: mean 0.68, median 0, p99 4, max **104**.
- The large-fanout cells are all **shared, primitive, never-written** style/theme
  constants (a `String` at 104, `StyleColor`/`StyleFont` at 72/72/24…, an `Int64` at 63).
- A primitive cell that is never written never invalidates, so its whole
  `dependents` vector is maintained (register/unregister scans on every reader
  recompute) but never used. `ImmutableCell` reads register **nothing**, and an
  `ImmutableCell` inlines into its parent (no separate `Set`+`Vector` allocation).
- The one micro-cost the earlier Set→Vector change introduced — the O(n) register
  round-trip, ~5× slower than the Set at n=104 — is paid *only* on these high-fanout
  cells. Removing the fanout removes that cost too.

Baseline end-to-end A/B already showed no slowdown from Set→Vector; this change is
strictly additive on top of it.

## Design — the macro extension

Surface syntax: **a field's declared type is the cell kind, carrying the value
type as its parameter.** An unannotated field (`f` or `f::T`) means reactive, as
today.

```julia
@document struct TextString <: TextDocument
    content::AbstractString                 # unannotated → ReactiveCell{Any}
    font::ImmutableCell{StyleFont}          # default kind = ImmutableCell
    font_color::ImmutableCell{StyleColor}
    fill_color::StyleColor                  # left reactive (often `nothing`; low fanout)
    line_color::StyleColor
    padding::Inset
end
```

### Two families — the feature spans both cell-struct codegens

There are **four** transparent-cell-struct macros in two families that share only
the `StructPlan` parse:

- **Family A — `cell_struct_exprs`**: `@cell_struct`, `@projection`, `@iomap`
  (`@projection` = `cell_struct_exprs` + `<: Projection`; `@iomap` similarly).
  Fields are **fixed** `::Cell`, not kind-parameterized.
- **Family B — `@document`**: its own codegen, kind-parameterized `Foo{C1,…}`
  with `R/I/M` aliases. Does **not** route through `cell_struct_exprs`.

Style fields live in **both**: `TextString` (@document) *and* the `@projection`
config structs (`ObjectToSyntax.style/quote_style/value/…`,
`CollectionToSyntax.delim/sep`, `ReferenceToText.font`). A projection's single
`style` cell is read by every node it projects, so it — not the per-span
`TextString` cells — is the likely source of the shared 72-fanout cells. The
baseline owner-attribution measurement will confirm.

So the feature is layered:

| layer (all unsealed) | change | covers |
|---|---|---|
| `cell/StructPlan.jl` | parse declared type → `(kind, value_type)`; `declared_value_types` strips the kind wrapper; add `field_cell_kinds(plan)` | shared parse |
| `cell/CellStruct.jl` (`cell_struct_exprs`, `cell_struct_autowrap_ctor`) | field type = its **fixed** kind cell; autowrap wraps raw in that kind | `@cell_struct` / `@projection` / `@iomap` |
| `document/DocumentMacro.jl` | per-field **default** kind (parameterized, overridable) | `@document` |

**The asymmetry is intentional.** Family A fields are *fixed* (a projection never
mutates its own `style`; no override or kind-parameter needed — simpler, lower
risk). Family B (`@document`) fields stay *overridable* (the `ConversationEditor`
carve-out flips one span's `font_color` to reactive per instance). Same
annotation; "fixed kind" in a plain cell-struct, "default kind" in a document.
Backward-compat holds in both: no field annotated ⇒ all `:reactive` ⇒
byte-identical codegen to today.

### Semantics (must hold)

1. The struct stays **fully kind-parameterized** — `Foo{C1<:AbstractCell,…}`. The
   per-field kind is only the *default the bare `Foo(raw…)` ctor wraps with*, never
   a fixed field type. So `RFoo`/`IFoo`/`MFoo` aliases are **unchanged** (they still
   force one kind across all fields).
2. `getindex`/pass-through override still works: `Foo(Cell(v), …)` puts a reactive
   cell in a normally-immutable field. This is how the carve-out sites opt back in.
3. **No field annotated ⇒ bare `Foo` ≡ `RFoo`**, byte-for-byte as today (backward
   compatible). At least one annotated ⇒ bare `Foo` builds the *default field
   cell-kind combination*.
4. Reactive default stays `ReactiveCell{Any}` (the historic untyped `Cell`, loose
   bound). Immutable/mutable defaults use the **typed** cell `{T}` so they inline —
   consistent with how `IFoo`/`MFoo` already behave.

### Parse rule

Detection is **syntactic** at macro-expansion time (no resolved types available):
a field's declared type is a "kind" iff its head symbol is one of the reserved cell
names `ReactiveCell` / `Cell` / `ImmutableCell` / `MutableCell` (bare `X` or `X{…}`).
Anything else is a value type wrapped in the reactive default. Those names are
reserved cell vocabulary, so the check is safe.

### Touch points (all unsealed) — see the two-families table above

- `cell/StructPlan.jl` — parse declared type → `(kind, value_type)`;
  `declared_value_types` strips a kind wrapper (`ImmutableCell{T}` → `T`; plain types
  unchanged, so `StructPlanTest` is unaffected); add `field_cell_kinds(plan)`.
- `cell/CellStruct.jl` — `cell_struct_exprs` retypes each field to its **fixed** kind
  cell instead of uniform `:Cell`; `cell_struct_autowrap_ctor` wraps a raw value in
  that kind and passes any `AbstractCell` through (widen `isa Cell` → `isa AbstractCell`).
- `document/DocumentMacro.jl` — `_emit_autowrap_ctor` wraps each raw arg in *its
  field's* default kind (the "no cell" fast path builds the default combination);
  `_emit_kind_aliases` uses the stripped value types; the "all reactive" fast path
  stays so an all-reactive struct is byte-identical.

## Phases

### Phase 1 — macro extension (backward-compatible, a no-op until a field is annotated) — DONE
- [x] Shared parse in `StructPlan`: `field_cell_kinds` + kind-stripping `declared_value_types`
      (`_cell_kind_name`/`_field_kind_type` helpers; export `field_cell_kinds`).
- [x] Family A: per-field fixed kind in `cell_struct_exprs` + `cell_struct_autowrap_ctor`
      (reactive branch kept byte-identical; non-reactive uses `isa AbstractCell`).
- [x] Family B: per-field default kind in `DocumentMacro._emit_autowrap_ctor` (`_default_cell_type`
      helper; aliases use the now-stripped value types).
- [x] **Checkpoint:** full-stack precompile clean; smoke test green (unannotated → all reactive;
      annotated → mixed default combo; per-instance override; `IFoo`/`MFoo` strip the wrapper so
      field 1 is `ImmutableCell{Int}`, not double-wrapped). `test_kernel()` **431 pass / 0 fail /
      0 error / 0 broken**. Codegen is byte-identical for unannotated structs, so this is a true no-op.

### Phase 0/baseline measurement (before converting anything)
- [ ] Extend the measurement harness to (a) census cell kinds (Reactive/Immutable/
      Mutable counts), (b) **attribute** each >16-fanout cell to an owning struct
      type + field (so we know whether the fanout is in TextString source or in the
      TextToGraphics/pl0 output layer — the earlier analysis was unsure).
- [ ] Run on `text_example` (isolates TextString) and `workbench_example` (original
      target). Record baseline numbers in this plan.

### Phase 2 — TextString first consumer + measure
- [ ] Annotate `TextString.font` / `font_color` as `ImmutableCell{…}` (the always-
      present, high-fanout fields). Leave `fill_color`/`line_color`/`padding`
      reactive for now — they are usually `nothing`, and `ImmutableCell{StyleColor}`
      can't hold `nothing` without widening the value type to `Union{…,Nothing}`.
- [ ] Rewrite the hand-written `TextString(content, font, color)` convenience ctors
      (Text.jl) to pass **raw** font/color through so the macro default applies
      (they currently hard-wrap in `Cell()`), keeping `content` reactive.
- [ ] **Carve-out:** `ConversationEditor._editable_body` does
      `set_function!(getfield(value_span,:font_color),…)` — build those spans with an
      explicit `Cell(color)` so the field is reactive there. Same for any other
      `set_function!`/`setproperty!` on a span's style (audit: `hinted_text` already
      passes `Cell(()->…)`, so it's fine).
- [ ] Measure fanout + microbench on text_example + workbench_example. Record delta.

### Phase 3 — all authored style immutable by default + measure
- [ ] Sweep the **`@projection`/`@iomap`/`@cell_struct` config structs** (Family A) —
      likely the biggest win: `ObjectToSyntax.style/quote_style/value/type_name/…`,
      `CollectionToSyntax.delim/sep`, `ReferenceToText.font`, `SyntaxToText.deco_font`,
      and the rest surfaced by the audit. These become fixed `::ImmutableCell{…}`.
- [ ] Sweep the remaining **`@document`** style fields (Family B).
- [ ] Audit every struct with a `StyleFont`/`StyleColor`/`StyleText` field. Classify:
      **authored/source** (→ immutable) vs **computed/output** (ever `set_function!`'d /
      `setproperty!`'d — e.g. `GraphicsText.font/color` set by `TextToGraphics`,
      conversation value spans → **keep reactive**). Grep `set_function!`/`setproperty!`
      on each candidate before converting.
- [ ] Convert the authored ones; leave the computed ones reactive.
- [ ] Handle the `nothing`-valued optional colors: either widen to
      `ImmutableCell{Union{StyleColor,Nothing}}` or keep reactive — decide per the
      measured fanout of those specific fields.
- [ ] Measure fanout + microbench again. Record final delta.

## Measurement harness

Reuse the session scripts (adapted, committed under `bench/` in the worktree so the
plan is reproducible):
- `fanout_distribution.jl` — dependents fanout distribution + **cell-kind census** +
  **owner attribution** for top cells.
- `microbench_set_vs_vector.jl` — register/detach + invalidation cost at the observed
  max fanout (re-run at the *new, smaller* max to show the register-scan cost dropped).

Metrics to track at each checkpoint (text_example + workbench_example):
- total ReactiveCells vs ImmutableCells; `dependents` sum, mean, p99, **max**.
- cells with fanout >16 / >64 (and their owners).
- build allocation (GB) — fewer `Set`+`Vector` allocations.
- worst-case register round-trip ns at the new max fanout.

## Risks / constraints

- **Concrete-type proliferation.** Mixed kinds ⇒ `TextString{ReactiveCell,ImmutableCell,…}`
  is a new concrete type distinct from the all-reactive one. Plain spans share ONE
  such type (homogeneous — good); reactive-style spans are another. A few types, not
  an explosion. Watch compile time.
- **Immutable ⇒ no in-place style edit.** `setproperty!`/`set_function!` on an
  immutable field is a `MethodError`. Every mutate-style site must construct reactive
  (the carve-outs). There is currently **no** recolor operation, so nothing else breaks.
- **`nothing`-valued optional colors** can't sit in `ImmutableCell{StyleColor}` — see Phase 3.
- **Live theming.** If a shared theme cell is ever meant to broadcast a change to all
  readers, it must stay reactive. Confirm via owner attribution that no high-fanout
  cell is such a hub before demoting it.

## Verification (per repo conventions)

- A macro change is validated by a **real precompile + load**, not just guards
  (memory: "guards are not a load check", "clean load ≠ migration check"). Read the
  precompile warnings; scan for unresolved globals.
- Targeted tests: `test_text()`, `test_syntax_to_text()`, `test_printer/reader` on a
  text example; then, for a shared-seam change, a **full-suite baseline diff** vs main
  (memory: "wide refactor → baseline diff") — Fail/Error counts must not rise;
  pass-count shifts are explained by field-count/cell-kind changes.
- Run everything under a `systemd-run` memory cap (memory: "cap Julia test memory").

## Status

- Worktree: `/home/projectured/workspace/projectured-julia-cellkind`, branch
  `document-field-cell-kind`, off `main` @ b27dbd11.
- Not started (this file is commit 1).
