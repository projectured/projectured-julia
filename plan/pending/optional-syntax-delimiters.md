# Optional delimiters: let each projection use the simplest syntax document it needs

## The problem

**42.7% of every text span in the corpus is empty.** Measured by flattening each example's pipeline
to its `TextText` and counting zero-length `TextString`s:

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

- `SyntaxLeaf`'s `open` / `close` default to `TextString("")`
  ([Syntax.jl:247](../../package/visual/main/syntax/Syntax.jl#L247)), and `SyntaxLeafToText`
  unconditionally emits three spans, `[leaf.open, leaf.value, leaf.close]`.
- `SyntaxNode`'s `open` / `close` / `sep` default the same way, and `SyntaxNodeToText` pushes
  `node.open`, a `node.sep` between children, and `node.close` regardless of content.

So `JsonNullToSyntaxLeaf` — `SyntaxLeaf(TextString("null", prj.style))`, no delimiters — becomes
**three** spans, two of them empty. Only `JsonStringToSyntaxLeaf` (quotes), the XML tag leaves, and a
handful of others actually carry delimiters.

### What the empty spans cost

1. **Phantom carets.** A leaf with no delimiter still offers `.open{0}` and `.close{0}` cursor
   positions that render in the same place as the value's edge. They are not typeable in any
   meaningful sense; they just duplicate a caret.
2. **A navigation bug.** One class of empty span (the width-0 indent slot) makes leftward cursor
   motion stall on *every* syntax-backed document — see
   [left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md), which also
   records why the tempting fix (skip empty spans in the steppers) is wrong: an undelimited leaf's
   empty `.close` is currently a *real* caret, and `json_null`'s end-of-text position IS that empty
   span. Removing the delimiter removes the caret honestly, which the stepper hack could not.
3. **Wasted work.** Every empty span is a reactive cell, an iomap entry, and a layout element.

### The wrapper types are not dead weight — they are the model being hand-rolled

The Syntax domain declares six wrapper types — `SyntaxDelimitation`, `SyntaxIndentation`,
`SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` — that describe a
compositional model in which each projection assembles exactly the structure it needs. None is
currently *constructible in practice*: they have no `print_document`, no `render`, and no reference
mapping, and no projection imports them.

But a full inventory of all ~340 syntax construction sites shows the domains are **reimplementing
them ad hoc on top of the fat types**:

- **`SyntaxConcatenation`** — `JuliaToSyntax` builds 19 "connector" nodes as literally
  `SyntaxNode(TextString(""), TextString(""), TextString(""), [...])`: no delimiters, no separator,
  purely to sequence a fixed child list (`JuliaBinaryOp` L143, `JuliaIf` L474/475, `JuliaFunction`
  L494/495, …). `SqlWhereFilterConditionToSyntaxNode` (L768) is a one-child, no-delimiter node — an
  identity wrapper. `MarkdownStyledInline` (L368) omits all three.
- **`SyntaxSeparation`** — Markdown sets `sep=TextString("")` on five inline/paragraph types
  (L128, 138, 148, 157, 368) just to join runs; SQL's `_comma_node` / `_space_node` helpers (L71-74)
  pass bare `""` open/close with only a real `sep`.
- **`SyntaxIndentation`** — zero uses, yet every domain sets `indentation=` as an inline field on the
  node it is already constructing (`JsonArray` 1, `FileSystemDirectory` body 2, `DbCatalog` −1,
  `YamlMapping` `prj.indent` −1, `JuliaBlock` 1, SQL `_comma_body` 1 / `_newline_body_compact` −1).
- **`SyntaxDelimitation`** — the SQL helpers, all six of them (L66-83), pass bare `""` for open/close.

So the empty-delimiter problem and the unused-wrapper problem are the *same* problem seen from two
ends: the fat types force every node to carry delimiter slots, so "I need no delimiters" is expressed
as an empty string rather than as absence.

**Decided: keep all six types.** Reviving them properly (leaf = value only; delimiters, indentation,
collapse, separation as wrappers) is the purest answer to "the simplest document required", but it
means teaching `SyntaxToText` six more types, rewriting every domain projection, and adding a
`.content` hop to every reference path — deeper paths, for a selection model that is already the hard
part. That is a separate, larger plan. This plan does the contained half: stop *materializing* what
is not there. It moves the code toward the wrapper model rather than away from it — a bare
`SyntaxNode` with no delimiters becomes, structurally, a concatenation.

## The design

Make the delimiters genuinely optional, and have the printer emit a span only for a delimiter that
exists.

```julia
@document struct SyntaxLeaf <: SyntaxDocument
    open::Union{TextString,Nothing}      # was TextString, defaulted to TextString("")
    close::Union{TextString,Nothing}
    value::TextString
    indentation::Int
    collapsed::Bool
end

SyntaxLeaf(value; open=nothing, close=nothing, …)    # was open=TextString("")
```

…and the same for `SyntaxNode`'s `open` / `close` / `sep`. Then:

```julia
# SyntaxLeafToText
spans = TextDocument[s for s in (leaf.open, leaf.value, leaf.close) if s !== nothing]
```

`JsonNull` → one span. `JsonString` → three, unchanged. Nothing in the domain projections has to
change to get this: they already *don't* pass delimiters; they only inherit them from the default.

The consequence that needs care: **span indices stop being static.** `SyntaxLeafToText`'s reference
maps currently hardcode `span_idx == 1 → .open`, `2 → .value`, `3 → .close`. With optional
delimiters, index 1 is `.value` on a bare leaf. Both maps must derive the index from which
delimiters are present, and `.open{k}` / `.close{k}` must map to *nothing* (decline) when that
delimiter does not exist, rather than address a span that isn't there.

## Steps

Work in a worktree; one commit per step.

### 1 — Audit the assumptions

Find everything that assumes a fixed leaf/node span layout, before changing anything:
`_leaf_cursor`, `_flat_to_text_elem_path`, `span_idx == 1/2/3`, `marker_index`,
`child_elem_ranges`, and any `render` / `splice_value!` path over `open`/`close`/`sep`. Write the
list into this plan — the fix is only as good as this audit.

### 2 — `Syntax.jl`: optional delimiter fields

Field types to `Union{TextString,Nothing}`, keyword constructors default to `nothing`, positional
constructors unchanged (they pass explicit delimiters). `render` skips a `nothing` delimiter.

### 3 — `SyntaxLeafToText`: emit only the spans that exist

Dynamic span list; forward map `.open{k}` / `.close{k}` → the right index, or decline when absent;
backward map index → the right field. `_leaf_cursor` / `_flat_to_text_elem_path` over the present
spans only.

### 4 — `SyntaxNodeToText`: same for `open` / `close` / `sep`

Skip an absent delimiter when assembling `elements`; keep `child_elem_ranges`, `indent_indices` and
`marker_index` consistent with the (now shorter) element list.

### 5 — Sweep the domain projections

Drop any explicitly-passed empty delimiter (`open=""`), and fix anything that relied on a bare leaf
having three spans or an `.open{0}` caret.

### 6 — Re-baseline the tests

Caret counts *will* drop — that is the point, the phantom carets are gone. Expect:

- `json_null`: 3 spans → 1; its rightward walk should now end at `.value{4}`, which is exactly where
  Ctrl+End lands, so `right_reaches_end` / `left_reaches_start` should agree by construction.
- `test_position_navigations` state counts drop across the board.
- `NAV_LEFT_WALK_STALLS` / `NAV_RIGHT_WALK_MISSES_END` in
  [ExampleSweeps.jl](../../package/projectured/test/editor/ExampleSweeps.jl) may shrink — re-measure,
  do not guess.

Guard rails (these must not regress):

- `test_table_navigation()` stays at 63 pass / 0 fail / 1 error / 1 broken.
- `test_typeins()` stays at 1187 pass / 23 broken — typing must still work everywhere it did.
- `test_click_roundtrips()` stays at 26/1/6.

### 7 — Leave the wrapper types alone

`SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`,
`SyntaxConcatenation`, `SyntaxSeparation` **stay**. They are not to be deleted. They are the
compositional model the domains are currently hand-rolling (see above), and the target of the
follow-up plan below. The only change here is a comment in `Syntax.jl` recording that status, so the
next reader does not mistake "unused" for "unwanted".

## Deferred

- **The compositional wrapper model.** The natural end state: `SyntaxLeaf` carries a value and
  nothing else, `SyntaxNode` carries children and nothing else, and `SyntaxDelimitation` /
  `SyntaxIndentation` / `SyntaxCollapsible` / `SyntaxSeparation` / `SyntaxConcatenation` /
  `SyntaxNavigation` are applied only where a projection actually needs them — so JSON's null is one
  leaf, and Julia's 19 connector nodes say `SyntaxConcatenation(children)` instead of
  `SyntaxNode(TextString(""), TextString(""), TextString(""), children, 0, false, nothing)`. Blocked
  on: `SyntaxToText` printers/readers for six more types, and a reference model that tolerates a
  `.content` hop per wrapper. Optional delimiters (this plan) is the step that makes the fat types
  *behave* like the thin ones, and is a prerequisite either way — absence has to be representable
  before it can be factored out.

- **A value-only leaf.** The inventory found the fully-undelimited leaves are the overwhelming
  majority: every Julia identifier/keyword/operator token, every SQL keyword (`_kw`), JSON
  null/bool/number, all four YAML scalars, `PrimitiveBool`/`PrimitiveNumber`, `MathVariable`,
  `NothingToSyntaxLeaf`, the filesystem/dbcatalog/book/gesturemap leaves. Delimited leaves are the
  exception: JSON strings and keys, XML tags and attribute values, Julia strings/chars/symbols,
  Markdown code/link/image, SQL's parenthesized AND/OR/NOT. Once delimiters are optional this
  distinction is visible in the data, which is what a value-only type would formalize.

- **The width-0 indent slot.** `SyntaxToText` emits an empty `TextString` before each close delimiter
  so ancestors always have a slot to widen and element counts do not depend on depth
  ([SyntaxToText.jl:479-486](../../package/visual/main/syntax/SyntaxToText.jl#L479-L486)). Optional
  delimiters do **not** remove it, and it is the remaining source of the left-motion stall. Decided:
  handle it together with the text-selection work below, where a caret model that does not key on
  span identity makes a chrome slot harmless.
- **Text-domain reference step that ignores spans.** The span-boundary duplicate (one visual caret,
  two valid paths — `(span, len)` and `(span+1, 0)`) is baked into today's `.elements[i].content{k}`
  representation, and both the left/right steppers and the click round-trip have to work around it. A
  text-domain reference step addressing a *flat character offset* rather than a span+offset would
  make the duplicate unrepresentable. This is the real fix for the caret model; the present plan just
  stops manufacturing spans that should never have existed.
