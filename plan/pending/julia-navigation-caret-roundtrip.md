# Fix Julia (and fixed-node) caret navigation: introduced-token round-trip

`test_text_navigation(julia_example)` reached only **2** caret states and
`test_tree_navigation(julia_example)` only **1** (the root) — i.e. text and syntax
navigation on `julia_example` were effectively dead, even though the suite was
"green" (both tests only assert `states > 0` / `isempty(errors)`; `check_reaches_all`
is not applied to `julia`, so the ceiling went unnoticed).

Root cause: a caret sitting on (or a whole-element selection of) a projection-
**introduced** token/sub-node — which Julia's projection is full of (`function`,
`if`, `else`, `end`, operators, parens, and the `function name(params)` header
grouping) — failed to **round-trip** through the reference machinery, so no cursor
rendered and relative navigation had no anchor. JSON/XML/SQL mostly dodge this
because their carets land on `bound` value leaves or collection children.

## Symptoms (light-path BFS, `using Projectured, ProjecturedExample`)

| example | text-nav (before) | text-nav (after) | tree-nav (before) | tree-nav (after) |
|---|---|---|---|---|
| json | 382 | 382 | 49 | 49 |
| syntax | 84 | 84 | 21 | 21 |
| sql_syntax | 29 | 29 | 3 | 3 |
| xml | 978 | 978 | 3 | **118** |
| **julia** | **2** | **69** | **1** | **28** |

All runs report **0 errors**. Established-good baselines (json / syntax / sql)
are byte-for-byte unchanged — the non-regression evidence. Julia rose to full
syntax-tree coverage (text 69, tree 28). xml tree-nav also rose 3 → 118 as a
side effect: xml's `<tag …>` header is a `SubNodeSlot` too, so fixes #2/#3 make
its structural navigation complete (0 errors — validate in the full suite).

## Fixes

### 1. Text nav — forward-map introduced-token carets on fixed/conditional nodes
`ProjectionTemplate.jl`: `_slots_forward` (shared by `_fixed_forward` /
`_conditional_forward`) was missing the `ProjectionReference(^(p), …)` unwrap
clause that `_node_forward` / `_mixed_forward` / `_inline_forward` all have — so a
caret on an introduced token of a fixed-children node forward-mapped to `nothing`
(selection → nothing → no caret → dead arrows). Added `_own_introduced(p, ref)`
and short-circuit it in both `_fixed_forward` and `_conditional_forward`
(keep the reference wrapped forward; `SyntaxToText._syntax_to_flat` renders a
`ProjectionReference` transparently). **Done — julia text-nav 2 → 69, no regression.**

### 2. Tree nav — introduced grouping sub-node is a distinct structural position
`ProjectionTemplate.jl`: `_slots_backward` SubNodeSlot branch mapped a
**whole-element** selection of an introduced grouping sub-node (∅ `leaf_path`) by
delegating, which collapsed it to the whole parent (∅) — colliding with the root
and stalling `Alt+Down` at step 1. Now a whole introduced sub-node backward-maps
to `ProjectionReference(p, .children[k])` (an opaque structural position); a deeper
selection still delegates (may resolve to a real `project(:f)` child). The
reader's existing `nothing`→`ProjectionReference(p, op.path)` fallback (`projection_read`
line ~1285) then covers the introduced *leaves* inside the sub-node.

### 3. Tree nav — `_tree_navigate` must read a wrapped current selection
`document/Syntax.jl`: `_tree_navigate` / `_is_tree_selection` only understood
`EmptyReferencePath` or a `.children[i]` head, so once the current selection was
`ProjectionReference(p, .children[i])` (fix #2) they returned `nothing` and
navigation couldn't leave the header. Added `_unwrap_projection_ref` (unwrap a
leading `ProjectionReference` to its `output_path`; no-op for native SyntaxNode
selections) at the top of both. The navigated result is a plain `.children[i]…`
path that re-wraps downstream via fix #2 / the reader fallback.

## Out of scope (per user)
- **LineNumbering**: independently drops the caret (`projection_print` hardcodes
  output `.selection = Cell(nothing)`, no `map_reference_forward`). Left as-is — it
  will be reworked from a Text→Text to a graphics projection. Removed the (already
  commented-out) `LineNumbering()` stage from `make_julia_projection_example`.
- **Char-descent into opaque Julia leaves** (the documented "28 unreached `name{k}`
  carets"): still deferred — Julia leaves carry no `bound(…)` marker.

## Verification
- Light-path BFS (above) — run here, safe (no native stack).
- Authoritative full suite (native stack — hand to user, external terminal):
  `test_printer/reader/repl(julia_example)`, `test_text_navigation`/`test_tree_navigation`
  for julia + json + xml + syntax + sql, and `test_json_to_syntax` / `test_xml_to_syntax`
  / `test_syntax` to guard the shared template-engine + Syntax.jl changes.
