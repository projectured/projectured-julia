# SyntaxToText: delegate children instead of flattening the subtree

## Problem

`SyntaxNodeToText` (and its sibling `SyntaxListToText`) in
[program/src/projection/primitive/SyntaxToText.jl](../../program/src/projection/primitive/SyntaxToText.jl)
is the one projection in the codebase that recursively walks its **whole input
subtree itself** and bakes the entire tree into a single flat `TextText`, instead
of delegating each child to the `recursion` parameter the way every `*ToSyntax`
node projection does.

Concretely:

- `projection_print(::SyntaxNodeToText, recursion, node, ctx)`
  ([SyntaxToText.jl:190](../../program/src/projection/primitive/SyntaxToText.jl#L190))
  calls `_collect_spans(node, p, 0, recursion)`.
- `_collect_spans` ([:906](../../program/src/projection/primitive/SyntaxToText.jl#L906))
  walks `node.children` and, per child, calls `_collect_child_spans`
  ([:897](../../program/src/projection/primitive/SyntaxToText.jl#L897)), which for a
  `SyntaxNode` child calls `_collect_spans` again — i.e. it recurses over the
  syntax tree directly.
- **`recursion` is threaded through every helper but never invoked.** There is no
  `projection_print(recursion, recursion, child, …)` anywhere in the file
  (delegates = 0). The comment at
  [:113](../../program/src/projection/primitive/SyntaxToText.jl#L113) even claims
  "Children are projected recursively via projection_print(recursion, ...)" —
  which is false.
- The selection / collapse / hit-test machinery (`_syntax_to_flat`,
  `_subtree_len`, `_pos_to_selection`, `_pos_to_tree_selection`,
  `_node_at_collapse_glyph`) all re-walk the same subtree in flat-character space.

### Why this matters

Because `SyntaxNodeToText` owns the layout of the *entire* subtree, no other
projection can be interposed for any descendant. A `SyntaxNode` child is itself a
valid `SyntaxDocument` that the surrounding `RecursiveProjection(SyntaxToText())`
could render — possibly differently, or as part of an unforeseen cross-domain
composition — but the self-walk forecloses that. This is the printer-side twin of
the "School B" reference-mapping anti-pattern the guides already forbid for
`map_reference_*`.

### Why the fix is safe (behavior-preserving)

Every call site wraps the projection as `RecursiveProjection(SyntaxToText())`
(verified across `example/src/projection/*`, `program/src/backend/Sdl.jl`,
`program/src/editor/WorkbenchAssistant.jl`). So when `SyntaxNodeToText` runs,
`recursion` is the `RecursiveProjection` around the
`TypeDispatchingProjection(SyntaxLeaf => SyntaxLeafToText, SyntaxNode =>
SyntaxNodeToText, ListNode => SyntaxListToText)`. Delegating a child via
`projection_print(recursion, recursion, child, child_ctx)` therefore re-enters the
exact same dispatcher and produces the exact same spans — only now the recursion
follows whatever projection actually ran, so a different one could be substituted.

---

## Part A — Refactor `SyntaxNodeToText` to delegate (the code fix)

The output domain is a **flat `TextText`** (a list of `TextString`/`TextNewline`
spans), so "composing children" means splicing each child's
`child_iomap.output.elements` into the parent's element list and tracking, per
child, the **element-index range** it occupies (replacing today's flat *character*
ranges). All output references are already element-based
(`.elements[j].content{c}`), so element-index composition is the natural axis.

### A0. Prerequisite / coordination
- [ ] If [projection-docs-and-fixes.md](projection-docs-and-fixes.md) task **B4**
  (`projection_printer_recurse` helper) lands first, use it for the child calls
  here. Otherwise introduce the plain `projection_print(recursion, recursion, …)`
  form and let B4 sweep it later. Don't block on B4.

### A1. Printer: project children through `recursion`
- [ ] In `projection_print(::SyntaxNodeToText, …)`, build `child_iomaps =
  Cell(() -> [projection_print(recursion, recursion, child,
  child_context(ctx, @reference ^(reference).children[i])) for (i,child) in …])`.
- [ ] Rewrite `_collect_spans` to assemble the parent element list from **its own
  structural spans** (marker, open, sep, newline+indent, trailing newline+indent,
  ellipsis, close) interleaved with each child's `child_iomap.output.elements`
  (splice the element list, do **not** re-render the child).
- [ ] Record, per direct child, the `[base_i, base_i + n_i)` **element-index**
  range in the parent's element list. This replaces `child_char_ranges`.
- [ ] Delete `_collect_child_spans` and the `_render_*`/`_subtree_len` flat-char
  walkers that exist only to flatten the subtree (keep any helper still needed for
  the node's *own* spans).

### A2. IoMap
- [ ] Extend `SyntaxNodeToTextIoMap` (or switch to `ChildrenIoMap`) to carry
  `child_iomaps::Cell` and `child_elem_ranges::Cell`, keeping `marker_index`.
  Storing child IoMaps is what lets the reader and mappers recurse in lockstep.

### A3. `map_reference_forward` (School A delegation)
- [ ] `.open{k}` / `.close{k}` → own open/close span element index + char `k`.
- [ ] `.sep{k}` → first separator span element index + char `k`.
- [ ] `.children[i] + rest` → delegate `rest` to child `i`'s
  `map_reference_forward` (via the stored child IoMap), then **shift the resulting
  `.elements[m]` index by `base_i`** → `.elements[base_i + m].content{c}`. Whole-
  element tail (`∅`) maps to the child's element range as a
  `TextRectangularReference` (preserve current behavior at
  [:199](../../program/src/projection/primitive/SyntaxToText.jl#L199)).
- [ ] Marker / ellipsis / newline / indent: projection-introduced, no input
  pre-image — keep them out of the forward image.

### A4. `map_reference_backward` (School A delegation)
- [ ] Output `.elements[j].content{c}` (and `.elements[j]∅`, and bare `{flat}` /
  `RangeReference` shapes still arriving from `TextToGraphics`): locate `j`.
  - Own structural span → `.open{c}` / `.close{c}` / `.sep{c}`, or a
    `ProjectionReference(p, {flat})` for non-addressable chrome (marker, indent,
    ellipsis), mirroring today's flat-offset collapse.
  - Falls in child `i`'s element range → delegate `.elements[j - base_i].content{c}`
    to child `i`'s `map_reference_backward`, then prepend `.children[i]`.
- [ ] Keep the `StringReplaceRangeOperation` retarget working through delegation
  (the leaf's `.value{s:e}` rewrite already lives in `SyntaxLeafToText`); preserve
  the input-selection disambiguation at
  [:462](../../program/src/projection/primitive/SyntaxToText.jl#L462).

### A5. Reader: collapse + tree-selection by mouse (`projection_read` 4-arg)
- [ ] Today the gesture-aware reader
  ([:223](../../program/src/projection/primitive/SyntaxToText.jl#L223)) hit-tests
  the **whole** tree via `_node_at_collapse_glyph` / `_pos_to_tree_selection`.
  After delegation the parent recognizes only **its own** marker/ellipsis; a click
  landing in child `i`'s element range must be **forwarded to child `i`'s
  `projection_read`** (Change threaded), then the returned operation extended by
  prepending `.children[i]` where the op is path-based.
- [ ] `ToggleCollapseOperation` carries the `SyntaxNode` **object** as its target
  (per the collapse design), not a path — so a child-produced toggle propagates up
  **unchanged**; no path rewrite needed. Confirm `_node_at_collapse_glyph` can be
  reduced to "own marker/ellipsis only" + child delegation.
- [ ] Alt+click tree selection: own delimiters → `∅`; in child `i`'s range →
  delegate and prepend `.children[i]`.

### A6. Keep (do **not** delegate): keyboard tree navigation over the input
- [ ] `_tree_navigate`, `_is_tree_selection`, `_promote_to_structural`,
  `_descend_to_text_cursor`, `_resolve_collapsible` walk the **input** SyntaxNode
  tree and its selection *paths* — that is this projection's own domain, not a
  projection of foreign child output, so it is **not** the anti-pattern. They stay.
  Only the root `SyntaxNodeToText` receives the `KeyDown`, and its `iomap.input` is
  still the whole tree, so these continue to work unchanged.

### A7. `SyntaxListToText`
- [ ] Apply the same fix to `_render_syntax_to_spans`
  ([:613](../../program/src/projection/primitive/SyntaxToText.jl#L613)): render each
  list element through `recursion` and splice its element list, instead of the
  self-recursive `_render_syntax_to_spans(node::SyntaxNode)`. Lower priority —
  `ListNode`-of-syntax is a narrower path than the `SyntaxNode` tree.

### A8. Cleanup
- [ ] Fix the misleading comment at
  [:113](../../program/src/projection/primitive/SyntaxToText.jl#L113) (it will now
  be true).

---

## Part B — Document the principle (API doc + guides)

State the convention the user asked for: **a projection should transform only its
own single node/level and delegate every child to `recursion` — it must not
recursively process the child subtree itself.** Rationale: a descendant may, in
unforeseen compositions, be a different domain or be rendered by a different
projection; a projection that hand-walks the subtree forecloses those
combinations. This is the printer-side statement of the existing School-A rule.

### B1. `program/src/api/Projection.jl` — **Done**
- [x] In the `projection_print` docstring, added a **"Delegate one level; never
  flatten the subtree"** principle paragraph and cross-referenced the
  `map_reference_forward` "delegate, don't re-walk by type" note so printer and
  mappers state one rule.

### B2. `guide/projection-system.md` — **Done**
- [x] Added a **"Principle: recurse as little as possible"** blockquote under
  **"Recursion across projections"**.
- [x] Extended the **"Anti-pattern — re-walking the input by type (School B)"**
  callout to say the same prohibition applies to the **printer** (flattening a
  child subtree into your own output), naming `SyntaxNodeToText` + this plan.

### B3. `guide/higher-order-projections.md` — **Done**
- [x] Added a paragraph to the `RecursiveProjection` section explaining that
  `recursion` exists to keep each projection single-level and composable.

### B4. (optional) `guide/concepts.md` / `architecture.md`
- [ ] One-line mention that projections are single-level transforms wired together
  by `recursion`, so domains compose in unforeseen ways. Keep light.

---

## Verification

Behavior must be identical before/after (delegation re-enters the same
dispatcher). Run the narrowest covering tests, not `test_all`:

- [ ] `test_syntax()` and `test_syntax_to_text()`.
- [ ] Projection tests: `SyntaxToTextTest.jl`, `SyntaxTreeSelectionTest.jl`.
- [ ] Editor round-trips touching collapse/navigation: `CollapseRoundtripTest.jl`,
  `SyntaxTreeNavigationTest.jl`.
- [ ] Downstream pipelines that go through SyntaxToText: `test_json_to_syntax()`
  plus `test_example(json_example)` / `test_example(xml_example)` /
  `test_example(math_example)` (printer + reader + text navigation), and a
  `test_text_navigation(...; check_reaches_all=true)` on at least one nested
  example to assert every caret is still reachable.
- [ ] Spot-check collapse: `test_repl` on an example exercising
  `ToggleCollapseOperation`.

## Risks / open questions

- **Largest risk:** the selection/collapse/hit-test redistribution (A3–A5). The
  flat-offset math is currently centralized; after delegation it is split between
  "own spans" and "delegate to child," and the reader must recurse for clicks.
  Stage A1–A2 (printer + IoMap, keep old mappers temporarily computing over the
  spliced list) before A3–A5 so output can be diffed against the current printer
  first.
- **`TextRectangularReference`** whole-child highlight (forward) and the bare
  `{flat}` backward inputs must keep round-tripping; add a targeted assertion.
- Decide whether to keep `SyntaxNodeToTextIoMap` (extended) or move to the shared
  `ChildrenIoMap` — prefer reusing `ChildrenIoMap` if its shape fits, for
  consistency with the `*ToSyntax` nodes.
