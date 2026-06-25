# Eliminate `skip_type_checkpoints` — fold the type into every path node

Make a node's type a **mandatory structural part of every reference**: each
linked-list node of a `ReferencePath` carries the Julia type of the document it
stands on. The interleaved `TypeReference` *step* disappears, so there is no
longer a variable number of leading checkpoints to peel — `head` is **always** a
navigation step. `skip_type_checkpoints` (184 call sites) becomes meaningless and
is deleted; most of `strip_reference_types` (87 sites) follows.

> Status: **IMPLEMENTED.** `skip_type_checkpoints` is fully eliminated (function,
> export, 135 call sites, 4 matcher wrappers, ~30 import mentions all removed). A
> node's type is now a mandatory `type` field on every `ReferencePath` node;
> `head` is always a navigation step. See **"Implementation outcome"** at the end
> for the as-built design, deviations from the draft below, and test status.
> Builds on the completed
> [`type-reference-everywhere`](../done/type-reference-everywhere.md) work, which
> had made `TypeReference(T)` checkpoints the canonical-at-rest *and*
> output-resident form but left every hand-written structural walker merely
> *tolerant* (calling `skip_type_checkpoints` to skip an **optional** number of
> leading checkpoints). This plan promoted "a type before every object" from a
> tolerated convention to a **structural invariant**.

## Design decision (chosen: fold type into the node)

The user chose **Option 1 — fold the type into each path node** over keeping
`TypeReference` as an interleaved step and enforcing-then-inlining the skip
(rejected: relies on every producer emitting canonical form by convention and
crashes on any plain skeleton or transient mapped tail — the very paths the
prior plan showed are unavoidable at construction time).

### The "two TypeReferences per FieldReference?" question — RESOLVED

A `FieldReference` connects two nodes: the object it descends **from** and the
value it lands **on**. It might seem to need two type checkpoints (a start and an
end). It does not. In today's flat canonical form
(`…[1]{{JsonObjectEntry}}.value{{JsonString}}.value{{String}}{3}`) the checkpoint
*between* two steps is **simultaneously** the result-type of the previous step
and the source-type of the next — one checkpoint per gap, shared.

The folded model keeps exactly that sharing:

> **Invariant.** Each path node stores **one** type — the type of the document
> you are standing on **at that node**. A step's *start* type is its own node's
> `.type`; its *end* type is its `.tail`'s `.type`. The boundary type is stored
> once, on the downstream node, and serves both roles.

So a `FieldReference` reads its own node for the start and its tail node for the
end; `evaluate_reference` validates the end-type automatically when the recursion
lands on the tail node. A k-step path has **k+1 typed nodes** (every navigation
boundary plus the terminal) — identical to today's annotated checkpoint count, no
duplication.

Concretely, `entry.value.value{3}` (a `JsonObjectEntry` → … → char offset):

| node | `.type` | `.head` (nav step) |
|---|---|---|
| n0 | `JsonObjectEntry` | `FieldReference("value")` |
| n1 | `JsonString` | `FieldReference("value")` |
| n2 | `String` | `PositionReference(3)` |
| n3 (terminal) | `nothing` | — (`EmptyReferencePath`) |

A `{k}` position is a cursor *between* characters, not a descent into a child, so
it lands on no typed node — the terminal's `.type` is `nothing` (mirrors the
existing `annotate_reference_types` rule that gives a position no child
checkpoint). A whole-element `∅` selection, by contrast, terminates *at* a node,
so its terminal `EmptyReferencePath` records that node's type.

## New data model (kernel: `package/kernel/src/reference/Reference.jl`)

```julia
abstract type ReferencePath end

struct EmptyReferencePath <: ReferencePath
    type::Any            # type of the node the path lands on; `nothing` if a
end                      # cursor/position terminal or unknown-at-build

EmptyReferencePath() = EmptyReferencePath(nothing)

# head is ALWAYS a navigation step (RangeReference / FieldReference /
# PointReference / ProjectionReference / FunctionReference) — never a type.
@document struct ConcreteReferencePath <: ReferencePath
    type::Any            # type of the node here; `nothing` if unknown-at-build
    head::ReferenceStep
    tail::ReferencePath
end
```

- `head`/`tail` stay **reactive Cells** (as today, via `@document` + the manual
  `Cell`-wrapping outer constructor); `type` is a **plain immutable field**
  (types do not change reactively — re-annotation rebuilds the path). Hand-roll
  the outer constructors so only `head`/`tail` are `Cell`-wrapped.
- **`TypeReference` the struct is removed as a path step.** Nothing stores a
  `TypeReference` in `head` anymore; the raw Julia type lives directly in
  `.type`. (Decision below on whether to keep a deprecated alias — recommend
  remove; it is internal-only.)

### The shim that makes this incremental

Two backward-compatible constructors keep all **375** `ConcreteReferencePath(…)`
and **107** `EmptyReferencePath()` call sites compiling untouched:

```julia
ConcreteReferencePath(head::ReferenceStep, tail::ReferencePath) =   # 2-arg
    ConcreteReferencePath(nothing, head, tail)                      # type unknown
```

A node built by a generic two-arg site has `type === nothing`; `evaluate_reference`
and `valid_reference_prefix` **skip the `isa` assertion when `type === nothing`**
(can't validate an unknown type — navigate anyway), so behaviour is identical to
today for every un-annotated path. `annotate_reference_types` fills the `nothing`
types in against a document; the canonical-at-rest pipeline keeps working.

Once `head` can never be a `TypeReference`, redefine the two tolerance helpers as
**identities** so the 184 + 87 call sites keep compiling and behaving correctly
during the migration:

```julia
skip_type_checkpoints(p::ReferencePath) = p   # nothing to skip anymore
strip_reference_types(p::ReferencePath) = p   # types are inert metadata on nodes
```

Then Phases 3–5 delete the now-no-op calls at leisure and finally remove the
shims and their exports. **This is the lever that turns a ~650-site change into a
sequence of individually green commits.**

## Kernel changes (`Reference.jl`)

- [ ] Add `type` field to `EmptyReferencePath` and `ConcreteReferencePath`;
      add the 2-arg/0-arg backward-compatible constructors above. Forbid a
      `TypeReference`/type in `head` (remove the `TypeReference <: ReferenceStep`
      definition).
- [ ] `evaluate_reference(document, path)` — drop the `TypeReference` branch;
      at each `ConcreteReferencePath`, assert `path.type === nothing ||
      document isa path.type` (throw `ReferenceTypeMismatch`), then navigate
      `head`, recurse on `tail`. At an `EmptyReferencePath`, assert its `.type`
      likewise. Net: **one** assertion per node, covering each step's end-type
      via the tail recursion.
- [ ] `valid_reference_prefix` — same fold: a node whose `type` mismatches
      truncates the path *before* that node (return the prefix up to here).
- [ ] `annotate_reference_types(document, path)` — **fill** `.type` on each node
      (set `nothing` → `typeof(node)`), rather than insert checkpoint cons cells.
      Keep the position-is-terminal rule (no child type after `{k}`). The
      `∅`/whole-element case sets the lone terminal's type.
- [ ] `strip_reference_types` — becomes "blank every `.type` to `nothing`"
      (or the identity shim above; pick per call-site need in Phase 3). Keep the
      permissive non-path fallback.
- [ ] `skip_type_checkpoints` — redefine as identity shim, then delete in Phase 5.
- [ ] Equality / `show` / `is_prefix_of`:
      - `Base.show` — render `::Type` from each node's `.type` instead of from a
        `TypeReference` step (keeps the `{{Type}}` printed form).
      - **Decision (recommend):** `==` / `is_prefix_of` compare **navigation
        structure only, ignoring node types** (most equality checks compare a
        stored typed selection against a plain `@reference` skeleton; making
        `==` type-significant would break them). `reference_equal_ignoring_types`
        becomes the same as `==`; add `reference_equal_strict` only if a
        type-sensitive compare is ever needed. `EmptyReferencePath` equality
        ignores `.type` so `∅` matches any-typed terminal.
- [ ] `append_reference`, `ReferencePath(steps...)`, `collect_references`,
      `_search_document` — unaffected structurally (they build nav-step nodes);
      `collect_references` keeps calling `annotate_reference_types` to fill types.
- [ ] Update the module `export` list (drop `TypeReference`; keep
      `skip_type_checkpoints`/`strip_reference_types` exported until Phase 5).

## Macro changes

- [ ] **`@reference` / `@step`** (`ReferenceBuilder.jl`). `BSType`/`_build_*_type!`
      currently emit a standalone `TypeReference(T)` step. Re-target them to set
      the **adjacent node's `.type`**: `field::T` sets the node *after* `field`
      (the result/end node) to `T`; a leading `::T.rest` sets the *root* node's
      type. `_gen_build_path` threads the per-node types when assembling the
      `ConcreteReferencePath` chain. A bare `@reference obj.value` (no `::T`)
      builds `type === nothing` nodes (filled later by `set_selection!`).
- [ ] **`@reference_case`** (`ReferenceCase.jl`). Remove the
      `skip_type_checkpoints(...)` wrappers in `_gen_path_match` /
      `_gen_prefix_match` (lines ~506, 511, 549, 582) — `head` is now always a
      nav step, so matching is direct and the macro gets *simpler*. `PSType`
      (`::T` assertion) changes from `head isa TypeReference && head.type <: T`
      to checking the **current node's `.type <: T`** (the `::T` still being an
      *optional* assertion: a `nothing` type means "unknown", treat as match or
      no-match per the documented rule — recommend: `nothing` type fails a
      `::T` assertion only if the pattern demands a type; otherwise types are
      ignored, preserving today's tolerant matching). `∅` still matches
      `isa EmptyReferencePath` regardless of terminal type.

## Projection / template helpers

- [ ] `ProjectionTemplate.jl` — `_typed(T)`, `_path`, `_prepend`,
      `_strip_checkpoints`, and every `::T`-emitting typed mapper build/inspect
      `TypeReference` steps today (47 skip calls, 103 `.head`/`.tail` reads, 8
      `TypeReference(` here). Rewrite `_typed`/`_path`/`_prepend` to set node
      `.type`; delete `_strip_checkpoints` (now identity); drop the `skip`/`head`
      checkpoint dances in the compound-printer §8 recurse patterns (read
      `input.selection[]`'s `.head` directly).
- [ ] `ObjectToSyntax.jl` and the other typed `::T` doc→syntax mappers — their
      `@reference …::T …` builders now produce typed nodes automatically; remove
      any manual `TypeReference(` construction.

## Consumer cleanup (the 184 `skip_type_checkpoints` + redundant `strip`)

With the identity shims in place this is **mechanical and independently testable
per file**. For each file, replace `skip_type_checkpoints(x)` with `x` and
collapse the resulting `x.head`/`x.tail` reads; delete `strip_reference_types`
calls that existed **only** for tolerance. Group by layer and verify with the
narrowest test after each (see Testing). Heaviest files:

- Navigation / text: `document/Syntax.jl` (13), `document/Text.jl` (7),
  `SyntaxToText.jl`, `TextToGraphics.jl`, `WidgetToGraphics.jl` (16),
  `LayoutToGraphics.jl` (6).
- Doc→syntax: `CollectionToSyntax.jl`, `XmlToSyntax.jl`, `MathToSyntax.jl`,
  `BookToSyntax.jl`, `PrimitiveToSyntax.jl`, `PrimitiveToText.jl`,
  `DbCatalogToSyntax.jl`, `DocumentInsertionToSyntax.jl`,
  `FileSystemToWidget.jl` (9).
- Re-segmentation / higher-order: `WordWrapping.jl`, `TextHighlighting.jl`,
  `TextFiltering.jl`, `TextFirstLine.jl`, `TextToWidget.jl`, `Dragging.jl`,
  `TooltipDecorator.jl`, `ProjectionConfiguring.jl`, generic `Copying.jl`.
- Editor / kernel: `ConversationEditor.jl` (3), `common/Operation.jl` (4),
  `WorkbenchToWidget.jl`, `odbc/ProjecturedOdbc.jl` (6).

- [ ] **`common/Operation.jl`** — the two `strip_reference_types` calls in the
      `ReplaceDocumentOperation` / `StringReplaceRangeOperation` evaluators were
      previously documented as **load-bearing** (normalize a *mutation*
      navigation path so the terminal-slot split sees a plain path). In the
      folded model the path is already navigation-clean structurally; re-verify
      these two specifically — they likely become no-ops (delete) but confirm the
      mutate/replace round-trip selection tests still pass before removing.
      `set_selection!`/`clear_selection!` keep `annotate_reference_types` (now the
      type-filling normalizer); drop their internal `skip_type_checkpoints`.

## Renderers (read `.type` instead of a `TypeReference` step)

- [ ] `ReferenceToText.jl` — `_emit_step_short!(…, ::TypeReference)` and the
      human-readable variant render the `::Type` token. Re-source the type from
      each node's `.type` in `_emit_path_short!` (emit the `::Type` token per
      node before/after its step per the chosen printed shape) instead of from a
      step. `_short_type`, coloring unchanged.
- [ ] `ReferenceInspector.jl` / `ReferenceInspectorToText.jl` — these annotate a
      raw reference to show both plain and typed forms; update to read node
      `.type` (the "typed form" is now intrinsic, no separate annotate needed for
      display).

## Docs & cleanup

- [ ] `documentation/editor/reference.md` — rewrite the "Type checkpoints" and
      "Reference Steps" sections: a type is a **field of every path node**, not a
      `TypeReference` step; `head` is always navigation; the `::T` DSL sets a
      node's type; the `{{Type}}` printed form is per-node. Update worked-example
      paths.
- [ ] `documentation/selection-deep-dive.md` — update the canonical-form
      worked examples (the deferred rewrite from the prior plan).
- [ ] Remove the `skip_type_checkpoints` shim, its export, and (decision) the
      `TypeReference` struct + alias once all call sites are gone. Audit the test
      suite (`TypeReferenceTest.jl` — 6 skip + 3 `TypeReference(` uses) and
      rewrite against the node-`.type` model.
- [ ] Update memory `type-checkpoints-canonical-at-rest`: the
      strip-at-boundary / skip-on-read mechanics it documents are superseded by
      structural per-node types.

## Phasing (each phase ends green)

1. **Kernel + shims** — new structs, folded `evaluate`/`valid`/`annotate`/`strip`,
   identity shims, `show`/equality. Run `test_cell()` + `TypeReferenceTest` +
   `test_json()`. Nothing downstream edited yet; everything compiles via the
   2-arg constructor + identity shims. *Commit.*
2. **Macros** — `@reference`/`@step`/`@reference_case` map `::T` to node types
   and drop internal skips. Re-run the reference tests + `test_json_to_syntax()`.
   *Commit.*
3. **Consumer cleanup** — delete the 184 skip calls + redundant strips, per
   layer, each verified with its narrowest test (`test_<domain>` /
   `test_<stage>` / `test_<example>`). Mechanical batches are
   **Sonnet-subagent-delegable**, but read each diff and run the targeted test
   before relying on it. *Commit per layer.*
4. **Renderers + ProjectionTemplate helpers.** `test_printers`/`test_readers`
   sweep. *Commit.*
5. **Remove shims, `TypeReference` struct, exports; docs; memory.** Full
   `test_all()` sweep once targeted layers are green (see baseline below).
   *Commit; `git mv` plan to `plan/done/`.*

## Testing

Per `CLAUDE.md`, run the **narrowest** test for each change, never default to
`test_all()`:

- Kernel/macros: `test_cell()`, the reference `@testset`s in
  `TypeReferenceTest.jl`, `test_json()`.
- Each consumer layer: `test_<domain>()` / `test_<stage>()` (e.g.
  `test_syntax_to_text()`, `test_json_to_syntax()`) or single example
  (`test_example(json_example)`), plus `test_text_navigation(<ex>;
  check_reaches_all=true)` for navigation-touching files.
- Broad sweep (`test_printers()`/`test_readers()`/`test_repls()`/`test_all()`)
  only at phase boundaries, after the targeted tests pass. Compare against the
  known-green baseline (memory `test-suite-green-baseline`: ~13 pre-existing
  failures by design) — **target zero new regressions**, matching the prior
  `type-reference-everywhere` outcome.

## Risks / open decisions

- **Equality default flip** (`==` ignoring node types) — verify no selection
  round-trip / dedup test depends on type-significant `==`. *Recommend the flip;
  add `reference_equal_strict` only if something needs it.*
- **`type === nothing` semantics** — a node may legitimately have an unknown type
  (generic two-arg construction, plain skeleton). `evaluate`/`valid` skip the
  assertion; `::T` patterns must decide nothing = "no assertion". Document the
  rule once and apply uniformly.
- **`ProjectionReference.output_path`** is itself a `ReferencePath` and folds
  automatically — confirm nested output paths annotate/strip/render correctly.
- **Reactive `type` field** — keeping `type` non-reactive while `head`/`tail`
  stay `Cell`s requires a hand-written outer constructor; verify `@document`'s
  generated inner constructor cooperates (it currently wraps every field).
- **Performance** — unchanged from the prior plan: `annotate` walks the document
  per `set_selection!`; folding removes the extra checkpoint cons allocations
  (fewer nodes), a mild win. Measure only if a hot path shows up.
- **Blast radius** — 184 skip + 87 strip + 375 `ConcreteReferencePath(` + 107
  `EmptyReferencePath()` sites. The shim strategy contains the risk; the only
  *semantically* tricky edits are the macros, `ProjectionTemplate.jl`, and the
  two `Operation.jl` strips.

---

## Implementation outcome (2026-06-25)

Landed on branch `eliminate-skip-type-checkpoints` in six incremental, individually
green commits. `skip_type_checkpoints` is **gone**; a node's type is a mandatory
structural field.

### As-built design

- **Data model** (`kernel/.../Reference.jl`). `ConcreteReferencePath` gained a
  `type::Any` field (`type, head, tail`); `EmptyReferencePath` gained `type::Any`
  (the terminal node's type). Backward-compatible constructors default `type` to
  `nothing`, so all ~375 `ConcreteReferencePath(...)` / ~107 `EmptyReferencePath()`
  sites compiled untouched. `head` is **always a navigation step**.
- **Boundary-type sharing** (resolves the "two checkpoints per FieldReference?"
  question): each node stores **one** type — the node it stands on. A step's start
  type is its node's `type`, its end type is its `tail`'s `type`; the boundary type
  lives once on the downstream node. `evaluate_reference` validates the end type
  when the recursion lands on the tail. k steps → k+1 typed nodes.
- **`annotate_reference_types`** fills node `type` fields (no longer inserts
  checkpoint cons); **`strip_reference_types`** blanks them; **`evaluate_reference`
  / `valid_reference_prefix`** assert per node; **`show`** prints `::Type` per node.
- **Equality kept STRICT** over the `type` fields (matching the existing codebase
  contract), *not* flipped to ignoring as the draft's §"Decision" suggested — this
  was lower-risk and made the existing `strip != canonical` tests pass.
  `reference_equal_ignoring_types` / `is_prefix_of_ignoring_types` (strip-then-`==`)
  remain for cross-form comparison; the matcher uses them.
- **Macros.** `@reference ::T` still *builds* `TypeReference` steps, then a new
  `fold_reference_types` runtime pass folds them into node types (wrapped in only
  when a `::T` is present, so plain skeletons stay allocation-free).
  `@reference_case`'s `::T` reads the folded node `.type` (optional assertion:
  `nothing` matches), with the transitional flat-step form still accepted.
- **ProjectionTemplate.** `_typed(T) = EmptyReferencePath(T)`; `_path`/`_prepend`
  fold the checkpoint steps their callers pass; `_strip_checkpoints` delegates to
  `strip_reference_types`. This was the last producer of interleaved checkpoint
  steps, which made `skip_type_checkpoints` **provably the identity** on every
  consumed path.
- **Elimination.** With skip provably identity, a balanced-paren script replaced
  all 135 `skip_type_checkpoints(X)` → `X`; the function, its export, the 4 matcher
  wrappers, and ~30 import mentions were removed.
- **Renderer.** The compact `ReferenceToText` now emits each node's `::Type` (it
  used to render the interleaved `TypeReference` step); the human-readable form was
  unaffected (it derives types via `evaluate_reference`).

### Deviation from the draft

- **`strip_reference_types` was kept** (not eliminated): it is load-bearing at the
  `set_selection!` annotate boundary and at the JSON input boundary. Only the
  consumer-*tolerance* role went away. This narrowed scope and risk; the user's
  explicit goal was `skip_type_checkpoints`.
- **`TypeReference` the struct is kept** as an internal **build-time token** (DSL
  + ProjectionTemplate emit it, `fold_reference_types` immediately folds it). It
  never appears as a step in a stored/consumed path. Building folded nodes directly
  and deleting the struct + the harmless transitional tolerance branches is a small
  optional follow-up.
- **Equality stayed strict** rather than flipping to type-ignoring (see above).

### Phase checklist (as executed)

- [x] **1** Struct prep — add `type` fields + back-compat constructors (commit 1).
- [x] **2** Fold annotate/evaluate/valid/strip/show/`==` (commit 2).
- [x] **3** `@reference`/`@reference_case` speak folded node types (commit 3).
- [x] **4** Fold `ProjectionTemplate` output (commit 4).
- [x] **5** Eliminate `skip_type_checkpoints` — calls, function, export, imports (commit 5).
- [x] **6** Render folded node types in the compact renderer (commit 6); docs.

### Regressions found by the full sweep + fixed

The base-commit `test_all` diff surfaced one real regression (navigator
click-on-file repl, +3), traced to the fold removing the leading `TypeReference`
*step* that had incidentally acted as a cross-domain tripwire. Two fixes (commit
`fix(fold)`):

1. **`_selection_child` (kernel `Operation.jl`)** did a raw `getfield(document,
   name)` with **no `hasproperty` guard** — unlike its siblings
   `set_selection!`/`clear_selection!`. A filesystem `.elements[…]` selection with
   no Workspace pre-image used to be deflected because the leading `TypeReference`
   step kept `head` from being a `FieldReference`; folded, `head` is the nav step,
   so `getfield(Workspace, :elements)` threw `FieldError`. Added the matching
   graceful guard.
2. **`@reference_case ::T`** had been made an *enforcing* `<: T` gate in the macro
   commit, which wrongly rejects re-rooted child selections whose folded node type
   differs from the documented one. Restored to the documented **optional/tolerant**
   semantics (a `::T` never fails a match), in both the path and prefix matchers.

### Test status

**Full `test_all`: 230705 pass / 158 fail / 3 error — vs the base-commit
(`d6c1ea5`) baseline of 165 fail / 3 error.** Every failing location is a strict
subset of the baseline's (same or fewer), the 3 errors are identical
(CollapseRoundtrip / DirtyRect / McpTest, pre-existing), and the branch
incidentally **fixes 7 pre-existing failures** (`ReplTest:87` ×5,
`SqlToSyntax:113`, `JsonToSyntax:122`) — **zero regressions introduced.** (The 455
`graph_adaptagrams` failures seen in a fresh worktree are purely the gitignored
native `.so` being absent; copying it in makes `graph` 4668/4668 + 225/225 pass.)

Green: `test_cell`, `test_reference_builder` 22/22,
`test_type_reference` 36/36 (updated to folded shapes), `test_json` /
`test_syntax`, `JsonToSyntax` fwd 11/11 + reader 48/48, all `SyntaxToText`,
`PrimitiveToText`, `TextToGraphics`, `WordWrapping`/`TextFiltering`/
`TextHighlighting`/`SelectionInverting`, `ObjectToWidget`/`SyntaxToWidget`/
`FileSystemToWidget`, `Tooltip`/`Dragging`/`ProjectionConfiguring`,
`Copying`/`ClipboardToAny`/`VersioningToAny`, `XmlToSyntax` fwd+reader,
`DbCatalogSql`, `ConversationEditor`, `ReferenceInspectorToText` 9/9, `HoverProbe`,
`json` text-navigation 543/543 reaches-all. The `xml` reaches-all `1490/5` matches
the **pre-existing** baseline on `d6c1ea5` (verified) — not a regression.
