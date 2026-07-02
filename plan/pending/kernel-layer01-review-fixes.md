# Kernel layer 0/1 review fixes

Fix list from the 2026-07-02 code review of the kernel's **layer 0** (`reactive/`)
and **layer 1** (`api/*`, `common/Change|Document|IoMap|Operation|OperationRerooting`,
`reference/*`, `document/Collection|Primitive`), as delimited by the include-list
sections in `ProjecturedKernel.jl`. Review criteria: (a) these layers must not
talk about anything declared *forward* of them in the architecture (projections,
editor, backends, concrete domains), (b) clarity, (c) purity, (d) idiomatic code.

Companion to [kernel-cleanup.md](kernel-cleanup.md), which owns the *structural*
work (module consolidation, api/impl separation). Items already tracked there —
the `Change` and `NoOperation` moves out of `api/` — are **not** repeated here.
Where a fix below touches a file that plan will later move, land the fix first;
the moves are mechanical.

Execution conventions (per global plan rules): work in a dedicated worktree,
commit per step **with explicit paths** (the main checkout is shared), tick each
item here as it lands, and record any decision changes inline.

---

## Group C — correctness

- [x] **C1. Type-preserving path concatenation.** Three copies of path-concat all
  rebuild the left spine with the 2-arg `ConcreteReferencePath` ctor, silently
  blanking the folded node `type` fields — so appending to an annotated
  (canonical) path de-canonicalizes it under the strict `==`:
  - `append_reference` (`reference/Reference.jl`, both methods),
  - `_concat_paths` (`common/Operation.jl`),
  - `_concat` (`reference/ReferenceBuilder.jl`) — whose comment even claims
    spliced folded sub-paths are "kept"; true only when the splice is the *last*
    segment (`^(expr).field` loses the spliced types).

  Fix: one canonical, type-preserving concat exported from `ReferenceModule`
  (`ConcreteReferencePath(a.type, a.head, …)` on the walk); make
  `append_reference` preserve the terminal `EmptyReferencePath` type onto the
  new node it grows (the terminal's type *is* the type of the node the first
  appended step descends from); delete the two duplicates. Junction rule per
  D-1: keep `b`'s node types verbatim; apply `a`'s terminal type to the grown
  node only when `b`'s head has `type === nothing`; never invent types. Ship
  with unit tests (folded × skeleton × spliced, both directions) since strict
  `==` makes the junction rule observable.

- [x] **C2. `PrimitiveString` byte-indexing.** `Base.setindex!(::PrimitiveString,
  ch, i)` splices with byte indices (`str[1:i-1] * … * str[i+1:end]`) and
  `getindex(s, r::UnitRange)` byte-slices, while `splice_string` is deliberately
  character-aware. Multibyte content breaks both. Route them through
  `splice_string` / character-aware indexing (`document/Primitive.jl`).

- [x] **C3. `CellVector(n::Integer)` footgun.** `CellVector(5)` makes five
  `nothing` slots; `CellVector(5, 6)` makes elements `[5, 6]` — same name,
  unrelated semantics, one argument apart (`document/Collection.jl`). Replace the
  `Integer` ctor with `CellVector(undef, n)` and migrate every call site in
  kernel, domain, and tests (no deprecation shim — D-4).

## Group S — stale docs/comments (mostly type-folding leftovers)

- [x] **S1.** `OperationModule` docstring is factually wrong: "Loaded after
  EditorModule so the Editor type is available" — it loads far *before*
  EditorModule and `evaluate_operation` is duck-typed; the Editor type is never
  available (`common/Operation.jl:1-6`). Rewrite to describe what the module
  actually is (built-in operations + selection propagation + splice helpers).
- [x] **S2.** `set_selection!` docstring says a fresh `TypeReference(typeof(node))`
  is "inserted before every navigation step" — the folded model fills node
  `type` *fields*; no step is inserted (`common/Operation.jl`).
- [x] **S3.** Vestiges in `clear_selection!` / `_set_selection_walk!`: the
  "Skip leading type checkpoints" comments describe skipping that no longer
  happens; one ends with a dangling "(mirrors evaluate_reference / )"; the
  `nav = path; nav isa ConcreteReferencePath || return` re-check is redundant
  with the line above it (`common/Operation.jl`). (Largely subsumed by D2.)
- [x] **S4.** `ReferenceCase.jl` PSIndex/PSPosition comments reference
  "`ElementReference.index[]`" / "`PositionReference.index[]`" — those structs
  no longer exist (unified `RangeReference`).
- [x] **S5.** `ReferenceModule` docstring claims "All reference steps and paths
  are immutable" — `@document` makes them *mutable* structs of Cells (that is
  what `_mutate_terminal_step!` exploits). Also fix two wrong docstring
  signatures: `ReferencePath(steps::Reference...)` and
  `append_reference(base, steps::Reference...)` → `ReferenceStep...`.
- [x] **S6.** `CollectionDocument` docstring describes only 2 of its 4 union
  members (`document/Collection.jl`).
- [x] **S7.** The "Inter-string boundary behaviour" paragraph is pasted into both
  replace-range op docstrings; it is meaningless for
  `NumberReplaceRangeOperation` (numbers have no adjacent string spans). Keep it
  on the string op only (`document/Primitive.jl`).

## Group L — layering: no forward talk in layers 0/1

Layer 0:

- [x] **L1. PerformanceCounter.** Stop pre-seeding the editor-stage keys
  (`:read_time`, `:evaluate_time`, `:print_time`) in `_perf` — `perf_record!`
  creates keys on demand, so the editor can own its counter names; reword the
  module/`perf_counters` docstrings to stop describing "the editor's read
  stage" (`reactive/PerformanceCounter.jl`).
- [x] **L2. Reactive.jl prose.** Remove editor/assistant/document references:
  module docstring + `peek` docstring name `EditorTimeModule`/`editor/Time.jl`
  (say "a caller that samples rather than subscribes, e.g. a per-frame clock");
  `_force_thunk` comment names "the assistant's `execute_julia_code`" and the
  render loop (the generic constraint is "a thunk constructed in a newer world
  than the caller's"); `Base.show` comment names `:document_depth` (say
  "forward `io` so IOContext keys set by callers stay in effect").

Layer 1 — api stubs:

- [x] **L3. api/Backend.jl.** Five docstrings each say "Implemented by the SDL
  backend"; `render_canvas` types its signature with `GraphicsCanvas ->
  GraphicsImage` (domain types); `pointer_position` cites "the hover reference
  inspector". State the provenance pattern once in the module docstring
  ("methods are registered by opt-in backend packages") and keep per-function
  text and signatures generic.
- [x] **L4. api/Projection.jl.** Keep the four-function contract text but move
  the domain-package examples (`JsonNumberToSyntaxLeaf`, `_syntax_to_flat`,
  "`*ToSyntax` node readers", graphics/widget/popup-anchoring stories) into
  `documentation/projection-system.md` (already cross-referenced). The
  kernel-resident combinators (`SequentialProjection` …) may stay as examples.
- [x] **L5. api/Document.jl.** `document_read` docstring: keep the load-bearing
  `GestureBindingModule` note, drop the `ConsoleBackend`/`TextText`/"(Text,
  Syntax)" domain examples. Also clarify the `Document` selection contract
  wording ("a `selection::Reference` field … stored in a `Cell`"): the struct
  field holds a `Cell`; `document.selection` reads through it via the
  `@document`-generated `getproperty`, so `selection(::Document)` returns the
  path/`nothing`, not the Cell.
- [x] **L6. api smaller.** `api/Operation.jl`: drop "concretely an
  `EditorModule.Editor` in production" and the "used to carry splice_*"
  provenance note. `api/Device.jl`: replace the `SdlBackend` example with a
  generic one. `api/IoMap.jl`: add the missing module docstring (only api file
  without one).

Layer 1 — core:

- [ ] **L7. common/Operation.jl operation docstrings.** Trim the layer-2/3/domain
  narration to each operation's *semantics*, moving producer/consumer inventory
  to `documentation/operations.md`: `TooltipDecoratorProjection` /
  `WindowManagerProjection` / `CopyingProjection` / `WidgetSelect` (window ops),
  `SyntaxNodeToText` / `SyntaxToText` / `TextToGraphics` / `Ctrl+.`
  (`ToggleCollapseOperation`), "lives in the SDL backend" + `_FONT_ZOOM` (zoom
  ops), `MousePress` / `Ctrl+Home` (`ReplaceSelectionOperation`),
  `JuliaInsertion` / "the Julia Tab gesture" (`SelectNextInsertionOperation`),
  `WorkbenchPage`, "the clipboard cut gesture" (`CompoundOperation`).
- [x] **L8. OperationRerooting docstring.** Generalize away `WidgetComposite` /
  `WidgetToGraphics` / `LayoutToGraphics` / `ProjectionTemplate.jl` (all domain
  package): "a container projection prepends the steps that reach the routed
  child" carries the idea.
- [x] **L9. Scattered comments.** `reference/Reference.jl`: `search_references`
  (lives in the domain package) and `step_iomaps` (layer 2) in the `_deref_cell`
  comment; `JsonArray` + commit hash in `valid_reference_prefix`.
  `ReferenceCase.jl`: `TextString`, "the navigator repl". `ReferenceBuilder.jl`:
  `JsonNumber`. `common/Document.jl`: `JsonArray` (`@forward` example),
  `JsonObject` (Rule C comment), "mixed JSON / text / widget" (`@document`
  docstring), "clipboard / versioning projections" (`copy_document` header) —
  use neutral or kernel-resident examples.
- [ ] **L10. `editor.iomap` in layer 1 (code-level).** `evaluate_operation(editor,
  ::ReplaceReferencedValue)`'s whole-root swap writes `editor.iomap = nothing` —
  layer 1 knowing the editor caches an iomap and how to invalidate it. Per D-3:
  add an api-level `invalidate_projection!(editor)` stub (default no-op),
  implement it in EditorModule to drop the cached iomap, and call it here
  instead of the direct field write.
- [ ] **L11. Move window operations next to `WindowDocument`.** Per D-2,
  relocate `OpenWindowOperation` / `OpenPopupOperation` / `CloseWindowOperation`
  / `ResizeWindowOperation` and their `evaluate_operation` methods from
  `common/Operation.jl` into `document/ScreenDocument.jl` (their schema mirrors
  `WindowDocument`, which lives there). Move the exports accordingly and fix
  importers; coordinate with kernel-cleanup.md Phase 2.

## Group D — duplication / purity

- [x] **D1. `@iomap` duplicates `@document`'s codegen** (~80 lines: Cell field
  rewrite, auto-wrapping inner ctor, getproperty/setproperty! chains, kwctor)
  in `common/IoMap.jl` vs `common/Document.jl`. Extract shared helper functions
  (the way `_forward_defs` already serves `@forward*`); `@iomap` is a strict
  subset of `@document`'s features, minus the I-struct/Rule Y/Rule C parts.
- [x] **D2. Selection descent triplicated.** `clear_selection!`,
  `_set_selection_walk!`, and `_selection_child` each carry the identical
  FieldReference/RangeReference descent block with the same comment
  (`common/Operation.jl`). Express the first two via `_selection_child`.
  Subsumes S3.
- [x] **D3. Path unroll/rebuild helpers.** `_split_terminal_step`
  (`common/Operation.jl`) and `_split_replace_reference` /
  `_replace_terminal_with_cursor` (`document/Primitive.jl`) re-implement the
  same "steps vector ↔ path" walk. Provide shared helpers in `ReferenceModule`
  (pairs naturally with C1; the rebuild side must be type-preserving or
  explicitly skeleton-producing).
- [x] **D4. Include reorder + real `isa`.** `document/Collection.jl` imports
  nothing from `OperationModule`, so include it *before* `common/Operation.jl`
  and replace the `nameof(typeof(node)) === :CellVector` name-match hack in
  `_preorder_documents!` with a real import + `isa`.
- [x] **D5. Redundant Cell-wrapping outer ctors** in `reference/Reference.jl`:
  `RangeReference(Int,Int)`, `FieldReference(String)`, `PointReference(Int,Int)`
  — the `@document` inner ctor already auto-wraps. Delete.
- [x] **D6. Silent catch-all `evaluate_operation(editor, op)`.** Opposite
  philosophy to `DeviceModule`'s documented "deliberately no catch-all". If the
  swallow is intentional (raw events bubbling out of the reader), say so in the
  comment; otherwise narrow it.
- [x] **D7. Swallowed exceptions in `collect_references` / `_search_document`**
  (`reference/Reference.jl`): three bare `catch end` blocks plus a blanket
  `@error`. Narrow to what each is expected to absorb (unindexable access,
  non-iterable field).
- [x] **D8. `copy_document` Cell rewrap edge** (`common/Document.jl`): reads
  `raw isa Cell ? raw[] : raw` but then unconditionally re-wraps in `Cell(...)`
  — for a non-Cell field of a hand-written Document this changes the field's
  representation and fails the default ctor. Either assert the all-Cell
  convention or preserve rawness.
- [x] **D9. Dead `_gen_step_match(..., ::PSType, ...)`** in
  `reference/ReferenceCase.jl`: both `_gen_path_match` and `_gen_prefix_match`
  intercept a leading `PSType` before step dispatch and steps are always
  consumed from position 1, so the method is unreachable. Verify and delete.

## Group I — idiomatic / documentation gaps

- [x] **I1.** Docstrings for `@reference`, `@reference_case`, `@step` (currently
  no REPL help at all for the two most-used DSL entry points; the grammar lives
  only in `#` header comments) and module docstrings for
  `ReferenceCaseModule` / `ReferenceBuilderModule`.
- [x] **I2.** `PrimitiveInsertion` docstring (siblings all have one).
- [x] **I3 (optional).** `take_first_n` (`document/Collection.jl`): **kept** per
  D-5. Optional tidy only — type the accumulator (`result = Any[]`), drop the
  dead `current === nothing` checks; leave both overloads and their semantics
  intact.
- [x] **I4.** `isuptodate(cs::Vector{Cell})` → `all(isuptodate, cs)`;
  `perf_reset!`'s single-line `for k in keys(_perf); …; end` → multi-line.

---

## Resolved decisions (2026-07-02)

- **D-1 (C1): concat semantics for folded types — RESOLVED: agree.** When
  concatenating `a ⧺ b`, the junction node holds *one* type. Rule: keep `b`'s
  node types verbatim; use `a`'s terminal type only for the node grown from
  `a`'s terminal when `b`'s head node has `type === nothing`; never invent
  types. Strict `==` means this shifts equality of concatenated vs
  hand-annotated paths, so C1 must ship with targeted unit tests
  (folded × skeleton × spliced, both concat directions).
- **D-2 (L11): window operations — RESOLVED: move next to `ScreenDocument`.**
  Relocate `OpenWindowOperation` / `OpenPopupOperation` / `CloseWindowOperation`
  / `ResizeWindowOperation` (and their `evaluate_operation` methods) from
  `common/Operation.jl` into `document/ScreenDocument.jl`, where
  `WindowDocument` lives — they are its vocabulary. Update
  `OperationModule`/`ProjecturedKernel` exports and any importers. Coordinate
  with kernel-cleanup.md Phase 2 so the two don't collide.
- **D-3 (L10): editor invalidation seam — RESOLVED: add
  `invalidate_projection!`.** New api stub (default no-op), implemented by
  EditorModule to drop the cached iomap; `evaluate_operation(::ReplaceReferencedValue)`
  calls it instead of writing `editor.iomap = nothing` directly.
- **D-4 (C3): `CellVector(n::Integer)` — RESOLVED: migrate.** Replace with
  `CellVector(undef, n)` (or equivalent unambiguous form); update all call
  sites in kernel, domain, and tests. No deprecation shim.
- **D-5 (I3): `take_first_n` — RESOLVED: keep.** Do **not** delete. Downgrade
  I3 to an optional idiomatic tidy (typed accumulator, drop dead
  `current === nothing` checks) — leave the two overloads and semantics intact.

## Verification

Smallest-scope tests per group (do **not** run `test_all` per step; heavy runs
happen in the user's external terminal, not the editor host):

- C1/D3/D5 + anything touching references: `test_cell()` is unaffected; use the
  reference-focused walkers — `test_printer(json_example)` +
  `test_reader(json_example)` exercise annotate/strip/concat heavily; add unit
  tests for the new concat (folded × skeleton × spliced cases, strict `==`).
- C2: a small multibyte `PrimitiveString` unit test (é/emoji) around
  `setindex!`/`getindex`.
- C3/D4: precompile + `test_printers()` only if ctor call-site audit shows wide
  use; otherwise the touched domains' `test_example`.
- L1/L2: `test_cell()`.
- D1 (`@iomap`/`@document` codegen share): precompile is the main gate (macro
  method-overwrite risk — remember the Rule Y `req ≥ 1` guard); then
  `test_example(json_example)`.
- D2/S3: `test_text_navigation(json_example)` + `test_repl(json_example)`
  (selection propagation paths).
- Docstring/comment-only groups (S, L3–L9, I1, I2): no test run needed beyond
  precompile.
