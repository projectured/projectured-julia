# The simplest syntax document: optional delimiters, then real wrapper projections

Goal: **every domain→syntax projection emits the simplest syntax document that expresses what it
means** — a JSON null is one span, not three; a Julia connector node says "concatenate these", not
"a node with three empty delimiters". Today neither is possible, and the cost is measurable.

## The problem

**42.7% of every text span in the corpus is empty** — 1319 of 3088. Measured by flattening each
example's pipeline to its `TextText` and counting zero-length `TextString`s:

| example | spans | empty | | example | spans | empty |
|---|---|---|---|---|---|---|
| sql_syntax | 37 | 25 (67.6%) | | markdown | 129 | 73 (56.6%) |
| json_null | 3 | 2 (66.7%) | | navigator | 351 | 180 (51.3%) |
| julia | 105 | 65 (61.9%) | | filesystem | 354 | 180 (50.8%) |
| sql_update_syntax | 49 | 30 (61.2%) | | sql_insert_syntax | 37 | 18 (48.6%) |
| sql_nested_syntax | 205 | 123 (60.0%) | | xml | 535 | 248 (46.4%) |
| yaml | 211 | 120 (56.9%) | | object | 123 | 57 (46.3%) |
| formula | 109 | 62 (56.9%) | | syntax | 86 | 29 (33.7%) |
| | | | | **corpus** | **3088** | **1319 (42.7%)** |

These spans render nothing. They exist because a syntax document always *materializes* every
delimiter, present or not:

- `SyntaxLeaf`'s `open`/`close` default to `TextString("")`
  ([Syntax.jl:247](../../package/visual/main/syntax/Syntax.jl#L247)), and `SyntaxLeafToText`
  unconditionally emits three spans, `[leaf.open, leaf.value, leaf.close]`.
- `SyntaxNode`'s `open`/`close`/`sep` default the same way, and `SyntaxNodeToText` pushes `node.open`,
  a `node.sep` between children, and `node.close` regardless of content.

So `JsonNullToSyntaxLeaf` — `SyntaxLeaf(TextString("null", prj.style))`, no delimiters — becomes
**three** spans, two empty.

The cost: **phantom carets** (a leaf with no delimiter still offers `.open{0}` / `.close{0}` cursor
positions that render exactly where the value's edge renders), **wasted work** (every empty span is a
reactive cell, an iomap entry, a layout element), and **a navigation bug** — see
[left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md), which also
records why the tempting fix (skip empty spans in the steppers) is wrong: an undelimited leaf's empty
`.close` is currently a *real* caret, and `json_null`'s end-of-text position IS that empty span.
Removing the delimiter removes the caret honestly, which the stepper hack could not.

## The two ends of one problem

`Syntax.jl` declares six wrapper types — `SyntaxDelimitation`, `SyntaxIndentation`,
`SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` — describing a
compositional model where each projection assembles exactly the structure it needs. None has a
`print_document`, a `render`, or a reference map, so none is constructible. **They are not dead
weight: they are the model the domains are hand-rolling.** From an inventory of all ~340 construction
sites:

- **`SyntaxConcatenation`** — `JuliaToSyntax` builds 19 connector nodes as literally
  `SyntaxNode(TextString(""), TextString(""), TextString(""), [...], 0, false, nothing)`: no
  delimiters, no separator, purely to sequence a fixed child list (`JuliaBinaryOp` L143, `JuliaIf`
  L474/475, `JuliaFunction` L494/495, …). `SqlWhereFilterConditionToSyntaxNode` (L768) is a
  one-child, no-delimiter node — an identity wrapper. `MarkdownStyledInline` (L368) omits all three.
- **`SyntaxSeparation`** — Markdown sets `sep=TextString("")` on five inline/paragraph types
  (L128, 138, 148, 157, 368) just to join runs; SQL's `_comma_node` / `_space_node` (L71-74) pass
  bare `""` open/close with only a real `sep`.
- **`SyntaxIndentation`** — zero uses, yet every domain sets `indentation=` as an inline field on the
  node it is already building (`JsonArray` 1, `FileSystemDirectory` body 2, `DbCatalog` −1,
  `YamlMapping` −1, `JuliaBlock` 1, SQL `_comma_body` 1 / `_newline_body_compact` −1).
- **`SyntaxDelimitation`** — all six SQL helpers (L66-83) pass bare `""` for open/close.

The fat types force every node to carry delimiter slots, so "I need no delimiter" gets written as an
empty string instead of as *absence*. That is the same fact as the 42.7%.

## Target model

`SyntaxNodeToText` today does **five jobs at once**. The six wrappers are exactly those five jobs,
separated — so Phase 2 is a **factoring of existing code**, not new duplication:

| wrapper | the job it takes over from `SyntaxNodeToText` | reference steps it owns |
|---|---|---|
| `SyntaxConcatenation` | splicing children's spans into one element list (`child_elem_ranges`) | `.children[i].^(inner)` |
| `SyntaxSeparation` | the same, plus a separator span *between* children (n−1 of them) | `.children[i].^(inner)`, `.separator{k}` |
| `SyntaxDelimitation` | the open / close spans around content | `.opening_delimiter{k}`, `.content.^(inner)`, `.closing_delimiter{k}` |
| `SyntaxIndentation` | newline + indent chrome, `indent_indices`, the splice-widening machinery | `.content.^(inner)` |
| `SyntaxCollapsible` | the expand/collapse marker span, the ellipsis, `marker_eligible`, `ToggleCollapseOperation`, marker click hit-testing | `.content.^(inner)` |
| `SyntaxNavigation` | the whole-element (`∅`) tree-selection anchor | `.content.^(inner)` |

End state: `SyntaxLeaf` carries a value, `SyntaxNode` carries children, and everything else is applied
only where it is meant. `JsonNull` → one span. Julia's connectors → `SyntaxConcatenation(children)`.

## Phase 1 — optional delimiters on the fat types

Contained, unblocks navigation, needs no domain edits. **Absence must be representable before it can
be factored into a wrapper**, so this comes first either way.

```julia
@document struct SyntaxLeaf <: SyntaxDocument
    open::Union{TextString,Nothing}      # was TextString, defaulted to TextString("")
    close::Union{TextString,Nothing}
    value::TextString
    indentation::Int
    collapsed::Bool
end
SyntaxLeaf(value; open=nothing, close=nothing, …)
```

…and the same for `SyntaxNode`'s `open` / `close` / `sep`. The printer then emits only what exists:

```julia
spans = TextDocument[s for s in (leaf.open, leaf.value, leaf.close) if s !== nothing]
```

### 1.1 — Audit the fixed-layout assumptions

Before changing anything, list everything that assumes a fixed leaf/node span layout, and record the
list here. Known: `SyntaxLeafToText` hardcodes `span_idx == 1 → .open`, `2 → .value`, `3 → .close` in
both reference maps — **on a bare leaf, index 1 becomes `.value`**. Also `_leaf_cursor`,
`_flat_to_text_elem_path`, `marker_index`, `child_elem_ranges`, `render`, `splice_value!`.

### 1.2 — `Syntax.jl`: optional delimiter fields

Field types to `Union{TextString,Nothing}`; keyword constructors default to `nothing`; positional
constructors unchanged. `render` skips an absent delimiter.

### 1.3 — `SyntaxLeafToText`: emit only the spans that exist

Dynamic span list. Forward map `.open{k}` / `.close{k}` → the right index, or **decline** when that
delimiter does not exist. Backward map: index → the right field.

### 1.4 — `SyntaxNodeToText`: same for `open` / `close` / `sep`

Skip absent delimiters when assembling `elements`; keep `child_elem_ranges`, `indent_indices` and
`marker_index` consistent with the now-shorter element list.

### 1.5 — Sweep the domains

Drop explicitly-passed empty delimiters (`open=""`); fix anything relying on a bare leaf having three
spans or an `.open{0}` caret.

### 1.6 — Re-baseline

Caret counts *will* drop — that is the point. `json_null`: 3 spans → 1, and its rightward walk should
now end at `.value{4}`, exactly where Ctrl+End lands, so `right_reaches_end` / `left_reaches_start`
should agree by construction. Re-measure `NAV_LEFT_WALK_STALLS` / `NAV_RIGHT_WALK_MISSES_END` in
[ExampleSweeps.jl](../../package/projectured/test/editor/ExampleSweeps.jl); do not guess.

## Phase 2 — printers and readers for the six wrapper types

Make the wrappers real. Each gets the full projection surface, following the shape of
`SyntaxLeafToText` / `SyntaxNodeToText`:

1. a `<Type>ToText <: Projection` struct, carrying the config that type needs (e.g.
   `SyntaxIndentationToText` takes `indent_size`; `SyntaxCollapsibleToText` takes `expanded_marker` /
   `collapsed_marker` / `marker_eligible` / `ellipsis_text`);
2. an IoMap. The single-child wrappers (`Delimitation`, `Indentation`, `Collapsible`, `Navigation`)
   need a `child_iomap` plus the element range the child occupies; the multi-child ones
   (`Concatenation`, `Separation`) need `child_iomaps` + `child_elem_ranges` + `indent_indices` —
   i.e. the existing `SyntaxNodeToTextIoMap` shape
   ([SyntaxToText.jl:155](../../package/visual/main/syntax/SyntaxToText.jl#L155));
3. `print_document` — splice the child's `output.elements`, adding only this wrapper's own spans;
4. `map_reference_forward` / `map_reference_backward` — peel the one step this wrapper owns and
   delegate the tail to the child's mapper (School A: delegate through the child's IO map, never
   re-walk by document type);
5. `read_intent` for `ReplaceSelectionOperation` (delegate) and `ReplaceStringRangeOperation` (edits
   to this wrapper's own delimiter/separator spans); for `SyntaxCollapsible` also
   `ToggleCollapseOperation` and the 4-arg geometric reader for marker clicks;
6. `render` in `Syntax.jl`;
7. registration in the `SyntaxToText` `TypeDispatchingProjection`
   ([SyntaxToText.jl:818](../../package/visual/main/syntax/SyntaxToText.jl#L818)).

Do them in dependency order, one commit each, each with its own tests:

- **2.1 `SyntaxConcatenation`** — the core splice. **Extract** the child-splicing loop out of
  `SyntaxNodeToText` into a shared helper both use; do not copy it.
- **2.2 `SyntaxSeparation`** — concatenation plus separator spans between children.
- **2.3 `SyntaxDelimitation`** — open/close spans around a single child. **Its delimiters should be
  required, not defaulted to `TextString("")`**: a document with no delimiter simply is not wrapped.
  (One-sided delimitation, via `nothing` on one side, is fine.)
- **2.4 `SyntaxIndentation`** — the newline/indent chrome and the `indent_indices` + splice-widening
  machinery, lifted wholesale out of `SyntaxNodeToText`. **This is where the width-0 indent slot
  lives**, so the deferred indent-slot problem becomes localized to one projection.
- **2.5 `SyntaxCollapsible`** — the marker span, ellipsis, `marker_eligible`,
  `ToggleCollapseOperation` and the marker-click hit-testing, lifted out of `SyntaxNodeToText`.
- **2.6 `SyntaxNavigation`** — the `∅` whole-element anchor.

### Design decisions to settle in Phase 2 — do not skip these

- **Reference depth.** Every wrapper adds a `.content` hop, so a wrapped node's paths get longer.
  Check the impact on `strip_reference_types`, `@reference_case` patterns, and above all tree
  navigation: `_is_tree_selection` / `_promote_to_structural` / `_descend_to_text_cursor`
  ([Syntax.jl:426-561](../../package/visual/main/syntax/Syntax.jl#L426-L561)) walk chains of
  `.children[i]` steps and must hop transparently over wrapper `.content` steps. `@gestures
  SyntaxNode` ([Syntax.jl:394](../../package/visual/main/syntax/Syntax.jl#L394)) is registered on
  `SyntaxNode` — decide whether tree navigation moves to `SyntaxNavigation` or the gesture table
  follows the content.
- **Collapse semantics.** `ToggleCollapseOperation` carries a `SyntaxNode` today. If collapse moves
  to `SyntaxCollapsible`, the operation and the collapse-lives-at-the-syntax-layer behaviour follow
  it.
- **Layering cost.** Each wrapper is another projection layer per node — more iomaps, more cells.
  `PrinterLocalityTest` is the guard; watch it for reconciliation loss.

## Phase 3 — migrate the domains to the simplest document

One domain per commit, easiest first, re-baselining each time. The inventory gives the work-list:

- **Julia** — 19 connector nodes → `SyntaxConcatenation`; `JuliaBlock`'s `indentation=1` →
  `SyntaxIndentation`. The biggest single win (61.9% of julia's spans are empty).
- **SQL** — the six helpers: `_kw` → bare leaf; `_space_node` / `_comma_node` → `SyntaxSeparation`;
  `_comma_body` / `_newline_body` / `_newline_body_compact` → `SyntaxSeparation` +
  `SyntaxIndentation`. 16 of 22 node rules drop their empty delimiters.
- **Markdown** — the five `sep=""` types → `SyntaxConcatenation`.
- **JSON / YAML / XML** — entry nodes with explicit `TextString("")` open/close → `SyntaxSeparation`;
  array/object `indentation=` → `SyntaxIndentation`.
- The rest: object, book, conversation, filesystem, dbcatalog, formula, math, gesturemap.

## Phase 4 — (optional, later) shed the fat fields

Once every domain is migrated, `SyntaxLeaf` can lose `open` / `close` / `indentation` / `collapsed`,
and `SyntaxNode` can lose `open` / `close` / `sep` / `indentation` / `collapsed` — at which point
`SyntaxNode` *is* `SyntaxConcatenation`, and one of the two goes away. Do not attempt before Phase 3
is complete.

## Guard rails

These must not regress at any point:

- `test_text_nav_invariants_all()` — baseline 219 pass / 34 broken. Improvements expected; regressions
  are not.
- `test_typeins()` — 1187 pass / 23 broken. Typing must still work everywhere it does today.
- `test_table_navigation()` — 63 pass / 0 fail / 1 error / 1 broken.
- `test_click_roundtrips()` — 26 / 1 / 6.
- `PrinterLocalityTest` — the reactive-reuse guard; wrapper layers must not break reconciliation.

## Deferred

- **The width-0 indent slot.** `SyntaxToText` emits an empty `TextString` before each close so
  ancestors always have a slot to widen and element counts do not depend on depth
  ([SyntaxToText.jl:479-486](../../package/visual/main/syntax/SyntaxToText.jl#L479-L486)). Optional
  delimiters do **not** remove it, and it is the remaining source of the left-motion stall. Phase 2.4
  localizes it to `SyntaxIndentationToText`; the fix lands with the text-selection work below.
- **A text-domain reference step that ignores spans.** The span-boundary duplicate — one visual caret,
  two valid paths, `(span, len)` and `(span+1, 0)` — is baked into today's `.elements[i].content{k}`
  representation, and both the cursor steppers and the click round-trip work around it. A reference
  step addressing a *flat character offset* instead would make the duplicate unrepresentable. That is
  the real fix for the caret model; this plan stops manufacturing spans that should never have
  existed.
- **`SyntaxInsertion`** is also unconstructed and has no printer. It is not one of the six; decide
  separately whether it belongs with the insertion machinery (`DocumentInsertionToSyntaxModule`) or
  should be retired.
