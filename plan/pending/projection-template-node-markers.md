# `@projection_template` — general node markers (nested sub-nodes, conditional children, project override)

**Origin:** Follow-up to the JuliaToSyntax macro refactor (2026-07-01), which
converted 22 of 32 `JuliaToSyntax` projections to `@projection_template` and left
10 hand-written because the template's node forms can't express them. This plan
adds the **general, domain-neutral** engine features that unblock those 10 — and,
by the same tokens, the still-open SQL node conversions.

**Relationship to existing plans:**
- [projection-template-engine.md](projection-template-engine.md) — the engine
  itself (done for JSON). Its **Stage B** (SQL fixed/conditional nodes) and
  **Stage C** (sweep `XToSyntax`, incl. Julia) are OPEN and depend on exactly the
  features below. This plan is the concrete driver for those features; completing
  it lets Stage B/C proceed mechanically.
- [julia-syntax-navigation.md](julia-syntax-navigation.md) — the *separate*
  `bound`-leaf + `_syntax_to_flat` work that would make a cursor descend into leaf
  *text*. Out of scope here (see "Interaction / out of scope").

## Current state

`JuliaToSyntax` after the refactor (working tree):

- **22 converted** — 10 leaves (opaque atomic), 3 `collection` nodes (Tuple, Array,
  Block), 8 flat fixed-children nodes (BinaryOp, UnaryOp, Ternary, FieldAccess,
  TypeAnnotation, Assignment, ForIterator, Begin), 1 all-introduced node (Using).
- **10 hand-written** — each blocked by a shape the template can't express:

| Node | Blocking shape | Feature needed |
|---|---|---|
| Index | recursive child inside a `[indices]` bracket sub-node | **F1** |
| While | `project(:condition)` inside a `while …` header sub-node | **F1** |
| If | `project(:condition)` inside an `if …` header sub-node | **F1** |
| Lambda | `collection(:parameters)` inside a `(params)` sub-node | **F1** |
| For | `collection(:iterators)` inside a `for …` header sub-node | **F1** |
| Function | `project(:name)` + `collection(:params)` inside a header sub-node | **F1** |
| Range | child list depends on optional `step` | **F2** |
| Return | child list depends on optional `value` | **F2** |
| Try | optional `catch`/`catch var`/`finally` + a `catch <var>` header sub-node | **F1 + F2** |
| Call | nested `(args)` sub-node **and** callee must render in the function-name color | **F1 + F3** |

The engine is deliberately output-domain-neutral ("fields classified by value; no
output type or field named; nothing generated per type"). All three features below
extend it *in that same style* — new markers + new wiring variants + new generic
mapper cases — with **no per-type codegen** and **no Julia coupling**. Two of them
(F1, F2) are generalizations of mechanisms the engine already has.

---

## Feature F1 — nested sub-node marker

**What:** allow a child in a fixed-children node to be *itself* a marker-bearing
`SyntaxNode` (a header/bracket grouping that has no input pre-image but contains
further `project`/`collection`/leaf children referring to the **parent** doc), and
have the walk recurse into it instead of treating it as opaque (`IntroSlot`).

**Why general:** the engine already walks a marker-bearing node in one place — the
`collection(:f) do e … end` element builder (`_fixed_print`). F1 lifts the "one
level, collection-element only" cap to arbitrary nesting at any fixed-child
position. Every domain with structural grouping benefits (SQL clause headers, XML
nested elements, Lisp forms).

**Design:**
- Slot vocabulary gains `SubNodeSlot(children_field, slots, store)` — the slot
  tree becomes a *tree*, not a flat list. A sub-node is **output-only**: its
  `project`/`collection` children key off parent input fields, but sit one (or
  more) `.children[k]` hops deeper in the output.
- `_fixed_print` (and `_mixed_print`): when a child is a built `SyntaxNode` whose
  children vector contains markers, recurse — record a `SubNodeSlot` carrying the
  nested slots + a store of the nested child iomaps (keyed by parent input field).
- Generic mappers gain a recursive case:
  - forward: match a parent input field against the slot tree; on a hit inside a
    `SubNodeSlot` chain, prepend each `.children[k]` hop.
  - backward: a `.children[k].children[j]…` path descends the slot tree.
- `_focused_child` (reader): a `ProjectSlot`/collection reached *through* a
  `SubNodeSlot` still yields the child iomap + the parent input step(s).

**Unblocks (faithfully):** Index, While, If, Lambda, For, Function (6).

**Example — `While`:**
```julia
@projection_template JuliaWhileToSyntaxNode JuliaWhile (p, w) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(TextString(""), TextString(""), TextString(""),      # nested header — walked
              [ SyntaxLeaf(TextString("while", p.keyword);
                           close=TextString(" ", p.keyword.font, color_default)),
                project(:condition) ],
              0, false, nothing),
          project(:body),
          SyntaxLeaf(TextString("end", p.keyword)) ],
        0, false, nothing)
```
Wires `.condition ↔ .children[1].children[2]`. `Function` is the same with a
`project(:name)` **and** a `collection(:params)` nested in the header.

---

## Feature F2 — reactive conditional children

**What:** let the children argument be a **thunk returning a marker vector**,
re-run reactively, so optional fields appear/disappear and the wiring tracks the
current shape.

**Why general (and why a thunk, not a static `if`):** the engine already has two
*restricted* reactive-marker forms — `tokens(thunk)` (variable-length **leaf**
vector, one bound token) and `sections(specs)` (dynamic per-field sub-collections).
F2 generalizes them to a reactive vector of **arbitrary** markers
(`project`/`collection`/leaf). A purely *static* conditional builder (ordinary
`if`/`push!`, as [projection-template-engine.md](projection-template-engine.md)
Stage B assumes) records positions correctly for one print, **but** the current
hand-written Range/Return/Try build their children with `CellVector(() -> …)` and
so re-render when an optional field toggles *in place* (same object, mutated
`.value`/`.step`) — a reconciling parent reuses that child iomap by `objectid` and
never re-invokes `projection_print`, so a static slot list would go stale. F2
preserves that reactivity; it's the faithful form.

**Design:**
- Detect a thunk in the children position of `SyntaxNode(...)` (distinct from the
  existing homogeneous `collection` thunk, which yields *outputs* not markers).
- Model on `_inline_print`/`_sections_print`: store the walked (slots +
  child_iomaps) in a `Cell` recomputed each structural change; strip markers per
  recompute. New `ConditionalNodeWiring` whose mappers read the *current* slot list
  from the stored cell (exactly as `_sections_forward` reads `iomap.child_iomaps[]`).
- Reuse the F1 slot tree so a conditional branch may itself contain a sub-node
  (needed by Try's `catch <var>` header).

**Unblocks (faithfully):** Range, Return, Try (with F1) (3).

**Example — `Range`:**
```julia
@projection_template JuliaRangeToSyntaxNode JuliaRange (p, r) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        () -> r.step === nothing ?
            [ project(:start), SyntaxLeaf(TextString(":", p.op)), project(:stop) ] :
            [ project(:start), SyntaxLeaf(TextString(":", p.op)),
              project(:step),  SyntaxLeaf(TextString(":", p.op)), project(:stop) ],
        0, false, nothing)
```

---

## Feature F3 — `project` with a projection override

**What:** `project(:field; as = some_projection)` — delegate the child, but through
a supplied projection instead of the recursion's type-dispatcher.

**Why general, and smallest:** a routing/decoration hook. Only the **printer**
changes — build the ProjectSlot's child iomap with
`projection_print(as, recursion, v, ctx)` instead of
`projection_printer_recurse(recursion, v, ctx)`. Wiring and mappers are unchanged
(they delegate through the stored child iomap regardless of which projection built
it). No new wiring type, no mapper case.

**Unblocks:** Call (with F1) — the callee must render in the function-name blue,
which plain `project(:callee)` (type-dispatched → variable violet) can't do.

**Example — `Call`:**
```julia
@projection_template JuliaCallToSyntaxNode JuliaCall (p, c) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ project(:callee; as = JuliaIdentifierToSyntaxLeaf(p.callee)),
          SyntaxNode(collection(:arguments);
                     open=TextString("(", p.delim), close=TextString(")", p.delim),
                     sep=TextString(", ", p.delim)) ],
        0, false, nothing)
```

---

## Plan of work (incremental; commit + gate per step)

Per repo conventions: work in a dedicated git worktree, mark each step done here as
it lands, commit per step. **Native-artifact caveat** (from prior experience):
`ProjecturedAdaptagrams` etc. ship gitignored `.so` files, so build/test in a
checkout that has them (or copy them in) — a bare worktree yields phantom failures.

- [ ] **Step 0 — land the 22 done conversions.** Commit the current
  behavior-preserving JuliaToSyntax refactor (already in the working tree). Gate:
  `test_printer/reader/text_navigation(julia_example)` unchanged from baseline
  (1725/0, 225/0, 3/0; `check_reaches_all` 4/28 — the 28 are the deferred
  leaf-content carets, see julia-syntax-navigation.md).

- [ ] **Step 1 — F3 (project override).** Printer-only change + the marker builder
  `project(:f; as=…)`. Smallest, self-contained warm-up. No node converts yet
  (Call also needs F1), so gate = engine tests + JSON/SQL leaf regressions green.

- [ ] **Step 2 — F1 (nested sub-node), engine.** Slot tree + `SubNodeSlot`, the
  recursive walk in `_fixed_print`/`_mixed_print`, recursive forward/backward mapper
  cases, `_focused_child` through a sub-node. Add engine unit coverage
  (`ProjectionTemplateTest.jl`) for a two-level nested node. Gate: JSON + SQL
  suites unchanged.

- [ ] **Step 3 — F1 apply to Julia.** Convert Index, While, If, Lambda, For,
  Function. Gate: `test_example(julia_example)` — printer tree byte-identical, nav
  unchanged; `check_reaches_all` no worse than 4/28.

- [ ] **Step 4 — F2 (reactive conditional children), engine.** `ConditionalNodeWiring`
  modeled on `_inline_print`/`_sections_print`, reusing the Step-2 slot tree. Engine
  unit coverage for an optional-field toggle (assert re-render on in-place mutation).
  Gate: JSON + SQL unchanged.

- [ ] **Step 5 — F2 apply to Julia.** Convert Range, Return, Try (Try uses the
  Step-2 sub-node for its `catch <var>` header). Gate as Step 3.

- [ ] **Step 6 — F3 apply to Julia.** Convert Call. Result: **32/32** JuliaToSyntax
  projections macro-based; delete the remaining hand-written `projection_print`s.
  Update the in-file "Reference mapping & readers" comment.

- [ ] **Step 7 (cross-domain, optional / hand off to Stage B).** Re-point
  [projection-template-engine.md](projection-template-engine.md) Stage B: SQL's
  hand-written nodes are now expressible — clause headers via F1, optional
  `DISTINCT`/`WHERE` via F2. Convert `SqlComparison`, `SqlNot`, the clauses, and the
  statements; delete the `body_idx = distinct ? 3 : 2` arithmetic. Gate:
  `test_sql_to_syntax`, `test_sql_to_syntax_selection`, DDL suites unchanged.

## Design risks / open questions

- **Reference mapping is the hard part** (not the walk). Every new shape must peel
  exactly the steps it owns and delegate the rest through the stored child iomaps
  (School A), and get folded-vs-clean path handling right (the collection mapper
  strips `TypeReference` checkpoints at the boundary). The F1 slot *tree* multiplies
  the path-prefix bookkeeping — this is where bugs will hide. Mitigate with engine
  unit tests before touching any real domain.
- **F2 reactivity vs. reconciliation.** Confirm the recomputed slot cell interacts
  correctly with the parent's `_reconciling_child_iomap(s)` — an optional field
  toggling in place must re-render without orphaning stable siblings. Test both
  in-place toggle and wholesale replacement.
- **Byte-identical output.** These conversions must not change the rendered syntax
  tree (printer tests compare structure). Watch header sub-node `sep`/`open`/`close`
  and the space-carrying introduced leaves — reproduce them exactly.
- **`check_reaches_all` is a floor, not a target.** The 28 unreached carets are
  leaf-*content* positions owned by julia-syntax-navigation.md; F1/F2/F3 are about
  *structural* mapping and should leave that count unchanged (they may even improve
  it via School-A delegation, but that's a bonus, not a requirement).

## Interaction / out of scope

- **`bound` leaf editability** (identifier/number/string cursor into text) and the
  `_syntax_to_flat` structural traversal remain in
  [julia-syntax-navigation.md](julia-syntax-navigation.md). They are orthogonal:
  this plan makes the *nodes* macro-based; that plan makes the *leaves* editable.
  Doing both would retire the 28 unreached carets, but neither strictly needs the
  other.
- Authoring readers (keystroke → new document) stay hand-written, as in the engine
  plan.

## Done criteria

- All three features (F1, F2, F3) live in `ProjectionTemplate.jl` as generic
  markers + wiring + mapper cases, with engine unit coverage; no Julia/SQL coupling.
- `JuliaToSyntax` is **32/32** macro-based; every hand-written `projection_print`
  removed; net line reduction on top of the current −105.
- All `julia_example` gates unchanged from baseline; JSON and SQL suites unchanged.
- Stage B of projection-template-engine.md is unblocked (Step 7 either landed or
  handed off with the features proven).
