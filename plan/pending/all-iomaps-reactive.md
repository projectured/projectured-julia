# Every IoMap struct is `@iomap`

## Goal

Uniform rule, no per-struct judgment: **every** `struct … <: IoMap` is declared with
`@iomap`. Rationale — any projection may return any IoMap struct (its own or a shared
default) and must be able to rely on it being reactive-capable: its fields transparently
unwrap cells (`iomap.field` → value, `getfield` → raw cell), so a computed-cell field
re-derives while the IoMap keeps its identity (AR-STABLE-IOMAP-IDENTITY). A plain struct
silently defeats that for a future consumer.

## The conversion + its ripple

`struct X <: IoMap` → `@iomap struct X` (drop the explicit `<: IoMap`; the macro injects it).

- **Fields that hold a plain value today** (e.g. `output` = a document): behaviour-neutral.
  The `@iomap` constructor wraps the value in a `Cell`; `iomap.field` unwraps back to the
  same value. Property-access consumers are unaffected.
- **Fields that hold a `Cell` today** (e.g. `window_iomaps::Cell`): the constructor keeps
  the cell (no double-wrap), and `iomap.field` now returns the *value* instead of the cell.
  **Ripple:** every `iomap.field[]` (property + deref) consumer must drop the `[]`
  → `iomap.field`; `getfield(iomap, :field)[]` still works. Found by grep + tests
  (a broken site fails with `MethodError: no method matching getindex(::<value>)`).

## Special cases — derived `.output` via custom `getproperty`

`@iomap` generates `getproperty` (to unwrap fields), which collides with a hand-written one.
Two structs synthesise a **derived** `.output` that is not a stored field:

- `ChainingProjectionIoMap` (`base/…/Chaining.jl`) — `.output = step_iomaps[end][].output`.
- `VersioningToAnyProjectionIoMap` (`domain/…/VersioningToAny.jl`) — derived `.output`.

Fix: **store `output` as a computed cell field** (`output = Cell(() -> …)`) and drop the
custom `getproperty`, so `@iomap`'s accessor handles it uniformly. (This is the "store
output as a field" option the reactive-iomap plan noted for Chaining.) Chaining is the
universal critical path — convert last, verify broadly.

## Batches (convert, then load + targeted tests, fix ripples, commit)

- [ ] **B0 — kernel defaults:** `ContentIoMap` (IoMapDefaults.jl), `RuleIoMap`
  (ProjectionTemplate.jl). Verify `test_kernel` + a template-driven domain.
- [ ] **B1 — visual, all-plain / simple:** ProjectionConfiguring, ObjectToWidget,
  the WidgetToGraphics IoMaps (ScrollPane/TransformPane/Dialog/Table/Tree/ScrollViewport),
  GridLayoutIoMap. `test_visual`.
- [ ] **B2 — visual text/syntax/screen (Cell fields):** TextFiltering, TextFirstLine,
  SelectionInverting, WordWrapping, TextHighlighting, TextToGraphics, SyntaxCompoundToText,
  ScreenToScreen (+ ScreenWindowIoMap), WindowManaging, Clipboard (Slice/Collection).
  Fix `.field[]` ripples. `test_visual`.
- [ ] **B3 — domain:** GraphGraphToGraphLayout, GraphLayoutToGraphicsCanvas,
  Workbench (Shell/Navigator). `test_domain`.
- [ ] **B4 — special getproperty:** VersioningToAny, then ChainingProjectionIoMap
  (store `output` cell, drop custom getproperty). `test_base` + `test_visual` + `test_domain`.

## Verification

Per batch: load + the batch's package suite (memory-capped). Final: base + visual + domain
all 0-fail (Broken 1/5 baseline). Avoid `test_all` — the kernel `NavigationTest` reaches-all
is a known memory hog that stalls the run; run per-package instead.

## Done

Move to `plan/done/`, ff `iomap-all-reactive` → main.
