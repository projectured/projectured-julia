# Live example construction test

> **Status (2026-08-12): IN PROGRESS.** JSON, YAML, and XML reconstruct fully
> (confirmed against `package/projectured/test/editor/ConstructTest.jl`); SQL, the
> text/graph domains, Julia insertion-domain recipes, and the generic
> `test_construct(example::Example)` sweep across all domains (Phase 4) are still
> open, matching this plan's own "Next" list below.

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
| Place selection by path | ✅ exists | `set_selection!(doc, @reference(doc, …))` [`selection/Selection.jl:75`, `reference/ReferenceBuilder.jl:174`]; enumerate sites `collect_tree_selections` / `collect_position_selections` [now `package/substrate/test/document/SelectionEnumeration.jl` — `package/base` no longer exists; a near-duplicate copy also lives at `package/projectured/test/document/SelectionEnumeration.jl`] |
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

**Oracle** in `package/kernel/test/editor/ConstructTest.jl` (kernel-tier — it needs only kernel
primitives), exported from `ProjecturedKernelTest`. **Engine** (`reconstruct` / `test_construct` /
per-domain cases) in `package/projectured/test/editor/ConstructTest.jl` (moved from the old
`package/domain/test/editor/ConstructTest.jl` when `ProjecturedDomain` was dissolved into
per-domain packages) — *not* kernel-tier as first
planned, because it needs base's `@domain` seed machinery (`nothing_document` / `domain_insertion`)
and visual's `TextToString`, and drives domain examples. This mirrors how `collect_*_selections`
(base test) and the JSON test invocations (domain test) split across tiers. A generic
`test_construct(example::Example)` sweep is Phase 4. Run under the memory cap
(`julia-tests-need-memory-cap`) for the broad sweeps.

## Phases (commit per phase; worktree `projectured-julia-construct`, branch `live-example-construction`)

- [x] **Phase 0 — Oracle. DONE.** Implemented as `compare_content(actual, expected) -> Vector{String}`
  (empty = equal; each entry tags the mismatch path `∅`/`.field`/`[i]`) — a returns-diffs shape rather
  than a throwing `assert_equal_content`, which is cleaner to `@test`. Mirrors `walk_document`'s descent
  (`is_element_collection`/dict/array/fieldnames, `unwrap_cell`, skip `:ref`/`:selection`); kind compared
  by `typename` (reactive structs are parametric). In `package/kernel/test/editor/ConstructTest.jl` (still the current path) with
  `test_construct_oracle()` (14/14 pass; wired into `test_kernel()`). *Committed.*
- [x] **Phase 1 — Leaf reconstruction. DONE.** `reconstruct(target, projection)` +
  `test_construct` + `test_json_construct()` in `package/projectured/test/editor/ConstructTest.jl`.
  Seed = `nothing_document(domain_insertion(typeof(target)))()`; surface (the keystrokes) = the
  target rendered to text by swapping the projection's graphics terminal for
  `RecursiveProjection(TextToString())` and forcing `iomap.output`; drive = set ∅ selection then
  feed each surface char through the real `read_intent → evaluate_operation` loop, with a mutable
  `_ConstructEditor` holder (construction swaps the whole root: `JsonNothing → JsonNumber/…`).
  Uses the **whole-tree dispatching** projection `make_json_projection_example()` (the leaf-specific
  atom projections can't project the `JsonNothing` seed). `null`/`true`/`false` reconstruct
  immediately; `number`/`string` first landed as `@test_broken` — the two **revealed reader bugs** now
  fixed (see "Revealed bugs — now fixed"). Oracle made **strict** (42 ≠ 42.0) so it surfaces the number
  bug. *Committed.*
- [x] **Phase 2 — Structural recipes (element-collection containers). DONE (arrays).** `reconstruct`
  is now a **recursive planner** (`construct_node!` + `_document_child_slots`): a leaf is typed as its
  whole surface; a container is created by the **first character of its surface** (the kind-selecting
  keystroke — `[`/`{`/digit/`"`/`n`/`t`/`f`), then each child slot is navigated to (programmatic ∅
  selection at its reference path) and recursed. **Design change:** probe-and-learn `choose_recipe`
  proved unnecessary for JSON — print-then-type already encodes the create gesture in the surface's
  first char; op-inspection probe-and-learn stays the documented fallback for a domain where that
  doesn't hold. `json/array`, `json/array-bool`, `json/array-nested` (and, once the string bug was
  fixed, `json/array-string`) reconstruct exactly. **Bug found & fixed in the planner:** the base
  `CellVector` *is* a `Document`, so
  `_document_child_slots` must test the collection case *before* `fv isa Document`, else it pushes the
  container itself as a child and `construct_surface` throws projecting a bare CellVector. Multi-child
  sequence growth (a per-domain "append element" gesture between children) is deferred — the catalog
  atoms hold a single child. **Object entries (record node: string key beside a document value) are
  Phase 3** — the entry is not created by a gesture (it comes with `{`) and its key is a scalar field
  that needs text-typing, so the "create + fill document children" shape doesn't fit; it needs a
  fill-in-place node treatment. *Committed.*
- [x] **Phase 3 — Record nodes + multi-child grow (JSON). DONE.** The planner is now a slot model
  (`_node_slots` → `:scalar` / `:document` / `:element`; `construct_node!` + `_fill_slot!` +
  `_fill_element!` + `_fill_scalar!`). **Multi-child grow:** a second-or-later collection element is
  appended with the container's `,` gesture, fed with the *whole container* ∅-selected so the key
  reaches the container's `@gestures` (a caret inside a filled leaf would swallow it as text) rather
  than programmatic navigation to a not-yet-existent slot. **Record nodes:** a JSON object entry (a
  scalar `key` beside a `Document` value) is pre-created by its object's `{` / `,` with the caret at
  `key{0}`; its key is typed there and its value recursed — no `Tab` needed (programmatic ∅ nav to the
  value). A slot already matching the target (an insertion the create left in place — the `placeholder`
  entry) is skipped via a `compare_content` early-out. A bare `*Insertion` target is seeded as itself
  (`insertion_root` overridden ⇒ placeholder). **All six catalog JSON documents reconstruct**, including
  the full nested `make_json_document_example()` (objects/arrays/strings/numbers/bools/placeholder at
  once). *Julia insertion-domain recipes deferred — the JSON record work covered the same ground
  (create-with-parent + typed scalar field).* *Committed.*
- [~] **Phase 4 — Harness integration + sweep. PARTIAL (JSON).** `test_json_construct()` is now a full
  reachability sweep: scalars, arrays (incl. multi-element + nesting), objects (incl. multi-entry +
  nesting + placeholder), and both catalog example documents — 19 `@test`, 2 `@test_broken`. The two
  broken are the **only authoring gap**: a truly empty `[]` / `{}` is unreachable by typing (creation
  always leaves one placeholder child and JSON has no element-delete gesture). A generic
  `test_construct(example::Example)` cross-domain sweep is still open. *Committed.*
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

## Revealed bugs — now fixed

The construction test surfaced these; all three are resolved.

- **json/number — number editing drifted to `Float64`.** `splice_number`
  (`package/kernel/main/operation/Operations.jl`) always did `tryparse(Float64, …)`, so editing `4` into `42`
  produced `JsonNumber(42.0)`. Fixed by parsing `Int` first, `Float64` only for a fractional/exponent
  result (`something(tryparse(Int, …), tryparse(Float64, …), Some(nothing))`) — matching the canonical
  JSON parser. Integer numbers now stay integers.
- **json/string — the first content char could never be typed.** *Not* a "just-created string" cursor
  bug as first hypothesised: a caret at `value{0}` lowers to the flat boundary between the introduced
  opening-quote span and the value span, and the flat→span lowering counts a boundary offset to the
  *earlier* span's end — so the edit mapped onto the introduced `open` delimiter (no pre-image) and was
  declined. It bit *every* insertion at a string's start (`value{0}`), empty or not; an empty string
  offers only that caret, so it could never take a character. Fixed in `SyntaxLeafToText` (the projection
  that knows which spans are delimiters vs content): a zero-width insertion sitting on the open|value
  boundary is redirected into `value{0}` — *prefer content over the projection's own delimiters, even
  when the value is empty*. Covers both the graphics and console pipelines (both funnel through the
  `ReplaceStringRangeOperation` reader).
- **Delimited-leaf closing quote was typed as content (reconstruction engine).** `reconstruct` typed a
  leaf's *whole* surface, so the trailing `"` of `"Hi"` inserted a literal quote (`"Hi\""`). A closing
  delimiter is projection chrome — a container's `]`/`}` is likewise never typed. Fixed in the engine
  (`_leaf_authoring_surface`): drop the leaf's `close`-span text (read off the domain→syntax stage) from
  the surface, so a leaf is authored by its opening delimiter + value only.

The earlier `JsonNull` "2nd keystroke throws `FieldError`" note did not reproduce under the reconstruction
loop after these fixes (a second keystroke on a completed literal is simply declined).

## Status

**JSON is complete: Phases 0–3 done, both revealed reader bugs fixed, every JSON document is
reconstructable.** Oracle `compare_content` (kernel, strict, 17/17). `test_json_construct` (domain) is
**19 pass / 2 broken**: scalars, arrays (multi-element + nesting), objects (multi-entry + nesting +
placeholder entry), and both catalog example documents (the empty buffer and the full nested object)
reconstruct exactly. The 2 broken are the sole authoring gap — an empty `[]` / `{}` (no element-delete
gesture). The planner is a generic slot model (`:scalar` / `:document` / `:element`) with multi-child
grow and record (keyed-entry) handling.

**The entire JSON test surface is now green**, including `test_typein` (963/963 across json / json_sorted
/ json_insertion). Closing the last gap took two shared-seam fixes: `_lower_text_range` now snaps a
non-empty delete/replace range's ends *into* the span they touch (a range starting on the open-quote
seam stays in the value), so deleting a string's first character no longer declines as cross-span — this
also un-broke the `ConsoleBackendTest` boundary-delete case (its `@test_broken` promoted to `@test`); and
`InsertionToSyntaxLeaf` gained the `ReplaceStringRangeOperation` reader it was missing, so typing into an
insertion buffer through the full pipeline no longer throws. Both were verified regression-clean against
`main` (test_visual byte-identical; test_domain Fail unchanged at the 19 pre-existing `versioning`
printer failures). The zero-width insertion boundary stays with SyntaxToText's prefer-content redirect —
only the *range* case moved to the generic Text lowering.

**YAML is also complete.** The engine gained **create-keystroke discovery** (`_create_keystroke`): the
keystroke that turns a placeholder into a kind is found by trying each character the placeholder's create
gestures offer and keeping the one that produces the right kind (cached per kind). This replaced the
JSON-only "first surface char is the create key" assumption — a YAML string is unquoted (created by `"`,
surface starts with content) and a YAML sequence renders `[…]` yet is created by `-`. A leaf now types
`create-key + surface` when the key is not already the surface's first character; a container types the
discovered create key. `test_yaml_construct` is **15 pass / 2 broken** (same empty-container gap), and the
whole YAML example surface (printer / reader / navigation / repl / typein) is green — the text-selection
fix carried straight over. This also incidentally reconstructs a bare `JsonObjectEntry` (discovery finds
its `:` create key).

**XML is also complete — the engine is now fully domain-agnostic.** XML stretched it furthest: an
`XmlElement` is a scalar `tag` beside *two* collections (attributes + children), an `XmlAttribute` is a
two-scalar `name`/`value` record, its collections start *empty* (every element is appended, none
pre-exists), and each is grown by a *different, kind-specific* gesture — a child element with `<`, a child
text with `"`, an attribute with `KeyDown(:space)`. Four generalizations covered it, all discovered, none
domain-coded:
- **Grow-event discovery** (`_grow_event`): the event that appends kind K to collection F, found by
  building a fresh empty container and trying each event its gestures offer plus K's create keystroke,
  keeping the one that grows F — preferring the event that lands K's kind (XML) over a placeholder
  (JSON/YAML's `,`). The container must *survive* the probe (JSON's inherited `n` would replace the array
  with a `JsonNull`).
- **Event-based feeding** (`_synth_event` / `_feed_event!`): `KeyDown` gestures (`:space`), not just chars.
- **Multi-scalar records**: a node with >1 scalar (an attribute's `name`+`value`) is created, then each
  scalar navigated to (`<field>` + `Position(0)`, the shape `move_to_field` produces) and typed.
- **Already-created skip**: a node a grow gesture built directly (an XML child) skips its create keystroke
  and fills in place; a JSON placeholder (`,`-grown) does not, so it is still created in place.

One small domain change enabled it (approved): `_xml_replaceable` now treats the empty `XmlNothing` as
replaceable too, so `<`/`"`/`@` build a node directly from nothing (as JSON's `[`/`{`/`"` do), without the
typed-name insertion buffer. `test_xml_construct` reconstructs text, the attribute record, elements with
attributes / text / multiple / nested children, and the full nested `make_xml_document_example()` — **10
pass / 0 broken** (XML has no empty-container gap: an element is created empty). Regression-verified: the
whole XML example surface is **10647 pass / 0 fail / 0 broken** on the worktree versus **98 fail / 4
broken** on clean `main` — the changes *fix* pre-existing XML boundary-delete typein failures, none new.

Next, in order of remaining value:
- **The remaining domains** — apply the same generic engine (sql, then the text/graph domains as their
  authoring models allow).
- **Julia insertion-domain recipes** — a `kind → commit-string` reflection table + `Insert → type →
  Enter`, for a domain whose nodes are created by a typed-name buffer rather than a single char (the one
  shape `_create_keystroke` still returns `nothing` for).
- **Phase 4 — generic `test_construct(example::Example)` sweep** across all domains.

The reader fixes + reconstruction engine landed on `main` directly (commits `b83b83ec`,
`194319e7`, `3b55e3ab`, `c57e7ff7`, `af4b26ef`, `b7b231cc`, `0da6b7fd`, 2026-07-16/17).
The branch `fix-json-number-string-readers` and its worktree `../projectured-julia-jsonfix`
no longer exist — the branch was merged and deleted.
