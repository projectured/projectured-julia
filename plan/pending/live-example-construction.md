# Live example construction test

A new end-to-end test that **rebuilds each example document from an empty seed using only the
editor's own gestures**, then asserts the reconstruction deeply equals the original example.

## The property this asserts

Existing tests prove single stages:
- `test_printer` — document → text is correct.
- `test_reader` — text → document inverts.

This proves the thing nothing else does: **the interactive authoring path exists and is correct
for every example** — `gesture → binding → operation → apply`, iterated over a whole tree,
including placeholder/insertion swaps, sequence growth, and selection placement. It is a
*reachability* proof: every document in the example corpus is constructible through the editor's
own affordances, starting from nothing.

A failure is diagnostic, not just red:
- **no recipe found for a kind** → an editor authoring gap (or a genuinely non-compositional path),
- **recipe produces the wrong shape** → a reader/operation bug,
- **leaf typed but re-parses differently** → printer/reader non-inversion,
- **final deep-compare mismatch at path P** → a precisely-located content regression.

## Why it is not a deep search (the core design fact)

"From nothing to document D by gestures" looks like an exponential search (`Bᴰ`). It isn't, because
**D is fully materialized** — we transcribe a known goal, we don't discover an unknown one. Two
mechanisms collapse the space:

1. **The target tree decomposes depth-D search into D depth-1 decisions.** We recurse over the
   *target's* structure; each node's kind and children are read straight off the target. The shape
   of the edit sequence is dictated, never searched. Subproblems are independent because the
   document is a tree of independent placeholders and editor operations are local — building
   sibling 1 cannot invalidate sibling 2, filling a child cannot break its parent.
2. **Each local decision is decidable in one ply.** At a node, the applicable gestures are already
   filtered to a small legal menu (`get_applicable_gesture_bindings`), and *what to type is always a
   lookup keyed by the target* — a value leaf's keystrokes are its printed surface, a structural
   kind's commit-string comes from reflection. We pick the one legal recipe whose result type
   matches the target's type.

Complexity: `O(N · B_local)`, and with recipe caching by `(context-kind, goal-kind)` it is
effectively `O(N)` after warmup — linear in document size. The only residual search is the bounded
fallback in Phase 5 (a stuck node → depth ≤3 local probe) and gesture-navigation mode (finite BFS
over the selection graph); neither is exponential.

## Architecture — three engines

- **Planner** (generic): recurse over the target; emit "make kind K here" / "type this leaf" /
  "grow this sequence". No domain knowledge.
- **Action model** (probe-and-learn, cached): turn "make kind K" into a concrete recipe by
  inspecting the `Operation` each applicable binding would produce. Domain-agnostic.
- **Oracle** (the one new primitive): recursive content-equality, reports first-mismatch path,
  ignores selection/cell identity.

### Recipe = gesture *sequence*, and print-then-type

The atom is a short **recipe**, not a single gesture, because insertion domains commit via
`Insert → type name → Enter`. But *what to type is never searched*:
- **Value leaves** (number, string, identifier): keystrokes = `printer_surface(target_node)`. The
  reader disambiguates by content (`123` vs `"x"` vs `true`). Uniform across domains.
- **Structural / insertion kinds** (Julia): the commit-string for kind K comes from
  `insertion_candidates(root)` + `make_insertion_document` — a `kind → string` table built once by
  reflection, then looked up. Not probed by trial.

So: structural skeleton from learned recipes; every text leaf from print-then-type; only non-text
leaves (a boolean toggle, a color swatch) need a per-kind gesture — the flagged fallback.

### Classifying a candidate recipe without cloning

`GestureBinding.operation :: (document, event) -> Operation | Nothing` *builds* an op without
applying it. Most creation ops are `ReplaceSelectionOperation(path, replacement)`, so the resulting
kind is `typeof(replacement)` — **classify by inspecting the op payload, no clone/apply needed** in
the common case. Fall back to apply-on-a-scratch-doc only for ops whose result type isn't evident
from the payload. This keeps probing side-effect-free and cheap.

## Load-bearing APIs — verified (2 exist, 1 to build)

| Need | Status | Hook (with location) |
|---|---|---|
| Enumerate gestures at a state | ✅ exists | `collect_gesture_bindings(proj, recursion, iomap)` [`projection/GestureBindings.jl:54`], filter via `get_applicable_gesture_bindings(bindings, doc, sel)` [`binding/GestureBinding.jl:230`]; descriptor `GestureBinding{pattern, operation, applicable, description, domain}` [`binding/GestureBinding.jl:60`] |
| Empty seed | ✅ exists | `@domain` generates `XNothing`/`XInsertion` [`base/main/document/Domain.jl:488`]; e.g. `JuliaNothing()` [`domain/main/julia/Julia.jl:74`]; `insertion_candidates` / `make_insertion_document` / `resolve_insertion` [`Domain.jl:213,128,320`] |
| Drive keystrokes headless | ✅ exists | `read_intent(proj, iomap, ev)` → `evaluate_operation((document=doc,), op)` → `print_document`; manual loop in [`documentation/debugging.md:87`]; events `KeyPress`/`KeyDown` [`event/KeyboardEvent.jl:24`], `Modifiers` [`event/Modifiers.jl:17`] |
| Place selection by path | ✅ exists | `set_selection!(doc, @reference(doc, …))` [`selection/Selection.jl:75`, `reference/ReferenceBuilder.jl:174`]; enumerate sites `collect_tree_selections` / `collect_position_selections` [`base/test/document/SelectionEnumeration.jl:130,100`] |
| Recursive content-equality | ⚠️ **build** | *No* `Base.==` on `@document` nodes — they compare by identity. New generic oracle (below). |

## The oracle (the only new primitive)

`@document` nodes expose fields via `getproperty` (unwraps cells) and `propertynames`; the last
field is always `:selection` (transient — skip it).

```
function assert_equal_content(a, b, path=ROOT):
    typeof(a) == typeof(b)                     || fail_at(path, "kind", a, b)
    for name in propertynames(b):
        name == :selection && continue          # skip transient editor state
        av, bv = getproperty(a,name), getproperty(b,name)   # cells auto-unwrapped
        if bv isa Document:      assert_equal_content(av, bv, path*name)
        elseif bv isa AbstractVector:
            length(av) == length(bv) || fail_at(path*name, "arity")
            for i in eachindex(bv): assert_equal_content(av[i], bv[i], path*[i])
        else:                    av == bv || fail_at(path*name, "value", av, bv)
```

Generic over every domain; localises the first mismatch; content-only.

## Algorithm (final, real names)

```
test_construct(example):
    target = example.document                       # built eagerly by Example ctor
    doc    = nothing_document(root_type_of(target))()   # e.g. JuliaNothing()
    proj   = example.projection
    model  = RecipeCache()
    construct(doc, proj, model, ROOT, target)
    assert_equal_content(doc, target)

construct(doc, proj, model, path, tgt):
    set_selection!(doc, @reference(doc, path))      # ∅ whole-element caret at path
    if is_leaf(tgt):
        replay(doc, proj, printer_surface(tgt)); return
    replay(doc, proj, choose_recipe(model, ctx(doc,proj,path), MAKE_KIND(typeof(tgt))))
    for (i, child) in enumerate(children_of(tgt)):
        grow_if_needed(doc, proj, model, path, i)   # learned INSERT_ELEMENT recipe
        construct(doc, proj, model, path*[i], child)

choose_recipe(model, ctx, goal):                    # cached by (ctx.kind, goal)
    for b in get_applicable_gesture_bindings(collect_gesture_bindings(ctx.proj,nothing,ctx.iomap), ctx.doc, ctx.sel):
        op = b.operation(ctx.doc, synth_event(b.pattern))    # builds, does not apply
        op !== nothing && classify(op) == goal && return [b]
    fail("no recipe for $goal at $(ctx.kind) — editor authoring gap")
```

- `replay` feeds each event through the *real* `read_intent → evaluate_operation` path (the genuine
  binding path is what's under test).
- `synth_event(pattern)` builds an event from `pattern.fields` + `pattern.modifiers`.
- `classify(op)` inspects the op payload (`typeof(op.replacement)` for `ReplaceSelectionOperation`).

## Where it lives

Generic engine + oracle in a new `package/kernel/test/editor/ConstructTest.jl` (kernel-tier, so it
works for any `Example`, mirroring how `test_repl` is defined in `ReplTest.jl` with an `Example`
overload). Domain-tier callers (`test_construct(json_example)`, …) sit in `package/domain/test/`.
Run everything under the memory cap (see the `julia-tests-need-memory-cap` convention) and bound
`replay` length, since a runaway reader would otherwise eat RAM.

## Phases (commit per phase; worktree `projectured-julia-construct`, branch `live-example-construction`)

- [ ] **Phase 0 — Oracle.** Implement `assert_equal_content` + `fail_at` (path-carrying). Unit-check:
  example vs itself passes; example vs a one-field mutation fails at the right path. Standalone, no
  editor. *Commit.*
- [ ] **Phase 1 — Leaf reconstruction.** Seed `XNothing()` → `set_selection!` ∅ → `replay(printer_surface(tgt))`
  → oracle, on the simplest atoms (`json/number`, `json/string`). Exercises seed + placement +
  replay driver + oracle + leaf path. *Commit.*
- [ ] **Phase 2 — Structural recipes (JSON).** Implement `choose_recipe` (enumerate → op-inspect →
  classify → cache) and `grow_if_needed` for sequences. Reconstruct a small nested JSON, then
  `json_example`. *Commit.*
- [ ] **Phase 3 — Insertion-domain recipes (Julia).** `kind → commit-string` reflection table from
  `insertion_candidates`; `Insert → type → Enter` recipe. Reconstruct a small julia example. *Commit.*
- [ ] **Phase 4 — Harness integration + sweep.** `test_construct(example::Example)` `@testset`
  wrapper; add to the domain suite; sweep all domain examples. Mark authoring-gap failures
  `@test_broken` with a `# @broken:` note (per `documentation/testing.md`). *Commit.*
- [ ] **Phase 5 (deferred) — Robustness + strict mode.** (a) bounded-depth probing fallback (depth ≤3)
  for a stuck node; (b) non-text leaf gestures (boolean/color); (c) *gesture-navigation mode* —
  replace `set_selection!` teleport with finite BFS over the selection graph (reuse
  `explore_position_selections` machinery) so navigation is also under test.

## Design decisions

1. **Programmatic selection first.** Default to `set_selection!` teleport to each edit site;
   isolates *edit* gestures from *navigation* (already covered by `test_position_navigation`).
   Gesture-navigation is the Phase 5 strict mode.
2. **Drive at gesture/keystroke level**, not operation level — testing the bindings is the point.
3. **Probe by op-inspection, not clone-and-apply** — cheap, side-effect-free; scratch-doc apply only
   as fallback for opaque ops. Cache recipes by `(context-kind, goal-kind)` → probe once per pair.
4. **Print-then-type for value leaves**, uniformly; per-kind gestures only for non-text leaves.

## Risks / open questions

- **Template projections with introduced carets** may need the domain `_syntax_to_flat`
  `ReplaceSelectionOperation` reader to accept replayed keystrokes (cf.
  `projection-template-needs-flat-offset-reader`); replaying through the chaining projection touches
  those readers. Watch for runaway navigation → the memory cap and bounded `replay` guard this.
- **Non-compositional kinds** (reachable only via create-then-transform) → Phase 5 bounded probing.
- **`synth_event(pattern)` fidelity** — must reproduce exactly what the real backend feeds
  (`pattern.fields` + `modifiers`), including `KeyPress` vs `KeyDown` for character entry.
- **Sequence growth direction** (append vs prepend) — detect from where the new slot lands after the
  first `grow` and pick front-to-back / back-to-front accordingly, so indices stay stable.

## Status

Not started. Design complete and grounded against the verified APIs above.
