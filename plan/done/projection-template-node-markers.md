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

- [x] **Step 0 — land the 22 done conversions.** ✅ Committed on `main` (a764d51)
  before this plan; the worktree branches from it.

- [x] **Step 1 — F3 (project override).** ✅ `project(:f; as=…)` where `as` is a
  projection *or* a per-value thunk `v -> proj|nothing`; shared `_project_child_cell`
  used by fixed/mixed print. (Landed together with F1 in commit 962bc36.)

- [x] **Step 2 — F1 (nested sub-node), engine.** ✅ `SubNodeSlot` + detection
  (`_is_marker_bearing_subnode`) + `_dispatch_print` (factored from `rule_print`) +
  the SubNodeSlot cases in the fixed mappers and `_focused_child`. Applied to
  `_fixed_print` (Julia needs it there); `_mixed_print` left for a later need.
  Commit 962bc36. (Engine unit test in `ProjectionTemplateTest.jl` — see "deferred".)

- [x] **Step 3 — F1 apply to Julia.** ✅ Index, While, If, Lambda, For, Function.
  Printer byte-identical (1725/0), reader 225/0, nav 3/0, `check_reaches_all` 4/28.
  Commit 962bc36.

- [x] **Step 4 — F2 (reactive conditional children), engine.** ✅
  `ConditionalNodeWiring` + `_conditional_print` (reactive state cell, modeled on
  `_sections_print`) + `_find_conditional` (a `Function` in a field) + shared
  `_walk_markers` / `_slots_forward` / `_slots_backward` factored from `_fixed_*`.

- [x] **Step 5 — F2 apply to Julia.** ✅ Range, Return, Try (Try's `catch <var>` is
  a nested sub-node, F1+F2).

- [x] **Step 6 — F3 apply to Julia.** ✅ Call (`project(:callee; as = v -> v isa
  JuliaIdentifier ? … : nothing)` + `(args)` collection sub-node). **32/32**
  macro-based; all hand-written `projection_print` deleted; imports trimmed;
  "Reference mapping & readers" comment rewritten. (Steps 4–6 in the F2+F3 commit.)

- [ ] **Step 7 (cross-domain — HANDED OFF).** Not done here. The features are proven,
  so [projection-template-engine.md](projection-template-engine.md) Stage B (SQL) is
  now unblocked: clause headers via F1, optional `DISTINCT`/`WHERE`/columns via F2,
  the callee-style override via F3. Left as a follow-up in that plan.

## Implementation notes (as-built)

- **F1 wiring is "delegate the whole reference, prepend one `.children[k]`".** A
  `SubNodeSlot` embeds the nested `RuleIoMap` (built with the *parent* doc/ctx, since
  the sub-node's `project`/`collection` children key off parent input fields). The
  fixed forward mapper hands the whole parent reference to the sub-node's mapper —
  which claims only the fields it actually contains (returns `nothing` otherwise) —
  and prepends `.children[k]` on a hit; backward hands the sub-node-relative tail and
  returns the result unchanged (already parent-relative). Nesting is uniform and
  unbounded (Function/For nest a collection *inside* a header — two SubNodeSlot levels).
- **The checkpoint mix was a non-issue.** A plain-prefixed `.children[k]` in front of
  a *checkpointed* inner collection path (Function/For/Lambda/Index) round-trips fine —
  printer stayed 1725/0 and json nav_complete 543/543. No checkpoint normalization was
  needed at the SubNodeSlot boundary.
- **Per-sub-node selection cells are fine.** Each nested sub-node carries its own
  forward-mapped selection cell (unlike the old hand-written header nodes, which had
  none). The top and sub-node cells are consistent (top = sub prefixed by `.children[k]`),
  so the renderer descends correctly — mirroring JSON's nested pair-node cells.
- **F2 detection = a `Function` in a node field.** Only the 7-arg positional
  `SyntaxNode(open, close, sep, thunk, …)` stores an unevaluated thunk (the keyword
  `children=` ctor turns a `Function` into an output CellVector). `_find_conditional`
  runs first in `_dispatch_print`; no false positives (leaves hold TextStrings,
  collection/tokens/sections hold markers).
- **F2 reactivity is correct but not locality-optimal.** The state cell re-walks the
  marker vector whenever the thunk's structural dependencies change (`r.step`,
  `r.value`, `t.catch_branch`, …), which *rebuilds every project child* of that node
  (a fresh `_project_child_cell` each time) rather than reconciling them across the
  toggle. Correct (child *content* changes still propagate via the output-cell deref
  without a state recompute); the only cost is that toggling an optional field
  re-projects the node's other children. Acceptable for Range/Return/Try (few children,
  rare toggles); a reconciling `_walk_markers` is a possible future optimization.
- **F3 is printer-only, as predicted.** Wiring/mappers unchanged; the override only
  changes which projection builds the ProjectSlot's child iomap. `_project_child_cell`
  must call `ProjectionApiModule.projection_print` (qualified — the module doesn't
  import bare `projection_print`).

## Design risks — resolved

- **Reference mapping (the hard part):** resolved — the slot-tree bookkeeping worked;
  gates green across JSON/SQL/Julia. Engine *unit* coverage in `ProjectionTemplateTest.jl`
  was **deferred** (validated through the JSON/SQL/Julia domain gates instead); a
  focused two-level-nesting + optional-toggle unit test is a nice-to-have follow-up.
- **F2 reactivity vs. reconciliation:** the domain gates exercise the *static* shapes
  only; in-place optional-field toggle isn't covered by a test (see the locality note
  above). Left as a follow-up alongside the unit test.
- **Byte-identical output:** confirmed — printer 1725/0 unchanged at every step.
- **`check_reaches_all` floor:** held at 4/28. F1 shifted *which* leaf-content carets
  are enumerated (School-A now descends into `Function` etc., exposing `.name.name{k}`)
  but not the count; those remain owned by julia-syntax-navigation.md.

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

- [x] All three features (F1, F2, F3) live in `ProjectionTemplate.jl` as generic
  markers + wiring + mapper cases; no Julia/SQL coupling. *(Engine unit coverage
  deferred — validated via domain gates; see "Design risks — resolved".)*
- [x] `JuliaToSyntax` is **32/32** macro-based; every hand-written `projection_print`
  removed; imports trimmed. Net reduction well beyond the earlier −105.
- [x] All `julia_example` gates unchanged from baseline; JSON and SQL suites unchanged
  (json_to_syntax 11/0, json nav_complete 543/543, sql_to_syntax 19/0, julia printer
  1725/0, reader 225/0, nav 3/0, nav_complete 4/28).
- [x] Stage B of projection-template-engine.md is unblocked (Step 7 handed off with
  the features proven).

**Status: complete** (Step 7 SQL conversion handed off). Ready to move to `plan/done/`.
