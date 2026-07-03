# SyntaxToText: delegate children instead of flattening the subtree

> **STATUS (2026-07-02, implementation-ready rewrite):** Expanded to code level so an
> implementer can execute it directly. Part A (the code fix) is **entirely open**;
> Part B (docs) is **entirely done**. Audited against the working tree on
> 2026-07-02 — every line number below is current as of that date.
>
> Since the original plan was written, three relevant things landed:
> - `projection_printer_recurse(recursion, input, ctx)` exists
>   ([Projection.jl:184–194](../../package/kernel/src/api/Projection.jl#L184-L194))
>   and is the mandated child-call form — the old A0 coordination item is resolved.
> - The printer grew a **two-pass split** (spans-only pass vs cursor pass) and a
>   **`_DecoCache`** for decorative-span identity; both interact with this refactor
>   (see S1).
> - `_syntax_to_flat` acquired **~12 external call sites** in six `*ToSyntax`
>   projections — it must be **kept as a shared utility**, not deleted (see the
>   Machinery inventory).

## Problem

`SyntaxNodeToText` (and its sibling `SyntaxListToText`) in
[SyntaxToText.jl](../../package/domain/src/projection/primitive/SyntaxToText.jl)
is the one projection in the codebase that recursively walks its **whole input
subtree itself** and bakes the entire tree into a single flat `TextText`, instead
of delegating each child through `recursion` the way every other node projection
does.

Concretely (line numbers as of 2026-07-02):

- `projection_print(::SyntaxNodeToText, …)` ([:194](../../package/domain/src/projection/primitive/SyntaxToText.jl#L194))
  calls `_collect_spans(node, p, 0, recursion, …)` ([:826](../../package/domain/src/projection/primitive/SyntaxToText.jl#L826)),
  which walks `node.children` and per child calls `_collect_child_spans`
  ([:809–816](../../package/domain/src/projection/primitive/SyntaxToText.jl#L809-L816)),
  which for a `SyntaxNode` child calls `_collect_spans` again — direct
  self-recursion over the input tree.
- **`recursion` is threaded through every helper but never invoked.** There is no
  `projection_printer_recurse` / `projection_print(recursion, recursion, …)` call
  anywhere in the file. The comment at [:115](../../package/domain/src/projection/primitive/SyntaxToText.jl#L115)
  claiming children are projected via `recursion` is **false**.
- The selection / collapse / hit-test machinery (`_syntax_to_flat`,
  `_syntax_to_flat_range`, `_subtree_len`, `_pos_to_selection`,
  `_pos_to_tree_selection`, `_node_at_collapse_glyph`) all re-walk the same input
  subtree in flat-character space, duplicating the layout arithmetic five times.

### Why this matters

Because `SyntaxNodeToText` owns the layout of the *entire* subtree, no other
projection can be interposed for any descendant. A `SyntaxNode` child is itself a
valid `SyntaxDocument` that the surrounding `RecursiveProjection(SyntaxToText())`
could render — possibly differently, or as part of a cross-domain composition —
but the self-walk forecloses that. This is the printer-side twin of the "School B"
anti-pattern the guides forbid for `map_reference_*`. It also destroys
incrementality: any structural edit re-runs the root's whole-tree walk, where
delegation re-renders only the edited node plus a per-ancestor re-splice.

### Why the fix is safe (behavior-preserving)

Every call site wraps the projection as `RecursiveProjection(SyntaxToText())`. So
when `SyntaxNodeToText` runs, `recursion` is the `RecursiveProjection` around
`TypeDispatchingProjection(SyntaxLeaf => SyntaxLeafToText(), SyntaxNode =>
SyntaxNodeToText(…), ListNode => SyntaxListToText())`
([:511–525](../../package/domain/src/projection/primitive/SyntaxToText.jl#L511-L525)).
Delegating a child via `projection_printer_recurse(recursion, child, child_ctx)`
re-enters the exact same dispatcher and produces the same spans — the flat
concatenated text must be **byte-for-byte identical** before and after (S1 gates
on this).

---

## Machinery inventory (read before coding)

Everything the implementation touches, with where it lives today.

**The file under refactor** —
[package/domain/src/projection/primitive/SyntaxToText.jl](../../package/domain/src/projection/primitive/SyntaxToText.jl) (1295 lines):

| Piece | Lines | Fate |
|---|---|---|
| `SyntaxLeafToText` (print/read/mappers) | 38–106 | **Unchanged** (already single-level; it is the delegation target for leaf children) |
| `SyntaxNodeToText` struct + ctor | 128–141 | Unchanged |
| `SyntaxNodeToTextIoMap` | 143–152 | **Reshaped** (S1): `child_char_ranges` → `child_iomaps` + `child_elem_ranges` + `indent_indices`; keep `marker_index` |
| `map_reference_forward(::SyntaxNodeToText, …)` | 154–160 | **Rewritten** (S2): element-zone classification + child delegation |
| `map_reference_backward(::SyntaxNodeToText, …)` | 162–184 | **Rewritten** (S2) |
| `projection_print(::SyntaxNodeToText, …)` | 194–234 | **Rewritten** (S1): splice child outputs; composed selection cell replaces the cursor pass |
| 4-arg gesture reader (`Change`) | 245–282 | **Rewritten** (S3): own-chrome hit-test + child delegation. The console fallback (276–279) survives unchanged |
| `projection_read(…, ::ReplaceSelectionOperation)` | 284–288 | Unchanged (rides the new backward mapper) |
| `projection_read(…, ::ToggleCollapseOperation)` | 295–299 | Unchanged (`_resolve_collapsible` stays, see A6) |
| `projection_read(…, ::KeyDown)` | 308–310 | Unchanged (delegates to `document_read(iomap.input, evt)` — input-domain, root-only, correct) |
| `projection_read(…, ::StringReplaceRangeOperation)` | 316–350 | **Rewritten** (S2): delegate by element zone; keep the input-selection disambiguation |
| `_ends_in_field_range`, `_join_leaf_range` | 354–400 | `_ends_in_field_range` stays (disambiguation); `_join_leaf_range` becomes deletable after S2 |
| `SyntaxListToText` + `_render_syntax_to_spans` | 402–507 | **Rewritten** (S4, lower priority) |
| `_indent_span` / `_newline_span` | 536–538 | Stay (parent's own chrome) |
| `_DecoCache` / `_deco_span` | 551–563 | Stay, scope shrinks to the node's own chrome + widened child indents (S1) |
| `_active_marker` / `_marker_len` / `_ellipsis_len` | 575–593 | Stay |
| `_leaf_cursor` | 598–638 | Stays (used by `SyntaxLeafToText`) |
| `_syntax_to_flat` (leaf + node) | 642–742 | **Stays as a shared utility** — external consumers below. SyntaxToText itself stops calling it after S2 |
| `_structural_cursor` | 744–748 | Deletable after S1 |
| `_syntax_to_flat_range` | 755–807 | Deletable after S1 (TextRect composition replaces it) |
| `_collect_child_spans` / `_collect_spans` | 809–930 | **Deleted** in S1 (replaced by splice) |
| `_span_len` | 818–824 | Stays (splice arithmetic + `_subtree_len`) |
| `_subtree_len` | 932–961 | Stays (backs `_syntax_to_flat`) |
| `_pos_to_tree_selection` | 968–1017 | Deletable after S3 |
| `_pos_to_selection` | 1019–1101 | Deletable after S2 |
| `_node_at_collapse_glyph` | 1109–1154 | Deletable after S3 |
| `_resolve_collapsible` | 1161–1184 | **Stays** (input-domain keyboard fold; A6) |
| `_click_flat_pos` | 1189–1199 | Stays (operates on **output** spans — still valid) |
| `_parse_*` / `_flat_to_text_elem_path` / `_text_elem_path_to_flat` | 1201–1293 | Stay (output-space helpers; the whole refactor leans on them) |

**Kernel machinery to use:**

- `projection_printer_recurse(recursion, input, ctx)` —
  [Projection.jl:184–194](../../package/kernel/src/api/Projection.jl#L184-L194).
  The only sanctioned child-print call form.
- `ChildrenIoMap` — [IoMap.jl:46](../../package/kernel/src/common/IoMap.jl#L46):
  `(projection, input, output, child_iomaps::Cell)`. **Decision: do NOT switch to
  it.** `SyntaxNodeToText` needs three extra cells (`child_elem_ranges`,
  `indent_indices`, `marker_index`) that `ChildrenIoMap` cannot carry — keep the
  dedicated `SyntaxNodeToTextIoMap`, just reshaped. (This settles the old A2 open
  question.)
- `PrinterContext` / `child_context` —
  [PrinterContext.jl:41–91](../../package/kernel/src/context/PrinterContext.jl#L41-L91).
  Build each child's ctx by extending `ctx.reference` with the `.children[i]`
  steps. Copy the exact step-construction idiom from an existing children-field
  delegator (`Copying.jl:126` or the `@projection_template` engine output) rather
  than hand-rolling `RangeReference` indices — index-base conventions live in one
  place there.
- `Change` — [Projection.jl:93](../../package/kernel/src/api/Projection.jl#L93):
  `(gesture, operation)`; readers return a fresh `Change` with the gesture
  preserved.

**School-A exemplars to imitate** (read both before S1):

- [CollectionToSyntax.jl:75–97](../../package/domain/src/projection/primitive/CollectionToSyntax.jl#L75-L97)
  — `child_iomaps = Cell(() -> [projection_printer_recurse(recursion, x, …) …])`,
  output assembled from `im.output`, `ChildrenIoMap` stored.
- [MathToSyntax.jl:91–125](../../package/domain/src/projection/primitive/MathToSyntax.jl#L91-L125)
  — forward/backward mappers that peel one step, look up
  `iomap.child_iomaps[][i]`, and call `map_reference_forward(child.projection,
  child, rest)` / prepend the step on the way back.

**External consumers of `_syntax_to_flat` (do not break them):**
`MathToSyntax` (3 sites), `BookToSyntax` (3), `SqlToSyntax` (3),
`CollectionToSyntax`, `XmlToSyntax`, `DbCatalogToSyntax` (1 each) — all the
flat-offset `ReplaceSelectionOperation` reader pattern from the
projection-template work: they call
`_syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)` to
collapse an unmapped caret on their **output syntax subtree** to a bounded flat
offset (see the rationale comment at
[XmlToSyntax.jl:120–137](../../package/domain/src/projection/primitive/XmlToSyntax.jl#L120-L137)).
Consequences:

- `_syntax_to_flat` + `_subtree_len` + `_span_len` stay exported and unchanged,
  as the **canonical flat metric of a syntax subtree** (measured with a default
  `SyntaxNodeToText()` at depth 0).
- SyntaxToText must keep accepting the resulting reference shapes:
  `proj(p′, {flat})` forward (the `ProjectionReference` branch of
  `_syntax_to_flat`, [:730–741](../../package/domain/src/projection/primitive/SyntaxToText.jl#L730-L741))
  and the bare flat `{n}` backward
  ([:165–171](../../package/domain/src/projection/primitive/SyntaxToText.jl#L165-L171)).
  Preserve exactly the shapes accepted today; do not widen.
- Note these upstream flats are measured **subtree-local at depth 0** while
  today's consumption point sits at absolute depth — a latent metric mismatch for
  indented content. Re-indent-on-splice (below) makes the child-local metric
  *match* the upstream depth-0 metric, so delegation quietly fixes this. If an
  xml/filesystem caret test changes behavior here, it is likely this latent bug
  resolving — verify direction, don't blindly "fix back".

---

## Settled design decisions

These were open questions in earlier revisions; they are now decided. Record any
deviation discovered during implementation back into this section.

> **Implementation note (naming drift):** since this plan was written, a kernel
> naming refactor renamed `projection_print`→`print_document`,
> `projection_read`→`read_intent`, `projection_printer_recurse`→`print_child`,
> `Change`→`Intent`, `StringReplaceRangeOperation`→`ReplaceStringRangeOperation`,
> and children contexts are built with `make_child_context(ctx, @reference
> ^(ctx.reference).children[i])`. The plan's line numbers/names below predate that;
> the current names are used in the code.
>
> **Deviation (S1):** to keep S1 *provably* byte-identical, the S1 selection cell
> reuses the surviving input-walk helpers — `_syntax_to_flat` (case 3, structural)
> and `_syntax_to_flat_range` (case 2, child-∅ TextRect) — rather than deleting
> `_syntax_to_flat_range` in S1. Only case 4 (descendant-cursor fallback) is done
> by delegation (reading each `child_iomap.output.selection`). The full
> mapper-based delegation for cases 2/3 lands in S2 with the rewritten
> `map_reference_forward`; `_syntax_to_flat_range` is deleted then. `_structural_cursor`
> *is* deleted in S1 (its one-line body is inlined into the selection cell).

1. **IoMap:** keep `SyntaxNodeToTextIoMap`, reshaped to
   `(projection, input::SyntaxNode, output::TextText, child_iomaps::Cell,
   child_elem_ranges::Cell, indent_indices::Cell, marker_index::Cell)`.
   - `child_iomaps :: Vector{IoMap}` — one per (expanded) child, in order.
   - `child_elem_ranges :: Vector{UnitRange{Int}}` — 1-based inclusive element-index
     range each child's spliced output occupies in `output.elements`.
   - `indent_indices :: Vector{Int}` — element indices (in `output.elements`) of
     **every line-start indent span in the whole spliced output** — own indents ∪
     each child's `indent_indices` shifted by its splice base. This is what makes
     re-indent-on-splice compositional.
   - `marker_index` — as today (0 or 1); S3's reader finally reads it.

2. **Indentation composes by re-indent-on-splice** (this is what the YAML consumer
   needs, and what keeps every node depth-agnostic — no depth is threaded through
   ctx). Mechanism, chosen to keep element indices 1:1 stable:
   - Each node renders itself at **relative depth 0**: before each child line it
     emits `\n` + an indent span of width `1 * p.indent_size` (its children sit at
     relative depth 1); its trailing indent (the `indentation > 0` case,
     [:892–897](../../package/domain/src/projection/primitive/SyntaxToText.jl#L892-L897))
     is width 0 — an **empty TextString is still emitted** so there is always a
     span to widen and element counts never depend on depth.
   - When splicing a child's output, an `indentation != 0` parent **widens** every
     element listed in the child's `indent_indices` by `p.indent_size` (replace
     the span with a cached wider copy; all other child elements are reused by
     identity). Inline (`indentation == 0`) parents splice verbatim.
   - Sum over ancestors reproduces today's `depth * indent_size` widths exactly ⇒
     byte-identical flat text. (Today `depth` increments only in the
     `indentation != 0` branch — matching "each `indentation != 0` ancestor widens
     once".)
   - Widened spans are cached like deco spans, keyed
     `(child objectid, element index)`, so re-layouts keep identity.
   - Why not thread depth through `PrinterContext`: it keeps output depth-dependent
     (defeats reuse when a subtree moves), and it cannot express the YAML
     inline-container shape (see the YAML section — an inline container's interior
     newlines must be pushed right by the *wrapping entry*, which only splice-time
     widening does).

3. **Child identity across recomputation.** The `child_iomaps` cell re-runs when
   `node.children` changes structurally. Naively re-calling
   `projection_printer_recurse` for every child would hand fresh output objects
   for *unchanged* children to downstream layers on every sibling insert. Keep a
   per-invocation `IdDict{Any,IoMap}` cache in the cell's closure (the
   `_DecoCache` pattern, or `_syntax_list_to_text_node`'s cache at
   [:434](../../package/domain/src/projection/primitive/SyntaxToText.jl#L434)):
   reuse the iomap when the child **object** is unchanged (`get!`), evict slots
   not seen this pass. Input syntax nodes are identity-stable across unrelated
   edits (the template engine reconciles them), so this preserves — and extends
   to whole subtrees — the printer-locality property `_DecoCache` currently
   provides for single spans. Content edits inside a retained child flow through
   that child's own reactive cells; no staleness.

4. **Collapse prunes delegation.** When `node.collapsed`, the `child_iomaps` cell
   yields `IoMap[]` and the spans cell lays out `marker? open ellipsis close` only
   — children are neither projected nor depended on (today's reactive-pruning
   behavior, [:850–865](../../package/domain/src/projection/primitive/SyntaxToText.jl#L850-L865),
   preserved). Forward-mapping `.children[i]…` on a collapsed node returns
   `nothing` (today: −1), backward has no child zones — both fall out naturally.

5. **Output-selection composition** replaces the cursor pass (the
   `want_cursor=true` re-walk, [:213](../../package/domain/src/projection/primitive/SyntaxToText.jl#L213)).
   The output `TextText.selection` cell computes, in order (this reproduces
   today's precedence exactly — structural wins, then first child in order,
   [:917–925](../../package/domain/src/projection/primitive/SyntaxToText.jl#L917-L925)):
   1. `strip_reference_types(node.selection)` is `∅` → `@reference()` (whole-node
      highlight, as today [:218](../../package/domain/src/projection/primitive/SyntaxToText.jl#L218)).
   2. It is a path ending in `∅` under `.children[i]…` → a
      `TextRectangularReference(s, e)` in **parent-flat characters**: delegate the
      tail to child `i`; if the tail is bare `∅` the range is child `i`'s full
      flat extent; if the child returns its own `TextRect(s,e)` (deeper ∅), shift
      both ends by the parent-flat offset of child `i`'s first element
      (`_text_elem_path_to_flat(elements, base_i, 0)`). Downstream consumes flat
      chars ([TextToGraphics.jl:978–995](../../package/domain/src/projection/primitive/TextToGraphics.jl#L978-L995)) —
      the flat-char convention for `TextRect` and bare `{n}` at the projection
      *boundary* is unchanged; only the *internal* bookkeeping moves to element
      indices.
   3. Otherwise map `node.selection` forward through the S2 mapper (own spans /
      child delegation) → element path; if valid, use it (structural wins).
   4. Otherwise scan children in order; take the first whose
      `child_iomap.output.selection[]` is a **cursor element path**
      (`.elements[m].content{c}`), shift `m` by the child's splice base.
      **Subtle:** a child returning `∅` or a `TextRect` is *skipped*, not
      promoted — today a mid-tree stored tree-selection is invisible to the
      parent (only the node's own `node.selection` produces `∅`/`TextRect` at
      [:216–226](../../package/domain/src/projection/primitive/SyntaxToText.jl#L216-L226));
      preserve that.
   5. Otherwise `nothing`.

   **End-anchoring edge:** `_flat_to_text_elem_path`
   ([:1263–1284](../../package/domain/src/projection/primitive/SyntaxToText.jl#L1263-L1284))
   anchors a cursor at end-of-content to the last **non-empty** span (the cursor
   renderer only emits SegCoords for non-empty spans). When the composed mapper
   produces an own-span path (e.g. `.close{k}` on an *empty* close span), it must
   re-anchor the same way — factor a small `_anchor_nonempty(elements, j, c)`
   helper out of `_flat_to_text_elem_path` and use it for every own-span result.

6. **Spans-stability property is preserved by construction.** Today's spans-only
   pass exists so the element vector never depends on selection cells
   ([:195–199](../../package/domain/src/projection/primitive/SyntaxToText.jl#L195-L199)).
   After delegation the parent's spans cell reads `child_iomap.output.elements`
   (never `…output.selection`), and the composed selection cell is a separate
   cell — the property holds without a second pass. Caret moves re-run only
   selection cells up the spine; structural edits re-render one node + re-splice
   its ancestors (strictly better than today's whole-tree re-walk).

---

## Part A — the code fix, staged

Work in a dedicated git worktree. One commit per stage; the flat text must be
byte-identical after S1 and S2 (S1's harness proves it). Update the checkboxes
and record deviations in "Settled design decisions" as you go.

### S1 — Printer + IoMap: delegate, splice, compose selection ✅ DONE

- [x] Rewrote `print_document(::SyntaxNodeToText, …)`:
  - `child_iomaps = Cell(() -> …)` — `IoMap[]` when collapsed; otherwise
    `print_child(recursion, child, child_ctx)` per child through an IdDict
    identity cache keyed on the child object (decision 3), with `child_ctx =
    make_child_context(ctx, @reference ^(ctx.reference).children[i])`.
  - Spans cell → `_splice_node` returns `(elements, child_elem_ranges,
    indent_indices)`: own chrome interleaved with each child's `output.elements`,
    child indents widened when `indentation != 0` (decision 2, via
    `_widen_indent_span` cached `(nid, :widen, child objectid, j)`). Own chrome
    keeps the existing `_deco_span` keys. Emits child-line indent at width
    `1*indent_size` (`_indent_span(p, 1, …)`) and trailing indent at width 0
    (`_indent_span(p, 0, …)`), an empty span always present.
  - Selection cell → `_compose_node_selection` (decision 5). `cursor_cell` /
    `want_cursor` pass deleted.
  - Reshaped `SyntaxNodeToTextIoMap` (decision 1); imports `print_child`,
    `make_child_context`.
- [x] Deleted `_collect_spans`, `_collect_child_spans`, `_structural_cursor`.
  **Kept** `_syntax_to_flat_range` (deviation — see Settled decisions note: the S1
  selection cell reuses it for case 2; it is deleted in S2). Kept `_pos_to_selection`,
  `_pos_to_tree_selection`, `_node_at_collapse_glyph` (S2/S3) and the old
  mappers/readers unchanged (interim shim).
- [x] **Byte-identity harness (gate):** `print_example` for 20 SyntaxToText-exercising
  examples (json/xml/math/yaml/sql/filesystem/markdown/julia/… — full pipeline to
  graphics, so layout geometry is gated) — **byte-identical** before/after.
  Plus a **differential selection driver** (`sel_check.jl`, 14 scenarios covering
  all 5 decision-5 cases incl. child-∅ TextRect and the case-4 descendant fallback)
  — OLD (main) vs NEW (worktree) **identical**. (`test_printer`/`test_syntax` handed
  to the user — heavy stack.)
- [x] Commit: `refactor(syntax-to-text): printer delegates children via recursion, splices element lists`.

### S2 — Mappers + StringReplaceRange: element-zone classification

Replace flat-char input-tree walks with: *classify the element index into a zone
(own chrome vs child range), delegate child zones, shift indices.*

- [ ] `map_reference_forward` ([:154–160](../../package/domain/src/projection/primitive/SyntaxToText.jl#L154-L160)) —
  after `strip_reference_types` / `∅ → @reference()`:
  - `.open{k}` / `.close{k}` → own span's element index + char `k`, through
    `_anchor_nonempty`.
  - `.sep{k}` → first separator occurrence's element index + `k` (today's
    documented behavior, [:674–691](../../package/domain/src/projection/primitive/SyntaxToText.jl#L674-L691)).
  - `.children[i] + rest` → `nothing` when collapsed; else delegate `rest` to
    `child_iomaps[][i]` (Math idiom), then shift the returned `.elements[m]…` by
    `base_i − 1`. A child-returned `TextRect` shifts by flat chars (decision 5.2).
  - `proj(p, {flat})` (own introduced position) → node-local flat over **own
    output** via `_flat_to_text_elem_path(output.elements, flat)`. Preserve the
    transparent-unwrap behavior for other `proj(_, inner)` shapes
    ([:730–741](../../package/domain/src/projection/primitive/SyntaxToText.jl#L730-L741)).
  - Marker / ellipsis / newline / indent: projection-introduced, no input
    pre-image — absent from the forward image (as today).
- [ ] `map_reference_backward` ([:162–184](../../package/domain/src/projection/primitive/SyntaxToText.jl#L162-L184)):
  - Bare flat `{n}` → element path via `_flat_to_text_elem_path`, then fall
    through to the element-path logic.
  - Tree path `.elements[j]∅` → whole-element: own chrome element → `@reference()`;
    child zone → delegate `.elements[j − base_i + 1]∅`, prepend `.children[i]`.
  - `.elements[j].content{c}` → own `open`/`close`/`sep` element → `.open{c}` /
    `.close{c}` / `.sep{c}`; own chrome (marker, ellipsis, newline, indent) →
    `proj(p, {node-local flat})` exactly as `_pos_to_selection`'s `_proj` does
    today (compute the flat with `_text_elem_path_to_flat` over own output);
    child zone → delegate with the index shifted child-local, prepend
    `.children[i]` to the result. Delegation reproduces today's shapes because
    chrome *inside* a child already comes back `proj(p, {child-local flat})` from
    the child's own mapper.
- [ ] `projection_read(…, ::StringReplaceRangeOperation)` ([:316–350](../../package/domain/src/projection/primitive/SyntaxToText.jl#L316-L350)):
  the reference is single-span (`_parse_text_elem_range`). Classify its element:
  child zone → shift child-local, delegate the 3-arg read to
  `child_iomap.projection`, prepend `.children[i]` to the returned op's
  reference; the leaf `.value{s:e}` rewrite already lives in `SyntaxLeafToText`
  ([:93–101](../../package/domain/src/projection/primitive/SyntaxToText.jl#L93-L101)).
  Keep the zero-width input-selection disambiguation ([:337–343](../../package/domain/src/projection/primitive/SyntaxToText.jl#L337-L343)),
  re-expressed in output space: forward-map `iomap.input.selection` via the new
  mapper and compare element path + char to the edit target (replaces the
  `_syntax_to_flat(…) == flat_start` comparison).
- [ ] Delete `_pos_to_selection` and (if now unused) `_join_leaf_range`. Keep
  `_syntax_to_flat` / `_subtree_len` / `_span_len` — external consumers; move
  them under a clearly-labeled "shared flat metric of a syntax subtree — used by
  *ToSyntax flat-offset readers, not by this projection's own mapping" section
  divider with a docstring naming the consumers.
- [ ] Verify: `test_syntax_to_text()`, `test_json_to_syntax()`,
  `test_example(json_example)`, `test_example(xml_example)`,
  `test_example(math_example)`,
  `test_text_navigation(json_example; check_reaches_all=true)`.
- [ ] Commit: `refactor(syntax-to-text): mappers delegate by element zone through child iomaps`.

### S3 — Reader: collapse + Alt+click by delegation

- [ ] Rewrite the gesture branch of the 4-arg reader ([:245–258](../../package/domain/src/projection/primitive/SyntaxToText.jl#L245-L258)):
  resolve the click to an element index (via `_click_flat_pos` +
  `_flat_to_text_elem_path`, both output-space). Then:
  - Own marker (use `marker_index`, finally read; include today's
    boundary-pixel tolerance, [:1113–1118](../../package/domain/src/projection/primitive/SyntaxToText.jl#L1113-L1118))
    or own ellipsis element → `Change(gesture, ToggleCollapseOperation(node))`.
  - Child zone → forward the **Change** (path shifted child-local) to
    `projection_read(child_iomap.projection, recursion, change′, child_iomap)`.
    A returned `ToggleCollapseOperation` carries the target `SyntaxNode`
    **object** — propagates up unchanged, no path rewrite. A returned
    path-based op (Alt+click tree selection) gets `.children[i]` prepended.
  - Alt+click on own delimiters/chrome → `ReplaceSelectionOperation(∅)` (select
    this whole node — today's close-delimiter behavior at
    [:1015–1016](../../package/domain/src/projection/primitive/SyntaxToText.jl#L1015-L1016)).
- [ ] Delete `_node_at_collapse_glyph`, `_pos_to_tree_selection`.
- [ ] Keep untouched (A6 of the old plan): `KeyDown → document_read(iomap.input, evt)`,
  `ToggleCollapseOperation` resolution via `_resolve_collapsible`, and the
  console fallback — all input-domain or output-whole concerns that only the
  root instance exercises.
- [ ] Verify: `test_repl` on a collapse-exercising example, `CollapseRoundtripTest.jl`,
  `SyntaxTreeSelectionTest.jl`, `SyntaxTreeNavigationTest.jl` (baselines: see
  Verification).
- [ ] Commit: `refactor(syntax-to-text): reader routes clicks by element zone, delegates to children`.

### S4 — `SyntaxListToText` (lower priority)

- [ ] In `_syntax_list_to_text_node` ([:434–486](../../package/domain/src/projection/primitive/SyntaxToText.jl#L434-L486)),
  replace `_render_syntax_to_spans(elem)` ([:488–507](../../package/domain/src/projection/primitive/SyntaxToText.jl#L488-L507))
  with `projection_printer_recurse(recursion, elem, ctx′)` and splice
  `iomap.output.elements` into the lazy ListNode chain. Delete the three
  `_render_syntax_to_spans` methods. Note the current flat render emits **no
  newlines/indentation** for nested nodes — delegated rendering will add them;
  check `test_syntax()` list cases and accept/record the (improved) difference.
- [ ] Commit: `refactor(syntax-to-text): SyntaxListToText delegates elements via recursion`.

### S5 — Cleanup + docs

- [ ] Fix the false comment at [:113–115](../../package/domain/src/projection/primitive/SyntaxToText.jl#L113-L115)
  (it is finally true) and the module docstring (lines 1–8: "character ranges …
  recorded in the IoMap" → element ranges + delegation).
- [ ] Update the `_DecoCache` block comment ([:540–555](../../package/domain/src/projection/primitive/SyntaxToText.jl#L540-L555))
  — the "re-runs whole on any structural change" premise no longer holds.
- [ ] Remove the printer-side anti-pattern callout naming `SyntaxNodeToText` in
  [documentation/projection-system.md](../../documentation/projection-system.md)
  (~L552–558) — or reword it past-tense as a worked example.
- [ ] Move this plan to `plan/done/`.
- [ ] Commit: `docs(syntax-to-text): update comments and guides after delegation refactor`.

---

## Part B — Document the principle ✅ ALL DONE

The convention ("a projection transforms only its own single level and delegates
every child to `recursion`") is now stated in four places — verified 2026-07-02:

- **B1** ✅ [Projection.jl:135](../../package/kernel/src/api/Projection.jl#L135) —
  "Delegate one level; never flatten the subtree" in the `projection_print`
  docstring, plus the two-prohibitions block (no fifth recursive function; no
  self-walking by child type).
- **B2** ✅ [documentation/projection-system.md](../../documentation/projection-system.md) —
  "Principle: recurse as little as possible" (~L478) and the School-B printer
  extension naming `SyntaxNodeToText` + this plan (~L552).
- **B3** ✅ [documentation/higher-order-projections.md](../../documentation/higher-order-projections.md)
  (~L116) — `recursion` keeps projections single-level and composable.
- **B4** ✅ [documentation/concepts.md:186–191](../../documentation/concepts.md#L186-L191)
  and [documentation/architecture.md:130–135](../../documentation/architecture.md#L130-L135)
  — single-level transform + the recursion contract, with cross-links.

---

## Verification

**Protocol:** run the Julia suite from the repo root with `julia --project=.`.
Full-stack precompile/test runs crash the VS Code editor host — hand the heavier
sweeps to the user for an external terminal; a light `using Projectured`-only
driver (e.g. the byte-identity harness) is safe in-session (~10 s).

Per-stage gates are listed in each stage. Known pre-existing baselines (do not
chase these as regressions): `test_syntax_tree_selection` 12 pass / 9 fail /
4 err; `test_json_to_syntax_reader` one line-117 array-insert selection quirk;
`test_typein` wholesale-fail baselines for json/xml/julia; `test_all` ≈13 known
fails. Anything *beyond* these after S3 is a regression.

Final sweep after S5 (external terminal): `test_syntax()`,
`test_syntax_to_text()`, `test_json_to_syntax()`, `test_example` on
`json_example` / `xml_example` / `math_example`,
`test_text_navigation(json_example; check_reaches_all=true)`, then
`test_printers()` + `test_repls()` as the broad pass.

## Risks

- **Largest:** the S2/S3 redistribution of selection/collapse/hit-test logic.
  Mitigated by the staging: S1 lands with old mappers intact and a byte-identity
  gate, so mapper changes are diffed against a proven-identical printer.
- `TextRectangularReference` and bare `{n}` stay **flat-char at the boundary**
  while bookkeeping moves to element indices — every boundary conversion goes
  through `_text_elem_path_to_flat` / `_flat_to_text_elem_path` over the spliced
  output; never mix the two spaces inside one function.
- Upstream `proj(p′, flat)` carets: the depth-0 subtree metric now matches
  child-local delegation (see Machinery inventory) — a behavior *change* here is
  likely the latent mismatch resolving; investigate before reverting.
- Reactive regressions of the reuse kind pass direct-read tests but fail live
  (iomap reuse) — exercise via `test_repl` and, if in doubt, a real `Editor`
  round-trip, not just fresh reprints.

---

## Follow-on consumer: YAML block layout depends on this refactor

> **Context (2026-07-02):** Surfaced while adding the YAML domain
> (`package/domain/src/document/Yaml.jl`,
> `package/domain/src/projection/primitive/YamlToSyntax.jl`). Recorded here because
> the clean fix *is* this refactor, not a `SyntaxToText` special-case.

`YamlToSyntax(style=:block)` renders idiomatic block YAML by making each mapping /
sequence a **block `SyntaxNode`** (`indentation=-1`, empty open/close) laid out one
entry / item per indented line. It works, but the **root** container carries two
cosmetic artifacts: a **2-space left margin** on every line, and a **leading blank
line**.

### Why it happens

A block node emits `\n + indent(child_depth)` before each child, with
`child_depth = depth + 1`. The root mapping is at `depth 0`, so its entries land at
`depth 1` → indent 2 (the margin), and the first child's leading `\n` is the blank
line. The root mapping node and every nested mapping node are **byte-for-byte
identical**; only the render depth differs. Nested indentation is correct and
wanted — only the root's own self-indent is spurious.

### Why a "flush the root" flag is the wrong fix — and this refactor rules it out

The obvious patch is `SyntaxToText(flush_root=true)`, special-casing the outermost
node. **Part A deletes exactly that entry point.** After delegation,
`SyntaxNodeToText` is applied per-node and independently; no application can tell
whether its node is the root, and threading a depth just to reintroduce that
knowledge fights the "delegate one level" principle. So `flush_root` is a dead end.

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
ever asks "am I root?"** — the margin falls out of composition.

### How A1's re-indent-on-splice serves this

The indented wrapper works only if wrapping indents the child's **entire
multi-line output** — the child's *interior* newlines must be pushed right too.
That is exactly the splice-time widening of the child's `indent_indices`
(Settled design decision 2). Depth-threading cannot express it: an inline
container's interior newlines never learn about the wrapper. This is why the
inline-container shape is impossible pre-refactor.

### Action

- [ ] After Part A lands, restructure `YamlToSyntax` (block style) to inline
  containers + value-edge indentation per the above, dropping the `indentation=-1`
  block-container shape (currently
  [YamlToSyntax.jl:188–190](../../package/domain/src/projection/primitive/YamlToSyntax.jl#L188-L190)),
  and remove the cosmetic-margin caveat from the module docstring. Gate with
  `test_text_navigation(yaml_example; check_reaches_all=true)` once the suite runs.
