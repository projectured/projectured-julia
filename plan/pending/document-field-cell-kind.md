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

### Touch points (all unsealed)

- `cell/StructPlan.jl` — parse each field's declared type into `(kind, value_type)`;
  expose a per-field default-kind vector alongside `declared_value_types`.
- `document/DocumentMacro.jl` — `_emit_autowrap_ctor` wraps each raw arg in *its
  field's* default kind instead of uniform `_REACTIVE_ANY`; keep the "all reactive"
  fast path firing when every field defaults reactive (backward compat). Alias
  emitter (`_emit_kind_aliases`) unchanged.
- `cell/CellStruct.jl` — only if its auto-wrap path needs the same treatment (audit).

## Phases

### Phase 1 — macro extension (backward-compatible, a no-op until a field is annotated)
- [ ] Parse per-field default kind in `StructPlan`.
- [ ] Emit per-field-default wrapping in `DocumentMacro`.
- [ ] **Checkpoint:** precompile the whole stack + `using Projectured` (a macro
      change runs at every `@document` expansion). Run a broad targeted suite and
      confirm **zero** change vs main baseline (no field annotated yet, so bare ==
      RStem everywhere). Pass-count must not move (per "test counts track cell count").

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
- [ ] Audit every `@document` struct in `package/visual/main` (and domains) with a
      `StyleFont`/`StyleColor` field. Classify each field:
      **authored/source** (→ `ImmutableCell` default) vs **computed/output**
      (ever `set_function!`'d / `setproperty!`'d — e.g. `GraphicsText.font/color` set
      by `TextToGraphics`, conversation value spans → **keep reactive**).
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
