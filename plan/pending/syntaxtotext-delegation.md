# SyntaxToText: delegate children instead of flattening the subtree

> **AUDIT (2026-06-23):** Verified against the current codebase (now restructured
> under `package/<subpackage>/src/...`; the source file is
> `package/domain/src/projection/primitive/SyntaxToText.jl`, the docs under
> `documentation/`, not `guide/`).
> - **Part A (the code fix): all OPEN.** `SyntaxNodeToText`/`SyntaxListToText`
>   still flatten the whole subtree. `recursion` is threaded but never invoked —
>   the only mention is the misleading comment at line 115. The IoMap still carries
>   `child_char_ranges` (flat character ranges), not element-index ranges; the
>   flat-char walkers (`_collect_child_spans`, `_subtree_len`, `_pos_to_selection`,
>   `_pos_to_tree_selection`, `_node_at_collapse_glyph`) are all still present.
> - **Part B (docs): B1, B2, B3 DONE and verified** in the current tree (see
>   per-item notes). **B4 OPEN** (no single-level mention found in
>   `documentation/concepts.md` / `documentation/architecture.md`).
> - **Verification checklist: all OPEN** (the code change has not landed). The
>   named test files exist under `package/test/src/...`.
> - **Nothing is OBSOLETE.** The refactor remains applicable and unimplemented.

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

> ⏳ **OPEN (all of A0–A8).** Source file:
> `package/domain/src/projection/primitive/SyntaxToText.jl`. None of the delegation
> work has landed: `recursion` is never invoked (only the false comment at L115),
> the IoMap still stores `child_char_ranges` (L147) instead of element ranges, and
> `_collect_child_spans` (L765) still self-recurses over child SyntaxNodes.

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
> ✅ VERIFIED DONE — `package/kernel/src/api/Projection.jl:135` (the
> "Delegate one level; never flatten the subtree" heading + paragraph in the
> `projection_print` docstring, cross-referencing `map_reference_forward`).
- [x] In the `projection_print` docstring, added a **"Delegate one level; never
  flatten the subtree"** principle paragraph and cross-referenced the
  `map_reference_forward` "delegate, don't re-walk by type" note so printer and
  mappers state one rule.

### B2. `guide/projection-system.md` — **Done**
> ✅ VERIFIED DONE — file now at `documentation/projection-system.md`. The
> "Principle: recurse as little as possible" blockquote is at L478; the printer
> extension of the School B anti-pattern callout (naming `SyntaxNodeToText` and
> this plan) is at L552–558.
- [x] Added a **"Principle: recurse as little as possible"** blockquote under
  **"Recursion across projections"**.
- [x] Extended the **"Anti-pattern — re-walking the input by type (School B)"**
  callout to say the same prohibition applies to the **printer** (flattening a
  child subtree into your own output), naming `SyntaxNodeToText` + this plan.

### B3. `guide/higher-order-projections.md` — **Done**
> ✅ VERIFIED DONE — file now at `documentation/higher-order-projections.md`. The
> `RecursiveProjection` section (L116–121) explains `recursion` keeps each
> projection "single-level and composable" and links back to the recursion
> principle in projection-system.md.
- [x] Added a paragraph to the `RecursiveProjection` section explaining that
  `recursion` exists to keep each projection single-level and composable.

### B4. (optional) `guide/concepts.md` / `architecture.md`
> ⏳ OPEN — no single-level/`recursion`-composability mention found in
> `documentation/concepts.md` or `documentation/architecture.md`.
- [ ] One-line mention that projections are single-level transforms wired together
  by `recursion`, so domains compose in unforeseen ways. Keep light.

---

## Verification

> ⏳ **OPEN (all items).** These are run after the Part A code change, which has
> not landed. The named test files exist:
> `package/test/src/projection/SyntaxToTextTest.jl`,
> `package/test/src/projection/SyntaxTreeSelectionTest.jl`,
> `package/test/src/editor/CollapseRoundtripTest.jl`,
> `package/test/src/editor/SyntaxTreeNavigationTest.jl`.

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
- **How indentation composes is a design decision A1 must settle** — fixed
  per-level vs depth-threaded vs re-indent-on-splice. The YAML consumer below
  needs *re-indent-on-splice* (indent a child's whole multi-line output), which is
  also what keeps each node depth-agnostic. See
  [§ Follow-on consumer: YAML block layout](#follow-on-consumer-yaml-block-layout-depends-on-this-refactor).

---

## Follow-on consumer: YAML block layout depends on this refactor

> **Context (2026-07-02):** Surfaced while adding the YAML domain
> (`package/domain/src/document/Yaml.jl`,
> `package/domain/src/projection/primitive/YamlToSyntax.jl`). Recorded here because
> the clean fix *is* this refactor, not a `SyntaxToText` special-case.

`YamlToSyntax(style=:block)` renders idiomatic block YAML by making each mapping /
sequence a **block `SyntaxNode`** (`indentation=-1`, empty open/close) laid out one
entry / item per indented line. It works, but the **root** container carries two
cosmetic artifacts:

- a **2-space left margin** on every line, and
- a **leading blank line**.

### Why it happens

A block node emits `\n + indent(child_depth)` before each child, with
`child_depth = depth + 1`. The root mapping is at `depth 0`, so its entries land at
`depth 1` → indent 2 (the margin), and the first child's leading `\n` is the blank
line. The root mapping node and every nested mapping node are **byte-for-byte
identical** (`Node indentation=-1 open=""`); only the render depth differs. Nested
indentation (e.g. `street` under `address`) is correct and wanted — only the root's
own self-indent is spurious.

### Why a "flush the root" flag is the wrong fix — and this refactor rules it out

The obvious patch is `SyntaxToText(flush_root=true)`, special-casing the outermost
node (keyed on the single top-level `_collect_spans(node, 0)` call / an `is_top`
flag / `ctx.depth == 0`). **Part A deletes exactly that entry point.** After
delegation, `SyntaxNodeToText` is applied per-node and independently; no application
can tell whether its node is the root, and threading a depth just to reintroduce
that knowledge fights the "delegate one level; never flatten" principle (Part B). So
`flush_root` is a dead end.

### The clean, root-agnostic fix — enabled by delegation

Put the block indentation on the **value edge**, not the container edge:

- **Mapping** → an *inline* node (entries joined by a newline separator, **adds no
  indent**).
- **Entry** with a scalar value → inline `key: value`.
- **Entry** with a block value → `key:` + an *indented wrapper* around the value.
- **Sequence** → inline `- item` lines; a block item-value is indented the same way.

Then a mapping's entries always sit at the mapping's own column: the **root** is
composed by the pipeline (nothing indents it) → column 0; a nested mapping is
composed by its `key:` entry, which indents it → +2. Correct YAML, and **no node
ever asks "am I root?"** — the margin falls out of composition. Same
"recurse-as-little-as-possible" shape Part B documents.

### Design constraint this puts on A1

For value-edge indentation to compose, a block wrapper must indent its child's
**entire multi-line** output — i.e. **re-indent every line of the spliced child
element list**, not just prepend one `newline+indent` before it (A1's "splice the
element list" must push the child's *interior* newlines right too). Re-indent-on-
splice is preferable to threading a depth: it keeps each `SyntaxNodeToText`
depth-agnostic, which is exactly what lets the root stay flush with no
root-detection. Today's depth-threaded `\n+indent`-before-first-line does neither,
which is why the inline-container shape is impossible pre-refactor (an inline
container's *interior* newlines never get pushed right).

### Action

- [ ] After Part A lands, restructure `YamlToSyntax` (block style) to inline
  containers + value-edge indentation per the above, dropping the `indentation=-1`
  block-container shape, and remove the cosmetic-margin caveat from the module
  docstring. Gate with `test_text_navigation(yaml_example; check_reaches_all=true)`
  (every caret still reachable) once the suite runs.
